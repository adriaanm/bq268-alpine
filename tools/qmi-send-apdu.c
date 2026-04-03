/*
 * qmi-send-apdu — Send APDUs via QMI UIM over AF_MSM_IPC
 *
 * Minimal QMI client that opens a logical channel (with short AID to
 * bypass ISD-R filter) and sends APDUs directly. Avoids the libqmi
 * dependency for testing different QMI message formats.
 *
 * Cross-compile:
 *   ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc \
 *       -static -O2 -o tools/qmi-send-apdu tools/qmi-send-apdu.c
 *
 * Usage:
 *   ./qmi-send-apdu open AID_HEX      Open logical channel
 *   ./qmi-send-apdu apdu CH APDU_HEX  Send APDU on channel
 *   ./qmi-send-apdu close CH           Close logical channel
 */

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <poll.h>

/* AF_MSM_IPC = 27 on MSM8909 */
#define AF_MSM_IPC 27
#define MSM_IPC_ADDR_NAME 1
#define MSM_IPC_ADDR_ID   2

struct msm_ipc_port_addr {
    uint32_t node_id;
    uint32_t port_id;
};

struct msm_ipc_port_name {
    uint32_t service;
    uint32_t instance;
};

struct msm_ipc_addr {
    unsigned char addrtype;
    union {
        struct msm_ipc_port_addr port_addr;
        struct msm_ipc_port_name port_name;
    } addr;
};

struct sockaddr_msm_ipc {
    unsigned short family;
    struct msm_ipc_addr address;
    unsigned char reserved;
};

/*
 * QMI service message format — no QMUX framing on msmipc.
 * libqmi sends raw service headers directly on the connected socket.
 */
struct __attribute__((packed)) qmi_svc_hdr {
    uint8_t  flags;       /* 0x00 request, 0x02 response, 0x04 indication */
    uint16_t transaction; /* incrementing, LE */
    uint16_t message_id;  /* LE */
    uint16_t tlv_length;  /* LE */
};

/* QMI CTL service for allocating UIM client */
#define QMI_CTL_ALLOCATE_CID  0x0022
#define QMI_CTL_RELEASE_CID   0x0023
#define QMI_SVC_UIM           0x0B

/* QMI UIM messages */
#define QMI_UIM_OPEN_LOGICAL_CHANNEL  0x0042
#define QMI_UIM_CLOSE_LOGICAL_CHANNEL 0x003F
#define QMI_UIM_SEND_APDU            0x003B

static int uim_fd = -1;
static uint16_t txn_id = 1;
static uint8_t uim_client_id = 1;  /* locally assigned, not from CTL */

/* UIM service: node 0, port 39 (found from qmicli verbose output) */
static uint32_t uim_node = 0;
static uint32_t uim_port = 39;

static int hex_to_bytes(const char *hex, uint8_t *out, int max_len)
{
    int len = 0;
    while (*hex && len < max_len) {
        while (*hex == ' ' || *hex == ':')
            hex++;
        if (!*hex) break;
        char byte_str[3] = { hex[0], hex[1] ? hex[1] : '\0', '\0' };
        out[len++] = (uint8_t)strtol(byte_str, NULL, 16);
        hex += byte_str[1] ? 2 : 1;
    }
    return len;
}

static void hex_dump(const char *label, const uint8_t *data, int len)
{
    fprintf(stderr, "%s (%d bytes):", label, len);
    for (int i = 0; i < len && i < 64; i++)
        fprintf(stderr, " %02x", data[i]);
    if (len > 64) fprintf(stderr, " ...");
    fprintf(stderr, "\n");
}

