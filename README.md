# volumeHUD

A simple macOS app that displays a volume overlay when you change your volume, just like it used to.

## Why This Exists

With macOS Tahoe, Apple has revamped Control Center, and as part of this they decided to replace the nice reliable volume indicator of 25 years with a tiny popover in the corner of the screen that's even smaller than a notification. It's barely visible, especially against light backgrounds, and it disappears faster than I remember where to look for it. Even after months on the Tahoe beta, I still haven't gotten used to it. It's bad UI.

So I did what any sane person would do: I picked up Xcode and wrote my first ever Mac app to bring back the classic macOS volume experience we all know and love (except Apple, apparently). It does what any good volume indicator should do: it tells you what your volume is when you change it and then it goes away. And get this—you can actually *see it*. A groundbreaking feature in 2025.

## What It Looks Like

<img src="volumeHUD.gif" alt="volumeHUD Demo" height="300"></img>

## How to Use It

### Installation

You can get it from the repo, but I **strongly recommend** installing via Homebrew:

```bash
brew install dannystewart/apps/volumehud
```

The app has no updater, but Homebrew keeps you updated. It's my first Swift app, so there will be bug fixes!

### Interface

I have no desire to inflict gratuitous menu bar icons on you (or me), so there is no UI. To quit, just launch the app a second time, like how some apps show their settings when they don't have an icon.

To run on startup, you can add it to **System Settings** > **General** > **Login Items & Extensions** > **Open at Login**.

### Permissions

The app will ask for two permissions, both of which are **completely optional:**

- **Accessibility:** The app works by detecting volume changes, so the HUD doesn't appear when you press volume down at 0% or volume up at 100% because the volume doesn't change. Input monitoring works around that by watching for key presses. That's the only thing you'll lose if you leave it off.
- **Notifications:** A single notification is displayed on first run to say the app has started and explain how to quit. After that, it's not shown again. There is also a notification when you quit, because otherwise it may not be clear that you actually did. You're free to leave them off if you don't find them helpful.

## License

This project is open source under the [MIT License](./LICENSE). Feel free to do what you like with it, or contribute!

<a href="https://www.buymeacoffee.com/dannystewart" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-blue.png" alt="Buy Me A Coffee" height="41" width="174"></a>
