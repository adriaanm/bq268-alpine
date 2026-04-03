/*
 * diag-efs-write — Write a file to modem EFS via DIAG protocol
 *
 * Uses the DIAG EFS2 subsystem (0x4B 0x13) through /dev/diag to create
 * or overwrite a file in the modem's Embedded File System.
 *
 * Primary use case: disable APDU security restrictions for eSIM
 * provisioning by writing 0x00 to:
 *   /nv/item_files/modem/qmi/uim/apdu_security_restrictions
 *
 * Protocol: opens /dev/diag, switches to MEMORY_DEVICE_MODE (required
 * for bidirectional command/response), disables HDLC framing on the
 * read path, then sends EFS2 OPEN → WRITE → CLOSE commands.
 *
 * Cross-compile:
 *   ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc \
 *       -static -O2 -o diag-efs-write tools/diag-efs-write.c
 *
 * Usage:
 *   ./diag-efs-write                           # disable APDU restrictions
 *   ./diag-efs-write /efs/path 0xAB            # write byte to custom path
 *   ./diag-efs-write -r /efs/path              # read and print file contents
 *   ./diag-efs-write -l /efs/dir               # list directory contents
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

/* ── DIAG ioctl / mode constants (from kernel include/linux/diagchar.h) ── */

#define DIAG_IOCTL_SWITCH_LOGGING  7
#define DIAG_IOCTL_HDLC_TOGGLE    38

#define MEMORY_DEVICE_MODE  2
#define DIAG_CON_MPSS       0x0002

/* ── Data types for /dev/diag read/write ─────────────────────────────── */

#define USER_SPACE_DATA_TYPE      0x00000020
#define USER_SPACE_RAW_DATA_TYPE  0x00000080
#define PKT_TYPE                  0x00000008

/* ── DIAG subsystem dispatch ─────────────────────────────────────────── */

#define DIAG_SUBSYS_CMD  0x4B
#define SUBSYS_EFS2      0x13

/* ── EFS2 command codes (subsys_cmd_code values) ─────────────────────── */

#define EFS2_HELLO     0
#define EFS2_QUERY     1
#define EFS2_OPEN      2
#define EFS2_CLOSE     3
#define EFS2_READ      4
#define EFS2_WRITE     5
#define EFS2_MKDIR     9
#define EFS2_STAT      15
#define EFS2_OPENDIR   11
#define EFS2_READDIR   12
#define EFS2_CLOSEDIR  13
#define EFS2_PUT       26
#define EFS2_GET       27
#define EFS2_SYNC_NO_WAIT 48

/* ── Non-HDLC packet frame (wraps each response when HDLC is disabled) */

#define CONTROL_CHAR  0x7E

struct __attribute__((packed)) diag_pkt_frame {
	uint8_t  start;     /* 0x7E */
	uint8_t  version;   /* 1 */
	uint16_t length;    /* payload length (LE) */
};

/*
 * Strip non-HDLC frame from a packet if present.
 * Format: [7E] [01] [LL LL] [payload...] [7E]
 * Returns pointer to payload and sets *out_len.
 */
static const uint8_t *strip_non_hdlc_frame(const uint8_t *pkt, int pkt_len,
					    int *out_len)
{
	if (pkt_len >= (int)sizeof(struct diag_pkt_frame) + 1 &&
	    pkt[0] == CONTROL_CHAR && pkt[1] == 1) {
		const struct diag_pkt_frame *f = (const void *)pkt;
		uint16_t payload_len = f->length;
		int total = sizeof(struct diag_pkt_frame) + payload_len + 1;
		if (total <= pkt_len) {
			*out_len = payload_len;
			return pkt + sizeof(struct diag_pkt_frame);
		}
	}
	/* No frame — return as-is */
	*out_len = pkt_len;
	return pkt;
}

/* ── EFS2 open flags ──────────────────────────────────────────────────
 *
 * The DIAG EFS2 protocol uses POSIX-style octal flag values.
 * Two common flag schemes exist in various tools:
 *   Scheme A (POSIX): O_CREAT=0x40, O_TRUNC=0x200
 *   Scheme B (QXDM):  O_CREAT=0x100, O_TRUNC=0x400
 * We try Scheme A first; if that fails, fall back to Scheme B.
 */
#define EFS_O_RDONLY  0x0000
#define EFS_O_WRONLY  0x0001

/* Scheme A: POSIX octal values */
#define EFS_O_CREAT_A   0x0040
#define EFS_O_TRUNC_A   0x0200
/* Scheme B: QXDM/libqcdm values */
#define EFS_O_CREAT_B   0x0100
#define EFS_O_TRUNC_B   0x0400

/* Default to scheme A */
#define EFS_O_CREAT   EFS_O_CREAT_A
#define EFS_O_TRUNC   EFS_O_TRUNC_A
#define EFS_O_AUTODIR 0x0010

/* ── Structures ──────────────────────────────────────────────────────── */

struct __attribute__((packed)) diag_logging_mode_param_t {
	uint32_t req_mode;
	uint32_t peripheral_mask;
	uint32_t pd_mask;       /* not in all kernel versions, but safe */
	uint8_t  mode_param;
};

