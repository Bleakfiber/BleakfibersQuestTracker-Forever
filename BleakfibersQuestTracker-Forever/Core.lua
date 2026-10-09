  local addonName, ns = ...

-- Localized Lua & WoW API bindings for performance & garbage reduction
local pairs, ipairs, type, tostring, tonumber, select, pcall, next = pairs, ipairs, type, tostring, tonumber, select, pcall, next
local string_format = string.format
local table_insert, table_remove = table.insert, table.remove
local wipe = table.wipe or wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local math_floor, math_max, math_min, math_abs = math.floor, math.max, math.min, math.abs
local UnitClass, UnitFactionGroup, UnitLevel = UnitClass, UnitFactionGroup, UnitLevel
local CreateFrame = CreateFrame
local C_QuestLog = C_QuestLog
local GetNumQuestLogEntries = GetNumQuestLogEntries
local GetQuestLogTitle = GetQuestLogTitle
local GetNumQuestLeaderBoards = GetNumQuestLeaderBoards
local GetQuestLogLeaderBoard = GetQuestLogLeaderBoard
local GetQuestDifficultyColor = GetQuestDifficultyColor
local GetDifficultyColor = GetDifficultyColor
local SelectQuestLogEntry = SelectQuestLogEntry
local QuestLogPushQuest = QuestLogPushQuest

-- Keybinding Global Strings for Blizzard Keybindings Menu (loaded immediately)
_G["BINDING_HEADER_BLEAKFIBER_TRACKER"] = "Bleakfiber's Quest Tracker"
_G["HEADER_BLEAKFIBER_TRACKER"] = "Bleakfiber's Quest Tracker"
_G["BINDING_CATEGORY_BLEAKFIBER_TRACKER"] = "Bleakfiber's Quest Tracker"
_G["BINDING_CATEGORY_Bleakfiber's Quest Tracker"] = "Bleakfiber's Quest Tracker"
_G["BINDING_NAME_BLEAKFIBER_USE_QUEST_ITEM"] = "Use Active Quest Item"

-- Safe API caller wrapper
local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, res1, res2, res3 = pcall(fn, ...)
    if ok then return res1, res2, res3 end
    return nil
end
ns.SafeCall = SafeCall

-- Safe number converter (discards any secondary return values to avoid base-out-of-range errors)
local function ToNumber(val)
    if val == nil then return nil end
    return tonumber(val)
end
ns.ToNumber = ToNumber

-- Addon metadata & global access
ns.addonName = addonName
ns.title = "|cff00c0ffBleakfiber's Quest Tracker - Forever|r"
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) 
    or (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")) 
    or "1.1.0"

-- Public Module API & Global Exports for Centralized Config Addons
local PublicAPI = _G["BleakfibersQuestTrackerForever"] or {}
_G["BleakfibersQuestTrackerForever"] = PublicAPI
_G["BleakfiberQuestTracker"] = PublicAPI
ns.PublicAPI = PublicAPI
PublicAPI.addonName = addonName
PublicAPI.version = ns.version

function PublicAPI:GetDB()
    return ns.db or _G["BleakfiberTrackerDB"]
end

function PublicAPI:ApplySettings()
    -- 1. Tracker frame, typography, backdrops & headers
    if ns.Tracker then
        if ns.Tracker.UpdateBackdrop then ns.Tracker:UpdateBackdrop() end
        if ns.Tracker.UpdateTypography then ns.Tracker:UpdateTypography() end
        if ns.Tracker.UpdateSettings then ns.Tracker:UpdateSettings() end
        if ns.Tracker.UpdateVisibility then ns.Tracker:UpdateVisibility() end
        if ns.Tracker.UpdateFilterButtons then ns.Tracker:UpdateFilterButtons() end
    end

    -- 2. Quest entries and item buttons
    if ns.StandaloneTracker then
        if ns.StandaloneTracker.UpdateItemButton then ns.StandaloneTracker:UpdateItemButton() end
        if ns.StandaloneTracker.RequestUpdate then ns.StandaloneTracker:RequestUpdate(true) end
        if ns.StandaloneTracker.UpdateTracker then ns.StandaloneTracker:UpdateTracker() end
    end

    -- 3. Wayfinder navigation and map pins
    if ns.WayfinderModule and ns.WayfinderModule.RefreshState then
        ns.WayfinderModule:RefreshState()
    end

    -- 4. DataBars (XP, Coordinates, Quest Timer)
    if ns.DataBarsModule then
        if ns.DataBarsModule.RefreshBars then ns.DataBarsModule:RefreshBars() end
        if ns.DataBarsModule.ApplyTypography then ns.DataBarsModule:ApplyTypography() end
    end

    -- 5. Social & Automation events
    if ns.SocialModule and ns.SocialModule.UpdateLootEvents then
        ns.SocialModule:UpdateLootEvents()
    end

    -- 6. Immediate multi-layer persistence flush
    if ns.FlushDBToGlobals then
        ns.FlushDBToGlobals()
    end
end

function PublicAPI:OpenSettings()
    if ns.Config and ns.Config.ToggleConfigFrame then
        ns.Config:ToggleConfigFrame()
    end
end

function PublicAPI:RegisterWithMasterConfig()
    if BleakfibersAddonConfigForever and BleakfibersAddonConfigForever.RegisterModule then
        BleakfibersAddonConfigForever:RegisterModule("BleakfibersQuestTracker", {
            id = "BleakfibersQuestTracker",
            name = "Quest Tracker",
            sidebarName = "Quest Tracker",
            version = ns.version or "1.1.0",
            author = "Bleakfiber",
            isBleakfiber = true,
            db = ns.db or _G["BleakfiberTrackerDB"],
            getDB = function() return ns.db or _G["BleakfiberTrackerDB"] end,
            profiles = {
                GetCurrent = function()
                    return (ns.dbObject and ns.dbObject.GetCurrentProfile and ns.dbObject:GetCurrentProfile()) or "Default"
                end,
                SetCurrent = function(profileKey)
                    if not profileKey or profileKey == "" then return end
                    if ns.dbObject and ns.dbObject.SetProfile then
                        local current = ns.dbObject:GetCurrentProfile()
                        if current == profileKey then return end

                        local exists = false
                        if ns.dbObject.GetProfiles then
                            local list = ns.dbObject:GetProfiles()
                            if type(list) == "table" then
                                for _, p in ipairs(list) do
                                    if p == profileKey then exists = true; break end
                                end
                            end
                        end

                        if exists then
                            -- Profile already exists: DO NOT OVERWRITE, just switch to it!
                            ns.dbObject:SetProfile(profileKey)
                        else
                            -- New profile: switch to it and copy from current so settings are captured!
                            ns.dbObject:SetProfile(profileKey)
                            if current and current ~= profileKey and ns.dbObject.CopyProfile then
                                ns.dbObject:CopyProfile(current)
                            end
                        end
                    else
                        ns.pendingProfileSync = profileKey
                    end
                end,
                Create = function(profileKey, fromProfile)
                    if not profileKey or profileKey == "" then return end
                    if ns.dbObject and ns.dbObject.SetProfile then
                        local current = fromProfile or (ns.dbObject.GetCurrentProfile and ns.dbObject:GetCurrentProfile())
                        local exists = false
                        if ns.dbObject.GetProfiles then
                            local list = ns.dbObject:GetProfiles()
                            if type(list) == "table" then
                                for _, p in ipairs(list) do
                                    if p == profileKey then exists = true; break end
                                end
                            end
                        end

                        if exists then
                            -- Do not overwrite existing profile!
                            ns.dbObject:SetProfile(profileKey)
                        else
                            -- Capture current settings into new profile
                            ns.dbObject:SetProfile(profileKey)
                            if current and current ~= profileKey and ns.dbObject.CopyProfile then
                                ns.dbObject:CopyProfile(current)
                            end
                        end
                    else
                        ns.pendingProfileSync = profileKey
                    end
                end,
                SaveCurrentAs = function(profileKey)
                    if not profileKey or profileKey == "" then return end
                    if ns.dbObject and ns.dbObject.SetProfile then
                        local current = ns.dbObject:GetCurrentProfile()
                        ns.dbObject:SetProfile(profileKey)
                        if current and current ~= profileKey and ns.dbObject.CopyProfile then
                            ns.dbObject:CopyProfile(current)
                        end
                    else
                        ns.pendingProfileSync = profileKey
                    end
                end,
                List = function()
                    if ns.dbObject and ns.dbObject.GetProfiles then
                        return ns.dbObject:GetProfiles()
                    end
                    return { "Default" }
                end,
                Delete = function(profileKey)
                    if not profileKey or profileKey == "Default" then return end
                    if ns.dbObject and ns.dbObject.DeleteProfile then
                        ns.dbObject:DeleteProfile(profileKey)
                    end
                end,
                Copy = function(fromKey, toKey)
                    if not fromKey or not toKey then return end
                    if ns.dbObject and ns.dbObject.SetProfile and ns.dbObject.CopyProfile then
                        ns.dbObject:SetProfile(toKey)
                        ns.dbObject:CopyProfile(fromKey)
                    end
                end,
                Reset = function(profileKey)
                    if ns.dbObject and ns.dbObject.ResetProfile then
                        if profileKey and ns.dbObject:GetCurrentProfile() ~= profileKey then
                            ns.dbObject:SetProfile(profileKey)
                        end
                        ns.dbObject:ResetProfile()
                    end
                end,
            },
            refresh = function()
                PublicAPI:ApplySettings()
            end,
            toggleMovers = function(enable)
                if ns.Tracker and ns.Tracker.SetLocked then
                    if enable ~= nil then
                        ns.Tracker:SetLocked(not enable)
                    else
                        ns.Tracker:SetLocked(not (ns.db and ns.db.isLocked))
                    end
                end
            end,
            isMoversUnlocked = function()
                return ns.db and not ns.db.isLocked
            end,
            openStandalone = function()
                PublicAPI:OpenSettings()
            end,
            buildUI = function(parentContainer)
                if PublicAPI.BuildMasterConfigUI then
                    PublicAPI:BuildMasterConfigUI(parentContainer)
                end
            end,
        })
    end
end

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

-- Player Class & Faction Color Helpers (Cached to eliminate repetitive table churn)
local cachedClassColor = nil
function ns.GetClassColor()
    if cachedClassColor then return cachedClassColor end
    local _, classFilename = UnitClass("player")
    local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFilename]) 
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename])
    if c then
        cachedClassColor = { r = c.r, g = c.g, b = c.b }
    else
        cachedClassColor = { r = 0.0, g = 0.75, b = 1.0 }
    end
    return cachedClassColor
