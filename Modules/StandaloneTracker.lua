local addonName, ns = ...

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

local function SafeSetFont(fs, fontPath, fontSize, outline)
    if not fs or not fontPath then return end
    fontSize = tonumber(fontSize) or 11
    local clean = CleanOutline(outline)
    if clean then
        fs:SetFont(fontPath, fontSize, clean)
    else
        fs:SetFont(fontPath, fontSize)
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
    
    local activeMarker = ""
    if ns.activeQuestID and questInfo.questID == ns.activeQuestID then
        local showInline = ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow
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
    if showCompleteIcon and questInfo.isComplete then
        local iconSize = math.max(12, StandaloneTracker.titleSize or 13)
        completeMarker = string.format("|TInterface\\GossipFrame\\ActiveQuestIcon:%d:%d:0:0|t ", iconSize, iconSize)
    end

    local levelPrefix = ""
    if level > 0 then
        levelPrefix = string.format("[%d%s] ", level, badge)
    elseif badge ~= "" then
        levelPrefix = string.format("[%s] ", badge)
    end

    if useDifficultyColor and hexColor ~= "" then
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
    self:UpdateTracker()
end

-- Get or Create the Dedicated Quest Item Button Frame (BleakfiberQuestItemFrame)
function StandaloneTracker:GetOrCreateItemButton()
    if self.itemButton then return self.itemButton end

    local btn = CreateFrame("Button", "BleakfiberQuestItemFrame", UIParent, (BackdropTemplateMixin and "SecureActionButtonTemplate, BackdropTemplate") or "SecureActionButtonTemplate")
    btn:SetSize(28, 28)
    btn:SetFrameStrata("HIGH")
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
    btn.cooldown = CreateFrame("Cooldown", "BleakfiberQuestItemCooldown", btn, "CooldownFrameTemplate")
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
            ns.Print("|cff00c0ffQuest item button position saved.|r Hold Alt + Right-Click to re-dock.")
        end
    end)

    -- Alt + Right-Click to reset docking
    btn:HookScript("OnMouseDown", function(s, mouseButton)
        if mouseButton == "RightButton" and IsAltKeyDown() then
            if ns.db then
                ns.db.itemButtonPosition = nil
            end
            ns.Print("|cff00c0ffQuest item button re-docked to quest tracker.|r")
            StandaloneTracker:UpdateItemButton()
        end
    end)

    btn:Hide()
    self.itemButton = btn
    return btn
end