struct __attribute__((packed)) subsys_hdr {
	uint8_t  cmd_code;          /* 0x4B */
	uint8_t  subsys_id;         /* 0x13 for EFS2 */
	uint16_t subsys_cmd_code;   /* little-endian */
};

/* ── DIAG send/receive ───────────────────────────────────────────────── */

static int diag_fd = -1;

static void hex_dump(const char *label, const uint8_t *data, int len)
{
	fprintf(stderr, "%s (%d bytes):", label, len);
	for (int i = 0; i < len && i < 64; i++)
		fprintf(stderr, " %02x", data[i]);
	if (len > 64)
		fprintf(stderr, " ...");
	fprintf(stderr, "\n");
}

/*
 * Send a raw DIAG command (no HDLC — kernel handles framing to modem).
 * Write format: [4-byte pkt_type][raw payload]
 */
static int diag_send(const void *cmd, int len)
{
	uint8_t buf[4 + 4096];
	if (len > 4096) {
		fprintf(stderr, "diag_send: command too large (%d)\n", len);
		return -1;
	}

	*(uint32_t *)buf = USER_SPACE_RAW_DATA_TYPE;
	memcpy(buf + 4, cmd, len);

	hex_dump("[dbg] TX", (const uint8_t *)cmd, len);
	int ret = write(diag_fd, buf, 4 + len);
	if (ret < 0) {
		perror("write /dev/diag");
		return -1;
	}
	fprintf(stderr, "[dbg] write returned %d\n", ret);
	return 0;
}

/*
 * Read a DIAG response matching our subsystem and command code.
 *
 * Read format (HDLC disabled):
 *   [4B data_type][4B num_data][4B pkt_len][pkt_data]...
 *
 * Returns the matching packet length, or -1 on timeout.
 */
static int diag_recv(uint16_t expect_cmd, uint8_t *out, int out_max,
		     int timeout_ms)
{
	uint8_t buf[16384];
	int elapsed = 0;

	while (elapsed < timeout_ms) {
		int wait = (timeout_ms - elapsed);
		if (wait > 500)
			wait = 500;

		struct pollfd pfd = { .fd = diag_fd, .events = POLLIN };
		int pret = poll(&pfd, 1, wait);
		elapsed += wait;

		if (pret <= 0)
			continue;

		ssize_t n = read(diag_fd, buf, sizeof(buf));
		if (n < (ssize_t)sizeof(int)) {
			if (n > 0)
				fprintf(stderr, "[dbg] short read: %zd\n", n);
			continue;
		}

		int data_type = *(int *)buf;
		fprintf(stderr, "[dbg] RX data_type=0x%08x len=%zd\n",
			data_type, n);
		if (n > (ssize_t)sizeof(int))
			hex_dump("[dbg] RX payload",
				 buf + sizeof(int),
				 (int)(n - sizeof(int)));

		/* USER_SPACE_DATA_TYPE: multiplexed packet container */
		if (data_type == USER_SPACE_DATA_TYPE &&
		    n >= 2 * (ssize_t)sizeof(int)) {
			int num_data = *(int *)(buf + 4);
			int off = 8;

			for (int i = 0; i < num_data && off < n; i++) {
				if (off + (int)sizeof(int) > n)
					break;
				int pkt_len = *(int *)(buf + off);
				off += 4;
				if (pkt_len <= 0 || off + pkt_len > n)
					break;

				uint8_t *raw_pkt = buf + off;
				int payload_len;
				const uint8_t *pkt = strip_non_hdlc_frame(
					raw_pkt, pkt_len, &payload_len);

				if (payload_len >= (int)sizeof(struct subsys_hdr)) {
					const struct subsys_hdr *h = (const void *)pkt;
					if (h->cmd_code == DIAG_SUBSYS_CMD &&
					    h->subsys_id == SUBSYS_EFS2 &&
					    h->subsys_cmd_code == expect_cmd) {
						int cp = payload_len < out_max ?
							 payload_len : out_max;
						memcpy(out, pkt, cp);
						return cp;
					}
				}
				off += pkt_len;
			}
		}

		/* PKT_TYPE: single command response */
		if (data_type == PKT_TYPE && n > (ssize_t)sizeof(int)) {
			uint8_t *raw_pkt = buf + 4;
			int raw_len = n - 4;
			int payload_len;
			const uint8_t *pkt = strip_non_hdlc_frame(
				raw_pkt, raw_len, &payload_len);

			if (payload_len >= (int)sizeof(struct subsys_hdr)) {
				const struct subsys_hdr *h = (const void *)pkt;
				if (h->cmd_code == DIAG_SUBSYS_CMD &&
				    h->subsys_id == SUBSYS_EFS2 &&
				    h->subsys_cmd_code == expect_cmd) {
					int cp = payload_len < out_max ?
						 payload_len : out_max;
					memcpy(out, pkt, cp);
					return cp;
				}
			}
		}
	}

	return -1;
}

/* ── EFS2 operations ─────────────────────────────────────────────────── */

/*
 * EFS2 MKDIR: create a directory.
 *
 * Request:  [hdr 4B][mode 2B][path\0]
 * Response: [hdr 4B][errno 4B]
 */
