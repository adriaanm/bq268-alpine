# Fix: gate QMI init on Q6 readiness (stabilize the shared Q6 → fix audio)

**Prompt for a Fable working session.** Self-contained; read it top to bottom.

## Scope & non-goals (read first)

This task is **system-stability and init-ordering work only**: making the
modem's QMI bring-up wait for the Q6 DSP to be ready, and stopping a leaked QMI
indication subscription. It is a plain Linux/OpenRC/QMI plumbing problem.

**Out of scope — do not touch, read, or reason about:** modem firmware patching,
eSIM/APDU/UIM manipulation, DIAG APDU tooling, or anything about cellular
security. Those live in other repos and are irrelevant here. If a change seems
to require any of that, stop — you've left the intended scope.

## Why this matters (the goal)

The BQ268 is a cellular walkie-talkie: it needs **both** the modem **and** audio
working. On MSM8909 there is **no separate audio DSP** — audio's AFE/APR runs on
the **same Q6** as the modem (confirmed: subsystem list is `venus`, `wcnss`,
`modem`; audio dmesg shows `afe_q6_interface_prepare … -19` until
`apr_tal:Modem Is Up`).

Audio playback is currently **silent**, and the leading, evidence-backed
hypothesis is that a **modem/QMI init bug destabilizes the shared Q6**, which
degrades the Q6's audio service. Audio last worked (2026-03-31) when the modem
Q6 was booted but idle; it broke after the network-active modem bring-up landed
(2026-04-02/03). Stabilizing the Q6 is expected to restore audio. See
[../../../wata/docs/planning/audio-regression-2026-04-24.md] and
`~/g/bq268/audio_experiments.md` for the audio-side investigation.

## The confirmed failure mode

After every boot, on the device (`ssh bq268`):

- **4 `kworker/u8:N` threads pile up in `D` (uninterruptible) state**, waiting in
  `diag_socket_read`, `diag_cntl_process_read_data`, `flush_workqueue`,
  `msm_mpm_work_fn`. They don't burn CPU (top shows ~87% idle) but pin
  **load average at ~4**.
- dmesg grows `send_filled_buffers_to_user: Send Failed -3 drop_count = N`
  continuously (~10/min) — a QMI indication the kernel `msm_ipc_router` can't
  deliver because a subscriber leaked/never drains it.
- The modem's DMS operating mode gets stuck reporting **`shutting-down`** even
  though the modem *subsystem* sysfs state is `ONLINE`.
- Occasionally the **hardware watchdog fires and the device spontaneously
  reboots** (observed live 2026-07-05).

This is the tracked issue in `TASKS.md`:
> QMI-proxy boot-time orphan subscriptions + modem restart reboots … 4
> `kworker/u8:N` still pile up in D state after every boot … drop_count grows
> ~10/min, pinning load average around 4. Suspect: modem init retry loop hammers
> QMI while Q6 DSP isn't ready. Fix: wait for Q6 readiness before issuing QMI.

## Root cause (what to fix)

Two linked problems:

1. **The DMS "online" command is issued before the Q6's QMI services are ready,
   in a retry loop.** In `rootfs/files/etc/init.d/modem`, the start daemon runs:
   ```sh
   while [ $w -lt 60 ]; do
       qmicli -p -d msmipc://0 --dms-set-operating-mode=online … && break
       sleep 0.5; w=$((w+1))
   done
   ```
   Each attempt before the modem's DMS service is up is a failed QMI round-trip.
   Routing through `qmi-proxy` (`qmicli -p`) "halved" the leak but did not
   eliminate it. The loop should not fire QMI at all until the Q6 is actually
   ready.

2. **A NAS/serving-system indication subscription is left orphaned**, so once the
   modem goes online and starts emitting network indications, they fail to
   deliver (`Send Failed -3`) and the drop count climbs forever. Find who holds
   that subscription (candidates: a leaked retry from problem 1, or `qmi-proxy`
   holding a client subscription nobody drains) and make sure every subscribed
   indication is drained — or that no such subscription is created during
   readiness probing.

## Files involved

