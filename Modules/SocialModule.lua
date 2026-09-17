local addonName, ns = ...

local SocialModule = {}
ns.SocialModule = SocialModule
ns:RegisterModule("SocialModule", SocialModule)

-- Sound effect presets with direct CASC FileDataIDs and SoundKit IDs
local SOUND_PRESETS = {
    peon = { type = "file", id = 558132 },           -- Peon: "Work complete!"
    quest_complete = { type = "file", id = 567400 }, -- Classic Quest Complete Chime
    level_up = { type = "kit", id = 888 },           -- Level Up Fanfare
    raid_warning = { type = "kit", id = 8959 },      -- Raid Warning Chime
    ready_check = { type = "kit", id = 8960 },       -- Ready Check Chime
    map_ping = { type = "kit", id = 3175 },          -- Mini-Map Ping
    pvp_horn = { type = "kit", id = 8456 },          -- PvP Queue Horn
}

function SocialModule:PlaySoundKey(choice)
    local entry = SOUND_PRESETS[choice] or SOUND_PRESETS.peon
    if entry.type == "file" then
        PlaySoundFile(entry.id, "Master")
    elseif entry.type == "kit" then
        PlaySound(entry.id, "Master")
    end
end

function SocialModule:PlayPreviewSound(choice)
    self:PlaySoundKey(choice or (ns.db and ns.db.sound and ns.db.sound.soundChoice) or "peon")
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

-- Track quest and objective completion states so sounds ONLY play on actual completion
local completedQuestsCache = {}
local completedObjectivesCache = {}
local objectiveCountCache = {}
local soundSuppressedUntil = GetTime() + 5.0 -- Mute completion sounds during initial load & zoning
local lastSoundPlayTime = 0

function SocialModule:PlayCompletionSound()
    local now = GetTime()
    if now < soundSuppressedUntil then return end
    if (now - lastSoundPlayTime) < 0.5 then return end
    lastSoundPlayTime = now

    local db = ns.db and ns.db.sound
    if not (db and db.enableCompleteSound) then return end
    self:PlaySoundKey(db.soundChoice or "peon")
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
    local numEntries = (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries())) or 0
    local shouldPlay = false

    for i = 1, numEntries do
        local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
        if not isHeader and questID then
            local isFinished = (isComplete == 1 or isComplete == true)

            -- 1. Full Quest Completion (ready for turn-in)
            local wasQuestComplete = completedQuestsCache[questID]
            if isFinished then
                if wasQuestComplete == false and not isSuppressed then
                    shouldPlay = true
                    AnnouncePartyMessage(string.format("[BFQ] Quest Complete: %s", title or "Quest"))
                end
                completedQuestsCache[questID] = true
            else
                completedQuestsCache[questID] = false
            end

            -- 2. Individual Objective Completion (finished == true)
            local numLeaderBoards = (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i)) or 0
            for j = 1, numLeaderBoards do
                local text, objType, finished = GetQuestLogLeaderBoard(j, i)
                local key = questID .. "_" .. j
                local wasObjFinished = completedObjectivesCache[key]
                local cur, maxVal = 0, 1
                if text then
                    local c, m = text:match("(%d+)%s*/%s*(%d+)")
                    if c and m then
                        cur = tonumber(c) or 0
                        maxVal = tonumber(m) or 1
                    else
                        cur = finished and 1 or 0
                        maxVal = 1
                    end
                end

                local wasCount = objectiveCountCache[key]
                objectiveCountCache[key] = cur

                if finished then
                    if wasObjFinished == false and not isSuppressed then
                        -- Only alert if count actually progressed or this is a single event objective
                        if wasCount == nil or cur > wasCount or maxVal == 1 then
                            shouldPlay = true
                            AnnouncePartyMessage(string.format("[BFQ] Completed: %s", text or "Objective"))
                        end
                    end
                    completedObjectivesCache[key] = true
                else
                    completedObjectivesCache[key] = false
                end
            end
        end
    end

    if not isSuppressed and shouldPlay then
        SocialModule:PlayCompletionSound()
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