end

local cachedFactionColor = nil
function ns.GetFactionColor()
    if cachedFactionColor then return cachedFactionColor end
    local englishFaction = UnitFactionGroup("player")
    if englishFaction == "Alliance" then
        cachedFactionColor = { r = 0.0, g = 0.44, b = 0.87 }
    elseif englishFaction == "Horde" then
        cachedFactionColor = { r = 0.87, g = 0.13, b = 0.13 }
    else
        cachedFactionColor = { r = 1.0, g = 0.82, b = 0.0 }
    end
    return cachedFactionColor
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

-- Static Difficulty Colors (Eliminates table churn in high-frequency tracker redraws)
local DIFF_COLOR_WHITE  = { r = 1.00, g = 1.00, b = 1.00 }
local DIFF_COLOR_RED    = { r = 1.00, g = 0.12, b = 0.12 }
local DIFF_COLOR_ORANGE = { r = 1.00, g = 0.50, b = 0.25 }
local DIFF_COLOR_YELLOW = { r = 1.00, g = 1.00, b = 0.00 }
local DIFF_COLOR_GREEN  = { r = 0.25, g = 1.00, b = 0.25 }
local DIFF_COLOR_GRAY   = { r = 0.60, g = 0.60, b = 0.60 }

function ns.GetDifficultyColor(level, playerLevelOverride)
    level = tonumber(level) or 0
    if level <= 0 then
        return DIFF_COLOR_WHITE
    end

    local playerLevel = playerLevelOverride or (UnitLevel and UnitLevel("player")) or 1
    local diff = level - playerLevel

    -- Calculate Blizzard green difficulty range dynamically (Classic / Wrath bracket formula)
    local greenRange = 0
    if GetQuestGreenRange then
        greenRange = GetQuestGreenRange()
    end
    if not greenRange or greenRange <= 0 then
        if playerLevel <= 5 then
            greenRange = 2
        elseif playerLevel <= 39 then
            greenRange = math.floor(playerLevel / 10) + 3
        elseif playerLevel <= 59 then
            greenRange = math.floor(playerLevel / 5) + 1
        else
            greenRange = 9
        end
    end

    if diff >= 5 then
        return (QuestDifficultyColors and QuestDifficultyColors["verydifficult"]) or DIFF_COLOR_RED
    elseif diff >= 3 then
        return (QuestDifficultyColors and QuestDifficultyColors["difficult"]) or DIFF_COLOR_ORANGE
    elseif diff >= -2 then
        return DIFF_COLOR_YELLOW
    elseif -diff <= greenRange then
        return (QuestDifficultyColors and QuestDifficultyColors["easy"]) or DIFF_COLOR_GREEN
    else
        return (QuestDifficultyColors and QuestDifficultyColors["trivial"]) or DIFF_COLOR_GRAY
    end
end

-- Grey / Trivial Quest Level Threshold Calculation
function ns.GetGreyThreshold(playerLevel)
    playerLevel = tonumber(playerLevel) or (UnitLevel and UnitLevel("player")) or 1
    if playerLevel <= 5 then
        return 5
    elseif playerLevel <= 39 then
        return math_floor(playerLevel / 10) + 5
    elseif playerLevel <= 59 then
        return math_floor(playerLevel / 5) + 1
    else
        return 9
    end
end

function ns.IsQuestGrey(questLevel, playerLevel)
    questLevel = tonumber(questLevel) or 0
    playerLevel = tonumber(playerLevel) or (UnitLevel and UnitLevel("player")) or 1
    if questLevel <= 0 then return false end
    local threshold = ns.GetGreyThreshold(playerLevel)
    return (playerLevel - questLevel) >= threshold
end

function ns.IsQuestComplete(questID, questLogIndex, objectives)
    if questID and C_QuestLog and C_QuestLog.IsComplete then
        local complete = C_QuestLog.IsComplete(questID)
        if complete == true or complete == 1 then
            return true
        end
    end

    if questID and C_QuestLog and C_QuestLog.ReadyForTurnIn then
        local ready = C_QuestLog.ReadyForTurnIn(questID)
        if ready == true or ready == 1 then
            return true
        end
    end

    if questLogIndex and ns.GetQuestLogTitle then
        local _, _, _, _, _, isComplete = ns.GetQuestLogTitle(questLogIndex)
        if isComplete == 1 or isComplete == true then
            return true
        end
    end

    if objectives and #objectives > 0 then
        local allDone = true
        for _, obj in ipairs(objectives) do
            if not obj.finished then
                allDone = false
                break
            end
        end
        if allDone then
            return true
        end
    end

    if questLogIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local numLeaderBoards = GetNumQuestLeaderBoards(questLogIndex) or 0
        if (numLeaderBoards == 0) and SelectQuestLogEntry then
            local prev = GetQuestLogSelection and GetQuestLogSelection()
            SelectQuestLogEntry(questLogIndex)
            numLeaderBoards = GetNumQuestLeaderBoards() or 0
            if numLeaderBoards > 0 then
                local allDone = true
                for j = 1, numLeaderBoards do
                    local _, _, done = GetQuestLogLeaderBoard(j)
                    if not done then allDone = false break end
                end
                if prev and prev > 0 then SelectQuestLogEntry(prev) end
                if allDone then return true end
            elseif prev and prev > 0 then
                SelectQuestLogEntry(prev)
            end
        elseif numLeaderBoards > 0 then
            local allDone = true
            for j = 1, numLeaderBoards do
                local _, _, done = GetQuestLogLeaderBoard(j, questLogIndex)
                if not done then
                    allDone = false
                    break
                end
            end
            if allDone then
                return true
            end
        end
    end

    return false
