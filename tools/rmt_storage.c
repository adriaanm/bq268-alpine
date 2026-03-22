/*
 * rmt_storage — Modem EFS storage daemon for BQ268 (MSM8909, CAF 4.4 kernel)
 *
 * Registers as QMI service 14 (RMTFS) on the IPC Router and serves modem
 * EFS partition read/write requests via shared memory (/dev/uioN).
 *
 * Partitions served:
 *   /boot/modem_fs1 → /dev/mmcblk0p26 (modemst1)
 *   /boot/modem_fs2 → /dev/mmcblk0p27 (modemst2)
 *   /boot/modem_fsg → /dev/mmcblk0p3  (fsg)
 *   /boot/modem_fsc → /dev/mmcblk0p29 (fsc)
 *
 * Protocol based on linux-msm/rmtfs (BSD-3-Clause, Linaro Ltd / Bjorn Andersson).
 * QMI wire format from qrtr/lib/qmi.c (BSD-3-Clause, The Linux Foundation).
 *
 * Cross-compile:
 *   arm-linux-gnueabihf-gcc -static -o rmt_storage rmt_storage.c
 */

#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ── IPC Router (AF_MSM_IPC) ────────────────────────────────────────────── */
/* From include/uapi/linux/msm_ipc.h (CAF 4.4 kernel) */

#define AF_MSM_IPC		27
#define MSM_IPC_ADDR_NAME	1
#define MSM_IPC_ADDR_ID		2

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

/* ── QMI Protocol Constants ─────────────────────────────────────────────── */

#define QMI_REQUEST		0x00
#define QMI_RESPONSE		0x02
#define QMI_INDICATION		0x04

#define RMTFS_QMI_SERVICE	14
#define RMTFS_QMI_VERSION	1
#define RMTFS_QMI_INSTANCE	0

/* RMTFS QMI message IDs */
#define QMI_RMTFS_OPEN		1
#define QMI_RMTFS_CLOSE		2
#define QMI_RMTFS_RW_IOVEC	3
#define QMI_RMTFS_ALLOC_BUFF	4
#define QMI_RMTFS_GET_DEV_ERROR	5

#define SECTOR_SIZE		512
#define MAX_CALLERS		10
#define BUF_SIZE		4096

/* ── QMI Wire Format ────────────────────────────────────────────────────── */
/*
 * QMI header (7 bytes, little-endian):
 *   uint8_t  type      (0x00=request, 0x02=response, 0x04=indication)
 *   uint16_t txn_id
 *   uint16_t msg_id
 *   uint16_t msg_len   (payload length after header)
 *
 * Payload = sequence of TLVs:
 *   uint8_t  type
 *   uint16_t len       (little-endian)
 *   uint8_t  data[len]
 *
 * Top-level QMI_STRING: TLV data = raw string (no length prefix).
 * Top-level QMI_DATA_LEN + VAR_LEN_ARRAY: [uint8_t count][entries...].
 */

struct __attribute__((packed)) qmi_hdr {
	uint8_t  type;
	uint16_t txn_id;
	uint16_t msg_id;
	uint16_t msg_len;
};

struct __attribute__((packed)) qmi_tlv_hdr {
	uint8_t  type;
	uint16_t len;
};

/* ── Response Builder ───────────────────────────────────────────────────── */

struct resp_buf {
	uint8_t data[BUF_SIZE];
	size_t  len;
};

static void resp_init(struct resp_buf *r, uint16_t txn_id, uint16_t msg_id)
{
	struct qmi_hdr *hdr = (struct qmi_hdr *)r->data;
	hdr->type = QMI_RESPONSE;
	hdr->txn_id = txn_id;
	hdr->msg_id = msg_id;
	hdr->msg_len = 0;
	r->len = sizeof(struct qmi_hdr);
}

static int resp_add_tlv(struct resp_buf *r, uint8_t type,
			const void *data, uint16_t len)
{
	size_t need = sizeof(struct qmi_tlv_hdr) + len;
	if (r->len + need > sizeof(r->data)) {
		fprintf(stderr, "[rmt_storage] response buffer overflow "
			"(%zu + %zu > %zu)\n", r->len, need, sizeof(r->data));
		return -1;
	}
	struct qmi_tlv_hdr *tlv = (struct qmi_tlv_hdr *)(r->data + r->len);
	tlv->type = type;
	tlv->len = len;
	memcpy(r->data + r->len + sizeof(struct qmi_tlv_hdr), data, len);
	r->len += need;
	/* Update msg_len in header */
	((struct qmi_hdr *)r->data)->msg_len = r->len - sizeof(struct qmi_hdr);
	return 0;
}

