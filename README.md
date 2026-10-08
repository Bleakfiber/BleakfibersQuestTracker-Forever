# Bleakfiber's Quest Tracker (Forever)

[![Interface](https://img.shields.io/badge/Interface-16001%20(WoW%20Forever)-blue.svg)](https://github.com/Bleakfiber/BleakfibersQuestTracker-Forever)
[![Version](https://img.shields.io/badge/Version-1.0.18-green.svg)](https://github.com/Bleakfiber/BleakfibersQuestTracker-Forever)
[![License](https://img.shields.io/badge/License-Restricted%20Source--Available-red.svg)](LICENSE.md)

**Bleakfiber's Quest Tracker** is a modular, high-performance, standalone quest tracking interface crafted specifically for **World of Warcraft: Forever**.

Designed as a modern alternative to the default Blizzard quest watch frame, it combines a sleek aesthetic and customizable header with advanced standalone features including quest item action buttons with bag scanning fallback, smart zone-based grouping, quest level sorting, right-click context menus, party quest synchronization, and automation tools. Built completely independent with zero external addon dependencies for launch.

---

## Table of Contents

1. [Features Overview](#features-overview)
2. [User Interface & Controls](#user-interface--controls)
   - [Header Bar Controls](#header-bar-controls)
   - [Interactive Mouse Controls](#interactive-mouse-controls)
   - [Quest Right-Click Context Menu](#quest-right-click-context-menu)
   - [Interactive Sizing Guide & Overlay](#interactive-sizing-guide--overlay)
3. [Slash Commands](#slash-commands)
4. [Configuration Guide](#configuration-guide)
   - [General](#1-general)
   - [Sizing](#2-sizing)
   - [Fonts & Typography](#3-fonts--typography)
   - [Appearance & Backdrop](#4-appearance--backdrop)
   - [Headers & Sections](#5-headers--sections)
   - [Sorting & Filtering](#6-sorting--filtering)
   - [Social, Automation & Audio](#7-social-automation--audio)
   - [Profiles](#8-profiles)
5. [Code Architecture & Function Reference](#code-architecture--function-reference)
   - [Core Architecture (`Core.lua`)](#core-architecture-corelua)
   - [Tracker Frame (`TrackerFrame.lua`)](#tracker-frame-trackerframelua)
   - [Standalone Tracker Engine (`Modules/StandaloneTracker.lua`)](#standalone-tracker-engine-modulesstandalonetrackerlua)
   - [Social & Automation Module (`Modules/SocialModule.lua`)](#social--automation-module-modulessocialmodulelua)
   - [Configuration & Dialogs (`Config.lua`)](#configuration--dialogs-configlua)
6. [Dependencies](#dependencies)
7. [Installation](#installation)
8. [License & Contributing](#license--contributing)

---

## Features Overview

* **100% Independent & Standalone**: Operates natively using Blizzard's Classic APIs without requiring third-party database or UI frameworks.
* **Native Dark Slate & Gold GUI**: Replaces raw AceGUI configuration windows with a bespoke 8-tab settings suite (`/bfq`) rendered in the Bleakfiber design theme.
* **Responsive Layout Reflow**: Settings controls dynamically switch between a 2-column balanced layout and a 1-column stacked layout with word-wrapping labels to guarantee zero element overlaps.
* **Auto-Hiding Scrollbars**: Integrated smart scrollbar detection automatically hides the scroll bar and disables mouse wheel scrolling whenever options fit within the visible viewport.
* **BleakfibersAddonConfig Suite Mover**: Seamlessly locks/unlocks positioning with the global master mover system (`/bac mover`).
* **Customizable Header Bar**: Complete with custom textures (Flat, Gradient, Blizzard, None), color pickers, counter displays, and quick-access buttons (`[Log]`, `[Zone]`, `[All]`, `[...]`, `[-]`/`[+]`).
* **Interactive Quest Item Buttons**: Usable quest items (flares, totems, containment devices, seeds) appear directly alongside the quest block with full cooldown animations and stack counters. Includes native bag scanning fallback.
* **Smart Zone & Section Grouping**: Automatically clusters quests under collapsible zone banners (e.g., `Durotar (3)`) with custom color gradients.
* **Quest Level & Zone Sorting**: Choose between sorting quests by recommended level ascending or grouped alphabetically by zone.
* **Zero-Garbage Object Pooling**: Uses dynamic object pools for quest blocks, objective strings, party member tags, and quest item buttons, completely eliminating garbage collection frame drops during combat and zone transitions.
* **Rich Quest Context Menus**: Right-click any quest title to quickly track/untrack, link to chat, share with group, abandon, set navigation waypoints (via TomTom), or copy a Wowhead URL.
* **Social & Quest Automation**:
  - Auto-accept quests from NPCs and group members (with optional shift-key bypass).
  - Auto-turn in quests with 0 or 1 item choices (pauses automatically when multiple rewards are offered so you can select your gear).
  - Auto-share newly accepted quests with your party.
* **Party Quest Progress Sync**: Broadcasts and displays live party progress underneath each objective (e.g., `• Teammate: 4/5`) via hidden addon communications (`BFQ_SYNC`), and provides one-click sharing to party members who do not have the quest yet.
* **Custom Audio Alerts**: Plays customizable completion sounds (Peon *"Work complete!"*, Classic chime, Level-up fanfare, Raid warning) when completing quests or individual objectives.
* **TomTom Navigation Support**: Integrates with TomTom for one-click navigation waypoints from the context menu.

---

## User Interface & Controls

### Header Bar Controls

The header at the top of the tracker displays current quest capacity and includes several interactive buttons:

| Button | Action |
| :--- | :--- |
| **`[Log]`** | Opens or closes the standard Blizzard Quest Log (`ToggleQuestLog`). |
| **`[Zone]`** | Toggles filtering to only show quests for your current zone. |
| **`[All]`** | Displays all tracked quests across all zones. |
| **`[...]`** | Opens the Quick Filter & Settings Menu. |
| **`[-]` / `[+]`** | Minimizes or expands the tracker contents. |

### Interactive Mouse Controls

* **Left-Click Quest Title**: Opens the quest entry in the Blizzard Quest Log.
* **Shift + Left-Click Quest Title**: 
  - If a chat edit box is open: pastes the quest link into chat (e.g. `[12] The Barrens Ooze`).
  - If no chat box is open: toggles tracking (watch/unwatch) for that quest.
* **Right-Click Quest Title**: Opens the **Quest Context Menu**.
* **Left-Click Zone Header**: Expands or collapses that zone's quest list.
* **Left-Click Quest Collapse Button (`[-]`/`[+]`)**: Collapses or expands that individual quest block.
* **Alt + Right-Click Tracker Body**: Quickly opens the full Options Panel.
* **Left-Click Quest Item Button**: Uses the associated quest item.
* **Click-to-Share Badge (`[Share]`)**: When a party member lacks the quest, a badge appears allowing you to share the quest with one click.

### Quest Right-Click Context Menu

Right-clicking any quest title displays a dedicated context menu:

* **Stop Tracking / Track Quest**: Toggles Blizzard quest watch status.
* **Link to Chat**: Inserts formatted quest details into the active chat channel.
* **Share Quest**: Sends the quest offer to your party.
* **Set Waypoint (TomTom)**: Creates a navigation arrow and map marker if TomTom is loaded.
* **Open in Quest Log**: Expands the log directly to this quest.
* **Copy Wowhead URL**: Opens a copy-paste dialog with the exact Wowhead database link.
* **Abandon Quest**: Prompts an immediate confirmation dialog to abandon the quest without needing to open the quest log.

### Interactive Sizing Guide & Overlay

When configuring the tracker via the **Sizing** tab, you can enable the **Visual Sizing Guide**:
* Highlights the tracker boundary with a high-contrast dashed border.
* Displays the current pixel dimensions (`Width × Max Height`).
* Provides a draggable resize handle at the bottom-right corner to adjust tracker width and maximum height in real time.

---

## Slash Commands

You can manage the tracker using `/bfq`, `/bqt`, or `/bleaktracker`:

| Command | Description |
| :--- | :--- |
| `/bfq` or `/bqt` | Opens the graphical AceConfig options window. |
| `/bfq lock` | Locks the tracker frame position to prevent accidental dragging. |
| `/bfq unlock` | Unlocks the tracker frame so it can be moved. |
| `/bfq toggle` | Minimizes or expands the quest tracker. |
| `/bfq reset` | Resets the tracker to its default screen position (`TOPRIGHT`). |
| `/bfq profile [name]` | Displays the active profile or switches to a named profile. |

---

## Configuration Guide

The configuration panel can be opened with `/bfq`, `/bqt`, or via the `[...]` menu. It is organized into 8 intuitive tabs:

### 1. General
* **Lock Tracker Position**: Toggles mouse dragging on the header bar.
* **Auto-hide Tracker When Empty**: Hides the container completely when no quests are being tracked.
* **Auto-collapse in Dungeons & Raids**: Automatically minimizes the tracker upon entering an instance.
* **Quest Filter Mode**: Switch between:
  - *All Quests*: Tracks all quests in your log up to the tracker height.
  - *Current Zone Only*: Automatically filters the view to quests within your current subzone/zone.
  - *Watched (Shift-Clicked) Only*: Only displays quests you have manually watched.
* **Reset Position**: Returns the tracker to default coordinates.

### 2. Sizing
* **Tracker Width**: Adjusts width from `180px` to `500px` (default: `280px`).
* **Maximum Height**: Sets maximum downward expansion from `200px` to `1200px` before content is clipped.
* **Show Visual Sizing Guide**: Toggles the interactive resizing frame and handles.
* **Tracker Scale**: Scales the entire UI container from `50%` to `200%`.

### 3. Fonts & Typography
* **Font Family**: Select any font registered in `LibSharedMedia-3.0` (or defaults like *Friz Quadrata TT*).
* **Header Font Size**: Font size for quest titles (range: `8` to `24`).
* **Objective Font Size**: Font size for objective lines and progress descriptions (range: `8` to `20`).
* **Font Outline**: Toggle between `None`, `Outline`, `Thick Outline`, `Monochrome`, or `Outline Monochrome`.
* **Color by Quest Difficulty**: Colors quest titles based on player level versus quest level (Grey, Green, Yellow, Orange, Red).

### 4. Appearance & Backdrop
* **Show Backdrop**: Enable or disable the background panel.
* **Background Texture**: Choose solid or patterned textures via LibSharedMedia.
* **Border Texture**: Choose border styles (e.g., Tooltip, Dialog, Solid).
* **Border Edge Size**: Thickness of the frame border (`1` to `32`).
* **Background Color & Opacity**: Full RGBA color picker for the backdrop.
* **Border Color & Opacity**: Full RGBA color picker for the frame border.
* **Padding**: Internal padding between frame edge and quest contents (`0` to `24px`).

### 5. Headers & Sections
* **Main Header Texture**: Background style for the top bar (`None`, `Flat`, `Gradient`, `Blizzard`).
* **Header Texture Color**: Custom RGBA tint for the header bar.
* **Header Title Color**: Custom RGBA color for the "Quests" title text.
* **Header Button Color**: Color tint for header buttons (`[Log]`, `[Zone]`, `[All]`, `[...]`, `[-]`).
* **Quest Count Format**: Choose between `None`, `Short` (`(5/40)`), or `Full` (`(5/40 Quests)`).
* **Collapsed Text Mode**: What to display when collapsed (`None`, `Counter`, or `Title`).
* **Header Button Toggles**: Individual toggles to show/hide the Log, Zone, All, Menu, or Collapse buttons.
* **Zone / Section Headers**:
  - *Group Quests by Zone*: Toggles zone section separators.
  - *Show Zone Quest Count*: Shows total quests in that zone (e.g. `Westfall (4)`).
  - *Zone Header Texture*: Texture styling for zone banners (`None`, `Flat`, `Gradient`, `Blizzard`).
  - *Zone Header Color*: RGBA tint for zone banners.

### 6. Sorting & Filtering
* **Sort Mode**:
  - *Level*: Orders quests by recommended level ascending (default).
  - *Zone*: Orders quests alphabetically by zone name.
* **Move Completed to Bottom**: Automatically pushes completed quests ready for turn-in to the bottom of the list.
* **Show Group & Difficulty Tags**: Displays badges for elite quests (`[11+]`), dungeons (`[d]`), and raids (`[r]`).

### 7. Social, Automation & Audio
* **Auto-Share Quests**: Automatically shares newly accepted quests with group members.
* **Auto-Accept Quests (NPC)**: Instantly accepts quests offered by friendly NPCs.
* **Auto-Accept Shared Quests**: Automatically accepts quests shared by group members.
* **Auto-Turn In Quests**: Automatically completes quests with 0 or 1 item choices.
* **Hold Shift to Bypass**: Holding `Shift` while interacting with an NPC temporarily disables all automation.
* **Enable Party Sync**: Transmits objective progress and quest states to group members running the addon.
* **Announce Completions to Party**: Sends chat notifications to Party/Raid/Instance chat when finishing an objective or quest.
* **Play Sound on Complete**: Triggers an audio chime when an objective or quest is finished.
* **Sound Effect Choice**: Choose between *Peon ("Work complete!")*, *Classic Quest Complete*, *Level Up Fanfare*, *Raid Warning*, *Ready Check*, *Mini-Map Ping*, or *PvP Horn*. Includes a live sound preview button.

### 8. Profiles
* **Global "Default" Profile**: All characters initially share the `"Default"` profile. Any changes made to settings or position are automatically shared account-wide across all your characters.
* **Per-Character Customization**: Switch to a character-specific profile at any time in the Profiles tab (or create custom named profiles for alts, roles, or screen setups).
* **Profile Management**: Full support for copying settings between profiles, creating new profiles, and resetting to addon defaults.
* **Slash Command Switching**: Use `/bfq profile` to see your active profile, or `/bfq profile <name>` to switch instantly.

---

## Code Architecture & Function Reference

The addon is structured modularly under the private internal namespace `ns`:

```
BleakfibersQuestTracker-Forever/
├── BleakfibersQuestTracker-Forever.toc # Primary Addon manifest
├── Core.lua                            # Lifecycle events, AceDB profile system, module manager, callbacks
├── Config.lua                          # AceConfig table, options panel, custom quick menu & copy dialog
├── TrackerFrame.lua                    # Primary UI frame, header controls, sizing guide, backdrop
├── Modules/
│   ├── StandaloneTracker.lua           # Object pooling, quest rendering, event hooks, context menus
│   └── SocialModule.lua                # Quest automation, party sync protocol (BFQ_SYNC), sound alerts
├── Archive/                            # Preserved integration modules for future reference
│   └── Modules/
│       ├── QuestieIntegration.lua
│       └── ElvUIIntegration.lua
└── Libs/                               # Ace3, LibSharedMedia-3.0, CallbackHandler, Compat.lua
```

---

### Core Architecture (`Core.lua`)

`Core.lua` manages SavedVariables initialization, the internal callback event bus, and module lifecycle management.

#### Global / Namespace Variables
* `ns.addonName` *(string)*: Addon folder name.
* `ns.title` *(string)*: Formatted title with color codes.
* `ns.version` *(string)*: Version string read from the TOC file.
* `ns.defaultDB` *(table)*: Comprehensive schema of default profile settings.
* `ns.dbObject` *(table)*: AceDB-3.0 database instance (`BleakfiberTrackerDB`).
* `ns.db` *(table)*: Active profile pointer referencing `BleakfiberTrackerDB.profile` (defaults to `"Default"`).
* `ns.modules` *(table)*: Hash map of registered module tables.
* `ns.callbacks` *(table)*: Hash map of registered event callback functions.

#### Core Functions

##### `ns.Print(...)`
Prints formatted output to the default chat frame with the `[Bleakfiber's Quest Tracker - Forever]` prefix.

##### `ns.CopyDefaults(src, dest)`
Recursively copies missing default key-value pairs from `src` into `dest`.

##### `ns:RegisterCallback(event, func)`
Registers a listener function on the internal callback bus.

##### `ns:FireCallback(event, ...)`
Dispatches a callback event to all subscribed listeners.

##### `ns:RegisterModule(name, moduleTable)`
Registers a submodule table into `ns.modules` and assigns its internal name.

##### `ns:GetModule(name)`
Retrieves a registered module by its string name.

##### `ns:InitializeModules()`
Iterates through all registered modules and safely calls their `Initialize()` methods wrapped in `pcall`.

---

### Tracker Frame (`TrackerFrame.lua`)

`TrackerFrame.lua` implements the main container window (`BleakfiberQuestTrackerFrame`), the customizable header bar, the resizing overlay, and frame backdrop/typography logic.

#### Key Functions on `ns.Tracker`

##### `Tracker:Initialize()`
Constructs the main container frame, anchors it to screen coordinates stored in `ns.db`, sets up dragging logic, and instantiates the header frame and its control buttons (`[Log]`, `[Zone]`, `[All]`, `[...]`, `[-]`).

##### `Tracker:UpdateBackdrop()`
Applies user-selected backdrop textures, edge files, border sizes, colors, and insets to `BleakfiberQuestTrackerFrame` using `BackdropTemplate`.

##### `Tracker:ApplyHeaderSettings()`
Refreshes the header bar's background texture (Flat, Gradient, Blizzard, None), text color, button tint, and visibility of individual header buttons based on current settings.

##### `Tracker:UpdateFilterButtons()`
Updates the highlighted visual state of the `[Zone]` and `[All]` filter buttons on the header depending on whether current-zone filtering is active.

##### `Tracker:CreateConfigOverlay()` / `Tracker:ShowConfigOverlay()` / `Tracker:HideConfigOverlay()`
Creates and toggles the visual sizing guide frame with dashed green border, dimension label, and a bottom-right drag handle for interactive resizing.

##### `Tracker:UpdateTypography()`
Fetches current font selections and sizes from LibSharedMedia and applies them to the header title, quest count label, and pooled quest content blocks.

##### `Tracker:SetLocked(locked)`
Locks or unlocks the frame. When locked, mouse dragging on the header is disabled.

##### `Tracker:RestorePosition()`
Restores the tracker frame's screen position based on coordinates saved in the active profile (`ns.db`), applying scale normalization and clearing Blizzard's layout cache (`SetUserPlaced(false)`).

##### `Tracker:ResetPosition()`
Resets the tracker to the default screen position (`TOPRIGHT`, -250, -200), anchors it for downward growth, synchronizes SavedVariables, and clears Blizzard's layout cache.

##### `Tracker:ToggleCollapse()`
Toggles the expanded/collapsed state of the tracker contents and updates the collapse button icon (`-` or `+`).

##### `Tracker:UpdateHeight(contentHeight)`
Recalculates the tracker frame height based on rendered content height and clamps it to `maxHeight`. Hides the frame if empty and `autoHideEmpty` is enabled.

---

### Standalone Tracker Engine (`Modules/StandaloneTracker.lua`)

`StandaloneTracker.lua` handles quest log inspection, objective parsing, object pooling, quest item buttons, and layout rendering.

#### Object Pooling Functions
* `AcquireQuestBlock(parent)`: Retrieves or instantiates a recyclable frame for an individual quest.
* `AcquireObjectiveString(parent)`: Retrieves or instantiates a recyclable `FontString` for quest objective lines.
* `AcquirePartyString(parent)`: Retrieves or instantiates a recyclable `FontString` for displaying party member progress.
* `AcquireShareButton(parent)`: Retrieves or instantiates a recyclable clickable `[Share]` button for party synchronization.
* `AcquireItemButton(parent)`: Retrieves or instantiates a recyclable `ItemButton` configured to cast or use quest items.
* `AcquireZoneHeader(parent)`: Retrieves or instantiates a recyclable collapsible section header for zone groupings.

#### Engine Functions

##### `StandaloneTracker:Initialize()`
Hides the default Blizzard watch frame, registers quest log and inventory events (`QUEST_LOG_UPDATE`, `QUEST_WATCH_UPDATE`, `BAG_UPDATE`, `BAG_UPDATE_COOLDOWN`, `ZONE_CHANGED_NEW_AREA`), and connects to internal callbacks.

##### `StandaloneTracker:GetTrackedQuests()`
Scans the player's quest log, determines completion status, parses objectives, resolves zone names, checks for quest items in bags, and applies the selected sorting algorithm (Level or Zone).
* **Returns**: `table` — An array of processed quest data objects.

##### `StandaloneTracker:UpdateTracker()`
Main render cycle:
1. Gathers sorted quests from `GetTrackedQuests()`.
2. Releases unused pool objects back to their respective pools.
3. Groups quests by zone (if enabled).
4. Renders zone banners, quest titles, collapse icons, objective lines, party sync lines, and quest item buttons.
5. Calculates total rendered height and calls `Tracker:UpdateHeight()`.

##### `StandaloneTracker:OpenQuestContextMenu(anchor, qInfo)`
Constructs and displays the right-click dropdown context menu anchored to the clicked quest block.

---

### Social & Automation Module (`Modules/SocialModule.lua`)

`SocialModule.lua` handles quest automation, sound alerts, and the hidden party sync communications channel.

#### Sound Functions

##### `SocialModule:PlaySoundKey(choice)`
Plays a registered sound preset using `PlaySoundFile` (FileDataID) or `PlaySound` (SoundKit ID).
* **Parameters**: `choice` *(string)* — One of `"peon"`, `"quest_complete"`, `"level_up"`, `"raid_warning"`, `"ready_check"`, `"map_ping"`, `"pvp_horn"`.

##### `SocialModule:PlayPreviewSound(choice)`
Plays a sound preset immediately for settings testing.

##### `SocialModule:PlayCompletionSound()`
Throttled sound trigger called when a quest or objective is completed. Checks if sound alerts are enabled in settings.

#### Automation & Social Functions

##### `SocialModule:BroadcastMyQuests()`
Iterates through all quests and objectives in the local quest log and transmits current progress to the party via hidden addon message prefix `BFQ_SYNC`.

##### `SocialModule:ShareQuest(questID, questLogIndex)`
Safely shares a quest with the party using `QuestLogPushQuest(questLogIndex)` with index validation.

##### `SocialModule:GetObjectivePartyProgress(questID, objIndex)`
Retrieves cached progress for group members on a specific objective.

##### `SocialModule:GetMissingPartyInfo(questID, questLogIndex)`
Compares the group roster against `ns.partyQuestData` to determine which group members do not have this quest.

---

### Configuration & Dialogs (`Config.lua`)

`Config.lua` registers the AceConfig-3.0 options table, handles slash commands, and manages custom popups.

#### Key Functions on `ns.Config`

##### `Config:InitializeOptions()`
Registers the addon options table with `AceConfig-3.0` and adds it to the Blizzard Interface Options via `AceConfigDialog-3.0`.

##### `Config:ToggleConfigFrame()`
Opens or closes the graphical options window. Automatically activates the visual sizing guide if the Sizing tab is viewed.

##### `Config:OpenFilterMenu(anchor)` *(or `Config.OpenQuickMenu`)*
Opens the lightweight, independent dropdown menu from the `[...]` header button, offering quick toggles for filters, locking, and sorting.

##### `Config:ShowCopyDialog(url, questTitle)`
Displays a draggable, modal dialog (`BleakfiberCopyURLDialog`) containing an edit box with the pre-selected Wowhead URL ready for copying with `Ctrl+C`.

---

## Dependencies

### Required
* **None**: Bleakfiber's Quest Tracker contains built-in fallback routines and runs completely standalone.

### Embedded Libraries (Included in `Libs/`)
* **AceAddon-3.0**, **AceEvent-3.0**, **AceTimer-3.0**, **AceConsole-3.0**, **AceGUI-3.0**, **AceConfig-3.0**, **AceDB-3.0**, **AceDBOptions-3.0**
* **LibSharedMedia-3.0**
* **CallbackHandler-1.0**

### Optional Helpers
* **TomTom**: Enables navigation waypoints from the right-click context menu.

---

## Installation

1. Download the latest release from the [Releases](https://github.com/Bleakfiber/BleakfibersQuestTracker-Forever/releases) page.
2. Exit World of Warcraft.
3. Extract the downloaded zip archive.
4. Move the `BleakfibersQuestTracker-Forever` folder into your World of Warcraft AddOns directory:
   - **World of Warcraft: Forever**: `_forever_\Interface\AddOns\BleakfibersQuestTracker-Forever`
5. Launch the game, log into your character, and type `/bfq` to configure the tracker.

---

## License & Contributing

* **License**: This project is licensed under a **Source-Available Restricted License** (All Rights Reserved, No Derivatives). See [LICENSE.md](LICENSE.md) for full terms.
* **Contributing**: Contributions, bug reports, and suggestions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting pull requests or opening issues.
