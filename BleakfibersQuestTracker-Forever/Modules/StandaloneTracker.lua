local addonName, ns = ...

-- Localized Lua & WoW API bindings for performance & garbage reduction
local pairs, ipairs, type, tostring, tonumber, select, pcall = pairs, ipairs, type, tostring, tonumber, select, pcall
local string_format, string_lower, string_find, string_match, string_upper = string.format, string.lower, string.find, string.match, string.upper
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local math_floor, math_ceil, math_max, math_min, math_abs = math.floor, math.ceil, math.max, math.min, math.abs
local wipe = table.wipe or wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local GetTime = GetTime
local C_QuestLog = C_QuestLog
local C_SuperTrack = C_SuperTrack
local C_Item = C_Item
local C_Container = C_Container
local GetNumQuestLogEntries = GetNumQuestLogEntries
local GetQuestLogTitle = GetQuestLogTitle
local GetQuestDifficultyColor = GetQuestDifficultyColor
local GetQuestLogLeaderBoard = GetQuestLogLeaderBoard
local GetNumQuestLeaderBoards = GetNumQuestLeaderBoards
local SelectQuestLogEntry = SelectQuestLogEntry
local AbandonQuest = AbandonQuest
local SetAbandonQuest = SetAbandonQuest
local RemoveQuestWatch = RemoveQuestWatch
local GetRealZoneText = GetRealZoneText
local GetZoneText = GetZoneText
local GetSubZoneText = GetSubZoneText
local IsInInstance = IsInInstance
local GetInstanceInfo = GetInstanceInfo
local GetItemInfoInstant = function(item)
    if not item then return nil end
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(item)
    elseif _G.GetItemInfoInstant then
        return _G.GetItemInfoInstant(item)
    end
    return nil
end
local GetItemInfo = function(item)
    if not item then return nil end
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    elseif _G.GetItemInfo then
        return _G.GetItemInfo(item)
    end
    return nil
end
local IsQuestWatched = IsQuestWatched
local GetQuestTagInfo = GetQuestTagInfo

local StandaloneTracker = {}
ns.StandaloneTracker = StandaloneTracker
ns:RegisterModule("StandaloneTracker", StandaloneTracker)

-- Frame & FontString Pools
local questBlocks = {}
local objectiveStrings = {}
local itemButtons = {}
local partyStrings = {}
local shareButtons = {}
local zoneHeaders = {}

-- Static Data Recycling Pools (Zero-Garbage Collection)
local questEntryPool = {}
local cachedTrackedQuests = {}
local zoneMap = {}
local zoneOrder = {}
local initialOrder = {}
local zoneListPool = {}

local function AcquireQuestEntry()
    local entry = table_remove(questEntryPool)
    if not entry then
        entry = { objectives = {} }
    else
        local objs = entry.objectives
        wipe(entry)
        if objs then
            wipe(objs)
            entry.objectives = objs
        else
            entry.objectives = {}
        end
    end
    return entry
end

local function ReleaseQuestEntries(list)
    if not list then return end
    for i = 1, #list do
        local entry = list[i]
        if entry then
            if entry.objectives and ns.ReleaseObjectiveObjs then
                ns.ReleaseObjectiveObjs(entry.objectives)
            end
            table_insert(questEntryPool, entry)
            list[i] = nil
        end
    end
end

local function CleanOutline(outline)
    if not outline or outline == "" or outline == "NONE" or outline == "nil" then
        return nil
    end
    local u = string.upper(tostring(outline))
    if u == "NONE" or u == "" then
        return nil
    end
    return outline
end

local function SafeSetFont(fs, fontPath, fontSize, outline, enableShadow)
    if not fs or not fontPath then return end
    fontSize = tonumber(fontSize) or 11
    local clean = CleanOutline(outline)
    if clean then
        fs:SetFont(fontPath, fontSize, clean)
    else
        fs:SetFont(fontPath, fontSize)
    end
    if enableShadow == nil then
        enableShadow = not (ns.db and ns.db.fonts and ns.db.fonts.enableTextShadow == false)
    end
    if enableShadow then
        fs:SetShadowColor(0, 0, 0, 0.85)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- Context Menu Frame for Quest Actions
local questContextMenu = CreateFrame("Frame", "BleakfiberQuestContextMenu", UIParent, "UIDropDownMenuTemplate")