static void resp_add_result(struct resp_buf *r, uint16_t result, uint16_t error)
{
	struct __attribute__((packed)) { uint16_t result; uint16_t error; } res;
	res.result = result;
	res.error = error;
	resp_add_tlv(r, 2, &res, sizeof(res));
}

static void resp_add_u32(struct resp_buf *r, uint8_t type, uint32_t val)
{
	resp_add_tlv(r, type, &val, sizeof(val));
}

static void resp_add_u64(struct resp_buf *r, uint8_t type, uint64_t val)
{
	resp_add_tlv(r, type, &val, sizeof(val));
}

static void resp_add_u8(struct resp_buf *r, uint8_t type, uint8_t val)
{
	resp_add_tlv(r, type, &val, sizeof(val));
}

/* ── TLV Parser ─────────────────────────────────────────────────────────── */

static const uint8_t *find_tlv(const uint8_t *data, size_t len,
			       uint8_t type, uint16_t *out_len)
{
	size_t off = 0;

	while (off + 3 <= len) {
		uint8_t  t = data[off];
		uint16_t l = (uint16_t)data[off + 1] |
			     ((uint16_t)data[off + 2] << 8);

		if (off + 3 + l > len)
			break;
		if (t == type) {
			*out_len = l;
			return data + off + 3;
		}
		off += 3 + l;
	}
	return NULL;
}

/* ── Partition Table ────────────────────────────────────────────────────── */

struct partition {
	const char *modem_path;  /* path the modem requests */
	const char *dev_path;    /* block device on eMMC */
};

static const struct partition partitions[] = {
	{ "/boot/modem_fs1", "/dev/mmcblk0p26" },  /* modemst1 */
	{ "/boot/modem_fs2", "/dev/mmcblk0p27" },  /* modemst2 */
	{ "/boot/modem_fsg", "/dev/mmcblk0p3"  },  /* fsg */
	{ "/boot/modem_fsc", "/dev/mmcblk0p29" },  /* fsc */
	{ NULL, NULL }
};

/* ── Caller (open file) Management ──────────────────────────────────────── */

struct caller {
	int fd;
	off_t dev_size;  /* partition size in bytes (0 = unknown) */
	uint32_t node;
	uint32_t port;
	const struct partition *part;
};

static struct caller callers[MAX_CALLERS];

static void callers_init(void)
{
	for (int i = 0; i < MAX_CALLERS; i++)
		callers[i].fd = -1;
}

static const struct partition *find_partition(const char *path, size_t len)
{
	for (const struct partition *p = partitions; p->modem_path; p++) {
		if (strlen(p->modem_path) == len &&
		    memcmp(p->modem_path, path, len) == 0)
			return p;
	}
	return NULL;
}

static int caller_open(uint32_t node, uint32_t port,
		       const char *path, size_t path_len)
{
	const struct partition *part = find_partition(path, path_len);
	if (!part) {
		fprintf(stderr, "[rmt_storage] unknown partition: %.*s\n",
			(int)path_len, path);
		return -1;
	}

	/* Already open for this node? */
	for (int i = 0; i < MAX_CALLERS; i++) {
		if (callers[i].fd >= 0 && callers[i].node == node &&
		    callers[i].part == part)
			return i;
	}

	/* Find free slot */
	int slot = -1;
	for (int i = 0; i < MAX_CALLERS; i++) {
		if (callers[i].fd < 0) {
			slot = i;
			break;
		}
	}
	if (slot < 0) {
		fprintf(stderr, "[rmt_storage] no free caller slots\n");
		return -1;
	}

	int fd = open(part->dev_path, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "[rmt_storage] open %s: %s\n",
			part->dev_path, strerror(errno));
		return -1;
	}

	/* Get partition size for bounds checking */
	off_t dev_size = lseek(fd, 0, SEEK_END);
	if (dev_size <= 0)
		dev_size = 0; /* unknown — skip size checks */
	lseek(fd, 0, SEEK_SET);

	callers[slot].fd = fd;
	callers[slot].dev_size = dev_size;
	callers[slot].node = node;
	callers[slot].port = port;
	callers[slot].part = part;

	fprintf(stderr, "[rmt_storage] Open %s (%s, %lld bytes) => caller %d\n",
		part->modem_path, part->dev_path, (long long)dev_size, slot);
	return slot;
}

