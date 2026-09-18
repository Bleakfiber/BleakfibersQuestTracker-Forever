local addonName, ns = ...

-- Addon metadata & global access
ns.addonName = addonName
ns.title = "|cff00c0ffBleakfiber's Quest Tracker - Forever|r"
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) 
    or (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")) 
    or "0.0.1"

-- Print helper with colored prefix
function ns.Print(...)
    print("|cff00c0ff[" .. addonName .. "]|r", ...)
end

-- Debug helper (silent by default, toggleable via /bfq debug)
ns.debugMode = false
function ns.Debug(...)
    if ns.debugMode then
        print("|cff00c0ff[" .. addonName .. " Debug]|r", ...)
    end
end

-- Player Class & Faction Color Helpers
function ns.GetClassColor()
    local _, classFilename = UnitClass("player")
    local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFilename]) 
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename])
    if c then
        return { r = c.r, g = c.g, b = c.b }
    end
    return { r = 0.0, g = 0.75, b = 1.0 }
end

function ns.GetFactionColor()
    local englishFaction = UnitFactionGroup("player")
    if englishFaction == "Alliance" then
        return { r = 0.0, g = 0.44, b = 0.87 }
    elseif englishFaction == "Horde" then
        return { r = 0.87, g = 0.13, b = 0.13 }
    end
    return { r = 1.0, g = 0.82, b = 0.0 }
end

-- Cross-version Quest API Helpers (WoW Forever 1.60.1+ / Classic Era 1.15+)
function ns.GetNumQuestLogEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
        local numQuests = 0
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
            if info and not info.isHeader and not info.isHidden then
                numQuests = numQuests + 1
            end
        end
        return numEntries, numQuests
    elseif GetNumQuestLogEntries then
        local entries, quests = GetNumQuestLogEntries()
        return entries or 0, quests or 0
    end
    return 0, 0
end

function ns.GetQuestLogTitle(i)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(i)
        if info then
            local isComplete = (info.isComplete and 1) or 0
            return info.title, info.level, info.suggestedGroup, info.isHeader, info.isCollapsed, isComplete, info.frequency, info.questID
        end
    elseif GetQuestLogTitle then
        return GetQuestLogTitle(i)
    end
    return nil
end

function ns.GetQuestObjectives(questID, questLogIndex)
    local objectives = {}
    if questID and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local list = C_QuestLog.GetQuestObjectives(questID)
        if list and #list > 0 then
            for _, obj in ipairs(list) do
                table.insert(objectives, {
                    text = obj.text or "",
                    finished = obj.finished or false,
                    type = obj.type or ""
                })
            end
            return objectives
        end
    end

    if questLogIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local numLeaderBoards = GetNumQuestLeaderBoards(questLogIndex) or 0
        for j = 1, numLeaderBoards do
            local desc, objType, done = GetQuestLogLeaderBoard(j, questLogIndex)
            if desc then
                table.insert(objectives, {
                    text = desc,
                    finished = done,
                    type = objType
                })
            end
        end
    end
    return objectives
end

function ns.IsQuestPushable(questID, questLogIndex)
    if questID and C_QuestLog and C_QuestLog.IsPushableQuest then
        return C_QuestLog.IsPushableQuest(questID)
    end
    if questLogIndex and GetQuestLogPushable and SelectQuestLogEntry then
        SelectQuestLogEntry(questLogIndex)
        return GetQuestLogPushable() and true or false
    end
    return false
end

function ns.ShareQuest(questID, questLogIndex)
    if questID and C_QuestLog and C_QuestLog.ShareQuest then
        C_QuestLog.ShareQuest(questID)
        return true
    end
    if questLogIndex and SelectQuestLogEntry and QuestLogPushQuest then
        SelectQuestLogEntry(questLogIndex)
        QuestLogPushQuest()
        return true
    end
    return false
end

