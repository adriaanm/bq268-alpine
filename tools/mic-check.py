#!/usr/bin/env python3
"""Does the handset's microphone actually hear? Measured, not assumed.

    tools/mic-check.py            # exits 0 if the tone was heard
    tools/mic-check.py --freq 1000 --seconds 3

The mirror of speaker-check.py, and it exists because the failure it catches
went unnoticed for a whole session: the codec's `DEC1 MUX` resets to ZERO when
the Q6 comes up, and from then on every voice message the handset records is
silence. It SENDS, it ARRIVES, it plays back as nothing — the only symptom is
that the recipient hears no voice, which is indistinguishable from a kid who
did not speak.

This plays a tone from THIS Mac, records it on the device over ALSA, and
compares the tone's band against a neighbouring band in the same recording.
Both are in-recording ratios, so a quiet room and a loud one give the same
answer.

Needs ffmpeg (for the tone) on the host and arecord on the device, and the
handset in front of the Mac's speakers. The device is ssh host $BQ268_HOST.
"""

import argparse
import math
import os
import re
import struct
import subprocess
import sys
import tempfile
import wave

HOST = os.environ.get("BQ268_HOST", "bq268")
# Calibrated on real hardware (2026-08-07): with `DEC1 MUX` forced to ZERO —
# the failure this exists to catch — the recording is digital silence (peak 0),
# and with the route right the tone band read many times its neighbour. The bar
# sits well below what a working mic manages and well above silence.
MIN_TONE_VS_NOISE = 3.0
MIN_PEAK = 40


def band_energy(samples, rate, lo, hi):
    """Goertzel-ish: sum the power in a band by brute-force DFT over a few
    bins. Cheap, exact enough, and needs no numpy."""
    n = len(samples)
    total = 0.0
    step = max(1, (hi - lo) // 8)
    for f in range(lo, hi + 1, step):
        w = 2 * math.pi * f / rate
        cr = si = 0.0
        for i, s in enumerate(samples):
            cr += s * math.cos(w * i)
            si += s * math.sin(w * i)
        total += (cr * cr + si * si) / (n * n)
    return math.sqrt(total)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--freq", type=int, default=1000)
    ap.add_argument("--seconds", type=float, default=3.0)
    args = ap.parse_args()

    tmp = tempfile.mkdtemp(prefix="mic-check.")
    tone = os.path.join(tmp, "tone.wav")
    subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i",
                    f"sine=frequency={args.freq}:duration={args.seconds + 1}",
                    tone], capture_output=True)

    # start the device recording, then play the tone into the room
    rec = subprocess.Popen(
        ["ssh", "-o", "ConnectTimeout=10", HOST,
         f"arecord -D hw:0,0 -f S16_LE -r 48000 -c 1 -d {int(args.seconds)} /tmp/mic-check.wav"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    subprocess.run(["afplay", tone], capture_output=True)
    out = rec.communicate(timeout=60)[0]
    if rec.returncode != 0:
        print(f"mic-check: the device could not record (exit {rec.returncode}):\n{out.strip()}")
        sys.exit(2)

    local = os.path.join(tmp, "cap.wav")
    if subprocess.run(["scp", "-q", f"{HOST}:/tmp/mic-check.wav", local]).returncode != 0:
        sys.exit("mic-check: could not fetch the recording")

    w = wave.open(local)
    rate, n = w.getframerate(), w.getnframes()
    raw = w.readframes(n)
    s = struct.unpack("<%dh" % (len(raw) // 2), raw)
    peak = max(abs(x) for x in s)
    # one second from the middle is plenty, and keeps the DFT quick
    mid = s[len(s) // 2 - rate // 2: len(s) // 2 + rate // 2]

    f = args.freq
    heard = band_energy(mid, rate, int(f * 0.94), int(f * 1.06))
    other = band_energy(mid, rate, int(f * 1.5), int(f * 2.5))
    ratio = heard / other if other > 0 else float("inf")
    print(f"mic-check: peak={peak}  {f}Hz band={heard:.1f}  "
          f"neighbouring band={other:.1f} ({ratio:.1f}x)")

    if peak < MIN_PEAK:
        print("mic-check: FAIL — the recording is silence. The capture route is "
              "the usual cause; check `DEC1 MUX` (0 = the ADC is disconnected).")
        dump_route()
        sys.exit(1)
    if ratio < MIN_TONE_VS_NOISE:
        print(f"mic-check: FAIL — the mic hears SOMETHING but not the tone "
              f"(needs {MIN_TONE_VS_NOISE}x over the neighbouring band)")
        dump_route()
        sys.exit(1)
    print("mic-check: PASS — the device is hearing")


def dump_route():
    print(subprocess.run(
        ["ssh", "-o", "ConnectTimeout=10", HOST,
         'for c in "DEC1 MUX" "ADC1 Volume" "DEC1 Volume" '
         '"MultiMedia1 Mixer TERT_MI2S_TX"; do printf "%-34s " "$c"; '
         'amixer -c 0 cget name="$c" 2>/dev/null | awk "/: values=/{print}"; done'],
        capture_output=True, text=True).stdout)


main()
