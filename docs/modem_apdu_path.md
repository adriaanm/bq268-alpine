# Modem APDU Path — How QMI UIM Talks to the SIM Card

## What we want

Send APDUs to the eUICC's ISD-R applet (AID `A0000005591010...`) via
`qmicli --uim-open-logical-channel` / `--uim-send-apdu`.

## The layers

```
┌─────────────────────────────────────────────────────────┐
│  AP (Linux)                                             │
│  qmicli / lpac  ──QMI──▶  /dev/wwan0qmi0               │
└───────────────────────────┬─────────────────────────────┘
                            │ QMI UIM message
                            ▼
┌─────────────────────────────────────────────────────────┐
│  QMI UIM handler (FUN_c0a15234)                  seg12  │
│                                                         │
│  1. restriction bitmask check ──▶ FUN_c0a16da8          │
│     reads struct+0x7B8 for permission bits              │
│     bit 2 = APDU blocked, bit 8 = extra restriction     │
│     ★ PATCHED: always returns 0 (all bits clear)        │
│                                                         │
│  2. session state check ──▶ FUN_c0717d4c (seg9)         │
│     table[slot][session*0x2C+2] — is session active?    │
│                                                         │
│  3. creates signal, sends to MMGSDI task, waits         │
│     signal mask 0x402, timeout 0x20                      │
│                                                         │
│  4. reads async result from 0xC2149DB4                  │
│     result == -2  →  return 0 (denied → QMI error 82)   │
│     result != -2  →  return 1 (success)                 │
└───────────────────────────┬─────────────────────────────┘
                            │ signal(0x402)
                            ▼
┌─────────────────────────────────────────────────────────┐
│  MMGSDI async callback (FUN_c09caa78)            seg12  │
│                                                         │
│  Receives signal, processes the request:                │
│                                                         │
│  1. FUN_c0a23140 — table lookup (session → request)     │
│  2. FUN_c093b13c — resolve request via dispatch tables  │
│     looks up handler by command type + AID              │
│     ┌──────────────────────────────────────────────┐    │
│     │ dispatch tables at 0xC1F8B588 (22 entries)   │    │
│     │ + dynamic table at 0xC1F8B648                │    │
│     │                                              │    │
│     │ For most AIDs: handler = generic UICC driver │    │
│     │ For ISD-R AID: handler = LPA callback ←──────┼─── │ ★ THIS IS THE FILTER
│     └──────────────────────────────────────────────┘    │
│  3. FUN_c092a1e4 — state machine dispatcher             │
│     calls handler via request->callback[0x20]           │
│     ┌─────────────────────────────────────┐             │
│     │ if callback != NULL:                │             │
│     │   r16 = 0xFE  (pre-set return = -2)│             │
│     │   callr callback                   │             │
│     │   return sxtb(r16) = -2 (DENIED)   │             │
│     │                                     │             │
│     │ if callback == NULL:                │             │
│     │   (falls through to generic path)  │             │
│     └─────────────────────────────────────┘             │
│                                                         │
│  result written to 0xC2149DB4, signal fired back        │
└─────────────────────────────────────────────────────────┘
                            │
                            │ (only reached for non-LPA AIDs)
                            ▼
┌─────────────────────────────────────────────────────────┐
│  Generic UICC driver                                    │
│                                                         │
│  Sends actual ISO 7816 commands to the SIM card:        │
│  - MANAGE CHANNEL (open logical channel)                │
│  - SELECT (by AID)                                      │
│  - subsequent APDUs on that channel                     │
│                                                         │
│  This is where non-ISD-R AIDs go. They reach the card   │
│  and get back real responses (SimFileNotFound, etc.)    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  LPA subsystem (modem's built-in eSIM stack)     seg12  │
│                                                         │
│  Code at 0xC0F0F000–0xC0F13A00                          │
│  Own AID table at 0xC27EE290 (private, 10 slots)        │
│  ISD-R AID data at 0xC1CD0678 in b14                    │
│                                                         │
│  At boot:                                               │
│  - FUN_c0f11758 copies ISD-R AID from 0xC1CD0678        │
│    into LPA structures                                  │
│  - Registers callback in MMGSDI dispatch table          │
│    (the callback at request+0x20)                       │
│                                                         │
│  When ISD-R APDU comes in:                              │
│  - MMGSDI routes it here instead of to the card         │
│  - LPA handles it internally (or rejects it)            │
│  - State machine returns -2 regardless                  │
│                                                         │
│  Uses QMI services:                                     │
│  - /lpa/store_data_resp_from_card                       │
│  - /lpa/asn...                                          │
│  - cancelSessionResponse, pendingNotification, etc.     │
└─────────────────────────────────────────────────────────┘
```

## Why non-ISD-R AIDs work (after bitmask patch)

```
qmicli open_logical_channel(AID=A000000003...)
  → QMI handler: bitmask check passes (patched) ✓
  → signal → MMGSDI callback
  → FUN_c093b13c: looks up AID in dispatch tables
  → no registered handler for this AID
  → callback pointer at request+0x20 is NULL
  → state machine takes generic path (callback == NULL)
  → generic UICC driver sends MANAGE CHANNEL + SELECT to card
  → card responds: "6A82" (file not found — AID doesn't exist on this card)
  → result written to 0xC2149DB4 (not -2)
  → QMI handler returns success
  → qmicli gets response with card's SW1/SW2
```

## Why ISD-R AID is blocked

```
qmicli open_logical_channel(AID=A0000005591010...)
  → QMI handler: bitmask check passes (patched) ✓
  → signal → MMGSDI callback
  → FUN_c093b13c: looks up AID in dispatch tables
  → MATCH: LPA registered a handler for ISD-R AID
  → callback pointer at request+0x20 = LPA handler
  → state machine: r16=0xFE, calls LPA handler, returns -2
  → -2 written to 0xC2149DB4
  → QMI handler: result == -2 → returns 0 → QMI error 82 (AccessDenied)
```

## Patch options to unblock ISD-R

### Option C: prevent LPA from registering (preferred)

Prevent the LPA from registering its handler in the MMGSDI dispatch
table. Then ISD-R AID is treated like any other AID — goes through
the generic UICC driver and reaches the card.

**Where**: the LPA init code that registers the callback. Likely in
FUN_c0f11758 or a function it calls. Need to find the exact call
that writes the LPA handler pointer into the dispatch table.

**Effect**: ISD-R AID flows through the generic path. Card receives
MANAGE CHANNEL + SELECT. Card responds normally. Clean.

**Risk**: the modem's LPA becomes non-functional (can't manage eSIM
profiles internally). This is fine — we use lpac on the AP instead.

### Option B: ignore -2 result in async callback

NOP the error check at b12 offset 0x0D5ABC.

**Effect**: MMGSDI still routes to LPA, LPA callback still runs, but
the -2 result is ignored. Async callback reports success.

**Risk**: the LPA callback intercepted the request — it never sent
MANAGE CHANNEL to the card. So there's no actual logical channel.
Subsequent send_apdu would fail because the channel doesn't exist.

### Option A: change state machine return

Change `r16 = #0xfe` to `r16 = #0x0` at b12 offset 0xE40F18.

**Effect**: same as B but broader — ALL callback-dispatched requests
return success. Same risk: no actual channel opened.

## Conclusion

**Option C is the right approach.** The others fake success without
actually talking to the card. We need to find where the LPA registers
its ISD-R handler callback and NOP that registration.