static int efs_mkdir(const char *path)
{
	int path_len = strlen(path) + 1;
	int total = 4 + 2 + path_len;
	uint8_t cmd[512];

	if (total > (int)sizeof(cmd))
		return -1;

	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + 2) = EFS2_MKDIR;
	*(int16_t *)(cmd + 4) = 0777;
	memcpy(cmd + 6, path, path_len);

	if (diag_send(cmd, total) < 0)
		return -1;

	uint8_t rsp[64];
	int rsp_len = diag_recv(EFS2_MKDIR, rsp, sizeof(rsp), 3000);
	if (rsp_len < 8) {
		/* No response — might already exist, continue */
		return 0;
	}

	int32_t err = *(int32_t *)(rsp + 4);
	/* 0 = success, EEXIST (17) = already exists — both OK */
	if (err != 0 && err != 17) {
		fprintf(stderr, "  mkdir %s: EFS error %d\n", path, err);
		return -err;
	}
	return 0;
}

/*
 * Create all parent directories for a path.
 */
static void efs_mkdirs(const char *path)
{
	char buf[256];
	strncpy(buf, path, sizeof(buf) - 1);
	buf[sizeof(buf) - 1] = '\0';

	for (char *p = buf + 1; *p; p++) {
		if (*p == '/') {
			*p = '\0';
			efs_mkdir(buf);
			*p = '/';
		}
	}
}

/*
 * EFS2 OPEN: open a file, returns file descriptor.
 *
 * Request:  [hdr 4B][oflag 4B][mode 4B][path\0]
 * Response: [hdr 4B][fd 4B][errno 4B]
 */
static int efs_open(const char *path, uint32_t flags, uint32_t mode)
{
	int path_len = strlen(path) + 1;
	int total = 4 + 4 + 4 + path_len;
	uint8_t cmd[512];

	if (total > (int)sizeof(cmd))
		return -1;

	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + 2) = EFS2_OPEN;
	*(uint32_t *)(cmd + 4) = flags;
	*(uint32_t *)(cmd + 8) = mode;
	memcpy(cmd + 12, path, path_len);

	if (diag_send(cmd, total) < 0)
		return -1;

	uint8_t rsp[64];
	int rsp_len = diag_recv(EFS2_OPEN, rsp, sizeof(rsp), 5000);
	if (rsp_len < 12) {
		fprintf(stderr, "  open: no response\n");
		return -1;
	}

	int32_t fd_val = *(int32_t *)(rsp + 4);
	int32_t err    = *(int32_t *)(rsp + 8);

	if (fd_val < 0 || err != 0) {
		fprintf(stderr, "  open %s: fd=%d errno=%d\n", path, fd_val, err);
		return -1;
	}

	return fd_val;
}

/*
 * EFS2 WRITE: write data to an open file.
 *
 * Request:  [hdr 4B][fd 4B][offset 4B][nbyte 4B][data]
 * Response: [hdr 4B][fd 4B][offset 4B][bytes_written 4B][errno 4B]
 */
static int efs_write(int efs_fd, uint32_t offset, const uint8_t *data, int len)
{
	int total = 4 + 4 + 4 + len;
	uint8_t cmd[4096];

	if (total > (int)sizeof(cmd))
		return -1;

	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + 2) = EFS2_WRITE;
	*(uint32_t *)(cmd + 4) = efs_fd;
	*(uint32_t *)(cmd + 8) = offset;
	memcpy(cmd + 12, data, len);

	if (diag_send(cmd, total) < 0)
		return -1;

	uint8_t rsp[64];
	int rsp_len = diag_recv(EFS2_WRITE, rsp, sizeof(rsp), 5000);
	if (rsp_len < 20) {
		fprintf(stderr, "  write: no response\n");
		return -1;
	}

	int32_t written = *(int32_t *)(rsp + 12);
	int32_t err     = *(int32_t *)(rsp + 16);

	if (err != 0) {
		fprintf(stderr, "  write: errno=%d\n", err);
		return -1;
	}

	return written;
}

/*
 * EFS2 CLOSE: close a file descriptor.
 *
 * Request:  [hdr 4B][fd 4B]
 * Response: [hdr 4B][errno 4B]
 */
static int efs_close(int efs_fd)
{
	uint8_t cmd[8];

	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + 2) = EFS2_CLOSE;
	*(uint32_t *)(cmd + 4) = efs_fd;

	if (diag_send(cmd, 8) < 0)
		return -1;

	uint8_t rsp[64];
	int rsp_len = diag_recv(EFS2_CLOSE, rsp, sizeof(rsp), 3000);
	if (rsp_len < 8)
		return 0;  /* close response optional */

	int32_t err = *(int32_t *)(rsp + 4);
	if (err != 0) {
		fprintf(stderr, "  close: errno=%d\n", err);
		return -1;
	}
	return 0;
}

/*
 * EFS2 READ: read data from an open file.
 *
 * Request:  [hdr 4B][fd 4B][nbyte 4B][offset 4B]
 * Response: [hdr 4B][fd 4B][offset 4B][bytes_read 4B][errno 4B][data]
 */
