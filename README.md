# volumeHUD

A simple macOS app that brings back the classic volume and brightness HUDs.

## Why This Exists

With macOS Tahoe, Apple revamped Control Center and replaced the classic volume and brightness indicators of 25 years with tiny popovers in the corner of the screen, even smaller than notifications. They're hard to see, especially against light backgrounds, and they disappear before I remember where to look. Even after months on the Tahoe beta I haven't gotten used to them. It's bad UI.

So I did what any sane person would do: I picked up Xcode and wrote my first ever Mac app to bring back the classic macOS HUDs we all know and love (except Apple, apparently). They do what any good system indicator should do: they show you the level when you change it and then they go away. And get this—you can actually *see them*. A groundbreaking feature in 2025.

## What It Looks Like

<img src="volumeHUD-demo.gif" alt="volumeHUD Demo" height="300"></img>

## Installation

You can download it from the repo, but I strongly recommend installing via Homebrew, as that will handle updates for you. It's my first Swift app, so I don't want you to be left with any lingering bugs.

```bash
brew install dannystewart/apps/volumehud
```

## Usage

Just launch the app! You should see a notification that it started and you can begin enjoying your new (old) volume HUD right away. You can launch it a second time to open a window where you can set it to open at login, enable the brightness HUD (off by default—it's *volumeHUD* after all), see if an update is available, or quit.

## Permissions

I worked hard to ensure the app would function as well as possible without requiring any permissions. It will request two that are **completely optional:**

- **Accessibility:** The app works by detecting changes to volume and brightness levels, which means the HUD won't appear when you try to go below 0% or above 100% since the levels don't change. Input monitoring works around this by watching for key presses. That's the only thing you'll lose if you leave it off.
- **Notifications:** Used only to confirm the app has started (and only when launched manually, not as a login item). Feel free to leave them disabled if you find them unnecessary.

## Troubleshooting

- **Issues with key press detection:** Go to **System Settings** > **Privacy & Security** > **Accessibility**. Make sure volumeHUD is in the list and turned on. If it is but it's still not working, you may need to remove it from the list entirely and re-add it.
- **Brightness HUD stops appearing after display changes:** 2.0.1 will be out soon with a fix for this, but in the meantime you can simply restart volumeHUD to restore it.

## License

This project is open source under the [MIT License](./LICENSE). Feel free to do what you like with it, or contribute!

<a href="https://www.buymeacoffee.com/dannystewart" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-blue.png" alt="Buy Me A Coffee" height="41" width="174"></a>