static void caller_close(int id)
{
	if (id < 0 || id >= MAX_CALLERS || callers[id].fd < 0)
		return;
	close(callers[id].fd);
	callers[id].fd = -1;
	callers[id].part = NULL;
}

static void callers_close_all(void)
{
	for (int i = 0; i < MAX_CALLERS; i++)
		caller_close(i);
}

/* ── UIO Shared Memory ──────────────────────────────────────────────────── */

struct sharedmem {
	void     *base;
	uint64_t phys_addr;
	uint64_t size;
	int      fd;
};

/*
 * Scan /sys/class/uio/ for a UIO device named "rmtfs", read its physical
 * address and size from sysfs, then mmap the device.
 */
static int sharedmem_open(struct sharedmem *sm, const char *uio_name)
{
	DIR *dir;
	struct dirent *de;
	char path[512], buf[64];
	int uio_num = -1;

	dir = opendir("/sys/class/uio");
	if (!dir) {
		fprintf(stderr, "[rmt_storage] /sys/class/uio: %s\n",
			strerror(errno));
		return -1;
	}

	while ((de = readdir(dir)) != NULL) {
		if (strncmp(de->d_name, "uio", 3) != 0)
			continue;

		snprintf(path, sizeof(path),
			 "/sys/class/uio/%s/name", de->d_name);
		int fd = open(path, O_RDONLY);
		if (fd < 0)
			continue;
		ssize_t n = read(fd, buf, sizeof(buf) - 1);
		close(fd);
		if (n <= 0)
			continue;
		buf[n] = '\0';
		/* strip newline */
		char *nl = strchr(buf, '\n');
		if (nl) *nl = '\0';

		if (strcmp(buf, uio_name) == 0) {
			uio_num = atoi(de->d_name + 3);
			break;
		}
	}
	closedir(dir);

	if (uio_num < 0) {
		fprintf(stderr, "[rmt_storage] UIO device '%s' not found\n",
			uio_name);
		return -1;
	}

	/* Read physical address */
	snprintf(path, sizeof(path),
		 "/sys/class/uio/uio%d/maps/map0/addr", uio_num);
	int fd = open(path, O_RDONLY);
	if (fd < 0) {
		perror(path);
		return -1;
	}
	ssize_t n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return -1;
	buf[n] = '\0';
	sm->phys_addr = strtoull(buf, NULL, 16);

	/* Read size */
	snprintf(path, sizeof(path),
		 "/sys/class/uio/uio%d/maps/map0/size", uio_num);
	fd = open(path, O_RDONLY);
	if (fd < 0) {
		perror(path);
		return -1;
	}
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return -1;
	buf[n] = '\0';
	sm->size = strtoull(buf, NULL, 16);

	/* mmap the UIO device */
	snprintf(path, sizeof(path), "/dev/uio%d", uio_num);
	sm->fd = open(path, O_RDWR);
	if (sm->fd < 0) {
		fprintf(stderr, "[rmt_storage] %s: %s\n", path, strerror(errno));
		return -1;
	}

	if (sm->phys_addr == 0 || sm->size == 0) {
		fprintf(stderr, "[rmt_storage] bad sharedmem: "
			"addr=0x%llx size=0x%llx\n",
			(unsigned long long)sm->phys_addr,
			(unsigned long long)sm->size);
		close(sm->fd);
		return -1;
	}

	sm->base = mmap(NULL, sm->size, PROT_READ | PROT_WRITE,
			MAP_SHARED, sm->fd, 0);
	if (sm->base == MAP_FAILED) {
		fprintf(stderr, "[rmt_storage] mmap: %s\n", strerror(errno));
		close(sm->fd);
		return -1;
	}

	fprintf(stderr, "[rmt_storage] shared memory: "
		"phys=0x%llx size=0x%llx (%llu KB) dev=%s\n",
		(unsigned long long)sm->phys_addr,
		(unsigned long long)sm->size,
		(unsigned long long)sm->size / 1024, path);
	return 0;
}

