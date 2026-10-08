local addonName, ns = ...

-- ---------------------------------------------------------------------------
-- TargetMarkerModule: Lightweight Visual Quest Mob Markers (Skull & Cross)
-- ---------------------------------------------------------------------------
-- Pure In-Game Tooltip Scanning Engine:
--  - 100% standalone with ZERO external data files or database tables.
--  - Scans in-game unit tooltips dynamically for active & tracked quest objectives.
--  - Species-level caching: Tooltip is scanned at most ONCE per unique mob name.
--  - Zero lag, zero stutter, zero mouseover spam.
--  - Automatically removes Skull and Cross markers the instant objectives complete.
--  - 100% unprotected visual nameplate overlays: safe in combat, zero UI taint.
-- ---------------------------------------------------------------------------

local TargetMarkerModule = {}
ns.TargetMarkerModule = TargetMarkerModule

local activeNameplates = {}       -- [unitToken] = nameplateFrame
local knownMobCache = {}          -- [cleanMobName] = "active" | "tracked" | false
local refreshScheduled = false

-- Authentic Blizzard Raid Target Icon Texture Coordinates
local RAID_ICON_COORDS = {
    [1] = { 0.00, 0.25, 0.00, 0.25 }, -- Star
    [2] = { 0.25, 0.50, 0.00, 0.25 }, -- Circle
    [3] = { 0.50, 0.75, 0.00, 0.25 }, -- Diamond
    [4] = { 0.75, 1.00, 0.00, 0.25 }, -- Triangle
    [5] = { 0.00, 0.25, 0.25, 0.50 }, -- Moon
    [6] = { 0.25, 0.50, 0.25, 0.50 }, -- Square
    [7] = { 0.50, 0.75, 0.25, 0.50 }, -- Cross
    [8] = { 0.75, 1.00, 0.25, 0.50 }, -- Skull
}

-- Hidden scanning tooltip attached to WorldFrame
local scanTooltip = nil
local function GetScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "BFQTargetMarkerScanTooltip", WorldFrame, "GameTooltipTemplate")
        scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTooltip
end

-- Helper: Parse tooltip lines to detect incomplete quest objectives and active vs tracked status
local function ScanTooltipLines(tip, activeTitle)
    if not tip or not tip.NumLines then return nil end
    local numLines = tip:NumLines()
    if not numLines or numLines < 1 then return nil end

    local tipName = tip:GetName()
    local curQuestTitle = nil

    for i = 1, numLines do
        local fontString = _G[tipName .. "TextLeft" .. i]
        local text = fontString and fontString:GetText()
        if text and text ~= "" then
            local hasCounter = text:find("%d+/%d+")
            local isCompleteText = text:find("%([Cc]omplete%)") or text:find("%([Dd]one%)")
            local isKillText = text:find("slain") or text:find("killed") or text:find("defeated") or text:find("destroyed")

            if hasCounter or isKillText or isCompleteText then
                local isDone = (isCompleteText ~= nil)
                if not isDone and hasCounter then
                    local cur, maxVal = text:match("(%d+)/(%d+)")
                    if cur and maxVal and tonumber(cur) and tonumber(maxVal) and tonumber(cur) >= tonumber(maxVal) then
                        isDone = true
                    end
                end

                if not isDone then
                    local isActive = false
                    if activeTitle and curQuestTitle and (curQuestTitle == activeTitle or curQuestTitle:find(activeTitle, 1, true)) then
                        isActive = true
                    end
                    return isActive and "active" or "tracked"
                end
            else
                -- Candidates for quest title (skip mob name, level, corpse labels)
                if i >= 2 and not text:find("^Level %d+") and not text:find("Corpse") then
                    curQuestTitle = text
                end
            end
        end
    end

    return nil
end

