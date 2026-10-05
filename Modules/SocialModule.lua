local addonName, ns = ...

local SocialModule = {}
ns.SocialModule = SocialModule
ns:RegisterModule("SocialModule", SocialModule)

-- Sound effect presets with direct CASC FileDataIDs and SoundKit IDs
-- Sound effect presets with SoundKit IDs, classic sound names, and audio file paths
local SOUND_PRESETS = {
    peon = {
        name = "Peon: \"Work complete!\"",
        kit = (SOUNDKIT and SOUNDKIT.UI_PEON_BUILDING_COMPLETE_01) or 6199,
        soundName = "PeonBuildingComplete1",
        files = {
            "Sound\\Creature\\Peon\\PeonBuildingComplete1.ogg",
            "Sound\\Creature\\Peon\\PeonBuildingComplete1.wav",
            558132,
        },
    },
    quest_complete = {
        name = "Classic Quest Complete Chime",
        kit = (SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE) or 618,
        soundName = "igQuestListComplete",
        files = {
            "Sound\\Interface\\igQuestListComplete.ogg",
            "Sound\\Interface\\igQuestListComplete.wav",
            567400,
        },
    },
    map_ping = {
        name = "Mini-Map Ping",
        kit = (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175,
        soundName = "MapPing",
        files = {
            "Sound\\Interface\\MapPing.ogg",
            "Sound\\Interface\\MapPing.wav",
            567439,
        },
    },
    item_click = {
        name = "Subtle Objective Click",
        kit = (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856,
        soundName = "igMainMenuOptionCheckBoxOn",
        files = {
            "Sound\\Interface\\uChatScrollButton.ogg",
            "Sound\\Interface\\uChatScrollButton.wav",
        },
    },
    level_up = {
        name = "Level Up Fanfare",
        kit = (SOUNDKIT and SOUNDKIT.LEVEL_UP) or 888,
        soundName = "LevelUp",
        files = {
            "Sound\\Interface\\LevelUp.ogg",
            "Sound\\Interface\\LevelUp.wav",
        },
    },
    raid_warning = {
        name = "Raid Warning Chime",
        kit = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959,
        soundName = "RaidWarning",
        files = {
            "Sound\\Interface\\RaidWarning.ogg",
            "Sound\\Interface\\RaidWarning.wav",
        },
    },
    ready_check = {
        name = "Ready Check Chime",
        kit = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960,
        soundName = "ReadyCheck",
        files = {
            "Sound\\Interface\\ReadyCheck.ogg",
            "Sound\\Interface\\ReadyCheck.wav",
        },
    },
    pvp_horn = {
        name = "PvP Queue Horn",
        kit = (SOUNDKIT and SOUNDKIT.PVP_THROUGH_QUEUE) or 8456,
        soundName = "PVPThroughQueue",
        files = {
            "Sound\\Interface\\PVPThroughQueue.ogg",
            "Sound\\Interface\\PVPThroughQueue.wav",
        },
    },
}

-- Track quest and objective completion states so sounds ONLY play on actual completion
local completedQuestsCache = {}
local completedObjectivesCache = {}
local objectiveCountCache = {}
local soundSuppressedUntil = GetTime() + 5.0 -- Mute completion sounds during initial load & zoning
local lastSoundPlayTime = 0

function SocialModule:PlaySoundKey(choice)
    local preset = SOUND_PRESETS[choice] or SOUND_PRESETS.peon
    local played = false

    -- 1. Try runtime SOUNDKIT table first with multiple channels
    if SOUNDKIT and PlaySound then
        local kitConst = (choice == "peon" and SOUNDKIT.UI_PEON_BUILDING_COMPLETE_01)
            or (choice == "quest_complete" and SOUNDKIT.IG_QUEST_LIST_COMPLETE)
            or (choice == "level_up" and SOUNDKIT.LEVEL_UP)
            or (choice == "raid_warning" and SOUNDKIT.RAID_WARNING)
            or (choice == "ready_check" and SOUNDKIT.READY_CHECK)
            or (choice == "map_ping" and SOUNDKIT.MAP_PING)
            or (choice == "item_click" and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            or (choice == "pvp_horn" and SOUNDKIT.PVP_THROUGH_QUEUE)
        if kitConst then
            local ok, willPlay = pcall(PlaySound, kitConst, "Master")
            if ok and willPlay ~= false then
                played = true
            else
                local ok2, willPlay2 = pcall(PlaySound, kitConst, "SFX")
                if ok2 and willPlay2 ~= false then
                    played = true
                else
                    local ok3, willPlay3 = pcall(PlaySound, kitConst)
                    if ok3 and willPlay3 ~= false then
                        played = true
                    end
                end
            end
        end
    end

    -- 2. Try numeric preset.kit
    if not played and preset.kit and PlaySound then
        local ok, willPlay = pcall(PlaySound, preset.kit, "Master")
        if ok and willPlay ~= false then
            played = true
        else
            local ok2, willPlay2 = pcall(PlaySound, preset.kit, "SFX")
            if ok2 and willPlay2 ~= false then
                played = true
            else
                local ok3, willPlay3 = pcall(PlaySound, preset.kit)
                if ok3 and willPlay3 ~= false then
                    played = true
                end
            end
        end
    end

    -- 3. Try legacy sound name string via PlaySound
    if not played and preset.soundName and PlaySound then
        local ok, willPlay = pcall(PlaySound, preset.soundName, "Master")
        if ok and willPlay ~= false then
            played = true
        else
            pcall(PlaySound, preset.soundName)
        end
    end

    -- 4. Try PlaySoundFile with exact paths and FileDataIDs
    if not played and preset.files and PlaySoundFile then
        for _, file in ipairs(preset.files) do
            local ok, willPlay = pcall(PlaySoundFile, file, "Master")
            if ok and willPlay ~= false then
                played = true
                break
            else
                local ok2, willPlay2 = pcall(PlaySoundFile, file, "SFX")
                if ok2 and willPlay2 ~= false then
                    played = true
                    break
                else
                    local ok3, willPlay3 = pcall(PlaySoundFile, file)
                    if ok3 and willPlay3 ~= false then
                        played = true
                        break
                    end
                end
            end
        end
    end
end

function SocialModule:PlayCompletionSound()
    local now = GetTime()
    if soundSuppressedUntil and now < soundSuppressedUntil then return end
    if lastSoundPlayTime and (now - lastSoundPlayTime) < 0.25 then return end
    lastSoundPlayTime = now

    local db = ns.db and ns.db.sound
    if not (db and db.enableCompleteSound) then return end
    self:PlaySoundKey(db.soundChoice or "peon")
end

function SocialModule:PlayObjectiveSound()
    local now = GetTime()
    if soundSuppressedUntil and now < soundSuppressedUntil then return end
    if lastSoundPlayTime and (now - lastSoundPlayTime) < 0.25 then return end
    lastSoundPlayTime = now

    local db = ns.db and ns.db.sound
    if not (db and db.enableObjectiveSound) then return end
    self:PlaySoundKey(db.objectiveSoundChoice or "map_ping")
end

function SocialModule:PlayPreviewSound(choice)
    self:PlaySoundKey(choice or (ns.db and ns.db.sound and ns.db.sound.soundChoice) or "peon")
end

function SocialModule:PlayPreviewObjectiveSound(choice)
    self:PlaySoundKey(choice or (ns.db and ns.db.sound and ns.db.sound.objectiveSoundChoice) or "map_ping")
end

-- Helper: Check if automation is currently bypassed by holding Shift
local function IsBypassed()
    local db = ns.db and ns.db.social
    if db and db.shiftBypass and IsShiftKeyDown() then
        return true
    end
    return false
end

-- Helper: Determine if current quest offer is from an NPC vs shared by a party member
local function IsNPCOffer()
    if UnitExists("npc") then return true end
    if UnitExists("target") and not UnitIsPlayer("target") then return true end
    return false
end

local function AnnouncePartyMessage(msg)
    if GetTime() < soundSuppressedUntil then return end
    local db = ns.db and ns.db.social
    if not (db and db.announceToParty) then return end
    if not (IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0)) then return end

    local chatType = "PARTY"
    if IsInRaid and IsInRaid() then
        chatType = "RAID"
    elseif IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        chatType = "INSTANCE_CHAT"
    end
    if SendChatMessage then
        SendChatMessage(msg, chatType)
    end
end

local function CheckForCompletions()
    local now = GetTime()
    local isSuppressed = (now < soundSuppressedUntil)
    local numEntries = (ns.GetNumQuestLogEntries and select(1, ns.GetNumQuestLogEntries()))
        or (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries()))
        or 0

    local questJustCompleted = false
    local objectiveJustProgressed = false

    for i = 1, numEntries do
        local title, _, _, isHeader, _, isComplete, _, questID = (ns.GetQuestLogTitle and ns.GetQuestLogTitle(i))
            or (GetQuestLogTitle and GetQuestLogTitle(i))

        if not isHeader and questID then
            local isFinished = (isComplete == 1 or isComplete == true)
                or (ns.IsQuestComplete and ns.IsQuestComplete(questID, i))

            -- 1. Full Quest Completion (ready for turn-in)
            local wasQuestComplete = completedQuestsCache[questID]
            if isFinished then
                if wasQuestComplete == false and not isSuppressed then
                    questJustCompleted = true
                    AnnouncePartyMessage(string.format("[BFQ] Quest Complete: %s", title or "Quest"))
                end
                completedQuestsCache[questID] = true
            else
                completedQuestsCache[questID] = false
            end

            -- 2. Individual Objective Progress & Completion
            local objectives = (ns.GetQuestObjectives and ns.GetQuestObjectives(questID, i))
                or (C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID))
                or {}

            for j, obj in ipairs(objectives) do
                local text = obj.text
                local finished = obj.finished
                local key = questID .. "_" .. j
                local wasObjFinished = completedObjectivesCache[key]
                local cur, maxVal = 0, 1

                if text then
                    local c, m = text:match("(%d+)%s*/%s*(%d+)")
                    if c and m then
                        cur = tonumber(c) or 0
                        maxVal = tonumber(m) or 1
                    else
                        cur = (finished and 1) or 0
                        maxVal = 1
                    end
                else
                    cur = (finished and 1) or 0
                    maxVal = 1
                end

                local wasCount = objectiveCountCache[key]
                objectiveCountCache[key] = cur

                if finished then
                    if wasObjFinished == false and not isSuppressed then
                        if not isFinished then
                            objectiveJustProgressed = true
                        end
                        AnnouncePartyMessage(string.format("[BFQ] Completed: %s", text or "Objective"))
                    end
                    completedObjectivesCache[key] = true
                else
                    completedObjectivesCache[key] = false
                    -- Count increased (e.g. looting 3/4 Raptor Horns)
                    if wasCount ~= nil and cur > wasCount and not isSuppressed then
                        objectiveJustProgressed = true
                    end
                end
            end
        end
    end

    if not isSuppressed then
        if questJustCompleted then
            SocialModule:PlayCompletionSound()
        elseif objectiveJustProgressed then
            SocialModule:PlayObjectiveSound()
        end
    end
