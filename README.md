# volumeHUD

A simple macOS app that displays a volume overlay when you change your volume, just like it used to.

## Why This Exists

With macOS Tahoe, Apple has completely revamped Control Center, and as part of this they decided to replace the nice, reliable volume indicator of 25 years with a tiny popover beneath the Control Center icon about the size of a notification. It is barely visible, especially against light backgrounds, and it disappears faster than I remember where to look for it. Even after months on the Tahoe beta, I still can't get used to it and I still don't like it.

So I felt compelled to pick up Xcode and write my first ever Mac app to bring back the classic macOS volume experience we all know and love (except Apple, apparently). The features are not terribly exciting because they're exactly what the old one did:

- Shows a nice overlay with volume bars and speaker icon
- Appears on volume change and disappears a few moments later
- Uses standard macOS materials and SF Symbols to ensure a native look
- Runs transparently in the background _(but note point 1 under [Known Issues](#known-issues))_

## How to Use It

The app is available for download from the [Releases](https://github.com/dannystewart/volumeHUD/releases) page. Just place it in your Applications folder (or wherever) and run it. To have it run on startup, you can add it to **System Settings** > **General** > **Login Items & Extensions** > **Open at Login**.

### Building with Xcode

You can also build it yourself, if you're so inclined. You'll need Xcode 16. Just clone the repository:

```bash
git clone https://github.com/dannystewart/volumeHUD.git
```

Open `volumeHUD.xcodeproj` in Xcode and either **Build and Run** (⌘R) or just **Build** (⌘B).

## What It Looks Like

<img src="volumeHUD.gif" alt="volumeHUD Demo" height="300"></img>

## Known Issues

1. There's currently no GUI to quit the app. Use `pkill -f volumeHUD`.
2. The HUD won't show if you press volume down when at 0% or volume up when at 100% because there's no volume change to detect. I'd need to watch for key presses, which I haven't figured out how to do and would require Accessibility permissions which I'm hesitant to request.

## License

This project is open source under the [MIT License](./LICENSE). Feel free to do what you like with it, or contribute!