-- Default Settings
ns.defaultDB = {
    profile = {
        -- Positioning & Sizing
        framePosition = nil,
        width = 280,
        maxHeight = 600,
        scale = 1.0,
        isLocked = false,
        collapsedQuests = {},     -- [questID or title] = true when user collapsed the quest
        collapsedZones = {},      -- [zoneName] = true when user collapsed a zone header

        -- Headers Configuration
        headers = {
            -- Main Tracker Header Bar
            texture = "flat",              -- "none", "flat", "gradient", "blizzard"
            textureColor = { r = 0.05, g = 0.08, b = 0.12, a = 0.85 },
            textureColorShare = false,     -- Share color with tracker border
            textColor = nil,               -- Defaults dynamically to player's Class Color
            textColorShare = false,        -- Share text color with tracker border
            buttonColor = nil,             -- Defaults dynamically to player's Class Color
            buttonColorShare = false,      -- Share button color with tracker border
            countFormat = "short",         -- "none", "short" ((5/40)), "full" ((5/40 Quests))
            collapsedText = "counter",     -- "none", "counter", "title"
            showQuestLogBtn = true,        -- [Log] button that toggles QuestLogFrame
            showZoneBtn = true,            -- [Zone] filter toggle button
            showAllBtn = true,             -- [All] filter toggle button
            showMenuBtn = true,            -- [...] options menu button
            showCollapseBtn = true,        -- [-] collapse button

            -- Zone / Section Headers in Tracker
            showZoneHeaders = true,        -- Group quests under collapsible Zone headers
            showZoneCount = true,          -- Show count e.g. Durotar (3)
            zoneHeaderTexture = "gradient", -- "none", "flat", "gradient", "blizzard"
            zoneHeaderColor = { r = 1.0, g = 0.82, b = 0.0, a = 1.0 }, -- Classic gold
            zoneHeaderColorShare = false,  -- Share with border color
        },

        -- Appearance & Backdrop
        backdrop = {
            show = true,
            bgFile = "Solid", -- Default or SharedMedia
            edgeFile = "Solid",
            edgeSize = 1,
            bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.65 },
            borderColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.9 },
            padding = 8,
        },

        -- Typography
        fonts = {
            font = "Friz Quadrata TT",
            headerFont = "Friz Quadrata TT",
            headerSize = 13,
            headerOutline = "OUTLINE",
            objectiveFont = "Friz Quadrata TT",
            objectiveSize = 11,
            objectiveOutline = "NONE",
            colorDifficulty = true,
        },

        -- Filtering & Behavior
        filtering = {
            filterMode = "all", -- "all", "zone", "watched"
            zoneOnly = false,
            autoHideInInstances = false,
            autoHideEmpty = true,
            collapseInCombat = false,
        },

        -- Sorting
        sorting = {
            mode = "level", -- "level", "zone"
            moveCompletedToBottom = false, -- Push "Ready for turn-in" quests to bottom of tracker
            showGroupTags = true,          -- Show [11+] elite/group and dungeon badges
        },

        -- Social & Quest Automation
        social = {
            autoShare = false,           -- Auto-share quests to party upon accept
            autoAcceptNPC = false,       -- Auto-accept quests from NPCs
            autoAcceptShared = false,    -- Auto-accept quests shared by party members
            autoTurnIn = false,          -- Auto-turnin quests with 0 or 1 reward choice
            shiftBypass = true,          -- Hold Shift to temporarily bypass automation
            enablePartySync = true,      -- Party quest progress sync and click-to-share
            announceToParty = false,     -- Announce objective/quest completion to party chat
        },

        -- Audio & Sounds
        sound = {
            enableCompleteSound = false, -- Play sound on quest/objective complete
            soundChoice = "peon",        -- "peon", "quest_complete", "raid_warning", "level_up"
        },
    },
}

-- Recursive table copy for defaults merging
local function CopyDefaults(src, dest)
    if type(src) ~= "table" then return {} end
    if type(dest) ~= "table" then dest = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = CopyDefaults(v, dest[k])
        elseif dest[k] == nil then
            dest[k] = v
        end
    end
    return dest
end
ns.CopyDefaults = CopyDefaults

-- Simple internal event/callback bus
ns.callbacks = {}

function ns:RegisterCallback(event, func)
    if not self.callbacks[event] then
        self.callbacks[event] = {}
    end
    table.insert(self.callbacks[event], func)
end

function ns:FireCallback(event, ...)
    if self.callbacks[event] then
        for _, func in ipairs(self.callbacks[event]) do
            func(...)
        end
    end
end

-- Module Management System
ns.modules = {}

function ns:RegisterModule(name, moduleTable)
    if not name or type(moduleTable) ~= "table" then return end
    self.modules[name] = moduleTable
    moduleTable.name = name
end

function ns:GetModule(name)
    return self.modules[name]
end