-- Custom Abandon Confirmation Dialog (bypasses Blizzard popup taint and ensures clean programmatic abandon)
StaticPopupDialogs["BFQ_CONFIRM_ABANDON_QUEST"] = {
    text = "Are you sure you want to abandon '%s'?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        if not data then return end
        local questID = data.questID
        local logIndex = data.questLogIndex

        if not questID and logIndex and C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then
            questID = C_QuestLog.GetQuestIDForLogIndex(logIndex)
        end

        if questID and C_QuestLog and C_QuestLog.SetSelectedQuest then
            C_QuestLog.SetSelectedQuest(questID)
        elseif logIndex and SelectQuestLogEntry then
            SelectQuestLogEntry(logIndex)
        end

        if C_QuestLog and C_QuestLog.SetAbandonQuest then
            C_QuestLog.SetAbandonQuest()
        elseif SetAbandonQuest then
            SetAbandonQuest()
        end

        if C_QuestLog and C_QuestLog.AbandonQuest then
            C_QuestLog.AbandonQuest()
        elseif AbandonQuest then
            AbandonQuest()
        end

        if StandaloneTracker and StandaloneTracker.UpdateTracker then
            C_Timer.After(0.2, function()
                StandaloneTracker:UpdateTracker()
            end)
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

-- Helper: Permanently and safely suppress Default Blizzard Quest Watch / Objective Tracker Frames
local function HideBlizzardTrackerFrame(f)
    if not f then return end
    if not InCombatLockdown() then
        f:Hide()
    end
    f:SetAlpha(0)
    if not f._bfqHooked then
        f._bfqHooked = true
        f:HookScript("OnShow", function(self)
            if not InCombatLockdown() then
                self:Hide()
            end
            self:SetAlpha(0)
        end)
    end
end

local function HookBlizzardTracker()
    HideBlizzardTrackerFrame(_G.QuestWatchFrame)
    HideBlizzardTrackerFrame(_G.ObjectiveTrackerFrame)
    HideBlizzardTrackerFrame(_G.ObjectiveTrackerBlocksFrame)
end
ns.HookBlizzardTracker = HookBlizzardTracker

-- Helper: Format Quest Title with Level, Difficulty Color and Badges
local function GetFormattedQuestTitle(questInfo)
    local level = tonumber(questInfo.level) or 0
    local title = questInfo.title or "Unknown Quest"
    local db = ns.db
    local useDifficultyColor = not (db and db.fonts and db.fonts.colorDifficulty == false)
    
    local hexColor = ""
    if useDifficultyColor then
        local color = (ns.GetDifficultyColor and ns.GetDifficultyColor(level))
            or (level > 0 and GetQuestDifficultyColor and GetQuestDifficultyColor(level))
            or { r = 1, g = 1, b = 1 }
        hexColor = string.format("|cff%02x%02x%02x", math.floor((color.r or 1) * 255), math.floor((color.g or 1) * 255), math.floor((color.b or 1) * 255))
    end

    -- Elite / Group / Dungeon / Raid Badges
    local badge = ""
    local showBadges = not (db and db.sorting and db.sorting.showGroupTags == false)
    if showBadges then
        if questInfo.isDungeon then
            badge = "D"
        elseif questInfo.isRaid then
            badge = "R"
        elseif questInfo.isElite then
            badge = "+"
        else
            local numGroup = tonumber(questInfo.suggestedGroup)
            if numGroup and numGroup > 1 then
                badge = "+" .. numGroup
            elseif type(questInfo.suggestedGroup) == "string" then
                local sgLower = questInfo.suggestedGroup:lower()
                if sgLower:find("dungeon") or sgLower == "d" then
                    badge = "D"
                elseif sgLower:find("raid") or sgLower == "r" then
                    badge = "R"
                elseif sgLower:find("elite") or sgLower == "+" then
                    badge = "+"
                end
            end
        end
    end

    local tag = ""
    local freq = tonumber(questInfo.frequency)
    if freq and freq > 1 then
        tag = " |cff00ccff[Daily]|r"
    end

    local showPartyBadge = db and db.tooltips and db.tooltips.showPartyBadge
    if showPartyBadge and ns.SocialModule and ns.SocialModule.GetPartyQuestDetails then
        local partyDetails = ns.SocialModule:GetPartyQuestDetails(questInfo.questID, questInfo.questLogIndex)
        if partyDetails and partyDetails.onQuestCount > 0 then
            tag = tag .. string.format(" |cff00e5ff[👥%d]|r", partyDetails.onQuestCount)
        end
    end
    
    local activeMarker = ""
    if ns.activeQuestID and questInfo.questID == ns.activeQuestID then
        local isWayfinderActive = (not ns.IsModuleEnabled or ns.IsModuleEnabled("wayfinder"))
        local showInline = isWayfinderActive and ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow
        local arrowPos = (ns.db and ns.db.wayfinder and ns.db.wayfinder.inlineArrowPosition) or "left"
        if not (showInline and arrowPos == "left") then
            local iconChoice = (ns.db and ns.db.activeQuestIcon) or "star"
            if iconChoice == "star" then
                activeMarker = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:13:13:0:0|t "
            elseif iconChoice == "arrow" then
                activeMarker = "|TInterface\\Buttons\\UI-SpellbookIcon-NextPage-Up:13:13:0:0|t "
            elseif iconChoice == "blizz" then
                activeMarker = "|TInterface\\GossipFrame\\AvailableQuestIcon:13:13:0:0|t "
            elseif iconChoice == "pointer" then
                activeMarker = "|cff00e5ff► |r"
            elseif iconChoice == "none" then
                activeMarker = ""
            else
                activeMarker = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:13:13:0:0|t "
            end
        end
    end

    -- Blizzard ? Icon for Completed Quests
    local completeMarker = ""
    local showCompleteIcon = not (db and db.headers and db.headers.showCompleteIcon == false)
    if showCompleteIcon and questInfo.isComplete and not questInfo.isFailed then
        local iconSize = math.max(12, StandaloneTracker.titleSize or 13)
        completeMarker = string.format("|TInterface\\GossipFrame\\ActiveQuestIcon:%d:%d:0:0|t ", iconSize, iconSize)
    end

    local levelPrefix = ""
    if level > 0 then
        levelPrefix = string.format("[%d%s] ", level, badge)
    elseif badge ~= "" then
        levelPrefix = string.format("[%s] ", badge)
    end

    if questInfo.isFailed then
        tag = tag .. " |cffff2020[FAILED]|r"
        return string.format("%s%s|cffff2020%s%s%s|r", activeMarker, completeMarker, levelPrefix, title, tag)
    elseif useDifficultyColor and hexColor ~= "" then
        return string.format("%s%s%s%s%s|r%s", activeMarker, completeMarker, hexColor, levelPrefix, title, tag)
    else
        return string.format("%s%s%s%s%s", activeMarker, completeMarker, levelPrefix, title, tag)
    end
end

-- Acquire or create a quest objective FontString
local function AcquireObjectiveString(parent)
    local fs
    for _, str in ipairs(objectiveStrings) do
        if not str:IsShown() then
            fs = str
            fs:SetParent(parent)
            fs:Show()
            break
        end
    end
    local font = StandaloneTracker.objectiveFontPath or StandaloneTracker.fontPath
    local size = StandaloneTracker.objSize or 11
    local outline = StandaloneTracker.objOutline
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        SafeSetFont(fs, font, size, outline)
        table.insert(objectiveStrings, fs)
    else
        SafeSetFont(fs, font, size, outline)
    end
    return fs
end

-- Acquire or create a Party Progress FontString
local function AcquirePartyString(parent)
    local fs
    for _, str in ipairs(partyStrings) do
        if not str:IsShown() then
            fs = str
            fs:SetParent(parent)
            fs:Show()
            break
        end
    end
    local font = StandaloneTracker.objectiveFontPath or StandaloneTracker.fontPath
    local size = math.max(9, (StandaloneTracker.objSize or 11) - 1)
    local outline = StandaloneTracker.objOutline
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        SafeSetFont(fs, font, size, outline)
        table.insert(partyStrings, fs)
    else
        SafeSetFont(fs, font, size, outline)
    end
    return fs
end

-- Acquire or create an interactive Click-to-Share Button
local function AcquireShareButton(parent)
    local btn
    for _, b in ipairs(shareButtons) do
        if not b:IsShown() then
            btn = b
            btn:SetParent(parent)
            btn:Show()
            break
        end
    end
    local font = StandaloneTracker.objectiveFontPath or StandaloneTracker.fontPath
    local size = math.max(9, (StandaloneTracker.objSize or 11) - 1)
    local outline = StandaloneTracker.objOutline
    if not btn then
        btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(14)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("LEFT", btn, "LEFT", 0, 0)
        btn.text:SetJustifyH("LEFT")
        SafeSetFont(btn.text, font, size, outline)
        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints(btn)
        btn.highlight:SetColorTexture(0, 0.75, 1, 0.12)
        btn:SetScript("OnEnter", function(self)
            if not self:IsEnabled() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Party Quest Share", 0, 0.8, 1)
            GameTooltip:AddLine("Click to share this quest with your party.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(shareButtons, btn)
    else
        btn:Enable()
        SafeSetFont(btn.text, font, size, outline)
    end
    return btn
end

-- Set or change the Active Quest (syncs with Blizzard SuperTrack if available)
function StandaloneTracker:SetActiveQuest(questID)
    if not questID or questID == 0 then
        ns.activeQuestID = nil
        ns.waypointExplicitlyCleared = true
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(0)
        end
        if ns.WayfinderModule and ns.WayfinderModule.ClearWaypoint then
            if not (ns.WayfinderModule.IsCustomTarget and ns.WayfinderModule:IsCustomTarget()) then
                ns.WayfinderModule:ClearWaypoint(true)
            end
        end
        if ns.DataBarsModule and ns.DataBarsModule.UpdateTimerBar then
            ns.DataBarsModule:UpdateTimerBar()
        end
        self:UpdateTracker()
        return
    end

    ns.waypointExplicitlyCleared = false
    ns.activeQuestID = questID
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        C_SuperTrack.SetSuperTrackedQuestID(questID)
    end
    if ns.WayfinderModule and ns.WayfinderModule.SetQuestTarget then
        ns.WayfinderModule:SetQuestTarget(questID, true, true)
    end
    if ns.DataBarsModule and ns.DataBarsModule.UpdateTimerBar then
        ns.DataBarsModule:UpdateTimerBar()
    end
    self:UpdateTracker()
end

-- Get or Create the Dedicated Quest Item Button Frame (pooled BleakfiberQuestItemButton1..N)
function StandaloneTracker:GetOrCreateItemButton(index)
    index = index or 1
    self.itemButtons = self.itemButtons or {}
    if self.itemButtons[index] then return self.itemButtons[index] end

    if InCombatLockdown and InCombatLockdown() then
        self.pendingItemUpdate = true
        return nil
    end

    local frameName = (index == 1) and "BleakfiberQuestItemButton1" or ("BleakfiberQuestItemButton" .. index)
    local btn = CreateFrame("Button", frameName, UIParent, (BackdropTemplateMixin and "SecureActionButtonTemplate, BackdropTemplate") or "SecureActionButtonTemplate")
    if index == 1 then
        _G["BleakfiberQuestItemFrame"] = btn
        self.itemButton = btn
    end
    btn.buttonIndex = index
    btn:SetSize(26, 26)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(12)
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)

    -- Clean Modern Backdrop & Border
    if btn.SetBackdrop then
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        btn:SetBackdropColor(0, 0, 0, 0.85)
        btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1.0)
    end

    -- Item Icon
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Cooldown Spiral
    btn.cooldown = CreateFrame("Cooldown", frameName .. "Cooldown", btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints(btn.icon)

    -- Stack / Item Count
    btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)

    -- Highlight Texture
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn.icon)
    hl:SetColorTexture(1, 1, 1, 0.25)
    btn:SetHighlightTexture(hl)

    -- Secure Action Setup
    btn:RegisterForClicks("AnyUp", "AnyDown")

    -- Tooltips
    btn:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        if s.itemLink and type(s.itemLink) == "string" and s.itemLink:find("|Hitem:") then
            GameTooltip:SetHyperlink(s.itemLink)
        else
            GameTooltip:AddLine("Quest Item", 1, 0.82, 0)
            if s.questTitle then
                GameTooltip:AddLine(s.questTitle, 1, 1, 1)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Left-Click: Use quest item|r", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffaaaaaaShift + Right-Drag: Move button|r", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("|cffaaaaaaAlt + Right-Click: Re-dock to tracker|r", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Free Repositioning via Shift + Right Drag (doesn't interfere with secure Left-Click)
    btn:RegisterForDrag("RightButton")
    btn:SetScript("OnDragStart", function(s)
        if InCombatLockdown() then return end
        if IsShiftKeyDown() then
            s.isMoving = true
            s:StartMoving()
        end
    end)
    btn:SetScript("OnDragStop", function(s)
        if s.isMoving then
            s.isMoving = false
            s:StopMovingOrSizing()
            local point, _, relPoint, x, y = s:GetPoint()
            if ns.db then
                ns.db.itemButtonPosition = {
                    point = point or "TOPLEFT",
                    relativePoint = relPoint or "TOPLEFT",
                    x = math.floor((x or 0) + 0.5),
                    y = math.floor((y or 0) + 0.5),
                }
            end
            if ns.FlushDBToGlobals then
                ns.FlushDBToGlobals()
            end
            ns.Print("|cff00c0ffQuest item button position saved.|r Hold Alt + Right-Click to re-dock.")
        end
    end)

    -- Alt + Right-Click to reset docking
    btn:HookScript("OnMouseDown", function(s, mouseButton)
        if mouseButton == "RightButton" and IsAltKeyDown() then
            if ns.db then
                ns.db.itemButtonPosition = nil
            end
            if ns.FlushDBToGlobals then
                ns.FlushDBToGlobals()
            end
            ns.Print("|cff00c0ffQuest item button re-docked to quest tracker.|r")
            StandaloneTracker:UpdateItemButton()
        end
    end)

    btn:Hide()
    self.itemButtons[index] = btn
    return btn
end

-- Update Dedicated Quest Item Button Frame(s) for All Tracked Quests with Items
function StandaloneTracker:UpdateItemButton(trackedQuests)
    if not trackedQuests then
        if cachedTrackedQuests and #cachedTrackedQuests > 0 then
            trackedQuests = cachedTrackedQuests
        else
            trackedQuests = self:GetTrackedQuests()
        end
    end

    local isCollapsed = ns.Tracker and ns.Tracker.isCollapsed
    local isCombatHidden = ns.db and ns.db.filtering and ns.db.filtering.hideInCombat and (self.inCombat or (InCombatLockdown and InCombatLockdown()))

    if isCollapsed or isCombatHidden then
        if self.itemButtons then
            for _, btn in ipairs(self.itemButtons) do
                btn.parentBlock = nil
                btn.questID = nil
                if not InCombatLockdown() then
                    btn:Hide()
                else
                    btn:SetAlpha(0)
                    self.pendingItemUpdate = true
                end
            end
        end
        return
    end

    -- 1. Identify all quests with items (prioritize active/supertracked quest first)
    local itemQuests = {}
    local activeQ = nil
    local activeID = ns.activeQuestID
    if not activeID and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local stID = C_SuperTrack.GetSuperTrackedQuestID()
        if stID and stID > 0 then activeID = stID end
    end

    if activeID then
        for _, q in ipairs(trackedQuests) do
            if q.questID == activeID and q.itemTexture then
                activeQ = q
                table_insert(itemQuests, q)
                break
            end
        end
    end
    for _, q in ipairs(trackedQuests) do
        if q.itemTexture and q ~= activeQ then
            table_insert(itemQuests, q)
        end
    end

    if #itemQuests == 0 then
        if self.itemButtons then
            for _, btn in ipairs(self.itemButtons) do
                btn.parentBlock = nil
                btn.questID = nil
                if not InCombatLockdown() then
                    btn:Hide()
                else
                    btn:SetAlpha(0)
                    self.pendingItemUpdate = true
                end
            end
        end
        return
    end

    local placement = (ns.db and ns.db.itemButtonPlacement) or "inside_right"
    if placement ~= "outside_left" and placement ~= "inside_right" then
        placement = "inside_right"
    end
    local customPos = ns.db and ns.db.itemButtonPosition
    local tracker = ns.Tracker and ns.Tracker.frame
    local header = tracker and tracker.header
    local sf = ns.Tracker and ns.Tracker.scrollFrame
    local topBound = (header and header:IsVisible() and header:GetBottom()) or (sf and sf:IsVisible() and sf:GetTop())
    local bottomBound = (tracker and tracker:IsVisible() and tracker:GetBottom()) or (sf and sf:IsVisible() and sf:GetBottom())

    -- 2. Update button for each item quest
    for i, q in ipairs(itemQuests) do
        local btn = self:GetOrCreateItemButton(i)
        if not btn then
            self.pendingItemUpdate = true
            break
        end

        -- Item button should only be shown when the parent quest is actively rendered and visible inside the tracker
        local block = self.activeBlocks and q.questID and self.activeBlocks[q.questID]
        btn.parentBlock = block
        btn.questID = q.questID

        local isWithinScroll = true
        if not customPos and tracker and tracker:IsVisible() and topBound and bottomBound and block and block.header then
            local hTop = block.header:GetTop()
            local hBottom = block.header:GetBottom()
            if hTop and hBottom then
                local center = (hTop + hBottom) / 2
                local halfHeight = (btn:GetHeight() or 26) / 2
                local btnTop = center + halfHeight
                local btnBottom = center - halfHeight
                if (btnTop > topBound + 2) or (btnBottom < bottomBound - 2) then
                    isWithinScroll = false
                end
            end
        end

        local isQuestVisible = (block and block.header and block:IsVisible() and tracker and tracker:IsVisible() and isWithinScroll)

        -- Visuals
        btn.icon:SetTexture(q.itemTexture)
        local count = tonumber(q.numItems) or 0
        btn.count:SetText(count > 1 and tostring(count) or "")
        btn.itemLink = q.itemLink
        btn.itemID = q.itemID
        btn.questTitle = q.title

        -- Cooldown
        if btn.cooldown and q.itemID then
            local start, duration, enable = 0, 0, 0
            if C_Item and C_Item.GetItemCooldown then
                start, duration, enable = C_Item.GetItemCooldown(q.itemID)
            elseif C_Container and C_Container.GetItemCooldown then
                start, duration, enable = C_Container.GetItemCooldown(q.itemID)
            elseif GetItemCooldown then
                start, duration, enable = GetItemCooldown(q.itemID)
            end
            if start and duration and duration > 0 then
                btn.cooldown:SetCooldown(start, duration)
                btn.cooldown:Show()
            else
                btn.cooldown:Hide()
            end
        elseif btn.cooldown then
            btn.cooldown:Hide()
        end

        -- Secure attributes and positioning
        if InCombatLockdown() then
            self.pendingItemUpdate = true
            if not isQuestVisible then
                btn:SetAlpha(0)
            else
                if btn:IsShown() then
                    btn:SetAlpha(1)
                end
            end
        else
            local itemAttr = q.itemLink or (q.itemID and ("item:" .. q.itemID)) or q.itemTexture
            btn:SetAttribute("type", "item")
            btn:SetAttribute("item", itemAttr)

            if block and block.header then
                btn:ClearAllPoints()
                if customPos and i == 1 then
                    btn:SetPoint(customPos.point or "TOPLEFT", UIParent, customPos.relativePoint or "TOPLEFT", customPos.x or 0, customPos.y or 0)
                elseif customPos and i > 1 then
                    local prevVisibleBtn = nil
                    for p = i - 1, 1, -1 do
                        if self.itemButtons[p] and self.itemButtons[p]:IsShown() then
                            prevVisibleBtn = self.itemButtons[p]
                            break
                        end
                    end
                    if prevVisibleBtn then
                        btn:SetPoint("TOP", prevVisibleBtn, "BOTTOM", 0, -4)
                    else
                        btn:SetPoint(customPos.point or "TOPLEFT", UIParent, customPos.relativePoint or "TOPLEFT", customPos.x or 0, customPos.y or 0)
                    end
                else
                    if placement == "outside_left" then
                        btn:SetPoint("RIGHT", block.header, "LEFT", -6, 0)
                    else -- "inside_right"
                        btn:SetPoint("RIGHT", block.header, "RIGHT", -4, 0)
                    end
                end
            end

            if isQuestVisible then
                btn:SetAlpha(1)
                btn:Show()
            else
                btn:Hide()
            end
        end
    end

    -- Hide any extra unused buttons
    if self.itemButtons then
        for j = #itemQuests + 1, #self.itemButtons do
            local extraBtn = self.itemButtons[j]
            extraBtn.parentBlock = nil
            extraBtn.questID = nil
            if not InCombatLockdown() then
                extraBtn:Hide()
            else
                extraBtn:SetAlpha(0)
                self.pendingItemUpdate = true
            end
        end
    end
end

-- Lightweight Cooldown-Only Updater (Safe to execute during combat lockdown)
function StandaloneTracker:UpdateItemButtonCooldowns()
    if not self.itemButtons then return end
    for _, btn in ipairs(self.itemButtons) do
        if btn:IsShown() and btn.cooldown and btn.itemID then
            local start, duration, enable = 0, 0, 0
            if C_Item and C_Item.GetItemCooldown then
                start, duration, enable = C_Item.GetItemCooldown(btn.itemID)
            elseif C_Container and C_Container.GetItemCooldown then
                start, duration, enable = C_Container.GetItemCooldown(btn.itemID)
            elseif GetItemCooldown then
                start, duration, enable = GetItemCooldown(btn.itemID)
            end
            if start and duration and duration > 0 then
                btn.cooldown:SetCooldown(start, duration)
                btn.cooldown:Show()
            else
                btn.cooldown:Hide()
            end
        end
    end
end

-- Lightweight scroll-culler to hide/show item buttons when scrolled out of tracker bounds
function StandaloneTracker:UpdateItemButtonVisibility()
    if not self.itemButtons or #self.itemButtons == 0 then return end
    local customPos = ns.db and ns.db.itemButtonPosition
    if customPos then return end

    local tracker = ns.Tracker and ns.Tracker.frame
    local header = tracker and tracker.header
    local sf = ns.Tracker and ns.Tracker.scrollFrame
    local isCollapsed = ns.Tracker and ns.Tracker.isCollapsed
    local isCombatHidden = ns.db and ns.db.filtering and ns.db.filtering.hideInCombat and (self.inCombat or (InCombatLockdown and InCombatLockdown()))

    local trackerVisible = tracker and tracker:IsVisible() and not isCollapsed and not isCombatHidden
    local topBound = (header and header:IsVisible() and header:GetBottom()) or (sf and sf:IsVisible() and sf:GetTop())
    local bottomBound = (tracker and tracker:IsVisible() and tracker:GetBottom()) or (sf and sf:IsVisible() and sf:GetBottom())
    local inCombat = InCombatLockdown and InCombatLockdown()

    for _, btn in ipairs(self.itemButtons) do
        if btn.questID and btn.parentBlock and btn.parentBlock.header then
            local block = btn.parentBlock
            local isVisible = false
            if trackerVisible and block:IsVisible() and topBound and bottomBound then
                local hTop = block.header:GetTop()
                local hBottom = block.header:GetBottom()
                if hTop and hBottom then
                    local center = (hTop + hBottom) / 2
                    local halfHeight = ((btn:GetHeight() or 26) / 2)
                    local btnTop = center + halfHeight
                    local btnBottom = center - halfHeight
                    if (btnTop <= topBound + 2) and (btnBottom >= bottomBound - 2) then
                        isVisible = true
                    end
                end
            end

            if not isVisible then
                if not inCombat then
                    btn:Hide()
                else
                    btn:SetAlpha(0)
                    self.pendingItemUpdate = true
                end
            else
                if not inCombat then
                    btn:SetAlpha(1)
                    btn:Show()
                else
                    if btn:IsShown() then
                        btn:SetAlpha(1)
                    else
                        self.pendingItemUpdate = true
                    end
                end
            end
        end
    end
end

-- Acquire or create a Collapsible Zone Header Button
local function AcquireZoneHeader(parent)
    local btn
    for _, b in ipairs(zoneHeaders) do
        if not b:IsShown() then
            btn = b
            btn:SetParent(parent)
            btn:Show()
            break
        end
    end
    if not btn then
        btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(22)
        
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints(btn)
        
        btn.collapseText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.collapseText:SetPoint("LEFT", btn, "LEFT", 4, 0)
        btn.collapseText:SetWidth(20)
        btn.collapseText:SetJustifyH("CENTER")
        btn.collapseText:SetJustifyV("MIDDLE")
        btn.collapseText:SetWordWrap(false)

        btn.title = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.title:SetPoint("LEFT", btn.collapseText, "RIGHT", 4, 0)
        btn.title:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        btn.title:SetJustifyH("LEFT")
        btn.title:SetJustifyV("MIDDLE")
        btn.title:SetWordWrap(true)

        btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.count:Hide()

        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints(btn)
        btn.highlight:SetColorTexture(1, 1, 1, 0.08)

        local fPath = StandaloneTracker.headerFontPath or StandaloneTracker.fontPath
        local zSize = StandaloneTracker.zoneHeaderSize or math.max(10, (StandaloneTracker.titleSize or 13) - 1)
        local outline = StandaloneTracker.titleOutline
        local shadow = StandaloneTracker.enableShadow
        SafeSetFont(btn.title, fPath, zSize, outline, shadow)
        SafeSetFont(btn.collapseText, fPath, math.min(13, math.max(10, zSize - 1)), outline, shadow)

        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function(self)
            self.wasDragged = true
            if ns.Tracker and ns.Tracker.StartDragging then
                ns.Tracker.StartDragging()
            end
        end)
        btn:SetScript("OnDragStop", function(self)
            if ns.Tracker and ns.Tracker.StopDragging then
                ns.Tracker.StopDragging()
            end
            C_Timer.After(0.1, function()
                self.wasDragged = false
            end)
        end)

        btn:SetScript("OnClick", function(self)
            if self.wasDragged or (ns.Tracker and ns.Tracker.frame and ns.Tracker.frame.isMoving) then return end
            if not self.zoneName then return end
            if not ns.db then return end
            ns.db.collapsedZones = ns.db.collapsedZones or {}
            ns.db.collapsedZones[self.zoneName] = not ns.db.collapsedZones[self.zoneName]
            if ns.FlushDBToGlobals then
                ns.FlushDBToGlobals()
            end
            StandaloneTracker:UpdateTracker()
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.zoneName or "Zone", 1, 0.82, 0)
            local isCollapsed = ns.db and ns.db.collapsedZones and ns.db.collapsedZones[self.zoneName]
            GameTooltip:AddLine(isCollapsed and "Click to expand zone quests" or "Click to collapse zone quests", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        table.insert(zoneHeaders, btn)
    else
        local fPath = StandaloneTracker.headerFontPath or StandaloneTracker.fontPath
        local zSize = StandaloneTracker.zoneHeaderSize or math.max(10, (StandaloneTracker.titleSize or 13) - 1)
        local outline = StandaloneTracker.titleOutline
        local shadow = StandaloneTracker.enableShadow
        SafeSetFont(btn.title, fPath, zSize, outline, shadow)
        SafeSetFont(btn.collapseText, fPath, math.min(13, math.max(10, zSize - 1)), outline, shadow)
        SafeSetFont(btn.count, fPath, math.max(9, zSize - 2), outline, shadow)
    end
    return btn
end


-- Open rich dropdown context menu for a quest
function StandaloneTracker:OpenQuestContextMenu(anchor, qInfo)
    if not qInfo then return end

    local isCurActive = (qInfo.questID and ns.activeQuestID == qInfo.questID)

    local menu = {
        { text = "|cff00c0ff" .. (qInfo.title or "Quest Actions") .. "|r", isTitle = true, notCheckable = true },
        {
            text = isCurActive and "|cffff6666Clear Active Quest Navigation|r" or "|cff00c0ffSet as Active Quest|r",
            notCheckable = false,
            checked = isCurActive,
            func = function()
                if isCurActive then
                    StandaloneTracker:SetActiveQuest(nil)
                else
                    StandaloneTracker:SetActiveQuest(qInfo.questID)
                end
            end,
        },
        {
            text = "Copy Wowhead URL",
            notCheckable = true,
            func = function()
                if qInfo.questID and ns.Config and ns.Config.ShowCopyDialog then
                    local url = string.format("https://www.wowhead.com/forever/quest=%d", qInfo.questID)
                    ns.Config:ShowCopyDialog(url, qInfo.title)
                end
            end,
        },
        {
            text = "Show in Quest Log",
            notCheckable = true,
            func = function()
                if InCombatLockdown and InCombatLockdown() then
                    if UIErrorsFrame and UIErrorsFrame.AddMessage then
                        UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "Cannot open quest log in combat", 1.0, 0.1, 0.1, 1.0)
                    end
                    return
                end
                if qInfo.questID and QuestMapFrame_OpenToQuestDetails then
                    if securecallfunction then
                        securecallfunction(QuestMapFrame_OpenToQuestDetails, qInfo.questID)
                    else
                        QuestMapFrame_OpenToQuestDetails(qInfo.questID)
                    end
                elseif qInfo.questLogIndex and QuestLogFrame and SelectQuestLogEntry then
                    ShowUIPanel(QuestLogFrame)
                    SelectQuestLogEntry(qInfo.questLogIndex)
                    if QuestLog_Update then QuestLog_Update() end
                end
            end,
        },
        {
            text = "Share Quest to Party",
            notCheckable = true,
            disabled = not (IsInGroup and (IsInGroup() or (GetNumGroupMembers and GetNumGroupMembers() > 0))),
            func = function()
                if ns.SocialModule and ns.SocialModule.ShareQuest then
                    ns.SocialModule:ShareQuest(qInfo.questID, qInfo.questLogIndex)
                end
            end,
        },
        {
            text = "Set Wayfinder Arrow",
            notCheckable = true,
            func = function()
                if ns.WayfinderModule and qInfo.questID then
                    ns.WayfinderModule:SetQuestTarget(qInfo.questID, false, true)
                end
            end,
        },
        {
            text = (qInfo.questID and ns.db and ns.db.filtering and ns.db.filtering.untrackedQuests and ns.db.filtering.untrackedQuests[qInfo.questID]) and "Track Quest" or "Untrack Quest",
            notCheckable = true,
            func = function()
                local qID = qInfo.questID
                local logIdx = qInfo.questLogIndex
                local isUntracked = qID and ns.db and ns.db.filtering and ns.db.filtering.untrackedQuests and ns.db.filtering.untrackedQuests[qID]

                if isUntracked then
                    if ns.db and ns.db.filtering and ns.db.filtering.untrackedQuests then
                        ns.db.filtering.untrackedQuests[qID] = nil
                    end
                    if qID and C_QuestLog and C_QuestLog.AddQuestWatch then
                        C_QuestLog.AddQuestWatch(qID)
                    elseif logIdx and AddQuestWatch then
                        AddQuestWatch(logIdx)
                    end
                else
                    if ns.db and ns.db.filtering then
                        ns.db.filtering.untrackedQuests = ns.db.filtering.untrackedQuests or {}
                        if qID then
                            ns.db.filtering.untrackedQuests[qID] = true
                        end
                    end
                    if qID and C_QuestLog and C_QuestLog.RemoveQuestWatch then
                        C_QuestLog.RemoveQuestWatch(qID)
                    elseif logIdx and RemoveQuestWatch then
                        RemoveQuestWatch(logIdx)
                    end
                    if QuestWatch_Update then QuestWatch_Update() end
                end

                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                StandaloneTracker:UpdateTracker()
            end,
        },
        {
            text = "|cffff4444Abandon Quest|r",
            notCheckable = true,
            func = function()
                local questID = qInfo.questID
                local title = qInfo.title or (questID and C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)) or "Quest"

                StaticPopup_Show("BFQ_CONFIRM_ABANDON_QUEST", title, nil, {
                    questID = questID,
                    questLogIndex = qInfo.questLogIndex,
                    title = title,
                })
            end,
        },
        { text = "Cancel", notCheckable = true, func = function() end },
    }

    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(UIParent, function(ownerRegion, rootDescription)
            for _, item in ipairs(menu) do
                if item.isTitle then
                    if rootDescription.CreateTitle then
                        rootDescription:CreateTitle(item.text)
                    end
                elseif item.text and item.text ~= "" then
                    if item.text == "Cancel" then
                        if rootDescription.CreateDivider then rootDescription:CreateDivider() end
                        rootDescription:CreateButton(item.text, function() end)
                    else
                        local btn = rootDescription:CreateButton(item.text, function()
                            if item.func then item.func() end
                        end)
                        if item.disabled and btn and btn.SetEnabled then
                            btn:SetEnabled(false)
                        end
                    end
                end
            end
        end)
        return
    end

    if EasyMenu then
        EasyMenu(menu, questContextMenu, "cursor", 0, 0, "MENU")
    elseif ToggleDropDownMenu and UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(questContextMenu, function(_, level)
            for _, item in ipairs(menu) do
                UIDropDownMenu_AddButton(item, level)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, questContextMenu, "cursor", 0, 0)
    end