static void sharedmem_close(struct sharedmem *sm)
{
	if (sm->base && sm->base != MAP_FAILED)
		munmap(sm->base, sm->size);
	if (sm->fd >= 0)
		close(sm->fd);
}

/*
 * Translate a physical address to a pointer within the mmap'd region.
 * Returns NULL if the address is out of range.
 */
static void *shm_ptr(struct sharedmem *sm, uint64_t phys, size_t len)
{
	/* Guard against integer overflow in phys + len */
	if (len > sm->size || phys < sm->phys_addr)
		return NULL;
	uint64_t offset = phys - sm->phys_addr;
	if (offset > sm->size - len)
		return NULL;
	return (char *)sm->base + offset;
}

/* ── Globals ────────────────────────────────────────────────────────────── */

static struct sharedmem shmem;
static int verbose;

/* ── Debug Logging ──────────────────────────────────────────────────────── */

static void hex_dump(const char *prefix, const void *buf, size_t len)
{
	const uint8_t *p = buf;
	for (size_t i = 0; i < len; i += 16) {
		fprintf(stderr, "%s %04zx: ", prefix, i);
		size_t row = len - i < 16 ? len - i : 16;
		for (size_t j = 0; j < row; j++)
			fprintf(stderr, "%02x ", p[i + j]);
		for (size_t j = row; j < 16; j++)
			fprintf(stderr, "   ");
		for (size_t j = 0; j < row; j++) {
			uint8_t c = p[i + j];
			fprintf(stderr, "%c", (c >= 0x20 && c < 0x7f) ? c : '.');
		}
		fprintf(stderr, "\n");
	}
}

/* ── Send helper with debug logging ─────────────────────────────────────── */

static void resp_send(int sock, const struct sockaddr_msm_ipc *to,
		      socklen_t to_len, struct resp_buf *r)
{
	if (verbose) {
		struct qmi_hdr *hdr = (struct qmi_hdr *)r->data;
		fprintf(stderr, "[rmt_storage] >> msg_id=%d txn=%d len=%zu\n",
			hdr->msg_id, hdr->txn_id, r->len);
		hex_dump("[rmt_storage] >>", r->data, r->len);
	}
	sendto(sock, r->data, r->len, 0,
	       (const struct sockaddr *)to, to_len);
}

/* ── QMI Message Handlers ───────────────────────────────────────────────── */

static void handle_open(int sock, const struct sockaddr_msm_ipc *from,
			socklen_t from_len, const uint8_t *payload,
			size_t payload_len, uint16_t txn_id)
{
	struct resp_buf resp;
	resp_init(&resp, txn_id, QMI_RMTFS_OPEN);

	/* TLV 1: path (top-level QMI_STRING = raw bytes, no length prefix) */
	uint16_t path_len;
	const uint8_t *path = find_tlv(payload, payload_len, 1, &path_len);
	if (!path || path_len == 0) {
		fprintf(stderr, "[rmt_storage] open: missing path TLV\n");
		resp_add_result(&resp, 1, 2); /* FAILURE / MALFORMED_MSG */
		goto send;
	}

	int caller_id = caller_open(
		from->address.addr.port_addr.node_id,
		from->address.addr.port_addr.port_id,
		(const char *)path, path_len);
	if (caller_id < 0) {
		resp_add_result(&resp, 1, 3); /* FAILURE / INTERNAL */
		goto send;
	}

	resp_add_result(&resp, 0, 0); /* SUCCESS */
	resp_add_u32(&resp, 0x10, (uint32_t)caller_id);

send:
	resp_send(sock, from, from_len, &resp);
}

static void handle_close(int sock, const struct sockaddr_msm_ipc *from,
			 socklen_t from_len, const uint8_t *payload,
			 size_t payload_len, uint16_t txn_id)
{
	struct resp_buf resp;
	resp_init(&resp, txn_id, QMI_RMTFS_CLOSE);

	uint16_t tlen;
	const uint8_t *tlv = find_tlv(payload, payload_len, 1, &tlen);
	if (!tlv || tlen < 4) {
		resp_add_result(&resp, 1, 2);
		goto send;
	}

	uint32_t caller_id;
	memcpy(&caller_id, tlv, 4);

	if (verbose)
		fprintf(stderr, "[rmt_storage] close caller %u\n", caller_id);

	caller_close(caller_id);
	resp_add_result(&resp, 0, 0);

send:
	resp_send(sock, from, from_len, &resp);
}

