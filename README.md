# volumeHUD

A simple macOS app that displays a volume overlay when you change your volume, just like it used to.

## Why This Exists

With macOS Tahoe, Apple has completely revamped Control Center, and as part of this they decided to replace the nice, reliable volume indicator of 25 years with a tiny popover in the corner of the screen, even smaller than a notification. It is barely visible, especially against light backgrounds, and it disappears faster than I remember where to look for it. Even after months on the Tahoe beta, I still can't get used to it and I still don't like it.

So I felt compelled to pick up Xcode and write my first ever Mac app to bring back the classic macOS volume experience we all know and love (except Apple, apparently). The features are not terribly exciting because they're exactly what the old one did:

- Shows a nice overlay with volume bars and speaker icon
- Appears on volume change and disappears a few moments later
- Uses standard macOS materials and SF Symbols to ensure a native look
- Runs transparently in the background

## What It Looks Like

<img src="volumeHUD.gif" alt="volumeHUD Demo" height="300"></img>

## How to Use It

The app is available for download from the [Releases](https://github.com/dannystewart/volumeHUD/releases) page. Even better, you can install it via Homebrew:

```bash
brew install dannystewart/apps/volumehud
```

You can also build it yourself if you're so inclined. Just clone the repo, open `volumeHUD.xcodeproj`, and build. Note that you'll need Xcode 16.

Place the app in your Applications folder (or wherever) and run it. I hate gratuitous menu bar icons and I have no desire to inflict more of them upon myself or you, so there is no UI. You can quit the app by simply launching it again.

To run on startup, you can add it to **System Settings** > **General** > **Login Items & Extensions** > **Open at Login**.

## Permissions

The app will ask you for two permissions, both of which are completely optional:

- **Accessibility (Input Monitoring):** Without this, the HUD won't be shown if you press volume down when at 0% or volume up when at 100%, because there are no volume changes to detect. To get that, it needs to watch for key presses. You're free to leave this off and you just won't have that functionality, but everything else will still work fine.
- **Notifications:** A notification is displayed on first run to say the app has started and explain how to quit. After that, it's not shown again. There is also a notification when you quit, because otherwise it can be unclear that you did. You're free to leave notifications off if you don't find them helpful.

## License

This project is open source under the [MIT License](./LICENSE). Feel free to do what you like with it, or contribute!
