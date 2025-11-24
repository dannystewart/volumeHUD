# volumeHUD

A simple macOS app that brings back the classic volume and brightness HUDs.

## Why This Exists

With macOS Tahoe, Apple revamped Control Center and replaced the classic volume and brightness indicators of 25 years with tiny popovers in the corner of the screen, even smaller than notifications. They're hard to see, especially against light backgrounds, and they disappear before I remember where to look. Even after months on the Tahoe beta I haven't gotten used to them. It's bad UI.

So I did what any sane person would do: I picked up Xcode and wrote my first ever Mac app to bring back the classic macOS HUDs we all know and love (except Apple, apparently). They do what any good system indicator should do: they show you the level when you change it and then they go away. And get this—you can actually *see them*. A groundbreaking feature in 2025.

## What It Looks Like

<img src="volumeHUD-demo.gif" alt="volumeHUD Demo" height="300"></img>

## Usage

Just launch the app! You should see a notification that it started and you can begin enjoying your new (old) volume HUD right away. You can launch it a second time to open a window where you can set it to open at login, enable the brightness HUD (off by default—it's *volumeHUD* after all), control HUD positioning, check for updates, and quit.

As of version 3.0, volumeHUD now also hides the system HUD. It checks to make sure volume or brightness has actually changed after a key press is detected; if not, it stops intercepting those keys until it detects a device change or the app is restarted. This ensures you're not prevented from changing the volume or brightness if it doesn't work on your system.

## Installation

You can download it from the repo, but I strongly recommend installing via Homebrew, as that will handle updates for you. It's my first Swift app, so I don't want you to be left with any lingering bugs.

```bash
brew install dannystewart/apps/volumehud
```

You can uninstall with `brew uninstall volumehud`, which should remove all traces of the app, including preferences and login item. No permissions should be left behind either once the app is gone.

## Permissions

I worked hard to ensure the app could function without requiring any permissions. It will request two that are **optional but recommended**.

- **Notifications** are used only to confirm the app has started (and only when launched manually, not as a login item). Feel free to disable if you find them unnecessary.
- **Accessibility** is needed for full functionality. The app will work without it, but you lose some features:
  - The system HUD will still appear alongside volumeHUD.
  - The HUD won't appear if you go below 0% or above 100% since it can't use key presses to determine if levels should have changed.
  - Brightness checks may be less reliable since key timing can't be used to check whether a change is user-initiated.

Apart from that, all other features should work.

## Troubleshooting

If you're experiencing inconsistent behavior and aren't using Accessibility permissions, try granting those first, if you're comfortable doing so. They're optional but enabling them should improve reliability.

If you're unsure whether you've granted them or want to reset them, go to **System Settings** > **Privacy & Security** > **Accessibility**. Make sure volumeHUD is in the list and turned on, and if it's still not working, try removing it from the list entirely and then re-adding it.

## License

This project is open source under the [MIT License](./LICENSE). Feel free to do what you like with it, or contribute!

<a href="https://www.buymeacoffee.com/dannystewart" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-blue.png" alt="Buy Me A Coffee" height="41" width="174"></a>
