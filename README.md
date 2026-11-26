# ☕ Espresso

A tiny macOS menu bar app that stops your Mac from going to sleep.
Same idea as the classic "Caffeine" utility: one click on the cup and your Mac stays awake.

## Using it

| Action | What happens |
|---|---|
| **Click** the cup in the menu bar | Toggle on/off. Filled cup = awake, empty cup = normal sleep |
| **Right-click** (or Control/Option-click) | Menu with durations and settings |
| **Activate for →** | Stay awake for 5 min … 5 hours, or indefinitely |
| **Default Duration** | What a plain click uses (default: indefinitely) |
| **Allow Display to Sleep** | Screen can turn off, but the Mac keeps running (downloads, builds, calls) |
| **Activate at Launch** | Turn on automatically when the app starts |
| **Start at Login** | Launch Espresso when you log in |

Hover over the cup to see how much time is left.

Notes:
- It uses Apple's official power assertion API (the same one video players use), so there's no admin password, nothing to install system-wide, and quitting the app restores normal behavior immediately.
- Closing the lid still puts a MacBook to sleep, unless it's plugged in with an external display. That's macOS behavior and no regular app can override it without admin rights.
- Check that it works: `pmset -g assertions | grep Espresso`
- Requires macOS 13 Ventura or later. Runs natively on Apple Silicon and Intel.

## Installing (for teammates)

1. Unzip `Espresso-1.0.0.zip` and drag **Espresso.app** into **Applications**.
2. Open it. Because the app isn't notarized by Apple, macOS blocks it the first time:
   - **macOS 15 Sequoia and later:** click *Done*, then open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to "Espresso was blocked", and confirm.
   - **macOS 13–14:** right-click Espresso.app → **Open** → **Open**.
   - Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Espresso.app`
3. Look for the cup in the menu bar. There's no Dock icon.

You only have to do step 2 once.

## Building

On any Mac with the Xcode Command Line Tools (`xcode-select --install`):

```bash
./build.sh
```

This produces `build/Espresso.app` and `build/Espresso-1.0.0.zip` (the file to share).

No Mac handy? Push this folder to GitHub and the included workflow (`.github/workflows/build.yml`) builds the zip on a macOS runner. Download it from the run's *Artifacts*, or push a tag like `v1.0.0` to attach it to a GitHub Release.

### Removing the security warning (optional)

To share it without the "unidentified developer" prompt, sign and notarize it with an Apple Developer ID ($99/year Apple Developer Program, or ask whoever owns your company's Apple account):

```bash
xcrun notarytool store-credentials espresso --apple-id you@company.com --team-id TEAMID
SIGN_IDENTITY="Developer ID Application: Your Company (TEAMID)" NOTARY_PROFILE=espresso ./build.sh
```

Then teammates can just double-click it. If your IT team manages Macs with MDM, they can also push the app to everyone.

## Project layout

```
Sources/main.swift          the whole app (~330 lines, AppKit + IOKit)
Resources/Info.plist        bundle metadata (menu-bar-only app, macOS 13+)
Resources/AppIcon.png       1024px icon, converted to .icns at build time
build.sh                    build, sign, (optionally) notarize, zip
.github/workflows/build.yml CI build on macOS
```
