# DIAG kernel fixes (MSM8909, CAF 4.4)

The BQ268's CAF 4.4 kernel needs three fixes before the Qualcomm DIAG
framework can talk to the MPSS. Without them, `/dev/diag` opens, log
subscriptions appear to go through, but no modem command ever receives
a response and no log events ever arrive. With all three applied, the
DIAG tooling in `tools/` (`cell-diag`, `diag-apdu`, `qmi-send-apdu`)
works end to end.

These fixes live in the sibling kernel repo at `~/bq268-caf-4.4`. This
doc exists to document *why* they're needed and what each one does — the
code itself evolves in the kernel tree, not here.

## Fix 1 — SMD channel pre-registration (kernel #52, commit `034ada814c88`)

The DIAG driver's transport negotiation (SMD vs glink vs socket) never
fires on MSM8909 because only SMD exists. The negotiation path leaves
DATA / CMD / DCI channels unregistered, and the CNTL peripheral-info
struct stays empty. Every subsequent DIAG operation then fails because
it can't find a valid `peripheral_info` entry for the modem.

Fix: pre-register all channels during `diag_smd_init()` and copy
`early_init_info` into `peripheral_info` for CNTL. This skips the
broken negotiation entirely and wires the SMD channels up
unconditionally.

## Fix 2 — Direct feature-mask send (kernel #55)

`diag_cntl_channel_open()` queues `mask_update_work` via the `cntl_wq`
workqueue to send the AP's feature mask to the modem. The queueing
succeeds (`queue_work()` returns true) but the worker thread never
executes it — the kworker pool just doesn't pick it up. Root cause
unknown, likely related to singlethread WQ scheduling on this kernel.

Fix: call `diag_send_updates_peripheral()` directly from
`diag_cntl_channel_open()` instead of via the workqueue. The feature
mask now sends synchronously when the CNTL channel opens, which is
what everything downstream assumes anyway.

## Fix 3 — Modem command fallback forwarding (kernel #55)

After feature-mask exchange, the modem is *supposed* to send
`DIAG_CTRL_MSG_REG` messages on the CNTL channel to register its
command handlers. The MPSS.JO.3.1 firmware on this device never sends
these registrations. Without them, `diag_cmd_search()` returns NULL
and `diag_process_apps_pkt()` drops every command destined for the
modem.

Worse: `process_incoming_feature_mask()` calls
`diag_cmd_remove_reg_by_proc()` which *wipes* any pre-registered
entries once the modem's feature mask arrives, so simply adding
fake registrations in `diag_cntl_channel_open()` doesn't help either.

Fix: add a fallback in `diag_process_apps_pkt()` after
`diag_cmd_search()` returns NULL — if the modem's feature mask has
been received at all, forward the command directly via
`diagfwd_write(PERIPHERAL_MODEM, TYPE_CMD, ...)`. This lets the modem
receive every command byte we send at it, and any commands the modem
doesn't understand get a normal DIAG error code back rather than being
silently dropped.

## DIAG probe results (kernel #55, with all three fixes applied)

```
SS 0x03 WCDMA     error (0x13)   # bad mode — subsystem exists
SS 0x04 GSM       no response    # not present on this firmware
SS 0x06 CM        error (0x13)
SS 0x08 GPS       ALIVE (10 bytes)
SS 0x0A NAS       error (0x14)   # bad parameter
SS 0x0C UIM       error (0x13)
SS 0x13 EFS2      error (0x15)   # bad length (cmd 0x00 needs more data)
SS 0x19 MMGSDI    error (0x13)
SS 0x2D QMI       ALIVE (5 bytes)
SS 0x48 QMI_UIM   error (0x13)
```

EFS2 commands work fully with correct command framing (MKDIR, OPEN,
READ, WRITE, PUT are all functional after SPC unlock). PEEKD/POKED —
the legacy memory-peek / poke commands — are disabled in firmware and
never respond.

## Consumers in this repo

- `tools/cell-diag.c` — LTE log subscription for RRC / NAS analysis.
  Requires all three fixes; without them the log mask SET_MASK is
  accepted silently and no events ever arrive.
- `tools/diag-apdu.c` — raw APDU send via the DIAG MMGSDI subsystem.
  Relies on Fix 3 specifically, since the MMGSDI subsystem never
  registers itself.
- `tools/qmi-send-apdu.c` — userspace daemon for APDU access over
  QMI UIM. Not directly dependent on DIAG but was developed in
  parallel and shares the same debugging workflow.
