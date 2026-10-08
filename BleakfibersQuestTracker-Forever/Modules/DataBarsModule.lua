local addonName, ns = ...

-- Localized Lua & WoW API bindings for performance & zero table churn
local pairs, ipairs, type, tostring, tonumber, select, pcall = pairs, ipairs, type, tostring, tonumber, select, pcall
local string_format = string.format
local table_insert, table_remove = table.insert, table.remove
local wipe = table.wipe or wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local math_floor, math_ceil, math_max, math_min = math.floor, math.ceil, math.max, math.min
local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
local UnitXP, UnitXPMax, UnitLevel = UnitXP, UnitXPMax, UnitLevel
local GetXPExhaustion = GetXPExhaustion
local GetZoneText, GetSubZoneText, GetZonePVPInfo = GetZoneText, GetSubZoneText, GetZonePVPInfo
local ToggleWorldMap = ToggleWorldMap
local IsShiftKeyDown = IsShiftKeyDown
local C_QuestLog = C_QuestLog
local GetNumQuestLogEntries = GetNumQuestLogEntries
local GetQuestLogTitle = GetQuestLogTitle
local GetQuestLogRewardXP = GetQuestLogRewardXP
local C_Map = C_Map

local DataBarsModule = {}
ns.DataBarsModule = DataBarsModule
ns:RegisterModule("DataBarsModule", DataBarsModule)

-- Static Color Presets
local COLOR_XP_PURPLE      = { r = 0.58, g = 0.00, b = 0.83, a = 1.00 } -- Purple (Earned XP)
local COLOR_XP_RESTED      = { r = 0.00, g = 0.44, b = 0.88, a = 1.00 } -- Blue (Rested XP)
local COLOR_XP_QUEST_GHOST = { r = 0.25, g = 0.85, b = 0.45, a = 0.65 } -- Lighter Green (Completed Quest Turn-in XP)
local COLOR_XP_ALL_QUESTS  = { r = 0.12, g = 0.45, b = 0.25, a = 0.80 } -- Darker Green (All Quests Log XP)
local COLOR_XP_DING_READY  = { r = 1.00, g = 0.82, b = 0.00, a = 1.00 } -- Gold ([Ding Ready!] Alert)

local COLOR_TERRITORY = {
    ["sanctuary"] = { r = 0.40, g = 0.80, b = 1.00 }, -- Cyan
    ["friendly"]  = { r = 0.20, g = 1.00, b = 0.20 }, -- Green
    ["contested"] = { r = 1.00, g = 0.82, b = 0.00 }, -- Yellow / Gold
    ["hostile"]   = { r = 1.00, g = 0.20, b = 0.20 }, -- Red
    ["combat"]    = { r = 1.00, g = 0.45, b = 0.10 }, -- Orange
    ["default"]   = { r = 1.00, g = 0.82, b = 0.00 }, -- Default Gold
}

-- Frame References
local xpFrame = nil
local locFrame = nil
local timerFrame = nil

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, res1, res2, res3 = pcall(fn, ...)
    if ok then return res1, res2, res3 end
    return nil
end

local function GetLSMTexture(specificTexName)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local texName = specificTexName or (ns.db and ns.db.databars and ns.db.databars.barTexture) or (ns.db and ns.db.headers and ns.db.headers.statusbarTexture) or "Solid"
    local tex = LSM and LSM:Fetch("statusbar", texName)
    if tex then return tex end
    if texName == "Blizzard" or texName == "blizzard" then
        return "Interface\\TargetingFrame\\UI-StatusBar"
    end
    return "Interface\\Buttons\\WHITE8x8"
end

local BG_TEXTURE_PATHS = {
    ["solid"] = "Interface\\Buttons\\WHITE8x8",
    ["tooltip"] = "Interface\\Tooltips\\UI-Tooltip-Background",
    ["marble"] = "Interface\\FrameGeneral\\UI-Background-Marble",
    ["rock"] = "Interface\\FrameGeneral\\UI-Background-Rock",
    ["parchment"] = "Interface\\QuestFrame\\QuestBG",
    ["parchment_clean"] = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal",
}

local function ApplyBarBackdrop(frame, borderStyle, edgeSize, bgColor, borderColor, bgTexture)
    if not frame then return end

    local curDB = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    local useTrackerAppearance = (curDB and curDB.useTrackerAppearance ~= false)
    local trackerBackdrop = (ns.db and ns.db.backdrop) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.backdrop)

    if useTrackerAppearance and trackerBackdrop then
        if trackerBackdrop.show == false then
            borderStyle = "none"
            edgeSize = 0
            borderColor = { r = 0, g = 0, b = 0, a = 0 }
            bgColor = { r = 0, g = 0, b = 0, a = 0 }
            bgTexture = "solid"
        else
            borderStyle = trackerBackdrop.borderStyle or "flat"
            local tbWidth = trackerBackdrop.borderWidth
            if tbWidth == nil then tbWidth = trackerBackdrop.edgeSize end
            if tbWidth == nil then tbWidth = 1 end
            edgeSize = tbWidth
            borderColor = trackerBackdrop.borderColor or borderColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.90 }
            bgColor = trackerBackdrop.bgColor or bgColor or { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
            bgTexture = trackerBackdrop.bgTexture or "solid"
            if trackerBackdrop.classColorBorder and ns.GetClassColor then
                local cc = ns.GetClassColor()
                if cc then
                    borderColor = { r = cc.r, g = cc.g, b = cc.b, a = (borderColor and borderColor.a) or 0.90 }
                end
            end
        end
    else
        borderStyle = borderStyle or "flat"
        edgeSize = edgeSize or 1
        bgColor = bgColor or { r = 0.05, g = 0.05, b = 0.08, a = 0.85 }
        borderColor = borderColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.90 }
        bgTexture = bgTexture or "solid"
    end

    local bgPath = BG_TEXTURE_PATHS[bgTexture]
    if not bgPath then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        bgPath = (LSM and LSM:Fetch("background", bgTexture, true)) or "Interface\\Buttons\\WHITE8x8"
    end

    local edgeFile
    local insets = { left = 0, right = 0, top = 0, bottom = 0 }

    if borderStyle == "tooltip" then
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border"
        edgeSize = math_max(8, edgeSize or 14)
        local ins = math_max(2, math_min(4, math_floor(edgeSize * 0.25)))
        insets.left, insets.right, insets.top, insets.bottom = ins, ins, ins, ins
    elseif borderStyle == "dialog" then
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border"
        edgeSize = math_max(8, edgeSize or 14)
        local ins = math_max(2, math_min(4, math_floor(edgeSize * 0.25)))
        insets.left, insets.right, insets.top, insets.bottom = ins, ins, ins, ins
    elseif borderStyle == "toast" then
        edgeFile = "Interface\\FriendsFrame\\UI-Toast-Border"
        edgeSize = math_max(8, edgeSize or 12)
        local ins = math_max(2, math_min(3, math_floor(edgeSize * 0.22)))
        insets.left, insets.right, insets.top, insets.bottom = ins, ins, ins, ins
    elseif borderStyle == "thin" then
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border"
        edgeSize = math_max(8, math_min(12, edgeSize or 10))
        local ins = math_max(3, math_floor(edgeSize * 0.30))
        insets.left, insets.right, insets.top, insets.bottom = ins, ins, ins, ins
    elseif borderStyle == "none" then
        edgeFile = nil
        edgeSize = 0
        insets.left, insets.right, insets.top, insets.bottom = 0, 0, 0, 0
    else -- "flat"
        if edgeSize and edgeSize <= 0 then
            edgeFile = nil
            edgeSize = 0
        else
            edgeFile = "Interface\\Buttons\\WHITE8x8"
            edgeSize = edgeSize or 1
        end
        insets.left, insets.right, insets.top, insets.bottom = 0, 0, 0, 0
    end

    local backdropDef = {
        bgFile = (bgTexture ~= "parchment" and bgTexture ~= "parchment_clean") and bgPath or nil,
        edgeFile = edgeFile,
        tile = false,
        tileSize = 16,
        edgeSize = edgeSize,
        insets = insets,
    }

    if frame.ClearBackdrop then
        frame:ClearBackdrop()
    end
    frame.backdropInfo = nil
    frame:SetBackdrop(backdropDef)

    local ins = insets.left or 0
    if bgTexture == "parchment" or bgTexture == "parchment_clean" then
        if not frame.parchmentTex then
            local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
            frame.parchmentTex = tex
        end
        frame.parchmentTex:ClearAllPoints()
        frame.parchmentTex:SetPoint("TOPLEFT", frame, "TOPLEFT", ins, -ins)
        frame.parchmentTex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ins, ins)
        if bgTexture == "parchment_clean" then
            frame.parchmentTex:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal")
            frame.parchmentTex:SetTexCoord(0, 1, 0, 1)
        else
            frame.parchmentTex:SetTexture("Interface\\QuestFrame\\QuestBG")
            -- Horizontal slice of solid parchment art for thin databars without distortion or transparent gaps
            frame.parchmentTex:SetTexCoord(0.005, 0.582, 0.20, 0.55)
        end
        frame.parchmentTex:SetVertexColor(bgColor.r or 0.96, bgColor.g or 0.90, bgColor.b or 0.78, bgColor.a or 0.90)
        frame.parchmentTex:Show()
        frame:SetBackdropColor(0, 0, 0, 0)
    else
        if frame.parchmentTex then
            frame.parchmentTex:Hide()
        end
        frame:SetBackdropColor(bgColor.r or 0, bgColor.g or 0, bgColor.b or 0, bgColor.a or 0)
    end

    if backdropDef.edgeFile then
        frame:SetBackdropBorderColor(borderColor.r or 0.15, borderColor.g or 0.15, borderColor.b or 0.15, borderColor.a or 0.90)
    else
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end

    -- Re-anchor internal status bars to stay neatly inside border insets
    local function InsetBar(bar)
        if not bar then return end
        bar:ClearAllPoints()
        if ins > 0 then
            bar:SetPoint("TOPLEFT", frame, "TOPLEFT", ins, -ins)
            bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ins, ins)
        else
            bar:SetAllPoints(frame)
        end
    end

    InsetBar(frame.allQuestXPBar)
    InsetBar(frame.questXPBar)
    InsetBar(frame.restedBar)
    InsetBar(frame.playerBar)
    InsetBar(frame.statusBar)

    if frame.text and (frame == locFrame or frame == timerFrame) then
        local pad = 8 + ins
        frame.text:ClearAllPoints()
        frame.text:SetPoint("LEFT", frame, "LEFT", pad, 0)
        frame.text:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
    end
