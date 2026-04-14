#!/usr/bin/env python3
"""
Decode BCCH_DL_SCH PDUs captured by tools/cell-diag and emit a per-cell
summary: PLMN list, cellBarred, intraFreqReselection,
cellReservedForOperatorUse, q-RxLevMin, trackingAreaCode, cellIdentity.

Usage:
    tools/decode-bcch.py cell-diag-lte.log

The 0xB0C0 LTE_RRC_OTA payload layout for ver=13 on MSM8909 firmware,
determined empirically by hex-dumping the payload and lining up known
fields (pci, earfcn, channel_type):

    [0]       ver = 0x0d
    [1]       rrc_release (e.g. 12)
    [2..3]    ?
    [4..5]    pci u16 LE
    [6..9]    earfcn u32 LE
    [10..11]  ?
    [12]      channel_type (BCCH_DL_SCH=2, ...)
    [13..16]  ? (changes per frame; looks like sib-mask u32)
    [17..18]  pdu_len u16 LE (2 larger than actual remaining bytes,
              reason unclear but consistent across all frames)
    [19..]    RRC PDU (uPER-encoded BCCH-DL-SCH-Message)

We just slice [19:] and feed to pycrate's LTE RRC decoder — any trailing
garbage is harmless because uPER stops at the SEQUENCE terminator.
"""
import json
import sys
from pycrate_asn1dir import RRCLTE

BCCH = RRCLTE.EUTRA_RRC_Definitions.BCCH_DL_SCH_Message


def decode_pdu(hex_pdu):
    data = bytes.fromhex(hex_pdu)
    try:
        BCCH.from_uper(data)
    except Exception as e:
        return None, f"decode error: {e}"
    return BCCH(), None


def plmn_str(plmn_id):
    """plmn_id is a dict with mcc and mnc fields (sequences of digits)."""
    mcc = "".join(str(d) for d in plmn_id["mcc"])
    mnc = "".join(str(d) for d in plmn_id["mnc"])
    return f"{mcc}/{mnc}"


def summarize_sib1(sib1):
    info = {
        "plmns": [],
        "tac": None,
        "cell_id": None,
        "cell_barred": None,
        "intra_freq_reselection": None,
        "csg_indication": None,
        "q_rx_lev_min": None,
        "freq_band_indicator": None,
    }
    cell_access = sib1.get("cellAccessRelatedInfo", {})
    for entry in cell_access.get("plmn-IdentityList", []):
        pid = entry.get("plmn-Identity", {})
        mcc = pid.get("mcc")
        mnc = pid.get("mnc", [])
        mcc_str = "".join(str(d) for d in mcc) if mcc else "???"
        mnc_str = "".join(str(d) for d in mnc)
        reserved = entry.get("cellReservedForOperatorUse")
        info["plmns"].append(f"{mcc_str}/{mnc_str}{'(OP-RESERVED)' if reserved == 'reserved' else ''}")
    tac = cell_access.get("trackingAreaCode")
    if isinstance(tac, tuple) and len(tac) == 2:
        info["tac"] = f"0x{tac[0]:04x}"
    cell_id = cell_access.get("cellIdentity")
    if isinstance(cell_id, tuple) and len(cell_id) == 2:
        info["cell_id"] = f"0x{cell_id[0]:07x}"
    info["cell_barred"] = cell_access.get("cellBarred")
    info["intra_freq_reselection"] = cell_access.get("intraFreqReselection")
    info["csg_indication"] = cell_access.get("csg-Indication")
    sel = sib1.get("cellSelectionInfo", {})
    info["q_rx_lev_min"] = sel.get("q-RxLevMin")
    info["freq_band_indicator"] = sib1.get("freqBandIndicator")
    return info


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    path = sys.argv[1]

    per_cell = {}
    decoded = 0
    sib1_found = 0
    other_found = 0
    errors = 0

    with open(path) as f:
        for line in f:
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("event") != "LTE_RRC_OTA":
                continue
            if rec.get("ch_name") != "BCCH_DL_SCH":
                continue
            raw = rec.get("raw")
            if not raw:
                continue
            if len(raw) < 40:
                continue
            pdu_hex = raw[38:]  # skip 19 bytes = 38 hex chars
            if not pdu_hex:
                continue
            decoded += 1
            obj, err = decode_pdu(pdu_hex)
            if err:
                errors += 1
                continue
            # Outer CHOICE: message.c1 / messageClassExtension
            msg = obj["message"]
            if not isinstance(msg, tuple) or msg[0] != "c1":
                other_found += 1
                continue
            c1 = msg[1]
            if not isinstance(c1, tuple):
                other_found += 1
                continue
            inner_name, inner_val = c1
            if inner_name != "systemInformationBlockType1":
                other_found += 1
                continue
            sib1_found += 1
            info = summarize_sib1(inner_val)
            key = (rec["pci"], rec["earfcn"])
            per_cell[key] = info  # last-seen wins

    print(f"records with hex: {decoded}  decode-errors: {errors}")
    print(f"SIB1 found: {sib1_found}   other (SI msg): {other_found}")
    print()
    for (pci, earfcn), info in sorted(per_cell.items()):
        print(f"PCI={pci:4d} EARFCN={earfcn:5d}")
        print(f"  PLMNs            : {', '.join(info['plmns']) or '-'}")
        print(f"  TAC              : {info['tac']}")
        print(f"  Cell ID          : {info['cell_id']}")
        print(f"  cellBarred       : {info['cell_barred']}")
        print(f"  intraFreqResel   : {info['intra_freq_reselection']}")
        print(f"  csg-Indication   : {info['csg_indication']}")
        print(f"  q-RxLevMin       : {info['q_rx_lev_min']}")
        print(f"  freqBandIndicator: {info['freq_band_indicator']}")
        print()


if __name__ == "__main__":
    main()
