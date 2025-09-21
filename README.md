# volumeHUD

A simple macOS app that displays a volume overlay when you change your volume, just like it used to.

## Why This Exists

With macOS Tahoe, Apple has completely revamped Control Center, and as part of this they decided to replace the nice, reliable volume indicator of 25 years with a tiny popover beneath the Control Center icon about the size of a notification. It is barely visible, especially against light backgrounds, and it disappears faster than I remember where to look. Even after months on the Tahoe beta, I still can't get used to it and I still don't like it.

It bothered me so much that I felt compelled to pick up Xcode and write my first ever Mac app to bring back the classic macOS volume experience we all know and love (except for Apple, apparently).

## What It Looks Like

<img src="volumeHUD.gif" alt="volumeHUD Demo" height="300"></img>

## What It Does

Things it does that aren't very interesting because they're exactly what the old volume HUD did:

- **Actually Visible Volume Indicator**: Shows a nice HUD with volume bars and speaker icon
- **Visible Mute Indication**: Displays a muted speaker icon when audio is muted
- **Non-Intrusive Yet Still Obvious**: Appears when volume changes then automatically disappears
- **Background Operation**: Runs in the background without taking focus from other apps
- **Modern Design**: Uses standard macOS materials and SF Symbols for a native look

## How It Works

Once running, the app will:

- Monitor your system volume changes in the background
- Display a HUD overlay when you adjust volume using keyboard shortcuts or system controls
- Show different speaker icons based on volume level (low, medium, high)
- Display volume bars that fill based on the current volume level
- Show a muted speaker icon when audio is muted
- Automatically hide the HUD a second after adjustment stops

The HUD appears in the lower portion of your screen and won't interfere with your workflow, but not at the expense of you actually being able to see it.

## How to Use

This requires macOS 26 or later (you don't need it prior to that anyway) and Xcode 16 to build it.

1. Clone this repository:

```bash
git clone https://github.com/dannystewart/volumeHUD.git
cd volumeHUD
```

2. Open `volumeHUD.xcodeproj` project in Xcode
3. Build and run (⌘R), or you can just build it with ⌘B.

There are also build scripts:

```bash
./scripts/run-swift.sh       # Build and run with Swift Package Manager
./scripts/run-xcodebuild.sh  # Build with xcodebuild
```

## Known Issues

- There's currently no GUI to quit the app. Use `pkill -f volumeHUD`.
- The HUD won't show if you press volume down when at 0% or volume up when at 100% because there's no volume change to detect. I'd need to watch for key presses, which I haven't figured out how to do and would require Accessibility permissions which I'm hesitant to request.

## License

This project is open source under the [MIT License](./LICENSE). Feel free to do what you like with it, or contribute!