end

local function GetLSMFont()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local fontName = (ns.db and ns.db.fonts and ns.db.fonts.font) or "Nata Sans Bold"
    local font = LSM and LSM:Fetch("font", fontName)
    return font or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- ===========================================================================
-- 1. Experience & Completed Quest Log Progress Bar
-- ===========================================================================

local cachedCompletedQuests = {}
local completedQuestPool = {}

local function AcquireCompletedQuestEntry()
    local entry = table_remove(completedQuestPool)
    if not entry then
        entry = {}
    else
        wipe(entry)
    end
    return entry
end

local function ReleaseCompletedQuests()
    for i = 1, #cachedCompletedQuests do
        local e = cachedCompletedQuests[i]
        if e then
            table_insert(completedQuestPool, e)
            cachedCompletedQuests[i] = nil
        end
    end
end

local function ScanCompletedQuestLogXP()
    ReleaseCompletedQuests()
    local totalXP = 0
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and SafeCall(C_QuestLog.GetNumQuestLogEntries)) or (GetNumQuestLogEntries and SafeCall(GetNumQuestLogEntries)) or 0
    if numEntries == 0 then return 0, cachedCompletedQuests end

    for i = 1, numEntries do
        local title, level, _, isHeader, _, isComplete, _, questID
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = SafeCall(C_QuestLog.GetInfo, i)
            if info then
                title = info.title
                level = info.level
                isHeader = info.isHeader
                isComplete = (info.isComplete == 1 or info.isComplete == true)
                questID = info.questID
            end
        elseif GetQuestLogTitle then
            title, level, _, isHeader, _, isComplete, _, questID = SafeCall(GetQuestLogTitle, i)
        end

        if not isHeader and questID and (isComplete or (ns.IsQuestComplete and ns.IsQuestComplete(questID, i))) then
            local rewardXP = 0
            if GetQuestLogRewardXP then
                rewardXP = SafeCall(GetQuestLogRewardXP, questID) or 0
            end
            totalXP = totalXP + rewardXP
            local entry = AcquireCompletedQuestEntry()
            entry.questID = questID
            entry.title = title or ("Quest #" .. tostring(questID))
            entry.level = level or 0
            entry.rewardXP = rewardXP
            table_insert(cachedCompletedQuests, entry)
        end
    end

    return totalXP, cachedCompletedQuests
end

local cachedAllQuests = {}
local allQuestPool = {}

local function AcquireAllQuestEntry()
    local entry = table_remove(allQuestPool)
    if not entry then
        entry = {}
    else
        wipe(entry)
    end
    return entry
end

local function ReleaseAllQuests()
    for i = 1, #cachedAllQuests do
        local e = cachedAllQuests[i]
        if e then
            table_insert(allQuestPool, e)
            cachedAllQuests[i] = nil
        end
    end
end

local function ScanAllQuestLogXP()
    ReleaseAllQuests()
    local totalXP = 0
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and SafeCall(C_QuestLog.GetNumQuestLogEntries)) or (GetNumQuestLogEntries and SafeCall(GetNumQuestLogEntries)) or 0
    if numEntries == 0 then return 0, cachedAllQuests end

    for i = 1, numEntries do
        local title, level, _, isHeader, _, isComplete, _, questID
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = SafeCall(C_QuestLog.GetInfo, i)
            if info then
                title = info.title
                level = info.level
                isHeader = info.isHeader
                isComplete = (info.isComplete == 1 or info.isComplete == true)
                questID = info.questID
            end
        elseif GetQuestLogTitle then
            title, level, _, isHeader, _, isComplete, _, questID = SafeCall(GetQuestLogTitle, i)
        end

        if not isHeader and questID then
            local rewardXP = 0
            if GetQuestLogRewardXP then
                rewardXP = SafeCall(GetQuestLogRewardXP, questID) or 0
            end
            totalXP = totalXP + rewardXP
            local entry = AcquireAllQuestEntry()
            entry.questID = questID
            entry.title = title or ("Quest #" .. tostring(questID))
            entry.level = level or 0
            entry.rewardXP = rewardXP
            entry.isComplete = (isComplete or (ns.IsQuestComplete and ns.IsQuestComplete(questID, i)))
            table_insert(cachedAllQuests, entry)
        end
    end

    return totalXP, cachedAllQuests
end

