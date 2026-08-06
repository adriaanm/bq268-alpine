# wifi-join: the handset's join-a-network helper

Origin: the wata repo (`~/g/bq268/wata-sgola`, plan 0020 / queue key
`TUI-WIFI-PANEL`). Wata's admin tui can now push wifi credentials at a
handset through the server's device-command mailbox; the device client
(`wata-fb`, `cmdpoller.scala`/`WifiCmd`) executes the `wifi_join` op by
shelling out to **`/usr/local/bin/wifi-join`** — a helper this repo
provides, because the join mechanics (the wpa_supplicant config, the
reconfigure, surviving reboot) are rootfs concerns, not app concerns.
Until it lands, wata-fb reports `wifi-join helper missing` honestly and
the panel's join leg simply fails.

## Contract (wata-fb already calls exactly this)

```
wifi-join <ssid>        # ssid is the ONE argv argument
```

- **The PSK arrives on STDIN**, read to EOF (wata-fb writes it with no
  trailing newline; tolerate one). **Never accept it as an argument and
  never pass it to a child via argv or the environment** — /proc exposes
  both world-readably; stdin is the one channel it does not. Note
  `wpa_passphrase <ssid>` reads the passphrase from ITS stdin too, so the
  hash step needs no argv secret either.
- An **empty PSK means an open network** (`key_mgmt=NONE`). A non-empty
  PSK shorter than 8 or longer than 63 bytes is invalid per WPA — fail
  loudly before touching any config.
- **Exit 0** when the network block is in place and wpa_supplicant has
  been told (see below), with **one human-readable detail line on
  stdout** — wata-fb reports the first stdout line back to the admin's
  tui verbatim. Association/DHCP success is NOT required for exit 0: the
  connectivity element already shows the live outcome, and a helper that
  waited for DHCP would block the poller on a wrong-PSK typo.
- **Nonzero exit** with a one-line reason for anything else (bad args,
  config unwritable, wpa_cli unreachable). Keep total runtime bounded
  (< ~10 s) — the caller runs it synchronously with no timeout of its own.

## What it does

1. Validate, then build the network block — `wpa_passphrase` so the
   stored `psk=` is the derived hex, not the plaintext (open network:
   `key_mgmt=NONE`).
2. **Replace-or-append by ssid** in `/etc/wpa_supplicant/wpa_supplicant.conf`
   (one block per ssid — a re-join with a new PSK must not accumulate
   stale blocks), written atomically (temp file + rename, mode 0600).
   The file lives on the persistent rootfs, which is what makes the join
   survive reboot.
3. Give the new block a `priority` above the existing ones, so the
   network the parent just picked is the one the handset prefers.
4. Apply live: `wpa_cli -i wlan0 reconfigure`; if wlan0/the wifi service
   is down, `rc-service wifi start` first (the same service the settings
   toggle drives). A reconfigure that fails is still a nonzero exit even
   though the file was written — the next boot would pick it up, but the
   admin deserves the truth about "now".

No logging of the PSK anywhere (no `set -x`, no logger lines carrying
it). Runs as root today (wata runs as root); when the dedicated `wata`
user task lands, this helper is one of the commands that will need a
privilege path (doas rule or setuid wrapper) — note it there.

## Verification

- Host-side: wata's integ scenario `wifi-cmd` pins the CALLER's side of
  the contract against a fake helper (ssid via argv, PSK via stdin,
  first stdout line reported). This repo's half: a shell/pytest-style
  check that two joins for the same ssid leave ONE block, the psk is
  never plaintext in the file, an open network gets `key_mgmt=NONE`, and
  a short PSK is refused.
- On-device: `wifi-join <real-ssid>` with the PSK typed to stdin joins
  the network and survives a reboot; then the full loop from wata's tui
  (`wifi <user>` / `join <n>`), recorded in wata's plan 0020 when it
  happens.

## Implementation decisions (2026-08-06)

Implemented as `rootfs/files/usr/local/bin/wifi-join` (Python 3 — the
rootfs ships python3, and block-preserving conf rewriting is beyond
comfortable sh), installed by `rootfs/05-wifi.sh`. Host-side checks:
`just test-wifi-join` (`tools/test-wifi-join.py`, temp conf + PATH stubs
whose fake `wpa_passphrase` computes the real PBKDF2). Points the spec
left open, decided conservatively:

- **Env knobs, testing only** — `WIFI_JOIN_CONF` overrides the conf path
  and `WIFI_JOIN_DRY_RUN=1` validates + plans but touches nothing
  (prints a `dry-run:` line, exit 0). The argv/stdin contract wata-fb
  sees is unchanged; the dry-run also allows harmless on-device
  verification while a handset is mid-field-test.
- **Missing conf is an error**, not silently created — the base config
  (ctrl_interface etc.) is the rootfs build's job; a handset without it
  has bigger problems than this join.
- **ssid forms**: written quoted when it round-trips cleanly, hex
  otherwise; existing blocks match against either form. Non-ssid content
  of retained blocks is preserved verbatim.
- **Error reporting**: the one-line reason for a nonzero exit also goes
  to stdout, since wata-fb relays the first stdout line either way.
- **wpa_passphrase output is re-derived, not pasted**: only the 64-hex
  `psk=` line is taken from it, so its commented `#psk="plaintext"` line
  never reaches the conf.
