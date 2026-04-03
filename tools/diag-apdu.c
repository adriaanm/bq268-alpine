/*
 * diag-apdu — Send APDUs to eUICC via DIAG subsystem, bypassing QMI UIM
 *
 * Uses DIAG subsystem dispatch to probe available SIM-related subsystems
 * (MMGSDI, UIM, GSTK) and send APDUs directly to the SIM card.
 *
 * The modem's QMI UIM service enforces APDU access restrictions (NV 67312),
 * but the DIAG interface to lower-level SIM drivers may bypass this.
 *
 * Cross-compile:
 *   ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc \
 *       -static -O2 -o diag-apdu tools/diag-apdu.c
 *
 * Usage:
 *   ./diag-apdu probe          # probe available DIAG subsystems
 *   ./diag-apdu raw SS CC HH   # send raw: subsys=SS cmd=CC data=HH...
 */

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>

/* DIAG ioctl/mode constants */
#define DIAG_IOCTL_SWITCH_LOGGING  7
#define DIAG_IOCTL_HDLC_TOGGLE    38
#define MEMORY_DEVICE_MODE  2
#define DIAG_CON_MPSS       0x0002

/* Data types for /dev/diag read/write */
#define USER_SPACE_DATA_TYPE      0x00000020
#define USER_SPACE_RAW_DATA_TYPE  0x00000080
#define PKT_TYPE                  0x00000008

/* DIAG commands */
#define DIAG_SUBSYS_CMD       0x4B
#define DIAG_SUBSYS_CMD_VER2  0x80

#define CONTROL_CHAR  0x7E

struct __attribute__((packed)) diag_logging_mode_param_t {
	uint32_t req_mode;
	uint32_t peripheral_mask;
	uint8_t  mode_param;
};

struct __attribute__((packed)) subsys_hdr {
	uint8_t  cmd_code;
	uint8_t  subsys_id;
	uint16_t subsys_cmd_code;
};

static int diag_fd = -1;

static void hex_dump(const char *label, const uint8_t *data, int len)
{
	printf("%s (%d bytes):", label, len);
	for (int i = 0; i < len; i++)
		printf(" %02x", data[i]);
	printf("\n");
}

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

static const uint8_t *strip_frame(const uint8_t *pkt, int pkt_len, int *out_len)
{
	if (pkt_len >= 5 && pkt[0] == CONTROL_CHAR && pkt[1] == 1) {
		uint16_t payload_len = *(uint16_t *)(pkt + 2);
		int total = 4 + payload_len + 1;
		if (total <= pkt_len) {
			*out_len = payload_len;
			return pkt + 4;
		}
	}
	*out_len = pkt_len;
	return pkt;
}

static int diag_send(const void *cmd, int len)
{
	uint8_t buf[4 + 4096];
	if (len > 4096) return -1;
	*(uint32_t *)buf = USER_SPACE_RAW_DATA_TYPE;
	memcpy(buf + 4, cmd, len);
	int ret = write(diag_fd, buf, 4 + len);
	return ret < 0 ? -1 : 0;
}

/*
 * Receive any DIAG response, not filtering by subsystem.
 * Returns payload length, copies to out buffer.
 */
static int diag_recv_any(uint8_t *out, int out_max, int timeout_ms)
{
	uint8_t buf[16384];
	int elapsed = 0;

	while (elapsed < timeout_ms) {
		int wait = timeout_ms - elapsed;
		if (wait > 500) wait = 500;

		struct pollfd pfd = { .fd = diag_fd, .events = POLLIN };
		int pret = poll(&pfd, 1, wait);
		elapsed += wait;
		if (pret <= 0) continue;

		ssize_t n = read(diag_fd, buf, sizeof(buf));
		if (n < 4) continue;

		int data_type = *(int *)buf;

		if (data_type == USER_SPACE_DATA_TYPE && n >= 8) {
			int num_data = *(int *)(buf + 4);
			int off = 8;
			for (int i = 0; i < num_data && off < n; i++) {
				if (off + 4 > n) break;
				int pkt_len = *(int *)(buf + off);
				off += 4;
				if (pkt_len <= 0 || off + pkt_len > n) break;
				int pl;
				const uint8_t *p = strip_frame(buf + off, pkt_len, &pl);
				if (pl > 0) {
					int cp = pl < out_max ? pl : out_max;
					memcpy(out, p, cp);
					return cp;
				}
				off += pkt_len;
			}
		}

		if (data_type == PKT_TYPE && n > 4) {
			int pl;
			const uint8_t *p = strip_frame(buf + 4, n - 4, &pl);
			if (pl > 0) {
				int cp = pl < out_max ? pl : out_max;
				memcpy(out, p, cp);
				return cp;
			}
		}
	}
	return -1;
}

