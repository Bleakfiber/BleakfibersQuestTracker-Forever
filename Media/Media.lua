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
