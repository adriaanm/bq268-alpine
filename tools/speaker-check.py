#!/usr/bin/env python3
"""Does the handset's speaker actually make sound? Measured, not assumed.

    tools/speaker-check.py            # exits 0 if the tone was heard
    tools/speaker-check.py --freq 440 --seconds 3

Records the room on this Mac (an external mic in front of the device), plays a
sine on the device over ALSA, and compares the energy in a narrow band around
the tone against a silent baseline taken moments before. A speaker route that
looks right in `amixer` but plays nothing — which is exactly what a
half-initialised card gives you — fails here.

Needs ffmpeg + sox on the host (`brew install ffmpeg sox`) and an input device
whose name matches --mic (default: the Yeti). The device is ssh host $BQ268_HOST
(default bq268).
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

HOST = os.environ.get("BQ268_HOST", "bq268")
# How much the tone's own band must stand out. Both tests are in-recording
# ratios so a noisy room cannot decide the answer on its own: TONE_VS_NOISE
# compares the tone band against a neighbouring band in the SAME recording,
# and TONE_VS_QUIET compares it against the silent baseline. A baseline taken
# while someone was talking made an earlier version of this check report
# "nothing heard" from a perfectly audible speaker.
# Calibrated against a negative control on real hardware (2026-08-07): with
# `RX2 MIX1 INP1` forced to ZERO — the failure this exists to catch — the tone
# band read 0.3-0.4x its neighbour and 1.2x the baseline; playing, it read
# 2.5-5.6x and 4.5-38x. The bar sits between those, not at the top of what a
# well-placed mic can do.
MIN_TONE_VS_NOISE = 1.5
MIN_TONE_VS_QUIET = 2.5


def mic_index(name: str) -> str:
    out = subprocess.run(["ffmpeg", "-f", "avfoundation", "-list_devices", "true",
                          "-i", ""], capture_output=True, text=True).stderr
    audio = out.split("AVFoundation audio devices:")[-1]
    for line in audio.splitlines():
        m = re.search(r"\[(\d+)\] (.+)$", line)
        if m and name.lower() in m.group(2).lower():
            return m.group(1)
    sys.exit(f"speaker-check: no input device matching {name!r}\n{audio}")


def record(idx: str, seconds: float, path: str) -> None:
    subprocess.run(["ffmpeg", "-y", "-f", "avfoundation", "-i", f":{idx}",
                    "-t", str(seconds), "-ac", "1", "-ar", "44100", path],
                   capture_output=True)


def band_rms(path: str, lo: int, hi: int) -> float:
    out = subprocess.run(["sox", path, "-n", "sinc", f"{lo}-{hi}", "stat"],
                         capture_output=True, text=True).stderr
    m = re.search(r"RMS\s+amplitude:\s+([0-9.]+)", out)
    return float(m.group(1)) if m else 0.0


def bands(freq: int):
    """the tone's band, and a neighbouring band it must beat."""
    return (int(freq * 0.93), int(freq * 1.07)), (int(freq * 1.4), int(freq * 2.6))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mic", default="Yeti")
    ap.add_argument("--freq", type=int, default=1000)
    ap.add_argument("--seconds", type=float, default=3.0)
    args = ap.parse_args()

    idx = mic_index(args.mic)
    tmp = tempfile.mkdtemp(prefix="speaker-check.")
    base, tone = os.path.join(tmp, "base.wav"), os.path.join(tmp, "tone.wav")

    tband, nband = bands(args.freq)
    record(idx, args.seconds, base)
    quiet = band_rms(base, *tband)

    play = subprocess.Popen(
        ["ssh", "-o", "ConnectTimeout=10", HOST,
         f"speaker-test -D hw:0,0 -c 1 -t sine -f {args.freq} -l 1 -P 2"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    record(idx, args.seconds, tone)
    played = play.communicate(timeout=30)[0]
    # A play that never happened is not a silent speaker, and the difference
    # matters: PCM-busy (wata holds hw:0,0 while it plays) or a card that is
    # not ready look identical in the microphone.
    if play.returncode != 0:
        print(f"speaker-check: the device could not play it "
              f"(exit {play.returncode}):\n{played.strip()}")
        sys.exit(2)
    loud = band_rms(tone, *tband)
    noise = band_rms(tone, *nband)

    vs_noise = loud / noise if noise > 0 else float("inf")
    vs_quiet = loud / quiet if quiet > 0 else float("inf")
    print(f"speaker-check: {args.freq}Hz band={loud:.6f}  "
          f"neighbouring band={noise:.6f} ({vs_noise:.1f}x)  "
          f"silence={quiet:.6f} ({vs_quiet:.1f}x)")
    if vs_noise >= MIN_TONE_VS_NOISE and vs_quiet >= MIN_TONE_VS_QUIET:
        print("speaker-check: PASS — the device is making sound")
        return
    print(f"speaker-check: FAIL — nothing heard "
          f"(needs {MIN_TONE_VS_NOISE}x over the neighbouring band "
          f"and {MIN_TONE_VS_QUIET}x over silence)")
    # A failure is only useful with the route beside it: the mux dropping back
    # to ZERO is what silences this device, and it is invisible from here.
    print(subprocess.run(
        ["ssh", "-o", "ConnectTimeout=10", HOST,
         'for c in "RX2 MIX1 INP1" "Ext Spk Switch" "RX2 Digital Volume" '
         '"HPHR" "RDAC2 MUX" "PRI_MI2S_RX Audio Mixer MultiMedia1"; do '
         'printf "%-38s " "$c"; amixer -c 0 cget name="$c" 2>/dev/null | '
         'awk "/: values=/{print}"; done'],
        capture_output=True, text=True).stdout)
    sys.exit(1)


if __name__ == "__main__":
    main()
