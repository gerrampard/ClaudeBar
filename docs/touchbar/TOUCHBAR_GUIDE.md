# ClaudeBar Touch Bar Integration Guide (MacBook Pro)

This guide explains how to display persistent quota information from ClaudeBar on your MacBook Pro Touch Bar using **BetterTouchTool (BTT)** or **MTMR**.

> **Note:** ClaudeBar also includes built-in native Touch Bar support that requires no third-party tools. This guide is for users who prefer customizing their Touch Bar setup using BetterTouchTool or MTMR via the exported status file.

---

## Table of Contents
1. [How It Works](#how-it-works)
2. [Method 1: Setup via BetterTouchTool (Recommended)](#method-1-setup-via-bettertouchtool-recommended)
3. [Method 2: Setup via MTMR (Free & Open Source)](#method-2-setup-via-mtmr-free--open-source)
4. [URL Schemes](#url-schemes)
5. [Enabling / Disabling Touch Bar Integration](#enabling--disabling-touch-bar-integration)
6. [Troubleshooting](#troubleshooting)

---

## How It Works

ClaudeBar automatically syncs the latest quota data to `~/.claudebar/status.json` whenever:
- Quota status changes
- A quota refresh is triggered
- The active provider is switched

The helper script [`scripts/touchbar_status.py`](../../scripts/touchbar_status.py) reads this file and formats the output with status colors, real provider icons, and display text for the Touch Bar with virtually zero CPU and battery impact.

### Real Provider Icons
Transparent PNG icons for each supported provider are included in `scripts/icons/` and `~/.claudebar/icons/`:
- **Claude** (Anthropic)
- **OpenAI / Codex**
- **Google Gemini**
- **GitHub Copilot**
- **Cursor**
- **DeepSeek**
- **Alibaba Qwen**
- **Google Antigravity**
- **xAI Grok**
- **AWS Bedrock**
- **Moonshot Kimi**
- **MiniMax**
- **Mistral**
- **Z.ai**
- **Vercel**, **AmpCode**, **OpenCode**, **Oh My Pi**, **Kiro**

When executed with `--btt`, the script provides an `icon_path` pointing to the provider's PNG icon file, allowing BetterTouchTool to render it directly on the Touch Bar.

---

## Method 1: Setup via BetterTouchTool (Recommended)

BetterTouchTool (BTT) can display a persistent widget on the Touch Bar with dynamic background color based on status (green / amber / red).

### Configuration Steps:

1. Open **BetterTouchTool**.
2. Select the **Touch Bar** tab in the top navigation.
3. Select **All Apps** in the left column (to show across all applications).
4. Click the **+ (Add Widget)** button in the bottom bar.
5. Search for and select **"Shell Script / Task Widget"**.
6. Configure the widget settings:
   - **Widget Name**: `ClaudeBar Quota`
   - **Execute every**: `10` seconds (or your preferred interval)
   - **Script / Task**:
     ```bash
     python3 /path/to/ClaudeBar/scripts/touchbar_status.py --btt
     ```
     *(Replace `/path/to/ClaudeBar` with the absolute path to your cloned repository)*
   - **Script Output Type**: Select **`JSON (text, background_color, font_color)`**
7. **Assign Tap Action**:
   - In the **Action** section, select **"Execute Terminal Command"** or **"Open URL"**.
   - URL: `claudebar://open` (opens the ClaudeBar menu) or `claudebar://refresh` (triggers an immediate quota refresh).

---

## Method 2: Setup via MTMR (Free & Open Source)

[MTMR (My TouchBar. My Rules.)](https://github.com/Toxblh/MTMR) is a free, open-source application for customizing the Touch Bar via a JSON configuration file.

### Configuration Steps:

1. Install MTMR (via Homebrew: `brew install --cask mtmr`).
2. Open the configuration file `~/Library/Application Support/MTMR/items.json`.
3. Add the following widget configuration to the items array:

```json
{
  "type": "shellStream",
  "width": 140,
  "bordered": true,
  "align": "right",
  "refreshInterval": 10,
  "commandPath": "/usr/bin/python3",
  "shellArguments": [
    "/path/to/ClaudeBar/scripts/touchbar_status.py",
    "--mtmr"
  ],
  "actions": [
    {
      "trigger": "singleTap",
      "action": "openUrl",
      "url": "claudebar://open"
    }
  ]
}
```
*(Replace `/path/to/ClaudeBar` with the absolute path to your cloned repository)*

4. Save the file. The Touch Bar will update immediately.

---

## URL Schemes

ClaudeBar supports the following URL schemes:

| URL Scheme | Description | Terminal Example |
|---|---|---|
| `claudebar://open` | Opens the ClaudeBar dropdown menu | `open claudebar://open` |
| `claudebar://refresh` | Triggers an immediate quota refresh for all providers | `open claudebar://refresh` |
| `claudebar://settings` | Opens the Settings window | `open claudebar://settings` |

---

## Enabling / Disabling Touch Bar Integration

You can toggle Touch Bar data export in ClaudeBar:
- Go to **Settings (⌘,) > General > Touch Bar**.
- When disabled:
  - `status.json` will report state as `disabled`.
  - The BetterTouchTool script (`--btt`) will hide the widget transparently (leaving the Touch Bar clean).
  - The MTMR script (`--mtmr`) will output empty text.

---

## Troubleshooting

- **Touch Bar displays "ClaudeBar: Offline"**:
  - Check whether the ClaudeBar application is running.
  - Verify that `~/.claudebar/status.json` exists.
- **Test the script manually**:
  ```bash
  python3 scripts/touchbar_status.py --btt
  python3 scripts/touchbar_status.py --mtmr
  ```
