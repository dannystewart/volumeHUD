# volumeHUD

A simple macOS app that brings back the classic volume and brightness HUDs.

## Why This Exists

With macOS Tahoe, Apple revamped Control Center and replaced the classic volume and brightness indicators of 25 years with tiny popovers in the corner of the screen—even smaller than notifications. They're barely visible, especially against light backgrounds, and they disappear before I remember where to look. Even after months on the Tahoe beta, I still haven't gotten used to it. It's bad UI.

So I did what any sane person would do: I picked up Xcode and wrote my first ever Mac app to bring back the classic macOS HUDs we all know and love (except Apple, apparently). They do what good system indicators should do: show you the value when you change it, then get out of the way. And get this—you can actually *see them*. A groundbreaking feature in 2025.

## What It Looks Like

<img src="volumeHUD-demo.gif" alt="volumeHUD Demo" height="300"></img>

## How to Use It

### Installation

You can download straight from the repo, but I **strongly recommend** installing via Homebrew since it handles updates. This is my first Swift app, so I want to make sure you're not left with any lingering bugs.

```bash
brew install dannystewart/apps/volumehud
```

### Interface

Launching the app a second time while it's running will show the About window, where you can set it to open at login, enable the brightness HUD (off by default—it's *volumeHUD* after all), see if an update is available, and quit.

### Permissions

The app will request two permissions, both of which are **completely optional:**

- **Accessibility:** The app works by detecting changes to volume and brightness levels, which means the HUD won't appear when you try to go below 0% or above 100% (since the levels don't actually change). Input monitoring works around this by watching for key presses. That's all you'll lose if you leave it off.
- **Notifications:** Used only to confirm the app has started (and only when launched manually, not as a login item). If you find them unnecessary, feel free to disable.

## License

This project is open source under the [MIT License](./LICENSE). Feel free to do what you like with it, or contribute!

<a href="https://www.buymeacoffee.com/dannystewart" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-blue.png" alt="Buy Me A Coffee" height="41" width="174"></a>
