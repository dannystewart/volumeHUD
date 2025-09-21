#!/bin/bash
cd "$(dirname "$0")" && cd .. || exit 1
pkill -f 'volumeHUD' || true
sleep 0.5
swift build
echo 'Starting volumeHUD...'
exec ./.build/arm64-apple-macosx/debug/volumeHUD
