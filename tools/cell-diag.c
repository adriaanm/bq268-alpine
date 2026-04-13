/*
 * cell-diag — Subscribe to LTE NAS log packets via Qualcomm DIAG and
 *             append parsed events to /var/log/cellular-diag.log.
 *
 * Why: QMI only reports the final attach state ("registered" / "not
 * registered-searching") with no reject cause. The DIAG framework exposes
 * raw LTE NAS EMM/ESM OTA messages, which contain the real EMM-cause /
 * ESM-cause codes we need to distinguish RF vs. HSS-reject vs. roaming
 * backoff. This is the blind spot that's been blocking the "Live LTE
 * attach still failing" investigation.
 *
 * What this does:
 *   1. open /dev/diag, switch to MEMORY_DEVICE mode against the MPSS
 *      peripheral, disable HDLC framing (matches tools/diag-apdu.c)
 *   2. send DIAG LOG_CONFIG(GET_RANGE) to discover the modem's current
 *      max_items[] per equipment class
 *   3. send DIAG LOG_CONFIG(SET_MASK) for equip_id 0xB (LTE) enabling
 *      log codes 0xB0C0..0xB0FF (LTE RRC OTA, EMM/ESM state, EMM/ESM
 *      OTA in/out). We enable the whole 0xC0..0xFF range rather than a
 *      hand-picked list because exact code numbers vary across Qualcomm
 *      firmwares; the extras are cheap.
 *   4. poll(2) /dev/diag forever, and for every incoming packet, if the
 *      first byte is 0x10 (DIAG log packet) extract {length, log_code,
 *      timestamp, payload} and append a single JSONL line per event to
 *      the log file. Everything else (responses to our SET_MASK,
 *      asynchronous control frames, etc.) is logged as a debug line and
 *      skipped.
 *
 * Usage:
 *   cell-diag [-o /var/log/cellular-diag.log] [-d]
 *     -o PATH  output JSONL path (default /var/log/cellular-diag.log)
 *     -d       also echo events to stdout (debug)
 *
 * Cross-compile:
 *   ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc \
 *       -static -O2 -Wall -o tools/cell-diag tools/cell-diag.c
 *
 * First iteration: dump raw hex of each NAS event. Decoding the NAS PDU
 * (EMM-cause at a known offset in ATTACH REJECT, etc.) comes in a second
 * pass once we've confirmed events actually flow end-to-end.
 */

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/ioctl.h>

#define DIAG_IOCTL_SWITCH_LOGGING 7
#define DIAG_IOCTL_HDLC_TOGGLE    38
#define MEMORY_DEVICE_MODE        2
#define DIAG_CON_MPSS             0x0002

#define USER_SPACE_DATA_TYPE      0x00000020
#define USER_SPACE_RAW_DATA_TYPE  0x00000080
#define PKT_TYPE                  0x00000008

#define DIAG_LOG_CONFIG_F 0x73
#define LOG_CONFIG_DISABLE_OP  0
#define LOG_CONFIG_GET_RANGE   1
#define LOG_CONFIG_SET_MASK    3

#define LTE_EQUIP_ID  0x0B
#define NUM_EQUIP_IDS 16

static int diag_fd = -1;
static FILE *logf = NULL;
static int debug = 0;
static volatile sig_atomic_t stop = 0;

static void on_signal(int sig) { (void)sig; stop = 1; }

static uint64_t now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void emit_json(const char *event, uint64_t host_ms, int log_code,
		      uint64_t diag_ts, const uint8_t *payload, int paylen)
{
	fprintf(logf, "{\"host_ms\":%llu,\"event\":\"%s\"",
		(unsigned long long)host_ms, event);
	if (log_code >= 0)
		fprintf(logf, ",\"log_code\":\"0x%04X\"", log_code);
	if (diag_ts)
		fprintf(logf, ",\"diag_ts\":%llu", (unsigned long long)diag_ts);
	if (payload && paylen > 0) {
		fprintf(logf, ",\"len\":%d,\"hex\":\"", paylen);
		int cap = paylen > 256 ? 256 : paylen;
		for (int i = 0; i < cap; i++)
			fprintf(logf, "%02x", payload[i]);
		if (paylen > cap)
			fprintf(logf, "...");
		fprintf(logf, "\"");
	}
	fprintf(logf, "}\n");
	fflush(logf);
	if (debug) {
		fprintf(stderr, "evt %s code=0x%04X len=%d\n",
			event, log_code, paylen);
	}
}

static int diag_write_raw(const void *cmd, int len)
{
	uint8_t buf[4 + 4096];
	if (len > 4096) return -1;
	*(uint32_t *)buf = USER_SPACE_RAW_DATA_TYPE;
	memcpy(buf + 4, cmd, len);
	ssize_t n = write(diag_fd, buf, 4 + len);
	return n < 0 ? -1 : 0;
}

/*
 * Read one incoming DIAG packet with a timeout. Returns the length of
 * the inner packet copied into out, or -1 on timeout. If the packet
 * container holds multiple sub-packets we only return the first here —
 * for log streaming that's fine because log packets always arrive in
 * separate container frames in practice.
 */