static void handle_rw_iovec(int sock, const struct sockaddr_msm_ipc *from,
			    socklen_t from_len, const uint8_t *payload,
			    size_t payload_len, uint16_t txn_id)
{
	struct resp_buf resp;
	resp_init(&resp, txn_id, QMI_RMTFS_RW_IOVEC);

	uint16_t tlen;
	const uint8_t *tlv;

	/* TLV 1: caller_id (u32) */
	tlv = find_tlv(payload, payload_len, 1, &tlen);
	if (!tlv || tlen < 4) {
		resp_add_result(&resp, 1, 2);
		goto send;
	}
	uint32_t caller_id;
	memcpy(&caller_id, tlv, 4);

	if (caller_id >= MAX_CALLERS || callers[caller_id].fd < 0) {
		fprintf(stderr, "[rmt_storage] iovec: bad caller %u\n",
			caller_id);
		resp_add_result(&resp, 1, 3);
		goto send;
	}

	/* TLV 2: direction (u8, 0=read-from-storage, 1=write-to-storage) */
	tlv = find_tlv(payload, payload_len, 2, &tlen);
	if (!tlv || tlen < 1) {
		resp_add_result(&resp, 1, 2);
		goto send;
	}
	uint8_t is_write = *tlv;

	/* TLV 3: iovec [uint8_t count][entries: 12 bytes each] */
	tlv = find_tlv(payload, payload_len, 3, &tlen);
	if (!tlv || tlen < 1) {
		resp_add_result(&resp, 1, 2);
		goto send;
	}
	uint8_t count = *tlv;
	const uint8_t *entries = tlv + 1;
	if (tlen < (uint16_t)(1 + count * 12)) {
		fprintf(stderr, "[rmt_storage] iovec: truncated (%u entries, "
			"tlv_len=%u)\n", count, tlen);
		resp_add_result(&resp, 1, 2);
		goto send;
	}

	/* TLV 4: is_force_sync (u8) — informational only */
	uint8_t force = 0;
	tlv = find_tlv(payload, payload_len, 4, &tlen);
	if (tlv && tlen >= 1)
		force = *tlv;

	int fd = callers[caller_id].fd;
	off_t dev_size = callers[caller_id].dev_size;
	uint8_t sector_buf[SECTOR_SIZE];

	for (int i = 0; i < count; i++) {
		uint32_t sector_addr, phys_offset, num_sector;
		memcpy(&sector_addr, entries + i * 12 + 0, 4);
		memcpy(&phys_offset, entries + i * 12 + 4, 4);
		memcpy(&num_sector,  entries + i * 12 + 8, 4);

		if (verbose)
			fprintf(stderr, "[rmt_storage]   %s caller=%u "
				"sector=%u+%u phys=0x%x%s\n",
				is_write ? "write" : "read",
				caller_id, sector_addr, num_sector,
				phys_offset, force ? " (forced)" : "");

		/* Validate sector range won't overflow off_t or exceed partition */
		uint64_t end_sector = (uint64_t)sector_addr + num_sector;
		uint64_t end_byte = end_sector * SECTOR_SIZE;
		if (end_sector < sector_addr || end_byte / SECTOR_SIZE != end_sector) {
			fprintf(stderr, "[rmt_storage] sector overflow: "
				"addr=%u count=%u\n", sector_addr, num_sector);
			resp_add_result(&resp, 1, 3);
			goto send;
		}
		if (dev_size > 0 && (off_t)end_byte > dev_size) {
			fprintf(stderr, "[rmt_storage] sector range %u+%u "
				"exceeds partition (%lld bytes)\n",
				sector_addr, num_sector, (long long)dev_size);
			resp_add_result(&resp, 1, 3);
			goto send;
		}

		for (uint32_t j = 0; j < num_sector; j++) {
			off_t file_off = (off_t)(sector_addr + j) * SECTOR_SIZE;
			uint64_t phys = (uint64_t)phys_offset +
					(uint64_t)j * SECTOR_SIZE;

			void *sp = shm_ptr(&shmem, phys, SECTOR_SIZE);
			if (!sp) {
				fprintf(stderr, "[rmt_storage] phys 0x%llx "
					"out of shared memory range\n",
					(unsigned long long)phys);
				resp_add_result(&resp, 1, 3);
				goto send;
			}

			if (is_write) {
				/* modem wrote to shm → flush to partition */
				ssize_t n = pwrite(fd, sp, SECTOR_SIZE,
						   file_off);
				if (n != SECTOR_SIZE) {
					fprintf(stderr, "[rmt_storage] "
						"pwrite: %s\n",
						strerror(errno));
					resp_add_result(&resp, 1, 3);
					goto send;
				}
			} else {
				/* read partition → write to shm for modem */
				ssize_t n = pread(fd, sector_buf,
						  SECTOR_SIZE, file_off);
				if (n < 0) {
					fprintf(stderr, "[rmt_storage] "
						"pread: %s\n",
						strerror(errno));
					resp_add_result(&resp, 1, 3);
					goto send;
				}
				if (n < SECTOR_SIZE)
					memset(sector_buf + n, 0,
					       SECTOR_SIZE - n);
				memcpy(sp, sector_buf, SECTOR_SIZE);
			}
		}
	}

	if (is_write)
		fdatasync(fd);

	resp_add_result(&resp, 0, 0);

send:
	resp_send(sock, from, from_len, &resp);
}