end

--------------------------------------------------------------------------------
-- PARTY QUEST PROGRESS SYNC & CLICK-TO-SHARE ENGINE
--------------------------------------------------------------------------------
ns.partyQuestData = (BleakfiberTrackerDB and BleakfiberTrackerDB.partyQuestData) or ns.partyQuestData or {}

-- Register hidden addon communications channel
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix("BFQ_SYNC")
elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix("BFQ_SYNC")
end

-- Helper: Normalize character name (lowercase, strip realm and whitespace)
local function CleanName(name)
    if not name or name == "" or name == "Unknown" or name == UNKNOWNOBJECT then return "" end
    local raw = name:match("^([^-]+)") or name
    raw = raw:match("^%s*(.-)%s*$") or raw
    if raw == "" or raw == "Unknown" or raw == UNKNOWNOBJECT then return "" end
    return string.lower(raw)
end

-- Helper: Check if a cleaned name is an active member in the player's group
local function IsMemberInGroup(cleanName)
    if not cleanName or cleanName == "" then return false end
    local numMembers = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if numMembers <= 1 then return false end
    local isRaid = IsInRaid and IsInRaid()
    for i = 1, numMembers do
        local unit = isRaid and ("raid" .. i) or (i < numMembers and ("party" .. i) or nil)
        if unit and UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local rawName = UnitName(unit)
            if CleanName(rawName) == cleanName then
                return true
            end
        end
    end
    return false
