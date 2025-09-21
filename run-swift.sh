#!/bin/bash
cd "$(dirname "$0")" || exit 1
pkill -f 'Volume HUD' || true
sleep 0.5
swift build
echo 'Starting Volume HUD...'
exec ./.build/arm64-apple-macosx/debug/Volume\ HUD