static void handle_alloc_buf(int sock, const struct sockaddr_msm_ipc *from,
			     socklen_t from_len, const uint8_t *payload,
			     size_t payload_len, uint16_t txn_id)
{
	struct resp_buf resp;
	resp_init(&resp, txn_id, QMI_RMTFS_ALLOC_BUFF);

	uint16_t tlen;
	const uint8_t *tlv;

	/* TLV 2: buff_size (u32) */
	uint32_t req_size = 0;
	tlv = find_tlv(payload, payload_len, 2, &tlen);
	if (tlv && tlen >= 4)
		memcpy(&req_size, tlv, 4);

	if (req_size > shmem.size) {
		fprintf(stderr, "[rmt_storage] alloc_buf: requested %u > "
			"available %llu\n", req_size,
			(unsigned long long)shmem.size);
		resp_add_result(&resp, 1, 3);
		goto send;
	}

	fprintf(stderr, "[rmt_storage] Alloc buffer: req=%u avail=%llu "
		"addr=0x%llx\n", req_size,
		(unsigned long long)shmem.size,
		(unsigned long long)shmem.phys_addr);

	resp_add_result(&resp, 0, 0);
	resp_add_u64(&resp, 0x10, shmem.phys_addr);

send:
	resp_send(sock, from, from_len, &resp);
}

static void handle_get_dev_error(int sock, const struct sockaddr_msm_ipc *from,
				 socklen_t from_len,
				 const uint8_t *payload __attribute__((unused)),
				 size_t payload_len __attribute__((unused)),
				 uint16_t txn_id)
{
	struct resp_buf resp;
	resp_init(&resp, txn_id, QMI_RMTFS_GET_DEV_ERROR);

	resp_add_result(&resp, 0, 0);
	resp_add_u8(&resp, 0x10, 0); /* no error */

	resp_send(sock, from, from_len, &resp);
}

/* ── Main ───────────────────────────────────────────────────────────────── */

static volatile sig_atomic_t running = 1;

static void sig_handler(int sig)
{
	(void)sig;
	running = 0;
}

static void usage(const char *prog)
{
	fprintf(stderr,
		"Usage: %s [-v] [-u uio_name] [-w seconds]\n"
		"  -v            verbose logging\n"
		"  -u name       UIO device name (default: rmtfs)\n"
		"  -w seconds    wait for UIO device (default: 10)\n",
		prog);
}

