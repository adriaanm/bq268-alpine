# /data: separating device state from the rootfs image

Status: proposed

## The problem

Everything per-device lives inside the rootfs on `userdata` (p36), so
every rootfs reflash destroys it: wata's `/etc/wata/` (`config.json`
settings, `iroh.json` device identity — losing it forces re-enrolling
the handset — and `outbox/`, queued voice messages), the ssh host
keys (every reflash trips known_hosts), `wpa_supplicant.conf`, and
the persisted-clock file `clock-at-boot.md` wants. It also blocks
`reboot-forensics.md`: with only tmpfs available, per-boot PON-reason
logs cannot survive to be read.

## The decision

Repurpose the dead Android **`system` partition (p6, 921 MB)** as a
persistent `/data`. No GPT changes — on a device whose bootloader
history includes a fused-root-of-trust brick, not repartitioning is a
feature. The other dead candidates are smaller (`cache` 112 MB,
`persist` 32 MB) and `system`'s size fits the real growth path (voice
cache, persistent logs). Partitions that stay untouchable: everything
modem/secure (`modemst1/2`, `fsg`, `fsc`, `sec`, `ssd`, `keystore`,
`rpmb`) and the boot chain.

State moves by **bind mount and symlink, not path changes**: wata's
code and the rootfs image stay generic; a freshly flashed rootfs on a
new handset self-initializes.

## What changes

- **fstab / early boot**: mount `/dev/mmcblk0p6` ext4 `noatime` at
  `/data` in `localmount`'s window. A first-boot init script (openrc,
  before anything that touches state): if the partition has no ext4
  magic, `mkfs.ext4` it and seed the directory skeleton
  (`/data/wata`, `/data/ssh`, `/data/wifi`, `/data/log`, `/data/clock`).
- **Migration on first mount with existing rootfs state**: if
  `/etc/wata` is a real directory with content and `/data/wata` is
  empty, copy it over once, then bind.
- **Bind/symlink map**:
  - `/etc/wata` ← bind of `/data/wata`
  - `/etc/ssh/ssh_host_*` ← symlinks into `/data/ssh/`
  - `/etc/wpa_supplicant/wpa_supplicant.conf` ← symlink into `/data/wifi/`
  - the persisted-clock file → `/data/clock/` (unblocks part of
    `clock-at-boot.md`)
  - boot-time PON-reason capture appends to `/data/log/boot-reasons.log`
    (the `reboot-forensics.md` handoff, now unblocked); optionally a
    size-capped mirror of `/tmp/wata.log` rotated per boot.
- **build-rootfs.sh**: nothing per-device baked in (already true for
  wata state; ssh host keys must stop being generated into the image
  if they are today — first boot generates into `/data/ssh`).

## Crash-safety

Brownouts are a proven reality on this hardware (UVLO/SMPL log
entries), so `/data` is ext4 with its journal, and the write
discipline matters more than mount flags:

- wata's `iroh.json` is already written temp+rename (safe shape);
  `config.json` is truncate-in-place and can be zeroed by a power cut
  mid-write — tracked on the wata side (`FB-CONFIG-ATOMIC-WRITE` in
  wata-sgola). ext4's rename-over heuristic (auto_da_alloc) covers
  the rename path well enough; adding fsync-before-rename there is
  belt and braces.
- the first-boot mkfs must be gated on "no ext4 magic", never on a
  mount failure — a corrupted-but-present filesystem gets fsck'd
  (`fsck.ext4 -p` before mount), not wiped.

## Later, explicitly not now

Read-only rootfs + tmpfs overlay. Once state is out of `/`, an ro
root can't be corrupted by a brownout and a rootfs update becomes a
clean image write with zero state loss. It touches every writable
path Alpine expects, so it is its own plan.

## Verification

- Fresh-flash path: reflash rootfs, boot — device comes up, `/data`
  mounts, wata state intact (identity unchanged, outbox preserved,
  no re-enrol, ssh host key unchanged).
- First-boot path: wipe p6 (`dd` zeros over the first MB), boot —
  mkfs + skeleton + fresh state, wata starts unenrolled as designed.
- Brownout path: pull the battery mid-uptime twice; both boots mount
  `/data` cleanly (fsck -p) and state survives.