end

-- Helper: Determine appropriate chat channel for party communication
local function GetSyncChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid and IsInRaid() then
        return "RAID"
    elseif IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
        return "PARTY"
    end
    return nil
end

local function SendSync(msg)
    local channel = GetSyncChannel()
    if not channel then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage("BFQ_SYNC", msg, channel)
    elseif SendAddonMessage then
        SendAddonMessage("BFQ_SYNC", msg, channel)
    end
end

-- Broadcast current character's quest progress to the party (disabled)
function SocialModule:BroadcastMyQuests()
    -- Party progress sync disabled
end

-- Share a specific quest with party members & track manual share state
local lastManuallySharedQuestID = nil
local lastManuallySharedTime = 0

function SocialModule:ShareQuest(questID, questLogIndex)
    if not (IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0)) then
        ns.Print("You are not in a group.")
        return false
    end

    lastManuallySharedQuestID = questID
    lastManuallySharedTime = GetTime()

    if not questLogIndex or questLogIndex == 0 then
        local numEntries = (ns.GetNumQuestLogEntries and select(1, ns.GetNumQuestLogEntries())) or (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries())) or 0
        for i = 1, numEntries do
            local _, _, _, isH, _, _, _, id = (ns.GetQuestLogTitle and ns.GetQuestLogTitle(i)) or (GetQuestLogTitle and GetQuestLogTitle(i))
            if not isH and id == questID then
                questLogIndex = i
                break
            end
        end
    end

    -- The default quest log only enables its Share button after the quest has
    -- been clicked/selected; IsPushableQuest / GetQuestLogPushable both read
    -- that selection state, so querying them cold reports even shareable
    -- quests as unshareable. Select the quest first, same as Blizzard's UI does.
    if questID and C_QuestLog and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(questID)
    end
    if questLogIndex and SelectQuestLogEntry then
        SelectQuestLogEntry(questLogIndex)
    end

    -- Determine pushability across modern and classic APIs
    local isPushable = false
    if questID and C_QuestLog and C_QuestLog.IsPushableQuest then
        isPushable = C_QuestLog.IsPushableQuest(questID)
    end
    if not isPushable and GetQuestLogPushable then
        isPushable = GetQuestLogPushable() and true or false
    end
    if not isPushable and ns.IsQuestPushable then
        isPushable = ns.IsQuestPushable(questID, questLogIndex)
    end

    if not isPushable then
        ns.Print("This quest cannot be shared.")
        return false
    end

    -- Push to party via modern Retail / Midnight API (C_QuestLog.ShareQuest) or legacy QuestLogPushQuest
    if questID and C_QuestLog and C_QuestLog.ShareQuest then
        C_QuestLog.ShareQuest(questID)
        ns.Print("Shared quest with party.")
        return true
    end

    if QuestLogPushQuest then
        QuestLogPushQuest()
        ns.Print("Shared quest with party.")
        return true
    end

    if ns.ShareQuest and ns.ShareQuest(questID, questLogIndex) then
        ns.Print("Shared quest with party.")
        return true
    end

    ns.Print("This quest cannot be shared.")
    return false
