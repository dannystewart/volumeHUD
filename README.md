# volumeHUD

A simple macOS app that displays a volume overlay when you change your volume, just like it used to.

## Why This Exists

With macOS Tahoe, Apple has revamped Control Center, and as part of this they decided to replace the nice reliable volume indicator of 25 years with a tiny popover in the corner of the screen that's even smaller than a notification. It's barely visible, especially against light backgrounds, and it disappears faster than I remember where to look for it. Even after months on the Tahoe beta, I still haven't gotten used to it. It's bad UI.

So I did what any sane person would do: I picked up Xcode and wrote my first ever Mac app to bring back the classic macOS volume experience we all know and love (except Apple, apparently). It does what any good volume indicator should do: it tells you what your volume is when you change it and then it goes away. And get this—you can actually *see it*. A groundbreaking feature in 2025.

## What It Looks Like

<img src="volumeHUD.gif" alt="volumeHUD Demo" height="300"></img>

As of version 2.0, the app now offers a brightness HUD that works the same way.

## How to Use It

### Installation

You can get it from the repo, but I strongly recommend installing via Homebrew:

```bash
brew install dannystewart/apps/volumehud
```

The app does have a simple update check on the About screen, but Homebrew makes updating much easier so you don't have to think about it.

### Interface

The app has an interface you can access by launching it a second time. It's a simple About box with a button to quit. It will also tell you if an update is available.

To run on startup, you can add it to **System Settings** > **General** > **Login Items & Extensions** > **Open at Login**.

### Permissions

The app will ask for two permissions, both of which are **completely optional:**

- **Accessibility:** The app works by detecting changes to volume and brightness. This means the HUD won't appear when you try to go below 0% or above 100% because the levels don't change. Input monitoring works around this by watching for key presses. That's the only thing you'll lose if you leave it off.
- **Notifications:** Notifications are used only to tell you that the app has started. It only happens when the app is launched manually, not if it's set to run on startup.

## License

This project is open source under the [MIT License](./LICENSE). Feel free to do what you like with it, or contribute!

<a href="https://www.buymeacoffee.com/dannystewart" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-blue.png" alt="Buy Me A Coffee" height="41" width="174"></a>
