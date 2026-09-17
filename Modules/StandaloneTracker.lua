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

-- Context Menu Frame for Quest Actions
local questContextMenu = CreateFrame("Frame", "BleakfiberQuestContextMenu", UIParent, "UIDropDownMenuTemplate")

-- Helper: Hide Default Blizzard Quest Watch Frame
-- Helper: Hide Default Blizzard Quest Watch / Objective Tracker Frame (Supports Classic & Modern UI Presets)
local function HookBlizzardTracker()
    if QuestWatchFrame then
        QuestWatchFrame:Hide()
        QuestWatchFrame:HookScript("OnShow", function(self)
            self:Hide()
        end)
    end
    if ObjectiveTrackerFrame then
        ObjectiveTrackerFrame:Hide()
        ObjectiveTrackerFrame:HookScript("OnShow", function(self)
            self:Hide()
        end)
    end
end

-- Helper: Format Quest Title with Level, Difficulty Color and Badges
local function GetFormattedQuestTitle(questInfo)
    local level = tonumber(questInfo.level) or 0
    local title = questInfo.title or "Unknown Quest"
    local color = { r = 1, g = 1, b = 1 }
    local db = ns.db
    if not (db and db.fonts and db.fonts.colorDifficulty == false) then
        color = (GetQuestDifficultyColor and GetQuestDifficultyColor(level)) or color
    end
    
    local hexColor = string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)

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
    
    return string.format("%s[%d%s]|r %s%s", hexColor, level, badge, title, tag)
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
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        if StandaloneTracker.fontPath then
            fs:SetFont(StandaloneTracker.fontPath, StandaloneTracker.objSize or 11, StandaloneTracker.objOutline or "")
        end
        table.insert(objectiveStrings, fs)
    else
        if StandaloneTracker.fontPath then
            fs:SetFont(StandaloneTracker.fontPath, StandaloneTracker.objSize or 11, StandaloneTracker.objOutline or "")
        end
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
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        if StandaloneTracker.fontPath then
            fs:SetFont(StandaloneTracker.fontPath, math.max(9, (StandaloneTracker.objSize or 11) - 1), StandaloneTracker.objOutline or "")
        end
        table.insert(partyStrings, fs)
    else
        if StandaloneTracker.fontPath then
            fs:SetFont(StandaloneTracker.fontPath, math.max(9, (StandaloneTracker.objSize or 11) - 1), StandaloneTracker.objOutline or "")
        end
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
    if not btn then
        btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(14)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("LEFT", btn, "LEFT", 0, 0)
        btn.text:SetJustifyH("LEFT")
        if StandaloneTracker.fontPath then
            btn.text:SetFont(StandaloneTracker.fontPath, math.max(9, (StandaloneTracker.objSize or 11) - 1), StandaloneTracker.objOutline or "")
        end
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
        if StandaloneTracker.fontPath then
            btn.text:SetFont(StandaloneTracker.fontPath, math.max(9, (StandaloneTracker.objSize or 11) - 1), StandaloneTracker.objOutline or "")
        end
    end
    return btn
end