end

function SocialModule:IsRecentlyShared(questID)
    if lastManuallySharedQuestID == questID and (GetTime() - lastManuallySharedTime) < 3.5 then
        return true
    end
    return false
end

-- Helper: Listen for Blizzard server feedback on quest shares (e.g. "Player is already on that quest")
local function HandleQuestShareSystemFeedback(msg)
    if not msg or not lastManuallySharedQuestID then return end
    if (GetTime() - lastManuallySharedTime) > 8 then return end

    local qID = lastManuallySharedQuestID
    local playerName = nil

    local function MatchPattern(globalPattern)
        if not globalPattern or not msg then return nil end
        local pat = globalPattern:gsub("%%[0-9]%$s", "(.-)"):gsub("%%s", "(.-)"):gsub("%.", "%%."):gsub("%-", "%%-")
        local m1, m2 = msg:match(pat)
        return m2 or m1
    end

    playerName = MatchPattern(ERR_QUEST_ALREADY_HAVE_S)
        or MatchPattern(ERR_QUEST_ALREADY_DONE_S)
        or MatchPattern(ERR_QUEST_NOT_FOUND_S)
        or MatchPattern(ERR_QUEST_ACCEPTED_S)
        or MatchPattern(ERR_QUEST_DECLINED_S)
        or MatchPattern(ERR_QUEST_LOG_FULL_S)
        or MatchPattern(ERR_QUEST_BUSY_S)
        or MatchPattern(ERR_QUEST_PUSH_SUCCESS_S)

    -- Universal fallback regex patterns (English and standard variations)
    if not playerName then
        playerName = msg:match("^(.-) is already on that quest")
            or msg:match("^(.-) has already completed")
            or msg:match("^(.-) is not eligible")
            or msg:match("^(.-) has accepted the quest")
            or msg:match("^(.-) declines the quest")
            or msg:match("^(.-)'s quest log is full")
            or msg:match("^(.-) is busy")
            or msg:match("shared .+ with (.-)%.?$")
            or msg:match("Sharing .+ with (.-)%.%.%.$")
    end

    -- If in a 2-player group and any share-related message fired, target the other member
    if not playerName and (GetNumGroupMembers and GetNumGroupMembers() == 2) then
        local raw = UnitName("party1")
        if raw then playerName = raw end
    end

    if playerName and type(playerName) == "string" then
        local clean = CleanName(playerName)
        if clean ~= "" then
            ns.partyQuestData[qID] = ns.partyQuestData[qID] or { objectives = {}, have = {} }
            ns.partyQuestData[qID].have[clean] = true
            if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                ns.StandaloneTracker:UpdateTracker()
            end
        end
    end
