<h1><img src="reGIFt/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="48" height="48" align="center" style="margin-right:10px"> reGIFt</h1>

<table><tr><td width="63%" valign="top">

A macOS menu bar GIF picker powered by the [Klipy](https://klipy.com) API. Browse trending GIFs, search by keyword, and drag any GIF directly into Slack, Discord, or any app that accepts file drops — where it renders as an inline animated image.

**Features**

- **Menu bar native** — no Dock icon, stays out of your way
- **Trending & search** — opens to trending GIFs on first launch, updates results as you type
- **Hover preview** — hover any thumbnail to see the full image with a title caption in a panel that slides out below the grid
- **Drag and drop** — drag a GIF into Slack, Discord, or any app that accepts file drops and it renders as an animated image (not a link)
- **Right-click menu** — toggle Open at Login, update your API key, or quit from the menu bar icon
- **Auto-start at login** — registers as a Login Item on first launch so it's always ready

</td><td width="37%" valign="top">

![reGIFt UI](docs/reGIFt_ui.png)

</td></tr></table>

## Installation

1. Download **reGIFt.zip** from the [Releases](../../releases) page
2. Unzip and drag **reGIFt.app** to your `/Applications/` folder

**First launch — one-time Gatekeeper step:**
Because reGIFt is not distributed through the Mac App Store, macOS will show an "unidentified developer" warning the first time. To get past it:

1. In Finder, go to `/Applications/`
2. **Right-click** `reGIFt.app` → **Open**
3. Click **Open** in the dialog

macOS remembers this permanently — every subsequent launch (including auto-start at login) opens without any warning.

**API key setup:**
reGIFt requires a free Klipy API key. On first open, you'll be asked to enter one when you click the menu bar icon:

<table><tr><td valign="top">

1. Go to **[partner.klipy.com/api-keys](https://partner.klipy.com/api-keys)** and click **Add Platform**, then fill in the form:
   - **Platform name:** `reGIFt`
   - **Your email:** your email address
   - **Platform website:** leave blank
   - **Tell us about your platform:** paste this in:
     > Personal macOS menu bar app for browsing and drag-dropping GIFs into Slack and Discord. For personal use only.
   - Check the box to agree to the terms, then click **Add Platform**
2. Copy the API key that appears
3. Click the reGIFt icon in your menu bar, paste your key into the setup screen, and click **Save Key**

Your key is stored securely in macOS Keychain and never leaves your machine. To update your key at any time, right-click the menu bar icon and choose **Update API Key.**

</td><td width="50%" valign="top">

![reGIFt onboarding](docs/onboarding.png)

</td></tr></table>

## Usage

| Action                 | Result                                                         |
| ---------------------- | -------------------------------------------------------------- |
| **Left-click** icon    | Open / close the GIF picker                                    |
| **Right-click** icon   | Context menu (Open at Login toggle, Update API Key, Quit)      |
| **Type in search bar** | Search Klipy; clear to return to trending                      |
| **Hover a GIF**        | Preview panel slides out below the grid                        |
| **Drag a GIF**         | Drop into any app that accepts files — renders as animated GIF |

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

---

## Building from Source

For developers who want to build reGIFt themselves.

**Requirements:** Xcode 15+, a free [Klipy API key](https://partner.klipy.com/api-keys)

1. Clone the repo and set up your API key:
   ```bash
   git clone https://github.com/jandrewsnc/reGIFt.git
   cd reGIFt
   cp reGIFt/Config.swift.example reGIFt/Config.swift
   # Edit reGIFt/Config.swift and paste your Klipy API key
   ```
2. Open `reGIFt.xcodeproj` in Xcode and set your signing team under Signing & Capabilities. (`Config.swift` is already referenced in the project — copying the file in step 1 is all that's needed.)
3. Build and install:
   ```bash
   make install
   ```

Launch the app once after installing — it will register itself as a Login Item automatically. You can toggle this at any time by right-clicking the menu bar icon.

> **Note:** In Debug builds, `Config.swift` is used as a fallback API key so you can run without going through onboarding. Release builds rely on Keychain only — if you build in Release mode and haven't entered a key via the UI, the onboarding screen will appear as expected.

### Project Structure

```
reGIFt/
├── AppDelegate.swift       — menu bar icon, popover, preview panel, right-click menu
├── ContentView.swift       — search bar, GIF grid, preview panel view, brand styling
├── GIFCellView.swift       — individual cell with drag-and-drop support
├── GIFCache.swift          — downloads GIFs to a local temp cache for dragging
├── KlipyService.swift      — Klipy API client (trending + search)
├── KeychainHelper.swift    — macOS Keychain read/write for the user's API key
├── Config.swift            — API key (gitignored — create from Config.swift.example)
├── Config.swift.example    — template for Config.swift
└── Assets.xcassets/
    ├── AppIcon.appiconset/ — full app icon (all macOS sizes)
    └── MenuBarIcon.imageset/ — SVG template image for the menu bar
```

### API Usage

reGIFt uses the [Klipy GIF API](https://klipy.com/docs#overview). The free test key allows **100 requests/hour** — one call on first open, one per search query. Results are cached in memory between opens so repeated views don't trigger additional requests.

### Secrets

`reGIFt/Config.swift` is listed in `.gitignore` and must never be committed. Copy `Config.swift.example` to get started:

```bash
cp reGIFt/Config.swift.example reGIFt/Config.swift
```

Then open it and replace `YOUR_KLIPY_API_KEY_HERE` with your key from [partner.klipy.com/api-keys](https://partner.klipy.com/api-keys).