-- Update Dedicated Quest Item Button Frame for Active Quest
function StandaloneTracker:UpdateItemButton(trackedQuests)
    local btn = self:GetOrCreateItemButton()
    if not trackedQuests then
        trackedQuests = self:GetTrackedQuests()
    end

    -- If tracker is collapsed, hide item button
    if ns.Tracker and ns.Tracker.isCollapsed then
        if not InCombatLockdown() then
            btn:Hide()
        else
            btn:SetAlpha(0)
            self.pendingItemUpdate = true
        end
        return
    end

    -- 1. Identify the Active Quest (if any)
    local activeQuest
    if ns.activeQuestID then
        for _, q in ipairs(trackedQuests) do
            if q.questID == ns.activeQuestID then
                activeQuest = q
                break
            end
        end
    end

    if not activeQuest and not ns.waypointExplicitlyCleared then
        -- Check C_SuperTrack
        if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
            local stID = C_SuperTrack.GetSuperTrackedQuestID()
            if stID and stID > 0 then
                for _, q in ipairs(trackedQuests) do
                    if q.questID == stID then
                        activeQuest = q
                        ns.activeQuestID = stID
                        break
                    end
                end
            end
        end
    end

    -- 2. Determine which quest item to display: prioritize active quest, fallback to any tracked quest with an item
    local itemQuest = activeQuest
    if not (itemQuest and itemQuest.itemTexture) then
        for _, q in ipairs(trackedQuests) do
            if q.itemTexture then
                itemQuest = q
                break
            end
        end
    end

    if not (itemQuest and itemQuest.itemTexture) then
        if not InCombatLockdown() then
            btn:Hide()
        else
            btn:SetAlpha(0)
            self.pendingItemUpdate = true
        end
        return
    end

    activeQuest = itemQuest

    -- 3. Update Visual Elements (safe in combat)
    btn.icon:SetTexture(activeQuest.itemTexture)
    local count = tonumber(activeQuest.numItems) or 0
    btn.count:SetText(count > 1 and tostring(count) or "")
    btn.itemLink = activeQuest.itemLink
    btn.itemID = activeQuest.itemID
    btn.questTitle = activeQuest.title

    -- Cooldown Spinner
    if btn.cooldown and activeQuest.itemID then
        local start, duration, enable = 0, 0, 0
        if C_Item and C_Item.GetItemCooldown then
            start, duration, enable = C_Item.GetItemCooldown(activeQuest.itemID)
        elseif C_Container and C_Container.GetItemCooldown then
            start, duration, enable = C_Container.GetItemCooldown(activeQuest.itemID)
        elseif GetItemCooldown then
            start, duration, enable = GetItemCooldown(activeQuest.itemID)
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

    -- 4. Update Secure Attributes & Positioning (Protected actions - outside combat only)
    if InCombatLockdown() then
        self.pendingItemUpdate = true
        return
    end

    btn:SetAlpha(1)
    local itemAttr = activeQuest.itemLink or (activeQuest.itemID and ("item:" .. activeQuest.itemID)) or activeQuest.itemTexture
    btn:SetAttribute("type", "item")
    btn:SetAttribute("item", itemAttr)

    -- Position: Custom Saved Position or Docked to Left Side
    if ns.db and ns.db.itemButtonPosition then
        local pos = ns.db.itemButtonPosition
        btn:ClearAllPoints()
        btn:SetPoint(pos.point or "TOPLEFT", UIParent, pos.relativePoint or "TOPLEFT", pos.x or 0, pos.y or 0)
    else
        btn:ClearAllPoints()
        local activeBlock = self.activeBlocks and activeQuest.questID and self.activeBlocks[activeQuest.questID]
        local tracker = ns.Tracker and ns.Tracker.frame
        if activeBlock and activeBlock.header and activeBlock:IsVisible() then
            btn:SetPoint("RIGHT", activeBlock.header, "LEFT", -8, 0)
        elseif tracker and tracker:IsVisible() then
            btn:SetPoint("TOPRIGHT", tracker, "TOPLEFT", -8, -26)
        end
    end

    btn:Show()
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
        local tSize = StandaloneTracker.titleSize or 13
        local outline = StandaloneTracker.titleOutline
        SafeSetFont(btn.title, fPath, math.max(10, tSize - 1), outline)
        SafeSetFont(btn.collapseText, fPath, math.min(13, math.max(10, tSize - 2)), outline)

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
        local tSize = StandaloneTracker.titleSize or 13
        local outline = StandaloneTracker.titleOutline
        SafeSetFont(btn.title, fPath, math.max(10, tSize - 1), outline)
        SafeSetFont(btn.collapseText, fPath, math.max(9, tSize - 2), outline)
        SafeSetFont(btn.count, fPath, math.max(9, tSize - 3), outline)
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
            text = "Untrack Quest",
            notCheckable = true,
            func = function()
                if qInfo.questID and C_QuestLog and C_QuestLog.RemoveQuestWatch then
                    C_QuestLog.RemoveQuestWatch(qInfo.questID)
                    StandaloneTracker:UpdateTracker()
                elseif qInfo.questLogIndex and RemoveQuestWatch then
                    RemoveQuestWatch(qInfo.questLogIndex)
                    if QuestWatch_Update then QuestWatch_Update() end
                    StandaloneTracker:UpdateTracker()
                end
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

    local origSelected = SafeCall(GetQuestLogSelection)
    if questLogIndex and questLogIndex > 0 then
        SafeCall(SelectQuestLogEntry, questLogIndex)
    end
    if questID and C_QuestLog and C_QuestLog.SetSelectedQuest then
        SafeCall(C_QuestLog.SetSelectedQuest, questID)
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
    local numRewards = tonumber(SafeCall(GetNumQuestLogRewards)) or (questID and tonumber(SafeCall(GetNumQuestLogRewards, questID))) or 0
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
                count = tonumber(numItems) or 1,
                quality = tonumber(quality) or 1,
                itemLink = itemLink,
            })
        end
    end

    -- 6. Choice Item Rewards
    local numChoices = tonumber(SafeCall(GetNumQuestLogChoices)) or (questID and tonumber(SafeCall(GetNumQuestLogChoices, questID))) or 0
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
    if origSelected and origSelected > 0 then
        SafeCall(SelectQuestLogEntry, origSelected)
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
                    GameTooltip:AddLine("  • |cffffffff" .. xpStr .. "|r |cff00ff00XP|r", 0.9, 0.9, 0.9)
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

                if #rewards.choices > 0 then
                    GameTooltip:AddLine("  |cffffbb00Choose One:|r")
                    for _, choice in ipairs(rewards.choices) do
                        local icon = (choice.texture and ("|T" .. choice.texture .. ":14:14:0:0|t ")) or ""
                        local count = (choice.count and choice.count > 1 and (" |cffffffff(x" .. choice.count .. ")|r")) or ""
                        local itemText
                        if choice.itemLink then
                            itemText = choice.itemLink
                        else
                            local colorCode = (choice.quality and select(4, GetItemQualityColor(choice.quality))) or "|cffffffff"
                            itemText = colorCode .. (choice.name or "Item") .. "|r"
                        end
                        GameTooltip:AddLine("    " .. icon .. itemText .. count, 0.9, 0.9, 0.9)
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
                        GameTooltip:AddLine("    " .. icon .. itemText .. count, 0.9, 0.9, 0.9)
                    end
                end
            else
                GameTooltip:AddLine("  • |cff888888None (or discovery quest)|r", 0.6, 0.6, 0.6)
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
            break
        end
    end
    if not block then
        block = CreateFrame("Frame", nil, parent)
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