function ns:InitializeModules()
    for name, mod in pairs(self.modules) do
        if type(mod.Initialize) == "function" then
            local success, err = pcall(mod.Initialize, mod)
            if not success then
                print("|cffff3333[" .. addonName .. " Error]|r Failed to initialize module '" .. name .. "': " .. tostring(err))
            end
        end
    end
end

-- Database Initialization (Event-Safe across ADDON_LOADED, VARIABLES_LOADED, and PLAYER_LOGIN)
local dbInitialized = false
local function InitializeDB(triggerEvent)
    if dbInitialized then return end

    local rawExists = _G["BleakfiberTrackerDB"] ~= nil
    -- If triggered early at ADDON_LOADED but SavedVariables haven't loaded yet, wait for VARIABLES_LOADED/PLAYER_LOGIN
    if not rawExists and triggerEvent == "ADDON_LOADED" then
        return
    end

    dbInitialized = true

    local hasProfiles = rawExists and type(_G["BleakfiberTrackerDB"].profiles) == "table"
    local defProfile = hasProfiles and _G["BleakfiberTrackerDB"].profiles["Default"]
    local defPos = defProfile and defProfile.framePosition
    ns.Debug(string.format("[DB Init via %s] RawDB=%s, HasProfiles=%s, SavedPos=%s", 
        tostring(triggerEvent),
        tostring(rawExists), 
        tostring(hasProfiles), 
        defPos and (defPos.point .. " (" .. tostring(defPos.x) .. ", " .. tostring(defPos.y) .. ")") or "none"))

    -- Migrate legacy profile structure if present
    if BleakfiberTrackerDB and BleakfiberTrackerDB.profile then
        if not BleakfiberTrackerDB.profiles then
            BleakfiberTrackerDB.profiles = { ["Default"] = BleakfiberTrackerDB.profile }
        elseif not BleakfiberTrackerDB.profiles["Default"] or not next(BleakfiberTrackerDB.profiles["Default"]) then
            BleakfiberTrackerDB.profiles["Default"] = BleakfiberTrackerDB.profile
        end
        BleakfiberTrackerDB.profile = nil
    end

    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if AceDB then
        -- "Default" as third argument ensures all characters share "Default" by default
        local dbObject = AceDB:New("BleakfiberTrackerDB", ns.defaultDB, "Default")
        ns.dbObject = dbObject
        ns.db = dbObject.profile

        local function OnProfileChanged()
            ns.db = dbObject.profile
            if not ns.db.collapsedQuests then
                ns.db.collapsedQuests = {}
            end
            if ns.db.sorting and ns.db.sorting.mode == "distance" then
                ns.db.sorting.mode = "level"
            end
            if ns.Tracker and ns.Tracker.UpdateSettings then
                ns.Tracker:UpdateSettings()
            end
            ns:FireCallback("SETTINGS_UPDATED")
            ns:FireCallback("QUEST_DATA_CHANGED")

            local ACR = LibStub and LibStub("AceConfigRegistry-3.0", true)
            if ACR then
                ACR:NotifyChange("BleakfiberQuestTracker")
                ACR:NotifyChange("BleakfiberQuestTracker_Profiles")
            end
        end

        dbObject:RegisterCallback("OnProfileChanged", OnProfileChanged)
        dbObject:RegisterCallback("OnProfileCopied", OnProfileChanged)
        dbObject:RegisterCallback("OnProfileReset", OnProfileChanged)
    else
        if not BleakfiberTrackerDB then
            BleakfiberTrackerDB = {}
        end
        BleakfiberTrackerDB = CopyDefaults(ns.defaultDB, BleakfiberTrackerDB)
        ns.db = BleakfiberTrackerDB.profile
    end

    -- Migrate legacy position fields
    if ns.db and not ns.db.framePosition and (ns.db.xOfs or (ns.db.point and ns.db.point ~= "TOPRIGHT")) then
        ns.db.framePosition = {
            point = ns.db.point or "TOPRIGHT",
            relativePoint = ns.db.relativePoint or ns.db.point or "TOPRIGHT",
            x = ns.db.xOfs or -250,
            y = ns.db.yOfs or -200,
        }
        ns.db.point = nil
        ns.db.relativePoint = nil
        ns.db.xOfs = nil
        ns.db.yOfs = nil
    end

    -- Restore from per-character backup if profile framePosition is missing
    if ns.db and not ns.db.framePosition and _G["BleakfiberTrackerCharDB"] and _G["BleakfiberTrackerCharDB"].framePosition then
        ns.db.framePosition = _G["BleakfiberTrackerCharDB"].framePosition
    end

    if not ns.db.collapsedQuests then
        ns.db.collapsedQuests = {}
    end
    if ns.db.sorting and ns.db.sorting.mode == "distance" then
        ns.db.sorting.mode = "level"
    end
    if not BleakfiberTrackerDB.partyQuestData then
        BleakfiberTrackerDB.partyQuestData = {}
    end
    ns.partyQuestData = BleakfiberTrackerDB.partyQuestData

    -- Default Header Text and Buttons to player's Class Color if still using legacy cyan default
    if ns.db and ns.db.headers then
        local tc = ns.db.headers.textColor
        if tc and tc.r == 0.0 and math.abs(tc.g - 0.75) < 0.01 and tc.b == 1.0 then
            ns.db.headers.textColor = nil
        end
        local bc = ns.db.headers.buttonColor
        if bc and bc.r == 0.0 and math.abs(bc.g - 0.75) < 0.01 and bc.b == 1.0 then
            ns.db.headers.buttonColor = nil
        end
    end

    local activeProf = (ns.dbObject and ns.dbObject.GetCurrentProfile and ns.dbObject:GetCurrentProfile()) or "none"
    local pos = ns.db and ns.db.framePosition
    ns.Debug(string.format("[DB Ready] profile=%s, pos=%s", 
        tostring(activeProf), 
        pos and (pos.point .. " (" .. tostring(pos.x) .. ", " .. tostring(pos.y) .. ")") or "default"))
