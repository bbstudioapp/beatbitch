# Install BeatBitch on iPhone / iPad

> BeatBitch is **not** available on the App Store (the App Store does not
> allow adult content). On iOS, we use an **installable web version** (PWA).
> Once added to your home screen, it behaves like a real app: dedicated icon,
> full screen, no Safari bar, works offline after the first load.

**Languages**: [Français](INSTALL-iOS.fr.md) · English · [Deutsch](INSTALL-iOS.de.md)

---

## Before you start

- You need an **iPhone** or **iPad** running **iOS 16.4 or newer**.
- You must use **Safari** (not Chrome or Firefox on iOS — Apple does not allow
  PWA installation from those browsers).
- The first load requires an **Internet connection**. After that, everything
  works offline.

---

## Installation — step by step

### 1. Open Safari and go to

```
URL_BEATBITCH_PWA
```

(Replace with the URL provided by BB Studio.)

Wait for the page to fully load (a few seconds: we download the entire app,
audio included, so it can work offline afterwards).

### 2. Tap the **Share** icon

It's the icon at the bottom of the screen (center on iPhone, top on iPad) that
looks like a square with an upward arrow:

```
   ┌──┐
   │↑ │
   └──┘
```

### 3. Scroll the share menu

In the list of actions, find **"Add to Home Screen"** (icon **+** on a
square). Tap that option.

> If you don't see it, scroll down — depending on your iOS version, it may be
> further down the list.

### 4. Confirm the name and tap **Add**

iOS suggests the name "BeatBitch". Keep it as is (or change it if you want
discretion on your home screen — for example "Coach").

Tap **Add** in the top-right corner.

### 5. Launch BeatBitch from the icon

Exit Safari. You'll find the **BeatBitch** icon on your home screen, like any
other app. Tap it: the app launches full screen, without the Safari bar,
exactly like a native app.

---

## What you need to know

### Offline

After the first launch, BeatBitch works **without a network**. You can put
your iPhone in airplane mode: everything works.

### Updates

When BB Studio releases a new version, your iPhone fetches it automatically
the next time you open the app **with a connection**. No visible update
notification — it's silent.

### Storage: beware of the 7-week limit

iOS automatically clears a PWA's cache if you **don't open the app for ~7
weeks**. When that happens:

- The app needs an Internet connection to reload.
- **Your career progress will be lost** (level, badges, milestones, nicknames,
  settings).

> 💡 Open BeatBitch at least once a month to avoid this reset.

### Differences vs the Android version

A few features are **not available** on iOS PWA:

- **Camera hold check** — does not use the camera.
- **Surprise notifications** — iOS does not allow scheduled notifications for
  PWAs as freely as Android does.
- **TTS voice** — you only get the Apple voices installed on your iPhone
  (not Android's Google voices). Quality is decent, but tone may feel less
  "firm" than expected.
- **Background audio** — Safari iOS may cut audio when you lock the screen.
  Keep the screen on during your session.

---

## Common issues

### "The Add to Home Screen option doesn't appear"

You're probably not in Safari. Check: if you're using Chrome or Firefox on
iPhone, it won't work. Open the URL **in Safari**.

### "The app doesn't launch offline"

The first load didn't cache the full app. Reconnect your iPhone to the
Internet, open BeatBitch, wait for it to fully load, then try again in
airplane mode.

### "Sound is glitchy / cuts out"

Safari iOS has limits on background audio. Make sure:

- The screen stays on (**Settings → Display & Brightness → Auto-Lock → Never**
  during the session).
- Media volume (not ringer) is up.
- No other audio app is running (music, podcast).

### "No sound at all"

iOS sometimes blocks audio autoplay. Tap any button in the app once (for
example, start/stop a session) to unblock audio.

---

## Uninstall

Touch and hold the **BeatBitch** icon on the home screen → **Remove App** →
**Delete**. All local data is erased.

---

## Support

GitHub repo: [github.com/bbstudioapp/beatbitch](https://github.com/bbstudioapp/beatbitch)
Issues: open an issue in English or French.