-- Broadcast current character's quest progress to the party in compact batches
function SocialModule:BroadcastMyQuests()
    local db = ns.db and ns.db.social
    if not (db and db.enablePartySync) then return end
    if not (IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0)) then return end

    local numEntries = (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries())) or 0
    local haveList = {}
    local progressList = {}

    for i = 1, numEntries do
        local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
        if not isHeader and questID then
            table.insert(haveList, questID)

            local numLeaderBoards = (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i)) or 0
            for j = 1, numLeaderBoards do
                local text, objType, finished = GetQuestLogLeaderBoard(j, i)
                if text then
                    local cur, maxVal = text:match("(%d+)%s*/%s*(%d+)")
                    if not cur or not maxVal then
                        cur = finished and 1 or 0
                        maxVal = 1
                    end
                    table.insert(progressList, string.format("%d:%d:%s:%s:%d", questID, j, cur, maxVal, finished and 1 or 0))
                end
            end
        end
    end

    -- 1. Batch all active quest IDs into compact message(s) (prevents chat flood throttling)
    if #haveList > 0 then
        local chunk = {}
        for _, qid in ipairs(haveList) do
            table.insert(chunk, qid)
            if #chunk >= 25 then
                SendSync("H:" .. table.concat(chunk, ","))
                chunk = {}
            end
        end
        if #chunk > 0 then
            SendSync("H:" .. table.concat(chunk, ","))
        end
    end

    -- 2. Batch objective progress updates (up to 6 per packet)
    if #progressList > 0 then
        local pChunk = {}
        for _, pStr in ipairs(progressList) do
            table.insert(pChunk, pStr)
            if #pChunk >= 6 then
                SendSync("PB:" .. table.concat(pChunk, ";"))
                pChunk = {}
            end
        end
        if #pChunk > 0 then
            SendSync("PB:" .. table.concat(pChunk, ";"))
        end
    end
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

    if questID and C_QuestLog and C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questID) and C_QuestLog.PushQuestToParty then
        C_QuestLog.PushQuestToParty(questID)
        ns.Print("Shared quest with party.")
        return true
    end

    if not questLogIndex or questLogIndex == 0 then
        local numEntries = (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries())) or 0
        for i = 1, numEntries do
            local _, _, _, isH, _, _, _, id = GetQuestLogTitle(i)
            if not isH and id == questID then
                questLogIndex = i
                break
            end
        end
    end

    if questLogIndex and SelectQuestLogEntry and QuestLogPushQuest then
        SelectQuestLogEntry(questLogIndex)
        if (not GetQuestLogPushable) or GetQuestLogPushable() then
            QuestLogPushQuest()
            ns.Print("Shared quest with party.")
            return true
        end
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

-- Retrieve party progress formatted summary for an objective
function SocialModule:GetObjectivePartyProgress(questID, objIndex)
    local qData = ns.partyQuestData and ns.partyQuestData[questID]
    local oData = qData and qData.objectives and qData.objectives[objIndex]
    if not oData then return nil end

    local entries = {}
    local allDone = true
    local count = 0

    for cleanName, prog in pairs(oData) do
        if IsMemberInGroup(cleanName) then
            count = count + 1
            local nameDisplay = prog.displayName or cleanName
            if prog.finished then
                table.insert(entries, string.format("|cff00ff00%s (%d/%d)|r", nameDisplay, prog.max, prog.max))
            else
                allDone = false
                table.insert(entries, string.format("|cff99ccff%s|r (|cffffffff%d/%d|r)", nameDisplay, prog.current, prog.max))
            end
        end
    end

    if count == 0 then return nil end

    if allDone and count > 0 then
        return "|cff00ff00All Party Complete!|r"
    end

    return table.concat(entries, ", ")
end

-- Check if party members are missing this quest and if it can be shared
function SocialModule:GetMissingPartyInfo(questID, questLogIndex)
    if not (IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0)) then
        return 0, false
    end

    local isPushable = false
    if questID and C_QuestLog and C_QuestLog.IsPushableQuest then
        isPushable = C_QuestLog.IsPushableQuest(questID)
    end
    if not isPushable then
        if not questLogIndex or questLogIndex == 0 then
            local numEntries = (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries())) or 0
            for i = 1, numEntries do
                local _, _, _, isH, _, _, _, id = GetQuestLogTitle(i)
                if not isH and id == questID then
                    questLogIndex = i
                    break
                end
            end
        end
        if questLogIndex and GetQuestLogPushable and SelectQuestLogEntry then
            SelectQuestLogEntry(questLogIndex)
            isPushable = GetQuestLogPushable() and true or false
        end
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