end

-- Retrieve party progress formatted summary for an objective (disabled)
function SocialModule:GetObjectivePartyProgress(questID, objIndex)
    return nil
end

-- Check if party members are missing this quest and if it can be shared
function SocialModule:GetMissingPartyInfo(questID, questLogIndex)
    if not (IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0)) then
        return 0, false
    end

    if not questLogIndex or questLogIndex == 0 then
        local numEntries = (ns.GetNumQuestLogEntries and select(1, ns.GetNumQuestLogEntries())) or (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries())) or 0
        for i = 1, numEntries do
            local _, _, _, isH, _, _, _, id = (ns.GetQuestLogTitle and ns.GetQuestLogTitle(i)) or (GetQuestLogTitle and GetQuestLogTitle(i))
            if not isH and id == questID then
                questLogIndex = i
                break
            end
        end
    end

    -- Same selection requirement as ShareQuest: IsPushableQuest/GetQuestLogPushable
    -- report on whichever quest is currently selected, not the questID passed in.
    if questID and C_QuestLog and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(questID)
    elseif questLogIndex and SelectQuestLogEntry then
        SelectQuestLogEntry(questLogIndex)
    end

    local isPushable = false
    if questID and C_QuestLog and C_QuestLog.IsPushableQuest then
        isPushable = C_QuestLog.IsPushableQuest(questID)
    end
    if not isPushable and ns.IsQuestPushable then
        isPushable = ns.IsQuestPushable(questID, questLogIndex)
    end
    if not isPushable and questLogIndex and GetQuestLogPushable then
        isPushable = GetQuestLogPushable() and true or false
    end
    if not isPushable then
        return 0, false
    end

    local numMembers = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if numMembers <= 1 then return 0, false end

    local haveData = (ns.partyQuestData[questID] and ns.partyQuestData[questID].have) or {}
    local missingCount = 0

    local isRaid = IsInRaid and IsInRaid()
    for i = 1, numMembers do
        local unit = isRaid and ("raid" .. i) or (i < numMembers and ("party" .. i) or nil)
        if unit and UnitExists(unit) and UnitIsConnected(unit) and not UnitIsUnit(unit, "player") then
            local rawName = UnitName(unit)
            local clean = CleanName(rawName)
            if clean ~= "" and not haveData[clean] then
                missingCount = missingCount + 1
            end
        end
    end

    return missingCount, isPushable
end

function SocialModule:UpdateLootEvents()
    local db = (ns.dbObject and ns.dbObject.profile) or ns.db
    local fastLoot = db and db.social and db.social.fastAutoLoot ~= false
    if self.eventFrame then
        if fastLoot then
            self.eventFrame:RegisterEvent("LOOT_READY")
            self.eventFrame:RegisterEvent("LOOT_OPENED")
        else
            self.eventFrame:UnregisterEvent("LOOT_READY")
            self.eventFrame:UnregisterEvent("LOOT_OPENED")
        end
    end