static int diag_init(void)
{
	diag_fd = open("/dev/diag", O_RDWR | O_NONBLOCK);
	if (diag_fd < 0) { perror("open /dev/diag"); return -1; }

	struct diag_logging_mode_param_t param = {
		.req_mode = MEMORY_DEVICE_MODE,
		.peripheral_mask = DIAG_CON_MPSS,
		.mode_param = 0,
	};
	if (ioctl(diag_fd, DIAG_IOCTL_SWITCH_LOGGING, &param) < 0) {
		perror("ioctl SWITCH_LOGGING");
		close(diag_fd);
		return -1;
	}

	uint8_t hdlc_disable = 1;
	ioctl(diag_fd, DIAG_IOCTL_HDLC_TOGGLE, &hdlc_disable);

	usleep(100000);

	/* SPC unlock */
	uint8_t spc[7] = { 0x41, '0', '0', '0', '0', '0', '0' };
	diag_send(spc, 7);
	usleep(300000);

	/* Security password */
	uint8_t sec[9] = { 0x46 };
	diag_send(sec, 9);
	usleep(200000);

	/* Drain */
	for (int i = 0; i < 30; i++) {
		uint8_t tmp[16384];
		struct pollfd pfd = { .fd = diag_fd, .events = POLLIN };
		if (poll(&pfd, 1, 100) > 0)
			read(diag_fd, tmp, sizeof(tmp));
		else
			break;
	}

	return 0;
}

static void diag_cleanup(void)
{
	if (diag_fd >= 0) {
		struct diag_logging_mode_param_t param = {
			.req_mode = 1,
			.peripheral_mask = DIAG_CON_MPSS,
		};
		ioctl(diag_fd, DIAG_IOCTL_SWITCH_LOGGING, &param);
		close(diag_fd);
	}
}

/*
 * Probe DIAG subsystems by sending a version request (cmd_code=0)
 * to each subsystem and checking for a response.
 */
static void cmd_probe(void)
{
	/* Known QC subsystem names for SIM/modem */
	static const struct {
		int id;
		const char *name;
	} subsystems[] = {
		{ 0x03, "WCDMA" },
		{ 0x04, "GSM" },
		{ 0x06, "CM (Call Manager)" },
		{ 0x08, "GPS" },
		{ 0x0A, "NAS" },
		{ 0x0C, "UIM (legacy)" },
		{ 0x13, "EFS2" },
		{ 0x14, "NV_BROWSER" },
		{ 0x19, "MMGSDI" },
		{ 0x1E, "GSTK" },
		{ 0x2D, "QMI" },
		{ 0x32, "GSTK2" },
		{ 0x33, "UIM_SERVER" },
		{ 0x3B, "QMI_NAS" },
		{ 0x3F, "LTE" },
		{ 0x44, "UIM/MMGSDI2" },
		{ 0x48, "QMI_UIM" },
		{ 0x50, "RFS" },
		{ 0x51, "IMS" },
		{ 0 , NULL },
	};

	printf("Probing DIAG subsystems...\n\n");

	for (int i = 0; subsystems[i].name; i++) {
		uint8_t cmd[8] = {
			DIAG_SUBSYS_CMD,
			(uint8_t)subsystems[i].id,
			0x00, 0x00,  /* cmd_code = 0 */
			0x00, 0x00, 0x00, 0x00
		};

		diag_send(cmd, 8);

		uint8_t rsp[512];
		int rsp_len = diag_recv_any(rsp, sizeof(rsp), 1000);

		printf("  SS 0x%02x %-20s ", subsystems[i].id, subsystems[i].name);
		if (rsp_len < 0) {
			printf("no response\n");
		} else if (rsp_len >= 1 && (rsp[0] == 0x13 || rsp[0] == 0x14 ||
			   rsp[0] == 0x15 || rsp[0] == 0x0C || rsp[0] == 0x0D)) {
			printf("error (0x%02x)\n", rsp[0]);
		} else if (rsp_len >= 4 && rsp[0] == DIAG_SUBSYS_CMD &&
			   rsp[1] == subsystems[i].id) {
			printf("ALIVE (%d bytes)\n", rsp_len);
			hex_dump("    response", rsp, rsp_len > 32 ? 32 : rsp_len);
		} else {
			printf("unknown (%d bytes, first=0x%02x)\n", rsp_len, rsp[0]);
			hex_dump("    response", rsp, rsp_len > 32 ? 32 : rsp_len);
		}
	}
}

