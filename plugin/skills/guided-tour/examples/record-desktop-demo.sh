#!/bin/bash
# Desktop demo recorder — one approval, one artifact.
#
#   record-desktop-demo.sh <take-script> <out.mp4> [seconds] [prep-script]
#
# Everything needing macOS automation or screen capture lives behind this single
# entrypoint, so the harness prompts once instead of once per osascript call.
# Each prompt steals focus, and a stolen focus ruins a take — that is the whole
# reason this is one script.
#
# Allowlist it by path rather than allowlisting `osascript -e *`, which would
# grant blanket machine automation to every future tool call:
#   "Bash(bash /absolute/path/to/record-desktop-demo.sh:*)"
#
# Env:
#   SCREEN_DEV  avfoundation screen index (default: auto-detected)
#   FPS         capture framerate (default 30)
#   WIDTH       output width (default 1440; retina capture is ~3600 and huge)
set -uo pipefail

TAKE=${1:?usage: record-desktop-demo.sh <take-script> <out.mp4> [seconds] [prep-script]}
OUT=${2:?usage: record-desktop-demo.sh <take-script> <out.mp4> [seconds] [prep-script]}
MAX=${3:-60}
PREP=${4:-}
FPS=${FPS:-30}
WIDTH=${WIDTH:-1440}
RAW="${OUT%.mp4}.raw.mov"

command -v ffmpeg >/dev/null || { echo "ffmpeg not installed" >&2; exit 1; }

# Screen Recording permission is PER BINARY: `screencapture` being denied says
# nothing about ffmpeg. A denial is silent — no file, no stderr — so the run is
# asserted below rather than assumed.
if [ -z "${SCREEN_DEV:-}" ]; then
  SCREEN_DEV=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
    | sed -n 's/.*\[\([0-9]*\)\] Capture screen 0.*/\1/p' | head -1)
fi
[ -n "$SCREEN_DEV" ] || { echo "no 'Capture screen' avfoundation device found" >&2; exit 1; }

# --- prep, deliberately BEFORE the recorder rolls -------------------------
# Reset state, clear the terminal, pin the target tab, warm the page. Anything
# done after ffmpeg starts is in the video — including the operator's editor.
if [ -n "$PREP" ]; then
  bash "$PREP" || { echo "prep failed" >&2; exit 1; }
  sleep 1
fi

# --- record ---------------------------------------------------------------
rm -f "$RAW"
ffmpeg -y -loglevel error -f avfoundation -capture_cursor 1 -framerate "$FPS" \
  -i "${SCREEN_DEV}:none" -t "$MAX" "$RAW" >/dev/null 2>&1 &
FF=$!
sleep 1.2
bash "$TAKE" 2>&1 | tail -2
sleep 0.8
kill -INT $FF 2>/dev/null; wait $FF 2>/dev/null

[ -s "$RAW" ] || { echo "capture produced nothing — Screen Recording likely denied to ffmpeg" >&2; exit 1; }

# --- trim + encode --------------------------------------------------------
# Natural speed, always. Shorten by tightening the take script, never with
# setpts — a sped-up demo reads as "too fast" to every reviewer.
DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$RAW")
END=$(echo "$DUR - 0.9" | bc)
ffmpeg -y -loglevel error -ss 1.0 -to "$END" -i "$RAW" \
  -vf "scale=${WIDTH}:-2,fps=${FPS},format=yuv420p" -an \
  -c:v libx264 -preset slow -crf 24 -movflags +faststart "$OUT"
rm -f "$RAW"

# Verify by looking, not by file size. Every bad take is caught here and nowhere else.
SHEET="${OUT%.mp4}.sheet.png"
ffmpeg -y -v error -i "$OUT" -vf "fps=1/3,scale=430:-1,tile=4x3" -frames:v 1 "$SHEET"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT" \
  | xargs printf 'wrote %s (%.1fs)\n' "$OUT"
echo "contact sheet: $SHEET  <- open this before shipping the video"