function DataBarsModule:CreateXPBar()
    if xpFrame then return xpFrame end

    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)

    local f = CreateFrame("Button", "BleakfiberQuestTrackerXPBar", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    xpFrame = f
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(40)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")

    -- Dragging in Free Dock Mode
    f:SetScript("OnDragStart", function(self)
        local curDB = (ns.db and ns.db.databars)
        if curDB and curDB.xpDockMode == "free" and not curDB.locked then
            self:StartMoving()
            self.isMoving = true
        end
    end)
    f:SetScript("OnDragStop", function(self)
        if self.isMoving then
            self.isMoving = false
            self:StopMovingOrSizing()
            local curDB = (ns.db and ns.db.databars)
            if curDB and curDB.xpDockMode == "free" then
                local point, _, relPoint, x, y = self:GetPoint()
                curDB.xpFreePosition = { point = point, relativePoint = relPoint, x = x, y = y }
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            end
        end
    end)

    local barTex = GetLSMTexture(db and db.xpBarTexture)
    local cXP = (db and db.xpColor) or COLOR_XP_PURPLE
    local cRested = (db and db.restedColor) or COLOR_XP_RESTED
    local cQuest = (db and db.questXPColor) or COLOR_XP_QUEST_GHOST
    local cAllQuest = (db and db.allQuestXPColor) or COLOR_XP_ALL_QUESTS

    local baseLevel = f:GetFrameLevel() or 40

    -- Layer 1: All Active Quests XP "Ghost Bar" (Darker Green, lowest bar layer above frame background)
    local allQuestXPBar = CreateFrame("StatusBar", nil, f)
    f.allQuestXPBar = allQuestXPBar
    allQuestXPBar:SetAllPoints(f)
    allQuestXPBar:SetFrameLevel(baseLevel + 1)
    allQuestXPBar:SetStatusBarTexture(barTex)
    allQuestXPBar:SetStatusBarColor(cAllQuest.r, cAllQuest.g, cAllQuest.b, cAllQuest.a or 0.80)
    allQuestXPBar:SetMinMaxValues(0, 1)
    allQuestXPBar:SetValue(0)

    -- Layer 2: Completed Quest Log XP "Ghost Bar" (Lighter Green, above full quest log bar)
    local questXPBar = CreateFrame("StatusBar", nil, f)
    f.questXPBar = questXPBar
    questXPBar:SetAllPoints(f)
    questXPBar:SetFrameLevel(baseLevel + 2)
    questXPBar:SetStatusBarTexture(barTex)
    questXPBar:SetStatusBarColor(cQuest.r, cQuest.g, cQuest.b, cQuest.a or 0.65)
    questXPBar:SetMinMaxValues(0, 1)
    questXPBar:SetValue(0)

    -- Layer 3: Rested XP Status Bar (Blue - higher z draw distance so it is visible over top of any quest colors)
    local restedBar = CreateFrame("StatusBar", nil, f)
    f.restedBar = restedBar
    restedBar:SetAllPoints(f)
    restedBar:SetFrameLevel(baseLevel + 3)
    restedBar:SetStatusBarTexture(barTex)
    restedBar:SetStatusBarColor(cRested.r, cRested.g, cRested.b, cRested.a or 1.0)
    restedBar:SetMinMaxValues(0, 1)
    restedBar:SetValue(0)

    -- Layer 4: Active Player XP Status Bar (Top Layer, solid purple 0 to curXP)
    local playerBar = CreateFrame("StatusBar", nil, f)
    f.playerBar = playerBar
    playerBar:SetAllPoints(f)
    playerBar:SetFrameLevel(baseLevel + 4)
    playerBar:SetStatusBarTexture(barTex)
    playerBar:SetStatusBarColor(cXP.r, cXP.g, cXP.b, cXP.a or 1.0)
    playerBar:SetMinMaxValues(0, 1)
    playerBar:SetValue(0)

    ApplyBarBackdrop(f, db and db.xpBorderStyle, db and db.xpBorderWidth, db and db.xpBgColor, db and db.xpBorderColor, db and db.xpBgTexture)

    -- Overlay Text
    local text = playerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text = text
    text:SetPoint("CENTER", playerBar, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")

    self:ApplyTypography()

    -- Mouseover Tooltip & Click Handling
    f:SetScript("OnEnter", function(self)
        DataBarsModule:ShowXPTooltip(self)
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            if ns.Config and ns.Config.ToggleConfigFrame then
                ns.Config:ToggleConfigFrame()
            end
        end
    end)

    self:UpdateXPDocking()
    self:UpdateXPBar()
    return f
end

function DataBarsModule:UpdateXPDocking()
    if not xpFrame then return end
    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    if not db then return end

    local height = db.xpHeight or 14
    xpFrame:SetHeight(height)

    local dockMode = db.xpDockMode or "default_bar"

    if dockMode == "default_bar" then
        xpFrame:ClearAllPoints()
        xpFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 4)
        local width = db.xpWidth or 512
        xpFrame:SetWidth(width)
        xpFrame:SetUserPlaced(false)
    elseif dockMode == "tracker_bottom" then
        local tf = (ns.Tracker and ns.Tracker.frame) or _G["BleakfiberQuestTrackerContainer"] or _G["BleakfiberQuestTrackerFrame"]
        if tf then
            local spacing = tonumber(db.dockSpacing) or 0
            xpFrame:ClearAllPoints()
            xpFrame:SetPoint("TOPLEFT", tf, "BOTTOMLEFT", 0, -spacing)
            xpFrame:SetPoint("TOPRIGHT", tf, "BOTTOMRIGHT", 0, -spacing)
            xpFrame:SetUserPlaced(false)
        end
    elseif dockMode == "free" then
        xpFrame:ClearAllPoints()
        if db.xpFreePosition and db.xpFreePosition.point then
            local pos = db.xpFreePosition
            xpFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
        else
            xpFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
        end
        local width = db.xpWidth or 280
        xpFrame:SetWidth(width)
    end

    -- Suppress Blizzard default XP status tracking bar (default true, live toggleable)
    if db and db.hideBlizzardXPBar ~= false then
        self:SuppressBlizzardXP(true)
    else
        self:SuppressBlizzardXP(false)
    end

    if timerFrame and self.UpdateTimerDocking and db.timerDockMode == "tracker_bottom" then
        self:UpdateTimerDocking()
    end
end

function DataBarsModule:SuppressBlizzardXP(suppress)
    -- Modern 10.0+ engine StatusTrackingBarManager
    if StatusTrackingBarManager then
        if suppress then
            StatusTrackingBarManager:Hide()
            StatusTrackingBarManager:SetAlpha(0)
            if not self.hookedBlizzXP and StatusTrackingBarManager.HookScript then
                StatusTrackingBarManager:HookScript("OnShow", function(s)
                    local curDB = (ns.db and ns.db.databars)
                    if curDB and curDB.hideBlizzardXPBar ~= false then
                        s:Hide()
                        s:SetAlpha(0)
                    end
                end)
                self.hookedBlizzXP = true
            end
        else
            StatusTrackingBarManager:SetAlpha(1)
            StatusTrackingBarManager:Show()
        end
    end

    if MainStatusTrackingBarContainer then
        if suppress then
            MainStatusTrackingBarContainer:Hide()
            MainStatusTrackingBarContainer:SetAlpha(0)
        else
            MainStatusTrackingBarContainer:SetAlpha(1)
            MainStatusTrackingBarContainer:Show()
        end
    end

    if MainMenuExpBar then
        if suppress then
            MainMenuExpBar:Hide()
            MainMenuExpBar:SetAlpha(0)
            if not self.hookedMainMenuExpBar and MainMenuExpBar.HookScript then
                MainMenuExpBar:HookScript("OnShow", function(s)
                    local curDB = (ns.db and ns.db.databars)
                    if curDB and curDB.hideBlizzardXPBar ~= false then
                        s:Hide()
                        s:SetAlpha(0)
                    end
                end)
                self.hookedMainMenuExpBar = true
            end
        else
            MainMenuExpBar:SetAlpha(1)
            MainMenuExpBar:Show()
        end
    end

    if ReputationWatchBar then
        if suppress then
            ReputationWatchBar:Hide()
            ReputationWatchBar:SetAlpha(0)
        else
            ReputationWatchBar:SetAlpha(1)
            ReputationWatchBar:Show()
        end
    end
end

function DataBarsModule:UpdateXPBar()
    if not xpFrame or not xpFrame:IsShown() then return end

    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    local cXP = (db and db.xpColor) or COLOR_XP_PURPLE
    local cRested = (db and db.restedColor) or COLOR_XP_RESTED
    local cQuest = (db and db.questXPColor) or COLOR_XP_QUEST_GHOST
    local cAllQuest = (db and db.allQuestXPColor) or COLOR_XP_ALL_QUESTS
    local cDing = (db and db.dingReadyColor) or COLOR_XP_DING_READY
    local curXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 0
    local curLevel = UnitLevel("player") or 1
    local isMaxLevel = (maxXP == 0)

    local baseLevel = xpFrame:GetFrameLevel() or 40
    if xpFrame.allQuestXPBar then
        xpFrame.allQuestXPBar:SetFrameLevel(baseLevel + 1)
    end
    xpFrame.questXPBar:SetFrameLevel(baseLevel + 2)
    xpFrame.restedBar:SetFrameLevel(baseLevel + 3)
    xpFrame.playerBar:SetFrameLevel(baseLevel + 4)

    -- Texture Refresh
    local barTex = GetLSMTexture(db and db.xpBarTexture)
    xpFrame.playerBar:SetStatusBarTexture(barTex)
    xpFrame.questXPBar:SetStatusBarTexture(barTex)
    if xpFrame.allQuestXPBar then
        xpFrame.allQuestXPBar:SetStatusBarTexture(barTex)
    end
    xpFrame.restedBar:SetStatusBarTexture(barTex)

    -- Check Watched Reputation fallback at max level
    if isMaxLevel and db and db.showReputationAtMax then
        local watchedFaction = (C_Reputation and C_Reputation.GetWatchedFactionData and SafeCall(C_Reputation.GetWatchedFactionData))
        if watchedFaction and watchedFaction.name then
            local repCurrent = watchedFaction.currentStanding or 0
            local repMin = watchedFaction.currentReactionThreshold or 0
            local repMax = watchedFaction.nextReactionThreshold or 1
            local repSpan = math_max(1, repMax - repMin)
            local repProgress = math_max(0, repCurrent - repMin)
            local repPct = (repProgress / repSpan) * 100

            xpFrame.playerBar:SetMinMaxValues(0, repSpan)
            xpFrame.playerBar:SetValue(repProgress)
            xpFrame.playerBar:SetStatusBarColor(0.2, 0.7, 1.0, 0.9)

            xpFrame.questXPBar:Hide()
            if xpFrame.allQuestXPBar then xpFrame.allQuestXPBar:Hide() end
            xpFrame.restedBar:Hide()

            local standingText = (GetText and SafeCall(GetText, "FACTION_STANDING_LABEL" .. tostring(watchedFaction.reaction))) or ""
            xpFrame.text:SetText(string_format("%s: %s / %s (%s - %.1f%%)",
                watchedFaction.name,
                BreakUpLargeNumbers(repProgress),
                BreakUpLargeNumbers(repSpan),
                standingText ~= "" and standingText or "Rep",
                repPct))
            return
        end
    end

    if maxXP <= 0 then
        xpFrame.playerBar:SetMinMaxValues(0, 1)
        xpFrame.playerBar:SetValue(1)
        xpFrame.playerBar:SetStatusBarColor(cXP.r, cXP.g, cXP.b, cXP.a or 1.0)
        xpFrame.questXPBar:Hide()
        if xpFrame.allQuestXPBar then xpFrame.allQuestXPBar:Hide() end
        xpFrame.restedBar:Hide()
        xpFrame.text:SetText(string_format("Level %d (Max Level)", curLevel))
        return
    end

    -- Normal XP Progress Calculation
    xpFrame.playerBar:SetMinMaxValues(0, maxXP)
    xpFrame.playerBar:SetValue(curXP)
    xpFrame.playerBar:SetStatusBarColor(cXP.r, cXP.g, cXP.b, cXP.a or 1.0)

    -- Rested XP Overlay
    local restedXP = (GetXPExhaustion and SafeCall(GetXPExhaustion)) or 0
    if restedXP > 0 and db and db.showRestedXP ~= false then
        xpFrame.restedBar:Show()
        xpFrame.restedBar:SetMinMaxValues(0, maxXP)
        local restedTotal = math_min(maxXP, curXP + restedXP)
        xpFrame.restedBar:SetValue(restedTotal)
        xpFrame.restedBar:SetStatusBarColor(cRested.r, cRested.g, cRested.b, cRested.a or 1.0)
    else
        xpFrame.restedBar:Hide()
    end

    -- All Active Quests Log XP "Ghost Bar"
    local allQuestXP = 0
    if db and db.showAllQuestXP then
        allQuestXP = ScanAllQuestLogXP()
    end

    if allQuestXP > 0 and db and db.showAllQuestXP and xpFrame.allQuestXPBar then
        xpFrame.allQuestXPBar:Show()
        xpFrame.allQuestXPBar:SetMinMaxValues(0, maxXP)
        local projectedAllXP = curXP + allQuestXP
        xpFrame.allQuestXPBar:SetValue(math_min(maxXP, projectedAllXP))
        xpFrame.allQuestXPBar:SetStatusBarColor(cAllQuest.r, cAllQuest.g, cAllQuest.b, cAllQuest.a or 0.65)
    elseif xpFrame.allQuestXPBar then
        xpFrame.allQuestXPBar:Hide()
    end

    -- Completed Quest Log XP "Ghost Bar" & Ding Ready Detection
    local completedQuestXP = 0
    if db and db.showCompletedQuestXP ~= false then
        completedQuestXP = ScanCompletedQuestLogXP()
    end

    local projectedXP = curXP + completedQuestXP
    local isDingReady = (maxXP > 0 and projectedXP >= maxXP)

    if completedQuestXP > 0 and db and db.showCompletedQuestXP ~= false then
        xpFrame.questXPBar:Show()
        xpFrame.questXPBar:SetMinMaxValues(0, maxXP)
        xpFrame.questXPBar:SetValue(math_min(maxXP, projectedXP))

        if isDingReady then
            xpFrame.questXPBar:SetStatusBarColor(cDing.r, cDing.g, cDing.b, cDing.a or 1.0)
        else
            xpFrame.questXPBar:SetStatusBarColor(cQuest.r, cQuest.g, cQuest.b, cQuest.a or 1.0)
        end
    else
        xpFrame.questXPBar:Hide()
    end

    -- Formatted Text String
    local curPct = (curXP / maxXP) * 100
    local formatMode = (db and db.xpTextFormat) or "smart"
    local hideQuestText = (db and db.hideQuestXPText == true)

    if isDingReady and db and db.showDingReadyText ~= false and formatMode ~= "none" then
        if hideQuestText then
            xpFrame.text:SetText(string_format("|cff00ff00[DING READY!]|r %.1f%%", curPct))
        else
            local completedPct = (completedQuestXP / maxXP) * 100
            xpFrame.text:SetText(string_format("|cff00ff00[DING READY!]|r %.1f%% + |cffffd100%.1f%%|r", curPct, completedPct))
        end
    elseif formatMode == "none" then
        xpFrame.text:SetText("")
    elseif formatMode == "cur_max" then
        xpFrame.text:SetText(string_format("%s / %s", BreakUpLargeNumbers(curXP), BreakUpLargeNumbers(maxXP)))
    elseif formatMode == "cur_pct" then
        xpFrame.text:SetText(string_format("%.1f%%", curPct))
    elseif formatMode == "remain" then
        xpFrame.text:SetText(string_format("%s to Level %d", BreakUpLargeNumbers(maxXP - curXP), curLevel + 1))
    else -- "smart" default
        local maxAvailableWidth = math_max(100, xpFrame:GetWidth() - 14)
        local questXPStr = ""
        if not hideQuestText then
            if completedQuestXP > 0 and db and db.showAllQuestXP and allQuestXP > completedQuestXP then
                questXPStr = string_format(" |cffffd100(+%s Done)|r |cff3399ff(+%s All)|r", BreakUpLargeNumbers(completedQuestXP), BreakUpLargeNumbers(allQuestXP))
            elseif completedQuestXP > 0 then
                questXPStr = string_format(" |cffffd100(+%s Quest XP)|r", BreakUpLargeNumbers(completedQuestXP))
            elseif allQuestXP > 0 and db and db.showAllQuestXP then
                questXPStr = string_format(" |cff3399ff(+%s All Quest XP)|r", BreakUpLargeNumbers(allQuestXP))
            end
        end

        local fullStr = string_format("%s / %s (%.1f%%)%s",
            BreakUpLargeNumbers(curXP),
            BreakUpLargeNumbers(maxXP),
            curPct,
            questXPStr)
        xpFrame.text:SetText(fullStr)

        if xpFrame.text:GetStringWidth() > maxAvailableWidth then
            local function FormatCompactXP(val)
                if not val or val <= 0 then return "0" end
                if val >= 1000000 then
                    return string_format("%.1fM", val / 1000000)
                elseif val >= 1000 then
                    return string_format("%.1fk", val / 1000)
                else
                    return tostring(val)
                end
            end

            -- Tier 2: Compact numbers (e.g. 20.2k / 27.3k)
            local cDoneStr = ""
            if not hideQuestText then
                if completedQuestXP > 0 and db and db.showAllQuestXP and allQuestXP > completedQuestXP then
                    cDoneStr = string_format(" |cffffd100(+%s Done)|r |cff3399ff(+%s All)|r", FormatCompactXP(completedQuestXP), FormatCompactXP(allQuestXP))
                elseif completedQuestXP > 0 then
                    cDoneStr = string_format(" |cffffd100(+%s Quest)|r", FormatCompactXP(completedQuestXP))
                elseif allQuestXP > 0 and db and db.showAllQuestXP then
                    cDoneStr = string_format(" |cff3399ff(+%s All)|r", FormatCompactXP(allQuestXP))
                end
            end
            local t2 = string_format("%s / %s (%.1f%%)%s", FormatCompactXP(curXP), FormatCompactXP(maxXP), curPct, cDoneStr)
            xpFrame.text:SetText(t2)

            if xpFrame.text:GetStringWidth() > maxAvailableWidth then
                -- Tier 3: Drop All quests part, retain Completed quest XP if not hidden
                local singleDone = ""
                if not hideQuestText and completedQuestXP > 0 then
                    singleDone = string_format(" |cffffd100(+%s)|r", FormatCompactXP(completedQuestXP))
                end
                local t3 = string_format("%s / %s (%.1f%%)%s", FormatCompactXP(curXP), FormatCompactXP(maxXP), curPct, singleDone)
                xpFrame.text:SetText(t3)

                if xpFrame.text:GetStringWidth() > maxAvailableWidth then
                    -- Tier 4: Minimal cur/max percent
                    local t4 = string_format("%s / %s (%.1f%%)", FormatCompactXP(curXP), FormatCompactXP(maxXP), curPct)
                    xpFrame.text:SetText(t4)
                    if xpFrame.text:GetStringWidth() > maxAvailableWidth then
                        xpFrame.text:SetText(string_format("%.1f%%", curPct))
                    end
                end
            end
        end
    end
end

function DataBarsModule:ShowXPTooltip(owner)
    local curXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 0
    local curLevel = UnitLevel("player") or 1
    local isMaxLevel = (maxXP == 0)

    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine("|cff00c0ffBleakfiber's Quest Tracker|r - Experience DataBar", 1, 1, 1)

    if isMaxLevel then
        local watchedFaction = (C_Reputation and C_Reputation.GetWatchedFactionData and SafeCall(C_Reputation.GetWatchedFactionData))
        if watchedFaction and watchedFaction.name then
            local repCurrent = watchedFaction.currentStanding or 0
            local repMin = watchedFaction.currentReactionThreshold or 0
            local repMax = watchedFaction.nextReactionThreshold or 1
            local repSpan = math_max(1, repMax - repMin)
            local repProgress = math_max(0, repCurrent - repMin)
            local repPct = (repProgress / repSpan) * 100
            local standingText = (GetText and SafeCall(GetText, "FACTION_STANDING_LABEL" .. tostring(watchedFaction.reaction))) or ""

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string_format("Watched Faction: |cffffffff%s|r", watchedFaction.name))
            GameTooltip:AddLine(string_format("Standing: |cffffd100%s|r", standingText ~= "" and standingText or "Rep"))
            GameTooltip:AddLine(string_format("Progress: |cffffffff%s / %s|r (%.1f%%)",
                BreakUpLargeNumbers(repProgress), BreakUpLargeNumbers(repSpan), repPct))
        else
            GameTooltip:AddLine(string_format("Level: |cffffffff%d (Max Level)|r", curLevel))
        end
    else
        local remaining = maxXP - curXP
        local curPct = (curXP / maxXP) * 100
        local restedXP = (GetXPExhaustion and SafeCall(GetXPExhaustion)) or 0
        local totalQuestXP, qList = ScanCompletedQuestLogXP()
        local projectedXP = curXP + totalQuestXP
        local isDingReady = (projectedXP >= maxXP)

        GameTooltip:AddLine(string_format("Level %d Player", curLevel), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Current XP:", string_format("|cffffffff%s / %s (%.1f%%)|r",
            BreakUpLargeNumbers(curXP), BreakUpLargeNumbers(maxXP), curPct))
        GameTooltip:AddDoubleLine("XP to Level " .. tostring(curLevel + 1) .. ":", string_format("|cffffffff%s|r",
            BreakUpLargeNumbers(remaining)))

        if restedXP > 0 then
            local restedPct = (restedXP / maxXP) * 100
            GameTooltip:AddDoubleLine("Rested Bonus:", string_format("|cff0070dd+%s (%.1f%%)|r",
                BreakUpLargeNumbers(restedXP), restedPct))
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd100Completed Quest Log XP:|r")
        if #qList > 0 then
            for _, q in ipairs(qList) do
                local greyNow = (ns.IsQuestGrey and ns.IsQuestGrey(q.level, curLevel))
                local greyAtNext = (ns.IsQuestGrey and ns.IsQuestGrey(q.level, curLevel + 1))
                local statusTag = ""
                if not greyNow and greyAtNext then
                    statusTag = " |cffff2020[Grey at Ding!]|r"
                end
                GameTooltip:AddDoubleLine(string_format("• [%d] %s%s", q.level, q.title, statusTag),
                    string_format("|cff20ff20+%s XP|r", BreakUpLargeNumbers(q.rewardXP)), 0.9, 0.9, 0.9)
            end
            GameTooltip:AddDoubleLine("Total Completed Turn-In XP:", string_format("|cff00ff00+%s XP (%d quests)|r",
                BreakUpLargeNumbers(totalQuestXP), #qList))

            if isDingReady then
                local overflow = projectedXP - maxXP
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string_format("|cff00ff00✓ Ding Ready!|r Turning in these quests will level you up to %d (+%s overflow XP)!",
                    curLevel + 1, BreakUpLargeNumbers(overflow)), 0.2, 1.0, 0.2, true)
            end
        else
            GameTooltip:AddLine("  No completed quests ready for turn-in.", 0.6, 0.6, 0.6)
        end

        local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
        if db and db.showAllQuestXP then
            local allXP, allList = ScanAllQuestLogXP()
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Total Active Quests in Log XP:", string_format("|cff3399ff+%s XP (%d quests)|r",
                BreakUpLargeNumbers(allXP), #allList))
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00c0ffRight-Click:|r Open Settings & Appearance", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

-- ===========================================================================
-- 2. Location & Precision Coordinates Header Bar
-- ===========================================================================

function DataBarsModule:CreateLocationBar()
    if locFrame then return locFrame end

    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)

    local f = CreateFrame("Button", "BleakfiberQuestTrackerLocationBar", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    locFrame = f
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(45)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")

    -- Dragging in Free Mode
    f:SetScript("OnDragStart", function(self)
        local curDB = (ns.db and ns.db.databars)
        if curDB and curDB.locDockMode == "free" and not curDB.locked then
            self:StartMoving()
            self.isMoving = true
        end
    end)
    f:SetScript("OnDragStop", function(self)
        if self.isMoving then
            self.isMoving = false
            self:StopMovingOrSizing()
            local curDB = (ns.db and ns.db.databars)
            if curDB and curDB.locDockMode == "free" then
                local point, _, relPoint, x, y = self:GetPoint()
                curDB.locFreePosition = { point = point, relativePoint = relPoint, x = x, y = y }
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            end
        end
    end)

    -- Text Label with strict frame boundary clamping
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text = text
    text:SetPoint("LEFT", f, "LEFT", 8, 0)
    text:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)

    -- Hidden measuring FontString (used exclusively for layout bounds and truncation measurement)
    local measureFS = f:CreateFontString(nil, "BACKGROUND")
    f.measureFS = measureFS
    measureFS:Hide()

    ApplyBarBackdrop(f, db and db.locBorderStyle, db and db.locBorderWidth, db and db.locBgColor, db and db.locBorderColor, db and db.locBgTexture)

    self:ApplyTypography()

    -- Interactivity: Left-Click toggles WorldMap, Right-Click opens Wayfinder/Config
    f:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if ToggleWorldMap then
                ToggleWorldMap()
            end
        elseif button == "RightButton" then
            if ns.Config and ns.Config.ToggleConfigFrame then
                ns.Config:ToggleConfigFrame()
            end
        end
    end)

    f:SetScript("OnEnter", function(self)
        DataBarsModule:ShowLocationTooltip(self)
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Throttled OnUpdate for smooth coordinate updates without table churn
    local updateElapsed = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        updateElapsed = updateElapsed + elapsed
        if updateElapsed >= 0.25 then
            updateElapsed = 0
            DataBarsModule:UpdateLocationBar()
        end
    end)

    self:UpdateLocationDocking()
    self:UpdateLocationBar()
    return f