static int efs_read(int efs_fd, uint32_t offset, uint8_t *data, int max_len)
{
	uint8_t cmd[16];

	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + 2) = EFS2_READ;
	*(uint32_t *)(cmd + 4) = efs_fd;
	*(uint32_t *)(cmd + 8) = max_len;
	*(uint32_t *)(cmd + 12) = offset;

	if (diag_send(cmd, 16) < 0)
		return -1;

	uint8_t rsp[4096];
	int rsp_len = diag_recv(EFS2_READ, rsp, sizeof(rsp), 5000);
	if (rsp_len < 20) {
		fprintf(stderr, "  read: no response\n");
		return -1;
	}

	int32_t bytes_read = *(int32_t *)(rsp + 12);
	int32_t err        = *(int32_t *)(rsp + 16);

	if (err != 0) {
		fprintf(stderr, "  read: errno=%d\n", err);
		return -1;
	}

	if (bytes_read > 0 && rsp_len >= 20 + bytes_read) {
		int cp = bytes_read < max_len ? bytes_read : max_len;
		memcpy(data, rsp + 20, cp);
		return cp;
	}
	return 0;
}

/*
 * EFS2 PUT: single-shot file create/write (no OPEN/CLOSE needed).
 *
 * Request:  [hdr 4B][data_len 4B][flags 4B][mode 4B][path\0][data]
 * Response: [hdr 4B][errno 4B]
 */
static int efs_put(const char *path, const uint8_t *data, int data_len)
{
	int path_len = strlen(path) + 1;
	int total = 4 + 4 + 4 + 4 + path_len + data_len;
	uint8_t cmd[512];

	if (total > (int)sizeof(cmd))
		return -1;

	int off = 0;
	cmd[off++] = DIAG_SUBSYS_CMD;
	cmd[off++] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + off) = EFS2_PUT;
	off += 2;
	*(uint32_t *)(cmd + off) = data_len;
	off += 4;
	*(uint32_t *)(cmd + off) = EFS_O_CREAT_A | EFS_O_TRUNC_A;
	off += 4;
	*(uint32_t *)(cmd + off) = 0644;
	off += 4;
	memcpy(cmd + off, path, path_len);
	off += path_len;
	memcpy(cmd + off, data, data_len);
	off += data_len;

	if (diag_send(cmd, off) < 0)
		return -1;

	uint8_t rsp[64];
	int rsp_len = diag_recv(EFS2_PUT, rsp, sizeof(rsp), 5000);
	if (rsp_len < 8) {
		fprintf(stderr, "  put: no response\n");
		return -1;
	}

	int32_t err = *(int32_t *)(rsp + 4);
	if (err != 0) {
		fprintf(stderr, "  put %s: EFS error %d\n", path, err);
		return -err;
	}
	return 0;
}

/* ── High-level operations ───────────────────────────────────────────── */

static int efs_write_file(const char *path, const uint8_t *data, int len)
{
	printf("Creating parent directories...\n");
	efs_mkdirs(path);

	/* Try OPEN+WRITE without O_CREAT first (for existing files) */
	printf("OPEN+WRITE, flags=0x%x (O_WRONLY only)...\n", EFS_O_WRONLY);
	int fd = efs_open(path, EFS_O_WRONLY, 0644);
	if (fd >= 0)
		goto do_write;

	/* Try PUT with POSIX flags */
	printf("PUT %s (%d byte(s)), flags=POSIX...\n", path, len);
	int ret = efs_put(path, data, len);
	if (ret == 0)
		return 0;

	/* Try OPEN+WRITE with POSIX flags (scheme A) */
	printf("OPEN+WRITE, flags=0x%x (POSIX)...\n",
	       EFS_O_WRONLY | EFS_O_CREAT_A);
	fd = efs_open(path, EFS_O_WRONLY | EFS_O_CREAT_A, 0644);
	if (fd >= 0)
		goto do_write;

	/* Try OPEN+WRITE with QXDM flags (scheme B) */
	printf("OPEN+WRITE, flags=0x%x (QXDM)...\n",
	       EFS_O_WRONLY | EFS_O_CREAT_B);
	fd = efs_open(path, EFS_O_WRONLY | EFS_O_CREAT_B, 0644);
	if (fd >= 0)
		goto do_write;

	/* Try OPEN+WRITE with O_CREAT|O_TRUNC|O_WRONLY scheme A */
	printf("OPEN+WRITE, flags=0x%x (POSIX+TRUNC)...\n",
	       EFS_O_WRONLY | EFS_O_CREAT_A | EFS_O_TRUNC_A);
	fd = efs_open(path, EFS_O_WRONLY | EFS_O_CREAT_A | EFS_O_TRUNC_A, 0644);
	if (fd >= 0)
		goto do_write;

	/* Try OPEN+WRITE with O_CREAT|O_TRUNC|O_WRONLY scheme B */
	printf("OPEN+WRITE, flags=0x%x (QXDM+TRUNC)...\n",
	       EFS_O_WRONLY | EFS_O_CREAT_B | EFS_O_TRUNC_B);
	fd = efs_open(path, EFS_O_WRONLY | EFS_O_CREAT_B | EFS_O_TRUNC_B, 0644);
	if (fd >= 0)
		goto do_write;

	return -1;

do_write:
	printf("Writing %d byte(s)...\n", len);
	int written = efs_write(fd, 0, data, len);
	if (written < 0) {
		efs_close(fd);
		return -1;
	}

	printf("Closing (wrote %d bytes)...\n", written);
	efs_close(fd);
	return 0;
}