static int diag_read_one(uint8_t *out, int out_max, int timeout_ms)
{
	uint8_t buf[16384];
	struct pollfd pfd = { .fd = diag_fd, .events = POLLIN };
	int pret = poll(&pfd, 1, timeout_ms);
	if (pret <= 0) return -1;

	ssize_t n = read(diag_fd, buf, sizeof(buf));
	if (n < 4) return -1;

	int data_type = *(int *)buf;

	if (data_type == USER_SPACE_DATA_TYPE && n >= 8) {
		int num_data = *(int *)(buf + 4);
		int off = 8;
		if (num_data <= 0) return -1;
		if (off + 4 > n) return -1;
		int pkt_len = *(int *)(buf + off);
		off += 4;
		if (pkt_len <= 0 || off + pkt_len > n) return -1;
		int cp = pkt_len < out_max ? pkt_len : out_max;
		memcpy(out, buf + off, cp);
		return cp;
	}

	if (data_type == PKT_TYPE && n > 4) {
		int cp = (int)(n - 4);
		if (cp > out_max) cp = out_max;
		memcpy(out, buf + 4, cp);
		return cp;
	}

	return -1;
}

/*
 * Drain everything that's currently waiting on the fd, feeding each
 * packet to the log handler. Called from the main loop.
 */
static void handle_packet(const uint8_t *pkt, int len)
{
	if (len < 1) return;

	/* Log packets start with command code 0x10 (LOG_F). The exact
	 * wrapper shape on MSM8909 CAF 4.4 we'll discover empirically
	 * on first run; for now parse two common layouts:
	 *
	 * Layout A (kernel diagchar.h):
	 *   [0]     0x10
	 *   [1]     0x00
	 *   [2..3]  uint16 outer_len  (length from [2] onwards)
	 *   [4..5]  uint16 inner_len
	 *   [6..7]  uint16 log_code
	 *   [8..15] uint64 timestamp (1.25 us units)
	 *   [16..]  payload
	 *
	 * Layout B (some vendor blobs):
	 *   [0..1]  uint16 len
	 *   [2..3]  uint16 log_code
	 *   [4..11] uint64 ts
	 *   [12..]  payload
	 */
	if (pkt[0] == 0x10 && len >= 16) {
		uint16_t log_code = (uint16_t)(pkt[6] | (pkt[7] << 8));
		uint64_t ts;
		memcpy(&ts, pkt + 8, 8);
		const uint8_t *payload = pkt + 16;
		int paylen = len - 16;
		if (paylen < 0) paylen = 0;

		const char *ev = "LOG";
		switch (log_code) {
		case 0xB0C0: ev = "LTE_RRC_OTA"; break;
		case 0xB0E0: ev = "LTE_NAS_EMM_STATE"; break;
		case 0xB0E1: ev = "LTE_NAS_EMM_FORBIDDEN_TAI"; break;
		case 0xB0E2: ev = "LTE_NAS_EMM_OTA_IN"; break;
		case 0xB0E3: ev = "LTE_NAS_EMM_OTA_OUT"; break;
		case 0xB0E8: ev = "LTE_NAS_ESM_OTA_IN"; break;
		case 0xB0E9: ev = "LTE_NAS_ESM_OTA_OUT"; break;
		case 0xB0EA: ev = "LTE_NAS_ESM_STATE"; break;
		case 0xB0EB: ev = "LTE_NAS_ESM_BEARER_CTX"; break;
		default: break;
		}
		emit_json(ev, now_ms(), log_code, ts, payload, paylen);
		return;
	}

	/* Non-log packet — subsystem response, error, etc. Log as debug
	 * so we can see what the modem is saying back to our commands. */
	emit_json("DIAG_OTHER", now_ms(), -1, 0, pkt, len);
}

static int diag_init(void)
{
	diag_fd = open("/dev/diag", O_RDWR | O_NONBLOCK);
	if (diag_fd < 0) { perror("open /dev/diag"); return -1; }

	struct {
		uint32_t req_mode;
		uint32_t peripheral_mask;
		uint8_t  mode_param;
	} __attribute__((packed)) param = {
		.req_mode = MEMORY_DEVICE_MODE,
		.peripheral_mask = DIAG_CON_MPSS,
		.mode_param = 0,
	};
	if (ioctl(diag_fd, DIAG_IOCTL_SWITCH_LOGGING, &param) < 0) {
		perror("ioctl SWITCH_LOGGING");
		return -1;
	}

	uint8_t hdlc_disable = 1;
	ioctl(diag_fd, DIAG_IOCTL_HDLC_TOGGLE, &hdlc_disable);

	usleep(100000);

	/* drain anything queued */
	for (int i = 0; i < 20; i++) {
		uint8_t tmp[16384];
		struct pollfd pfd = { .fd = diag_fd, .events = POLLIN };
		if (poll(&pfd, 1, 50) > 0)
			read(diag_fd, tmp, sizeof(tmp));
		else
			break;
	}
	return 0;
}

