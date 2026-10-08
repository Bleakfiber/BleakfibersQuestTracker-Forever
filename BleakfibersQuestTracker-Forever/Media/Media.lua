local addonName, ns = ...

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM then return end

local mediaPath = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local fontPath = mediaPath .. "Fonts\\"

-- Default Font Constants
ns.DEFAULT_FONT_NAME = "Nata Sans Bold"
ns.DEFAULT_FONT_PATH = fontPath .. "NataSans-Bold.ttf"

ns.DEFAULT_HEADER_FONT_NAME = "Nata Sans Bold"
ns.DEFAULT_HEADER_FONT_PATH = fontPath .. "NataSans-Bold.ttf"

ns.DEFAULT_OBJECTIVE_FONT_NAME = "Nata Sans Regular"
ns.DEFAULT_OBJECTIVE_FONT_PATH = fontPath .. "NataSans-Regular.ttf"

-- Register Nata Sans Family (Default ADA Compliant / High Legibility)
LSM:Register("font", "Nata Sans Bold", fontPath .. "NataSans-Bold.ttf")
LSM:Register("font", "Nata Sans Regular", fontPath .. "NataSans-Regular.ttf")
LSM:Register("font", "Nata Sans", fontPath .. "NataSans-Regular.ttf")
LSM:Register("font", "Nata Sans Medium", fontPath .. "NataSans-Medium.ttf")

-- Register Orbitron Family (Futuristic / Geometric Display)
LSM:Register("font", "Orbitron Bold", fontPath .. "Orbitron-Bold.ttf")
LSM:Register("font", "Orbitron Medium", fontPath .. "Orbitron-Medium.ttf")
LSM:Register("font", "Orbitron Regular", fontPath .. "Orbitron-Regular.ttf")
LSM:Register("font", "Orbitron", fontPath .. "Orbitron-Regular.ttf")

-- Register Roboto Condensed Family (Clean / Compact Sans-Serif)
LSM:Register("font", "Roboto Condensed Bold", fontPath .. "RobotoCondensed-Bold.ttf")
LSM:Register("font", "Roboto Condensed Medium", fontPath .. "RobotoCondensed-Medium.ttf")
LSM:Register("font", "Roboto Condensed Regular", fontPath .. "RobotoCondensed-Regular.ttf")
LSM:Register("font", "Roboto Condensed", fontPath .. "RobotoCondensed-Regular.ttf")

-- Register Status Bar Textures
LSM:Register("statusbar", "BleakFlat", "Interface\\Buttons\\WHITE8x8")
LSM:Register("statusbar", "Blizzard", "Interface\\TargetingFrame\\UI-StatusBar")
LSM:Register("statusbar", "Blizzard Raid", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill")

-- Register Custom Audio Files & Pre-Configured Custom Slots
local soundPath = mediaPath .. "Sounds\\"
LSM:Register("sound", "Bleakfiber Beep", soundPath .. "beep.wav")
LSM:Register("sound", "Bleakfiber Click", soundPath .. "click.wav")
LSM:Register("sound", "Custom Sound 1 (custom1.wav)", soundPath .. "custom1.wav")
LSM:Register("sound", "Custom Sound 2 (custom2.wav)", soundPath .. "custom2.wav")
LSM:Register("sound", "Custom Sound 3 (custom3.wav)", soundPath .. "custom3.wav")
LSM:Register("sound", "Custom Sound 4 (custom4.wav)", soundPath .. "custom4.wav")
LSM:Register("sound", "Custom Sound 5 (custom5.wav)", soundPath .. "custom5.wav")

-- Sound Fetch Helper (resolves friendly slot keys, LSM names, or direct paths)
local customSoundSlots = {
    ["beep"] = soundPath .. "beep.wav",
    ["click"] = soundPath .. "click.wav",
    ["custom1"] = soundPath .. "custom1.wav",
    ["custom2"] = soundPath .. "custom2.wav",
    ["custom3"] = soundPath .. "custom3.wav",
    ["custom4"] = soundPath .. "custom4.wav",
    ["custom5"] = soundPath .. "custom5.wav",
}
ns.customSoundSlots = customSoundSlots

function ns.FetchSound(soundKey)
    if not soundKey or soundKey == "" then return nil end
    if customSoundSlots[soundKey] then
        return customSoundSlots[soundKey]
    end
    if type(soundKey) == "string" and (soundKey:find("%.wav$") or soundKey:find("%.ogg$") or soundKey:find("%.mp3$") or soundKey:find("\\") or soundKey:find("/")) then
        return soundKey
    end
    if LSM then
        local snd = LSM:Fetch("sound", soundKey, true)
        if snd and snd ~= "" then
            return snd
        end
    end
    return soundKey
end

-- Media Fetch Helper with safety fallbacks
function ns.FetchFont(fontName)
    local fallback = ns.DEFAULT_FONT_PATH
    if not fontName or fontName == "" then
        fontName = ns.DEFAULT_FONT_NAME
    end

    -- Direct file path support
    if type(fontName) == "string" and (fontName:find("%.ttf$") or fontName:find("%.otf$") or fontName:find("\\") or fontName:find("/")) then
        return fontName
    end

    -- Blizzard standard game font alias
    if fontName == "Friz Quadrata TT" or fontName == "Friz" then
        return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    end

    if LSM then
        local font = LSM:Fetch("font", fontName, true)
        if font and font ~= "" then
            return font
        end

        local def = LSM:Fetch("font", ns.DEFAULT_FONT_NAME, true)
        if def and def ~= "" then
            return def
        end
    end

    return fallback
end

-- Listen for late-registering media from third-party addons (SharedMedia packs, ElvUI, Details)
if LSM and LSM.RegisterCallback then
    LSM.RegisterCallback(ns, "LibSharedMedia_Registered", function(_, mediatype, key)
        if mediatype == "font" and ns.Tracker and ns.Tracker.UpdateTypography then
            ns.Tracker:UpdateTypography()
        end
    end)
end