static int efs_read_file(const char *path)
{
	int fd = efs_open(path, EFS_O_RDONLY, 0);
	if (fd < 0) {
		fprintf(stderr, "File not found or cannot open: %s\n", path);
		return -1;
	}

	uint8_t data[256];
	int n = efs_read(fd, 0, data, sizeof(data));
	efs_close(fd);

	if (n < 0)
		return -1;

	printf("Contents of %s (%d bytes):\n", path, n);
	hex_dump("  data", data, n);
	return 0;
}

/*
 * EFS2 OPENDIR / READDIR / CLOSEDIR: list directory contents.
 */
static int efs_opendir(const char *path)
{
	int path_len = strlen(path) + 1;
	int total = 4 + path_len;
	uint8_t cmd[512];

	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + 2) = EFS2_OPENDIR;
	memcpy(cmd + 4, path, path_len);

	if (diag_send(cmd, total) < 0)
		return -1;

	uint8_t rsp[64];
	int rsp_len = diag_recv(EFS2_OPENDIR, rsp, sizeof(rsp), 5000);
	if (rsp_len < 12) {
		fprintf(stderr, "  opendir: no response\n");
		return -1;
	}

	int32_t dirp = *(int32_t *)(rsp + 4);
	int32_t err  = *(int32_t *)(rsp + 8);
	if (dirp <= 0 || err != 0) {
		fprintf(stderr, "  opendir %s: dirp=%d errno=%d\n", path, dirp, err);
		return -1;
	}
	return dirp;
}

static int efs_readdir(int dirp, int seqno, char *name_out, int name_max,
		       int32_t *entry_type_out)
{
	uint8_t cmd[12];
	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + 2) = EFS2_READDIR;
	*(uint32_t *)(cmd + 4) = dirp;
	*(uint32_t *)(cmd + 8) = seqno;

	if (diag_send(cmd, 12) < 0)
		return -1;

	uint8_t rsp[512];
	int rsp_len = diag_recv(EFS2_READDIR, rsp, sizeof(rsp), 5000);
	if (rsp_len < 16) {
		fprintf(stderr, "  readdir: no response\n");
		return -1;
	}

	/*
	 * EFS2 READDIR response layout:
	 *   [hdr 4B][dirp 4B][seqno 4B][errno 4B]
	 *   [entry_type 4B][mode 4B][size 4B]
	 *   [atime 4B][mtime 4B][ctime 4B]
	 *   [name \0]
	 * Name starts at offset 40.
	 */
	int32_t err = *(int32_t *)(rsp + 12);
	int32_t entry_type = rsp_len >= 20 ? *(int32_t *)(rsp + 16) : -1;
	int32_t size = rsp_len >= 28 ? *(int32_t *)(rsp + 24) : 0;

	if (err != 0)
		return -1;

	if (entry_type_out)
		*entry_type_out = entry_type;

	/* Dump full response for debugging */
	hex_dump("[dbg] readdir full", rsp, rsp_len);

	/*
	 * EFS2 READDIR response: the name offset depends on firmware.
	 * Try offset 40 (with timestamps) first, fall back to 28 (without).
	 */
	int name_off = 40;
	if (rsp_len <= 41)  /* barely fits with timestamps → try without */
		name_off = 28;
	if (rsp_len > name_off) {
		int name_len = rsp_len - name_off;
		if (name_len >= name_max)
			name_len = name_max - 1;
		memcpy(name_out, rsp + name_off, name_len);
		name_out[name_len] = '\0';
		/* Strip trailing nulls */
		for (int i = name_len - 1; i >= 0 && name_out[i] == '\0'; i--)
			name_out[i] = '\0';
		printf("  %c %6d  %s\n",
		       entry_type == 1 ? 'd' : (entry_type == 0 ? 'f' : '?'),
		       size, name_out);
	}
	return 0;
}

static int efs_closedir(int dirp)
{
	uint8_t cmd[8];
	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + 2) = EFS2_CLOSEDIR;
	*(uint32_t *)(cmd + 4) = dirp;

	if (diag_send(cmd, 8) < 0)
		return -1;

	uint8_t rsp[64];
	diag_recv(EFS2_CLOSEDIR, rsp, sizeof(rsp), 3000);
	return 0;
}

static int efs_list_dir(const char *path)
{
	int dirp = efs_opendir(path);
	if (dirp < 0)
		return -1;

	printf("Contents of %s:\n", path);
	for (int seq = 1; seq < 256; seq++) {
		char name[256];
		int32_t entry_type;
		if (efs_readdir(dirp, seq, name, sizeof(name), &entry_type) < 0)
			break;
	}

	efs_closedir(dirp);
	return 0;
}

/*
 * EFS2 SYNC_NO_WAIT: ask modem to sync EFS to persistent storage.
 */
