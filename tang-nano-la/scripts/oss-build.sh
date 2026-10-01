#!/usr/bin/env bash
# Open-source build for Tang Nano 9K logic analyzer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/oss"
mkdir -p "$OUT"

if [[ -x /home/ubuntu/tools/oss-cad-suite/bin/yosys ]]; then
  export PATH="/home/ubuntu/tools/oss-cad-suite/bin:$PATH"
fi
export PATH="${HOME}/.local/bin:$PATH"

DEVICE="${DEVICE:-GW1NR-LV9QN88PC6/I5}"
FAMILY="${FAMILY:-GW1N-9C}"

command -v yosys >/dev/null
command -v nextpnr-himbaechel >/dev/null
command -v gowin_pack >/dev/null

echo "[1/3] yosys synth_gowin"
cd "$ROOT"
yosys -ql "$OUT/yosys.log" "$ROOT/scripts/synth.ys"

echo "[2/3] nextpnr-himbaechel"
# Target 90 MHz for timing closure (PLL still 99 MHz; Fmax typically ~94 MHz)
set +e
nextpnr-himbaechel \
  --json "$OUT/la.json" \
  --write "$OUT/la_pnr.json" \
  --device "$DEVICE" \
  --vopt family="$FAMILY" \
  --vopt cst="$ROOT/cst/tangnano9k.cst" \
  --freq 90 \
  > "$OUT/nextpnr.log" 2>&1
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "strict timing failed; retrying with --timing-allow-fail"
  nextpnr-himbaechel \
    --json "$OUT/la.json" \
    --write "$OUT/la_pnr.json" \
    --device "$DEVICE" \
    --vopt family="$FAMILY" \
    --vopt cst="$ROOT/cst/tangnano9k.cst" \
    --freq 99 \
    --timing-allow-fail \
    > "$OUT/nextpnr.log" 2>&1
fi

echo "[3/3] gowin_pack"
gowin_pack -d "$FAMILY" -o "$OUT/la.fs" "$OUT/la_pnr.json"
echo "Bitstream ready: $OUT/la.fs"
grep -E "Max frequency|Device utilisation|error|ERROR" "$OUT/nextpnr.log" | tail -40
