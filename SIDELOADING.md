# Getting NIM Voice onto your iPhone — free, from Windows, no Mac

You don't need a Mac. A free cloud macOS runner compiles the app; you sign and
install it from Windows with your own free Apple ID. Total cost: $0.

> **The one tradeoff:** apps signed with a *free* Apple ID expire after **7 days**
> and must be re-signed. AltStore can do this automatically over Wi-Fi; Sideloadly
> does it with a 30-second reinstall. That's the price of not paying $99/year.

---

## Step 1 — Build the .ipa in the cloud (free)

1. Create a **free GitHub account** if you don't have one.
2. Create a new repository (**Public** = unlimited free build minutes; the app
   keeps no secrets in source, so public is safe).
3. Push this project so that **`NIMVoice.xcodeproj` sits at the repo root**
   (i.e. upload the *contents* of the `NIMVoice` folder, including the hidden
   `.github` folder). Using GitHub Desktop on Windows is the easy way.
4. The included workflow [`.github/workflows/ios.yml`](.github/workflows/ios.yml)
   runs automatically. Open the **Actions** tab → latest run → wait for the green
   check (~5–10 min).
5. In that run, scroll to **Artifacts** and download **`NIMVoice-ipa`**. Unzip it
   to get `NIMVoice.ipa`.

You can re-trigger a build anytime from **Actions → iOS build → Run workflow**.

## Step 2 — Sign & install from Windows

Pick **one** tool. Both run on Windows and sign with your free Apple ID.

### Option A — Sideloadly (simplest, manual refresh)
1. Install **iTunes** and **iCloud** from **apple.com** (the *non*–Microsoft-Store
   versions — Sideloadly needs Apple's device drivers).
2. Download Sideloadly from **sideloadly.io** and install it.
3. Plug your iPhone in via USB and tap **Trust** on the phone.
4. Open Sideloadly, drag in `NIMVoice.ipa`, enter your **Apple ID** (use an
   [app-specific password](https://account.apple.com) if you have 2FA on),
   click **Start**. It signs with your free "Personal Team" and installs.

### Option B — AltStore (recommended: auto-refreshes the 7-day limit over Wi-Fi)
1. Install **iTunes** and **iCloud** from **apple.com** (the non–Microsoft-Store
   versions — the apple.com iTunes also installs **Bonjour**, which AltStore needs
   for Wi-Fi refresh).
2. Plug the iPhone in, tap **Trust**, then in iTunes open the device and tick
   **"Sync with this iPhone over Wi-Fi"** (required for background refresh).
3. Download **AltServer** for Windows from **altstore.io** and run it — it lives in
   the system tray (click the **^** chevron to find it).
4. Tray icon → **Install AltStore** → pick your iPhone → enter your Apple ID
   (app-specific password if you have 2FA). This installs the **AltStore** app.
5. Get `NIMVoice.ipa` onto the phone: copy it into your **iCloud Drive** folder on
   Windows; it then appears in the **Files** app on the iPhone.
6. On the iPhone open **AltStore → My Apps → + (top-left)** → pick `NIMVoice.ipa`.
7. Leave AltServer running on the PC. With Wi-Fi sync on and both on the same
   network, AltStore re-signs the app in the background so it never expires.
   (Open AltStore → My Apps once a week as a backstop.)

## Step 3 — Trust the app on the iPhone (first launch only)
1. **Developer Mode** (iOS 16+): *Settings → Privacy & Security → Developer Mode*
   → on → restart.
2. *Settings → General → VPN & Device Management* → tap your Apple ID → **Trust**.
3. Launch **NIM Voice**, allow Microphone + Speech, paste your `nvapi-` key in
   Settings. Done.

---

## Free-tier limits to know
- **7-day expiry** per signing (re-run Sideloadly, or let AltStore auto-refresh).
- Up to **3 sideloaded apps** and ~3 devices per free Apple ID.
- Mic, Speech, TTS, and iCloud-Keychain key storage all work on the free tier —
  this app uses no entitlements that the free tier blocks.
- Nothing is published; the app exists only on your device(s).

## If even this is too much friction
The only zero-build alternative is a **web app** in Safari — but iOS Safari has
no reliable hands-free speech *recognition*, so the always-listening experience
that makes this app what it is can't be reproduced in a browser. The cloud-build
+ sideload route above keeps the real native app intact, which is why it's the
recommendation.