end

-- SafeCall wrapper to guard against Classic API argument count crashes
local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, res1, res2, res3, res4 = pcall(fn, ...)
    if ok then
        return res1, res2, res3, res4
    end
    return nil
end

local function ToNumber(val)
    if val == nil then return nil end
    return tonumber(val)
end

-- Cache for quest rewards to avoid repeated quest log selection on hover
local questRewardsCache = {}

local function FormatMoneyString(copper)
    if GetCoinTextureString then
        local coinStr = SafeCall(GetCoinTextureString, copper)
        if coinStr then return coinStr end
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, string.format("|cffffd700%dg|r", g)) end
    if s > 0 then table.insert(parts, string.format("|cffc7c7cf%ds|r", s)) end
    if c > 0 or #parts == 0 then table.insert(parts, string.format("|cffeda55f%dc|r", c)) end
    return table.concat(parts, " ")
end

-- Helper: Determine whether an item reward is equippable and usable by the player's class
local function IsItemUsableByPlayerClass(itemLink)
    if not itemLink then return nil end
    local itemID = tonumber(itemLink:match("item:(%d+)"))

    -- 1. Modern C_PlayerInfo API check
    if itemID and C_PlayerInfo and C_PlayerInfo.CanUseItem then
        local ok, canUse = pcall(C_PlayerInfo.CanUseItem, itemID)
        if ok and canUse ~= nil then
            return canUse
        end
    end

    -- 2. Modern C_Item API check
    if C_Item and C_Item.IsItemUsable then
        local ok, usable = pcall(C_Item.IsItemUsable, itemLink)
        if ok and usable ~= nil then
            return usable
        end
    end

    -- 3. Detailed Equipment & Class Matrix Fallback
    local _, _, _, _, itemMinLevel, itemType, itemSubType, _, itemEquipLoc, _, _, classID, subclassID = GetItemInfo(itemLink)
    if not itemEquipLoc or itemEquipLoc == "" or itemEquipLoc == "INVTYPE_NON_EQUIP" then
        return nil -- Non-equipment (consumable, reagent, quest item)
    end

    local _, playerClass = UnitClass("player")
    local playerLevel = (UnitLevel and UnitLevel("player")) or 1

    -- Armor checks (classID == 4 or itemType == "Armor")
    if classID == 4 or itemType == "Armor" then
        -- Rings, Necks, Trinkets, Cloaks, Shirts, Tabards (subclass 0 or specific equip slots)
        if subclassID == 0 or itemEquipLoc == "INVTYPE_CLOAK" or itemEquipLoc == "INVTYPE_FINGER" or itemEquipLoc == "INVTYPE_TRINKET" or itemEquipLoc == "INVTYPE_NECK" or itemEquipLoc == "INVTYPE_BODY" or itemEquipLoc == "INVTYPE_TABARD" then
            return true
        end
        -- Cloth (subclass 1) - usable by all classes
        if subclassID == 1 then
            return true
        end
        -- Leather (subclass 2)
        if subclassID == 2 then
            return (playerClass == "DRUID" or playerClass == "ROGUE" or playerClass == "HUNTER" or playerClass == "SHAMAN" or playerClass == "PALADIN" or playerClass == "WARRIOR")
        end
        -- Mail (subclass 3)
        if subclassID == 3 then
            if playerClass == "WARRIOR" or playerClass == "PALADIN" then
                return true
            elseif playerClass == "HUNTER" or playerClass == "SHAMAN" then
                return playerLevel >= 40
            end
            return false
        end
        -- Plate (subclass 4)
        if subclassID == 4 then
            if playerClass == "WARRIOR" or playerClass == "PALADIN" then
                return playerLevel >= 40
            end
            return false
        end
        -- Shields (subclass 6)
        if subclassID == 6 or itemEquipLoc == "INVTYPE_SHIELD" then
            return (playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "SHAMAN")
        end
        -- Relics: Libram (7), Idol (8), Totem (9)
        if subclassID == 7 then return playerClass == "PALADIN" end
        if subclassID == 8 then return playerClass == "DRUID" end
        if subclassID == 9 then return playerClass == "SHAMAN" end
    end

    -- Weapon checks (classID == 2 or itemType == "Weapon")
    if classID == 2 or itemType == "Weapon" then
        if subclassID == 0 then -- 1H Axe
            return (playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "HUNTER" or playerClass == "SHAMAN" or playerClass == "ROGUE")
        elseif subclassID == 1 then -- 2H Axe
            return (playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "HUNTER" or playerClass == "SHAMAN")
        elseif subclassID == 2 then -- Bow
            return (playerClass == "WARRIOR" or playerClass == "HUNTER" or playerClass == "ROGUE")
        elseif subclassID == 3 then -- Gun
            return (playerClass == "WARRIOR" or playerClass == "HUNTER" or playerClass == "ROGUE")
        elseif subclassID == 4 then -- 1H Mace
            return (playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "ROGUE" or playerClass == "PRIEST" or playerClass == "SHAMAN" or playerClass == "DRUID")
        elseif subclassID == 5 then -- 2H Mace
            return (playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "SHAMAN" or playerClass == "DRUID")
        elseif subclassID == 6 then -- Polearm
            return (playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "HUNTER" or playerClass == "DRUID")
        elseif subclassID == 7 then -- 1H Sword
            return (playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "HUNTER" or playerClass == "ROGUE" or playerClass == "MAGE" or playerClass == "WARLOCK")
        elseif subclassID == 8 then -- 2H Sword
            return (playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "HUNTER")
        elseif subclassID == 10 then -- Staff
            return (playerClass == "WARRIOR" or playerClass == "HUNTER" or playerClass == "PRIEST" or playerClass == "SHAMAN" or playerClass == "MAGE" or playerClass == "WARLOCK" or playerClass == "DRUID")
        elseif subclassID == 13 then -- Fist
            return (playerClass == "WARRIOR" or playerClass == "HUNTER" or playerClass == "ROGUE" or playerClass == "SHAMAN" or playerClass == "DRUID")
        elseif subclassID == 14 then -- Misc/Thrown
            return (playerClass == "WARRIOR" or playerClass == "HUNTER" or playerClass == "ROGUE")
        elseif subclassID == 15 then -- Dagger
            return (playerClass ~= "PALADIN")
        elseif subclassID == 18 then -- Crossbow
            return (playerClass == "WARRIOR" or playerClass == "HUNTER" or playerClass == "ROGUE")
        elseif subclassID == 19 then -- Wand
            return (playerClass == "PRIEST" or playerClass == "MAGE" or playerClass == "WARLOCK")
        end
    end

    return true
end