static int efs_sync(void)
{
	uint8_t cmd[8];
	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + 2) = EFS2_SYNC_NO_WAIT;
	/* path filter: empty string means sync everything */
	cmd[4] = '/';
	cmd[5] = '\0';

	fprintf(stderr, "[dbg] sending EFS2 SYNC...\n");
	if (diag_send(cmd, 6) < 0)
		return -1;

	uint8_t rsp[64];
	int rsp_len = diag_recv(EFS2_SYNC_NO_WAIT, rsp, sizeof(rsp), 5000);
	if (rsp_len >= 8) {
		int32_t token = *(int32_t *)(rsp + 4);
		fprintf(stderr, "[dbg] EFS2 SYNC: token=%d\n", token);
	}
	return 0;
}

/*
 * EFS2 GET: single-shot file read (no OPEN/CLOSE needed).
 *
 * Request:  [hdr 4B][path\0]
 * Response: [hdr 4B][errno 4B][length 4B][data]
 */
static int efs_get(const char *path, uint8_t *data, int max_len)
{
	int path_len = strlen(path) + 1;
	int total = 4 + path_len;
	uint8_t cmd[512];

	cmd[0] = DIAG_SUBSYS_CMD;
	cmd[1] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + 2) = EFS2_GET;
	memcpy(cmd + 4, path, path_len);

	if (diag_send(cmd, total) < 0)
		return -1;

	uint8_t rsp[4096];
	int rsp_len = diag_recv(EFS2_GET, rsp, sizeof(rsp), 5000);
	if (rsp_len < 12) {
		fprintf(stderr, "  get: no response\n");
		return -1;
	}

	int32_t err = *(int32_t *)(rsp + 4);
	int32_t length = *(int32_t *)(rsp + 8);

	if (err != 0) {
		fprintf(stderr, "  get %s: EFS error %d\n", path, err);
		return -err;
	}

	if (length > 0 && rsp_len >= 12 + length) {
		int cp = length < max_len ? length : max_len;
		memcpy(data, rsp + 12, cp);
		return cp;
	}
	return 0;
}

/*
 * EFS2 HELLO: negotiate protocol version and capabilities.
 *
 * Request/Response: [hdr 4B][targ_pkt_window 4B][targ_byte_window 4B]
 *                   [targ_dir_iter_window 4B][version 4B][min_version 4B]
 *                   [max_version 4B][feature_bits 4B]
 */
static int efs_hello(void)
{
	uint8_t cmd[32];
	int off = 0;

	cmd[off++] = DIAG_SUBSYS_CMD;
	cmd[off++] = SUBSYS_EFS2;
	*(uint16_t *)(cmd + off) = EFS2_HELLO;
	off += 2;
	*(uint32_t *)(cmd + off) = 0x100000;  /* target pkt window (1MB) */
	off += 4;
	*(uint32_t *)(cmd + off) = 0x100000;  /* target byte window */
	off += 4;
	*(uint32_t *)(cmd + off) = 128;       /* target dir_iter window */
	off += 4;
	*(uint32_t *)(cmd + off) = 1;         /* version */
	off += 4;
	*(uint32_t *)(cmd + off) = 1;         /* min_version */
	off += 4;
	*(uint32_t *)(cmd + off) = 1;         /* max_version */
	off += 4;
	*(uint32_t *)(cmd + off) = 0;         /* feature_bits */
	off += 4;

	fprintf(stderr, "[dbg] sending EFS2 HELLO...\n");
	if (diag_send(cmd, off) < 0)
		return -1;

	uint8_t rsp[64];
	int rsp_len = diag_recv(EFS2_HELLO, rsp, sizeof(rsp), 3000);
	if (rsp_len < 8) {
		fprintf(stderr, "[dbg] EFS2 HELLO: no response (len=%d)\n", rsp_len);
		/* Non-fatal — some firmware rejects HELLO */
		return 0;
	}

	if (rsp_len >= 32) {
		int32_t ver = *(int32_t *)(rsp + 16);
		int32_t minv = *(int32_t *)(rsp + 20);
		int32_t maxv = *(int32_t *)(rsp + 24);
		int32_t feat = *(int32_t *)(rsp + 28);
		fprintf(stderr, "[dbg] EFS2 HELLO: ver=%d min=%d max=%d features=0x%x\n",
			ver, minv, maxv, feat);
	} else {
		hex_dump("[dbg] EFS2 HELLO response", rsp, rsp_len);
	}
	return 0;
}

/* ── DIAG session init ───────────────────────────────────────────────── */

