# BreakBuddy

A tiny macOS menu bar app that reminds you to take breaks. Unlike Pomodoro timers, it tracks your real activity — mouse movement, clicks, scrolling and typing. If you step away for a meeting or lunch, that counts as a break and the work timer starts over.

## How it works

- Every 5 seconds the app asks macOS how long it has been since the last user input (`CGEventSource.secondsSinceLastEventType`). No special permissions are required.
- After 5 minutes without any input (or while the Mac is asleep) you are considered on a break 💤.
- When you come back, a new work session starts from your first input.
- After 50 minutes of work without a break, a reminder window pops up with a sound: "5 more min", "15 more min", "Taking a break".
- If you ignore the window, it plays the sound and shakes again every 5 minutes.

Menu bar icon: `⏱ N` — minutes without a break, `☕ N` — time for a break, `💤` — on a break, `⏸` — paused.

Configurable from the menu: reminder interval (25–90 min), break length (2–10 min), "Do not disturb for 1 hour", launch at login, interface language.

## Language

The interface is in English by default. Russian is available: menu → **Language** → **Русский**. The switch applies immediately.

To add another language, create `Resources/<code>.lproj/Localizable.strings`, add the code to `CFBundleLocalizations` in `build.sh` and to the language list in `Sources/main.swift`.

## Build

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh           # build into build/BreakBuddy.app
./build.sh install   # build, install into ~/Applications and launch
```