end

-- Color Picker Enhancements: Quick-select Class Color & Faction Color on any ColorPicker
local function SetupColorPickerEnhancements()
    if not ColorPickerFrame or ColorPickerFrame.BleakfiberEnhanced then return end
    ColorPickerFrame.BleakfiberEnhanced = true

    local bar = CreateFrame("Frame", "BleakfiberColorPickerBar", ColorPickerFrame, BackdropTemplateMixin and "BackdropTemplate")
    bar:SetSize(310, 32)
    bar:SetPoint("TOP", ColorPickerFrame, "BOTTOM", 0, -3)

    if bar.SetBackdrop then
        bar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, tileSize = 0, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        bar:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
        bar:SetBackdropBorderColor(0.35, 0.35, 0.40, 0.9)
    end

    local function ApplyColor(r, g, b)
        r = math.max(0, math.min(1, r))
        g = math.max(0, math.min(1, g))
        b = math.max(0, math.min(1, b))

        -- Detect current alpha if present
        local a = 1
        if ColorPickerFrame.GetColorAlpha then
            local ok, val = pcall(ColorPickerFrame.GetColorAlpha, ColorPickerFrame)
            if ok and type(val) == "number" then a = val end
        elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
            local ok, val = pcall(OpacitySliderFrame.GetValue, OpacitySliderFrame)
            if ok and type(val) == "number" then a = val end
        end

        local colorObj = nil
        if CreateColor then
            colorObj = CreateColor(r, g, b, a)
        end

        ColorPickerFrame.r = r
        ColorPickerFrame.g = g
        ColorPickerFrame.b = b
        if colorObj then
            ColorPickerFrame.color = colorObj
        end

        -- 1. Modern ColorPickerFrame (10.2.5+ / Dragonflight / 1.15.2+):
        if colorObj and ColorPickerFrame.SetColor then
            pcall(ColorPickerFrame.SetColor, ColorPickerFrame, colorObj)
        end

        local cp = ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker
        if cp then
            if colorObj and cp.SetColor then
                pcall(cp.SetColor, cp, colorObj)
            end
            if cp.SetColorRGB then
                pcall(cp.SetColorRGB, cp, r, g, b)
            end
        end

        -- 2. Classic ColorPickerFrame:
        if ColorPickerFrame.SetColorRGB then
            pcall(ColorPickerFrame.SetColorRGB, ColorPickerFrame, r, g, b)
        end

        -- 3. Modern HexBox: set text AND trigger native OnEnterPressed / OnTextChanged
        local hexBox = ColorPickerFrame.Content and ColorPickerFrame.Content.HexBox
        if hexBox then
            local hexStr = string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
            if hexBox.SetText then
                pcall(hexBox.SetText, hexBox, hexStr)
            end
            local onEnter = hexBox:GetScript("OnEnterPressed")
            if onEnter then
                pcall(onEnter, hexBox)
            end
        end

        -- 4. Color Swatches
        if ColorSwatch then
            if ColorSwatch.SetColorTexture then
                pcall(ColorSwatch.SetColorTexture, ColorSwatch, r, g, b, a)
            elseif ColorSwatch.SetVertexColor then
                pcall(ColorSwatch.SetVertexColor, ColorSwatch, r, g, b)
            end
        end
        local contentSwatch = ColorPickerFrame.Content and ColorPickerFrame.Content.ColorSwatch
        if contentSwatch then
            if contentSwatch.SetColorTexture then
                pcall(contentSwatch.SetColorTexture, contentSwatch, r, g, b, a)
            elseif contentSwatch.SetVertexColor then
                pcall(contentSwatch.SetVertexColor, contentSwatch, r, g, b)
            end
        end

        -- 5. Fire AceGUI / Blizzard callbacks with temporary GetColorRGB wrapper to guarantee no desync
        local origGetColorRGB = ColorPickerFrame.GetColorRGB
        ColorPickerFrame.GetColorRGB = function() return r, g, b end

        local origGetColor = ColorPickerFrame.GetColor
        if colorObj and origGetColor then
            ColorPickerFrame.GetColor = function() return colorObj end
        end

        if ColorPickerFrame.info and ColorPickerFrame.info.swatchFunc then
            pcall(ColorPickerFrame.info.swatchFunc)
        end
        if ColorPickerFrame.swatchFunc then
            pcall(ColorPickerFrame.swatchFunc)
        end
        if ColorPickerFrame.func then
            pcall(ColorPickerFrame.func)
        end

        ColorPickerFrame.GetColorRGB = origGetColorRGB
        if origGetColor then
            ColorPickerFrame.GetColor = origGetColor
        end
    end

    -- Class Color Button
    local btnClass = CreateFrame("Button", "BleakfiberColorPickerClassBtn", bar, "UIPanelButtonTemplate")
    btnClass:SetSize(146, 24)
    btnClass:SetPoint("LEFT", bar, "LEFT", 6, 0)
    btnClass:SetText("") -- Clear default button text to use custom high-contrast layout

    local classSwatchBorder = btnClass:CreateTexture(nil, "BACKGROUND")
    classSwatchBorder:SetSize(16, 16)
    classSwatchBorder:SetPoint("LEFT", btnClass, "LEFT", 6, 0)
    classSwatchBorder:SetColorTexture(0, 0, 0, 1)

    local classSwatch = btnClass:CreateTexture(nil, "ARTWORK")
    classSwatch:SetSize(12, 12)
    classSwatch:SetPoint("CENTER", classSwatchBorder, "CENTER", 0, 0)

    local classLabel = btnClass:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classLabel:SetPoint("LEFT", classSwatchBorder, "RIGHT", 6, 0)
    classLabel:SetPoint("RIGHT", btnClass, "RIGHT", -4, 0)
    classLabel:SetJustifyH("LEFT")
    classLabel:SetTextColor(1, 1, 1, 1)
    if classLabel.SetShadowColor and classLabel.SetShadowOffset then
        classLabel:SetShadowColor(0, 0, 0, 1)
        classLabel:SetShadowOffset(1, -1)
    end

    btnClass:SetScript("OnClick", function()
        local c = ns.GetClassColor()
        ApplyColor(c.r, c.g, c.b)
    end)
    btnClass:SetScript("OnEnter", function(self)
        local curClass = UnitClass("player") or "Class"
        local c = ns.GetClassColor()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Set to Class Color", 1, 1, 1)
        GameTooltip:AddLine(string.format("Applies your %s color (|cff%02x%02x%02x#%02X%02X%02X|r) to this setting.",
            curClass, c.r * 255, c.g * 255, c.b * 255, c.r * 255, c.g * 255, c.b * 255), 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnClass:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Faction Color Button
    local btnFaction = CreateFrame("Button", "BleakfiberColorPickerFactionBtn", bar, "UIPanelButtonTemplate")
    btnFaction:SetSize(146, 24)
    btnFaction:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    btnFaction:SetText("") -- Clear default button text to use custom high-contrast layout

    local factionSwatchBorder = btnFaction:CreateTexture(nil, "BACKGROUND")
    factionSwatchBorder:SetSize(16, 16)
    factionSwatchBorder:SetPoint("LEFT", btnFaction, "LEFT", 6, 0)
    factionSwatchBorder:SetColorTexture(0, 0, 0, 1)

    local factionSwatch = btnFaction:CreateTexture(nil, "ARTWORK")
    factionSwatch:SetSize(12, 12)
    factionSwatch:SetPoint("CENTER", factionSwatchBorder, "CENTER", 0, 0)

    local factionLabel = btnFaction:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    factionLabel:SetPoint("LEFT", factionSwatchBorder, "RIGHT", 6, 0)
    factionLabel:SetPoint("RIGHT", btnFaction, "RIGHT", -4, 0)
    factionLabel:SetJustifyH("LEFT")
    factionLabel:SetTextColor(1, 1, 1, 1)
    if factionLabel.SetShadowColor and factionLabel.SetShadowOffset then
        factionLabel:SetShadowColor(0, 0, 0, 1)
        factionLabel:SetShadowOffset(1, -1)
    end

    btnFaction:SetScript("OnClick", function()
        local c = ns.GetFactionColor()
        ApplyColor(c.r, c.g, c.b)
    end)
    btnFaction:SetScript("OnEnter", function(self)
        local curFaction = UnitFactionGroup("player") or "Faction"
        local c = ns.GetFactionColor()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Set to Faction Color", 1, 1, 1)
        GameTooltip:AddLine(string.format("Applies your %s color (|cff%02x%02x%02x#%02X%02X%02X|r) to this setting.",
            curFaction, c.r * 255, c.g * 255, c.b * 255, c.r * 255, c.g * 255, c.b * 255), 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnFaction:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Dynamic positioning & button text/swatch refresh OnShow
    local function UpdateBar()
        bar:ClearAllPoints()
        local bottom = ColorPickerFrame:GetBottom()
        if bottom and bottom < 50 then
            bar:SetPoint("BOTTOM", ColorPickerFrame, "TOP", 0, 3)
        else
            bar:SetPoint("TOP", ColorPickerFrame, "BOTTOM", 0, -3)
        end

        local c = ns.GetClassColor()
        local cName = UnitClass("player") or "Class"
        classSwatch:SetColorTexture(c.r, c.g, c.b, 1)
        classLabel:SetText("Class: " .. cName)

        local f = ns.GetFactionColor()
        local fName = UnitFactionGroup("player") or "Faction"
        factionSwatch:SetColorTexture(f.r, f.g, f.b, 1)
        factionLabel:SetText("Faction: " .. fName)
    end

    ColorPickerFrame:HookScript("OnShow", UpdateBar)
    if ColorPickerFrame:HasScript("OnMouseUp") then
        ColorPickerFrame:HookScript("OnMouseUp", function()
            local bottom = ColorPickerFrame:GetBottom()
            bar:ClearAllPoints()
            if bottom and bottom < 50 then
                bar:SetPoint("BOTTOM", ColorPickerFrame, "TOP", 0, 3)
            else
                bar:SetPoint("TOP", ColorPickerFrame, "BOTTOM", 0, -3)
            end
        end)
    end
end
ns.SetupColorPickerEnhancements = SetupColorPickerEnhancements

-- Main Event Engine Frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitializeDB("ADDON_LOADED")
    elseif event == "VARIABLES_LOADED" then
        InitializeDB("VARIABLES_LOADED")
    elseif event == "PLAYER_LOGIN" then
        InitializeDB("PLAYER_LOGIN")
        SetupColorPickerEnhancements()

        -- Initialize Tracker container frame before modules hook into it
        if ns.Tracker and ns.Tracker.Initialize then
            ns.Tracker:Initialize()
        end

        -- Initialize registered modules
        ns:InitializeModules()
        ns:FireCallback("ON_INITIALIZE")

    elseif event == "PLAYER_ENTERING_WORLD" then
        ns:FireCallback("PLAYER_ENTERING_WORLD", ...)

    elseif event == "PLAYER_LOGOUT" then
        local rawExists = _G["BleakfiberTrackerDB"] ~= nil
        local hasProf = rawExists and type(_G["BleakfiberTrackerDB"].profiles) == "table"
        local def = hasProf and _G["BleakfiberTrackerDB"].profiles["Default"]
        local defPos = def and def.framePosition
        ns.Debug(string.format("[LOGOUT Check] RawDB=%s, Pos=%s", 
            tostring(rawExists), 
            defPos and (defPos.point .. " (" .. tostring(defPos.x) .. ", " .. tostring(defPos.y) .. ")") or "nil"))
    end
end)

