local addonName, ns = ...

-- Localized Lua & WoW API bindings for performance & garbage reduction
local pairs, ipairs, type, tostring, tonumber, select, pcall = pairs, ipairs, type, tostring, tonumber, select, pcall
local string_format, string_match, string_lower, string_gsub = string.format, string.match, string.lower, string.gsub
local GetTime = GetTime
local PlaySound, PlaySoundFile = PlaySound, PlaySoundFile
local C_Timer, CreateFrame = C_Timer, CreateFrame
local IsInGroup, IsInRaid = IsInGroup, IsInRaid
local IsShiftKeyDown = IsShiftKeyDown
local UnitExists, UnitName, UnitIsPlayer, UnitIsUnit, UnitIsConnected = UnitExists, UnitName, UnitIsPlayer, UnitIsUnit, UnitIsConnected

local SocialModule = {}
ns.SocialModule = SocialModule
ns:RegisterModule("SocialModule", SocialModule)

-- Sound effect presets with direct CASC FileDataIDs and SoundKit IDs
-- Sound effect presets with SoundKit IDs, classic sound names, and audio file paths
local SOUND_PRESETS = {
    -- Classic Subtle Sounds (Used for Objective Progress - Exactly 5 subtle Classic choices)
    whisper_ping = {
        name = "Whisper Ping (TellMessage)",
        kit = (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081,
        soundName = "TellMessage",
        files = {
            "Sound\\Interface\\iTellMessage.ogg",
            "Sound\\Interface\\iTellMessage.wav",
            567431,
        },
    },
    coins = {
        name = "Gold Coin Ding",
        kit = (SOUNDKIT and SOUNDKIT.LOOT_COIN_DING) or 895,
        soundName = "LootCoinDing",
        files = {
            "Sound\\Interface\\LootCoinDing.ogg",
            "Sound\\Interface\\LootCoinDing.wav",
            567425,
        },
    },
    loot_clink = {
        name = "Loot Coin Clink",
        kit = (SOUNDKIT and SOUNDKIT.IG_BACKPACK_COIN_SELECT) or 880,
        soundName = "igBackPackCoinSelect",
        files = {
            "Sound\\Interface\\igBackPackCoinSelect.ogg",
            "Sound\\Interface\\igBackPackCoinSelect.wav",
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
        name = "Subtle Click",
        kit = (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856,
        soundName = "igMainMenuOptionCheckBoxOn",
        files = {
            "Sound\\Interface\\uChatScrollButton.ogg",
            "Sound\\Interface\\uChatScrollButton.wav",
        },
    },

    -- Quest Complete Sounds
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
    custom_beep = {
        name = "Bleakfiber Beep (Custom)",
        files = {
            "Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Sounds\\beep.wav",
        },
    },
}

-- Track quest and objective completion states so sounds ONLY play on actual completion
local completedQuestsCache = {}
local completedObjectivesCache = {}
local objectiveCountCache = {}
local soundSuppressedUntil = GetTime() + 2.0 -- Mute completion sounds during initial load
local lastSoundPlayTime = 0

-- Volume scaling controller (Temporarily adjusts playback channel CVar if < 100%)
local activeVolumeAdjustments = {}

local function PlaySoundWithVolume(playFunc, channel, volumePercent)
    channel = channel or "Master"
    volumePercent = tonumber(volumePercent) or 100
    if volumePercent > 100 then volumePercent = 100 end
    if volumePercent < 5 then volumePercent = 5 end

    -- Direct playback if at full volume or CVars unavailable
    if volumePercent >= 98 or not SetCVar or not GetCVar then
        playFunc(channel)
        return
    end

    local cvar = (channel == "SFX" and "Sound_SFXVolume")
        or (channel == "Ambience" and "Sound_AmbienceVolume")
        or (channel == "Music" and "Sound_MusicVolume")
        or "Sound_MasterVolume"

    local currentCVar = tonumber(GetCVar(cvar)) or 1.0

    if not activeVolumeAdjustments[cvar] then
        activeVolumeAdjustments[cvar] = {
            base = currentCVar,
            timer = nil,
        }
    end

    local state = activeVolumeAdjustments[cvar]
    local ratio = volumePercent / 100.0
    local targetVol = math.max(0.01, math.min(1.0, state.base * ratio))

    SetCVar(cvar, tostring(targetVol))
    playFunc(channel)

    if state.timer and state.timer.Cancel then
        state.timer:Cancel()
    end

    local restoreDelay = 1.2
    if C_Timer and C_Timer.NewTimer then
        state.timer = C_Timer.NewTimer(restoreDelay, function()
            SetCVar(cvar, tostring(state.base))
            activeVolumeAdjustments[cvar] = nil
        end)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(restoreDelay, function()
            SetCVar(cvar, tostring(state.base))
            activeVolumeAdjustments[cvar] = nil
        end)
    end
end

function SocialModule:PlaySoundKey(choice, channel, volume)
    local preset = SOUND_PRESETS[choice] or SOUND_PRESETS.peon
    channel = channel or "Master"
    volume = tonumber(volume) or 100

    PlaySoundWithVolume(function(ch)
        local played = false

        -- 1. Try runtime SOUNDKIT table first with target channel
        if SOUNDKIT and PlaySound then
            local kitConst = (choice == "peon" and SOUNDKIT.UI_PEON_BUILDING_COMPLETE_01)
                or (choice == "quest_complete" and SOUNDKIT.IG_QUEST_LIST_COMPLETE)
                or (choice == "level_up" and SOUNDKIT.LEVEL_UP)
                or (choice == "raid_warning" and SOUNDKIT.RAID_WARNING)
                or (choice == "ready_check" and SOUNDKIT.READY_CHECK)
                or (choice == "map_ping" and SOUNDKIT.MAP_PING)
                or (choice == "item_click" and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                or (choice == "pvp_horn" and SOUNDKIT.PVP_THROUGH_QUEUE)
                or (choice == "whisper_ping" and SOUNDKIT.TELL_MESSAGE)
                or (choice == "coins" and SOUNDKIT.LOOT_COIN_DING)
                or (choice == "loot_clink" and SOUNDKIT.IG_BACKPACK_COIN_SELECT)
            if kitConst then
                local ok, willPlay = pcall(PlaySound, kitConst, ch)
                if ok and willPlay ~= false then
                    played = true
                else
                    local ok2, willPlay2 = pcall(PlaySound, kitConst, "Master")
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
            local ok, willPlay = pcall(PlaySound, preset.kit, ch)
            if ok and willPlay ~= false then
                played = true
            else
                local ok2, willPlay2 = pcall(PlaySound, preset.kit, "Master")
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
            local ok, willPlay = pcall(PlaySound, preset.soundName, ch)
            if ok and willPlay ~= false then
                played = true
            else
                pcall(PlaySound, preset.soundName)
            end
        end

        -- 4. Try PlaySoundFile with exact paths and FileDataIDs
        if not played and preset.files and PlaySoundFile then
            for _, file in ipairs(preset.files) do
                local ok, willPlay = pcall(PlaySoundFile, file, ch)
                if ok and willPlay ~= false then
                    played = true
                    break
                else
                    local ok2, willPlay2 = pcall(PlaySoundFile, file, "Master")
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
    end, channel, volume)
end

function SocialModule:PlaySoundFileWithVolume(soundFile, channel, volume)
    if not soundFile or soundFile == "" then return end
    channel = channel or "Master"
    volume = tonumber(volume) or 100

    if ns.FetchSound then
        soundFile = ns.FetchSound(soundFile)
    end

    PlaySoundWithVolume(function(ch)
        local ok, willPlay = pcall(PlaySoundFile, soundFile, ch)
        if not ok or willPlay == false then
            local ok2, willPlay2 = pcall(PlaySoundFile, soundFile, "Master")
            if not ok2 or willPlay2 == false then
                pcall(PlaySoundFile, soundFile)
            end
        end
    end, channel, volume)
end

local function GetSoundDB()
    local currentDB = (ns.dbObject and ns.dbObject.profile) or ns.db
    return currentDB and currentDB.sound
end

local function ResolveCustomSound(choice, manualPath)
    if choice and choice ~= "manual" then
        if ns.FetchSound then
            local fetched = ns.FetchSound(choice)
            if fetched and fetched ~= "" then
                return fetched
            end
        end
        return choice
    end
    return manualPath
end

function SocialModule:PlayCompletionSound()
    local now = GetTime()
    if soundSuppressedUntil and now < soundSuppressedUntil then return end
    if lastSoundPlayTime and (now - lastSoundPlayTime) < 0.25 then return end

    local sdb = GetSoundDB()
    if sdb and sdb.enableCompleteSound == false then return end
    lastSoundPlayTime = now

    local channel = (sdb and sdb.completeSoundChannel) or "Master"
    local volume = (sdb and sdb.completeSoundVolume) or 100

    if sdb and (sdb.useCustomCompleteSound or sdb.soundChoice == "custom") then
        local soundTarget = ResolveCustomSound(sdb.customCompleteSoundChoice, sdb.customCompleteSoundPath)
        if soundTarget and soundTarget ~= "" then
            self:PlaySoundFileWithVolume(soundTarget, channel, volume)
            return
        end
    end
    self:PlaySoundKey((sdb and sdb.soundChoice) or "peon", channel, volume)
end

function SocialModule:PlayObjectiveSound()
    local now = GetTime()
    if soundSuppressedUntil and now < soundSuppressedUntil then return end
    if lastSoundPlayTime and (now - lastSoundPlayTime) < 0.25 then return end

    local sdb = GetSoundDB()
    if sdb and sdb.enableObjectiveSound == false then return end
    lastSoundPlayTime = now

    local channel = (sdb and sdb.objectiveSoundChannel) or "Master"
    local volume = (sdb and sdb.objectiveSoundVolume) or 100

    if sdb and (sdb.useCustomObjectiveSound or sdb.objectiveSoundChoice == "custom") then
        local soundTarget = ResolveCustomSound(sdb.customObjectiveSoundChoice, sdb.customObjectiveSoundPath)
        if soundTarget and soundTarget ~= "" then
            self:PlaySoundFileWithVolume(soundTarget, channel, volume)
            return
        end
    end
    self:PlaySoundKey((sdb and sdb.objectiveSoundChoice) or "whisper_ping", channel, volume)
end

function SocialModule:PlayPreviewSound(choice, channel, volume)
    local sdb = GetSoundDB()
    channel = channel or (sdb and sdb.completeSoundChannel) or "Master"
    volume = volume or (sdb and sdb.completeSoundVolume) or 100
    choice = choice or (sdb and sdb.soundChoice) or "peon"

    if (choice == "custom" or (sdb and sdb.useCustomCompleteSound)) then
        local soundTarget = ResolveCustomSound(sdb and sdb.customCompleteSoundChoice, sdb and sdb.customCompleteSoundPath)
        if soundTarget and soundTarget ~= "" then
            self:PlaySoundFileWithVolume(soundTarget, channel, volume)
            return
        end
    end
    self:PlaySoundKey(choice, channel, volume)
end

function SocialModule:PlayPreviewObjectiveSound(choice, channel, volume)
    local sdb = GetSoundDB()
    channel = channel or (sdb and sdb.objectiveSoundChannel) or "Master"
    volume = volume or (sdb and sdb.objectiveSoundVolume) or 100
    choice = choice or (sdb and sdb.objectiveSoundChoice) or "whisper_ping"

    if (choice == "custom" or (sdb and sdb.useCustomObjectiveSound)) then
        local soundTarget = ResolveCustomSound(sdb and sdb.customObjectiveSoundChoice, sdb and sdb.customObjectiveSoundPath)
        if soundTarget and soundTarget ~= "" then
            self:PlaySoundFileWithVolume(soundTarget, channel, volume)
            return
        end
    end
    self:PlaySoundKey(choice, channel, volume)
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
    local isSuppressed = (soundSuppressedUntil and now < soundSuppressedUntil) or false
    local numEntries = (ns.GetNumQuestLogEntries and select(1, ns.GetNumQuestLogEntries()))
        or (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries()))
        or 0

    local questJustCompleted = false
    local objectiveJustProgressed = false

    for i = 1, numEntries do
        local title, level, suggestedGroup, isHeader, isCollapsed, isCompleteVal, frequency, questID
        if ns.GetQuestLogTitle then
            title, level, suggestedGroup, isHeader, isCollapsed, isCompleteVal, frequency, questID = ns.GetQuestLogTitle(i)
        elseif GetQuestLogTitle then
            title, level, suggestedGroup, isHeader, isCollapsed, isCompleteVal, frequency, questID = GetQuestLogTitle(i)
        end

        if title and not isHeader and (questID or i) then
            questID = questID or i

            -- 1. Gather objectives first
            local objectives = (ns.GetQuestObjectives and ns.GetQuestObjectives(questID, i))
                or (C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID))
                or {}

            -- Check if all objectives are completed
            local allObjectivesDone = false
            if #objectives > 0 then
                allObjectivesDone = true
                for _, obj in ipairs(objectives) do
                    if not obj.finished then
                        allObjectivesDone = false
                        break
                    end
                end
            end

            -- Determine if entire quest is complete
            local isFinished = (isCompleteVal == 1 or isCompleteVal == true)
                or allObjectivesDone
                or (ns.IsQuestComplete and ns.IsQuestComplete(questID, i, objectives))

            -- Full Quest Completion check
            local wasQuestComplete = completedQuestsCache[questID]
            if isFinished then
                if wasQuestComplete == false and not isSuppressed then
                    questJustCompleted = true
                    local sdb = ns.db and ns.db.social
                    if not sdb or sdb.announceQuestComplete ~= false then
                        AnnouncePartyMessage(string.format("[BFQ] %s (Complete)", title or "Quest"))
                    end
                end
                completedQuestsCache[questID] = true
            else
                completedQuestsCache[questID] = false
            end

            -- Individual Objective Progress & Completion
            for j, obj in ipairs(objectives) do
                local text = obj.text
                local finished = obj.finished
                local key = questID .. "_" .. j
                local wasObjFinished = completedObjectivesCache[key]
                local cur, maxVal = 0, 1

                if obj.numFulfilled ~= nil and obj.numRequired ~= nil then
                    cur = tonumber(obj.numFulfilled) or 0
                    maxVal = tonumber(obj.numRequired) or 1
                elseif text then
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
                        local sdb = ns.db and ns.db.social
                        if not sdb or sdb.announceObjectiveComplete ~= false then
                            local objLabel = text or "Objective"
                            AnnouncePartyMessage(string.format("[BFQ] %s: %s (Complete)", title or "Quest", objLabel))
                        end
                    end
                    completedObjectivesCache[key] = true
                else
                    completedObjectivesCache[key] = false
                    -- Count increased (e.g. looting 3/4 Raptor Horns)
                    if wasCount ~= nil and cur > wasCount and not isSuppressed then
                        objectiveJustProgressed = true
                        local sdb = ns.db and ns.db.social
                        if sdb and sdb.announceObjectiveProgress then
                            local objLabel = text or "Objective"
                            if objLabel:find("%d+%s*/%s*%d+") then
                                AnnouncePartyMessage(string.format("[BFQ] %s: %s", title or "Quest", objLabel))
                            else
                                AnnouncePartyMessage(string.format("[BFQ] %s: %s (%d/%d)", title or "Quest", objLabel, cur, maxVal))
                            end
                        end
                    end
                end
            end

            if ns.ReleaseObjectiveObjs and objectives and ns.GetQuestObjectives then
                ns.ReleaseObjectiveObjs(objectives)
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

-- Retrieve detailed party quest status for tooltips and badges
function SocialModule:GetPartyQuestDetails(questID, questLogIndex)
    if not (IsInGroup and (IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 1))) then
        return nil
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

    local numMembers = (GetNumGroupMembers and GetNumGroupMembers()) or (GetNumSubgroupMembers and (GetNumSubgroupMembers() + 1)) or 0
    if numMembers <= 1 then return nil end

    -- Check quest pushability across modern and classic APIs
    local isPushable = false
    if questID and C_QuestLog and C_QuestLog.IsPushableQuest then
        isPushable = C_QuestLog.IsPushableQuest(questID)
    end
    if not isPushable and questLogIndex and GetQuestLogPushable then
        if questID and C_QuestLog and C_QuestLog.SetSelectedQuest then
            C_QuestLog.SetSelectedQuest(questID)
        elseif questLogIndex and SelectQuestLogEntry then
            SelectQuestLogEntry(questLogIndex)
        end
        isPushable = GetQuestLogPushable() and true or false
    end
    if not isPushable and ns.IsQuestPushable then
        isPushable = ns.IsQuestPushable(questID, questLogIndex)
    end

    local onQuest = {}
    local missing = {}
    local isRaid = IsInRaid and IsInRaid()

    for i = 1, numMembers do
        local unit = isRaid and ("raid" .. i) or (i < numMembers and ("party" .. i) or nil)
        if unit and UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local rawName = UnitName(unit)
            if rawName and rawName ~= "" and rawName ~= UNKNOWNOBJECT and rawName ~= "Unknown" then
                local isConnected = UnitIsConnected(unit)
                local isOnQuest = false

                -- 1. Native engine IsUnitOnQuest (Classic/Vanilla)
                if questLogIndex and questLogIndex > 0 and IsUnitOnQuest then
                    local ok, res = pcall(IsUnitOnQuest, questLogIndex, unit)
                    if ok and res then isOnQuest = true end
                end

                -- 2. Modern C_QuestLog.IsUnitOnQuest
                if not isOnQuest and questID and C_QuestLog and C_QuestLog.IsUnitOnQuest then
                    local ok, res = pcall(C_QuestLog.IsUnitOnQuest, questID, unit)
                    if ok and res then isOnQuest = true end
                end

                -- 3. Fallback to Addon Sync / system feedback cache
                if not isOnQuest then
                    local clean = CleanName(rawName)
                    local haveData = (ns.partyQuestData and ns.partyQuestData[questID] and ns.partyQuestData[questID].have) or {}
                    if haveData[clean] then isOnQuest = true end
                end

                -- Class coloring
                local _, classFile = UnitClass(unit)
                local coloredName = rawName
                local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                if color and color.colorStr then
                    coloredName = string_format("|c%s%s|r", color.colorStr, rawName)
                elseif color and color.r then
                    coloredName = string_format("|cff%02x%02x%02x%s|r", math.floor(color.r * 255), math.floor(color.g * 255), math.floor(color.b * 255), rawName)
                end

                local entry = {
                    unit = unit,
                    name = rawName,
                    coloredName = coloredName,
                    class = classFile,
                    isConnected = isConnected,
                    isOnQuest = isOnQuest,
                }

                if isOnQuest then
                    table.insert(onQuest, entry)
                else
                    table.insert(missing, entry)
                end
            end
        end
    end

    return {
        totalGroupMembers = numMembers,
        onQuest = onQuest,
        missing = missing,
        onQuestCount = #onQuest,
        missingCount = #missing,
        isPushable = isPushable,
    }
end

-- Retrieve party progress formatted summary for an objective
function SocialModule:GetObjectivePartyProgress(questID, objIndex)
    return nil
end

-- Check if party members are missing this quest and if it can be shared
function SocialModule:GetMissingPartyInfo(questID, questLogIndex)
    local details = self:GetPartyQuestDetails(questID, questLogIndex)
    if not details then
        return 0, false
    end
    return details.missingCount, details.isPushable
end

function SocialModule:UpdateLootEvents()
    -- Fast Loot is handled by QoLModule
end

function SocialModule:UpdateAutomationEvents()
    -- Quest automation is handled by QuestAutomationModule
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
    eventFrame:RegisterEvent("QUEST_WATCH_UPDATE")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    eventFrame:RegisterEvent("QUEST_REMOVED")
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    eventFrame:RegisterEvent("UI_INFO_MESSAGE")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("GROUP_LEFT")
    self:UpdateAutomationEvents()
    local rosterUpdateTimer = nil

    local lastSharedQuestID = nil
    local lastSharedTime = 0

    eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, ...)
        -- 0. World & Zone Transition Events (Suppress sounds, seed caches, re-sync party)
        if event == "PLAYER_ENTERING_WORLD" then
            soundSuppressedUntil = GetTime() + 2.0
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
            CheckForCompletions()
            return
        end

        local currentDB = (ns.dbObject and ns.dbObject.profile) or ns.db
        local db = (currentDB and currentDB.social) or {}

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

        -- 6. Blizzard System Feedback for Quest Sharing & Objective Updates
        elseif event == "CHAT_MSG_SYSTEM" or event == "UI_INFO_MESSAGE" then
            HandleQuestShareSystemFeedback(arg1)
            if event == "UI_INFO_MESSAGE" then
                CheckForCompletions()
            end

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

if ns.RegisterCallback then
    ns:RegisterCallback("SETTINGS_UPDATED", function()
        SocialModule:UpdateAutomationEvents()
    end)
    ns:RegisterCallback("QUEST_DATA_CHANGED", function()
        CheckForCompletions()
    end)
end