end

--------------------------------------------------------------------------------
-- EVENT INITIALIZATION
--------------------------------------------------------------------------------
function SocialModule:Initialize()
    local eventFrame = CreateFrame("Frame")
    self.eventFrame = eventFrame
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("ZONE_CHANGED")
    eventFrame:RegisterEvent("QUEST_ACCEPTED")
    eventFrame:RegisterEvent("QUEST_DETAIL")
    eventFrame:RegisterEvent("QUEST_ACCEPT_CONFIRM")
    eventFrame:RegisterEvent("QUEST_PROGRESS")
    eventFrame:RegisterEvent("QUEST_COMPLETE")
    eventFrame:RegisterEvent("GOSSIP_SHOW")
    eventFrame:RegisterEvent("QUEST_GREETING")
    eventFrame:RegisterEvent("QUEST_WATCH_UPDATE")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    eventFrame:RegisterEvent("QUEST_REMOVED")
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    eventFrame:RegisterEvent("UI_INFO_MESSAGE")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("GROUP_LEFT")
    self:UpdateLootEvents()
    local rosterUpdateTimer = nil

    local lastSharedQuestID = nil
    local lastSharedTime = 0
    local lastBroadcastTime = 0

    eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, ...)
        -- 0. World & Zone Transition Events (Suppress sounds, seed caches, re-sync party)
        if event == "PLAYER_ENTERING_WORLD" then
            soundSuppressedUntil = GetTime() + 4.0
            CheckForCompletions()

            if BleakfiberTrackerDB then
                if not BleakfiberTrackerDB.partyQuestData then
                    BleakfiberTrackerDB.partyQuestData = {}
                end
                ns.partyQuestData = BleakfiberTrackerDB.partyQuestData
            end

            if not (IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0)) then
                if BleakfiberTrackerDB then
                    BleakfiberTrackerDB.partyQuestData = {}
                end
                ns.partyQuestData = (BleakfiberTrackerDB and BleakfiberTrackerDB.partyQuestData) or {}
            end
            return

        elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
            soundSuppressedUntil = GetTime() + 3.5
            CheckForCompletions()
            return
        end

        local currentDB = (ns.dbObject and ns.dbObject.profile) or ns.db
        local db = (currentDB and currentDB.social) or {}

        -- Fast Auto Loot
        if event == "LOOT_READY" or event == "LOOT_OPENED" then
            if db.fastAutoLoot ~= false and not IsBypassed() then
                local numLoot = (GetNumLootItems and GetNumLootItems()) or 0
                if numLoot > 0 then
                    for i = numLoot, 1, -1 do
                        LootSlot(i)
                    end
                end
            end
            return
        end

        -- 1. Auto-Share Quests upon accepting when in a party
        if event == "QUEST_ACCEPTED" then
            local questLogIndex, questID = arg1, arg2
            if not questID and type(questLogIndex) == "number" and C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then
                questID = C_QuestLog.GetQuestIDForLogIndex(questLogIndex)
            end

            if db.autoShare and (IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0)) then
                local now = GetTime()
                if questID and (questID ~= lastSharedQuestID or (now - lastSharedTime) > 2) then
                    lastSharedQuestID = questID
                    lastSharedTime = now

                    C_Timer.After(0.3, function()
                        SocialModule:ShareQuest(questID, questLogIndex)
                    end)
                end
            end

            -- Update quest completion
            C_Timer.After(0.5, function()
                CheckForCompletions()
            end)

        -- 2. Auto-Accept Quests (Split: NPC quests and Shared party quests)
        elseif event == "QUEST_DETAIL" then
            if IsBypassed() then return end

            local isNPC = IsNPCOffer()
            if isNPC and db.autoAcceptNPC then
                AcceptQuest()
            elseif (not isNPC) and db.autoAcceptShared then
                AcceptQuest()
            end

        elseif event == "QUEST_ACCEPT_CONFIRM" then
            if IsBypassed() then return end
            if db.autoAcceptNPC or db.autoAcceptShared then
                ConfirmAcceptQuest()
            end

        -- 3. Auto-Progress / Gossip Dialogs
        elseif event == "GOSSIP_SHOW" then
            if IsBypassed() then return end

            -- Prioritize turning in active complete quests first
            if db.autoTurnIn and C_GossipInfo and C_GossipInfo.GetActiveQuests then
                local active = C_GossipInfo.GetActiveQuests()
                if active then
                    for _, q in ipairs(active) do
                        if q.isComplete then
                            C_GossipInfo.SelectActiveQuest(q.questID)
                            return
                        end
                    end
                end
            end

            -- Auto-accept available quest if only 1 is available
            if db.autoAcceptNPC and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
                local available = C_GossipInfo.GetAvailableQuests()
                if available and #available == 1 then
                    C_GossipInfo.SelectAvailableQuest(available[1].questID)
                end
            end

        elseif event == "QUEST_GREETING" then
            if IsBypassed() then return end

            -- Auto turn-in complete active quests
            if db.autoTurnIn and GetNumActiveQuests then
                local numActive = GetNumActiveQuests() or 0
                for i = 1, numActive do
                    local _, isComplete = GetActiveTitle(i)
                    if isComplete then
                        SelectActiveQuest(i)
                        return
                    end
                end
            end

            -- Auto-select available quest if only 1 is offered
            if db.autoAcceptNPC and GetNumAvailableQuests then
                local numAvailable = GetNumAvailableQuests() or 0
                if numAvailable == 1 then
                    SelectAvailableQuest(1)
                end
            end

        -- 4. Auto Turn-In (Only for quests with 1 or less reward choice)
        elseif event == "QUEST_PROGRESS" then
            if IsBypassed() then return end
            if db.autoTurnIn and IsQuestCompletable and IsQuestCompletable() then
                CompleteQuest()
            end

        elseif event == "QUEST_COMPLETE" then
            if IsBypassed() then return end
            if db.autoTurnIn then
                local numChoices = (GetNumQuestChoices and GetNumQuestChoices()) or 0
                if numChoices <= 1 then
                    -- 0 or 1 choice: automatically claim reward
                    GetQuestReward(numChoices == 1 and 1 or 0)
                end
                -- If numChoices > 1: pause so player can pick their gear upgrade!
            end

        -- 5. Completion Sound Alerts
        elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_UPDATE" or (event == "UNIT_QUEST_LOG_CHANGED" and arg1 == "player") then
            CheckForCompletions()

        elseif event == "QUEST_REMOVED" then
            local qid = arg1
            if qid then
                completedQuestsCache[qid] = nil
                for j = 1, 10 do
                    completedObjectivesCache[qid .. "_" .. j] = nil
                    objectiveCountCache[qid .. "_" .. j] = nil
                end
                if ns.partyQuestData then
                    ns.partyQuestData[qid] = nil
                end
            end

        -- 6. Addon Message Communications (Party Quest Sync disabled)
        elseif event == "CHAT_MSG_ADDON" then
            -- Party progress sync disabled

        -- 7. Blizzard System Feedback for Quest Sharing
        elseif event == "CHAT_MSG_SYSTEM" or event == "UI_INFO_MESSAGE" then
            HandleQuestShareSystemFeedback(arg1)

        -- 8. Group Roster Changes
        elseif event == "GROUP_ROSTER_UPDATE" then
            if rosterUpdateTimer then
                rosterUpdateTimer:Cancel()
                rosterUpdateTimer = nil
            end
            if C_Timer and C_Timer.NewTimer then
                rosterUpdateTimer = C_Timer.NewTimer(0.5, function()
                    rosterUpdateTimer = nil
                    if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                        ns.StandaloneTracker:UpdateTracker()
                    end
                end)
            else
                if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                    ns.StandaloneTracker:UpdateTracker()
                end
            end

        elseif event == "GROUP_LEFT" then
            if rosterUpdateTimer then
                rosterUpdateTimer:Cancel()
                rosterUpdateTimer = nil
            end
            if BleakfiberTrackerDB then
                BleakfiberTrackerDB.partyQuestData = {}
            end
            ns.partyQuestData = (BleakfiberTrackerDB and BleakfiberTrackerDB.partyQuestData) or {}
            if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                ns.StandaloneTracker:UpdateTracker()
            end
        end
    end)

    -- Initial silent population of quest cache
    CheckForCompletions()
end