end

function ns.IsQuestFailed(questID, questLogIndex, objectives)
    if questID and C_QuestLog and C_QuestLog.IsFailed then
        local failed = SafeCall(C_QuestLog.IsFailed, questID)
        if failed == true or failed == 1 then
            return true
        end
    end
    if questLogIndex and questLogIndex > 0 then
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = SafeCall(C_QuestLog.GetInfo, questLogIndex)
            if info and (info.isFailed == true or info.isFailed == 1 or info.isComplete == -1) then
                return true
            end
        end
        if GetQuestLogTitle then
            local _, _, _, _, _, isComplete = SafeCall(GetQuestLogTitle, questLogIndex)
            if isComplete == -1 then
                return true
            end
        end
    end
    if objectives and #objectives > 0 then
        for _, obj in ipairs(objectives) do
            if obj.failed or obj.isFailed then
                return true
            end
            if obj.text and (obj.text:find("%(Failed%)") or obj.text:find("%(failed%)")) then
                return true
            end
        end
    end
    if questID and ns.GetQuestLogIndexForQuestID then
        local idx = ns.GetQuestLogIndexForQuestID(questID)
        if idx and idx > 0 and idx ~= questLogIndex then
            return ns.IsQuestFailed(nil, idx, objectives)
        end
    end
    return false
end

function ns.GetQuestLogTitle(i)
    if not i or i <= 0 then return nil end

    local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID

    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(i)
        if info then
            title = info.title
            level = info.level
            suggestedGroup = info.suggestedGroup
            isHeader = (info.isHeader == 1 or info.isHeader == true)
            isCollapsed = (info.isCollapsed == 1 or info.isCollapsed == true)
            frequency = info.frequency
            questID = info.questID
            if info.isComplete == 1 or info.isComplete == true then
                isComplete = 1
            elseif info.isComplete == -1 then
                isComplete = -1
            else
                isComplete = 0
            end
        end
    end

    if not title and GetQuestLogTitle then
        local numRet = select("#", GetQuestLogTitle(i))
        if numRet >= 9 then
            -- WotLK 3.3.5 / WoW Forever 16001:
            -- 1:title, 2:level, 3:questTag, 4:suggestedGroup, 5:isHeader, 6:isCollapsed, 7:isComplete, 8:isDaily, 9:questID
            local qTitle, qLevel, qTag, qGroup, qHdr, qCol, qComp, qDaily, qID = GetQuestLogTitle(i)
            title = qTitle
            level = qLevel
            suggestedGroup = qTag or qGroup
            isHeader = (qHdr == 1 or qHdr == true)
            isCollapsed = (qCol == 1 or qCol == true)
            isComplete = (qComp == 1 or qComp == true) and 1 or (qComp == -1 and -1 or 0)
            frequency = qDaily
            questID = tonumber(qID)
        elseif numRet >= 7 then
            -- Classic Era / Modern:
            -- 1:title, 2:level, 3:suggestedGroup, 4:isHeader, 5:isCollapsed, 6:isComplete, 7:frequency, 8:questID
            local qTitle, qLevel, qGroup, qHdr, qCol, qComp, qFreq, qID = GetQuestLogTitle(i)
            title = qTitle
            level = qLevel
            suggestedGroup = qGroup
            isHeader = (qHdr == 1 or qHdr == true)
            isCollapsed = (qCol == 1 or qCol == true)
            isComplete = (qComp == 1 or qComp == true) and 1 or (qComp == -1 and -1 or 0)
            frequency = qFreq
            questID = tonumber(qID)
        elseif numRet >= 4 then
            -- Vanilla 1.12:
            -- 1:title, 2:level, 3:questTag, 4:isHeader, 5:isCollapsed, 6:isComplete
            local qTitle, qLevel, qTag, qHdr, qCol, qComp = GetQuestLogTitle(i)
            title = qTitle
            level = qLevel
            suggestedGroup = qTag
            isHeader = (qHdr == 1 or qHdr == true)
            isCollapsed = (qCol == 1 or qCol == true)
            isComplete = (qComp == 1 or qComp == true) and 1 or (qComp == -1 and -1 or 0)
        end
    end

    if not title then return nil end

    -- Ensure questID is resolved
    if not questID or questID <= 0 then
        if C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then
            questID = C_QuestLog.GetQuestIDForLogIndex(i)
        end
    end
    if (not questID or questID <= 0) and GetQuestLink then
        local link = GetQuestLink(i)
        if link then
            local id = link:match("quest:(%d+)")
            if id then questID = tonumber(id) end
        end
    end
    if not questID or questID <= 0 then
        questID = i
    end

    return title, level, suggestedGroup, isHeader or false, isCollapsed or false, isComplete or 0, frequency or 0, questID
end

function ns.GetQuestLogIndexForQuestID(questID)
    if not questID or questID <= 0 then return nil end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local idx = SafeCall(C_QuestLog.GetLogIndexForQuestID, questID)
        if idx and idx > 0 then return idx end
    end
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and SafeCall(C_QuestLog.GetNumQuestLogEntries))
        or (GetNumQuestLogEntries and SafeCall(GetNumQuestLogEntries)) or 0
    for i = 1, numEntries do
        local qInfo = C_QuestLog and C_QuestLog.GetInfo and SafeCall(C_QuestLog.GetInfo, i)
        local qID = qInfo and qInfo.questID
        if not qID and ns.GetQuestLogTitle then
            local _, _, _, _, _, _, _, id = ns.GetQuestLogTitle(i)
            qID = id
        end
        if qID and qID == questID then
            return i
        end
    end
    return nil
end

-- Objective Object Recycling Pool (Eliminates GC overhead during quest redraws)
local objectiveObjPool = {}
local function AcquireObjectiveObj()
    local obj = table_remove(objectiveObjPool)
    if not obj then
        obj = {}
    else
        wipe(obj)
    end
    return obj
end

function ns.ReleaseObjectiveObjs(list)
    if not list then return end
    for i = 1, #list do
        local obj = list[i]
        if obj then
            table_insert(objectiveObjPool, obj)
            list[i] = nil
        end
    end
end

function ns.GetQuestObjectives(questID, questLogIndex, outList)
    local objectives = outList or {}
    if outList then
        ns.ReleaseObjectiveObjs(objectives)
    end

    -- If questLogIndex is missing but questID is provided, find questLogIndex
    local targetLogIndex = questLogIndex
    if not targetLogIndex and questID then
        local num = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and SafeCall(C_QuestLog.GetNumQuestLogEntries))
            or (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries())) or 0
        for i = 1, num do
            local qInfo = C_QuestLog and C_QuestLog.GetInfo and SafeCall(C_QuestLog.GetInfo, i)
            local foundQID = (qInfo and qInfo.questID) or (ns.GetQuestLogTitle and select(8, ns.GetQuestLogTitle(i)))
            if foundQID == questID then
                targetLogIndex = i
                break
            end
        end
    end

    if questID and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local list = C_QuestLog.GetQuestObjectives(questID)
        if list and #list > 0 then
            for _, obj in ipairs(list) do
                local entry = AcquireObjectiveObj()
                entry.text = obj.text or ""
                entry.finished = obj.finished or false
                entry.type = obj.type or ""
                entry.numFulfilled = obj.numFulfilled
                entry.numRequired = obj.numRequired
                table_insert(objectives, entry)
            end
            return objectives
        end
    end

    if targetLogIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local numLeaderBoards = GetNumQuestLeaderBoards(targetLogIndex) or 0
        if (numLeaderBoards == 0) and SelectQuestLogEntry then
            local prev = GetQuestLogSelection and GetQuestLogSelection()
            SelectQuestLogEntry(targetLogIndex)
            numLeaderBoards = GetNumQuestLeaderBoards() or 0
            for j = 1, numLeaderBoards do
                local desc, objType, done = GetQuestLogLeaderBoard(j)
                if not desc then
                    desc, objType, done = GetQuestLogLeaderBoard(j, targetLogIndex)
                end
                if desc then
                    local entry = AcquireObjectiveObj()
                    entry.text = desc
                    entry.finished = done or false
                    entry.type = objType or ""
                    local c, m = desc:match("(%d+)%s*/%s*(%d+)")
                    if c and m then
                        entry.numFulfilled = tonumber(c)
                        entry.numRequired = tonumber(m)
                    end
                    table_insert(objectives, entry)
                end
            end
            if prev and prev > 0 then SelectQuestLogEntry(prev) end
            return objectives
        elseif numLeaderBoards > 0 then
            for j = 1, numLeaderBoards do
                local desc, objType, done = GetQuestLogLeaderBoard(j, targetLogIndex)
                if desc then
                    local entry = AcquireObjectiveObj()
                    entry.text = desc
                    entry.finished = done or false
                    entry.type = objType or ""
                    local c, m = desc:match("(%d+)%s*/%s*(%d+)")
                    if c and m then
                        entry.numFulfilled = tonumber(c)
                        entry.numRequired = tonumber(m)
                    end
                    table_insert(objectives, entry)
                end
            end
            return objectives
        end
    end
    return objectives