static int msmipc_connect(void)
{
    uim_fd = socket(AF_MSM_IPC, SOCK_DGRAM, 0);
    if (uim_fd < 0) {
        perror("socket(AF_MSM_IPC)");
        return -1;
    }

    struct sockaddr_msm_ipc addr;
    memset(&addr, 0, sizeof(addr));
    addr.family = AF_MSM_IPC;
    addr.address.addrtype = MSM_IPC_ADDR_ID;
    addr.address.addr.port_addr.node_id = uim_node;
    addr.address.addr.port_addr.port_id = uim_port;

    if (connect(uim_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("connect to UIM service");
        close(uim_fd);
        return -1;
    }

    fprintf(stderr, "Connected to UIM service (node=%u, port=%u)\n", uim_node, uim_port);
    return 0;
}

static int qmi_send(uint16_t msg_id, const uint8_t *tlvs, int tlv_len)
{
    uint8_t buf[4096];
    struct qmi_svc_hdr *hdr = (void *)buf;

    hdr->flags = 0x00;      /* request */
    hdr->transaction = txn_id++;
    hdr->message_id = msg_id;
    hdr->tlv_length = tlv_len;

    if (tlv_len > 0)
        memcpy(buf + sizeof(*hdr), tlvs, tlv_len);

    int total = sizeof(*hdr) + tlv_len;

    hex_dump("  TX", buf, total);

    ssize_t ret = send(uim_fd, buf, total, 0);
    if (ret < 0) {
        perror("send");
        return -1;
    }
    return 0;
}

static int qmi_recv(uint8_t *buf, int max_len, int timeout_ms)
{
    struct pollfd pfd = { .fd = uim_fd, .events = POLLIN };
    int ret = poll(&pfd, 1, timeout_ms);
    if (ret <= 0) return -1;

    ssize_t n = recv(uim_fd, buf, max_len, 0);
    return (int)n;
}

/* TLV offset: skip service header to get to TLVs */
#define TLV_START sizeof(struct qmi_svc_hdr)

/* Find Result TLV (0x02) and check success */
static int qmi_check_result(const uint8_t *buf, int len, const char *op)
{
    int off = TLV_START;
    while (off + 3 < len) {
        uint8_t tlv_type = buf[off];
        uint16_t tlv_len = *(uint16_t *)(buf + off + 1);
        if (tlv_type == 0x02 && tlv_len >= 4) {
            uint16_t result = *(uint16_t *)(buf + off + 3);
            uint16_t error = *(uint16_t *)(buf + off + 5);
            if (result != 0) {
                fprintf(stderr, "%s: FAILED (QMI error=%d)\n", op, error);
                return -1;
            }
            return 0;
        }
        off += 3 + tlv_len;
    }
    fprintf(stderr, "%s: no result TLV in %d bytes\n", op, len);
    return -1;
}

/* Find a specific TLV and return pointer to its data */
static const uint8_t *qmi_find_tlv(const uint8_t *buf, int len,
                                    uint8_t type, int *out_len)
{
    int off = TLV_START;
    while (off + 3 < len) {
        uint8_t tlv_type = buf[off];
        uint16_t tlv_len = *(uint16_t *)(buf + off + 1);
        if (tlv_type == type) {
            *out_len = tlv_len;
            return buf + off + 3;
        }
        off += 3 + tlv_len;
    }
    *out_len = 0;
    return NULL;
}

/* No CTL allocation needed — CIDs are local on msmipc */

/*
 * Open Logical Channel (QMI UIM 0x0042)
 * TLV 0x01: Slot (uint8)
 * TLV 0x10: AID (uint8 len + bytes) — optional
 */
static int cmd_open(const char *aid_hex)
{
    uint8_t tlvs[256];
    int toff = 0;

    /* TLV 0x01: Slot = 1 */
    tlvs[toff++] = 0x01;  /* type */
    tlvs[toff++] = 0x01;  /* length */
    tlvs[toff++] = 0x00;  /* length hi */
    tlvs[toff++] = 0x01;  /* slot 1 */

    /* TLV 0x10: AID (optional) */
    if (aid_hex && *aid_hex) {
        uint8_t aid[32];
        int aid_len = hex_to_bytes(aid_hex, aid, sizeof(aid));
        tlvs[toff++] = 0x10;  /* type */
        uint16_t tlv_len = 1 + aid_len;
        *(uint16_t *)(tlvs + toff) = tlv_len;
        toff += 2;
        tlvs[toff++] = (uint8_t)aid_len;
        memcpy(tlvs + toff, aid, aid_len);
        toff += aid_len;
    }

    printf("Opening logical channel (AID=%s)...\n", aid_hex ?: "none");
    if (qmi_send(QMI_UIM_OPEN_LOGICAL_CHANNEL, tlvs, toff) < 0)
        return -1;

    uint8_t rsp[512];
    int rsp_len = qmi_recv(rsp, sizeof(rsp), 10000);
    if (rsp_len < 0) {
        printf("open channel: no response\n");
        return -1;
    }

    hex_dump("  RSP", rsp, rsp_len);

    if (qmi_check_result(rsp, rsp_len, "open channel") < 0)
        return -1;

    /* Channel ID TLV (0x10) */
    int tlen;
    const uint8_t *tv = qmi_find_tlv(rsp, rsp_len, 0x10, &tlen);
    if (tv && tlen >= 1) {
        printf("Channel ID: %d\n", tv[0]);
    }

    /* Select Response TLV (0x12) */
    tv = qmi_find_tlv(rsp, rsp_len, 0x12, &tlen);
    if (tv && tlen > 0) {
        /* First byte is uint8 length */
        hex_dump("  FCI", tv + 1, tlen - 1);
    }

    /* Card Result TLV (0x11) */
    tv = qmi_find_tlv(rsp, rsp_len, 0x11, &tlen);
    if (tv && tlen >= 2) {
        printf("SW: %02X%02X\n", tv[0], tv[1]);
    }

    return 0;
}

/*
 * Send APDU (QMI UIM 0x003B)
 * Tries different TLV combinations to find what works.
 */
static int cmd_apdu(int channel, const char *apdu_hex, int include_ch_tlv)
{
    uint8_t apdu[512];
    int apdu_len = hex_to_bytes(apdu_hex, apdu, sizeof(apdu));

    uint8_t tlvs[1024];
    int toff = 0;

    /* TLV 0x01: Slot = 1 */
    tlvs[toff++] = 0x01;
    tlvs[toff++] = 0x01;
    tlvs[toff++] = 0x00;
    tlvs[toff++] = 0x01;

    /* TLV 0x02: APDU data (uint16 len + bytes) */
    tlvs[toff++] = 0x02;
    uint16_t apdu_tlv_len = 2 + apdu_len;
    *(uint16_t *)(tlvs + toff) = apdu_tlv_len;
    toff += 2;
    *(uint16_t *)(tlvs + toff) = apdu_len;
    toff += 2;
    memcpy(tlvs + toff, apdu, apdu_len);
    toff += apdu_len;

    /* TLV 0x10: Channel ID (optional) */
    if (include_ch_tlv) {
        tlvs[toff++] = 0x10;
        tlvs[toff++] = 0x01;
        tlvs[toff++] = 0x00;
        tlvs[toff++] = (uint8_t)channel;
    }

    printf("Send APDU (ch=%d, ch_tlv=%s, %d bytes)...\n",
           channel, include_ch_tlv ? "yes" : "no", apdu_len);
    hex_dump("  APDU", apdu, apdu_len);

    if (qmi_send(QMI_UIM_SEND_APDU, tlvs, toff) < 0)
        return -1;

    uint8_t rsp[4096];
    int rsp_len = qmi_recv(rsp, sizeof(rsp), 10000);
    if (rsp_len < 0) {
        printf("send APDU: no response\n");
        return -1;
    }

    hex_dump("  RSP", rsp, rsp_len);

    if (qmi_check_result(rsp, rsp_len, "send APDU") < 0) {
        /* Show full response for debugging */
        return -1;
    }

    /* APDU Response TLV (0x10) */
    int tlen;
    const uint8_t *tv = qmi_find_tlv(rsp, rsp_len, 0x10, &tlen);
    if (tv && tlen > 2) {
        hex_dump("  APDU RSP", tv + 2, tlen - 2);
    }

    /* Card Result TLV (0x11) */
    tv = qmi_find_tlv(rsp, rsp_len, 0x11, &tlen);
    if (tv && tlen >= 2) {
        printf("SW: %02X%02X\n", tv[0], tv[1]);
    }

    return 0;
}

static int cmd_close(int channel)
{
    uint8_t tlvs[16];
    int toff = 0;

    /* TLV 0x01: Slot = 1 */
    tlvs[toff++] = 0x01;
    tlvs[toff++] = 0x01;
    tlvs[toff++] = 0x00;
    tlvs[toff++] = 0x01;

    /* TLV 0x10: Channel ID */
    tlvs[toff++] = 0x10;
    tlvs[toff++] = 0x01;
    tlvs[toff++] = 0x00;
    tlvs[toff++] = (uint8_t)channel;

    printf("Closing channel %d...\n", channel);
    if (qmi_send(QMI_UIM_CLOSE_LOGICAL_CHANNEL, tlvs, toff) < 0)
        return -1;

    uint8_t rsp[256];
    int rsp_len = qmi_recv(rsp, sizeof(rsp), 5000);
    if (rsp_len < 0) return -1;
    return qmi_check_result(rsp, rsp_len, "close channel");
}

/* ISD-R AID prefix: if the requested AID starts with this, truncate to
 * 6 bytes to bypass the modem's 7-byte filter */
static const char *ISDR_PREFIX = "A0000005591010";

static const char *maybe_truncate_aid(const char *aid)
{
    static char short_aid[13]; /* "A00000055910" + NUL */
    if (aid && strlen(aid) >= 14 &&
        strncasecmp(aid, ISDR_PREFIX, 14) == 0) {
        memcpy(short_aid, aid, 12);
        short_aid[12] = '\0';
        return short_aid;
    }
    return aid;
}

/*
 * Daemon mode: read commands from stdin, write responses to stdout.
 * Protocol (line-based, for use by lpac-qmi-wrapper):
 *   OPEN [AID_HEX]        → OK channel_id [FCI_HEX] | ERR msg
 *   APDU channel APDU_HEX → OK response_hex | ERR msg
 *   CLOSE channel          → OK | ERR msg
 *
 * Automatically truncates ISD-R AIDs to bypass modem filter.
 */
static int cmd_daemon(void)
{
    char line[8192];

    fprintf(stderr, "qmi-send-apdu: daemon mode ready\n");

    while (fgets(line, sizeof(line), stdin)) {
        /* Strip newline */
        int len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r'))
            line[--len] = '\0';
        if (len == 0) continue;

        fprintf(stderr, "qmi-send-apdu: << %s\n", line);

        if (strncmp(line, "OPEN", 4) == 0) {
            const char *aid = (line[4] == ' ') ? line + 5 : NULL;
            aid = maybe_truncate_aid(aid);

            /* Build open request */
            uint8_t tlvs[256];
            int toff = 0;
            tlvs[toff++] = 0x01; tlvs[toff++] = 0x01; tlvs[toff++] = 0x00; tlvs[toff++] = 0x01;
            if (aid && *aid) {
                uint8_t aid_bytes[32];
                int aid_len = hex_to_bytes(aid, aid_bytes, sizeof(aid_bytes));
                tlvs[toff++] = 0x10;
                *(uint16_t *)(tlvs + toff) = 1 + aid_len; toff += 2;
                tlvs[toff++] = (uint8_t)aid_len;
                memcpy(tlvs + toff, aid_bytes, aid_len); toff += aid_len;
            }

            if (qmi_send(QMI_UIM_OPEN_LOGICAL_CHANNEL, tlvs, toff) < 0) {
                printf("ERR send failed\n");
                continue;
            }
            uint8_t rsp[512];
            int rsp_len = qmi_recv(rsp, sizeof(rsp), 10000);
            if (rsp_len < 0 || qmi_check_result(rsp, rsp_len, "open") < 0) {
                printf("ERR open failed\n");
                continue;
            }
            int tlen;
            const uint8_t *tv = qmi_find_tlv(rsp, rsp_len, 0x10, &tlen);
            int ch = (tv && tlen >= 1) ? tv[0] : -1;

            /* Build response: OK channel_id [FCI_hex] */
            printf("OK %d", ch);
            tv = qmi_find_tlv(rsp, rsp_len, 0x12, &tlen);
            if (tv && tlen > 1) {
                printf(" ");
                for (int i = 1; i < tlen; i++)
                    printf("%02X", tv[i]);
            }
            printf("\n");

        } else if (strncmp(line, "APDU ", 5) == 0) {
            int ch = 0;
            char apdu_hex[4096];
            if (sscanf(line + 5, "%d %s", &ch, apdu_hex) < 2) {
                printf("ERR bad format\n");
                continue;
            }

            uint8_t apdu[512];
            int apdu_len = hex_to_bytes(apdu_hex, apdu, sizeof(apdu));

            uint8_t tlvs[1024];
            int toff = 0;
            tlvs[toff++] = 0x01; tlvs[toff++] = 0x01; tlvs[toff++] = 0x00; tlvs[toff++] = 0x01;
            tlvs[toff++] = 0x02;
            *(uint16_t *)(tlvs + toff) = 2 + apdu_len; toff += 2;
            *(uint16_t *)(tlvs + toff) = apdu_len; toff += 2;
            memcpy(tlvs + toff, apdu, apdu_len); toff += apdu_len;
            tlvs[toff++] = 0x10; tlvs[toff++] = 0x01; tlvs[toff++] = 0x00;
            tlvs[toff++] = (uint8_t)ch;

            if (qmi_send(QMI_UIM_SEND_APDU, tlvs, toff) < 0) {
                printf("ERR send failed\n");
                continue;
            }
            uint8_t rsp[4096];
            int rsp_len = qmi_recv(rsp, sizeof(rsp), 10000);
            if (rsp_len < 0 || qmi_check_result(rsp, rsp_len, "apdu") < 0) {
                printf("ERR apdu failed\n");
                continue;
            }

            /* APDU response TLV (0x10): uint16 len + data */
            int tlen;
            const uint8_t *tv = qmi_find_tlv(rsp, rsp_len, 0x10, &tlen);
            if (tv && tlen > 2) {
                printf("OK ");
                for (int i = 2; i < tlen; i++)
                    printf("%02X", tv[i]);
                printf("\n");
            } else {
                printf("ERR no apdu response\n");
            }

        } else if (strncmp(line, "CLOSE ", 6) == 0) {
            int ch = atoi(line + 6);
            uint8_t tlvs[16];
            int toff = 0;
            tlvs[toff++] = 0x01; tlvs[toff++] = 0x01; tlvs[toff++] = 0x00; tlvs[toff++] = 0x01;
            tlvs[toff++] = 0x10; tlvs[toff++] = 0x01; tlvs[toff++] = 0x00; tlvs[toff++] = (uint8_t)ch;

            qmi_send(QMI_UIM_CLOSE_LOGICAL_CHANNEL, tlvs, toff);
            uint8_t rsp[256];
            qmi_recv(rsp, sizeof(rsp), 5000);
            printf("OK\n");

        } else {
            printf("ERR unknown command\n");
        }
        fflush(stdout);
    }
    return 0;
}

int main(int argc, char *argv[])
{
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    if (argc < 2) {
        fprintf(stderr,
            "Usage:\n"
            "  %s open [AID_HEX]       Open logical channel (short AID for ISD-R)\n"
            "  %s apdu CH APDU_HEX     Send APDU on channel (with channel_id TLV)\n"
            "  %s apdu0 CH APDU_HEX    Send APDU on channel (WITHOUT channel_id TLV)\n"
            "  %s close CH             Close logical channel\n"
            "  %s test                 Open ISD-R + send GET DATA for EID\n"
            "  %s daemon               Persistent mode, reads commands from stdin\n"
            "\n"
            "Examples:\n"
            "  %s open A00000055910                  # Open to ISD-R via short AID\n"
            "  %s apdu 1 81CA006F00                  # GET DATA on channel 1\n"
            "  %s test                               # Full ISD-R test sequence\n"
            "  %s daemon                             # Used by lpac-qmi-wrapper\n",
            argv[0], argv[0], argv[0], argv[0], argv[0],
            argv[0], argv[0], argv[0], argv[0], argv[0]);
        return 1;
    }

    if (msmipc_connect() < 0) return 1;

    int ret = 0;

    if (strcmp(argv[1], "daemon") == 0) {
        ret = cmd_daemon();
    } else if (strcmp(argv[1], "open") == 0) {
        ret = cmd_open(argc > 2 ? argv[2] : NULL);
    } else if (strcmp(argv[1], "apdu") == 0 && argc >= 4) {
        int ch = atoi(argv[2]);
        ret = cmd_apdu(ch, argv[3], 1);  /* with channel_id TLV */
    } else if (strcmp(argv[1], "apdu0") == 0 && argc >= 4) {
        int ch = atoi(argv[2]);
        ret = cmd_apdu(ch, argv[3], 0);  /* without channel_id TLV */
    } else if (strcmp(argv[1], "close") == 0 && argc >= 3) {
        int ch = atoi(argv[2]);
        ret = cmd_close(ch);
    } else if (strcmp(argv[1], "test") == 0) {
        /* Full eUICC test: open ISD-R, get eUICC info */
        printf("=== Opening ISD-R via short AID ===\n");
        ret = cmd_open("A00000055910");
        if (ret == 0) {
            printf("\n=== GetEuiccInfo1 (STORE DATA BF20) ===\n");
            cmd_apdu(1, "81E2910003BF2000", 1);
            printf("\n=== GET RESPONSE (56 bytes) ===\n");
            cmd_apdu(1, "01C0000038", 1);

            printf("\n=== GetEuiccChallenge (STORE DATA BF2E) ===\n");
            cmd_apdu(1, "81E2910003BF2E00", 1);
            printf("\n=== GET RESPONSE (21 bytes) ===\n");
            cmd_apdu(1, "01C0000015", 1);

            printf("\n=== GetEuiccInfo2 (STORE DATA BF22) ===\n");
            cmd_apdu(1, "81E2910003BF2200", 1);
            printf("\n=== GET RESPONSE (125 bytes) ===\n");
            cmd_apdu(1, "01C000007D", 1);

            printf("\n=== Closing channel 1 ===\n");
            cmd_close(1);
        }
    } else {
        fprintf(stderr, "Unknown command: %s\n", argv[1]);
        ret = 1;
    }

    close(uim_fd);
    return ret;
}