static int diag_init(void)
{
	fprintf(stderr, "[dbg] opening /dev/diag...\n");
	diag_fd = open("/dev/diag", O_RDWR | O_NONBLOCK);
	if (diag_fd < 0) {
		perror("open /dev/diag");
		return -1;
	}
	fprintf(stderr, "[dbg] open OK, fd=%d\n", diag_fd);

	/* Register as memory-device client for modem peripheral.
	 * This creates an MD session so our commands get forwarded
	 * and responses routed back to us. */
	struct diag_logging_mode_param_t param = {
		.req_mode = MEMORY_DEVICE_MODE,
		.peripheral_mask = DIAG_CON_MPSS,
		.pd_mask = 0,
		.mode_param = 0,
	};

	fprintf(stderr, "[dbg] ioctl SWITCH_LOGGING...\n");
	if (ioctl(diag_fd, DIAG_IOCTL_SWITCH_LOGGING, &param) < 0) {
		perror("ioctl DIAG_IOCTL_SWITCH_LOGGING");
		close(diag_fd);
		return -1;
	}
	fprintf(stderr, "[dbg] SWITCH_LOGGING OK\n");

	/* Disable HDLC framing on read path — get raw packets */
	uint8_t hdlc_disable = 1;
	fprintf(stderr, "[dbg] ioctl HDLC_TOGGLE...\n");
	if (ioctl(diag_fd, DIAG_IOCTL_HDLC_TOGGLE, &hdlc_disable) < 0) {
		/* Non-fatal — some kernels don't support this.
		 * We'll still try to parse responses. */
		fprintf(stderr, "warning: HDLC toggle failed (non-fatal)\n");
	}
	fprintf(stderr, "[dbg] HDLC_TOGGLE OK\n");

	/* Small delay for mode switch to take effect */
	usleep(100000);
	fprintf(stderr, "[dbg] init complete\n");

	/* Send SPC (Service Programming Code) to unlock EFS writes.
	 * DIAG cmd 0x41, payload = 6-digit SPC (default "000000").
	 * Also try DIAG password cmd 0x46 (16-byte password). */
	{
		uint8_t spc_cmd[7] = { 0x41, '0', '0', '0', '0', '0', '0' };
		fprintf(stderr, "[dbg] sending SPC unlock...\n");
		diag_send(spc_cmd, 7);
		usleep(500000);

		/* Read all pending responses, look for 0x41 SPC reply */
		uint8_t rsp_buf[16384];
		struct pollfd pfd = { .fd = diag_fd, .events = POLLIN };
		for (int attempt = 0; attempt < 10; attempt++) {
			if (poll(&pfd, 1, 300) <= 0)
				break;
			ssize_t n = read(diag_fd, rsp_buf, sizeof(rsp_buf));
			if (n < 8) continue;
			int dt = *(int *)rsp_buf;
			if (dt != USER_SPACE_DATA_TYPE) continue;
			int nd = *(int *)(rsp_buf + 4);
			int off = 8;
			for (int i = 0; i < nd && off < n; i++) {
				if (off + 4 > n) break;
				int plen = *(int *)(rsp_buf + off);
				off += 4;
				if (plen <= 0 || off + plen > n) break;
				int pl;
				const uint8_t *p = strip_non_hdlc_frame(
					rsp_buf + off, plen, &pl);
				if (pl >= 2 && p[0] == 0x41) {
					fprintf(stderr, "[dbg] SPC result: %s\n",
						p[1] ? "ACCEPTED" : "REJECTED");
				} else if (pl >= 1) {
					fprintf(stderr, "[dbg] SPC drain: cmd=0x%02x len=%d\n",
						p[0], pl);
				}
				off += plen;
			}
		}
	}

	/* Drain initial mask data flood */
	fprintf(stderr, "[dbg] draining initial data...\n");
	for (int i = 0; i < 20; i++) {
		uint8_t tmp[16384];
		struct pollfd pfd = { .fd = diag_fd, .events = POLLIN };
		if (poll(&pfd, 1, 200) > 0)
			read(diag_fd, tmp, sizeof(tmp));
		else
			break;
	}
	fprintf(stderr, "[dbg] drain done\n");

	/* Test: send a simple DIAG version request (cmd 0x00) */
	{
		uint8_t vcmd = 0x00;
		fprintf(stderr, "[dbg] sending version request...\n");
		diag_send(&vcmd, 1);

		uint8_t vrsp[256];
		struct pollfd pfd = { .fd = diag_fd, .events = POLLIN };
		for (int i = 0; i < 10; i++) {
			if (poll(&pfd, 1, 500) > 0) {
				ssize_t n = read(diag_fd, vrsp, sizeof(vrsp));
				fprintf(stderr, "[dbg] ver RX type=0x%08x len=%zd\n",
					n >= 4 ? *(int *)vrsp : 0, n);
				if (n >= 4 && *(int *)vrsp == PKT_TYPE) {
					hex_dump("[dbg] ver response",
						 vrsp + 4, n - 4 > 32 ? 32 : n - 4);
					break;
				}
				if (n >= 4 && *(int *)vrsp == USER_SPACE_DATA_TYPE) {
					hex_dump("[dbg] ver USD",
						 vrsp + 4, n - 4 > 48 ? 48 : n - 4);
					break;
				}
			}
		}
	}

	/* Send DIAG security password (cmd 0x46, 8 bytes all-zero).
	 * This is a deeper security unlock beyond SPC. */
	{
		uint8_t sec_cmd[9];
		sec_cmd[0] = 0x46;
		memset(sec_cmd + 1, 0, 8);
		fprintf(stderr, "[dbg] sending security password...\n");
		diag_send(sec_cmd, 9);
		usleep(200000);

		uint8_t rsp_buf[16384];
		struct pollfd pfd = { .fd = diag_fd, .events = POLLIN };
		for (int attempt = 0; attempt < 5; attempt++) {
			if (poll(&pfd, 1, 300) <= 0)
				break;
			ssize_t n = read(diag_fd, rsp_buf, sizeof(rsp_buf));
			if (n >= 8) {
				int dt = *(int *)rsp_buf;
				if (dt == USER_SPACE_DATA_TYPE) {
					int nd = *(int *)(rsp_buf + 4);
					int off = 8;
					for (int i = 0; i < nd && off < n; i++) {
						if (off + 4 > n) break;
						int plen = *(int *)(rsp_buf + off);
						off += 4;
						if (plen <= 0 || off + plen > n) break;
						int pl;
						const uint8_t *p = strip_non_hdlc_frame(
							rsp_buf + off, plen, &pl);
						if (pl >= 2 && p[0] == 0x46) {
							fprintf(stderr,
								"[dbg] security password: %s\n",
								p[1] ? "ACCEPTED" : "REJECTED");
						}
						off += plen;
					}
				}
			}
		}
	}

	/* EFS2 HELLO — negotiate protocol version */
	efs_hello();

	return 0;
}