function StandaloneTracker:ApplyTypography(headerFontPath, objectiveFontPath, titleSize, objSize, headerOutline, objOutline)
    local hFont = headerFontPath
    local oFont = (type(objectiveFontPath) == "string" and objectiveFontPath) or headerFontPath
    local tSize = (type(objectiveFontPath) == "number" and objectiveFontPath) or (type(titleSize) == "number" and titleSize) or 13
    local oSize = (type(objSize) == "number" and objSize) or (type(titleSize) == "number" and titleSize) or 11
    local hOutline = CleanOutline((type(headerOutline) == "string" and headerOutline) or (type(objSize) == "string" and objSize) or "OUTLINE")
    local oOutline = CleanOutline((type(objOutline) == "string" and objOutline) or (hOutline == "THICKOUTLINE" and "OUTLINE") or nil)

    self.headerFontPath = hFont
    self.fontPath = hFont
    self.objectiveFontPath = oFont
    self.titleSize = tSize
    self.objSize = oSize
    self.titleOutline = hOutline
    self.objOutline = oOutline

    for _, block in ipairs(questBlocks) do
        if block.header and block.header.title then
            SafeSetFont(block.header.title, hFont, tSize, hOutline)
        end
    end

    for _, str in ipairs(objectiveStrings) do
        SafeSetFont(str, oFont, oSize, oOutline)
    end

    for _, str in ipairs(partyStrings) do
        SafeSetFont(str, oFont, math.max(9, oSize - 1), oOutline)
    end

    for _, btn in ipairs(shareButtons) do
        if btn.text then
            SafeSetFont(btn.text, oFont, math.max(9, oSize - 1), oOutline)
        end
    end

    for _, zh in ipairs(zoneHeaders) do
        SafeSetFont(zh.title, hFont, math.max(10, tSize - 1), hOutline)
        SafeSetFont(zh.collapseText, hFont, math.min(13, math.max(10, tSize - 2)), hOutline)
        SafeSetFont(zh.count, hFont, math.max(9, tSize - 3), hOutline)
    end

    self:UpdateTracker()
end

-- Helper: Robust Zone Matching (Checks Zone Header, SubZone, and Starter Heuristics)
local function MatchesCurrentZone(zoneHeader, questID, questLogIndex)
    local playerRealZone = (GetRealZoneText and GetRealZoneText()) or ""
    local playerZone = (GetZoneText and GetZoneText()) or ""
    local playerSubZone = (GetSubZoneText and GetSubZoneText()) or ""
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapInfo = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local mapName = (mapInfo and mapInfo.name) or ""

    local validZones = {}
    local function AddZone(z)
        if z and z ~= "" then
            table.insert(validZones, z)
        end
    end
    AddZone(playerRealZone)
    AddZone(playerZone)
    AddZone(playerSubZone)
    AddZone(mapName)

    if IsInInstance and IsInInstance() then
        local instName = GetInstanceInfo and GetInstanceInfo()
        if instName and instName ~= "" then
            AddZone(instName)
        end
    end

    local function Normalize(str)
        if not str or str == "" then return "" end
        local s = string.lower(str)
        s = s:gsub("^the%s+", "")
        s = s:match("^%s*(.-)%s*$") or s
        return s
    end

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