local function GetQuestRewards(questID, questLogIndex)
    if not questID then return nil end
    if questRewardsCache[questID] then
        return questRewardsCache[questID]
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

    if not questLogIndex or questLogIndex == 0 then return nil end

    local inCombat = InCombatLockdown and InCombatLockdown()
    local origSelected = not inCombat and SafeCall(GetQuestLogSelection) or nil
    local origSelectedQID = (not inCombat and C_QuestLog and C_QuestLog.GetSelectedQuest and SafeCall(C_QuestLog.GetSelectedQuest)) or nil
    if not inCombat then
        if questLogIndex and questLogIndex > 0 and origSelected ~= questLogIndex then
            SafeCall(SelectQuestLogEntry, questLogIndex)
        end
        if questID and C_QuestLog and C_QuestLog.SetSelectedQuest and origSelectedQID ~= questID then
            SafeCall(C_QuestLog.SetSelectedQuest, questID)
        end
    end

    local rewards = {
        xp = 0,
        money = 0,
        honor = 0,
        spell = nil,
        items = {},
        choices = {},
    }

    -- 1. Experience (Classic Era takes 0 args; modern clients take questID)
    local xp = SafeCall(GetQuestLogRewardXP)
    if xp == nil and questID then
        xp = SafeCall(GetQuestLogRewardXP, questID)
    end
    rewards.xp = tonumber(xp) or 0

    -- 2. Money (Classic Era takes 0 args; modern clients take questID)
    local money = SafeCall(GetQuestLogRewardMoney)
    if money == nil and questID then
        money = SafeCall(GetQuestLogRewardMoney, questID)
    end
    rewards.money = tonumber(money) or 0

    -- 3. Honor
    local honor = SafeCall(GetQuestLogRewardHonor)
    if honor == nil and questID then
        honor = SafeCall(GetQuestLogRewardHonor, questID)
    end
    rewards.honor = tonumber(honor) or 0

    -- 4. Spell
    local spellName, spellTexture = SafeCall(GetQuestLogRewardSpell)
    if not spellName and questID then
        spellName, spellTexture = SafeCall(GetQuestLogRewardSpell, questID)
    end
    if spellName and spellName ~= "" then
        rewards.spell = { name = spellName, texture = spellTexture }
    end

    -- 5. Guaranteed Fixed Item Rewards
    local numRewards = ToNumber((SafeCall(GetNumQuestLogRewards))) or (questID and ToNumber((SafeCall(GetNumQuestLogRewards, questID)))) or 0
    for i = 1, numRewards do
        local name, texture, numItems, quality = SafeCall(GetQuestLogRewardInfo, i)
        if not name and questID then
            name, texture, numItems, quality = SafeCall(GetQuestLogRewardInfo, i, questID)
        end
        local itemLink = SafeCall(GetQuestLogItemLink, "reward", i)
        if not itemLink and questID then
            itemLink = SafeCall(GetQuestLogItemLink, "reward", i, questID)
        end
        if name or itemLink then
            table.insert(rewards.items, {
                name = name,
                texture = texture,
                count = ToNumber(numItems) or 1,
                quality = ToNumber(quality) or 1,
                itemLink = itemLink,
            })
        end
    end

    -- 6. Choice Item Rewards
    local numChoices = ToNumber((SafeCall(GetNumQuestLogChoices))) or (questID and ToNumber((SafeCall(GetNumQuestLogChoices, questID)))) or 0
    for i = 1, numChoices do
        local name, texture, numItems, quality = SafeCall(GetQuestLogChoiceInfo, i)
        if not name and questID then
            name, texture, numItems, quality = SafeCall(GetQuestLogChoiceInfo, i, questID)
        end
        local itemLink = SafeCall(GetQuestLogItemLink, "choice", i)
        if not itemLink and questID then
            itemLink = SafeCall(GetQuestLogItemLink, "choice", i, questID)
        end
        if name or itemLink then
            table.insert(rewards.choices, {
                name = name,
                texture = texture,
                count = tonumber(numItems) or 1,
                quality = tonumber(quality) or 1,
                itemLink = itemLink,
            })
        end
    end

    -- Restore previous selection in Blizzard's quest log
    if not inCombat then
        if origSelected and origSelected > 0 and origSelected ~= questLogIndex then
            SafeCall(SelectQuestLogEntry, origSelected)
        end
        if origSelectedQID and C_QuestLog and C_QuestLog.SetSelectedQuest and origSelectedQID ~= questID then
            SafeCall(C_QuestLog.SetSelectedQuest, origSelectedQID)
        end
    end

    local hasRewards = (rewards.xp > 0) or (rewards.money > 0) or (rewards.honor > 0) or rewards.spell or (#rewards.items > 0) or (#rewards.choices > 0)
    rewards.hasRewards = hasRewards

    -- Only cache if item names/links aren't currently waiting on server query
    local pending = (numRewards > #rewards.items) or (numChoices > #rewards.choices)
    if not pending then
        questRewardsCache[questID] = rewards
    end

    return rewards
end
ns.GetQuestRewards = GetQuestRewards

local function ShowQuestTooltip(anchorFrame, qInfo)
    if not qInfo then return end
    local questKey = qInfo.questID or qInfo.title
    local isCollapsed = ns.db and ns.db.collapsedQuests and ns.db.collapsedQuests[questKey]
    local isActive = (qInfo.questID and ns.activeQuestID == qInfo.questID)

    GameTooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local titleLine = qInfo.title or "Quest"
    if qInfo.level and qInfo.level > 0 then
        titleLine = string.format("[%d] %s", qInfo.level, titleLine)
    end
    GameTooltip:AddLine(titleLine, 1, 0.82, 0)

    -- Optional: Show Quest Rewards on Mouseover
    local showRewards = not (ns.db and ns.db.tooltips and ns.db.tooltips.showRewards == false)
    if showRewards then
        local rewards = GetQuestRewards(qInfo.questID, qInfo.questLogIndex)
        if rewards then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd100Quest Rewards:|r")
            if rewards.hasRewards then
                if rewards.xp > 0 then
                    local xpStr = (BreakUpLargeNumbers and BreakUpLargeNumbers(rewards.xp)) or tostring(rewards.xp)
                    local xpPctStr = ""
                    local showXpPercent = not (ns.db and ns.db.tooltips and ns.db.tooltips.showXpPercent == false)
                    if showXpPercent then
                        local maxXP = UnitXPMax and UnitXPMax("player")
                        local curLevel = UnitLevel and UnitLevel("player")
                        local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
                        if maxXP and maxXP > 0 and curLevel and curLevel < maxLevel then
                            local pct = (rewards.xp / maxXP) * 100
                            xpPctStr = string.format(" |cffffd100(%.1f%% of lvl %d)|r", pct, curLevel)
                        end
                    end
                    GameTooltip:AddLine("  • |cffffffff" .. xpStr .. "|r |cff00ff00XP|r" .. xpPctStr, 0.9, 0.9, 0.9)
                end

                if rewards.money > 0 then
                    GameTooltip:AddLine("  • " .. FormatMoneyString(rewards.money), 1, 1, 1)
                end

                if rewards.honor > 0 then
                    GameTooltip:AddLine("  • |cff00e5ff" .. rewards.honor .. " Honor|r", 0, 0.9, 1)
                end

                if rewards.spell and rewards.spell.name then
                    local icon = (rewards.spell.texture and ("|T" .. rewards.spell.texture .. ":14:14:0:0|t ")) or ""
                    GameTooltip:AddLine("  • " .. icon .. "|cff71d5ff" .. rewards.spell.name .. "|r", 0.5, 0.8, 1)
                end

                local showUsableGear = not (ns.db and ns.db.tooltips and ns.db.tooltips.showUsableGear == false)
                local showBestSell = not (ns.db and ns.db.tooltips and ns.db.tooltips.showBestSell == false)

                if #rewards.choices > 0 then
                    -- Calculate highest vendor resale price among reward choices
                    local maxSellPrice = 0
                    local bestSellIndex = nil
                    if showBestSell and #rewards.choices > 1 then
                        for i, choice in ipairs(rewards.choices) do
                            local sellPrice = 0
                            if choice.itemLink then
                                local _, _, _, _, _, _, _, _, _, _, price = GetItemInfo(choice.itemLink)
                                sellPrice = price or 0
                            end
                            local totalSell = sellPrice * (choice.count or 1)
                            choice.totalSell = totalSell
                            if totalSell > maxSellPrice then
                                maxSellPrice = totalSell
                                bestSellIndex = i
                            end
                        end
                    end

                    GameTooltip:AddLine("  |cffffbb00Choose One:|r")
                    for i, choice in ipairs(rewards.choices) do
                        local icon = (choice.texture and ("|T" .. choice.texture .. ":14:14:0:0|t ")) or ""
                        local count = (choice.count and choice.count > 1 and (" |cffffffff(x" .. choice.count .. ")|r")) or ""
                        local itemText
                        if choice.itemLink then
                            itemText = choice.itemLink
                        else
                            local colorCode = (choice.quality and select(4, GetItemQualityColor(choice.quality))) or "|cffffffff"
                            itemText = colorCode .. (choice.name or "Item") .. "|r"
                        end

                        local usableTag = ""
                        local lineR, lineG, lineB = 0.9, 0.9, 0.9
                        if showUsableGear and choice.itemLink then
                            local isUsable = IsItemUsableByPlayerClass(choice.itemLink)
                            if isUsable == true then
                                usableTag = " |cff00ff00[Usable]|r"
                            elseif isUsable == false then
                                usableTag = " |cff888888[Unusable]|r"
                                lineR, lineG, lineB = 0.6, 0.6, 0.6
                            end
                        end

                        local bestSellTag = ""
                        if showBestSell and bestSellIndex == i and maxSellPrice > 0 then
                            bestSellTag = " |TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t |cffffd100[Best Sell: " .. FormatMoneyString(maxSellPrice) .. "]|r"
                        end

                        GameTooltip:AddLine("    " .. icon .. itemText .. count .. usableTag .. bestSellTag, lineR, lineG, lineB)
                    end
                end

                if #rewards.items > 0 then
                    GameTooltip:AddLine("  |cff00ff00You Receive:|r")
                    for _, item in ipairs(rewards.items) do
                        local icon = (item.texture and ("|T" .. item.texture .. ":14:14:0:0|t ")) or ""
                        local count = (item.count and item.count > 1 and (" |cffffffff(x" .. item.count .. ")|r")) or ""
                        local itemText
                        if item.itemLink then
                            itemText = item.itemLink
                        else
                            local colorCode = (item.quality and select(4, GetItemQualityColor(item.quality))) or "|cffffffff"
                            itemText = colorCode .. (item.name or "Item") .. "|r"
                        end

                        local usableTag = ""
                        local lineR, lineG, lineB = 0.9, 0.9, 0.9
                        if showUsableGear and item.itemLink then
                            local isUsable = IsItemUsableByPlayerClass(item.itemLink)
                            if isUsable == true then
                                usableTag = " |cff00ff00[Usable]|r"
                            elseif isUsable == false then
                                usableTag = " |cff888888[Unusable]|r"
                                lineR, lineG, lineB = 0.6, 0.6, 0.6
                            end
                        end

                        GameTooltip:AddLine("    " .. icon .. itemText .. count .. usableTag, lineR, lineG, lineB)
                    end
                end
            else
                GameTooltip:AddLine("  • |cff888888None (or discovery quest)|r", 0.6, 0.6, 0.6)
            end
        end
    end

    local db = ns.db
    -- Party Quest Status
    local showPartyTip = not (db and db.tooltips and db.tooltips.showPartyStatus == false)
    if showPartyTip and ns.SocialModule and ns.SocialModule.GetPartyQuestDetails then
        local partyDetails = ns.SocialModule:GetPartyQuestDetails(qInfo.questID, qInfo.questLogIndex)
        if partyDetails and partyDetails.totalGroupMembers > 1 then
            local classColorParty = not (db and db.tooltips and db.tooltips.classColorParty == false)
            local showMissing = not (db and db.tooltips and db.tooltips.showMissingParty == false)

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd100Party Quest Status:|r")

            if partyDetails.onQuestCount > 0 then
                for _, member in ipairs(partyDetails.onQuest) do
                    local nameStr = classColorParty and member.coloredName or member.name
                    local statusTag = "|cff00ff00[✓ On Quest]|r"
                    if not member.isConnected then
                        statusTag = statusTag .. " |cff888888(Offline)|r"
                    end
                    GameTooltip:AddLine("  • " .. nameStr .. " " .. statusTag)
                end
            else
                GameTooltip:AddLine("  • |cff888888No other party members are on this quest|r")
            end

            if showMissing and partyDetails.missingCount > 0 then
                for _, member in ipairs(partyDetails.missing) do
                    local nameStr = classColorParty and member.coloredName or member.name
                    local statusTag = "|cffff6666[✗ Missing]|r"
                    if partyDetails.isPushable then
                        statusTag = statusTag .. " |cff00e5ff(Click to Share)|r"
                    end
                    if not member.isConnected then
                        statusTag = statusTag .. " |cff888888(Offline)|r"
                    end
                    GameTooltip:AddLine("  • " .. nameStr .. " " .. statusTag)
                end
            end
        end
    end

    GameTooltip:AddLine(" ")
    if isActive then
        GameTooltip:AddLine("|cff00e5ff● Active Quest|r |cffaaaaaa(Left-Click to " .. (isCollapsed and "Expand" or "Collapse") .. ")|r", 0.0, 0.9, 1.0)
        if ns.WayfinderModule and ns.WayfinderModule.IsCustomTarget and ns.WayfinderModule:IsCustomTarget() then
            local cur = ns.WayfinderModule.GetCurrentTarget and ns.WayfinderModule:GetCurrentTarget()
            local nav = ns.WayfinderModule.GetNavigationState and ns.WayfinderModule:GetNavigationState()
            if cur and cur.title then
                local distStr = (nav and nav.distanceYards and nav.distanceYards > 0) and string.format("%d yd", math.floor(nav.distanceYards + 0.5)) or ""
                GameTooltip:AddDoubleLine("|cff00c0ffNavigating to Waypoint:|r", "|cffffd100" .. cur.title .. "|r" .. (distStr ~= "" and (" |cffffffff(" .. distStr .. ")|r") or ""))
            end
        end
    else
        GameTooltip:AddLine("|cff00ff00Left-Click: Set as Active Quest|r", 0.2, 1, 0.2)
    end
    GameTooltip:AddLine("|cffaaaaaaAlt + Left-Click: " .. (isCollapsed and "Expand Quest" or "Collapse Quest") .. "|r", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("|cffaaaaaaCtrl + Left-Click: Open in Quest Log|r", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("|cffaaaaaaShift + Left-Click: Link in Chat|r", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("|cffaaaaaaRight-Click: Quest Actions Menu|r", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff00c0ffShift + Right-Click: Copy Wowhead URL|r", 0.2, 0.8, 1)
    GameTooltip:AddLine("|cff00ff00Alt + Right-Click: Open Settings|r", 0.2, 1, 0.2)
    GameTooltip:Show()
end

local function HideQuestTooltip(frame)
    C_Timer.After(0.05, function()
        local header = (frame and (frame.header or (frame.IsObjectType and frame:IsObjectType("Button") and frame)))
        local block = (frame and (frame.block or (frame.IsObjectType and frame:IsObjectType("Frame") and frame)))
        if (header and header.IsMouseOver and header:IsMouseOver()) or (block and block.IsMouseOver and block:IsMouseOver()) then
            return
        end
        GameTooltip:Hide()
    end)
end

-- Acquire or create a Quest Block container
local function AcquireQuestBlock(parent)
    local block
    for _, b in ipairs(questBlocks) do
        if not b:IsShown() then
            block = b
            block:SetParent(parent)
            block:Show()
            if block.header then block.header:Show() end
            break
        end
    end
    if not block then
        block = CreateFrame("Frame", nil, parent)
        block.questInfo = {}
        block:SetWidth(parent:GetWidth())
        block:EnableMouse(true)
        block:RegisterForDrag("LeftButton")
        block:SetScript("OnDragStart", function(self)
            if ns.Tracker and ns.Tracker.StartDragging then
                ns.Tracker.StartDragging()
            end
        end)
        block:SetScript("OnDragStop", function(self)
            if ns.Tracker and ns.Tracker.StopDragging then
                ns.Tracker.StopDragging()
            end
        end)
        block:SetScript("OnEnter", function(self)
            ShowQuestTooltip(self.header or self, self.questInfo)
        end)
        block:SetScript("OnLeave", function(self)
            HideQuestTooltip(self)
        end)

        -- Header Button for Click/Hover
        local header = CreateFrame("Button", nil, block)
        block.header = header
        header.block = block
        header.questInfo = block.questInfo
        local titleSize = StandaloneTracker.titleSize or 13
        header:SetHeight(titleSize + 6)
        header:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)
        header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        header:RegisterForDrag("LeftButton")
        header:SetScript("OnDragStart", function(self)
            self.wasDragged = true
            if ns.Tracker and ns.Tracker.StartDragging then
                ns.Tracker.StartDragging()
            end
        end)
        header:SetScript("OnDragStop", function(self)
            if ns.Tracker and ns.Tracker.StopDragging then
                ns.Tracker.StopDragging()
            end
            C_Timer.After(0.1, function()
                self.wasDragged = false
            end)
        end)

        -- Quest Title
        local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header.title = title
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
        title:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(true)
        local fPath = StandaloneTracker.headerFontPath or StandaloneTracker.fontPath
        SafeSetFont(title, fPath, titleSize, StandaloneTracker.titleOutline or "OUTLINE")

        -- Wayfinder Inline Directional Arrow
        local wayfinderArrow = header:CreateTexture(nil, "OVERLAY")
        header.wayfinderArrow = wayfinderArrow
        local inlineSize = (ns.db and ns.db.wayfinder and ns.db.wayfinder.inlineArrowSize) or 22
        wayfinderArrow:SetSize(inlineSize, inlineSize)
        local arrowTex = (ns.WayfinderModule and ns.WayfinderModule.GetArrowTexture and ns.WayfinderModule:GetArrowTexture()) or "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW"
        wayfinderArrow:SetTexture(arrowTex)
        wayfinderArrow:Hide()

        -- Highlight Texture on mouseover
        local hl = header:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(header)
        hl:SetColorTexture(1, 1, 1, 0.08)

        -- Click Actions: Left = Collapse/Expand, Ctrl+Left = QuestLog, Shift+Left = ChatLink, Right = Context Menu, Shift+Right = Wowhead URL
        header:SetScript("OnClick", function(self, mouseButton)
            if self.wasDragged or (ns.Tracker and ns.Tracker.frame and ns.Tracker.frame.isMoving) then
                return
            end
            local qInfo = self.questInfo
            if not qInfo then return end

            if mouseButton == "LeftButton" then
                if IsModifiedClick("CHATLINK") and qInfo.questID then
                    local link = (C_QuestLog and C_QuestLog.GetQuestLink and C_QuestLog.GetQuestLink(qInfo.questID)) or (GetQuestLink and GetQuestLink(qInfo.questID))
                    if link then
                        ChatEdit_InsertLink(link)
                    end
                elseif IsControlKeyDown() then
                    if InCombatLockdown and InCombatLockdown() then
                        if UIErrorsFrame and UIErrorsFrame.AddMessage then
                            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "Cannot open quest log in combat", 1.0, 0.1, 0.1, 1.0)
                        end
                        return
                    end
                    if qInfo.questLogIndex and QuestLogFrame and SelectQuestLogEntry then
                        ShowUIPanel(QuestLogFrame)
                        SelectQuestLogEntry(qInfo.questLogIndex)
                        if QuestLog_Update then QuestLog_Update() end
                    elseif qInfo.questID and QuestMapFrame_OpenToQuestDetails then
                        if securecallfunction then
                            securecallfunction(QuestMapFrame_OpenToQuestDetails, qInfo.questID)
                        else
                            QuestMapFrame_OpenToQuestDetails(qInfo.questID)
                        end
                    end
                elseif IsAltKeyDown() then
                    -- Alt + Left-Click: Toggle Collapse/Expand directly
                    local questKey = qInfo.questID or qInfo.title
                    if questKey and ns.db then
                        ns.db.collapsedQuests = ns.db.collapsedQuests or {}
                        ns.db.collapsedQuests[questKey] = not ns.db.collapsedQuests[questKey]
                        if ns.FlushDBToGlobals then
                            ns.FlushDBToGlobals()
                        end
                        StandaloneTracker:UpdateTracker()
                    end
                else
                    -- Normal Left-Click:
                    -- If not the active quest, select it as active!
                    -- If already active, toggle collapse/expand!
                    if qInfo.questID and ns.activeQuestID ~= qInfo.questID then
                        StandaloneTracker:SetActiveQuest(qInfo.questID)
                    else
                        local questKey = qInfo.questID or qInfo.title
                        if questKey and ns.db then
                            ns.db.collapsedQuests = ns.db.collapsedQuests or {}
                            ns.db.collapsedQuests[questKey] = not ns.db.collapsedQuests[questKey]
                            if ns.FlushDBToGlobals then
                                ns.FlushDBToGlobals()
                            end
                            StandaloneTracker:UpdateTracker()
                        end
                    end
                end
            elseif mouseButton == "RightButton" then
                if IsAltKeyDown() then
                    if ns.Config then ns.Config:ToggleConfigFrame() end
                elseif IsShiftKeyDown() then
                    -- Shift + Right-Click: Direct Wowhead URL Dialog
                    if qInfo.questID then
                        local url = string.format("https://www.wowhead.com/forever/quest=%d", qInfo.questID)
                        if ns.Config and ns.Config.ShowCopyDialog then
                            ns.Config:ShowCopyDialog(url, qInfo.title)
                        end
                    end
                else
                    -- Normal Right-Click: Dropdown Context Menu
                    StandaloneTracker:OpenQuestContextMenu(self, qInfo)
                end
            end
        end)

        -- Tooltip on Hover
        header:SetScript("OnEnter", function(self)
            ShowQuestTooltip(self, self.questInfo)
        end)

        header:SetScript("OnLeave", function(self)
            HideQuestTooltip(self)
        end)

        block.activeObjectives = {}
        table.insert(questBlocks, block)
    end
    return block
end

function StandaloneTracker:ApplyTypography(headerFontPath, objectiveFontPath, titleSize, objSize, headerOutline, objOutline, zoneHeaderSize, enableShadow)
    local hFont = headerFontPath
    local oFont = (type(objectiveFontPath) == "string" and objectiveFontPath) or headerFontPath
    local tSize = (type(objectiveFontPath) == "number" and objectiveFontPath) or (type(titleSize) == "number" and titleSize) or 13
    local oSize = (type(objSize) == "number" and objSize) or (type(titleSize) == "number" and titleSize) or 11
    local zSize = (type(zoneHeaderSize) == "number" and zoneHeaderSize) or (ns.db and ns.db.fonts and ns.db.fonts.zoneHeaderSize) or math.max(10, tSize - 1)
    local hOutline = CleanOutline((type(headerOutline) == "string" and headerOutline) or (type(objSize) == "string" and objSize) or "OUTLINE")
    local oOutline = CleanOutline(type(objOutline) == "string" and objOutline)
    local shadow = (enableShadow ~= false)

    self.headerFontPath = hFont
    self.fontPath = hFont
    self.objectiveFontPath = oFont
    self.titleSize = tSize
    self.objSize = oSize
    self.zoneHeaderSize = zSize
    self.titleOutline = hOutline
    self.objOutline = oOutline
    self.enableShadow = shadow

    for _, block in ipairs(questBlocks) do
        if block.header and block.header.title then
            SafeSetFont(block.header.title, hFont, tSize, hOutline, shadow)
        end
    end

    for _, str in ipairs(objectiveStrings) do
        SafeSetFont(str, oFont, oSize, oOutline, shadow)
    end

    for _, str in ipairs(partyStrings) do
        SafeSetFont(str, oFont, math.max(9, oSize - 1), oOutline, shadow)
    end

    for _, btn in ipairs(shareButtons) do
        if btn.text then
            SafeSetFont(btn.text, oFont, math.max(9, oSize - 1), oOutline, shadow)
        end
    end

    for _, zh in ipairs(zoneHeaders) do
        SafeSetFont(zh.title, hFont, zSize, hOutline, shadow)
        SafeSetFont(zh.collapseText, hFont, math.min(13, math.max(10, zSize - 1)), hOutline, shadow)
        SafeSetFont(zh.count, hFont, math.max(9, zSize - 2), hOutline, shadow)
    end

    self:UpdateTracker()
end

-- Static Reusable Valid Zones Table (Zero Allocation across quest loop)
local playerValidZones = {}

local function UpdatePlayerValidZones()
    wipe(playerValidZones)
    local playerRealZone = (GetRealZoneText and GetRealZoneText()) or ""
    local playerZone = (GetZoneText and GetZoneText()) or ""
    local playerSubZone = (GetSubZoneText and GetSubZoneText()) or ""
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapInfo = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local mapName = (mapInfo and mapInfo.name) or ""

    if playerRealZone ~= "" then table_insert(playerValidZones, playerRealZone) end
    if playerZone ~= "" and playerZone ~= playerRealZone then table_insert(playerValidZones, playerZone) end
    if playerSubZone ~= "" and playerSubZone ~= playerZone and playerSubZone ~= playerRealZone then table_insert(playerValidZones, playerSubZone) end
    if mapName ~= "" and mapName ~= playerZone and mapName ~= playerRealZone then table_insert(playerValidZones, mapName) end

    if IsInInstance and IsInInstance() then
        local instName = GetInstanceInfo and GetInstanceInfo()
        if instName and instName ~= "" then
            table_insert(playerValidZones, instName)
        end
    end
end

local function NormalizeZoneStr(str)
    if not str or str == "" then return "" end
    local s = string_lower(str)
    s = s:gsub("^the%s+", "")
    s = s:match("^%s*(.-)%s*$") or s
    return s
end

-- Helper: Robust Zone Matching (Checks Zone Header, SubZone, and Starter Heuristics)
local function MatchesCurrentZone(zoneHeader, questID, questLogIndex)
    local validZones = playerValidZones
    local Normalize = NormalizeZoneStr

    -- 1. Compare against Quest Log Zone Header
    local nonZoneHeaders = {
        ["mage"] = true, ["warrior"] = true, ["paladin"] = true, ["hunter"] = true,
        ["rogue"] = true, ["priest"] = true, ["shaman"] = true, ["warlock"] = true, ["druid"] = true,
        ["alchemy"] = true, ["blacksmithing"] = true, ["enchanting"] = true, ["engineering"] = true,
        ["leatherworking"] = true, ["tailoring"] = true, ["herbalism"] = true, ["mining"] = true,
        ["skinning"] = true, ["cooking"] = true, ["first aid"] = true, ["fishing"] = true,
        ["general"] = true, ["special"] = true, ["battlegrounds"] = true, ["seasonal"] = true,
    }

    local normHeader = Normalize(zoneHeader)
    local isClassOrProfHeader = nonZoneHeaders[normHeader] or false

    if not isClassOrProfHeader and normHeader ~= "" then
        for _, z in ipairs(validZones) do
            local normZ = Normalize(z)
            if normZ ~= "" then
                if normHeader == normZ then
                    return true
                elseif #normZ >= 5 and #normHeader >= 5 then
                    if normHeader:find(normZ, 1, true) or normZ:find(normHeader, 1, true) then
                        return true
                    end
                end
            end
        end
    end

    -- 2. Starter Zone Class Quest Heuristic:
    if isClassOrProfHeader then
        local starterZones = {
            ["dun morogh"] = true, ["coldridge valley"] = true,
            ["elwynn forest"] = true, ["northshire"] = true, ["northshire valley"] = true,
            ["teldrassil"] = true, ["shadowglen"] = true,
            ["durotar"] = true, ["valley of trials"] = true,
            ["mulgore"] = true, ["red cloud mesa"] = true,
            ["tirisfal glades"] = true, ["deathknell"] = true,
            ["zephras isle"] = true, ["zephras isles"] = true, ["the zephras isles"] = true, ["the zephras isle"] = true,
            ["riverlands"] = true, ["the riverlands"] = true, ["the riverglades"] = true, ["riverglades"] = true,
            ["hall of thanes"] = true, ["the hall of thanes"] = true, ["hall of the thanes"] = true,
            ["darkspear islands"] = true, ["darkspear island"] = true, ["darkspear strand"] = true,
        }

        local inStarterZone = false
        for _, z in ipairs(validZones) do
            if starterZones[Normalize(z)] then
                inStarterZone = true
                break
            end
        end

        if inStarterZone then
            local qLevel = 1
            if C_QuestLog and C_QuestLog.GetInfo then
                local info = C_QuestLog.GetInfo(questID)
                if info and info.level then qLevel = info.level end
            end
            if qLevel <= 10 then
                return true
            end
        end
    end

    -- 3. Standalone Cross-Zone Module (if module is loaded and enabled)
    if ns.CrossZoneModule and ns.CrossZoneModule.MatchesCurrentZone then
        if ns.CrossZoneModule:MatchesCurrentZone(questID, questLogIndex, validZones) then
            return true
        end
    end

    return false
end

-- Helper: Format seconds to MM:SS or H:MM:SS
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

-- Event-driven Bag Quest Item Cache (Eliminates tooltip parsing and bag iteration during quest redraws)
local bagQuestItemsCache = {}
local bagCacheDirty = true

local function UpdateBagQuestItemsCache()
    if not bagCacheDirty then return end
    wipe(bagQuestItemsCache)
    bagCacheDirty = false

    local numBags = NUM_BAG_SLOTS or 4
    for bag = 0, numBags do
        local numSlots = 0
        if C_Container and C_Container.GetContainerNumSlots then
            numSlots = C_Container.GetContainerNumSlots(bag) or 0
        elseif _G.GetContainerNumSlots then
            numSlots = _G.GetContainerNumSlots(bag) or 0
        end

        for slot = 1, numSlots do
            local itemID, hyperlink, icon, stackCount
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    itemID = info.itemID
                    hyperlink = info.hyperlink
                    icon = info.iconFileID
                    stackCount = info.stackCount
                end
            elseif _G.GetContainerItemInfo then
                local itemTexture, count, _, _, _, _, link, _, _, id = _G.GetContainerItemInfo(bag, slot)
                itemID = id
                hyperlink = link
                icon = itemTexture
                stackCount = count
            end

            if itemID and hyperlink then
                local itemClassID
                if C_Item and C_Item.GetItemInfoInstant then
                    local _, _, _, _, _, cid = C_Item.GetItemInfoInstant(itemID)
                    itemClassID = cid
                elseif C_Item and C_Item.GetItemInfo then
                    local _, _, _, _, _, _, _, _, _, _, _, cid = C_Item.GetItemInfo(hyperlink)
                    itemClassID = cid
                elseif GetItemInfoInstant then
                    local _, _, _, _, _, cid = GetItemInfoInstant(itemID)
                    itemClassID = cid
                elseif GetItemInfo then
                    local _, _, _, _, _, _, _, _, _, _, _, cid = GetItemInfo(hyperlink)
                    itemClassID = cid
                end

                local isCandidate = (itemClassID == 12 or itemClassID == 0 or itemClassID == 15 or (Enum and Enum.ItemClass and itemClassID == Enum.ItemClass.Questitem))
                if isCandidate then
                    local itemName = hyperlink:match("%[(.-)%]")
                    if itemName and itemName ~= "" then
                        local nLower = string_lower(itemName)
                        bagQuestItemsCache[nLower] = { link = hyperlink, icon = icon, count = stackCount, name = itemName }
                    end
                    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
                        local data = C_TooltipInfo.GetBagItem(bag, slot)
                        if data and data.lines then
                            for _, line in ipairs(data.lines) do
                                if line.leftText and line.leftText ~= "" then
                                    local lText = string_lower(line.leftText)
                                    bagQuestItemsCache[lText] = { link = hyperlink, icon = icon, count = stackCount, name = itemName }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Helper to scan inventory bags for a quest item (O(1) cached lookup)
local function FindQuestItemInBags(targetQuestID, questTitle, objectives)
    if bagCacheDirty then
        UpdateBagQuestItemsCache()
    end
    local qLower = questTitle and string_lower(questTitle) or ""

    -- 1. Direct match on full title
    if qLower ~= "" and bagQuestItemsCache[qLower] then
        local c = bagQuestItemsCache[qLower]
        return c.link, c.icon, c.count
    end

    -- 2. Match if any cached tooltip line contains quest title
    if qLower ~= "" then
        for lineLower, data in pairs(bagQuestItemsCache) do
            if lineLower:find(qLower, 1, true) then
                return data.link, data.icon, data.count
            end
        end
    end

    -- 3. Match against quest objectives text (e.g. Darkshore Moonwell vials)
    if objectives and #objectives > 0 then
        for _, obj in ipairs(objectives) do
            if obj.text and obj.text ~= "" then
                local oLower = string_lower(obj.text)
                for lineLower, data in pairs(bagQuestItemsCache) do
                    if (data.name and oLower:find(string_lower(data.name), 1, true)) or oLower:find(lineLower, 1, true) then
                        return data.link, data.icon, data.count
                    end
                end
            end
        end
    end

    return nil
end

-- Static Sort Comparator State & Functions (Zero Closure Allocations)
local sortMode_active = "level"
local sortMoveCompleted_active = false
local sortActiveOnTop_active = true
local sortActiveQID_active = nil

local function QuestListComparator(a, b)
    if sortActiveOnTop_active and sortActiveQID_active then
        local isAActive = (a.questID == sortActiveQID_active)
        local isBActive = (b.questID == sortActiveQID_active)
        if isAActive ~= isBActive then
            return isAActive
        end
    end

    if sortMoveCompleted_active and (a.isComplete ~= b.isComplete) then
        return not a.isComplete
    end

    if sortMode_active == "zone" then
        local zoneA = tostring(a.zone or "")
        local zoneB = tostring(b.zone or "")
        if zoneA ~= zoneB then
            return zoneA < zoneB
        end
        local lvlA = tonumber(a.level) or 0
        local lvlB = tonumber(b.level) or 0
        if lvlA ~= lvlB then
            return lvlA < lvlB
        end
        return (a.questID or 0) < (b.questID or 0)
    else -- "level" (default)
        local lvlA = tonumber(a.level) or 0
        local lvlB = tonumber(b.level) or 0
        if lvlA ~= lvlB then
            return lvlA < lvlB
        end
        return (a.questID or 0) < (b.questID or 0)
    end
end

local function ZoneOrderComparator(zA, zB)
    if sortActiveOnTop_active and sortActiveQID_active then
        local listA = zoneMap[zA]
        local listB = zoneMap[zB]
        local hasActiveA = false
        if listA then
            for i = 1, #listA do
                if listA[i].questID == sortActiveQID_active then hasActiveA = true; break end
            end
        end
        local hasActiveB = false
        if listB then
            for i = 1, #listB do
                if listB[i].questID == sortActiveQID_active then hasActiveB = true; break end
            end
        end
        if hasActiveA ~= hasActiveB then
            return hasActiveA
        end
    end

    if sortMoveCompleted_active then
        local listA = zoneMap[zA]
        local listB = zoneMap[zB]
        local allCompleteA = listA and (#listA > 0)
        if listA then
            for i = 1, #listA do
                if not listA[i].isComplete then allCompleteA = false; break end
            end
        end
        local allCompleteB = listB and (#listB > 0)
        if listB then
            for i = 1, #listB do
                if not listB[i].isComplete then allCompleteB = false; break end
            end
        end
        if allCompleteA ~= allCompleteB then
            return not allCompleteA
        end
    end

    return (initialOrder[zA] or 0) < (initialOrder[zB] or 0)
end

local function ZoneQuestComparator(a, b)
    if sortActiveOnTop_active and sortActiveQID_active then
        local isAActive = (a.questID == sortActiveQID_active)
        local isBActive = (b.questID == sortActiveQID_active)
        if isAActive ~= isBActive then
            return isAActive
        end
    end
    if sortMoveCompleted_active and (a.isComplete ~= b.isComplete) then
        return not a.isComplete
    end
    local lvlA = tonumber(a.level) or 0
    local lvlB = tonumber(b.level) or 0
    if lvlA ~= lvlB then return lvlA < lvlB end
    return (a.questID or 0) < (b.questID or 0)
end

-- Collect Active & Watched Quests
function StandaloneTracker:GetTrackedQuests()
    ReleaseQuestEntries(cachedTrackedQuests)
    UpdatePlayerValidZones()
    local quests = cachedTrackedQuests
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    local activeZoneHeader = "General"

    for i = 1, numEntries do
        local title, level, suggestedGroup, isHeader, isCollapsed, isCompleteVal, frequency, questID
        if ns.GetQuestLogTitle then
            title, level, suggestedGroup, isHeader, isCollapsed, isCompleteVal, frequency, questID = ns.GetQuestLogTitle(i)
        elseif C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then
                title = info.title
                level = info.level
                suggestedGroup = info.suggestedGroup
                isHeader = info.isHeader
                isCollapsed = info.isCollapsed
                frequency = info.frequency
                questID = info.questID
                if info.isComplete == 1 or info.isComplete == true then
                    isCompleteVal = 1
                end
            end
        end

        if not title and GetQuestLogTitle then
            title, level, suggestedGroup, isHeader, isCollapsed, isCompleteVal, frequency, questID = GetQuestLogTitle(i)
        end

        if isHeader then
            activeZoneHeader = title or "General"
        elseif title and (questID or i) then
            questID = questID or i
            local isWatched = false
            if C_QuestLog and C_QuestLog.IsQuestWatched then
                isWatched = SafeCall(C_QuestLog.IsQuestWatched, questID) or false
            elseif C_QuestLog and C_QuestLog.GetQuestWatchType then
                local wt = SafeCall(C_QuestLog.GetQuestWatchType, questID)
                isWatched = (wt ~= nil and wt ~= 0 and wt ~= false)
            elseif IsQuestWatched then
                isWatched = SafeCall(IsQuestWatched, i) or false
            end

            -- If quest is actively watched in Blizzard's quest watch system, clear untracked state
            if isWatched and ns.db and ns.db.filtering and ns.db.filtering.untrackedQuests and ns.db.filtering.untrackedQuests[questID] then
                ns.db.filtering.untrackedQuests[questID] = nil
            end

            -- Filter mode check (all, zone, watched)
            local filterMode = ns.db and ns.db.filtering and ns.db.filtering.filterMode
            if not filterMode then
                filterMode = (ns.db and ns.db.filtering and ns.db.filtering.zoneOnly) and "zone" or "all"
            end

            local shouldInclude = true
            if ns.db and ns.db.filtering and ns.db.filtering.untrackedQuests and ns.db.filtering.untrackedQuests[questID] then
                shouldInclude = false
            elseif filterMode == "zone" then
                if not MatchesCurrentZone(activeZoneHeader, questID, i) then
                    shouldInclude = false
                end
            elseif filterMode == "watched" then
                shouldInclude = isWatched
            else
                -- "all" mode: show all quests from quest log
                shouldInclude = true
            end

            if shouldInclude then
                local entry = AcquireQuestEntry()

                -- Gather Objectives via ns.GetQuestObjectives or C_QuestLog or leaderboards
                local objectives = (ns.GetQuestObjectives and ns.GetQuestObjectives(questID, i, entry.objectives))
                    or (C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID))
                    or entry.objectives

                -- Determine if quest is failed
                local isFailed = false
                if isCompleteVal == -1 then
                    isFailed = true
                elseif ns.IsQuestFailed then
                    isFailed = ns.IsQuestFailed(questID, i, objectives)
                end

                -- Determine if quest is complete
                local isComplete = false
                if not isFailed then
                    if isCompleteVal == 1 or isCompleteVal == true then
                        isComplete = true
                    elseif ns.IsQuestComplete then
                        isComplete = ns.IsQuestComplete(questID, i, objectives)
                    else
                        if questID and C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then
                            isComplete = true
                        elseif GetQuestLogTitle then
                            local _, _, _, _, _, c = GetQuestLogTitle(i)
                            if c == 1 or c == true then isComplete = true end
                        end
                        if not isComplete and objectives and #objectives > 0 then
                            local allDone = true
                            for _, obj in ipairs(objectives) do
                                if not obj.finished then
                                    allDone = false
                                    break
                                end
                            end
                            if allDone then isComplete = true end
                        end
                    end
                end

                -- Check Quest Item via C_QuestLog
                local itemLink, itemTexture, numItems
                if C_QuestLog and C_QuestLog.GetQuestLogSpecialItemInfo then
                    itemLink, itemTexture, numItems = C_QuestLog.GetQuestLogSpecialItemInfo(questID)
                elseif GetQuestLogSpecialItemInfo then
                    itemLink, itemTexture, numItems = GetQuestLogSpecialItemInfo(i)
                end

                -- Standalone Fallback: Scan bags for quest items
                if not itemTexture then
                    local bLink, bTexture, bCount = FindQuestItemInBags(questID, title, objectives)
                    if bLink and bTexture then
                        itemLink, itemTexture, numItems = bLink, bTexture, bCount
                    end
                end

                -- Extract numeric itemID for cooldown tracking
                local itemID
                if itemLink and type(itemLink) == "string" then
                    itemID = tonumber(itemLink:match("item:(%d+)"))
                end

                -- Tag / Badge detection
                local isElite = false
                local isDungeon = false
                local isRaid = false
                local tagInfo = (C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)) or (GetQuestTagInfo and GetQuestTagInfo(i))
                if tagInfo then
                    if type(tagInfo) == "table" then
                        isElite = tagInfo.isElite or (tagInfo.tagID == 1)
                        isDungeon = (tagInfo.tagID == 81 or tagInfo.tagName == "Dungeon" or tagInfo.tagName == _G.DUNGEON)
                        isRaid = (tagInfo.tagID == 62 or tagInfo.tagName == "Raid" or tagInfo.tagName == _G.RAID)
                    elseif type(tagInfo) == "number" then
                        isElite = (tagInfo == 1)
                        isDungeon = (tagInfo == 81)
                        isRaid = (tagInfo == 62)
                    end
                end

                -- Parse questTag / suggestedGroup (in Classic Era, return #3 of GetQuestLogTitle is questTag e.g. "Dungeon", "Elite", "Raid")
                local numericGroup = 0
                if type(suggestedGroup) == "string" then
                    local sLower = suggestedGroup:lower()
                    if sLower == "dungeon" or suggestedGroup == _G.DUNGEON or sLower:find("dungeon") then
                        isDungeon = true
                    elseif sLower == "raid" or suggestedGroup == _G.RAID or sLower:find("raid") then
                        isRaid = true
                    elseif sLower == "elite" or suggestedGroup == _G.ELITE or sLower:find("elite") then
                        isElite = true
                    else
                        numericGroup = tonumber(suggestedGroup) or 0
                    end
                elseif type(suggestedGroup) == "number" then
                    numericGroup = suggestedGroup
                end

                entry.questLogIndex = i
                entry.questID = questID
                entry.title = title
                entry.level = tonumber(level) or 0
                entry.suggestedGroup = numericGroup
                entry.isElite = isElite
                entry.isDungeon = isDungeon
                entry.isRaid = isRaid
                entry.zone = activeZoneHeader
                entry.isFailed = isFailed
                entry.isComplete = isComplete
                entry.frequency = tonumber(frequency) or 1
                entry.objectives = objectives
                entry.itemLink = itemLink
                entry.itemTexture = itemTexture
                entry.itemID = itemID
                entry.numItems = tonumber(numItems) or 0
                entry.distance = 999999
                table_insert(quests, entry)
            end
        end
    end

    -- Sorting using static comparator (eliminates table/closure allocations per redraw)
    sortMode_active = (ns.db and ns.db.sorting and ns.db.sorting.mode) or "level"
    sortMoveCompleted_active = (ns.db and ns.db.sorting and ns.db.sorting.moveCompletedToBottom)
    sortActiveOnTop_active = not (ns.db and ns.db.sorting and ns.db.sorting.activeOnTop == false)
    sortActiveQID_active = ns.activeQuestID

    table_sort(quests, QuestListComparator)

    return quests
end

-- Helper: Render a single quest block and return its rendered height
local function RenderQuestBlock(content, qInfo, yOffset, lineSpacing)
    local block = AcquireQuestBlock(content)
    block:SetWidth(content:GetWidth())
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
    block:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOffset)
    if not block.questInfo then
        block.questInfo = {}
    else
        wipe(block.questInfo)
    end
    for k, v in pairs(qInfo) do
        block.questInfo[k] = v
    end
    block.header.questInfo = block.questInfo

    -- Collapsed State (Default is expanded; collapsed only if explicitly marked true)
    local questKey = qInfo.questID or qInfo.title
    local isCollapsed = ns.db and ns.db.collapsedQuests and ns.db.collapsedQuests[questKey]

    -- Anchor Quest Title across the full width of the header bar
    block.header:SetWidth(content:GetWidth())
    block.header:ClearAllPoints()
    block.header:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    block.header:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)

    local isWayfinderActive = (not ns.IsModuleEnabled or ns.IsModuleEnabled("wayfinder"))
    local showInlineArrow = isWayfinderActive and ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow and qInfo.questID and (qInfo.questID == ns.activeQuestID)
    local arrowPos = (ns.db and ns.db.wayfinder and ns.db.wayfinder.inlineArrowPosition) or "left"
    local inlineSize = (ns.db and ns.db.wayfinder and ns.db.wayfinder.inlineArrowSize) or 22

    local hasItem = (qInfo.itemTexture ~= nil and qInfo.itemTexture ~= "")
    local itemPlacement = (ns.db and ns.db.itemButtonPlacement) or "inside_right"
    local leftItemOffset = 0
    local rightItemOffset = (hasItem and itemPlacement == "inside_right") and -30 or 0

    block.header.title:ClearAllPoints()
    if showInlineArrow and block.header.wayfinderArrow then
        block.header.wayfinderArrow:SetSize(inlineSize, inlineSize)
        local arrowTex = (ns.WayfinderModule and ns.WayfinderModule.GetArrowTexture and ns.WayfinderModule:GetArrowTexture()) or "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW"
        block.header.wayfinderArrow:SetTexture(arrowTex)
        block.header.wayfinderArrow:ClearAllPoints()

        if arrowPos == "left" then
            block.header.wayfinderArrow:SetPoint("LEFT", block.header, "LEFT", leftItemOffset, 0)
            block.header.title:SetPoint("LEFT", block.header.wayfinderArrow, "RIGHT", 4, 0)
            block.header.title:SetPoint("RIGHT", block.header, "RIGHT", rightItemOffset, 0)
        else
            block.header.wayfinderArrow:SetPoint("RIGHT", block.header, "RIGHT", -2 + rightItemOffset, 0)
            block.header.title:SetPoint("TOPLEFT", block.header, "TOPLEFT", leftItemOffset, 0)
            block.header.title:SetPoint("RIGHT", block.header.wayfinderArrow, "LEFT", -4, 0)
        end
        block.header.wayfinderArrow:Show()

        if ns.WayfinderModule and ns.WayfinderModule.GetNavigationState then
            local nav = ns.WayfinderModule:GetNavigationState()
            if nav and nav.hasTarget then
                block.header.wayfinderArrow:SetRotation(nav.relativeAngle)
                block.header.wayfinderArrow:SetVertexColor(nav.r or 1.0, nav.g or 0.82, nav.b or 0.0, 1.0)
            else
                block.header.wayfinderArrow:SetRotation(0)
                block.header.wayfinderArrow:SetVertexColor(1.0, 0.82, 0.0, 0.85)
            end
        else
            block.header.wayfinderArrow:SetRotation(0)
            block.header.wayfinderArrow:SetVertexColor(1.0, 0.82, 0.0, 0.85)
        end
    else
        if block.header.wayfinderArrow then
            block.header.wayfinderArrow:Hide()
        end
        block.header.title:SetPoint("TOPLEFT", block.header, "TOPLEFT", leftItemOffset, 0)
        block.header.title:SetPoint("TOPRIGHT", block.header, "TOPRIGHT", rightItemOffset, 0)
    end
    block.header.title:SetWordWrap(true)
    block.header.title:SetJustifyH("LEFT")
    block.header.title:SetText(GetFormattedQuestTitle(qInfo))

    local titleSize = StandaloneTracker.titleSize or 13
    local titleHeight = math.max(titleSize + 6, math.ceil(block.header.title:GetStringHeight() + 2), showInlineArrow and (inlineSize + 2) or 0)
    block.header:SetHeight(titleHeight)
    local currentBlockHeight = titleHeight

    -- Map active block for dedicated item button positioning
    if qInfo.questID and StandaloneTracker.activeBlocks then
        StandaloneTracker.activeBlocks[qInfo.questID] = block
    end

    -- Objective Lines (Rendered only when expanded)
    if not isCollapsed then
        local prevAnchor = block.header
        local objIndent = 6 + leftItemOffset
        local objWidth = math.max(50, content:GetWidth() - objIndent - 6 + (rightItemOffset < 0 and rightItemOffset or 0))

        if qInfo.isFailed then
            local failedFs = AcquireObjectiveString(block)
            failedFs:ClearAllPoints()
            failedFs:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", objIndent, -lineSpacing)
            failedFs:SetWidth(objWidth)
            failedFs:SetWordWrap(true)
            failedFs:SetJustifyH("LEFT")
            failedFs:SetText("|cffff2020Quest Failed|r")
            currentBlockHeight = currentBlockHeight + math.ceil(failedFs:GetStringHeight()) + lineSpacing
            prevAnchor = failedFs
        else
            -- Prominent Countdown Timer line (when quest has an active timer)
            if ns.db and ns.db.showTimerInObjectives ~= false and ns.GetQuestTimeLeft then
                local tSec = ns.GetQuestTimeLeft(qInfo.questID, qInfo.questLogIndex)
                if tSec and tSec > 0 then
                    ns.hasActiveQuestTimer = true
                    local timerFs = AcquireObjectiveString(block)
                    timerFs:ClearAllPoints()
                    if prevAnchor == block.header then
                        timerFs:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", objIndent, -lineSpacing)
                    else
                        timerFs:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -lineSpacing)
                    end
                    timerFs:SetWidth(objWidth)
                    timerFs:SetWordWrap(true)
                    timerFs:SetJustifyH("LEFT")
                    local m = math_floor(tSec / 60)
                    local s = tSec % 60
                    timerFs:SetText(string_format("|cffffcc00 - Time Remaining: [%02d:%02d]|r", m, s))
                    local textHeight = math.ceil(timerFs:GetStringHeight())
                    currentBlockHeight = currentBlockHeight + textHeight + lineSpacing
                    prevAnchor = timerFs
                end
            end

            if qInfo.isComplete then
                local completeFs = AcquireObjectiveString(block)
                completeFs:ClearAllPoints()
                if prevAnchor == block.header then
                    completeFs:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", objIndent, -lineSpacing)
                else
                    completeFs:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -lineSpacing)
                end
                completeFs:SetWidth(objWidth)
                completeFs:SetWordWrap(true)
                completeFs:SetJustifyH("LEFT")
                completeFs:SetText("|cff00ff00Ready for turn-in|r")
                currentBlockHeight = currentBlockHeight + math.ceil(completeFs:GetStringHeight()) + lineSpacing
                prevAnchor = completeFs
            elseif qInfo.objectives and #qInfo.objectives > 0 then
                for objIdx, obj in ipairs(qInfo.objectives) do
                    local objFs = AcquireObjectiveString(block)
                    objFs:ClearAllPoints()
                    if prevAnchor == block.header then
                        objFs:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", objIndent, -lineSpacing)
                    else
                        objFs:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -lineSpacing)
                    end
                    objFs:SetWidth(objWidth)
                    objFs:SetWordWrap(true)
                    objFs:SetJustifyH("LEFT")

                    local colorCode = obj.finished and "|cff00ff00" or "|cffcccccc"
                    local lineText = obj.text or ""
                    objFs:SetText(colorCode .. " - " .. lineText .. "|r")

                    local textHeight = math.ceil(objFs:GetStringHeight())
                    currentBlockHeight = currentBlockHeight + textHeight + lineSpacing
                    prevAnchor = objFs
                end
            end
        end
    end

    block:SetHeight(currentBlockHeight)
    return currentBlockHeight