-- Scan unit's live tooltip using GameTooltip or fallback scanTooltip
local function ScanTooltipForUnit(unit)
    if not unit or not UnitExists(unit) then return nil end

    local activeTitle = nil
    if ns.activeQuestID and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        activeTitle = C_QuestLog.GetTitleForQuestID(ns.activeQuestID)
    end

    -- 1. Modern Tooltip API (C_TooltipInfo) if available
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = C_TooltipInfo.GetUnit(unit)
        if data and data.lines then
            local currentQuestTitle = nil
            for _, line in ipairs(data.lines) do
                local left = line.leftText
                if left and left ~= "" then
                    local isTitle = (Enum and Enum.TooltipDataLineType and line.type == Enum.TooltipDataLineType.QuestTitle)
                    local isObj = (Enum and Enum.TooltipDataLineType and line.type == Enum.TooltipDataLineType.QuestObjective)

                    if not isTitle and not isObj then
                        if left:find("%d+/%d+") or left:find("slain") or left:find("killed") then
                            isObj = true
                        end
                    end

                    if isTitle then
                        currentQuestTitle = left
                    elseif isObj then
                        local isDone = (line.completed == true)
                        if not isDone and (left:find("%([Cc]omplete%)") or left:find("%([Dd]one%)")) then
                            isDone = true
                        end
                        if not isDone then
                            local cur, maxVal = left:match("(%d+)/(%d+)")
                            if cur and maxVal and tonumber(cur) and tonumber(maxVal) and tonumber(cur) >= tonumber(maxVal) then
                                isDone = true
                            end
                        end

                        if not isDone then
                            local isActive = false
                            if activeTitle and currentQuestTitle and (currentQuestTitle == activeTitle or currentQuestTitle:find(activeTitle, 1, true)) then
                                isActive = true
                            end
                            return isActive and "active" or "tracked"
                        end
                    else
                        if not left:find("^Level %d+") and not left:find("Corpse") then
                            currentQuestTitle = left
                        end
                    end
                end
            end
        end
    end

    -- 2. If the active GameTooltip is currently hovering this exact unit, read it directly
    if GameTooltip and GameTooltip:IsShown() and GameTooltip.GetUnit then
        local _, tipUnit = GameTooltip:GetUnit()
        if tipUnit and UnitIsUnit(tipUnit, unit) then
            local status = ScanTooltipLines(GameTooltip, activeTitle)
            if status then return status end
        end
    end

    -- 3. Standard Classic GameTooltip scan
    local tip = GetScanTooltip()
    if tip and tip.SetUnit then
        tip:ClearLines()
        tip:SetUnit(unit)
        local status = ScanTooltipLines(tip, activeTitle)
        if status then return status end
    end

    return nil
end

-- Determine if unit is an incomplete quest mob: returns "active", "tracked", or nil
function TargetMarkerModule:GetUnitQuestStatus(unit)
    if not unit or not UnitExists(unit) then return nil end
    if UnitIsDead and UnitIsDead(unit) then return nil end
    if UnitIsFriend and UnitIsFriend("player", unit) then return nil end

    local unitName = UnitName(unit)
    if not unitName or unitName == "" then return nil end

    -- 1. Fast species-level cache check (O(1) instant return for previously evaluated mob species)
    local cached = knownMobCache[unitName]
    if cached ~= nil then
        return cached or nil
    end

    -- 2. Scan live tooltip
    local status = ScanTooltipForUnit(unit)
    if status then
        knownMobCache[unitName] = status
        return status
    end

    -- Mob is not a quest mob or all objectives on it are complete
    knownMobCache[unitName] = false
    return nil
end

-- Get or construct visual marker frame attached directly to nameplate
local function GetOrCreateMarkerFrame(parent)
    if not parent then return nil end
    if not parent.bfqQuestMarker then
        local marker = CreateFrame("Frame", nil, parent)
        marker:SetSize(22, 22)
        marker:SetPoint("BOTTOM", parent, "TOP", 0, 4)
        marker:SetFrameStrata("HIGH")
        if parent.GetFrameLevel then
            marker:SetFrameLevel(parent:GetFrameLevel() + 10)
        end

        local texture = marker:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints(marker)
        texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        marker.texture = texture

        parent.bfqQuestMarker = marker
    end
    return parent.bfqQuestMarker
end

-- Update marker for a specific unit
function TargetMarkerModule:UpdateUnitMarker(unit, explicitNameplate)
    if not (ns.db and ns.db.targetMarker and ns.db.targetMarker.enableAutoMark) then
        return
    end

    local nameplate = explicitNameplate or (C_NamePlate and C_NamePlate.GetNamePlateForUnit and unit and C_NamePlate.GetNamePlateForUnit(unit))
    if not nameplate then return end

    local parent = nameplate.UnitFrame or nameplate

    if not unit or not UnitExists(unit) or (UnitIsDead and UnitIsDead(unit)) then
        if parent.bfqQuestMarker then
            parent.bfqQuestMarker:Hide()
        end
        return
    end

    local questStatus = self:GetUnitQuestStatus(unit)
    if not questStatus then
        if parent.bfqQuestMarker then
            parent.bfqQuestMarker:Hide()
        end
        return
    end

    local activeMarker = (ns.db.targetMarker and ns.db.targetMarker.markActiveQuest) or 8     -- Skull (8)
    local trackedMarker = (ns.db.targetMarker and ns.db.targetMarker.markTrackedQuests) or 7 -- Cross (7)
    local desiredMarker = (questStatus == "active") and activeMarker or trackedMarker

    local marker = GetOrCreateMarkerFrame(parent)
    if marker then
        if SetRaidTargetIconTexture then
            SetRaidTargetIconTexture(marker.texture, desiredMarker)
        else
            local coords = RAID_ICON_COORDS[desiredMarker]
            if coords then
                marker.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                marker.texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
        end
        marker:Show()
    end