-- Helper to scan inventory bags for a quest item (fallback if GetQuestLogSpecialItemInfo is nil)
local function FindQuestItemInBags(targetQuestID, questTitle)
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
                if itemClassID == 12 or (Enum and Enum.ItemClass and itemClassID == Enum.ItemClass.Questitem) then
                    if questTitle and type(questTitle) == "string" and questTitle ~= "" then
                        local isMatch = false
                        if C_TooltipInfo and C_TooltipInfo.GetBagItem then
                            local data = C_TooltipInfo.GetBagItem(bag, slot)
                            if data and data.lines then
                                for _, line in ipairs(data.lines) do
                                    if line.leftText and line.leftText:find(questTitle, 1, true) then
                                        isMatch = true
                                        break
                                    end
                                end
                            end
                        end
                        if isMatch then
                            return hyperlink, icon, stackCount
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Collect Active & Watched Quests
function StandaloneTracker:GetTrackedQuests()
    local quests = {}
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    local activeZoneHeader = "General"

    for i = 1, numEntries do
        local title, level, suggestedGroup, isHeader, isCollapsed, isCompleteVal, frequency, questID
        if C_QuestLog and C_QuestLog.GetInfo then
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
            if C_QuestLog and C_QuestLog.GetQuestWatchType then
                isWatched = (C_QuestLog.GetQuestWatchType(questID) ~= nil)
            elseif IsQuestWatched then
                isWatched = IsQuestWatched(i)
            end

            -- Filter mode check (all, zone, watched)
            local filterMode = ns.db and ns.db.filtering and ns.db.filtering.filterMode
            if not filterMode then
                filterMode = (ns.db and ns.db.filtering and ns.db.filtering.zoneOnly) and "zone" or "all"
            end

            local shouldInclude = true
            if filterMode == "zone" then
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
                -- Gather Objectives via ns.GetQuestObjectives or C_QuestLog or leaderboards
                local objectives = (ns.GetQuestObjectives and ns.GetQuestObjectives(questID, i))
                    or (C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID))
                    or {}

                -- Determine if quest is complete
                local isComplete = false
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

                -- Check Quest Item via C_QuestLog
                local itemLink, itemTexture, numItems
                if C_QuestLog and C_QuestLog.GetQuestLogSpecialItemInfo then
                    itemLink, itemTexture, numItems = C_QuestLog.GetQuestLogSpecialItemInfo(questID)
                elseif GetQuestLogSpecialItemInfo then
                    itemLink, itemTexture, numItems = GetQuestLogSpecialItemInfo(i)
                end

                -- Standalone Fallback: Scan bags for quest items
                if not itemTexture then
                    local bLink, bTexture, bCount = FindQuestItemInBags(questID, title)
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

                table.insert(quests, {
                    questLogIndex = i,
                    questID = questID,
                    title = title,
                    level = tonumber(level) or 0,
                    suggestedGroup = numericGroup,
                    isElite = isElite,
                    isDungeon = isDungeon,
                    isRaid = isRaid,
                    zone = activeZoneHeader,
                    isComplete = isComplete,
                    frequency = tonumber(frequency) or 1,
                    objectives = objectives,
                    itemLink = itemLink,
                    itemTexture = itemTexture,
                    itemID = itemID,
                    numItems = tonumber(numItems) or 0,
                    distance = 999999, -- Default fallback distance
                })
            end
        end
    end

    -- Sorting
    local sortMode = (ns.db and ns.db.sorting and ns.db.sorting.mode) or "level"
    local moveCompleted = (ns.db and ns.db.sorting and ns.db.sorting.moveCompletedToBottom)
    local activeOnTop = not (ns.db and ns.db.sorting and ns.db.sorting.activeOnTop == false)
    local activeQID = ns.activeQuestID

    table.sort(quests, function(a, b)
        if activeOnTop and activeQID then
            local isAActive = (a.questID == activeQID)
            local isBActive = (b.questID == activeQID)
            if isAActive ~= isBActive then
                return isAActive
            end
        end

        if moveCompleted and (a.isComplete ~= b.isComplete) then
            return not a.isComplete
        end

        if sortMode == "zone" then
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
    end)

    return quests
end