/*
 * DIAG PEEKD (cmd 0x36): read 32-bit word from modem memory.
 * Request: [0x36, addr_b0, addr_b1, addr_b2, addr_b3]
 * Response: [0x36, addr_b0..3, value_b0..3]
 */
static int diag_peek32(uint32_t addr, uint32_t *value)
{
	uint8_t cmd[5];
	cmd[0] = 0x36;  /* DIAG_PEEKD */
	memcpy(cmd + 1, &addr, 4);

	diag_send(cmd, 5);

	uint8_t rsp[64];
	int rsp_len = diag_recv_any(rsp, sizeof(rsp), 2000);
	if (rsp_len >= 9 && rsp[0] == 0x36) {
		memcpy(value, rsp + 5, 4);
		return 0;
	}
	if (rsp_len >= 1 && (rsp[0] == 0x13 || rsp[0] == 0x14)) {
		/* Bad command / bad parameter */
		return -2;
	}
	return -1;
}

/*
 * DIAG POKED (cmd 0x39): write 32-bit word to modem memory.
 * Request: [0x39, addr_b0..3, value_b0..3]
 * Response: [0x39, addr_b0..3, value_b0..3]
 */
static int diag_poke32(uint32_t addr, uint32_t value)
{
	uint8_t cmd[9];
	cmd[0] = 0x39;  /* DIAG_POKED */
	memcpy(cmd + 1, &addr, 4);
	memcpy(cmd + 5, &value, 4);

	diag_send(cmd, 9);

	uint8_t rsp[64];
	int rsp_len = diag_recv_any(rsp, sizeof(rsp), 2000);
	if (rsp_len >= 9 && rsp[0] == 0x39)
		return 0;
	if (rsp_len >= 1 && (rsp[0] == 0x13 || rsp[0] == 0x14))
		return -2;
	return -1;
}

static void cmd_peek(int argc, char **argv)
{
	if (argc < 3) {
		fprintf(stderr, "Usage: diag-apdu peek <addr> [count]\n"
				"  addr: hex address (e.g. 0xC2149DB0)\n"
				"  count: number of 32-bit words (default 1, max 64)\n");
		return;
	}

	uint32_t addr = (uint32_t)strtoul(argv[2], NULL, 0);
	int count = (argc > 3) ? atoi(argv[3]) : 1;
	if (count < 1) count = 1;
	if (count > 64) count = 64;

	for (int i = 0; i < count; i++) {
		uint32_t a = addr + i * 4;
		uint32_t val;
		int ret = diag_peek32(a, &val);
		if (ret == 0) {
			printf("  [0x%08X] = 0x%08X", a, val);
			/* Print ASCII if looks like a pointer or small value */
			if (val >= 0xC0000000 && val < 0xD0000000)
				printf("  (modem VA)");
			else if (val == 0xFFFFFFFE)
				printf("  (-2)");
			else if (val == 0)
				printf("  (NULL)");
			printf("\n");
		} else if (ret == -2) {
			printf("  [0x%08X] = DENIED (DIAG peek disabled)\n", a);
			return;
		} else {
			printf("  [0x%08X] = NO RESPONSE\n", a);
		}
	}
}

static void cmd_poke(int argc, char **argv)
{
	if (argc < 4) {
		fprintf(stderr, "Usage: diag-apdu poke <addr> <value>\n"
				"  addr/value: hex (e.g. 0xC2149DB4 0x00000000)\n");
		return;
	}

	uint32_t addr = (uint32_t)strtoul(argv[2], NULL, 0);
	uint32_t val = (uint32_t)strtoul(argv[3], NULL, 0);

	printf("  POKE [0x%08X] <- 0x%08X\n", addr, val);
	int ret = diag_poke32(addr, val);
	if (ret == 0)
		printf("  OK\n");
	else if (ret == -2)
		printf("  DENIED (DIAG poke disabled)\n");
	else
		printf("  NO RESPONSE\n");
}

/*
 * Send raw DIAG subsystem command.
 */
