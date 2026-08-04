#!/usr/bin/env bash
pkill -x SpeechX 2>/dev/null || true
sleep 0.3
open SpeechX.app
echo "SpeechX launched. If hotkey doesn't work, re-toggle in:"
echo "  System Settings → Privacy & Security → Accessibility"
