# Bleakfiber's Quest Tracker - Forever

[![Interface](https://img.shields.io/badge/Interface-16001%20(WoW%20Forever)-0078D7.svg?style=flat-square)](https://github.com/Bleakfiber/BleakfibersQuestTracker-Forever)
[![Release](https://img.shields.io/badge/Release-v1.1.0-ffd100.svg?style=flat-square)](https://github.com/Bleakfiber/BleakfibersQuestTracker-Forever/releases)
[![License](https://img.shields.io/badge/License-Source--Available-crimson.svg?style=flat-square)](LICENSE.md)
[![Dependencies](https://img.shields.io/badge/Dependencies-Zero%20External-2ea44f.svg?style=flat-square)](https://github.com/Bleakfiber/BleakfibersQuestTracker-Forever)
[![Suite](https://img.shields.io/badge/Suite-Bleakfiber's%20Addon%20Suite-8a2be2.svg?style=flat-square)](https://github.com/Bleakfiber)

**Bleakfiber's Quest Tracker** is a modular, high-performance, standalone quest tracking and navigation suite crafted specifically for **World of Warcraft: Forever** (Interface 16001).

Engineered as an ultra-responsive alternative to the default Blizzard quest watch frame, it pairs a bespoke **Dark Slate & Gold** visual design language with advanced standalone capabilities: 360-degree floating **Wayfinder** HUD navigation with full `/way` support, interactive quest item action buttons with bag scanning fallback, multi-layer XP & Location DataBars, intelligent quest automation, and full integration with the **Bleakfiber Addon Suite**.

Runs **100% standalone out of the box** with zero required third-party libraries or addons.

---

## 📑 Table of Contents

- [Key Highlights](#-key-highlights)
- [Feature Showcase](#-feature-showcase)
  - [1. Native Dark Slate & Gold GUI](#1-native-dark-slate--gold-gui)
  - [2. Zero-Overlap Dynamic Reflow](#2-zero-overlap-dynamic-reflow)
  - [3. Wayfinder 360° Navigation HUD & /way](#3-wayfinder-360-navigation-hud---way)
  - [4. Interactive Quest Item Buttons](#4-interactive-quest-item-buttons)
  - [5. DataBars: XP with Ghost Turn-In & Location](#5-databars-xp-with-ghost-turn-in---location)
  - [6. Quest Automation & Group Sync](#6-quest-automation---group-sync)
  - [7. Audio Alerts & Custom Sounds](#7-audio-alerts---custom-sounds)
  - [8. Master Mover & Profile Sync](#8-master-mover---profile-sync)
- [Interactive Controls & Mouse Shortcuts](#-interactive-controls--mouse-shortcuts)
- [Configuration Guide (8 Sub-Tabs)](#-configuration-guide-8-sub-tabs)
- [Slash Commands Reference](#-slash-commands-reference)
- [Architecture & Module Overview](#-architecture--module-overview)
- [Installation Guide](#-installation-guide)
- [Bleakfiber Addon Suite Ecosystem](#-bleakfiber-addon-suite-ecosystem)
- [License & Support](#-license--support)

---

## 🌟 Key Highlights

* **Pure Standalone Power**: Zero external dependencies required to run. Embedded libraries (`Ace3`, `LibSharedMedia-3.0`) ensure full out-of-the-box reliability.
* **Bespoke Native GUI**: Replaces generic AceGUI options with a native 8-tab configuration interface styled in signature dark slate with beveled gold accents.
* **Dynamic Zero-Overlap Reflow**: Window resize detection dynamically shifts controls between a 2-column balanced view and a 1-column stacked view with word-wrapped labels to prevent text clipping.
* **Smart Auto-Hiding Scrollbars**: Automatically disables mouse wheel scrolling and hides scrollbars whenever content fits within the visible container height.
* **Wayfinder 360° HUD Arrow**: Floating directional arrow with real-time distance calculations, velocity-based ETA, `/waypaste` multi-point support, and world map pin placement (`Alt + Left-Click`).
* **Interactive Quest Item Buttons**: Action buttons anchored next to quest titles with live cooldown sweeps, stack counts, and free repositioning (`Shift + Right-Click Drag`).
* **Experience Bar with Ghost Turn-In Preview**: Live visualization showing current XP, rested XP, and banked turn-in XP from completed quests in your log.
* **Non-Destructive Profile Capture**: Instant profile synchronization with `BleakfibersAddonConfig-Forever` that captures current settings on profile creation rather than resetting to defaults.

---

## 🎯 Feature Showcase

### 1. Native Dark Slate & Gold GUI
Access the full graphical settings suite with `/bfq` or `/bqt`. Designed to reflect the Bleakfiber suite visual standard:
- Unified dark slate textures (`#1a1f26`) with crisp gold borders (`#ffd100`).
- 8 organized sub-tabs: **General**, **Quests & Items**, **Colors & Fonts**, **Headers & Sort**, **Automation**, **Wayfinder/Audio**, **DataBars**, and **Profiles**.
- Embedded live color pickers, numeric sliders, sound preview buttons, and dropdown selectors.

### 2. Zero-Overlap Dynamic Reflow
Settings never collide, overlap, or overflow:
- **Wide Mode (`width >= 470px`)**: Displays clean, balanced 2-column options layouts.
- **Narrow Mode (`width < 470px`)**: Automatically reorients into a vertical single-column stack.
- **Strict Word Wrapping**: Checkbox and control labels enforce `SetWordWrap(true)` and column width clamping.
- **Auto-Hiding Scrollbar**: Hides the scrollbar and disables mouse wheel scrolling when content fits within the window.

### 3. Wayfinder 360° Navigation HUD & `/way`
An integrated tactical waypoint HUD arrow pointing smoothly toward quest objectives or custom coordinates:
- Smooth 360° directional rotation with live distance in yards.
- Dynamic velocity-based **ETA countdown** (estimated arrival time).
- **World Map Pin Integration**: `Alt + Left-Click` on the World Map immediately places a custom waypoint at your cursor.
- **Multi-Line Waypoint Paste (`/waypaste`)**: Paste coordinate dumps directly from Wowhead or quest guides in a single click.
- Auto-hides during combat encounters (configurable).

### 4. Interactive Quest Item Buttons
Never dig through your bags during combat or questing:
- Usable quest items (flares, seeds, totems, containment devices) anchor directly to their respective quest entry.
- Cooldown sweeps, range tinting, and stack counts reflect active inventory state.
- **Shift + Right-Click & Drag**: Freely drag and detach item buttons to place them anywhere on your interface.
- **Alt + Right-Click**: Resets detached item buttons back to their quest anchor.
- Non-secure combat updater safeguards against `ADDON_ACTION_BLOCKED` errors.

### 5. DataBars: XP with Ghost Turn-In & Location
Comprehensive header and footer status bars:
- **Multi-Color Experience Bar**:
  - **Current XP**: Configurable fill color (default: rich purple).
  - **Rested XP**: Configurable fill color (default: vibrant blue).
  - **Ghost Turn-In Bar**: Live visual preview of XP banked across completed quests in your log (default: vivid green).
- **Location Bar**: Displays zone name, subzone territory, and live `(X, Y)` player coordinates with optional abbreviation.

### 6. Quest Automation & Group Sync
Streamline tedious quest interactions with safety toggles:
- **Party Quest Status in Tooltips**: Hovering over any quest displays an instant breakdown of party members currently on the quest (`[✓ On Quest]`) and missing teammates (`[✗ Missing]`), complete with class colors and pushable share hints.
- **Tracker Party Badges**: Optional `[👥 #]` group counter badge displayed directly beside quest titles in the tracker when fellow teammates share the quest.
- **Fast Auto Loot**: Instant event-driven looting that completely unhooks when disabled.
- **Auto-Accept**: Automatically accepts offered quests and party member quest shares.
- **Safe Auto-Turn In**: Automatically completes quests with 0 or 1 item choice. *Safely pauses if multiple equipment rewards are offered so you never take the wrong item.*
- **Shift Bypass**: Hold `Shift` when interacting with an NPC to temporarily suspend all automation.
- **Party Progress Sync (`BFQ_SYNC`)**: Broadcasts objective progress to group members (e.g. `• Teammate: 4/5`) and provides one-click `[Share]` buttons for teammates missing the quest.

### 7. Audio Alerts & Custom Sounds
Immediate auditory cues for quest progression:
- Independent sound alerts for quest completion and objective advancement.
- Built-in Classic audio presets: Peon *"Work complete!"*, Classic chime, Level Up Fanfare, Raid Warning, Whispers, and Coin clinks.
- In-menu **[Play Sound]** preview buttons with independent volume sliders (5% to 100%) and sound channel routing (Master, SFX, Ambience).
- Full support for custom `.wav`, `.ogg`, and `.mp3` audio files placed in `Media/Sounds/`.

### 8. Master Mover & Profile Sync
Seamless integration with `BleakfibersAddonConfig-Forever`:
- **Master Mover Mode**: Toggle screen repositioning for all Bleakfiber addons simultaneously with `/bac mover`.
- **Non-Destructive Profiles**: New profiles duplicate current active settings instead of resetting your configuration to factory defaults.
- Full backup and profile switching via AceDB-3.0.

---

## 🖱️ Interactive Controls & Mouse Shortcuts

### Tracker Frame Controls

| Action | Description |
| :--- | :--- |
| **Left-Click Quest Title** | Opens the quest directly in the standard Blizzard Quest Log (`ToggleQuestLog`). |
| **Shift + Left-Click Quest** | If chat box is open: pastes formatted quest link. If closed: toggles quest tracking on/off. |
| **Right-Click Quest Title** | Opens the rich **Quest Context Menu** (track, share, abandon, waypoints, copy URL). |
| **Left-Click Zone Header** | Expands or collapses all quests under that zone header. |
| **Left-Click Quest `[-]`/`[+]`** | Collapses or expands an individual quest block. |
| **Alt + Right-Click Body** | Instantly opens the graphical options configuration window (`/bfq`). |
| **Left-Click Quest Item** | Uses or casts the associated quest item. |
| **Shift + Right-Click Item** | Unlocks and drags the item button anchor to any custom screen position. |
| **Alt + Right-Click Item** | Resets the item button back to its default anchor next to the quest title. |

### Header Bar Quick Buttons

| Button | Action |
| :--- | :--- |
| **`[Log]`** | Opens or closes the standard Blizzard Quest Log (`ToggleQuestLog`). |
| **`[Zone]`** | Toggles filtering to only display quests for the player's current zone. |
| **`[All]`** | Displays all tracked quests across all zones. |
| **`[...]`** | Opens the Quick Filter & Settings Menu (lock/unlock, sorting, visual sizing guide). |
| **`[-]` / `[+]`** | Minimizes or expands the tracker frame contents. |

---

## 🛠️ Configuration Guide (8 Sub-Tabs)

Type `/bfq` or `/bqt` in chat to open the options panel:

1. **General**: Master toggle, UI scale slider, lock/unlock frame position, auto-hide in combat, auto-hide when empty, and frame strata selection.
2. **Quests & Items**: Quest item action buttons, bag scanning fallback, objective text colors, difficulty level coloring, and quest level badges.
3. **Colors & Fonts**: Backdrop backgrounds, beveled borders, class-colored border accents, LibSharedMedia typography selectors, font sizes, and line spacing.
4. **Headers & Sort**: Zone grouping banners, sort mode selection (Level Ascending vs. Grouped by Zone), and header textures (Flat, Gradient, Blizzard, None).
5. **Automation**: Fast Auto Loot, Auto-Accept quests, Safe Auto-Turn In (with multi-reward protection), and Party Quest Sharing.
6. **Wayfinder/Audio**: Wayfinder 360° navigation HUD arrow, arrival countdowns (ETA), distance units, completion sounds, objective chimes, and channel volume sliders.
7. **DataBars**: Experience bar settings (Current XP, Rested XP, Banked Quest Ghost Bar preview) and Live Location/Coordinate bar settings.
8. **Profiles**: Create, copy, delete, and switch configuration profiles backed by AceDB-3.0 with complete Bleakfiber Addon Suite synchronization.

---

## ⌨️ Slash Commands Reference

| Command | Description |
| :--- | :--- |
| `/bfq` or `/bqt` | Opens the full graphical options configuration window. |
| `/bfq lock` | Locks tracker position to prevent accidental dragging. |
| `/bfq unlock` | Unlocks the tracker frame for dragging and repositioning. |
| `/bfq toggle` | Minimizes or expands the tracker frame. |
| `/bfq reset` | Resets tracker position back to default (`TOPRIGHT`). |
| `/bfq profile <name>` | Switches to a named profile or displays current active profile. |
| `/bfq debug` | Toggles developer diagnostic output in chat. |
| `/way <x> <y> [title]` | Sets a custom Wayfinder navigation waypoint in your current zone. |
| `/way <zone> <x> <y> [title]` | Sets a custom Wayfinder waypoint in a specific zone. |
| `/way test` | Toggles test preview mode on the Wayfinder HUD arrow for repositioning. |
| `/way reset` or `/cway` | Clears the active custom navigation waypoint. |
| `/way paste` or `/waypaste` | Opens the Multi-Line Waypoint Paste Window. |

---

## 🏗️ Architecture & Module Overview

```
BleakfibersQuestTracker-Forever/
├── BleakfibersQuestTracker-Forever.toc  # Addon metadata, SavedVariables & file manifest
├── Core.lua                             # Addon lifecycle, DB init, event router, BAC registration
├── Config.lua                           # Bespoke 8-sub-tab Dark Slate & Gold GUI & responsive reflow
├── TrackerFrame.lua                     # Main display frame, header buttons, backdrop styling
├── Onboarding.lua                       # First-run welcome dialog & profile configuration
├── Modules/
│   ├── WayfinderModule.lua              # 360° directional arrow, coordinate math, map pin integration
│   ├── DataBarsModule.lua               # Multi-segment XP bar with ghost preview & location header
│   ├── QuestAutomationModule.lua        # Fast auto-loot, auto-accept, safe auto-turn in, party sync
│   ├── StandaloneTracker.lua            # Quest parsing, object pooling & objective rendering
│   ├── SocialModule.lua                 # Group broadcast communications (BFQ_SYNC)
│   ├── CrossZoneModule.lua              # Zone grouping & cross-zone objective scanning
│   ├── TargetMarkerModule.lua           # Quest target icon marking
│   └── QoLModule.lua                    # Audio cues, volume routing & sound previews
├── Media/
│   ├── Media.lua                        # LibSharedMedia font & texture registration
│   ├── Fonts/                           # Embedded Nata Sans, Orbitron, and Roboto Condensed fonts
│   ├── Sounds/                          # Custom audio completion cues (.wav)
│   └── Textures/                        # Wayfinder HUD arrows, map pins, borders & mask files
└── Libs/                                # Embedded Ace3 & LibSharedMedia-3.0 libraries
```

---

## 💾 Installation Guide

1. Download the latest release package from the official [Releases](https://github.com/Bleakfiber/BleakfibersQuestTracker-Forever/releases) page.
2. Exit World of Warcraft completely.
3. Extract the downloaded zip archive (`BleakfibersQuestTracker-Forever 1.0.19.zip`).
4. Copy the `BleakfibersQuestTracker-Forever` folder into your WoW client AddOns directory:
   ```
   World of Warcraft/_forever_/Interface/AddOns/BleakfibersQuestTracker-Forever
   ```
5. Launch World of Warcraft, log into your character, and type `/bfq` to configure the tracker.

---

## 🌌 Bleakfiber Addon Suite Ecosystem

Bleakfiber's Quest Tracker is designed to integrate seamlessly with the entire **Bleakfiber Addon Suite**:

* **[Bleakfiber's Addon Config](https://github.com/Bleakfiber/BleakfibersAddonConfig-Forever)**: Centralized master configuration hub with unified mover mode and cross-addon profile syncing.
* **[Bleakfiber's Action Bars](https://github.com/Bleakfiber/BleakfibersActionBars-Forever)**: Minimalist, high-performance standalone action bar suite with bags container and totem bars.
* **[Bleakfiber's Maps](https://github.com/Bleakfiber/BleakfibersMaps-Forever)**: Lightweight world map and minimap customization suite.
* **[Bleakfiber's Unit Toggles](https://github.com/Bleakfiber/BleakfibersUnitToggles-Forever)**: Instant Blizzard unit name & nameplate toggle suite with 20 CVar presets.

---

## 📜 License & Support

* **License**: Restricted - Source-Available (All Rights Reserved, No Derivatives). See [LICENSE.md](LICENSE.md) for full terms.
* **Issues & Feedback**: Encounter a bug or have a feature request? Open an issue on our [GitHub Issue Tracker](https://github.com/Bleakfiber/BleakfibersQuestTracker-Forever/issues).
* **Author**: Bleakfiber