end

function ns.IsQuestPushable(questID, questLogIndex)
    if questID and C_QuestLog and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(questID)
    end
    if questLogIndex and SelectQuestLogEntry then
        SelectQuestLogEntry(questLogIndex)
    end
    if questID and C_QuestLog and C_QuestLog.IsPushableQuest then
        local pushable = C_QuestLog.IsPushableQuest(questID)
        if pushable ~= nil then return pushable end
    end
    if GetQuestLogPushable then
        return GetQuestLogPushable() and true or false
    end
    return false
end

function ns.ShareQuest(questID, questLogIndex)
    if questID and C_QuestLog and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(questID)
    end
    if questLogIndex and SelectQuestLogEntry then
        SelectQuestLogEntry(questLogIndex)
    end
    if questID and C_QuestLog and C_QuestLog.ShareQuest then
        C_QuestLog.ShareQuest(questID)
        return true
    end
    if QuestLogPushQuest then
        QuestLogPushQuest()
        return true
    end
    return false
end

-- ===========================================================================
-- Quest Timer Active Cache Engine
-- Keeps timers rock-solid during hover, tooltip inspection, combat, and reload
-- ===========================================================================
ns.questTimerCache = ns.questTimerCache or {}

function ns.RecordQuestTimer(questID, timeLeft, maxTime)
    if not questID or not timeLeft or timeLeft <= 0 then return end
    local now = GetTime()
    local nowEpoch = time()
    local existing = ns.questTimerCache[questID]
    local mTime = maxTime or (existing and existing.maxTime) or timeLeft
    if mTime <= 0 then mTime = timeLeft end

    -- Update in-memory monotonic countdown cache
    ns.questTimerCache[questID] = {
        questID = questID,
        timeLeft = timeLeft,
        maxTime = mTime,
        expiresAt = now + timeLeft,
        expiresAtEpoch = nowEpoch + timeLeft,
    }

    -- Persist maxTime and active timer epoch to SavedVariables (throttled to avoid per-second disk flushes)
    local curDB = (ns.db and ns.db.databars)
    if curDB then
        curDB.timerMaxValues = curDB.timerMaxValues or {}
        if curDB.timerMaxValues[questID] ~= mTime then
            curDB.timerMaxValues[questID] = mTime
        end
        curDB.timerActiveQuests = curDB.timerActiveQuests or {}
        local saved = curDB.timerActiveQuests[questID]
        local newEpoch = nowEpoch + timeLeft
        if not saved or not saved.expiresAtEpoch or math.abs(saved.expiresAtEpoch - newEpoch) > 3 then
            curDB.timerActiveQuests[questID] = {
                maxTime = mTime,
                expiresAtEpoch = newEpoch,
            }
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
        end
    end
end

function ns.GetCachedQuestTimer(questID)
    if not questID then return nil, nil end
    if ns.IsQuestFailed and ns.IsQuestFailed(questID) then
        ns.ClearQuestTimer(questID)
        return nil, nil
    end
    local validQIDs = ns.GetActiveBlizzardTimerQuestIDs and ns.GetActiveBlizzardTimerQuestIDs()
    if not validQIDs or not validQIDs[questID] then
        ns.ClearQuestTimer(questID)
        return nil, nil
    end
    local cached = ns.questTimerCache[questID]
    if cached and cached.expiresAt then
        local now = GetTime()
        local remaining = math.max(0, math.floor(cached.expiresAt - now))
        if remaining > 0 then
            cached.timeLeft = remaining
            return remaining, cached.maxTime
        else
            ns.ClearQuestTimer(questID)
            return nil, nil
        end
    end
    return nil, nil
end

function ns.ClearQuestTimer(questID)
    if not questID then return end
    ns.questTimerCache[questID] = nil
    local curDB = (ns.db and ns.db.databars)
    if curDB and curDB.timerActiveQuests and curDB.timerActiveQuests[questID] then
        curDB.timerActiveQuests[questID] = nil
        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
    end
end

-- Query Blizzard's active timers directly to establish authoritative timed quest IDs
function ns.GetActiveBlizzardTimerQuestIDs()
    local validQIDs = {}
    -- Modern WoW Retail API: C_QuestLog.GetTimeAllowed across quest log entries
    if C_QuestLog and C_QuestLog.GetTimeAllowed then
        local numEntries = (C_QuestLog.GetNumQuestLogEntries and SafeCall(C_QuestLog.GetNumQuestLogEntries))
            or (GetNumQuestLogEntries and SafeCall(GetNumQuestLogEntries)) or 0
        for i = 1, numEntries do
            local qInfo = C_QuestLog.GetInfo and SafeCall(C_QuestLog.GetInfo, i)
            local qID = qInfo and qInfo.questID
            if not qID and ns.GetQuestLogTitle then
                local _, _, _, _, _, _, _, id = ns.GetQuestLogTitle(i)
                qID = id
            end
            if qID and qID > 0 and (not qInfo or not qInfo.isHeader) then
                local ok, totalTime, elapsedTime = pcall(C_QuestLog.GetTimeAllowed, qID)
                if ok and totalTime then
                    local tot = ToNumber(totalTime)
                    local elap = ToNumber(elapsedTime) or 0
                    if tot and tot > 0 and (tot - elap) > 0 then
                        validQIDs[qID] = true
                    end
                end
            end
        end
    end
    -- Modern C_QuestLog.GetQuestTimers()
    if C_QuestLog and C_QuestLog.GetQuestTimers then
        local ok, timers = pcall(C_QuestLog.GetQuestTimers)
        if ok and type(timers) == "table" then
            for _, info in ipairs(timers) do
                if type(info) == "table" then
                    local qID = info.questID or info.id
                    if qID and qID > 0 then validQIDs[qID] = true end
                end
            end
        end
    end
    return validQIDs
end

-- Purge any stale, non-timed, expired, or failed quests from timer memory and SavedVariables
function ns.PurgeInvalidTimerCache()
    local validQIDs = ns.GetActiveBlizzardTimerQuestIDs()

    if ns.questTimerCache then
        for qID in pairs(ns.questTimerCache) do
            if not validQIDs[qID] then
                ns.questTimerCache[qID] = nil
            end
        end
    end
    local curDB = (ns.db and ns.db.databars)
    if curDB then
        local changed = false
        if curDB.timerActiveQuests then
            for qID in pairs(curDB.timerActiveQuests) do
                if not validQIDs[qID] then
                    curDB.timerActiveQuests[qID] = nil
                    changed = true
                end
            end
        end
        if curDB.timerMaxValues then
            for qID in pairs(curDB.timerMaxValues) do
                if not validQIDs[qID] then
                    curDB.timerMaxValues[qID] = nil
                    changed = true
                end
            end
        end
        if changed and ns.FlushDBToGlobals then
            ns.FlushDBToGlobals()
        end
    end
end