--------------------------------------------------------------------------------
-- EVENT INITIALIZATION
--------------------------------------------------------------------------------
function SocialModule:Initialize()
    local eventFrame = CreateFrame("Frame")
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
    eventFrame:RegisterEvent("QUEST_REMOVED")
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    eventFrame:RegisterEvent("UI_INFO_MESSAGE")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("GROUP_LEFT")
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

            if IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
                C_Timer.After(1.5, function()
                    if IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
                        SendSync("REQ")
                        SocialModule:BroadcastMyQuests()
                    end
                end)
                C_Timer.After(3.5, function()
                    if IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
                        SendSync("REQ")
                        SocialModule:BroadcastMyQuests()
                    end
                end)
            else
                if BleakfiberTrackerDB then
                    BleakfiberTrackerDB.partyQuestData = {}
                end
                ns.partyQuestData = (BleakfiberTrackerDB and BleakfiberTrackerDB.partyQuestData) or {}
            end
            return

        elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
            soundSuppressedUntil = GetTime() + 3.5
            CheckForCompletions()

            if IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
                C_Timer.After(1.5, function()
                    if IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
                        SendSync("REQ")
                        SocialModule:BroadcastMyQuests()
                    end
                end)
            end
            return
        end

        local db = ns.db and ns.db.social
        if not db then return end

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

            -- Update quest completion and party broadcast
            C_Timer.After(0.5, function()
                CheckForCompletions()
                SocialModule:BroadcastMyQuests()
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

        -- 5. Completion Sound Alerts & Party Sync Broadcast
        elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_UPDATE" then
            CheckForCompletions()

            local now = GetTime()
            if (now - lastBroadcastTime) > 1.5 then
                lastBroadcastTime = now
                SocialModule:BroadcastMyQuests()
            end

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

        -- 6. Addon Message Communications (Party Quest Sync)
        elseif event == "CHAT_MSG_ADDON" then
            local prefix, msg, channel, sender = arg1, arg2, arg3, arg4
            if prefix == "BFQ_SYNC" and msg and sender then
                local cleanSender = CleanName(sender)
                local cleanPlayer = CleanName(UnitName("player"))
                if cleanSender ~= "" and cleanSender ~= cleanPlayer then
                    local displayName = sender:match("^([^-]+)") or sender
                    displayName = displayName:match("^%s*(.-)%s*$") or displayName

                    if msg:sub(1, 2) == "P:" then
                        -- Single Objective Progress: P:questID:objIndex:cur:max:finished
                        local qID, oIdx, cur, mx, fin = msg:sub(3):match("^(%d+):(%d+):(%d+):(%d+):(%d+)")
                        qID, oIdx = tonumber(qID), tonumber(oIdx)
                        if qID and oIdx then
                            ns.partyQuestData[qID] = ns.partyQuestData[qID] or { objectives = {}, have = {} }
                            ns.partyQuestData[qID].have[cleanSender] = true
                            ns.partyQuestData[qID].objectives[oIdx] = ns.partyQuestData[qID].objectives[oIdx] or {}
                            ns.partyQuestData[qID].objectives[oIdx][cleanSender] = {
                                current = tonumber(cur) or 0,
                                max = tonumber(mx) or 1,
                                finished = (fin == "1"),
                                displayName = displayName,
                            }
                            if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                                ns.StandaloneTracker:UpdateTracker()
                            end
                        end
                    elseif msg:sub(1, 3) == "PB:" then
                        -- Batched Objective Progress: PB:qID:oIdx:cur:mx:fin;qID:oIdx:cur:mx:fin;...
                        local updated = false
                        for item in msg:sub(4):gmatch("([^;]+)") do
                            local qID, oIdx, cur, mx, fin = item:match("^(%d+):(%d+):(%d+):(%d+):(%d+)")
                            qID, oIdx = tonumber(qID), tonumber(oIdx)
                            if qID and oIdx then
                                ns.partyQuestData[qID] = ns.partyQuestData[qID] or { objectives = {}, have = {} }
                                ns.partyQuestData[qID].have[cleanSender] = true
                                ns.partyQuestData[qID].objectives[oIdx] = ns.partyQuestData[qID].objectives[oIdx] or {}
                                ns.partyQuestData[qID].objectives[oIdx][cleanSender] = {
                                    current = tonumber(cur) or 0,
                                    max = tonumber(mx) or 1,
                                    finished = (fin == "1"),
                                    displayName = displayName,
                                }
                                updated = true
                            end
                        end
                        if updated and ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                            ns.StandaloneTracker:UpdateTracker()
                        end
                    elseif msg:sub(1, 2) == "H:" then
                        -- Format: H:qid1,qid2,qid3... or single H:qid
                        local updated = false
                        for qIDStr in msg:sub(3):gmatch("([^,]+)") do
                            local qID = tonumber(qIDStr)
                            if qID then
                                ns.partyQuestData[qID] = ns.partyQuestData[qID] or { objectives = {}, have = {} }
                                ns.partyQuestData[qID].have[cleanSender] = true
                                updated = true
                            end
                        end
                        if updated and ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                            ns.StandaloneTracker:UpdateTracker()
                        end
                    elseif msg == "REQ" then
                        SocialModule:BroadcastMyQuests()
                    end
                end
            end

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
                    if IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
                        SendSync("REQ")
                        SocialModule:BroadcastMyQuests()
                    end
                    if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                        ns.StandaloneTracker:UpdateTracker()
                    end
                end)
            else
                if IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
                    SendSync("REQ")
                    SocialModule:BroadcastMyQuests()
                end
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
