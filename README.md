# volumeHUD

A simple macOS app that displays a volume overlay when you change your volume, just like it used to.

## Why This Exists

With macOS Tahoe, Apple has revamped Control Center, and as part of this they decided to replace the nice reliable volume indicator of 25 years with a tiny popover in the corner of the screen that's even smaller than a notification. It's barely visible, especially against light backgrounds, and it disappears faster than I remember where to look for it. Even after months on the Tahoe beta, I still haven't gotten used to it. It's bad UI, period.

So I did what any sane person would do: I picked up Xcode and wrote my first ever Mac app to bring back the classic macOS volume experience we all know and love (except Apple, apparently). It does what any good volume indicator should do: it tells you what your volume is when you change it and then it goes away. And get this—you can actually *see it*. A groundbreaking feature in 2025.

## What It Looks Like

<img src="volumeHUD.gif" alt="volumeHUD Demo" height="300"></img>

## How to Use It

You can build it from the repo, download it from the [Releases](https://github.com/dannystewart/volumeHUD/releases) page, or, best of all, install it via Homebrew:

```bash
brew install dannystewart/apps/volumehud
```

Place it in your Applications folder (or wherever) and run it. From that point forward, you'll actually know what your volume is when you change it.

I can't stand gratuitous menu bar icons and have no desire to inflict more of them on you (or me), so there is no UI. To quit, simply launch the app a second time, like how many apps show settings when they don't have an icon.

To run it on startup, you can add it to **System Settings** > **General** > **Login Items & Extensions** > **Open at Login**.

## Permissions

The app will ask for two permissions, both of which are **completely optional:**

- **Accessibility:** The app works by detecting volume changes, so the HUD won't be shown when you press volume down when at 0% or volume up when at 100% because the volume doesn't change. Input monitoring watches for volume key presses to work around that. You can leave it off with no impact on anything else.
- **Notifications:** A single notification is displayed on first run to say the app has started and explain how to quit. After that, it's not shown again. There is also a notification when you quit, because otherwise it may not be clear that you actually did. You're free to leave notifications off if you don't find them helpful.

## License

This project is open source under the [MIT License](./LICENSE). Feel free to do what you like with it, or contribute!

<a href="https://www.buymeacoffee.com/dannystewart" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-blue.png" alt="Buy Me A Coffee" height="41" width="174"></a>