end

-- Backward compatibility alias
TargetMarkerModule.ScanAndMarkUnit = TargetMarkerModule.UpdateUnitMarker

-- Refresh markers on all visible nameplates
function TargetMarkerModule:RefreshAllMarkers()
    local isEnabled = (ns.db and ns.db.targetMarker and ns.db.targetMarker.enableAutoMark)

    for unitToken, nameplate in pairs(activeNameplates) do
        local parent = nameplate and (nameplate.UnitFrame or nameplate)
        if not isEnabled then
            if parent and parent.bfqQuestMarker then
                parent.bfqQuestMarker:Hide()
            end
        else
            if unitToken and UnitExists(unitToken) then
                self:UpdateUnitMarker(unitToken, nameplate)
            elseif parent and parent.bfqQuestMarker then
                parent.bfqQuestMarker:Hide()
            end
        end
    end
end

-- Throttled refresh request to clear cache and update nameplates when quest state changes
function TargetMarkerModule:RequestRefresh()
    if refreshScheduled then return end
    refreshScheduled = true
    local doRefresh = function()
        refreshScheduled = false
        table.wipe(knownMobCache)
        TargetMarkerModule:RefreshAllMarkers()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, doRefresh)
    else
        doRefresh()
    end
end

-- ---------------------------------------------------------------------------
-- Initialization & Event Listeners
-- ---------------------------------------------------------------------------

function TargetMarkerModule:Initialize()
    local eventFrame = CreateFrame("Frame")
    local function SafeRegister(evt)
        pcall(eventFrame.RegisterEvent, eventFrame, evt)
    end

    SafeRegister("NAME_PLATE_UNIT_ADDED")
    SafeRegister("NAME_PLATE_UNIT_REMOVED")
    SafeRegister("PLAYER_TARGET_CHANGED")
    SafeRegister("UPDATE_MOUSEOVER_UNIT")
    SafeRegister("QUEST_LOG_UPDATE")
    SafeRegister("QUEST_WATCH_UPDATE")
    SafeRegister("UNIT_QUEST_LOG_CHANGED")
    SafeRegister("QUEST_ACCEPTED")
    SafeRegister("QUEST_REMOVED")
    SafeRegister("QUEST_TURNED_IN")
    SafeRegister("CHAT_MSG_LOOT")
    SafeRegister("CHAT_MSG_SYSTEM")
    SafeRegister("BAG_UPDATE")
    SafeRegister("BAG_UPDATE_DELAYED")
    SafeRegister("UI_INFO_MESSAGE")

    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "NAME_PLATE_UNIT_ADDED" then
            if arg1 then
                local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(arg1)
                if nameplate then
                    nameplate.bfqUnitToken = arg1
                    activeNameplates[arg1] = nameplate
                    TargetMarkerModule:UpdateUnitMarker(arg1, nameplate)
                end
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if arg1 then
                local nameplate = activeNameplates[arg1]
                if nameplate then
                    nameplate.bfqUnitToken = nil
                    local parent = nameplate.UnitFrame or nameplate
                    if parent and parent.bfqQuestMarker then
                        parent.bfqQuestMarker:Hide()
                    end
                end
                activeNameplates[arg1] = nil
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            TargetMarkerModule:UpdateUnitMarker("target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            TargetMarkerModule:UpdateUnitMarker("mouseover")
        elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" or event == "QUEST_ACCEPTED"
            or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN"
            or event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_SYSTEM"
            or event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "UI_INFO_MESSAGE" then
            TargetMarkerModule:RequestRefresh()
        elseif event == "UNIT_QUEST_LOG_CHANGED" then
            if arg1 == "player" or not arg1 then
                TargetMarkerModule:RequestRefresh()
            end
        end
    end)

    self.eventFrame = eventFrame
    table.wipe(knownMobCache)
end

-- Auto-initialize when Core fires ON_INITIALIZE
if ns.RegisterCallback then
    ns:RegisterCallback("ON_INITIALIZE", function()
        TargetMarkerModule:Initialize()
    end)
    ns:RegisterCallback("QUEST_DATA_CHANGED", function()
        TargetMarkerModule:RequestRefresh()
    end)
end