end

function DataBarsModule:UpdateLocationDocking()
    if not locFrame then return end
    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    if not db then return end

    local height = db.locHeight or 22
    locFrame:SetHeight(height)

    local dockMode = db.locDockMode or "tracker_top"

    if dockMode == "tracker_top" then
        local tf = (ns.Tracker and ns.Tracker.frame) or _G["BleakfiberQuestTrackerContainer"] or _G["BleakfiberQuestTrackerFrame"]
        if tf then
            local spacing = tonumber(db.dockSpacing) or 0
            locFrame:ClearAllPoints()
            locFrame:SetPoint("BOTTOMLEFT", tf, "TOPLEFT", 0, spacing)
            locFrame:SetPoint("BOTTOMRIGHT", tf, "TOPRIGHT", 0, spacing)
            locFrame:SetUserPlaced(false)
        end
    elseif dockMode == "minimap_top" then
        local mm = MinimapCluster or Minimap
        if mm then
            locFrame:ClearAllPoints()
            locFrame:SetPoint("BOTTOM", mm, "TOP", 0, 4)
            locFrame:SetWidth(db.locWidth or 220)
            locFrame:SetUserPlaced(false)
        end
    elseif dockMode == "free" then
        locFrame:ClearAllPoints()
        if db.locFreePosition and db.locFreePosition.point then
            local pos = db.locFreePosition
            locFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
        else
            locFrame:SetPoint("TOP", UIParent, "TOP", 0, -40)
        end
        locFrame:SetWidth(db.locWidth or 280)
    end

    -- Minimap Header Suppression
    self:ApplyMinimapHeaderSuppression(db.hideMinimapHeader)

    self.lastLocationKey = nil
    self.lastLocationStr = nil
    if locFrame and locFrame:IsShown() then
        self:UpdateLocationBar()
    end
    if timerFrame and self.UpdateTimerDocking then
        self:UpdateTimerDocking()
    end