static void cmd_raw(int argc, char **argv)
{
	if (argc < 4) {
		fprintf(stderr, "Usage: diag-apdu raw <subsys_id> <cmd_code> [hex_data]\n");
		return;
	}

	uint8_t subsys_id = (uint8_t)strtol(argv[2], NULL, 0);
	uint16_t cmd_code = (uint16_t)strtol(argv[3], NULL, 0);

	uint8_t cmd[4096];
	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = subsys_id;
	*(uint16_t *)(cmd + 2) = cmd_code;
	int total = 4;

	/* Append hex data if provided */
	for (int i = 4; i < argc && total < (int)sizeof(cmd); i++) {
		total += hex_to_bytes(argv[i], cmd + total, sizeof(cmd) - total);
	}

	printf("Sending: subsys=0x%02x cmd=0x%04x (%d bytes)\n",
	       subsys_id, cmd_code, total);
	hex_dump("  TX", cmd, total);

	diag_send(cmd, total);

	uint8_t rsp[4096];
	int rsp_len = diag_recv_any(rsp, sizeof(rsp), 5000);
	if (rsp_len < 0) {
		printf("  No response\n");
	} else {
		printf("  Response (%d bytes):\n", rsp_len);
		hex_dump("  RX", rsp, rsp_len);
	}
}

int main(int argc, char *argv[])
{
	setbuf(stdout, NULL);
	setbuf(stderr, NULL);

	if (argc < 2 || strcmp(argv[1], "-h") == 0) {
		fprintf(stderr,
			"Usage:\n"
			"  %s probe                  Probe DIAG subsystems\n"
			"  %s peek ADDR [COUNT]      Read modem memory (32-bit words)\n"
			"  %s poke ADDR VALUE        Write modem memory (32-bit)\n"
			"  %s raw SS CMD [HEX]       Send raw subsystem command\n"
			"\n"
			"ADDR/VALUE/SS/CMD are hex values.\n"
			"Examples:\n"
			"  %s peek 0xC2149DB0 4      # Dump 4 words at result struct\n"
			"  %s poke 0xC2149DB4 0      # Clear result to 0\n"
			"  %s raw 0x19 0x00          # MMGSDI version query\n",
			argv[0], argv[0], argv[0], argv[0],
			argv[0], argv[0], argv[0]);
		return 0;
	}

	if (diag_init() < 0)
		return 1;

	if (strcmp(argv[1], "probe") == 0) {
		cmd_probe();
	} else if (strcmp(argv[1], "scan") == 0) {
		/* Scan all subsystem IDs 0x00-0x80 */
		printf("Scanning all DIAG subsystems 0x00-0x80...\n\n");
		for (int ss = 0; ss <= 0x80; ss++) {
			uint8_t cmd[8] = { DIAG_SUBSYS_CMD, (uint8_t)ss, 0, 0, 0, 0, 0, 0 };
			diag_send(cmd, 8);
			uint8_t rsp[512];
			int rsp_len = diag_recv_any(rsp, sizeof(rsp), 500);
			if (rsp_len >= 4 && rsp[0] == DIAG_SUBSYS_CMD && rsp[1] == ss) {
				printf("  SS 0x%02x: ALIVE (%d bytes)", ss, rsp_len);
				hex_dump("", rsp + 4, rsp_len - 4 > 16 ? 16 : rsp_len - 4);
			}
		}
		printf("\nDone.\n");
	} else if (strcmp(argv[1], "probe-ss") == 0 && argc >= 3) {
		/* Probe all commands 0x00-0x40 for a specific subsystem */
		int ss = (int)strtol(argv[2], NULL, 0);
		printf("Probing subsystem 0x%02x commands 0x00-0x40...\n\n", ss);
		for (int cmd = 0; cmd <= 0x40; cmd++) {
			uint8_t pkt[8] = { DIAG_SUBSYS_CMD, (uint8_t)ss,
				(uint8_t)(cmd & 0xff), (uint8_t)(cmd >> 8),
				0, 0, 0, 0 };
			diag_send(pkt, 8);
			uint8_t rsp[512];
			int rsp_len = diag_recv_any(rsp, sizeof(rsp), 500);
			if (rsp_len >= 4 && rsp[0] == DIAG_SUBSYS_CMD && rsp[1] == ss) {
				uint16_t rcmd = *(uint16_t *)(rsp + 2);
				printf("  cmd 0x%04x: ALIVE (%d bytes)", cmd, rsp_len);
				if (rsp_len > 4)
					hex_dump("", rsp + 4,
						 rsp_len - 4 > 24 ? 24 : rsp_len - 4);
				else
					printf("\n");
			}
		}
		printf("\nDone.\n");
	} else if (strcmp(argv[1], "peek") == 0) {
		cmd_peek(argc, argv);
	} else if (strcmp(argv[1], "poke") == 0) {
		cmd_poke(argc, argv);
	} else if (strcmp(argv[1], "raw") == 0) {
		cmd_raw(argc, argv);
	} else {
		fprintf(stderr, "Unknown command: %s\n", argv[1]);
	}

	diag_cleanup();
	return 0;
}
