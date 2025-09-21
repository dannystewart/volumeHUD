#!/bin/bash
cd "$(dirname "$0")" || exit 1
pkill -f 'Volume HUD' || true
sleep 0.5
xcodebuild -project 'Volume HUD.xcodeproj' -scheme 'Volume HUD' -configuration Debug build
echo 'Starting Volume HUD from Xcode build...'
exec ./build/Debug/Volume\ HUD