end

function DataBarsModule:ApplyMinimapHeaderSuppression(hide)
    if not (ns.db and ns.db.databars and ns.db.databars.enableLocationBar) then
        hide = false
    end

    -- Modern 10.0+ MinimapCluster Header
    if MinimapCluster then
        if MinimapCluster.ZoneTextButton then
            MinimapCluster.ZoneTextButton:SetShown(not hide)
        end
        if MinimapCluster.BorderTop then
            MinimapCluster.BorderTop:SetShown(not hide)
        end
    end

    -- Classic Minimap Header Elements
    if MinimapZoneTextButton then
        MinimapZoneTextButton:SetShown(not hide)
    end
    if MinimapBorderTop then
        MinimapBorderTop:SetShown(not hide)
    end
end

local function TruncateTextToWidth(measureFS, prefix, textToTrim, maxWidth)
    local full = prefix .. textToTrim .. "|r"
    measureFS:SetText(full)
    if measureFS:GetStringWidth() <= maxWidth then
        return full
    end

    local len = #textToTrim
    while len > 3 do
        len = len - 1
        local candidate = prefix .. textToTrim:sub(1, len) .. "...|r"
        measureFS:SetText(candidate)
        if measureFS:GetStringWidth() <= maxWidth then
            return candidate
        end
    end
    return prefix .. textToTrim:sub(1, 3) .. "...|r"
end

function DataBarsModule:UpdateMaxCoordsWidth()
    if locFrame and locFrame.measureFS then
        locFrame.measureFS:SetText(" (99.9, 99.9)")
        self.maxCoordsWidth = math_ceil(locFrame.measureFS:GetStringWidth() + 4)
    else
        self.maxCoordsWidth = 68
    end
end

function DataBarsModule:ResetLocationCache()
    self.lastLocationKey = nil
    self.lastLocationStr = nil
    if locFrame and locFrame:IsShown() then
        self:UpdateLocationBar()
    end
end

function DataBarsModule:UpdateLocationBar(force)
    if not locFrame or not locFrame:IsShown() then return end
    if force then
        self.lastLocationKey = nil
        self.lastLocationStr = nil
    end

    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    local bestMapID = (C_Map and C_Map.GetBestMapForUnit and SafeCall(C_Map.GetBestMapForUnit, "player"))

    local zoneName = (GetZoneText and SafeCall(GetZoneText)) or ""
    if zoneName == "" and bestMapID and C_Map and C_Map.GetMapInfo then
        local info = SafeCall(C_Map.GetMapInfo, bestMapID)
        if info and info.name then zoneName = info.name end
    end
    if zoneName == "" then zoneName = "Unknown Zone" end

    local subZone = (GetSubZoneText and SafeCall(GetSubZoneText)) or ""

    -- Territory Color Coding or Custom Text Color
    local pvpType = (GetZonePVPInfo and SafeCall(GetZonePVPInfo)) or "default"
    local color
    if db and db.locCustomTextColor and db.locTextColor then
        color = db.locTextColor
    else
        color = (db and db.colorTerritory ~= false and (COLOR_TERRITORY[pvpType] or COLOR_TERRITORY["default"])) or COLOR_TERRITORY["default"]
    end
    local zoneColorHex = string_format("|cff%02x%02x%02x", math_floor((color.r or 1) * 255), math_floor((color.g or 1) * 255), math_floor((color.b or 1) * 255))

    -- Player Coordinates
    local coordsStr = ""
    if db and db.showCoords ~= false and bestMapID and C_Map and C_Map.GetPlayerMapPosition then
        local pos = SafeCall(C_Map.GetPlayerMapPosition, bestMapID, "player")
        if pos and pos.x and pos.y and pos.x > 0 and pos.y > 0 then
            coordsStr = string_format(" |cffffffff(%.1f, %.1f)|r", pos.x * 100, pos.y * 100)
        end
    end

    local mode = (db and db.locFormat) or "subzone_only"
    local showSubzone = not (db and db.showSubzone == false)
    local hasSubZone = (showSubzone and subZone ~= "" and subZone ~= zoneName)
    local hasCoords = (coordsStr ~= "")

    local barWidth = locFrame:GetWidth() or 220
    local totalAvailable = math_max(60, barWidth - 16)
    local maxCoordsWidth = (hasCoords and (self.maxCoordsWidth or 68) or 0)
    local locationAvailableWidth = math_max(40, totalAvailable - maxCoordsWidth)

    local cacheKey = string_format("%s|%s|%s|%d|%d|%s|%s|%s",
        zoneName, subZone, pvpType,
        math_floor(barWidth),
        math_floor(locationAvailableWidth),
        mode, tostring(showSubzone), tostring(hasCoords))

    local locPrefix
    if cacheKey == self.lastLocationKey and self.cachedLocationPrefix then
        locPrefix = self.cachedLocationPrefix
    else
        local measureFS = locFrame.measureFS or locFrame.text
        if not hasSubZone or mode == "zone_only" then
            locPrefix = TruncateTextToWidth(measureFS, zoneColorHex, zoneName, locationAvailableWidth)
        elseif mode == "subzone_only" then
            locPrefix = TruncateTextToWidth(measureFS, zoneColorHex, subZone, locationAvailableWidth)
        elseif mode == "both" then
            local prefix = string_format("%s%s|r • |cffffffff", zoneColorHex, zoneName)
            locPrefix = TruncateTextToWidth(measureFS, prefix, subZone, locationAvailableWidth)
        else -- "smart" default
            -- Tier 1: Try full Zone • Subzone
            local fullCandidate = string_format("%s%s|r • |cffffffff%s|r", zoneColorHex, zoneName, subZone)
            measureFS:SetText(fullCandidate)
            if measureFS:GetStringWidth() <= locationAvailableWidth then
                locPrefix = fullCandidate
            else
                -- Tier 2: Try specific Subzone
                local subCandidate = string_format("%s%s|r", zoneColorHex, subZone)
                measureFS:SetText(subCandidate)
                if measureFS:GetStringWidth() <= locationAvailableWidth then
                    locPrefix = subCandidate
                else
                    -- Tier 3: Try parent Zone
                    local zoneCandidate = string_format("%s%s|r", zoneColorHex, zoneName)
                    measureFS:SetText(zoneCandidate)
                    if measureFS:GetStringWidth() <= locationAvailableWidth then
                        locPrefix = zoneCandidate
                    else
                        -- Tier 4: Truncate zone with ellipsis
                        locPrefix = TruncateTextToWidth(measureFS, zoneColorHex, zoneName, locationAvailableWidth)
                    end
                end
            end
        end
        self.lastLocationKey = cacheKey
        self.cachedLocationPrefix = locPrefix
    end

    local finalStr = locPrefix .. coordsStr
    if finalStr ~= self.lastLocationStr then
        self.lastLocationStr = finalStr
        locFrame.text:SetText(finalStr)
    end
