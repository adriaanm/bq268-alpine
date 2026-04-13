#!/usr/bin/env python3
"""Generate rootfs/files/etc/cellular/roaming-partners from
eskimo_roaming.md + tools/data/mcc-mnc-list.json.

This is a build-time join, run on the buildbox. The runtime file is
checked in so the device doesn't need any of this at boot.

Re-run with `just gen-roaming-partners` after editing the Eskimo list
or bumping the vendored mcc-mnc-list.json.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ESKIMO_MD = REPO / "eskimo_roaming.md"
MCC_JSON = REPO / "tools" / "data" / "mcc-mnc-list.json"
OUT_FILE = REPO / "rootfs" / "files" / "etc" / "cellular" / "roaming-partners"

# Normalisation for fuzzy matching on country names and operator brands.
# Both sides are lowercased, stripped of punctuation, and aliased as needed.
COUNTRY_ALIASES: dict[str, str] = {
    "macedonia": "north macedonia",
    "united states": "united states of america",
    "usa": "united states of america",
    "czech republic": "czechia",
    "south korea": "korea, republic of",
    "korea, south": "korea, republic of",
    "russia": "russian federation",
    "ivory coast": "côte d'ivoire",
    "cote d'ivoire": "côte d'ivoire",
    "cape verde": "cabo verde",
    "east timor": "timor-leste",
    "swaziland": "eswatini",
    "vatican city": "holy see (vatican city state)",
    "hong kong": "hong kong, china",
    "macau": "macao, china",
    "taiwan": "taiwan, china",
    "palestine": "palestinian territory",
    "dr congo": "congo, democratic republic of the",
    "democratic republic of the congo": "congo, democratic republic of the",
    "republic of the congo": "congo",
    "burma": "myanmar",
    "laos": "lao people's democratic republic",
    "bolivia": "bolivia (plurinational state of)",
    "venezuela": "venezuela (bolivarian republic of)",
    "moldova": "moldova, republic of",
    "tanzania": "tanzania, united republic of",
    "syria": "syrian arab republic",
    "iran": "iran (islamic republic of)",
    "brunei": "brunei darussalam",
    "vietnam": "viet nam",
    "st lucia": "saint lucia",
    "st kitts and nevis": "saint kitts and nevis",
    "st vincent and the grenadines": "saint vincent and the grenadines",
    "bosnia and herzegovina": "bosnia and herzegovina",
    "trinidad and tobago": "trinidad and tobago",
}


def norm(s: str) -> str:
    """Fold for comparison: lowercase, strip accents, strip non-alnum,
    collapse spaces.
    """
    import unicodedata
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower().strip()
    s = re.sub(r"[^\w\s]", " ", s, flags=re.UNICODE)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def strip_rat(operator: str) -> str:
    """Remove trailing RAT markers like '5G' / '4G' / 'LTE'."""
    return re.sub(r"\s*(5G|4G|3G|LTE|UMTS)\s*$", "", operator, flags=re.IGNORECASE).strip()


# Eskimo occasionally uses a global-parent name that doesn't appear as
# a brand in pbakondy — translate to the local operating brands to
# match successfully. Values are searched as additional candidates
# alongside the literal eskimo name.
BRAND_PARENTS: dict[str, list[str]] = {
    "telefonica": ["Movistar", "O2", "Vivo"],
    "telefónica": ["Movistar", "O2", "Vivo"],
    "veon": ["Beeline", "Kyivstar", "Banglalink", "Jazz"],
    "airtel": ["Airtel", "Bharti"],
    "cable & wireless": ["FLOW", "Cable & Wireless", "C&W", "LIME"],
    "digicel": ["Digicel"],
    "telia": ["Telia", "LMT"],
    "a1": ["A1", "Vip", "One"],
    "wind": ["Wind", "WindTre", "San Marino Telecom"],
    "mtn": ["MTN"],
    "bemobile": ["bmobile", "Digicel Pacific"],
    "vodafone": ["Vodafone"],
    "zain": ["Zain"],
    "telekom": ["T-Mobile", "Telekom", "Magenta"],
    "orange": ["Orange"],
}

MAX_MATCHES_PER_ENTRY = 4  # cap for brands like Jio with 20+ MCC/MNC rows


def strip_paren(operator: str) -> list[str]:
    """'Bangalink (Veon)' -> ['Bangalink', 'Veon']. Returns all candidates,
    plus any brand-parent aliases for each candidate.
    """
    base = re.sub(r"\s*\(.*?\)\s*", " ", operator).strip()
    aliases = re.findall(r"\(([^)]+)\)", operator)
    out = [base] if base else []
    out.extend(a.strip() for a in aliases if a.strip())
    # Fan out parent brands
    expanded = list(out)
    for c in out:
        cn = norm(c)
        for key, children in BRAND_PARENTS.items():
            if key in cn:
                expanded.extend(children)
    return expanded


@dataclass
class EskimoEntry:
    country: str
    operator: str
    rat: str  # "4G" or "5G" usually


def parse_eskimo_md(path: Path) -> list[EskimoEntry]:
    """Parse '- Country\\n  - Operator RAT' pairs. Skips the prose header."""
    entries: list[EskimoEntry] = []
    current_country: str | None = None
    for raw in path.read_text().splitlines():
        line = raw.rstrip()
        if not line or line.startswith("#"):
            continue
        m_country = re.match(r"^- (.+)$", line)
        m_operator = re.match(r"^\s{2,}- (.+?)\s*(5G|4G|3G)?\s*$", line)
        if m_operator and current_country:
            op = m_operator.group(1).strip()
            rat = m_operator.group(2) or ""
            entries.append(EskimoEntry(current_country, op, rat))
            current_country = None
        elif m_country:
            current_country = m_country.group(1).strip()
    return entries


def load_mcc_mnc(path: Path) -> list[dict]:
    return json.loads(path.read_text())


def country_matches(eskimo_country: str, row_country: str) -> bool:
    a = norm(eskimo_country)
    b = norm(row_country)
    a = COUNTRY_ALIASES.get(a, a)
    b = COUNTRY_ALIASES.get(b, b)
    if a == b:
        return True
    # pbakondy often annotates with parentheticals like "Netherlands
    # (Kingdom of the Netherlands)". Match if the eskimo name is a
    # whole-word prefix of the row name (or vice versa), but don't
    # allow partial-word matches ("Republic" vs "Dominican Republic").
    a_words = a.split()
    b_words = b.split()
    if a_words and b_words:
        if a_words == b_words[: len(a_words)]:
            return True
        if b_words == a_words[: len(b_words)]:
            return True
    return False


def brand_matches(eskimo_op: str, row: dict) -> bool:
    candidates = strip_paren(strip_rat(eskimo_op))
    # Also include the raw eskimo string minus RAT as a candidate
    raw = norm(strip_rat(eskimo_op))
    targets = [
        norm(row.get("brand") or ""),
        norm(row.get("operator") or ""),
    ]
    for cand in candidates:
        cn = norm(cand)
        if not cn:
            continue
        for t in targets:
            if not t:
                continue
            # Substring either direction so "Bouygues" matches
            # "Bouygues Telecom" and vice versa, but not "Vodafone"
            # matching "VodaPhone Test".
            if cn in t or t in cn:
                return True
    # Last-chance: first word of eskimo op vs first word of brand
    ew = raw.split()[:1]
    for t in targets:
        tw = t.split()[:1]
        if ew and tw and ew[0] == tw[0] and len(ew[0]) >= 4:
            return True
    return False


def bands_has_lte(row: dict) -> bool:
    b = (row.get("bands") or "").upper()
    return "LTE" in b or "5G" in b


def resolve(entry: EskimoEntry, db: list[dict]) -> list[dict]:
    """Return matching operational LTE/5G rows for this eskimo entry."""
    matches: list[dict] = []
    for row in db:
        if row.get("status") != "Operational":
            continue
        if not country_matches(entry.country, row.get("countryName") or ""):
            continue
        if not bands_has_lte(row):
            continue
        if not brand_matches(entry.operator, row):
            continue
        matches.append(row)
    return matches


def iso_code(row: dict) -> str:
    cc = row.get("countryCode") or ""
    # pbakondy uses ISO 3166-1 alpha-2. Multi-territory entries come
    # back as "AU/CC/CX" (Australia + Cocos + Christmas); keep only
    # the first code. Region-scoped entries like "GE-AB" drop the
    # region suffix.
    if not cc:
        return "??"
    first = cc.split("/")[0]
    return first.split("-")[0].upper()


def main() -> int:
    if not ESKIMO_MD.exists():
        print(f"error: {ESKIMO_MD} not found", file=sys.stderr)
        return 2
    if not MCC_JSON.exists():
        print(f"error: {MCC_JSON} not found", file=sys.stderr)
        print("       fetch with: curl -sSL -o tools/data/mcc-mnc-list.json \\", file=sys.stderr)
        print("            https://raw.githubusercontent.com/pbakondy/mcc-mnc-list/master/mcc-mnc-list.json", file=sys.stderr)
        return 2

    eskimo = parse_eskimo_md(ESKIMO_MD)
    db = load_mcc_mnc(MCC_JSON)

    unresolved: list[EskimoEntry] = []
    ambiguous: list[tuple[EskimoEntry, int]] = []
    rows_out: list[tuple[str, str, str, str]] = []  # (mcc, mnc, iso, brand)

    for e in eskimo:
        matches = resolve(e, db)
        if not matches:
            unresolved.append(e)
            continue
        if len(matches) > 1:
            ambiguous.append((e, len(matches)))
        # Emit every operational LTE-capable match — Eskimo names one
        # brand per country but a brand can span multiple MCC/MNC
        # entries (e.g. US T-Mobile has several). Cap at
        # MAX_MATCHES_PER_ENTRY to avoid flooding the file with
        # brands like Indian Jio which has 20+ MNCs.
        for m in matches[:MAX_MATCHES_PER_ENTRY]:
            rows_out.append((
                m["mcc"],
                m["mnc"],
                iso_code(m),
                m.get("brand") or m.get("operator") or "?",
            ))

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with OUT_FILE.open("w") as f:
        f.write(
            "# Approved roaming partners — AUTO-GENERATED, DO NOT EDIT.\n"
            "#\n"
            "# Regenerate with: just gen-roaming-partners\n"
            "# (runs tools/gen-roaming-partners.py)\n"
            "#\n"
            "# Provenance:\n"
            "#   - Partner list:  eskimo_roaming.md (extracted from\n"
            "#                    https://www.eskimo.travel/en/network-coverage)\n"
            "#   - MCC/MNC db:    tools/data/mcc-mnc-list.json\n"
            "#                    (vendored pbakondy/mcc-mnc-list)\n"
            "#   - Home SIM:      Eskimo eSIM, MVNO on Singtel IMSI 525-01\n"
            "#\n"
            "# Format: MCC MNC COUNTRY OPERATOR PRIORITY\n"
            "# PRIORITY is fixed at 10 (unused — Eskimo names one partner\n"
            "# per country; multiple MCC/MNC rows mean the brand spans\n"
            "# several network codes and we try all of them).\n"
            "#\n"
            "# cell-data wake uses this as a fallback after automatic\n"
            "# attach fails: `nas-network-scan=lte`, filter visible\n"
            "# networks against the pairs below, attach manually in\n"
            "# order. Non-partner networks are never tried.\n"
            "\n"
            "# MCC MNC COUNTRY OPERATOR                   PRIORITY\n"
        )
        # Sort for stable diffs: by iso, then mcc, mnc
        rows_out.sort(key=lambda r: (r[2], r[0], r[1]))
        for mcc, mnc, iso, brand in rows_out:
            # Normalize brand for shell-safety: no spaces (use hyphens)
            brand_safe = re.sub(r"\s+", "-", brand).replace("&", "and")
            f.write(f"{mcc:<4} {mnc:<3} {iso:<3} {brand_safe:<30} 10\n")

    print(f"wrote {len(rows_out)} MCC/MNC rows for {len(eskimo) - len(unresolved)}/{len(eskimo)} eskimo entries")
    if ambiguous:
        print(f"  {len(ambiguous)} entries matched multiple MCC/MNC pairs (expected for multi-brand operators):")
        for e, n in ambiguous[:10]:
            print(f"    {e.country}: {e.operator} → {n} matches")
        if len(ambiguous) > 10:
            print(f"    … and {len(ambiguous) - 10} more")
    if unresolved:
        # Non-fatal: partial resolution is expected for long-tail
        # territories (crown dependencies, small Pacific islands,
        # brand-name gaps in pbakondy). Report and continue so
        # `just gen-roaming-partners` stays green; fix individual
        # entries by extending BRAND_PARENTS / COUNTRY_ALIASES and
        # re-running.
        print(f"  {len(unresolved)} UNRESOLVED (no MCC/MNC row found):", file=sys.stderr)
        for e in unresolved:
            print(f"    {e.country}: {e.operator} {e.rat}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