-- Helper: Render a single quest block and return its rendered height
local function RenderQuestBlock(content, qInfo, yOffset, lineSpacing)
    local block = AcquireQuestBlock(content)
    block:SetWidth(content:GetWidth())
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
    block:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOffset)
    block.header.questInfo = qInfo
    block.questInfo = qInfo

    -- Collapsed State (Default is expanded; collapsed only if explicitly marked true)
    local questKey = qInfo.questID or qInfo.title
    local isCollapsed = ns.db and ns.db.collapsedQuests and ns.db.collapsedQuests[questKey]

    -- Anchor Quest Title across the full width of the header bar
    block.header:SetWidth(content:GetWidth())
    block.header:ClearAllPoints()
    block.header:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    block.header:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)

    local showInlineArrow = ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow and qInfo.questID and (qInfo.questID == ns.activeQuestID)
    local arrowPos = (ns.db and ns.db.wayfinder and ns.db.wayfinder.inlineArrowPosition) or "left"
    local inlineSize = (ns.db and ns.db.wayfinder and ns.db.wayfinder.inlineArrowSize) or 22

    block.header.title:ClearAllPoints()
    if showInlineArrow and block.header.wayfinderArrow then
        block.header.wayfinderArrow:SetSize(inlineSize, inlineSize)
        local arrowTex = (ns.WayfinderModule and ns.WayfinderModule.GetArrowTexture and ns.WayfinderModule:GetArrowTexture()) or "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW"
        block.header.wayfinderArrow:SetTexture(arrowTex)
        block.header.wayfinderArrow:ClearAllPoints()

        if arrowPos == "left" then
            block.header.wayfinderArrow:SetPoint("LEFT", block.header, "LEFT", 0, 0)
            block.header.title:SetPoint("LEFT", block.header.wayfinderArrow, "RIGHT", 4, 0)
            block.header.title:SetPoint("RIGHT", block.header, "RIGHT", 0, 0)
        else
            block.header.wayfinderArrow:SetPoint("RIGHT", block.header, "RIGHT", -2, 0)
            block.header.title:SetPoint("TOPLEFT", block.header, "TOPLEFT", 0, 0)
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
        block.header.title:SetPoint("TOPLEFT", block.header, "TOPLEFT", 0, 0)
        block.header.title:SetPoint("TOPRIGHT", block.header, "TOPRIGHT", 0, 0)
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
        local objIndent = 6
        local objWidth = math.max(50, content:GetWidth() - objIndent - 6)

        if qInfo.isComplete then
            local completeFs = AcquireObjectiveString(block)
            completeFs:ClearAllPoints()
            completeFs:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", objIndent, -lineSpacing)
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
                objFs:SetText(colorCode .. " - " .. (obj.text or "") .. "|r")

                local textHeight = math.ceil(objFs:GetStringHeight())
                currentBlockHeight = currentBlockHeight + textHeight + lineSpacing
                prevAnchor = objFs
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

    self.activeBlocks = {}

    -- Reset previous active fontstrings, blocks, and zone headers
    for _, fs in ipairs(objectiveStrings) do fs:Hide() end
    for _, fs in ipairs(partyStrings) do fs:Hide() end
    for _, btn in ipairs(shareButtons) do btn:Hide() end
    for _, blk in ipairs(questBlocks) do blk:Hide() end
    for _, zh in ipairs(zoneHeaders) do zh:Hide() end

    local trackedQuests = self:GetTrackedQuests()
    local totalQuests = #trackedQuests

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
        -- Group tracked quests by zone
        local zoneMap = {}
        local zoneOrder = {}
        for _, qInfo in ipairs(trackedQuests) do
            local z = qInfo.zone or "Other Quests"
            if not zoneMap[z] then
                zoneMap[z] = {}
                table.insert(zoneOrder, z)
            end
            table.insert(zoneMap[z], qInfo)
        end

        local moveCompleted = (ns.db and ns.db.sorting and ns.db.sorting.moveCompletedToBottom)
        local activeOnTop = not (ns.db and ns.db.sorting and ns.db.sorting.activeOnTop == false)
        local activeQID = ns.activeQuestID

        local initialOrder = {}
        for idx, zName in ipairs(zoneOrder) do
            initialOrder[zName] = idx
        end

        table.sort(zoneOrder, function(zA, zB)
            if activeOnTop and activeQID then
                local listA = zoneMap[zA] or {}
                local listB = zoneMap[zB] or {}
                local hasActiveA = false
                for _, q in ipairs(listA) do
                    if q.questID == activeQID then hasActiveA = true; break end
                end
                local hasActiveB = false
                for _, q in ipairs(listB) do
                    if q.questID == activeQID then hasActiveB = true; break end
                end
                if hasActiveA ~= hasActiveB then
                    return hasActiveA
                end
            end

            if moveCompleted then
                local listA = zoneMap[zA] or {}
                local listB = zoneMap[zB] or {}
                local allCompleteA = (#listA > 0)
                for _, q in ipairs(listA) do
                    if not q.isComplete then
                        allCompleteA = false
                        break
                    end
                end
                local allCompleteB = (#listB > 0)
                for _, q in ipairs(listB) do
                    if not q.isComplete then
                        allCompleteB = false
                        break
                    end
                end
                if allCompleteA ~= allCompleteB then
                    return not allCompleteA
                end
            end

            return (initialOrder[zA] or 0) < (initialOrder[zB] or 0)
        end)

        for _, z in ipairs(zoneOrder) do
            local qList = zoneMap[z]
            local isZoneCollapsed = ns.db and ns.db.collapsedZones and ns.db.collapsedZones[z]

            table.sort(qList, function(a, b)
                if activeOnTop and activeQID then
                    local isAActive = (a.questID == activeQID)
                    local isBActive = (b.questID == activeQID)
                    if isAActive ~= isBActive then
                        return isAActive
                    end
                end
                if moveCompleted and (a.isComplete ~= b.isComplete) then
                    return not a.isComplete
                end
                local lvlA = tonumber(a.level) or 0
                local lvlB = tonumber(b.level) or 0
                if lvlA ~= lvlB then return lvlA < lvlB end
                return (a.questID or 0) < (b.questID or 0)
            end)

            local zh = AcquireZoneHeader(content)
            zh.zoneName = z
            zh:SetWidth(content:GetWidth())
            zh:ClearAllPoints()
            zh:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
            zh:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOffset)

            local titleSize = self.titleSize or 13
            local zhHeight = math.max(22, titleSize + 6)
            zh:SetHeight(zhHeight)

            local zhColor = (hCfg.zoneHeaderColorShare and (ns.db.backdrop and ns.db.backdrop.borderColor))
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
end

function StandaloneTracker:Initialize()
    HookBlizzardTracker()

    -- Register Blizzard Quest & System Events
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("QUEST_WATCH_UPDATE")
    eventFrame:RegisterEvent("QUEST_ACCEPTED")
    eventFrame:RegisterEvent("QUEST_REMOVED")
    eventFrame:RegisterEvent("ZONE_CHANGED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("BAG_UPDATE")
    eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    if C_SuperTrack then
        pcall(eventFrame.RegisterEvent, eventFrame, "SUPER_TRACKING_CHANGED")
    end

    eventFrame:SetScript("OnEvent", function(self, event, arg1)
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
        if event == "BAG_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
            if StandaloneTracker.UpdateItemButton then
                StandaloneTracker:UpdateItemButton()
            end
            return
        end
        if event == "SUPER_TRACKING_CHANGED" then
            if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
                local stID = C_SuperTrack.GetSuperTrackedQuestID()
                if stID and stID > 0 and stID ~= ns.activeQuestID then
                    ns.activeQuestID = stID
                    ns.waypointExplicitlyCleared = false
                    StandaloneTracker:UpdateTracker()
                elseif (not stID or stID == 0) and ns.activeQuestID then
                    ns.activeQuestID = nil
                    ns.waypointExplicitlyCleared = true
                    if ns.WayfinderModule and not (ns.WayfinderModule.IsCustomTarget and ns.WayfinderModule:IsCustomTarget()) then
                        ns.WayfinderModule:ClearWaypoint(true)
                    end
                    StandaloneTracker:UpdateTracker()
                end
            end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            HookBlizzardTracker()
            if StandaloneTracker.pendingTrackerUpdate then
                StandaloneTracker.pendingTrackerUpdate = false
                StandaloneTracker:UpdateTracker()
            end
            if StandaloneTracker.pendingItemUpdate then
                StandaloneTracker.pendingItemUpdate = false
                StandaloneTracker:UpdateItemButton()
            end
            return
        end
        if event == "QUEST_REMOVED" and arg1 and ns.db and ns.db.collapsedQuests then
            ns.db.collapsedQuests[arg1] = nil
        end
        StandaloneTracker:UpdateTracker()
    end)

    -- Register internal callbacks
    ns:RegisterCallback("QUEST_DATA_CHANGED", function()
        StandaloneTracker:UpdateTracker()
    end)

    ns:RegisterCallback("SETTINGS_UPDATED", function()
        StandaloneTracker:UpdateTracker()
    end)

    -- Initial load and persistent Blizzard suppression
    C_Timer.After(0.1, HookBlizzardTracker)
    C_Timer.After(0.5, function()
        HookBlizzardTracker()
        StandaloneTracker:UpdateTracker()
    end)
    C_Timer.After(1.5, HookBlizzardTracker)
end