end

function DataBarsModule:ShowLocationTooltip(owner)
    local bestMapID = (C_Map and C_Map.GetBestMapForUnit and SafeCall(C_Map.GetBestMapForUnit, "player"))
    local zoneName = (GetZoneText and SafeCall(GetZoneText)) or "Current Zone"
    local subZone = (GetSubZoneText and SafeCall(GetSubZoneText)) or ""
    local pvpType, _, factionName = (GetZonePVPInfo and SafeCall(GetZonePVPInfo))

    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("|cff00c0ffBleakfiber's Quest Tracker|r - Location Header", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Zone:", string_format("|cffffffff%s|r", zoneName))
    if subZone ~= "" and subZone ~= zoneName then
        GameTooltip:AddDoubleLine("Subzone:", string_format("|cffffffff%s|r", subZone))
    end

    if pvpType then
        local color = COLOR_TERRITORY[pvpType] or COLOR_TERRITORY["default"]
        local typeLabel = pvpType:gsub("^%l", string.upper)
        if factionName and factionName ~= "" then
            typeLabel = typeLabel .. " (" .. factionName .. ")"
        end
        GameTooltip:AddDoubleLine("Territory:", string_format("|cff%02x%02x%02x%s|r",
            math_floor(color.r * 255), math_floor(color.g * 255), math_floor(color.b * 255), typeLabel))
    end

    if bestMapID and C_Map and C_Map.GetPlayerMapPosition then
        local pos = SafeCall(C_Map.GetPlayerMapPosition, bestMapID, "player")
        if pos and pos.x and pos.y and pos.x > 0 and pos.y > 0 then
            GameTooltip:AddDoubleLine("Coordinates:", string_format("|cffffffff%.1f, %.1f|r (Map ID: %d)",
                pos.x * 100, pos.y * 100, bestMapID))
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00c0ffLeft-Click:|r Toggle World Map", 0.2, 0.8, 1.0)
    GameTooltip:AddLine("|cff00c0ffRight-Click:|r Open Settings & Options", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

-- ===========================================================================
-- 3. Quest Timer DataBar (Timed Quests)
-- ===========================================================================

local function FormatTimeLeft(seconds)
    if not seconds or seconds <= 0 then return "00:00" end
    local m = math_floor(seconds / 60)
    local s = math_floor(seconds % 60)
    if m >= 60 then
        local h = math_floor(m / 60)
        m = m % 60
        return string_format("%d:%02d:%02d", h, m, s)
    end
    return string_format("%02d:%02d", m, s)
end

function DataBarsModule:GetSelectedQuestID()
    if ns.activeQuestID and ns.activeQuestID > 0 then
        return ns.activeQuestID
    end
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local stID = SafeCall(C_SuperTrack.GetSuperTrackedQuestID)
        if stID and stID > 0 then
            return stID
        end
    end
    if GetQuestLogSelection and ns.GetQuestLogTitle then
        local sel = SafeCall(GetQuestLogSelection)
        if sel and sel > 0 then
            local _, _, _, _, _, _, _, qID = ns.GetQuestLogTitle(sel)
            if qID and qID > 0 then
                return qID
            end
        end
    end
    return nil
end

function DataBarsModule:GetActiveTimedQuest()
    if ns.PurgeInvalidTimerCache then
        ns.PurgeInvalidTimerCache()
    end

    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and SafeCall(C_QuestLog.GetNumQuestLogEntries))
        or (GetNumQuestLogEntries and SafeCall(GetNumQuestLogEntries)) or 0

    -- Check if player has an actively selected/targeted quest:
    local selectedQID = self:GetSelectedQuestID()
    if selectedQID and selectedQID > 0 then
        -- Find the selected quest's log index and title
        local activeTitle = nil
        local activeLogIndex = nil
        for i = 1, numEntries do
            local qInfo = C_QuestLog and C_QuestLog.GetInfo and SafeCall(C_QuestLog.GetInfo, i)
            local qID = qInfo and qInfo.questID
            if not qID and ns.GetQuestLogTitle then
                local _, _, _, _, _, _, _, id = ns.GetQuestLogTitle(i)
                qID = id
            end
            if qID and qID == selectedQID then
                activeLogIndex = i
                activeTitle = (qInfo and qInfo.title) or (ns.GetQuestLogTitle and select(1, ns.GetQuestLogTitle(i)))
                break
            end
        end

        -- If the selected quest is failed, do not show timer
        if ns.IsQuestFailed and ns.IsQuestFailed(selectedQID, activeLogIndex) then
            if ns.ClearQuestTimer then ns.ClearQuestTimer(selectedQID) end
            return nil
        end

        local timeLeft, maxTime = nil, nil
        if ns.GetQuestTimeInfo then
            timeLeft, maxTime = ns.GetQuestTimeInfo(selectedQID, activeLogIndex)
        end

        if timeLeft and timeLeft > 0 then
            activeTitle = activeTitle 
                or (C_QuestLog and C_QuestLog.GetTitleForQuestID and SafeCall(C_QuestLog.GetTitleForQuestID, selectedQID)) 
                or "Timed Quest"

            local curDB = (ns.db and ns.db.databars)
            if not maxTime or maxTime <= 0 then
                local curSaved = curDB and curDB.timerMaxValues and curDB.timerMaxValues[selectedQID]
                maxTime = (curSaved and curSaved >= timeLeft and curSaved) or timeLeft
            end

            return {
                questID = selectedQID,
                logIndex = activeLogIndex,
                title = activeTitle,
                timeLeft = timeLeft,
                maxTime = maxTime or timeLeft,
            }
        else
            -- USER REQUIREMENT: Hide the databar if the selected quest doesn't have a timer
            return nil
        end
    end

    if numEntries == 0 then return nil end

    local bestQuest = nil
    local lowestTime = 999999

    for i = 1, numEntries do
        local title, isHeader, questID
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = SafeCall(C_QuestLog.GetInfo, i)
            if info then
                title = info.title
                isHeader = info.isHeader
                questID = info.questID
            end
        elseif GetQuestLogTitle then
            local t, _, _, h, _, _, _, qID = SafeCall(GetQuestLogTitle, i)
            title = t
            isHeader = h
            questID = qID
        end

        if title and not isHeader and (questID or i) then
            questID = questID or i
            local isFailed = ns.IsQuestFailed and ns.IsQuestFailed(questID, i)
            if not isFailed then
                local timeLeft, maxTime
                if ns.GetQuestTimeInfo then
                    timeLeft, maxTime = ns.GetQuestTimeInfo(questID, i)
                end

                if timeLeft and timeLeft > 0 then
                    -- Persist maxTime across /reload via SavedVariables
                    local curDB = (ns.db and ns.db.databars)
                    if not maxTime or maxTime <= 0 then
                        local curSaved = curDB and curDB.timerMaxValues and curDB.timerMaxValues[questID]
                        if curSaved and curSaved >= timeLeft then
                            maxTime = curSaved
                        else
                            maxTime = timeLeft
                            if curDB then
                                curDB.timerMaxValues = curDB.timerMaxValues or {}
                                curDB.timerMaxValues[questID] = maxTime
                                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            end
                        end
                    else
                        if curDB then
                            curDB.timerMaxValues = curDB.timerMaxValues or {}
                            if curDB.timerMaxValues[questID] ~= maxTime then
                                curDB.timerMaxValues[questID] = maxTime
                                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            end
                        end
                    end

                    if timeLeft < lowestTime then
                        lowestTime = timeLeft
                        bestQuest = {
                            questID = questID,
                            logIndex = i,
                            title = title,
                            timeLeft = timeLeft,
                            maxTime = maxTime or timeLeft,
                        }
                    end
                end
            else
                if ns.ClearQuestTimer then ns.ClearQuestTimer(questID) end
            end
        end
    end

    return bestQuest
end

function DataBarsModule:CreateTimerBar()
    if timerFrame then return timerFrame end

    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)

    local f = CreateFrame("Button", "BleakfiberQuestTrackerTimerBar", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    timerFrame = f
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(45)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")

    local timerElapsed = 0
    function DataBarsModule:StartTimerTicker()
        if not timerFrame or timerFrame.hasTicker then return end
        timerFrame.hasTicker = true
        timerFrame:SetScript("OnUpdate", function(self, elapsed)
            timerElapsed = timerElapsed + elapsed
            if timerElapsed >= 1.0 then
                timerElapsed = 0
                DataBarsModule:UpdateTimerBar()
            end
        end)
    end

    function DataBarsModule:StopTimerTicker()
        if not timerFrame or not timerFrame.hasTicker then return end
        timerFrame.hasTicker = false
        timerFrame:SetScript("OnUpdate", nil)
        timerElapsed = 0
    end

    -- Dragging in Free Mode
    f:SetScript("OnDragStart", function(self)
        local curDB = (ns.db and ns.db.databars)
        if curDB and curDB.timerDockMode == "free" and not curDB.locked then
            self:StartMoving()
            self.isMoving = true
        end
    end)
    f:SetScript("OnDragStop", function(self)
        if self.isMoving then
            self.isMoving = false
            self:StopMovingOrSizing()
            local curDB = (ns.db and ns.db.databars)
            if curDB and curDB.timerDockMode == "free" then
                local point, _, relPoint, x, y = self:GetPoint()
                curDB.timerFreePosition = { point = point, relativePoint = relPoint, x = x, y = y }
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            end
        end
    end)

    -- Status Bar fill layer
    local statusBar = CreateFrame("StatusBar", nil, f)
    f.statusBar = statusBar
    statusBar:SetAllPoints(f)
    statusBar:SetFrameLevel(f:GetFrameLevel() + 1)
    local barTex = GetLSMTexture(db and db.timerBarTexture)
    statusBar:SetStatusBarTexture(barTex)
    local tCol = (db and db.timerColor) or { r = 1.0, g = 0.82, b = 0.0, a = 1.0 }
    statusBar:SetStatusBarColor(tCol.r, tCol.g, tCol.b, 0.35)
    statusBar:SetMinMaxValues(0, 100)
    statusBar:SetValue(100)

    -- Centered Countdown Label
    local text = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text = text
    text:SetPoint("LEFT", f, "LEFT", 8, 0)
    text:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)

    ApplyBarBackdrop(f, db and db.timerBorderStyle, db and db.timerBorderWidth, db and db.timerBgColor, db and db.timerBorderColor or { r = 1.00, g = 0.82, b = 0.00, a = 0.85 }, db and db.timerBgTexture)

    self:ApplyTypography()

    -- Click Actions: Left = Open Quest in Log, Right = Open Settings
    f:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if self.activeQuest then
                if self.activeQuest.questID and QuestMapFrame_OpenToQuestDetails then
                    if securecallfunction then
                        securecallfunction(QuestMapFrame_OpenToQuestDetails, self.activeQuest.questID)
                    else
                        QuestMapFrame_OpenToQuestDetails(self.activeQuest.questID)
                    end
                elseif self.activeQuest.logIndex and QuestLogFrame and SelectQuestLogEntry then
                    ShowUIPanel(QuestLogFrame)
                    SelectQuestLogEntry(self.activeQuest.logIndex)
                    if QuestLog_Update then QuestLog_Update() end
                elseif ToggleQuestLog then
                    ToggleQuestLog()
                end
            elseif ToggleQuestLog then
                ToggleQuestLog()
            end
        elseif button == "RightButton" then
            if ns.Config and ns.Config.ToggleConfigFrame then
                ns.Config:ToggleConfigFrame()
            end
        end
    end)

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cff00c0ffBleakfiber's Quest Tracker|r - Quest Timer", 1, 1, 1)
        GameTooltip:AddLine(" ")
        if self.activeQuest then
            GameTooltip:AddDoubleLine("Quest:", string_format("|cffffffff%s|r", self.activeQuest.title or "Timed Quest"))
            GameTooltip:AddDoubleLine("Time Remaining:", string_format("|cffffd100%s|r", FormatTimeLeft(self.activeQuest.timeLeft)))
        else
            GameTooltip:AddLine("No active timed quest (Preview Mode)", 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00c0ffLeft-Click:|r View Quest in Log", 0.2, 0.8, 1.0)
        GameTooltip:AddLine("|cff00c0ffRight-Click:|r Open Settings & Options", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self:UpdateTimerDocking()
    self:UpdateTimerBar()
    return f
end

function DataBarsModule:UpdateTimerDocking()
    if not timerFrame then return end
    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    if not db then return end

    local height = db.timerHeight or 22
    timerFrame:SetHeight(height)

    local dockMode = db.timerDockMode or "tracker_top"
    local spacing = tonumber(db.dockSpacing) or 0

    if dockMode == "tracker_top" then
        local tf = (ns.Tracker and ns.Tracker.frame) or _G["BleakfiberQuestTrackerContainer"] or _G["BleakfiberQuestTrackerFrame"]
        if tf then
            timerFrame:ClearAllPoints()
            if locFrame and locFrame:IsShown() and db.locDockMode == "tracker_top" then
                timerFrame:SetPoint("BOTTOMLEFT", locFrame, "TOPLEFT", 0, spacing)
                timerFrame:SetPoint("BOTTOMRIGHT", locFrame, "TOPRIGHT", 0, spacing)
            else
                timerFrame:SetPoint("BOTTOMLEFT", tf, "TOPLEFT", 0, spacing)
                timerFrame:SetPoint("BOTTOMRIGHT", tf, "TOPRIGHT", 0, spacing)
            end
            timerFrame:SetUserPlaced(false)
        end
    elseif dockMode == "tracker_bottom" then
        local tf = (ns.Tracker and ns.Tracker.frame) or _G["BleakfiberQuestTrackerContainer"] or _G["BleakfiberQuestTrackerFrame"]
        if tf then
            timerFrame:ClearAllPoints()
            if xpFrame and xpFrame:IsShown() and db.xpDockMode == "tracker_bottom" then
                timerFrame:SetPoint("TOPLEFT", xpFrame, "BOTTOMLEFT", 0, -spacing)
                timerFrame:SetPoint("TOPRIGHT", xpFrame, "BOTTOMRIGHT", 0, -spacing)
            else
                timerFrame:SetPoint("TOPLEFT", tf, "BOTTOMLEFT", 0, -spacing)
                timerFrame:SetPoint("TOPRIGHT", tf, "BOTTOMRIGHT", 0, -spacing)
            end
            timerFrame:SetUserPlaced(false)
        end
    elseif dockMode == "free" then
        timerFrame:ClearAllPoints()
        if db.timerFreePosition and db.timerFreePosition.point then
            local pos = db.timerFreePosition
            timerFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
        else
            timerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
        end
        local width = db.timerWidth or 220
        timerFrame:SetWidth(width)
    end
end

function DataBarsModule:UpdateAllDocking()
    self:UpdateXPDocking()
    self:UpdateLocationDocking()
    self:UpdateTimerDocking()
end

function DataBarsModule:UpdateTimerBar(force)
    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    local isTimerEnabled = not (db and db.enableTimerBar == false)
    if not isTimerEnabled then
        if timerFrame then timerFrame:Hide() end
        return
    end

    if not timerFrame then
        self:CreateTimerBar()
    end
    if not timerFrame then return end

    local timedQuest = self:GetActiveTimedQuest()
    local isPreview = self.timerPreviewMode

    if timedQuest then
        timerFrame.activeQuest = timedQuest
        local timeLeft = timedQuest.timeLeft
        local maxTime = timedQuest.maxTime or timeLeft
        local timeStr = FormatTimeLeft(timeLeft)

        timerFrame.statusBar:SetMinMaxValues(0, maxTime)
        timerFrame.statusBar:SetValue(timeLeft)

        local barTex = GetLSMTexture(db and db.timerBarTexture)
        timerFrame.statusBar:SetStatusBarTexture(barTex)

        -- Dynamic Urgency Color Coding
        local ratio = (maxTime > 0) and (timeLeft / maxTime) or 1.0
        local r, g, b
        local timeColorCode
        if timeLeft <= 60 or ratio <= 0.20 then
            -- Critical Urgency: High-contrast red (<= 60s or <= 20% remaining)
            r, g, b = 1.0, 0.22, 0.22
            timeColorCode = "|cffff3333"
        elseif timeLeft <= 120 or ratio <= 0.40 then
            -- Warning: Amber / Orange (<= 120s or <= 40% remaining)
            r, g, b = 1.0, 0.65, 0.0
            timeColorCode = "|cffff9900"
        else
            -- Normal: User configured or Theme Gold
            local tCol = (db and db.timerColor) or { r = 1.0, g = 0.82, b = 0.0, a = 1.0 }
            r, g, b = tCol.r, tCol.g, tCol.b
            timeColorCode = string_format("|cff%02x%02x%02x", math_floor(r * 255), math_floor(g * 255), math_floor(b * 255))
        end

        local fillAlpha = (db and db.timerColor and db.timerColor.a) or 0.50
        timerFrame.statusBar:SetStatusBarColor(r, g, b, fillAlpha)

        local tBorder = (db and db.timerBorderColor) or { r = 1.00, g = 0.82, b = 0.00, a = 0.85 }
        if timeLeft <= 60 or ratio <= 0.20 or timeLeft <= 120 or ratio <= 0.40 then
            timerFrame:SetBackdropBorderColor(r, g, b, 0.95)
        else
            timerFrame:SetBackdropBorderColor(tBorder.r, tBorder.g, tBorder.b, tBorder.a or 0.85)
        end

        local showTitle = not (db and db.timerShowTitle == false)
        local formattedTime = string_format("%s%s|r", timeColorCode, timeStr)
        local displayText = showTitle and string_format("%s: %s", timedQuest.title or "Quest", formattedTime) or formattedTime
        timerFrame.text:SetText(displayText)

        timerFrame:Show()
        self:StartTimerTicker()
    elseif isPreview then
        timerFrame.activeQuest = nil
        timerFrame.statusBar:SetMinMaxValues(0, 300)
        timerFrame.statusBar:SetValue(272)
        local barTex = GetLSMTexture()
        timerFrame.statusBar:SetStatusBarTexture(barTex)
        local tCol = (db and db.timerColor) or { r = 1.0, g = 0.82, b = 0.0, a = 1.0 }
        timerFrame.statusBar:SetStatusBarColor(tCol.r, tCol.g, tCol.b, 0.50)
        timerFrame:SetBackdropBorderColor(tCol.r, tCol.g, tCol.b, 0.85)
        local showTitle = not (db and db.timerShowTitle == false)
        local displayText = showTitle and "A Hot Mug (Preview): |cffffd10004:32|r" or "|cffffd10004:32|r"
        timerFrame.text:SetText(displayText)
        timerFrame:Show()
        self:StopTimerTicker()
    else
        timerFrame.activeQuest = nil
        timerFrame:Hide()
        self:StopTimerTicker()
    end
end

-- ===========================================================================
-- 4. Module Lifecycle & Event Registration
-- ===========================================================================

function DataBarsModule:UpdateEvents()
    if not self.eventFrame then return end
    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    local xpEnabled = db and db.enableXPBar
    local locEnabled = db and db.enableLocationBar
    local timerEnabled = not (db and db.enableTimerBar == false)

    self.eventFrame:UnregisterAllEvents()

    if xpEnabled or locEnabled or timerEnabled then
        self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end

    if xpEnabled then
        self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
        self.eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
        self.eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
        self.eventFrame:RegisterEvent("UPDATE_FACTION")
        self.eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    end

    if locEnabled then
        self.eventFrame:RegisterEvent("ZONE_CHANGED")
        self.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self.eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
    end

    if timerEnabled then
        pcall(self.eventFrame.RegisterEvent, self.eventFrame, "QUEST_TIMER_UPDATE")
        pcall(self.eventFrame.RegisterEvent, self.eventFrame, "QUEST_TIMERS_UPDATE")
        pcall(self.eventFrame.RegisterEvent, self.eventFrame, "QUEST_TURNED_IN")
        pcall(self.eventFrame.RegisterEvent, self.eventFrame, "SUPER_TRACKING_CHANGED")
        self.eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
        self.eventFrame:RegisterEvent("QUEST_WATCH_UPDATE")
        self.eventFrame:RegisterEvent("QUEST_ACCEPTED")
        self.eventFrame:RegisterEvent("QUEST_REMOVED")
    end
end

function DataBarsModule:ApplyTypography(overrideFontPath)
    local curDB = (ns.db and ns.db.databars)
        or (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars)
        or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    local fontPath = overrideFontPath or GetLSMFont()
    local xpSize = (curDB and curDB.xpFontSize) or 11
    local xpOutline = (curDB and curDB.xpFontOutline) or "OUTLINE"
    if xpOutline == "NONE" or xpOutline == "" then xpOutline = nil end
    local locSize = (curDB and curDB.locFontSize) or 11
    local locOutline = (curDB and curDB.locFontOutline) or "OUTLINE"
    if locOutline == "NONE" or locOutline == "" then locOutline = nil end
    local timerSize = (curDB and curDB.timerFontSize) or 11
    local timerOutline = (curDB and curDB.timerFontOutline) or "OUTLINE"
    if timerOutline == "NONE" or timerOutline == "" then timerOutline = nil end

    if xpFrame and xpFrame.text and fontPath then
        if xpOutline then
            pcall(xpFrame.text.SetFont, xpFrame.text, fontPath, xpSize, xpOutline)
        else
            pcall(xpFrame.text.SetFont, xpFrame.text, fontPath, xpSize)
        end
    end

    if locFrame and fontPath then
        if locFrame.text then
            if locOutline then
                pcall(locFrame.text.SetFont, locFrame.text, fontPath, locSize, locOutline)
            else
                pcall(locFrame.text.SetFont, locFrame.text, fontPath, locSize)
            end
        end
        if locFrame.measureFS then
            if locOutline then
                pcall(locFrame.measureFS.SetFont, locFrame.measureFS, fontPath, locSize, locOutline)
            else
                pcall(locFrame.measureFS.SetFont, locFrame.measureFS, fontPath, locSize)
            end
        end
        self:UpdateMaxCoordsWidth()
        self.lastLocationKey = nil
        self.lastLocationStr = nil
        if locFrame:IsShown() then
            self:UpdateLocationBar()
        end
    end

    if timerFrame and timerFrame.text and fontPath then
        if timerOutline then
            pcall(timerFrame.text.SetFont, timerFrame.text, fontPath, timerSize, timerOutline)
        else
            pcall(timerFrame.text.SetFont, timerFrame.text, fontPath, timerSize)
        end
    end
end

function DataBarsModule:ApplyVisuals()
    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    if not db then return end

    if xpFrame then
        ApplyBarBackdrop(xpFrame, db.xpBorderStyle, db.xpBorderWidth, db.xpBgColor, db.xpBorderColor, db.xpBgTexture)
        local xpTex = GetLSMTexture(db.xpBarTexture)
        if xpFrame.playerBar then xpFrame.playerBar:SetStatusBarTexture(xpTex) end
        if xpFrame.questXPBar then xpFrame.questXPBar:SetStatusBarTexture(xpTex) end
        if xpFrame.allQuestXPBar then xpFrame.allQuestXPBar:SetStatusBarTexture(xpTex) end
        if xpFrame.restedBar then xpFrame.restedBar:SetStatusBarTexture(xpTex) end
    end

    if locFrame then
        ApplyBarBackdrop(locFrame, db.locBorderStyle, db.locBorderWidth, db.locBgColor, db.locBorderColor, db.locBgTexture)
    end

    if timerFrame then
        ApplyBarBackdrop(timerFrame, db.timerBorderStyle, db.timerBorderWidth, db.timerBgColor, db.timerBorderColor or { r = 1.00, g = 0.82, b = 0.00, a = 0.85 }, db.timerBgTexture)
        local timerTex = GetLSMTexture(db.timerBarTexture)
        if timerFrame.statusBar then timerFrame.statusBar:SetStatusBarTexture(timerTex) end
    end
end

function DataBarsModule:RefreshBars()
    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)
    if not db then return end

    self:ApplyTypography()
    self:ApplyVisuals()

    local isCombatHidden = db.hideInCombat and (self.inCombat or (InCombatLockdown and InCombatLockdown()))

    -- XP Bar Toggle
    if db.enableXPBar and not isCombatHidden then
        if not xpFrame then self:CreateXPBar() end
        xpFrame:Show()
        self:UpdateXPDocking()
        self:UpdateXPBar()
    elseif xpFrame then
        xpFrame:Hide()
        if not db.enableXPBar then
            self:SuppressBlizzardXP(false)
        end
    end

    -- Location Bar Toggle
    if db.enableLocationBar and not isCombatHidden then
        if not locFrame then self:CreateLocationBar() end
        locFrame:Show()
        self:UpdateLocationDocking()
        self:UpdateLocationBar()
    elseif locFrame then
        locFrame:Hide()
        if not db.enableLocationBar then
            self:ApplyMinimapHeaderSuppression(false)
        end
    end

    -- Quest Timer Bar Toggle
    local timerEnabled = not (db and db.enableTimerBar == false)
    if timerEnabled and not isCombatHidden then
        if not timerFrame then self:CreateTimerBar() end
        self:UpdateTimerDocking()
        self:UpdateTimerBar()
    elseif timerFrame then
        timerFrame:Hide()
    end

    self:UpdateEvents()
end

function DataBarsModule:Initialize()
    local db = (ns.db and ns.db.databars) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.databars)

    -- Event listener for player, quest log, and combat changes
    local eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_REGEN_DISABLED" then
            DataBarsModule.inCombat = true
            local curDB = (ns.db and ns.db.databars)
            if curDB and curDB.hideInCombat then
                if xpFrame then xpFrame:Hide() end
                if locFrame then locFrame:Hide() end
                if timerFrame then timerFrame:Hide() end
            end
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            DataBarsModule.inCombat = false
            local curDB = (ns.db and ns.db.databars)
            if curDB and curDB.hideInCombat then
                DataBarsModule:RefreshBars()
            end
            return
        end

        if (event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN") and arg1 then
            if ns.ClearQuestTimer then
                ns.ClearQuestTimer(arg1)
            end
        end

        if event == "QUEST_TIMER_UPDATE" or event == "QUEST_TIMERS_UPDATE" then
            local curDB = (ns.db and ns.db.databars)
            if curDB and curDB.enableTimerBar and not DataBarsModule.inCombat then
                DataBarsModule:UpdateTimerBar()
            end
            return
        end

        if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
            if locFrame and locFrame:IsShown() then
                DataBarsModule:UpdateLocationBar()
            end
        else
            if xpFrame and xpFrame:IsShown() then
                DataBarsModule:UpdateXPBar()
            end
            local curDB = (ns.db and ns.db.databars)
            if curDB and curDB.enableTimerBar and not DataBarsModule.inCombat then
                DataBarsModule:UpdateTimerBar()
            end
        end
    end)
    self.eventFrame = eventFrame
    self:UpdateEvents()

    -- Register callback for tracker redraws / width changes so bars snap seamlessly
    if ns.RegisterCallback then
        ns:RegisterCallback("QUEST_DATA_CHANGED", function()
            if xpFrame and xpFrame:IsShown() then
                DataBarsModule:UpdateXPBar()
            end
            local curDB = (ns.db and ns.db.databars)
            if curDB and curDB.enableTimerBar and not DataBarsModule.inCombat then
                DataBarsModule:UpdateTimerBar()
            end
        end)
        ns:RegisterCallback("TRACKER_DOCKING_CHANGED", function()
            DataBarsModule:UpdateAllDocking()
        end)
    end

    self:RefreshBars()
end

function DataBarsModule:Disable()
    if xpFrame then xpFrame:Hide() end
    if locFrame then locFrame:Hide() end
    if timerFrame then timerFrame:Hide() end
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
    self:SuppressBlizzardXP(false)
end

function DataBarsModule:Enable()
    if self.eventFrame then
        self:UpdateEvents()
    end
    self:RefreshBars()
end