- `rootfs/files/etc/init.d/modem` — the QMI retry loop (primary).
- `rootfs/files/etc/init.d/qmi-proxy` — persistent QMI multiplexer; starts
  `before modem`, does **not** `need modem` (so it's up before the Q6). Uses
  `/usr/libexec/qmi-proxy --no-exit` on abstract socket `@qmi-proxy`.
- `rootfs/files/etc/init.d/rmt-storage` — serves modem EFS; `modem` needs it.
- `rootfs/12-modem.sh` — installs the modem tooling/services into the rootfs.
- Readiness signal on device: modem subsystem state at
  `/sys/bus/msm_subsys/devices/subsys*/` (match `name`==`modem`, want
  `state`==`ONLINE`). Note: subsystem `ONLINE` only means the Q6 firmware
  loaded — the **QMI DMS service** may register a bit later, so also gate on a
  cheap *read* succeeding (see below).

## Suggested fix approach

1. **Gate on Q6 readiness before any QMI write.** In `init.d/modem`, after
   holding `/dev/subsys_modem` open, wait for the modem subsystem sysfs
   `state`==`ONLINE`. Then wait for the **DMS service to actually answer a
   read** — poll `qmicli -p -d msmipc://0 --dms-get-operating-mode` (a
   non-mutating query) until it succeeds. Only then issue
   `--dms-set-operating-mode=online` **once** (not in a hammering loop).
2. **Do not retry mutating QMI commands in a tight loop.** If the single online
   command fails after the DMS read is answering, log it and back off with a
   long sleep, don't spin at 0.5 s.
3. **Kill the indication leak.** Confirm whether the growing `Send Failed -3`
   comes from a subscription created during the readiness probe or held by
   `qmi-proxy`. Ensure indications are drained (libqmi drains for subscribed
   clients; a *dead* client's subscription is the leak). The readiness *read*
   in step 1 must not subscribe to indications.
4. Keep it OpenRC-idiomatic and reproducible (the repo builds via
   `just build-rootfs`; all repeated commands belong in the `justfile`).

## How to verify (success criteria)

On the device after `just build-rootfs` + flash + a clean boot:

**Stability (necessary):**
- `uptime` load average settles **near 0**, not ~4, a minute after boot.
- No `kworker/u8:N` threads stuck in `D` state:
  `for p in /proc/[0-9]*; do [ "$(cut -d" " -f3 $p/stat)" = D ] && echo $p; done`
  returns nothing persistent.
- `dmesg | grep -c "Send Failed"` **stops growing** (sample twice, 60 s apart).
- Modem DMS mode is a normal value (`online`), not `shutting-down`:
  `qmicli -p -d msmipc://0 --dms-get-operating-mode`.
- No spontaneous reboot: leave it 10 min, `uptime` keeps climbing.

**Audio (the actual goal — needs a human to listen):**
- Generate a 48 kHz mono tone and play it:
  ```sh
  python3 -c 'import struct,math,wave;sr=48000;w=wave.open("/tmp/t.wav","w");w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr);w.writeframes(b"".join(struct.pack("<h",int(22000*math.sin(2*math.pi*440*i/sr))) for i in range(sr*2)));w.close()'
  aplay -D hw:0,0 /tmp/t.wav
  ```
- Confirm the tone is **audible and does not cut out mid-stream** (the failure
  signature was the speaker path enabling for ~1.3 s then dying). A quick
  hardware cross-check: while playing, `gpio36` output should stay high for the
  whole tone (read via the `/dev/mem` TLMM helper in `audio_experiments.md`).

## Device access & caveats

- `ssh bq268` (root). IP is DHCP — if unreachable, its address may have changed;
  update `HostName` in `~/.ssh/config`.
- **Do not** `rc-service rmt-storage restart` / `modem restart` on a running
  device to test — per `TASKS.md`, that cascades a modem restart with a stale
  qmi-proxy PID and triggers a **watchdog reboot ~60 s later**. Test via a clean
  reboot instead (`reboot`, then reconnect after ~60–90 s).
- Audio needs the Q6 up (~50 s post-boot: wait for `apr_tal:Modem Is Up`).
