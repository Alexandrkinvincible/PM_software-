#!/usr/bin/env bash
# Render every HTML source in docs/build/ to a PDF in docs/.
# Chromium is used directly rather than a PDF library so the page is laid
# out by the same engine that previews it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CHROME="${CHROME:-}"
if [[ -z "$CHROME" ]]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" \
    "$(command -v chromium || true)" \
    "$(command -v google-chrome || true)"; do
    [[ -x "$candidate" ]] && CHROME="$candidate" && break
  done
fi
[[ -n "$CHROME" ]] || { echo "No Chrome/Chromium found. Set CHROME=/path/to/chrome"; exit 1; }

render() {
  local src="$1" out="$2"
  echo "==> $out"
  "$CHROME" --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
    --print-to-pdf="$ROOT/docs/$out" "file://$ROOT/docs/build/$src" 2>/dev/null
}

render phase0.html Phase0_Build_Package.pdf
render phase1.html Phase1_Completion.pdf
render phase2.html Phase2_Action_Plan.pdf
