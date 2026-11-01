# volumeHUD

A simple macOS app that brings back the classic volume and brightness HUDs.

---

**NOTE: volumeHUD is a personal project and I don't accept PRs or feature requests.** I'm very glad it's found an appreciative audience, but I built this for myself and it works the way I want. Issues are disabled because too many people didn't respect that.

---

With macOS Tahoe, Apple revamped Control Center and replaced the classic volume and brightness indicators of 25 years with tiny popovers in the corner of the screen, even smaller than notifications. They're hard to see, especially against light backgrounds, and they disappear before I remember where to look. It's bad UI.

So I did what any sane person would do: I picked up Xcode and wrote my first ever Mac app to bring back the classic macOS HUDs we all know and love. They do what any good system indicator should do: they show you your changes and then go away. And get this—you can actually *see them*. A groundbreaking feature post-2025.

volumeHUD also supports brightness on built-in displays (though it is **off by default**—it is *volumeHUD*, after all), and hides the system HUD by intercepting volume and brightness keys and handling the changes itself rather than letting the OS do it.

Version 4.0 features a redesigned glass UI that feels right at home on modern macOS without forgetting its roots as the original volume HUD we're all here for.

## What It Looks Like

<img src="Images/volumeHUD-demo.gif" alt="volumeHUD Demo" height="250"></img>

## Usage

Just launch the app. You should see a notification that it started, and you can begin enjoying your new (old) volume HUD right away. If you launch it a second time, you'll get a Settings window, where you can also update or quit the app.

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

If you're experiencing inconsistent behavior, the most likely cause is lack of Accessibility permissions, and the first thing I would recommend is a full reset. The most thorough way to do this is to uninstall and reinstall:

1. Completely quit volumeHUD by opening it a second time and clicking **Quit volumeHUD** or by running `pkill -f volumeHUD`
2. Open **System Settings** → **Privacy & Security** → **Accessibility**.
3. Find **volumeHUD** in the list, select it, and click the minus (-) button at the bottom. Make sure it's removed from the list.
4. Assuming you installed with Homebrew, run `brew uninstall volumehud` to remove the login item, the app, and any remaining files.
5. Run `brew install dannystewart/apps/volumehud` to reinstall.
6. Reopen **volumeHUD.app**. You should be prompted with "this application has been downloaded from the internet" first, followed by a request for Accessibility permissions.
7. Open **System Settings** like it says to do, make sure **volumeHUD** is in the list now, and toggle it on. If it says you'll need to quit and reopen, do that and try again.

Alternatively, you can do the same reset from the command line:

```bash
pkill -f volumeHUD
tccutil reset Accessibility com.dannystewart.volumehud
tccutil reset ListenEvent com.dannystewart.volumehud
brew uninstall volumehud
brew install dannystewart/apps/volumehud
```

Then run the app again, grant the requested permissions, and triple-check everything in **System Settings**.

## License

This project is open source under the [MIT License](./LICENSE). You're free to do what you want with it, but credit would be appreciated.

<a href="https://www.buymeacoffee.com/dannystewart" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-blue.png" alt="Buy Me A Coffee" height="41" width="174"></a>