int main(int argc, char **argv)
{
	const char *uio_name = "rmtfs";
	int wait_secs = 10;
	int opt;

	while ((opt = getopt(argc, argv, "vu:w:h")) != -1) {
		switch (opt) {
		case 'v':
			verbose = 1;
			break;
		case 'u':
			uio_name = optarg;
			break;
		case 'w':
			wait_secs = atoi(optarg);
			break;
		default:
			usage(argv[0]);
			return 1;
		}
	}

	struct sigaction sa = { .sa_handler = sig_handler };
	sigemptyset(&sa.sa_mask);
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);

	callers_init();

	/* Wait for UIO device to appear */
	int ret = -1;
	for (int i = 0; i < wait_secs && running; i++) {
		ret = sharedmem_open(&shmem, uio_name);
		if (ret == 0)
			break;
		if (i < wait_secs - 1) {
			fprintf(stderr, "[rmt_storage] waiting for UIO "
				"device '%s' (%d/%d)...\n",
				uio_name, i + 1, wait_secs);
			sleep(1);
		}
	}
	if (ret < 0) {
		fprintf(stderr, "[rmt_storage] shared memory not available, "
			"exiting\n");
		return 1;
	}

	/* Create IPC Router socket */
	int sock = socket(AF_MSM_IPC, SOCK_DGRAM, 0);
	if (sock < 0) {
		perror("[rmt_storage] socket(AF_MSM_IPC)");
		sharedmem_close(&shmem);
		return 1;
	}

	/* Register as QMI RMTFS service (service 14, version 1, instance 0) */
	struct sockaddr_msm_ipc addr;
	memset(&addr, 0, sizeof(addr));
	addr.family = AF_MSM_IPC;
	addr.address.addrtype = MSM_IPC_ADDR_NAME;
	addr.address.addr.port_name.service = RMTFS_QMI_SERVICE;
	addr.address.addr.port_name.instance =
		(RMTFS_QMI_VERSION & 0xFF) |
		((RMTFS_QMI_INSTANCE & 0xFF) << 8);

	if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		perror("[rmt_storage] bind(RMTFS service)");
		close(sock);
		sharedmem_close(&shmem);
		return 1;
	}

	fprintf(stderr, "[rmt_storage] QMI service %d registered, "
		"waiting for modem requests\n", RMTFS_QMI_SERVICE);

	/* Main event loop */
	while (running) {
		uint8_t buf[BUF_SIZE];
		struct sockaddr_msm_ipc from;
		socklen_t from_len = sizeof(from);

		ssize_t n = recvfrom(sock, buf, sizeof(buf), 0,
				     (struct sockaddr *)&from, &from_len);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			perror("[rmt_storage] recvfrom");
			break;
		}

		if (n < (ssize_t)sizeof(struct qmi_hdr)) {
			fprintf(stderr, "[rmt_storage] runt packet (%zd)\n", n);
			continue;
		}

		/* Validate sender address type */
		if (from.address.addrtype != MSM_IPC_ADDR_ID) {
			if (verbose)
				fprintf(stderr, "[rmt_storage] skip "
					"addrtype=%d\n",
					from.address.addrtype);
			continue;
		}

		struct qmi_hdr *hdr = (struct qmi_hdr *)buf;
		if (hdr->type != QMI_REQUEST) {
			if (verbose)
				fprintf(stderr, "[rmt_storage] skip "
					"type=%d\n", hdr->type);
			continue;
		}

		/* Use actual received length, not declared msg_len */
		const uint8_t *payload = buf + sizeof(struct qmi_hdr);
		size_t payload_len = n - sizeof(struct qmi_hdr);

		if (verbose) {
			fprintf(stderr, "[rmt_storage] << msg_id=%d txn=%d "
				"len=%zd from=%u:%u\n", hdr->msg_id,
				hdr->txn_id, (size_t)n,
				from.address.addr.port_addr.node_id,
				from.address.addr.port_addr.port_id);
			hex_dump("[rmt_storage] <<", buf, (size_t)n);
		}

		switch (hdr->msg_id) {
		case QMI_RMTFS_OPEN:
			handle_open(sock, &from, from_len,
				    payload, payload_len, hdr->txn_id);
			break;
		case QMI_RMTFS_CLOSE:
			handle_close(sock, &from, from_len,
				    payload, payload_len, hdr->txn_id);
			break;
		case QMI_RMTFS_RW_IOVEC:
			handle_rw_iovec(sock, &from, from_len,
					payload, payload_len, hdr->txn_id);
			break;
		case QMI_RMTFS_ALLOC_BUFF:
			handle_alloc_buf(sock, &from, from_len,
					 payload, payload_len, hdr->txn_id);
			break;
		case QMI_RMTFS_GET_DEV_ERROR:
			handle_get_dev_error(sock, &from, from_len,
					     payload, payload_len,
					     hdr->txn_id);
			break;
		default:
			fprintf(stderr, "[rmt_storage] unknown msg_id %d\n",
				hdr->msg_id);
			break;
		}
	}

	/* Cleanup */
	fprintf(stderr, "[rmt_storage] shutting down\n");
	close(sock);
	callers_close_all();
	sharedmem_close(&shmem);

	return 0;
}