-- Acquire or create a Quest Item Button
local function AcquireItemButton(parent)
    local btn
    for _, b in ipairs(itemButtons) do
        if not b:IsShown() then
            btn = b
            btn:SetParent(parent)
            btn:Show()
            break
        end
    end
    if not btn then
        local btnIndex = #itemButtons + 1
        btn = CreateFrame("Button", "BleakfiberQuestItemButton" .. btnIndex, parent, "SecureActionButtonTemplate")
        btn:SetSize(22, 22)
        btn:RegisterForClicks("AnyUp", "AnyDown")
        
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints(btn)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        btn.cooldown:SetAllPoints(btn)

        btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
        btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)

        btn:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if type(self.itemLink) == "string" and self.itemLink:find("|Hitem:") then
                    GameTooltip:SetHyperlink(self.itemLink)
                else
                    GameTooltip:SetText("Quest Item", 1, 1, 1)
                end
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        table.insert(itemButtons, btn)
    end
    return btn
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

        if StandaloneTracker.fontPath then
            local fPath = StandaloneTracker.fontPath
            local tSize = StandaloneTracker.titleSize or 13
            local outline = StandaloneTracker.titleOutline or ""
            btn.title:SetFont(fPath, math.max(10, tSize - 1), outline)
            btn.collapseText:SetFont(fPath, math.min(13, math.max(10, tSize - 2)), outline)
        end

        btn:SetScript("OnClick", function(self)
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
        if StandaloneTracker.fontPath then
            local fPath = StandaloneTracker.fontPath
            local tSize = StandaloneTracker.titleSize or 13
            local outline = StandaloneTracker.titleOutline or ""
            btn.title:SetFont(fPath, math.max(10, tSize - 1), outline)
            btn.collapseText:SetFont(fPath, math.max(9, tSize - 2), outline)
            btn.count:SetFont(fPath, math.max(9, tSize - 3), outline)
        end
    end
    return btn
end

-- Waypoint navigation helper (TomTom)
local function SetQuestWaypoint(qInfo)
    if not qInfo then return end
    local questID = qInfo.questID
    local title = qInfo.title or "Quest"

    -- Direct TomTom if user has C_QuestLog or C_Map waypoint
    if _G.TomTom and _G.TomTom.AddWaypoint and C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        if C_QuestLog and C_QuestLog.GetNextWaypoint then
            local ok, wX, wY = pcall(C_QuestLog.GetNextWaypoint, questID)
            if ok and wX and wY and mapID then
                local tx = (wX > 1) and (wX / 100) or wX
                local ty = (wY > 1) and (wY / 100) or wY
                local setOk = pcall(_G.TomTom.AddWaypoint, _G.TomTom, mapID, tx, ty, {
                    title = title,
                    persistent = false,
                    minimap = true,
                    world = true,
                })
                if setOk then
                    ns.Print("TomTom waypoint set for " .. title)
                    return
                end
            end
        end
    end

    -- Explanatory message if coordinates cannot be resolved
    if not _G.TomTom then
        ns.Print("TomTom is not installed or enabled.")
    else
        ns.Print("Could not find map coordinates for " .. title .. ".")
    end
end

-- Open rich dropdown context menu for a quest
function StandaloneTracker:OpenQuestContextMenu(anchor, qInfo)
    if not qInfo then return end

    local menu = {
        { text = "|cff00c0ff" .. (qInfo.title or "Quest Actions") .. "|r", isTitle = true, notCheckable = true },
        {
            text = "Copy Wowhead URL",
            notCheckable = true,
            func = function()
                if qInfo.questID and ns.Config and ns.Config.ShowCopyDialog then
                    local url = string.format("https://www.wowhead.com/classic/quest=%d", qInfo.questID)
                    ns.Config:ShowCopyDialog(url, qInfo.title)
                end
            end,
        },
        {
            text = "Show in Quest Log",
            notCheckable = true,
            func = function()
                if qInfo.questLogIndex then
                if qInfo.questLogIndex and QuestLogFrame then
                    ShowUIPanel(QuestLogFrame)
                    SelectQuestLogEntry(qInfo.questLogIndex)
                    if QuestLog_Update then QuestLog_Update() end
                elseif qInfo.questID and QuestMapFrame_OpenToQuestDetails then
                    QuestMapFrame_OpenToQuestDetails(qInfo.questID)
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
            text = "Set Waypoint (TomTom)",
            notCheckable = true,
            func = function()
                SetQuestWaypoint(qInfo)
            end,
        },
        {
            text = "Untrack Quest",
            notCheckable = true,
            func = function()
                if qInfo.questLogIndex and RemoveQuestWatch then
                    RemoveQuestWatch(qInfo.questLogIndex)
                    if QuestWatch_Update then QuestWatch_Update() end
                    StandaloneTracker:UpdateTracker()
                elseif qInfo.questID and C_QuestLog and C_QuestLog.RemoveQuestWatch then
                    C_QuestLog.RemoveQuestWatch(qInfo.questID)
                    StandaloneTracker:UpdateTracker()
                end
            end,
        },
        {
            text = "|cffff4444Abandon Quest|r",
            notCheckable = true,
            func = function()
                if qInfo.questLogIndex and SelectQuestLogEntry and SetAbandonQuest then
                    SelectQuestLogEntry(qInfo.questLogIndex)
                    SetAbandonQuest()
                    local items = GetAbandonQuestItems and GetAbandonQuestItems()
                    if items then
                        StaticPopup_Hide("ABANDON_QUEST")
                        StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", qInfo.title, items)
                    else
                        StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
                        StaticPopup_Show("ABANDON_QUEST", qInfo.title)
                    end
                end
            end,
        },
        { text = "Cancel", notCheckable = true, func = function() end },
    }

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

        -- Header Button for Click/Hover
        local header = CreateFrame("Button", nil, block)
        block.header = header
        local titleSize = StandaloneTracker.titleSize or 13
        header:SetHeight(titleSize + 6)
        header:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)
        header:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        -- Quest Title
        local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header.title = title
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
        title:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(true)
        if StandaloneTracker.fontPath then
            title:SetFont(StandaloneTracker.fontPath, titleSize, StandaloneTracker.titleOutline or "OUTLINE")
        end

        -- Highlight Texture on mouseover
        local hl = header:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(header)
        hl:SetColorTexture(1, 1, 1, 0.08)

        -- Click Actions: Left = Collapse/Expand, Ctrl+Left = QuestLog, Shift+Left = ChatLink, Right = Context Menu, Shift+Right = Wowhead URL
        header:SetScript("OnClick", function(self, mouseButton)
            local qInfo = self.questInfo
            if not qInfo then return end

            if mouseButton == "LeftButton" then
                if IsModifiedClick("CHATLINK") and qInfo.questID then
                    local link = GetQuestLink and GetQuestLink(qInfo.questID)
                    if link then
                        ChatEdit_InsertLink(link)
                    end
                elseif IsControlKeyDown() then
                    if qInfo.questLogIndex then
                        ShowUIPanel(QuestLogFrame)
                        SelectQuestLogEntry(qInfo.questLogIndex)
                        if QuestLog_Update then QuestLog_Update() end
                    end
                else
                    local questKey = qInfo.questID or qInfo.title
                    if questKey and ns.db then
                        ns.db.collapsedQuests = ns.db.collapsedQuests or {}
                        ns.db.collapsedQuests[questKey] = not ns.db.collapsedQuests[questKey]
                        StandaloneTracker:UpdateTracker()
                    end
                end
            elseif mouseButton == "RightButton" then
                if IsAltKeyDown() then
                    if ns.Config then ns.Config:ToggleConfigFrame() end
                elseif IsShiftKeyDown() then
                    -- Shift + Right-Click: Direct Wowhead URL Dialog
                    if qInfo.questID then
                        local url = string.format("https://www.wowhead.com/classic/quest=%d", qInfo.questID)
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
            local qInfo = self.questInfo
            if not qInfo then return end
            local questKey = qInfo.questID or qInfo.title
            local isCollapsed = ns.db and ns.db.collapsedQuests and ns.db.collapsedQuests[questKey]

            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(qInfo.title or "Quest", 1, 0.82, 0)
            GameTooltip:AddLine("|cffaaaaaaLeft-Click: " .. (isCollapsed and "Expand Quest" or "Collapse Quest") .. "|r", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("|cffaaaaaaCtrl + Left-Click: Open in Quest Log|r", 0.6, 0.6, 0.6)
            GameTooltip:AddLine("|cffaaaaaaShift + Left-Click: Link in Chat|r", 0.6, 0.6, 0.6)
            GameTooltip:AddLine("|cffaaaaaaRight-Click: Quest Actions Menu|r", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("|cff00c0ffShift + Right-Click: Copy Wowhead URL|r", 0.2, 0.8, 1)
            GameTooltip:AddLine("|cff00ff00Alt + Right-Click: Open Settings|r", 0.2, 1, 0.2)
            GameTooltip:Show()
        end)

        header:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        block.activeObjectives = {}
        table.insert(questBlocks, block)
    end
    return block
end

function StandaloneTracker:ApplyTypography(fontPath, titleSize, objSize, outline)
    self.fontPath = fontPath
    self.titleSize = titleSize
    self.objSize = objSize
    self.titleOutline = outline
    self.objOutline = (outline == "THICKOUTLINE" and "OUTLINE") or ""

    for _, block in ipairs(questBlocks) do
        if block.header and block.header.title then
            block.header.title:SetFont(fontPath, titleSize, outline)
        end
    end

    for _, str in ipairs(objectiveStrings) do
        str:SetFont(fontPath, objSize, self.objOutline)
    end

    for _, str in ipairs(partyStrings) do
        str:SetFont(fontPath, math.max(9, objSize - 1), self.objOutline)
    end

    for _, btn in ipairs(shareButtons) do
        if btn.text then
            btn.text:SetFont(fontPath, math.max(9, objSize - 1), self.objOutline)
        end
    end

    for _, zh in ipairs(zoneHeaders) do
        if zh.title then
            zh.title:SetFont(fontPath, math.max(10, titleSize - 1), outline)
        end
        if zh.collapseText then
            zh.collapseText:SetFont(fontPath, math.min(13, math.max(10, titleSize - 2)), outline)
        end
        if zh.count then
            zh.count:SetFont(fontPath, math.max(9, titleSize - 3), outline)
        end
    end

    self:UpdateTracker()
end

-- Helper: Robust Zone Matching (Checks Zone Header, SubZone, Starter Heuristics, and Objectives)
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
    -- Level 1-10 class quests in starting zones (Dun Morogh, Elwynn, Teldrassil, Durotar, Mulgore, Tirisfal)
    -- are always turned in to the starter trainer in the player's starter zone!
    if isClassOrProfHeader then
        local starterZones = {
            ["dun morogh"] = true, ["coldridge valley"] = true,
            ["elwynn forest"] = true, ["northshire"] = true, ["northshire valley"] = true,
            ["teldrassil"] = true, ["shadowglen"] = true,
            ["durotar"] = true, ["valley of trials"] = true,
            ["mulgore"] = true, ["red cloud mesa"] = true,
            ["tirisfal glades"] = true, ["deathknell"] = true,
            ["zephras isle"] = true, ["the riverglades"] = true, ["riverglades"] = true,
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

    -- 3. Fallback: Check objective text for zone name
    if questLogIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local numLeaderBoards = GetNumQuestLeaderBoards(questLogIndex) or 0
        for j = 1, numLeaderBoards do
            local text = GetQuestLogLeaderBoard(j, questLogIndex)
            if text then
                local lowerText = string.lower(text)
                for _, z in ipairs(validZones) do
                    local normZ = Normalize(z)
                    if #normZ >= 4 and lowerText:find(normZ, 1, true) then
                        return true
                    end
                end
            end
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
                local _, _, _, _, _, _, _, _, _, _, _, itemClassID = GetItemInfo(hyperlink)
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
    local numWatches = (C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches()) 
        or (GetNumQuestWatches and GetNumQuestWatches()) or 0

    for i = 1, numEntries do
        local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
        
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then
                title = info.title
                level = info.level
                suggestedGroup = info.suggestedGroup
                isHeader = info.isHeader
                isCollapsed = info.isCollapsed
                isComplete = (info.isComplete and 1) or 0
                frequency = info.frequency
                questID = info.questID
            end
        end

        if not title and GetQuestLogTitle then
            title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID = GetQuestLogTitle(i)
        end

        if isHeader then
            activeZoneHeader = title or "General"
        elseif title and questID then
            local isWatched = false
            if IsQuestWatched then
                isWatched = IsQuestWatched(i)
            elseif C_QuestLog and C_QuestLog.GetQuestWatchType then
                isWatched = (C_QuestLog.GetQuestWatchType(questID) ~= nil)
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
                -- Gather Objectives
                local objectives = {}
                local numLeaderBoards = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
                
                if numLeaderBoards > 0 then
                    for j = 1, numLeaderBoards do
                        local desc, objType, done = GetQuestLogLeaderBoard(j, i)
                        if desc then
                            table.insert(objectives, {
                                text = desc,
                                finished = done,
                                type = objType
                            })
                        end
                    end
                elseif C_QuestLog and C_QuestLog.GetQuestObjectives then
                    local cObjectives = C_QuestLog.GetQuestObjectives(questID)
                    if cObjectives then
                        for _, obj in ipairs(cObjectives) do
                            table.insert(objectives, {
                                text = obj.text,
                                finished = obj.finished,
                                type = obj.type
                            })
                        end
                    end
                end

                -- Check Quest Item
                local itemLink, itemTexture, numItems
                if GetQuestLogSpecialItemInfo then
                    itemLink, itemTexture, numItems = GetQuestLogSpecialItemInfo(i)
                elseif C_QuestLog and C_QuestLog.GetQuestLogSpecialItemInfo then
                    itemLink, itemTexture, numItems = C_QuestLog.GetQuestLogSpecialItemInfo(questID)
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
                    isComplete = (isComplete == 1 or isComplete == true),
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

    table.sort(quests, function(a, b)
        if moveCompleted and (a.isComplete ~= b.isComplete) then
            return not a.isComplete
        end

        if sortMode == "zone" then
            local zoneA = tostring(a.zone or "")
            local zoneB = tostring(b.zone or "")
            if zoneA == zoneB then
                local lvlA = tonumber(a.level) or 0
                local lvlB = tonumber(b.level) or 0
                if lvlA ~= lvlB then
                    return lvlA < lvlB
                end
                return (a.questID or 0) < (b.questID or 0)
            end
            return zoneA < zoneB
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

    -- Collapsed State (Default is expanded; collapsed only if explicitly marked true)
    local questKey = qInfo.questID or qInfo.title
    local isCollapsed = ns.db and ns.db.collapsedQuests and ns.db.collapsedQuests[questKey]

    -- Anchor Quest Title across the full width of the header bar
    block.header:SetWidth(content:GetWidth())
    block.header:ClearAllPoints()
    block.header:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    block.header:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)

    block.header.title:ClearAllPoints()
    block.header.title:SetPoint("TOPLEFT", block.header, "TOPLEFT", 0, 0)
    if qInfo.itemTexture then
        block.header.title:SetPoint("TOPRIGHT", block.header, "TOPRIGHT", -26, 0)
    else
        block.header.title:SetPoint("TOPRIGHT", block.header, "TOPRIGHT", 0, 0)
    end
    block.header.title:SetWordWrap(true)
    block.header.title:SetJustifyH("LEFT")
    block.header.title:SetText(GetFormattedQuestTitle(qInfo))

    local titleSize = StandaloneTracker.titleSize or 13
    local titleHeight = math.max(titleSize + 6, math.ceil(block.header.title:GetStringHeight() + 2))
    block.header:SetHeight(titleHeight)
    local currentBlockHeight = titleHeight

    -- Item Button Setup if available
    if qInfo.itemTexture then
        local itemBtn = AcquireItemButton(block)
        itemBtn:ClearAllPoints()
        itemBtn:SetPoint("TOPRIGHT", block.header, "TOPRIGHT", 0, 0)
        itemBtn.icon:SetTexture(qInfo.itemTexture)
        local itemCount = tonumber(qInfo.numItems) or 0
        itemBtn.count:SetText(itemCount > 1 and tostring(itemCount) or "")
        itemBtn.itemLink = qInfo.itemLink
        itemBtn.itemID = qInfo.itemID
        if not InCombatLockdown() then
            itemBtn:SetAttribute("type", "item")
            itemBtn:SetAttribute("item", qInfo.itemLink or qInfo.itemTexture)
        end

        -- Update Cooldown Spiral
        if itemBtn.cooldown and qInfo.itemID then
            local start, duration, enable = 0, 0, 0
            if C_Container and C_Container.GetItemCooldown then
                start, duration, enable = C_Container.GetItemCooldown(qInfo.itemID)
            elseif GetItemCooldown then
                start, duration, enable = GetItemCooldown(qInfo.itemID)
            end
            if start and duration and duration > 0 then
                itemBtn.cooldown:SetCooldown(start, duration)
                itemBtn.cooldown:Show()
            else
                itemBtn.cooldown:Hide()
            end
        elseif itemBtn.cooldown then
            itemBtn.cooldown:Hide()
        end
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

                -- Party Progress Sync Subline
                if ns.db and ns.db.social and ns.db.social.enablePartySync and ns.SocialModule and ns.SocialModule.GetObjectivePartyProgress then
                    local partyText = ns.SocialModule:GetObjectivePartyProgress(qInfo.questID, objIdx)
                    if partyText then
                        local partyFs = AcquirePartyString(block)
                        partyFs:ClearAllPoints()
                        partyFs:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -1)
                        partyFs:SetWidth(objWidth)
                        partyFs:SetWordWrap(true)
                        partyFs:SetJustifyH("LEFT")
                        partyFs:SetText("|cff778899> Party:|r " .. partyText)
                        local pHeight = math.ceil(partyFs:GetStringHeight())
                        currentBlockHeight = currentBlockHeight + pHeight + 2
                        prevAnchor = partyFs
                    end
                end
            end
        end

        -- Party Missing Quest / Click to Share Button
        if ns.db and ns.db.social and ns.db.social.enablePartySync and ns.SocialModule and ns.SocialModule.GetMissingPartyInfo then
            local missingCount, canShare = ns.SocialModule:GetMissingPartyInfo(qInfo.questID, qInfo.questLogIndex)
            if canShare and missingCount and missingCount > 0 then
                local shareBtn = AcquireShareButton(block)
                shareBtn:ClearAllPoints()
                shareBtn:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", (prevAnchor == block.header and objIndent or 0), -2)
                shareBtn:SetWidth(objWidth)
                shareBtn.text:ClearAllPoints()
                shareBtn.text:SetAllPoints(shareBtn)
                shareBtn.text:SetJustifyH("LEFT")
                local isRecent = ns.SocialModule.IsRecentlyShared and ns.SocialModule:IsRecentlyShared(qInfo.questID)
                if isRecent then
                    shareBtn.text:SetText("|cff778899> Party:|r |cff00ff00Sharing with party...|r")
                    shareBtn:Disable()
                else
                    shareBtn.text:SetText(string.format("|cff778899> Party:|r |cff00c0ff%d missing [Click to Share]|r", missingCount))
                    shareBtn:Enable()
                end

                local qID, qIndex = qInfo.questID, qInfo.questLogIndex
                shareBtn:SetScript("OnClick", function(btn)
                    btn.text:SetText("|cff778899> Party:|r |cff00ff00Sharing with party...|r")
                    btn:Disable()
                    ns.SocialModule:ShareQuest(qID, qIndex)
                    if C_Timer and C_Timer.After then
                        C_Timer.After(3.5, function()
                            if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                                ns.StandaloneTracker:UpdateTracker()
                            end
                        end)
                    end
                end)
                local sHeight = 14
                currentBlockHeight = currentBlockHeight + sHeight + 2
                prevAnchor = shareBtn
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

    -- Reset previous active fontstrings, blocks, and zone headers
    for _, fs in ipairs(objectiveStrings) do fs:Hide() end
    for _, fs in ipairs(partyStrings) do fs:Hide() end
    for _, btn in ipairs(shareButtons) do btn:Hide() end
    for _, blk in ipairs(questBlocks) do blk:Hide() end
    for _, zh in ipairs(zoneHeaders) do zh:Hide() end
    if not InCombatLockdown() then
        for _, btn in ipairs(itemButtons) do btn:Hide() end
    end

    local trackedQuests = self:GetTrackedQuests()
    local totalQuests = #trackedQuests
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

        for _, z in ipairs(zoneOrder) do
            local qList = zoneMap[z]
            local isZoneCollapsed = ns.db and ns.db.collapsedZones and ns.db.collapsedZones[z]

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
    local _, numQuests = GetNumQuestLogEntries()
    local maxQuests = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or MAX_QUESTLOG_QUESTS or 40
    ns.Tracker:UpdateHeight(yOffset)
    ns.Tracker:SetQuestCount(totalQuests, numQuests, maxQuests)
    ns.Tracker:UpdateFilterButtons()
end

function StandaloneTracker:Initialize()
    HookBlizzardTracker()

    -- Register Blizzard Quest Events
    local eventFrame = CreateFrame("Frame")
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

    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then
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

    -- Initial load
    C_Timer.After(0.5, function()
        StandaloneTracker:UpdateTracker()
    end)
end

