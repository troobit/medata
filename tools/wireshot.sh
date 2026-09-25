#!/bin/bash
# Render a wireframe option to a PNG at true iPhone 16 Pro metrics.
#
# The wireframe library made options cheap to WRITE — roughly 100 lines of HTML
# against the 542, 1,565 and 1,015 lines of Swift the three insulin-dosing
# attempts cost. It did not make them cheap to LOOK AT, and "costly to compare"
# is one of the three costs the spec exists to remove. This is the render step:
# it gets an option to the point of being worth looking at.
#
# It does NOT replace the gate. The gate is a person looking at the screen of an
# iPhone 16 Pro, and nothing here moves it. A PNG from headless Chrome says
# nothing about Dynamic Type, safe-area insets or ViewThatFits (requirements.md
# limit L4); it says only that the layout and the hierarchy are what you meant.
#
#   make wireshot SURFACE=insulin-dose                 # every attempt-*.html
#   make wireshot SURFACE=insulin-dose ATTEMPT=2       # just attempt-2.html
#
# Written for system bash 3.2.57. Requires Google Chrome; no Node, no npm.

set -u

SURFACE="${SURFACE:-}"
ATTEMPT="${ATTEMPT:-}"
OUT_DIR="${OUT_DIR:-tmp/wireshot}"

# An attempt-*.html is a PAGE — a `.stage` carrying a heading, the note saying
# what the option is testing, and inside it a `.device` at
# --device-w/--device-h = 402x874. So the window is sized to fit the page, not
# the phone. The phone inside it stays at exactly 402x874 CSS px, which at
# scale 3 is 1206x2622 device pixels: the same frame an iPhone 16 Pro
# screenshot produces. A distance measured on the device frame and divided by 3
# is the value to write in Swift.
#
# Widen SHOT_W for an attempt that renders two frames side by side.
SHOT_W="${SHOT_W:-1220}"
SHOT_H="${SHOT_H:-1500}"
SCALE="${SCALE:-3}"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

if [ -z "$SURFACE" ]; then
  echo "usage: make wireshot SURFACE=<surface> [ATTEMPT=<n>] [OUT_DIR=<dir>]" >&2
  echo "       surfaces available:" >&2
  ls -1 design-system/wireframes 2>/dev/null | sed 's/^/         /' >&2
  exit 2
fi

if [ ! -x "$CHROME" ]; then
  echo "wireshot: no Chrome at $CHROME" >&2
  echo "          install Google Chrome, or pass CHROME=<path to a Chromium binary>" >&2
  exit 127
fi

SRC_DIR="design-system/wireframes/$SURFACE"
if [ ! -d "$SRC_DIR" ]; then
  echo "wireshot: no such surface directory: $SRC_DIR" >&2
  exit 2
fi

if [ -n "$ATTEMPT" ]; then
  FILES="$SRC_DIR/attempt-$ATTEMPT.html"
  if [ ! -f "$FILES" ]; then
    echo "wireshot: no such attempt: $FILES" >&2
    exit 2
  fi
else
  FILES=$(ls -1 "$SRC_DIR"/attempt-*.html 2>/dev/null)
  if [ -z "$FILES" ]; then
    echo "wireshot: no attempt-*.html under $SRC_DIR" >&2
    exit 2
  fi
fi

mkdir -p "$OUT_DIR/$SURFACE"
count=0

# One scratch profile for the whole run, kept off any running Chrome profile.
profile=$(mktemp -d)
trap 'rm -rf "$profile"' EXIT

# Chrome 154 writes the PNG and then does not exit: measured on 2026-09-26, the
# file was complete one second after launch and the process was still alive 91
# seconds later. Waiting on it hangs the run after the first render, with the
# file you asked for already on disk. So the render is backgrounded and reaped:
# poll until the PNG exists and has stopped growing, then kill the browser.
# TIMEOUT is the ceiling in seconds for one render, after which it is a failure.
TIMEOUT="${TIMEOUT:-60}"

for f in $FILES; do
  base=$(basename "$f" .html)
  png="$OUT_DIR/$SURFACE/$base.png"
  rm -f "$png"
  "$CHROME" \
    --headless \
    --disable-gpu \
    --no-first-run \
    --no-default-browser-check \
    --hide-scrollbars \
    --force-color-profile=srgb \
    --user-data-dir="$profile" \
    --window-size="$SHOT_W,$SHOT_H" \
    --force-device-scale-factor="$SCALE" \
    --screenshot="$png" \
    "file://$(pwd)/$f" >/dev/null 2>&1 &
  chrome_pid=$!

  waited=0
  settled=0
  last_size=-1
  while [ "$waited" -lt "$TIMEOUT" ]; do
    if [ -f "$png" ]; then
      size=$(wc -c < "$png" | tr -d ' ')
      if [ "$size" = "$last_size" ] && [ "$size" != "0" ]; then
        settled=1
        break
      fi
      last_size="$size"
    fi
    sleep 1
    waited=$((waited + 1))
  done

  kill "$chrome_pid" 2>/dev/null
  wait "$chrome_pid" 2>/dev/null

  if [ ! -f "$png" ] || [ "$settled" != "1" ]; then
    echo "wireshot: failed to render $f within ${TIMEOUT}s" >&2
    exit 1
  fi
  echo "wireshot surface=$SURFACE attempt=$base out=$png window=${SHOT_W}x${SHOT_H}@${SCALE}x device=402x874"
  count=$((count + 1))
done

echo "wireshot rendered=$count"