end

-- Refresh and Render Tracker Contents
function StandaloneTracker:UpdateTracker()
    local content = ns.Tracker and ns.Tracker:GetContentFrame()
    if not content then return end

    -- Avoid UI rebuild and frame Hide calls during combat lockdown to prevent ADDON_ACTION_BLOCKED
    if InCombatLockdown() then
        self.pendingTrackerUpdate = true
        return
    end

    if not self.activeBlocks then
        self.activeBlocks = {}
    else
        wipe(self.activeBlocks)
    end

    -- Reset previous active fontstrings, blocks, and zone headers
    for _, fs in ipairs(objectiveStrings) do fs:Hide() end
    for _, fs in ipairs(partyStrings) do fs:Hide() end
    for _, btn in ipairs(shareButtons) do btn:Hide() end
    for _, blk in ipairs(questBlocks) do blk:Hide() end
    for _, zh in ipairs(zoneHeaders) do zh:Hide() end

    -- Purge any stale or non-Blizzard timed quests before rendering
    if ns.PurgeInvalidTimerCache then
        ns.PurgeInvalidTimerCache()
    end

    local trackedQuests = self:GetTrackedQuests()
    local totalQuests = #trackedQuests

    -- Synchronize active countdown timer detection for live 1-second ticker
    local hasAnyActiveTimer = false
    if ns.GetQuestTimeLeft then
        for _, qInfo in ipairs(trackedQuests) do
            if not qInfo.isFailed then
                local tSec = ns.GetQuestTimeLeft(qInfo.questID, qInfo.questLogIndex)
                if tSec and tSec > 0 then
                    hasAnyActiveTimer = true
                    break
                end
            end
        end
    end
    ns.hasActiveQuestTimer = hasAnyActiveTimer

    -- Pre-render: Ensure active quest is resolved and synchronized before rendering headers
    local activeFound = false
    if ns.activeQuestID then
        for _, q in ipairs(trackedQuests) do
            if q.questID == ns.activeQuestID then
                activeFound = true
                break
            end
        end
        if not activeFound then
            -- Active quest is no longer in tracked list (completed, abandoned, or untracked)
            ns.activeQuestID = nil
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(0)
            end
            if ns.WayfinderModule and not (ns.WayfinderModule.IsCustomTarget and ns.WayfinderModule:IsCustomTarget()) then
                ns.WayfinderModule:ClearWaypoint(true)
            end
        end
    end
    if not activeFound and not ns.waypointExplicitlyCleared then
        if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
            local stID = C_SuperTrack.GetSuperTrackedQuestID()
            if stID and stID > 0 then
                for _, q in ipairs(trackedQuests) do
                    if q.questID == stID then
                        ns.activeQuestID = stID
                        activeFound = true
                        break
                    end
                end
            end
        end
    end

    if activeFound and ns.activeQuestID and ns.WayfinderModule and ns.WayfinderModule.SetQuestTarget then
        if not (ns.WayfinderModule.IsCustomTarget and ns.WayfinderModule:IsCustomTarget()) then
            ns.WayfinderModule:SetQuestTarget(ns.activeQuestID, true, false)
        end
    end

    local yOffset = 0
    local blockSpacing = 10
    local lineSpacing = 3
    local hCfg = (ns.db and ns.db.headers) or {}
    local showZones = (hCfg.showZoneHeaders ~= false)

    if showZones then
        -- Group tracked quests by zone using pooled tables to eliminate table allocation churn
        for z, list in pairs(zoneMap) do
            wipe(list)
            table_insert(zoneListPool, list)
            zoneMap[z] = nil
        end
        wipe(zoneOrder)
        wipe(initialOrder)

        for _, qInfo in ipairs(trackedQuests) do
            local z = qInfo.zone or "Other Quests"
            if not zoneMap[z] then
                local list = table_remove(zoneListPool) or {}
                zoneMap[z] = list
                table_insert(zoneOrder, z)
            end
            table_insert(zoneMap[z], qInfo)
        end

        sortMoveCompleted_active = (ns.db and ns.db.sorting and ns.db.sorting.moveCompletedToBottom)
        sortActiveOnTop_active = not (ns.db and ns.db.sorting and ns.db.sorting.activeOnTop == false)
        sortActiveQID_active = ns.activeQuestID

        for idx, zName in ipairs(zoneOrder) do
            initialOrder[zName] = idx
        end

        table_sort(zoneOrder, ZoneOrderComparator)

        for _, z in ipairs(zoneOrder) do
            local qList = zoneMap[z]
            local isZoneCollapsed = ns.db and ns.db.collapsedZones and ns.db.collapsedZones[z]

            table_sort(qList, ZoneQuestComparator)

            local zh = AcquireZoneHeader(content)
            zh.zoneName = z
            zh:SetWidth(content:GetWidth())
            zh:ClearAllPoints()
            zh:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
            zh:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOffset)

            local titleSize = self.titleSize or 13
            local zhHeight = math.max(22, titleSize + 6)
            zh:SetHeight(zhHeight)

            local borderRef = (ns.db and ns.db.backdrop and ns.db.backdrop.borderColor) or { r = 0.15, g = 0.15, b = 0.15, a = 0.9 }
            if ns.db and ns.db.backdrop and ns.db.backdrop.classColorBorder and ns.GetClassColor then
                local cc = ns.GetClassColor()
                if cc then
                    borderRef = { r = cc.r, g = cc.g, b = cc.b, a = borderRef.a or 0.9 }
                end
            end
            local zhColor = (hCfg.zoneHeaderColorShare and borderRef)
                or hCfg.zoneHeaderColor
                or { r = 1.0, g = 0.82, b = 0.0, a = 1.0 }

            local zhTexType = hCfg.zoneHeaderTexture or "gradient"
            if zhTexType == "none" then
                zh.bg:Hide()
            elseif zhTexType == "blizzard" then
                zh.bg:Show()
                if zh.bg.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Objective-Header") then
                    zh.bg:SetAtlas("Objective-Header")
                    zh.bg:SetVertexColor(1, 1, 1, zhColor.a or 0.8)
                else
                    zh.bg:SetTexture("Interface\\QuestFrame\\UI-QuestHeader")
                    zh.bg:SetVertexColor(zhColor.r, zhColor.g, zhColor.b, zhColor.a or 0.8)
                end
            elseif zhTexType == "flat" then
                zh.bg:Show()
                zh.bg:SetColorTexture(zhColor.r, zhColor.g, zhColor.b, (zhColor.a or 1.0) * 0.25)
            else -- "gradient"
                zh.bg:Show()
                if zh.bg.SetGradient and CreateColor then
                    zh.bg:SetColorTexture(1, 1, 1, 1)
                    zh.bg:SetGradient("HORIZONTAL",
                        CreateColor(zhColor.r, zhColor.g, zhColor.b, (zhColor.a or 1.0) * 0.35),
                        CreateColor(zhColor.r, zhColor.g, zhColor.b, 0))
                else
                    zh.bg:SetColorTexture(zhColor.r, zhColor.g, zhColor.b, 0.25)
                end
            end

            -- Setup collapse button text [-] / [+]
            zh.collapseText:SetWordWrap(false)
            zh.collapseText:SetJustifyH("CENTER")
            zh.collapseText:SetJustifyV("MIDDLE")
            zh.collapseText:SetText(isZoneCollapsed and "[+]" or "[-]")
            zh.collapseText:SetTextColor(zhColor.r, zhColor.g, zhColor.b)
            local collapseW = math.max(20, math.ceil(zh.collapseText:GetStringWidth() + 4))
            zh.collapseText:ClearAllPoints()
            zh.collapseText:SetPoint("LEFT", zh, "LEFT", 4, 0)
            zh.collapseText:SetWidth(collapseW)
            zh.collapseText:SetHeight(zhHeight)

            -- Format zone title with quest count inline: e.g. "Dun Morogh (3)"
            local zoneDisplayText = z
            if hCfg.showZoneCount ~= false then
                zoneDisplayText = string.format("%s |cffaaaaaa(%d)|r", z, #qList)
            end

            zh.title:ClearAllPoints()
            zh.title:SetPoint("LEFT", zh.collapseText, "RIGHT", 4, 0)
            zh.title:SetPoint("RIGHT", zh, "RIGHT", -6, 0)
            zh.title:SetJustifyH("LEFT")
            zh.title:SetJustifyV("MIDDLE")
            zh.title:SetWordWrap(true)
            zh.title:SetText(zoneDisplayText)
            zh.title:SetTextColor(zhColor.r, zhColor.g, zhColor.b)
            if zh.count then zh.count:Hide() end

            local textH = math.ceil(zh.title:GetStringHeight() + 6)
            if textH > zhHeight then
                zhHeight = textH
            end
            zh:SetHeight(zhHeight)
            zh.collapseText:SetHeight(zhHeight)

            yOffset = yOffset + zhHeight + 4

            if not isZoneCollapsed then
                for _, qInfo in ipairs(qList) do
                    local blockH = RenderQuestBlock(content, qInfo, yOffset, lineSpacing)
                    yOffset = yOffset + blockH + blockSpacing
                end
                yOffset = yOffset + 2
            end
        end
    else
        for _, qInfo in ipairs(trackedQuests) do
            local blockH = RenderQuestBlock(content, qInfo, yOffset, lineSpacing)
            yOffset = yOffset + blockH + blockSpacing
        end
    end

    -- Update tracker frame dimensions, header counter & filter buttons
    local _, numQuests = ns.GetNumQuestLogEntries()
    local maxQuests = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or MAX_QUESTLOG_QUESTS or 40
    ns.Tracker:UpdateHeight(yOffset)
    ns.Tracker:SetQuestCount(totalQuests, numQuests, maxQuests)
    ns.Tracker:UpdateFilterButtons()

    -- Update dedicated quest item button frame for active quest
    self:UpdateItemButton(trackedQuests)
    if C_Timer and C_Timer.After then
        C_Timer.After(0.01, function()
            if StandaloneTracker.UpdateItemButtonVisibility then
                StandaloneTracker:UpdateItemButtonVisibility()
            end
        end)
    end
end

-- Throttled Tracker Redraw Engine (Coalesces bursts of rapid quest/bag events into a single frame redraw)
local updateThrottleScheduled = false
function StandaloneTracker:RequestUpdate(immediate)
    if immediate then
        updateThrottleScheduled = false
        self:UpdateTracker()
        return
    end

    if updateThrottleScheduled then return end
    updateThrottleScheduled = true

    if C_Timer and C_Timer.After then
        C_Timer.After(0.04, function()
            updateThrottleScheduled = false
            StandaloneTracker:UpdateTracker()
        end)
    else
        updateThrottleScheduled = false
        self:UpdateTracker()
    end
end

-- Live 1-Second Countdown Ticker for Quest Timers
local timerTickerFrame = CreateFrame("Frame")
local timerTickerElapsed = 0
timerTickerFrame:SetScript("OnUpdate", function(self, elapsed)
    if ns.hasActiveQuestTimer then
        if ns.Tracker and ns.Tracker.frame and not ns.Tracker.frame:IsShown() then
            return
        end
        timerTickerElapsed = timerTickerElapsed + elapsed
        if timerTickerElapsed >= 1.0 then
            timerTickerElapsed = 0
            StandaloneTracker:RequestUpdate()
        end
    else
        timerTickerElapsed = 0
    end
end)

function StandaloneTracker:Initialize()
    HookBlizzardTracker()

    -- Hook quest watch modifications from Quest Log or Blizzard UI
    if hooksecurefunc then
        if C_QuestLog and C_QuestLog.AddQuestWatch then
            hooksecurefunc(C_QuestLog, "AddQuestWatch", function(questID)
                if questID and ns.db and ns.db.filtering and ns.db.filtering.untrackedQuests then
                    if ns.db.filtering.untrackedQuests[questID] then
                        ns.db.filtering.untrackedQuests[questID] = nil
                        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        StandaloneTracker:RequestUpdate()
                    end
                end
            end)
        end
        if C_QuestLog and C_QuestLog.RemoveQuestWatch then
            hooksecurefunc(C_QuestLog, "RemoveQuestWatch", function(questID)
                if questID and ns.db and ns.db.filtering then
                    ns.db.filtering.untrackedQuests = ns.db.filtering.untrackedQuests or {}
                    if not ns.db.filtering.untrackedQuests[questID] then
                        ns.db.filtering.untrackedQuests[questID] = true
                        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        StandaloneTracker:RequestUpdate()
                    end
                end
            end)
        end
        if _G.AddQuestWatch then
            hooksecurefunc("AddQuestWatch", function(questIndex)
                local qID = questIndex and (C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetInfo(questIndex) and C_QuestLog.GetInfo(questIndex).questID) or (GetQuestLogTitle and select(8, GetQuestLogTitle(questIndex)))
                if qID and ns.db and ns.db.filtering and ns.db.filtering.untrackedQuests then
                    if ns.db.filtering.untrackedQuests[qID] then
                        ns.db.filtering.untrackedQuests[qID] = nil
                        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        StandaloneTracker:RequestUpdate()
                    end
                end
            end)
        end
        if _G.RemoveQuestWatch then
            hooksecurefunc("RemoveQuestWatch", function(questIndex)
                local qID = questIndex and (C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetInfo(questIndex) and C_QuestLog.GetInfo(questIndex).questID) or (GetQuestLogTitle and select(8, GetQuestLogTitle(questIndex)))
                if qID and ns.db and ns.db.filtering then
                    ns.db.filtering.untrackedQuests = ns.db.filtering.untrackedQuests or {}
                    if not ns.db.filtering.untrackedQuests[qID] then
                        ns.db.filtering.untrackedQuests[qID] = true
                        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        StandaloneTracker:RequestUpdate()
                    end
                end
            end)
        end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            hooksecurefunc(C_SuperTrack, "SetSuperTrackedQuestID", function(questID)
                if ns.DataBarsModule and ns.DataBarsModule.UpdateTimerBar then
                    ns.DataBarsModule:UpdateTimerBar()
                end
            end)
        end
        if _G.SelectQuestLogEntry then
            hooksecurefunc("SelectQuestLogEntry", function(questIndex)
                if ns.DataBarsModule and ns.DataBarsModule.UpdateTimerBar then
                    ns.DataBarsModule:UpdateTimerBar()
                end
            end)
        end
        if _G.QuestMapFrame_OpenToQuestDetails then
            hooksecurefunc("QuestMapFrame_OpenToQuestDetails", function(questID)
                if ns.DataBarsModule and ns.DataBarsModule.UpdateTimerBar then
                    ns.DataBarsModule:UpdateTimerBar()
                end
            end)
        end
    end

    -- Register Blizzard Quest & System Events
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("QUEST_WATCH_UPDATE")
    eventFrame:RegisterEvent("QUEST_ACCEPTED")
    eventFrame:RegisterEvent("QUEST_REMOVED")
    pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_TURNED_IN")
    eventFrame:RegisterEvent("ZONE_CHANGED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("BAG_UPDATE")
    eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_TIMER_UPDATE")
    pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_TIMERS_UPDATE")
    if C_SuperTrack then
        pcall(eventFrame.RegisterEvent, eventFrame, "SUPER_TRACKING_CHANGED")
    end

    eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
        if event == "ADDON_LOADED" then
            if arg1 == "Blizzard_ObjectiveTracker" or arg1 == addonName then
                HookBlizzardTracker()
            end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            HookBlizzardTracker()
            C_Timer.After(0.2, HookBlizzardTracker)
            C_Timer.After(1.0, HookBlizzardTracker)
            C_Timer.After(3.0, HookBlizzardTracker)
        elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
            HookBlizzardTracker()
        end
        if event == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then
            return
        end
        if event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
            bagCacheDirty = true
            StandaloneTracker:RequestUpdate()
            return
        end
        if event == "BAG_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
            if StandaloneTracker.UpdateItemButtonCooldowns then
                StandaloneTracker:UpdateItemButtonCooldowns()
            elseif StandaloneTracker.UpdateItemButton and not InCombatLockdown() then
                StandaloneTracker:UpdateItemButton()
            end
            return
        end
        if event == "QUEST_TIMER_UPDATE" or event == "QUEST_TIMERS_UPDATE" then
            StandaloneTracker:RequestUpdate()
            return
        end
        if event == "QUEST_WATCH_UPDATE" then
            local qID = arg1
            if qID and qID < 1000 then
                local info = C_QuestLog and C_QuestLog.GetInfo and SafeCall(C_QuestLog.GetInfo, qID)
                if info and info.questID then
                    qID = info.questID
                elseif GetQuestLogTitle then
                    local _, _, _, _, _, _, _, foundQID = SafeCall(GetQuestLogTitle, qID)
                    if foundQID then qID = foundQID end
                end
            end
            if qID and ns.db and ns.db.filtering and ns.db.filtering.untrackedQuests then
                local isWatchedNow = false
                if C_QuestLog and C_QuestLog.IsQuestWatched then
                    isWatchedNow = SafeCall(C_QuestLog.IsQuestWatched, qID) or false
                elseif C_QuestLog and C_QuestLog.GetQuestWatchType then
                    local wt = SafeCall(C_QuestLog.GetQuestWatchType, qID)
                    isWatchedNow = (wt ~= nil and wt ~= 0 and wt ~= false)
                elseif IsQuestWatched and arg1 then
                    isWatchedNow = SafeCall(IsQuestWatched, arg1) or false
                end
                if isWatchedNow then
                    ns.db.filtering.untrackedQuests[qID] = nil
                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                end
            end
            StandaloneTracker:RequestUpdate()
            return
        end
        if event == "SUPER_TRACKING_CHANGED" then
            if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
                local stID = C_SuperTrack.GetSuperTrackedQuestID()
                if stID and stID > 0 and stID ~= ns.activeQuestID then
                    ns.activeQuestID = stID
                    ns.waypointExplicitlyCleared = false
                    if ns.DataBarsModule and ns.DataBarsModule.UpdateTimerBar then
                        ns.DataBarsModule:UpdateTimerBar()
                    end
                    StandaloneTracker:RequestUpdate(true)
                elseif (not stID or stID == 0) and ns.activeQuestID then
                    ns.activeQuestID = nil
                    ns.waypointExplicitlyCleared = true
                    if ns.WayfinderModule and not (ns.WayfinderModule.IsCustomTarget and ns.WayfinderModule:IsCustomTarget()) then
                        ns.WayfinderModule:ClearWaypoint(true)
                    end
                    if ns.DataBarsModule and ns.DataBarsModule.UpdateTimerBar then
                        ns.DataBarsModule:UpdateTimerBar()
                    end
                    StandaloneTracker:RequestUpdate(true)
                end
            end
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            StandaloneTracker.inCombat = true
            if ns.db and ns.db.filtering and ns.db.filtering.hideInCombat then
                local tf = ns.Tracker and ns.Tracker.frame
                if tf then
                    tf:Hide()
                end
                if StandaloneTracker.itemButtons then
                    for _, btn in ipairs(StandaloneTracker.itemButtons) do
                        btn:SetAlpha(0)
                    end
                    StandaloneTracker.pendingItemUpdate = true
                elseif StandaloneTracker.itemButton then
                    StandaloneTracker.itemButton:SetAlpha(0)
                    StandaloneTracker.pendingItemUpdate = true
                end
            end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            StandaloneTracker.inCombat = false
            HookBlizzardTracker()
            if ns.db and ns.db.filtering and ns.db.filtering.hideInCombat then
                if ns.Tracker and ns.Tracker.UpdateVisibility then
                    ns.Tracker:UpdateVisibility()
                elseif ns.Tracker and ns.Tracker.frame then
                    local tf = ns.Tracker.frame
                    local shouldHide = false
                    if ns.db and ns.db.filtering and ns.db.filtering.autoHideEmpty then
                        local quests = StandaloneTracker.GetTrackedQuests and StandaloneTracker:GetTrackedQuests()
                        if not quests or #quests == 0 then
                            shouldHide = true
                        end
                    end
                    if not shouldHide then
                        tf:Show()
                    end
                end
                if StandaloneTracker.itemButtons then
                    for _, btn in ipairs(StandaloneTracker.itemButtons) do
                        if btn.questID and btn.parentBlock and btn.parentBlock:IsVisible() then
                            btn:SetAlpha(1)
                        end
                    end
                elseif StandaloneTracker.itemButton then
                    StandaloneTracker.itemButton:SetAlpha(1)
                end
            end
            if StandaloneTracker.pendingTrackerUpdate then
                StandaloneTracker.pendingTrackerUpdate = false
                StandaloneTracker:RequestUpdate(true)
            elseif ns.db and ns.db.filtering and ns.db.filtering.hideInCombat then
                StandaloneTracker:RequestUpdate(true)
            end
            if StandaloneTracker.pendingItemUpdate then
                StandaloneTracker.pendingItemUpdate = false
                StandaloneTracker:UpdateItemButton()
            end
            return
        end
        if event == "QUEST_ACCEPTED" and arg1 then
            if ns.db and ns.db.filtering and ns.db.filtering.untrackedQuests then
                ns.db.filtering.untrackedQuests[arg1] = nil
            end
        end
        if (event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN") and arg1 then
            if ns.ClearQuestTimer then
                ns.ClearQuestTimer(arg1)
            end
            if ns.db and ns.db.collapsedQuests then
                ns.db.collapsedQuests[arg1] = nil
            end
            if ns.db and ns.db.filtering and ns.db.filtering.untrackedQuests then
                ns.db.filtering.untrackedQuests[arg1] = nil
            end
        end
        StandaloneTracker:RequestUpdate()
    end)

    -- Register internal callbacks
    ns:RegisterCallback("QUEST_DATA_CHANGED", function()
        StandaloneTracker:RequestUpdate()
    end)

    ns:RegisterCallback("SETTINGS_UPDATED", function()
        StandaloneTracker:RequestUpdate(true)
    end)

    -- Initial load and persistent Blizzard suppression
    C_Timer.After(0.1, HookBlizzardTracker)
    C_Timer.After(0.5, function()
        HookBlizzardTracker()
        StandaloneTracker:RequestUpdate(true)
    end)
    C_Timer.After(1.5, HookBlizzardTracker)
end