-- ===========================================================================
-- Quest Timer Information (Modern WoW Retail Engine C_QuestLog.GetTimeAllowed)
-- ===========================================================================
function ns.GetQuestTimeInfo(questID, questLogIndex)
    if not questID and not questLogIndex then return nil, nil end

    -- 1. Resolve questID if only questLogIndex is provided
    if (not questID or questID <= 0) and questLogIndex and questLogIndex > 0 then
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = SafeCall(C_QuestLog.GetInfo, questLogIndex)
            if info and info.questID and info.questID > 0 then
                questID = info.questID
            end
        end
        if (not questID or questID <= 0) and C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then
            local qID = SafeCall(C_QuestLog.GetQuestIDForLogIndex, questLogIndex)
            if qID and qID > 0 then questID = qID end
        end
        if (not questID or questID <= 0) and ns.GetQuestLogTitle then
            local _, _, _, _, _, _, _, tQID = ns.GetQuestLogTitle(questLogIndex)
            if tQID and tQID > 0 then
                questID = tQID
            end
        end
    end

    if not questID or questID <= 0 then return nil, nil end

    if ns.IsQuestFailed and ns.IsQuestFailed(questID, questLogIndex) then
        ns.ClearQuestTimer(questID)
        return nil, nil
    end

    -- 2. Modern WoW Retail API: C_QuestLog.GetTimeAllowed(questID)
    -- In modern WoW, C_QuestLog.GetTimeAllowed(questID) returns (totalTime, elapsedTime)
    if C_QuestLog and C_QuestLog.GetTimeAllowed then
        local ok, totalTime, elapsedTime = pcall(C_QuestLog.GetTimeAllowed, questID)
        if ok and totalTime then
            local tot = ToNumber(totalTime)
            local elap = ToNumber(elapsedTime) or 0
            if tot and tot > 0 then
                local tLeft = tot - elap
                if tLeft > 0 then
                    ns.RecordQuestTimer(questID, tLeft, tot)
                    return tLeft, tot
                else
                    ns.ClearQuestTimer(questID)
                    return nil, nil
                end
            end
        end
    end

    -- 3. Monotonic cache fallback (only if this quest is authoritatively verified by Blizzard)
    if ns.questTimerCache and ns.questTimerCache[questID] then
        local cachedTime, cachedMax = ns.GetCachedQuestTimer(questID)
        if cachedTime and cachedTime > 0 then
            return cachedTime, cachedMax
        end
    end

    -- If no Blizzard timer detected, ensure this quest is cleared from cache
    ns.ClearQuestTimer(questID)
    return nil, nil
end
ns.GetQuestTimeLeft = ns.GetQuestTimeInfo