/* Try DIAG LOG_CONFIG GET_RANGE. Returns 0 if we got a response we can
 * parse and fills max_items[], -1 otherwise. */
static int log_get_range(uint32_t max_items[NUM_EQUIP_IDS])
{
	uint8_t req[8] = { DIAG_LOG_CONFIG_F, 0, 0, 0,
			   LOG_CONFIG_GET_RANGE, 0, 0, 0 };
	if (diag_write_raw(req, sizeof(req)) < 0) return -1;

	uint8_t rsp[512];
	for (int tries = 0; tries < 10; tries++) {
		int n = diag_read_one(rsp, sizeof(rsp), 500);
		if (n < 0) continue;
		if (n >= 8 + 4 * NUM_EQUIP_IDS && rsp[0] == DIAG_LOG_CONFIG_F) {
			uint32_t op;
			memcpy(&op, rsp + 4, 4);
			if (op == LOG_CONFIG_GET_RANGE) {
				memcpy(max_items, rsp + 8,
				       4 * NUM_EQUIP_IDS);
				return 0;
			}
		}
		/* not ours — log and keep trying */
		handle_packet(rsp, n);
	}
	return -1;
}

/* Send LOG_CONFIG SET_MASK for one equipment class, enabling bits
 * [first_item..last_item] inclusive. Packet layout:
 *   [0]    0x73
 *   [1..3] 0
 *   [4..7] op = 3 (SET_MASK)
 *   [8..11] equip_id
 *   [12..15] num_items
 *   [16..]  mask bytes, ceil(num_items/8) bytes
 */
static int log_set_mask(uint32_t equip_id, uint32_t num_items,
			uint32_t first_item, uint32_t last_item)
{
	uint32_t mask_bytes = (num_items + 7) / 8;
	if (mask_bytes > 512) mask_bytes = 512;

	uint8_t req[16 + 512];
	memset(req, 0, sizeof(req));
	req[0] = DIAG_LOG_CONFIG_F;
	uint32_t op = LOG_CONFIG_SET_MASK;
	memcpy(req + 4, &op, 4);
	memcpy(req + 8, &equip_id, 4);
	memcpy(req + 12, &num_items, 4);

	for (uint32_t i = first_item; i <= last_item && i < num_items; i++)
		req[16 + (i / 8)] |= (uint8_t)(1u << (i & 7));

	int total = 16 + (int)mask_bytes;
	if (diag_write_raw(req, total) < 0) return -1;

	/* Consume the ack + anything else that's arrived. */
	for (int tries = 0; tries < 10; tries++) {
		uint8_t rsp[512];
		int n = diag_read_one(rsp, sizeof(rsp), 300);
		if (n < 0) break;
		handle_packet(rsp, n);
	}
	return 0;
}

int main(int argc, char **argv)
{
	const char *out_path = "/var/log/cellular-diag.log";
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-o") && i + 1 < argc) {
			out_path = argv[++i];
		} else if (!strcmp(argv[i], "-d")) {
			debug = 1;
		} else {
			fprintf(stderr,
				"usage: %s [-o PATH] [-d]\n", argv[0]);
			return 1;
		}
	}

	logf = fopen(out_path, "a");
	if (!logf) { perror(out_path); return 1; }
	setvbuf(logf, NULL, _IOLBF, 0);

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	if (diag_init() < 0) return 1;
	emit_json("START", now_ms(), -1, 0, NULL, 0);

	uint32_t max_items[NUM_EQUIP_IDS] = { 0 };
	uint32_t lte_items = 0;
	if (log_get_range(max_items) == 0) {
		lte_items = max_items[LTE_EQUIP_ID];
		if (debug) {
			fprintf(stderr, "GET_RANGE LTE max_items=%u\n",
				lte_items);
		}
	} else {
		fprintf(stderr,
			"GET_RANGE failed; defaulting LTE num_items=0x100\n");
		lte_items = 0x100;
	}
	if (lte_items < 0xF0 || lte_items > 0x400) lte_items = 0x100;

	uint32_t last = lte_items - 1;
	if (last > 0xFF) last = 0xFF;
	if (log_set_mask(LTE_EQUIP_ID, lte_items, 0xC0, last) < 0) {
		fprintf(stderr, "SET_MASK failed\n");
		return 1;
	}
	emit_json("SUBSCRIBED", now_ms(), -1, 0, NULL, 0);

	while (!stop) {
		uint8_t pkt[8192];
		int n = diag_read_one(pkt, sizeof(pkt), 500);
		if (n > 0)
			handle_packet(pkt, n);
	}

	emit_json("STOP", now_ms(), -1, 0, NULL, 0);
	fclose(logf);

	/* restore USB logging mode on exit */
	struct {
		uint32_t req_mode;
		uint32_t peripheral_mask;
		uint8_t  mode_param;
	} __attribute__((packed)) reset = {
		.req_mode = 1, .peripheral_mask = DIAG_CON_MPSS,
	};
	ioctl(diag_fd, DIAG_IOCTL_SWITCH_LOGGING, &reset);
	close(diag_fd);
	return 0;
}