static void diag_cleanup(void)
{
	if (diag_fd >= 0) {
		/* Switch back to USB mode to not disrupt other tools */
		struct diag_logging_mode_param_t param = {
			.req_mode = 1, /* USB_MODE */
			.peripheral_mask = DIAG_CON_MPSS,
			.pd_mask = 0,
			.mode_param = 0,
		};
		ioctl(diag_fd, DIAG_IOCTL_SWITCH_LOGGING, &param);
		close(diag_fd);
	}
}

/* ── Main ────────────────────────────────────────────────────────────── */

static const char *APDU_RESTRICT_PATH =
	"/nv/item_files/modem/qmi/uim/apdu_security_restrictions";

static void usage(const char *argv0)
{
	fprintf(stderr,
		"Usage:\n"
		"  %s                        Disable APDU security restrictions\n"
		"  %s <path> <hex_value>     Write byte to EFS path\n"
		"  %s -r <path>              Read EFS file\n"
		"  %s -l <dir>               List directory contents\n"
		"  %s -h                     Show this help\n"
		"\n"
		"Default: writes 0x00 to %s\n"
		"This disables the modem's APDU access control, allowing\n"
		"QMI UIM logical channel operations for eSIM provisioning.\n",
		argv0, argv0, argv0, argv0, argv0, APDU_RESTRICT_PATH);
}

enum { MODE_WRITE, MODE_READ, MODE_LIST };

int main(int argc, char *argv[])
{
	int mode = MODE_WRITE;
	const char *path = APDU_RESTRICT_PATH;
	uint8_t value = 0x00;

	if (argc > 1 && strcmp(argv[1], "-h") == 0) {
		usage(argv[0]);
		return 0;
	}

	if (argc > 1 && strcmp(argv[1], "-r") == 0) {
		mode = MODE_READ;
		if (argc > 2)
			path = argv[2];
	} else if (argc > 1 && strcmp(argv[1], "-l") == 0) {
		mode = MODE_LIST;
		path = argc > 2 ? argv[2] : "/";
	} else {
		if (argc > 1)
			path = argv[1];
		if (argc > 2)
			value = (uint8_t)strtol(argv[2], NULL, 0);
	}

	setbuf(stdout, NULL);  /* unbuffered for SSH/pipe */
	setbuf(stderr, NULL);

	const char *mode_str[] = { "Write", "Read", "List" };
	printf("=== DIAG EFS %s ===\n", mode_str[mode]);
	printf("Path: %s\n", path);
	if (mode == MODE_WRITE)
		printf("Value: 0x%02x\n", value);
	printf("\n");

	if (diag_init() < 0)
		return 1;

	int ret;
	if (mode == MODE_READ) {
		ret = efs_read_file(path);
	} else if (mode == MODE_LIST) {
		ret = efs_list_dir(path);
	} else {
		ret = efs_write_file(path, &value, 1);
	}

	diag_cleanup();

	if (ret == 0) {
		if (mode == MODE_WRITE) {
			/* Verify by reading back */
			printf("\nVerifying...\n");
			uint8_t verify[16];
			int vn = efs_get(path, verify, sizeof(verify));
			if (vn > 0) {
				printf("  readback OK: %d byte(s), value=0x%02x\n",
				       vn, verify[0]);
			} else {
				/* Try OPEN+READ fallback */
				int vfd = efs_open(path, EFS_O_RDONLY, 0);
				if (vfd >= 0) {
					vn = efs_read(vfd, 0, verify, sizeof(verify));
					efs_close(vfd);
					if (vn > 0)
						printf("  readback OK: %d byte(s), value=0x%02x\n",
						       vn, verify[0]);
					else
						printf("  readback: file exists but empty\n");
				} else {
					printf("  WARNING: readback failed — file may not have persisted\n");
				}
			}

			/* Force EFS sync to persistent storage */
			efs_sync();
			usleep(500000);
		}

		printf("\n=== %s ===\n", mode == MODE_WRITE ? "Success" : "Done");
		if (mode == MODE_WRITE && strcmp(path, APDU_RESTRICT_PATH) == 0) {
			printf("APDU security restrictions disabled.\n");
			printf("Reboot:  reboot\n");
			printf("Then test:      qmicli -d msmipc://0 "
			       "--uim-open-logical-channel=1,"
			       "a0000005591010ffffffff8900000100\n");
		}
	} else {
		fprintf(stderr, "\n=== Failed ===\n");
	}

	return ret == 0 ? 0 : 1;
}