-- Default Settings
ns.defaultDB = {
    profile = {
        -- Positioning & Sizing
        framePosition = nil,
        growCorner = "AUTO", -- "AUTO", "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT"
        width = 280,
        maxHeight = 600,
        scale = 1.0,
        itemButtonPosition = nil, -- Dragged quest item button position
        itemButtonPlacement = "inside_right", -- "inside_right", "outside_left"
        showTimerInObjectives = true,         -- Show countdown timer in quest objective descriptions
        onboardingCompleted = false,          -- First-time account onboarding wizard status
        collapsedQuests = {},     -- [questID or title] = true when user collapsed the quest
        collapsedZones = {},      -- [zoneName] = true when user collapsed a zone header
        activeQuestIcon = "star", -- "star", "arrow", "blizz", "pointer", "none"

        -- Modular Architecture (Live Enable/Disable)
        modules = {
            wayfinder = true,
            databars = true,
            questAutomation = true,
            qol = true,
        },

        -- Dedicated Quest Automation Settings
        questAutomation = {
            autoAcceptNPC = false,
            autoAcceptShared = false,
            autoTurnIn = false,
            autoShare = false,
            shiftBypass = true,
        },

        -- Quality of Life Settings
        qol = {
            fastAutoLoot = true,
            autoVendorGreys = false,
            autoSellJunk = false,
            autoRepair = false,
            useGuildRepair = false,
            shiftBypass = true,
        },

        -- Headers Configuration
        headers = {
            -- Main Tracker Header Bar
            texture = "flat",              -- "none", "flat", "gradient", "blizzard"
            statusbarTexture = "Solid",    -- Statusbar texture used by bars/headers
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
            showCompleteIcon = true,       -- Show Blizzard gold ? in front of completed quests
        },

        -- Appearance & Backdrop
        backdrop = {
            show = true,
            borderStyle = "flat", -- "flat" (1px), "tooltip" (Blizzard rounded), "dialog", "toast", "none"
            bgTexture = "solid",  -- "solid", "tooltip", "marble", "rock", "parchment"
            bgFile = "Solid", -- Default or SharedMedia
            edgeFile = "Solid",
            edgeSize = 1,
            borderWidth = 1,
            insets = 0,
            bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.65 },
            borderColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.9 },
            classColorBorder = false,      -- Auto-color tracker border by character class
            padding = 8,
        },

        -- Typography
        fonts = {
            font = "Nata Sans Bold",
            headerFont = "Nata Sans Bold",
            headerSize = 13,
            headerOutline = "OUTLINE",
            zoneHeaderSize = 12,
            objectiveFont = "Nata Sans Regular",
            objectiveSize = 11,
            objectiveOutline = "",
            enableTextShadow = true,
            colorDifficulty = true,
        },

        -- Filtering & Behavior
        filtering = {
            filterMode = "all", -- "all", "zone", "watched"
            zoneOnly = false,
            enableCrossZone = true, -- Multi-zone objective and turn-in tracking
            autoHideInInstances = false,
            autoHideEmpty = false,
            collapseInCombat = false,
            hideInCombat = false, -- Automatically hide quest tracker in combat (default: off)
            untrackedQuests = {}, -- [questID] = true for quests manually hidden/untracked by the player
        },

        -- Sorting
        sorting = {
            mode = "level", -- "level", "zone"
            moveCompletedToBottom = false, -- Push "Ready for turn-in" quests to bottom of tracker
            activeOnTop = true,            -- Pin active quest (★) to the very top of tracker
            showGroupTags = true,          -- Show [11+] elite/group and dungeon badges
        },

        -- Social & Quest Automation
        social = {
            autoShare = false,           -- Auto-share quests to party upon accept
            autoAcceptNPC = false,       -- Auto-accept quests from NPCs
            autoAcceptShared = false,    -- Auto-accept quests shared by party members
            autoTurnIn = false,          -- Auto-turnin quests with 0 or 1 reward choice
            fastAutoLoot = true,         -- Fast Auto Loot (instantly loots all items; enabled by default)
            shiftBypass = true,          -- Hold Shift to temporarily bypass automation
            announceToParty = false,     -- Announce objective/quest completion to party chat
            announceQuestComplete = true,      -- Announce quest completion to party chat
            announceObjectiveProgress = false, -- Announce objective progress (N/X) to party chat
            announceObjectiveComplete = true,  -- Announce individual objective completion to party chat
        },

        -- Tooltips & Mouseover Rewards
        tooltips = {
            showRewards = true,          -- Show quest rewards (XP, money, items) on mouseover
            showXpPercent = true,        -- Show XP reward percentage toward current level
            showUsableGear = true,       -- Highlight class-usable equipment rewards
            showBestSell = true,         -- Mark highest vendor resale choice reward
            showPartyStatus = true,      -- Show party members on quest in tooltip
            showMissingParty = true,     -- Show party members missing the quest in tooltip
            classColorParty = true,      -- Color party member names with class color
            showPartyBadge = false,      -- Append [👥 #] group count badge next to quest title
        },

        -- Audio & Sounds
        sound = {
            enableCompleteSound = true,        -- Play sound on full quest complete (Work complete!)
            soundChoice = "peon",              -- "peon", "quest_complete", "level_up", "raid_warning", "ready_check", "map_ping", "pvp_horn", "custom"
            completeSoundChannel = "Master",   -- "Master", "SFX", "Ambience"
            completeSoundVolume = 100,         -- Playback volume percentage (5 to 100)
            useCustomCompleteSound = false,
            customCompleteSoundChoice = "beep",-- "beep", "click", "custom1", "custom2", "custom3", "custom4", "custom5", "manual"
            customCompleteSoundPath = "Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Sounds\\beep.wav",

            enableObjectiveSound = true,       -- Play sound when an objective updates (e.g. 3/4 Raptor Horns)
            objectiveSoundChoice = "whisper_ping", -- Max 5 subtle Classic choices: "whisper_ping", "coins", "loot_clink", "map_ping", "item_click"
            objectiveSoundChannel = "Master",  -- "Master", "SFX", "Ambience"
            objectiveSoundVolume = 100,        -- Playback volume percentage (5 to 100)
            useCustomObjectiveSound = false,
            customObjectiveSoundChoice = "beep", -- "beep", "click", "custom1", "custom2", "custom3", "custom4", "custom5", "manual"
            customObjectiveSoundPath = "Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Sounds\\beep.wav",
        },


        -- Wayfinder (Waypoint Navigation & Directional Arrows)
        wayfinder = {
            enableHUDArrow = true,        -- Floating HUD Arrow toggle (enabled by default)
            enableInlineArrow = true,     -- Inline Tracker Mini Arrow toggle (enabled by default)
            inlineArrowPosition = "left", -- "left" (in front of title) or "right" (tracker margin)
            inlineArrowSize = 22,         -- Inline Tracker Arrow Size in pixels (14 to 32, default 22)
            autoTrackActiveQuest = true,  -- Automatically point to ns.activeQuestID
            showDistance = true,          -- Show yards/meters below arrow / tooltip
            distanceUnit = "imperial",    -- "imperial" (yards/miles) or "metric" (meters/kilometers)
            arrowScale = 1.0,             -- Scale (0.6 to 1.6)
            arrivalThreshold = 15,        -- Yards to consider "Arrived"
            arrivalClearDelay = 5,        -- Seconds to display "Arrived!" before auto-clearing (0-30, default 5)
            playArrivalSound = true,      -- Chime when arrived
            hudPosition = nil,            -- Saved frame position { point = "CENTER", x = 0, y = 150 }
            locked = false,               -- Lock HUD arrow position
            showBackdrop = false,         -- Semi-transparent circular backdrop behind floating HUD arrow (default: off)
            arrowStyle = "auto",          -- Arrow graphic style: "auto" (default: Modern Minimalist), "minimal", or "classic"
            hideInCombat = true,          -- Hide waypoint arrow during combat (default: true)
            showETA = false,              -- Show Estimated Time of Arrival (ETA) countdown (optional)
            showMapPins = true,           -- Show pin icons on World Map & Minimap for custom waypoints (optional)
            showCoordinates = false,      -- Show Player & Cursor coordinates display on World Map (optional)
            savedWaypoints = {},          -- Persistent custom waypoints across game sessions
            hudFontSize = 11,             -- Floating HUD arrow distance text size (8 to 18px)
            hudFontOutline = "OUTLINE",   -- Floating HUD arrow distance text outline
            showDestination = true,       -- Show target/quest/flight destination name above distance readout
            hudTitleFormat = "zone",      -- "zone" (e.g. Westfall), "quest" (e.g. The People's Militia), or "both" (Westfall - The People's Militia)
            hudTitleFontSize = 11,        -- Floating HUD arrow destination text size (8 to 18px)
            hudTitleFontOutline = "OUTLINE", -- Floating HUD arrow destination text outline
        },

        -- DataBars: XP / Quest Log Progress Bar & Location Header Bar
        databars = {
            hideInCombat = false,              -- Hide DataBars (XP & Location bar) while in combat (default: off)
            useTrackerAppearance = true,       -- Follow tracker frame backdrop, border, and texture style (default: true)
            dockSpacing = 0,                   -- Spacing in pixels between tracker frame and docked DataBars (default: 0)
            -- Experience & Completed Quest Log XP Progress Bar
            enableXPBar = false,               -- Standalone XP / Quest Log progress bar
            xpDockMode = "tracker_bottom",     -- "tracker_bottom" (snaps to tracker, default), "default_bar", "free"
            xpHeight = 14,                     -- Bar height (8 to 32px)
            xpWidth = 512,                     -- Bar width when in default_bar or free mode
            xpFontSize = 11,                   -- XP bar text font size (8 to 18px)
            xpFontOutline = "OUTLINE",         -- XP bar text outline
            xpBorderStyle = "flat",            -- "flat", "tooltip", "dialog", "toast", "none"
            xpBorderWidth = 1,                 -- Border thickness in px
            xpBorderColor = { r = 0.12, g = 0.12, b = 0.16, a = 0.95 },
            xpBgTexture = "solid",             -- "solid", "tooltip", "marble", "rock", "parchment"
            xpBarTexture = "Solid",            -- Statusbar texture for XP bar
            hideBlizzardXPBar = true,          -- Suppress Blizzard's default XP status tracking bar (default: true)
            replaceBlizzardXP = true,          -- Compatibility alias for hideBlizzardXPBar
            showCompletedQuestXP = true,       -- Show completed quest turn-in XP overlay (ghost bar)
            showAllQuestXP = false,            -- Show all active quests XP overlay (ghost bar behind completed XP, default off)
            hideQuestXPText = false,           -- Hide (+Done) and (+All) quest XP bonus text from on-bar readout (ghost bars & tooltip remain)
            showDingReadyText = true,          -- Show [Ding Ready!] indicator when turn-in XP exceeds level requirement
            showRestedXP = true,               -- Show rested XP bonus segment
            showReputationAtMax = true,        -- Automatically transition to watched reputation at max level
            xpTextFormat = "smart",            -- "smart", "cur_max", "cur_pct", "remain", "none"
            xpFreePosition = nil,              -- Saved position for "free" docking mode
            xpBgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.65 },     -- Base color
            xpColor = { r = 0.58, g = 0.00, b = 0.83, a = 1.00 },       -- Actual XP (Default Purple)
            restedColor = { r = 0.00, g = 0.44, b = 0.88, a = 1.00 },   -- Rested XP (Default Blue, high z draw order)
            allQuestXPColor = { r = 0.12, g = 0.45, b = 0.25, a = 0.80 }, -- Full Questlog XP (Default Darker Green 80% opacity)
            questXPColor = { r = 0.25, g = 0.85, b = 0.45, a = 0.65 },  -- Completed Quest Log XP (Default Lighter Green lower opacity)
            dingReadyColor = { r = 1.00, g = 0.82, b = 0.00, a = 1.00 },-- Gold ([Ding Ready!] Alert)

            -- Location & Precision Coordinates Header Bar
            enableLocationBar = false,         -- Location & Precision coordinates header bar
            locDockMode = "tracker_top",       -- "tracker_top" (snaps above tracker), "minimap_top", "free"
            locHeight = 22,                    -- Bar height (16 to 36px)
            locWidth = 280,                    -- Bar width when in free mode
            locFontSize = 11,                  -- Location bar text font size (8 to 18px)
            locFontOutline = "OUTLINE",        -- Location bar text outline
            locBorderStyle = "flat",           -- "flat", "tooltip", "dialog", "toast", "none"
            locBorderWidth = 1,                -- Border thickness in px
            locBgTexture = "solid",            -- "solid", "tooltip", "marble", "rock", "parchment"
            locBgColor = { r = 0.06, g = 0.08, b = 0.12, a = 0.90 },
            locBorderColor = { r = 0.15, g = 0.55, b = 0.95, a = 0.85 },
            locCustomTextColor = false,        -- Override PvP territory coloring with custom text color
            locTextColor = { r = 1.00, g = 0.82, b = 0.00, a = 1.00 }, -- Custom text color
            hideMinimapHeader = true,          -- Suppress default Minimap header (MinimapCluster.ZoneTextButton / BorderTop)
            hideDefaultCoordinates = false,    -- Suppress default map coordinates
            colorTerritory = true,             -- Color zone/subzone by PvP status (Sanctuary, Friendly, Contested, Hostile)
            showSubzone = true,                -- Show subzone text alongside zone name
            locFormat = "subzone_only",        -- "subzone_only" (shows subzone when in a landmark, zone in wild), "smart", "zone_only", "both"
            showCoords = true,                 -- Show player coordinates (XX.X, YY.Y)
            locFreePosition = nil,             -- Saved position for "free" docking mode

            -- Quest Timer DataBar (Timed Quests)
            enableTimerBar = true,             -- Quest Timer standalone data bar for timed quests (default: true)
            timerDockMode = "tracker_top",     -- "tracker_top" (snaps above tracker), "tracker_bottom", "free"
            timerHeight = 22,                  -- Bar height (16 to 36px)
            timerWidth = 220,                  -- Bar width
            timerFontSize = 11,                -- Timer text font size (8 to 18px)
            timerFontOutline = "OUTLINE",      -- Timer text font outline
            timerBorderStyle = "flat",         -- "flat", "tooltip", "dialog", "toast", "none"
            timerBorderWidth = 1,              -- Border thickness in px
            timerBgTexture = "solid",          -- "solid", "tooltip", "marble", "rock", "parchment"
            timerBgColor = { r = 0.06, g = 0.08, b = 0.12, a = 0.90 },
            timerBorderColor = { r = 1.00, g = 0.82, b = 0.00, a = 0.85 },
            timerBarTexture = "Solid",         -- Statusbar texture for timer bar
            timerShowTitle = true,             -- Show quest title alongside timer (e.g. "A Hot Mug: 04:12")
            timerFreePosition = nil,           -- Saved position for "free" docking mode
            timerColor = { r = 1.00, g = 0.82, b = 0.00, a = 1.00 }, -- Classic gold statusbar / text
            timerMaxValues = {},               -- Persisted maximum durations for timed quests across /reload
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

-- Full recursive deep copy (clones ALL keys, not just missing ones — used for backup/restore)
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            copy[k] = DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end
ns.DeepCopy = DeepCopy

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

local moduleKeyMap = {
    WayfinderModule = "wayfinder",
    DataBarsModule = "databars",
    QuestAutomationModule = "questAutomation",
    QoLModule = "qol",
}

function ns:RegisterModule(name, moduleTable)
    if not name or type(moduleTable) ~= "table" then return end
    self.modules[name] = moduleTable
    moduleTable.name = name
end

function ns:GetModule(name)
    return self.modules[name]
end

function ns.IsModuleEnabled(moduleKey)
    local db = ns.db and ns.db.modules
    if not db then return true end
    local key = moduleKeyMap[moduleKey] or moduleKey
    if db[key] == nil then return true end
    return db[key] ~= false
end

function ns.SetModuleEnabled(moduleKey, enabled)
    if not ns.db then return end
    if not ns.db.modules then ns.db.modules = {} end
    ns.db.modules[moduleKey] = enabled and true or false

    local moduleInstances = {
        wayfinder = ns.WayfinderModule,
        databars = ns.DataBarsModule,
        questAutomation = ns.QuestAutomationModule,
        qol = ns.QoLModule,
    }
    local mod = moduleInstances[moduleKey]
    if mod then
        if enabled then
            if mod.Enable then
                pcall(mod.Enable, mod)
            elseif mod.Initialize then
                pcall(mod.Initialize, mod)
            end
        else
            if mod.Disable then
                pcall(mod.Disable, mod)
            end
        end
    end

    if ns.FlushDBToGlobals then
        ns.FlushDBToGlobals()
    end
end

function ns:InitializeModules()
    for name, mod in pairs(self.modules) do
        local key = moduleKeyMap[name]
        local isEnabled = true
        if key then
            isEnabled = ns.IsModuleEnabled(key)
        end
        if isEnabled and type(mod.Initialize) == "function" then
            local success, err = pcall(mod.Initialize, mod)
            if not success then
                print("|cffff3333[" .. addonName .. " Error]|r Failed to initialize module '" .. name .. "': " .. tostring(err))
            end
        end
    end
end

-- Keybinding Global Strings for Game Key Bindings Menu
_G["BINDING_HEADER_BLEAKFIBER_TRACKER"] = "Bleakfiber's Quest Tracker"
_G["HEADER_BLEAKFIBER_TRACKER"] = "Bleakfiber's Quest Tracker"
_G["BINDING_CATEGORY_BLEAKFIBER_TRACKER"] = "Bleakfiber's Quest Tracker"
_G["BINDING_CATEGORY_Bleakfiber's Quest Tracker"] = "Bleakfiber's Quest Tracker"
_G["BINDING_NAME_BLEAKFIBER_USE_QUEST_ITEM"] = "Use Active Quest Item"

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

    -- WoW Forever SavedVariables Backup Restore:
    -- WoW Forever creates a duplicate 70/ folder for SavedVariables which can cause
    -- settings to revert to defaults on reload/relog. If the primary DB is empty but
    -- our backup has real data, restore from backup before AceDB touches anything.
    local function HasAnyProfileData(db)
        if not db or type(db) ~= "table" then return false end
        if type(db.profiles) == "table" then
            for _, pTable in pairs(db.profiles) do
                if type(pTable) == "table" and next(pTable) then
                    return true
                end
            end
        end
        if type(db.profile) == "table" and next(db.profile) then
            return true
        end
        return false
    end

    local backupDB = _G["BleakfiberTrackerBackupDB"]
    local primaryDB = _G["BleakfiberTrackerDB"]
    local primaryHasProfiles = HasAnyProfileData(primaryDB)
    local backupHasProfiles = HasAnyProfileData(backupDB)

    if not primaryHasProfiles and backupHasProfiles then
        -- Primary DB is empty/default but backup has real data — restore it
        ns.Debug("[Backup Restore] Primary DB empty, restoring from BleakfiberTrackerBackupDB")
        _G["BleakfiberTrackerDB"] = DeepCopy(backupDB)
        primaryDB = _G["BleakfiberTrackerDB"]
        rawExists = true
    elseif primaryHasProfiles and not backupHasProfiles then
        -- Backup is stale/empty — update it from primary
        ns.Debug("[Backup Restore] Backup empty, seeding from primary DB")
        _G["BleakfiberTrackerBackupDB"] = DeepCopy(primaryDB)
    elseif primaryHasProfiles and backupHasProfiles then
        -- Both exist — keep backup in sync with primary (primary wins on load)
        _G["BleakfiberTrackerBackupDB"] = DeepCopy(primaryDB)
    end

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
            if ns.db.itemButtonPlacement == "inside_left" or ns.db.itemButtonPlacement == "outside_right" then
                ns.db.itemButtonPlacement = (ns.db.itemButtonPlacement == "inside_left") and "outside_left" or "inside_right"
            end
            if ns.Tracker and ns.Tracker.UpdateSettings then
                ns.Tracker:UpdateSettings()
            end
            if ns.SocialModule and ns.SocialModule.UpdateLootEvents then
                ns.SocialModule:UpdateLootEvents()
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

        if ns.pendingProfileSync then
            local pending = ns.pendingProfileSync
            ns.pendingProfileSync = nil
            local exists = false
            if dbObject.GetProfiles then
                local list = dbObject:GetProfiles()
                if type(list) == "table" then
                    for _, p in ipairs(list) do
                        if p == pending then exists = true; break end
                    end
                end
            end
            local current = dbObject:GetCurrentProfile()
            if exists then
                dbObject:SetProfile(pending)
            else
                dbObject:SetProfile(pending)
                if current and current ~= pending and dbObject.CopyProfile then
                    dbObject:CopyProfile(current)
                end
            end
        end
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

    -- Initialize per-character storage for frame position
    if not _G["BleakfiberTrackerCharDB"] then
        _G["BleakfiberTrackerCharDB"] = {}
    end
    ns.charDB = (ns.dbObject and ns.dbObject.char) or _G["BleakfiberTrackerCharDB"]

    -- Restore from per-character backup if profile framePosition is missing
    if ns.db and not ns.db.framePosition and _G["BleakfiberTrackerCharDB"].framePosition then
        ns.db.framePosition = _G["BleakfiberTrackerCharDB"].framePosition
    end

    if not ns.db.collapsedQuests then
        ns.db.collapsedQuests = {}
    end
    if ns.db.sorting and ns.db.sorting.mode == "distance" then
        ns.db.sorting.mode = "level"
    end
    if ns.db and (ns.db.itemButtonPlacement == "inside_left" or ns.db.itemButtonPlacement == "outside_right") then
        ns.db.itemButtonPlacement = (ns.db.itemButtonPlacement == "inside_left") and "outside_left" or "inside_right"
    end
    if not BleakfiberTrackerDB.partyQuestData then
        BleakfiberTrackerDB.partyQuestData = {}
    end
    ns.partyQuestData = BleakfiberTrackerDB.partyQuestData

    -- Initialize Wayfinder defaults for existing profiles
    if ns.db and ns.db.wayfinder then
        if not ns.db.wayfinder.initialized then
            ns.db.wayfinder.enableHUDArrow = true
            ns.db.wayfinder.enableInlineArrow = true
            ns.db.wayfinder.initialized = true
        end
        if not ns.db.wayfinder.inlineArrowSize or ns.db.wayfinder.inlineArrowSize < 18 then
            ns.db.wayfinder.inlineArrowSize = 22
        end
        if not ns.db.wayfinder.inlineArrowPosition then
            ns.db.wayfinder.inlineArrowPosition = "left"
        end
        if ns.db.wayfinder.arrivalClearDelay == nil then
            ns.db.wayfinder.arrivalClearDelay = 5
        end
        if ns.db.wayfinder.showBackdrop == nil then
            ns.db.wayfinder.showBackdrop = false
        end
        local validStyles = { ["auto"] = true, ["minimal"] = true, ["classic"] = true }
        if not ns.db.wayfinder.arrowStyle or not validStyles[ns.db.wayfinder.arrowStyle] then
            ns.db.wayfinder.arrowStyle = "auto"
        end
        if ns.db.wayfinder.hideInCombat == nil then
            ns.db.wayfinder.hideInCombat = true
        end
        if ns.db.wayfinder.showETA == nil then
            ns.db.wayfinder.showETA = false
        end
        if ns.db.wayfinder.showMapPins == nil then
            ns.db.wayfinder.showMapPins = true
        end
        if ns.db.wayfinder.showCoordinates == nil then
            ns.db.wayfinder.showCoordinates = false
        end
        if not ns.db.wayfinder.savedWaypoints then
            ns.db.wayfinder.savedWaypoints = {}
        end
    end

    if ns.db and ns.db.sorting and ns.db.sorting.activeOnTop == nil then
        ns.db.sorting.activeOnTop = true
    end

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

    -- Default typography: fallback only if unassigned
    if ns.db and ns.db.fonts then
        if not ns.db.fonts.font or ns.db.fonts.font == "" then
            ns.db.fonts.font = "Nata Sans Bold"
        end
        if not ns.db.fonts.headerFont or ns.db.fonts.headerFont == "" then
            ns.db.fonts.headerFont = "Nata Sans Bold"
        end
        if not ns.db.fonts.objectiveFont or ns.db.fonts.objectiveFont == "" then
            ns.db.fonts.objectiveFont = "Nata Sans Regular"
        end
        if ns.db.fonts.objectiveOutline == "NONE" then
            ns.db.fonts.objectiveOutline = ""
        end
        if ns.db.fonts.headerOutline == "NONE" then
            ns.db.fonts.headerOutline = ""
        end
    end

    -- Initialize Sound defaults for existing profiles
    if ns.db then
        if not ns.db.sound then
            ns.db.sound = {}
        end
        if ns.db.sound.enableCompleteSound == nil then
            ns.db.sound.enableCompleteSound = true
        end
        if not ns.db.sound.soundChoice then
            ns.db.sound.soundChoice = "peon"
        end
        if not ns.db.sound.customCompleteSoundChoice then
            ns.db.sound.customCompleteSoundChoice = "beep"
        end
        if not ns.db.sound.customCompleteSoundPath then
            ns.db.sound.customCompleteSoundPath = "Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Sounds\\beep.wav"
        end
        if ns.db.sound.enableObjectiveSound == nil then
            ns.db.sound.enableObjectiveSound = true
        end
        if not ns.db.sound.objectiveSoundChoice then
            ns.db.sound.objectiveSoundChoice = "whisper_ping"
        end
        if not ns.db.sound.customObjectiveSoundChoice then
            ns.db.sound.customObjectiveSoundChoice = "beep"
        end
        if not ns.db.sound.customObjectiveSoundPath then
            ns.db.sound.customObjectiveSoundPath = "Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Sounds\\beep.wav"
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
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            InitializeDB("ADDON_LOADED")
        elseif arg1 == "BleakfibersAddonConfigForever" or arg1 == "BleakfibersAddonConfig-Forever" then
            if PublicAPI.RegisterWithMasterConfig then
                PublicAPI:RegisterWithMasterConfig()
            end
        end
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
        if ns.SocialModule and ns.SocialModule.UpdateLootEvents then
            ns.SocialModule:UpdateLootEvents()
        end
        ns:FireCallback("ON_INITIALIZE")

        -- Register with Master Config addon if present
        if PublicAPI.RegisterWithMasterConfig then
            PublicAPI:RegisterWithMasterConfig()
        end
        if ns.PurgeInvalidTimerCache then
            ns.PurgeInvalidTimerCache()
        end

        if ns.Onboarding and ns.Onboarding.CheckFirstTimeUser then
            if C_Timer and C_Timer.After then
                C_Timer.After(1.5, function()
                    ns.Onboarding:CheckFirstTimeUser()
                end)
            else
                ns.Onboarding:CheckFirstTimeUser()
            end
        end

        -- WoW Forever SavedVariables Periodic Flush:
        -- Sync the live AceDB profile into both global tables every 30 seconds.
        -- This protects against crashes/disconnects where WoW doesn't get to run
        -- its normal PLAYER_LOGOUT serialization.
        local function FlushDBToGlobals()
            local liveDB = _G["BleakfiberTrackerDB"]
            if liveDB and type(liveDB) == "table" then
                _G["BleakfiberTrackerBackupDB"] = DeepCopy(liveDB)
            end
            if ns.db and ns.db.framePosition and _G["BleakfiberTrackerCharDB"] then
                _G["BleakfiberTrackerCharDB"].framePosition = DeepCopy(ns.db.framePosition)
            end
        end
        ns.FlushDBToGlobals = FlushDBToGlobals

        -- Use C_Timer if available (modern clients), otherwise fallback to OnUpdate throttle
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(30, FlushDBToGlobals)
        else
            local elapsed = 0
            local flushFrame = CreateFrame("Frame")
            flushFrame:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if elapsed >= 30 then
                    elapsed = 0
                    FlushDBToGlobals()
                end
            end)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        ns:FireCallback("PLAYER_ENTERING_WORLD", ...)
        if ns.PurgeInvalidTimerCache then
            ns.PurgeInvalidTimerCache()
        end

        -- Flush backup on zone transitions (loading screens) — another point where
        -- WoW Forever can lose SavedVariables data
        if ns.FlushDBToGlobals then
            ns.FlushDBToGlobals()
        end

    elseif event == "PLAYER_LOGOUT" then
        -- Aggressive flush: ensure both primary and backup globals are fully up to date
        -- before WoW serializes them to disk (to both root and 70/ folders)
        if ns.FlushDBToGlobals then
            ns.FlushDBToGlobals()
        end
        local liveDB = _G["BleakfiberTrackerDB"]

        local rawExists = liveDB ~= nil
        local hasProf = rawExists and type(liveDB.profiles) == "table"
        local def = hasProf and liveDB.profiles["Default"]
        local defPos = def and def.framePosition
        ns.Debug(string.format("[LOGOUT Flush] RawDB=%s, BackupDB=%s, Pos=%s", 
            tostring(rawExists), 
            tostring(_G["BleakfiberTrackerBackupDB"] ~= nil),
            defPos and (defPos.point .. " (" .. tostring(defPos.x) .. ", " .. tostring(defPos.y) .. ")") or "nil"))
    end
end)

