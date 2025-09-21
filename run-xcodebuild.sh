#!/bin/bash
cd "$(dirname "$0")" || exit 1
pkill -f 'volumeHUD' || true
sleep 0.5
xcodebuild -project 'volumeHUD.xcodeproj' -scheme 'volumeHUD' -configuration Debug build
echo 'Starting volumeHUD from Xcode build...'
exec ./build/Debug/volumeHUD
