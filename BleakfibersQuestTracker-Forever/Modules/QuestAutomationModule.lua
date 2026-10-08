local addonName, ns = ...

-- Localized Lua & WoW API bindings for performance
local pairs, ipairs, tonumber, select, pcall = pairs, ipairs, tonumber, select, pcall
local C_Timer, CreateFrame = C_Timer, CreateFrame
local IsShiftKeyDown = IsShiftKeyDown
local IsInGroup, GetNumGroupMembers = IsInGroup, GetNumGroupMembers
local AcceptQuest, CompleteQuest, GetQuestReward = AcceptQuest, CompleteQuest, GetQuestReward
local GetNumQuestChoices, SelectAvailableQuest, SelectActiveQuest = GetNumQuestChoices, SelectAvailableQuest, SelectActiveQuest

local QuestAutomationModule = {}
ns.QuestAutomationModule = QuestAutomationModule
ns:RegisterModule("QuestAutomationModule", QuestAutomationModule)

local eventFrame = CreateFrame("Frame")
QuestAutomationModule.eventFrame = eventFrame
QuestAutomationModule.isEnabled = false

local function GetAutomationCfg()
    local db = (ns.db and ns.db.questAutomation) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.questAutomation)
    -- Backward compatibility fallback to db.social
    if not db then
        db = (ns.db and ns.db.social) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.social)
    end
    return db or {}
end

local function IsBypassed()
    local cfg = GetAutomationCfg()
    return (cfg.shiftBypass ~= false and IsShiftKeyDown())
end

-- ===========================================================================
-- Quest Automation Handlers
-- ===========================================================================

local function OnQuestAccepted(questID)
    local cfg = GetAutomationCfg()
    if not cfg.autoShare or IsBypassed() then return end

    local inGroup = IsInGroup and IsInGroup()
    local numMembers = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if not inGroup and numMembers <= 0 then return end

    if C_QuestLog and C_QuestLog.PushQuestToParty and questID then
        C_QuestLog.PushQuestToParty(questID)
    elseif QuestLogPushQuest and GetQuestLogIndexByID and questID then
        local index = GetQuestLogIndexByID(questID)
        if index and index > 0 and SelectQuestLogEntry then
            SelectQuestLogEntry(index)
            QuestLogPushQuest()
        end
    end
end

local function OnQuestDetail()
    local cfg = GetAutomationCfg()
    if IsBypassed() then return end

    local isNPC = not (QuestGetAutoAccept and QuestGetAutoAccept())
    if QuestIsFromAreaTrigger and QuestIsFromAreaTrigger() then
        isNPC = false
    end

    if isNPC and cfg.autoAcceptNPC then
        AcceptQuest()
    elseif (not isNPC) and cfg.autoAcceptShared then
        AcceptQuest()
    end
end

local function OnQuestProgress()
    local cfg = GetAutomationCfg()
    if not cfg.autoTurnIn or IsBypassed() then return end

    if IsQuestCompletable and IsQuestCompletable() then
        CompleteQuest()
    end
end

local function OnQuestComplete()
    local cfg = GetAutomationCfg()
    if not cfg.autoTurnIn or IsBypassed() then return end

    local numChoices = (GetNumQuestChoices and GetNumQuestChoices()) or 0
    if numChoices <= 1 then
        GetQuestReward(1)
    else
        -- Multiple choice rewards: pause for player selection unless choice protection is explicitly disabled
        if cfg.rewardChoiceProtection ~= false then
            -- Pause safely and let player select their gear reward
            return
        else
            GetQuestReward(1)
        end
    end
end

local function OnGossipShow()
    local cfg = GetAutomationCfg()
    if not cfg.autoAcceptNPC or IsBypassed() then return end

    if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        local availableQuests = C_GossipInfo.GetAvailableQuests()
        if availableQuests and #availableQuests == 1 and not availableQuests[1].isTrivial then
            C_GossipInfo.SelectAvailableQuest(availableQuests[1].questID)
        end
    end
end

local function OnQuestGreeting()
    local cfg = GetAutomationCfg()
    if not cfg.autoAcceptNPC or IsBypassed() then return end

    if GetNumAvailableQuests and GetNumAvailableQuests() == 1 then
        SelectAvailableQuest(1)
    end
end

-- ===========================================================================
-- Lifecycle & Event Handlers
-- ===========================================================================

local function OnEvent(self, event, arg1, ...)
    if event == "QUEST_ACCEPTED" then
        OnQuestAccepted(arg1)
    elseif event == "QUEST_DETAIL" then
        OnQuestDetail()
    elseif event == "QUEST_PROGRESS" then
        OnQuestProgress()
    elseif event == "QUEST_COMPLETE" then
        OnQuestComplete()
    elseif event == "GOSSIP_SHOW" then
        OnGossipShow()
    elseif event == "QUEST_GREETING" then
        OnQuestGreeting()
    end
end

function QuestAutomationModule:Enable()
    if self.isEnabled then return end
    self.isEnabled = true

    eventFrame:RegisterEvent("QUEST_ACCEPTED")
    eventFrame:RegisterEvent("QUEST_DETAIL")
    eventFrame:RegisterEvent("QUEST_PROGRESS")
    eventFrame:RegisterEvent("QUEST_COMPLETE")
    eventFrame:RegisterEvent("GOSSIP_SHOW")
    eventFrame:RegisterEvent("QUEST_GREETING")
    eventFrame:SetScript("OnEvent", OnEvent)
end

function QuestAutomationModule:Disable()
    if not self.isEnabled then return end
    self.isEnabled = false

    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
end

function QuestAutomationModule:Initialize()
    if ns.IsModuleEnabled and not ns.IsModuleEnabled("QuestAutomationModule") then
        self:Disable()
        return
    end
    self:Enable()
end
