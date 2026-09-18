local addonName, ns = ...

local Tracker = {}
ns.Tracker = Tracker

-- Main Frame Reference
local trackerFrame
local scrollFrame
local contentFrame

-- Backdrop Definition Helper
local function GetBackdropConfig()
    local db = ns.db and ns.db.backdrop or ns.defaultDB.profile.backdrop
    return {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        tileSize = 0,
        edgeSize = db.edgeSize or 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    }
end

function Tracker:Initialize()
    if self.initialized then return end
    self.initialized = true

    local db = ns.db or ns.defaultDB.profile

    -- Create Main Container Frame (anonymous to permanently eliminate layout-local.txt caching)
    trackerFrame = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
    _G["BleakfiberQuestTrackerFrame"] = trackerFrame
    _G["BleakfiberQuestTrackerContainer"] = trackerFrame
    self.frame = trackerFrame

    trackerFrame:SetSize(db.width or 280, 100)
    trackerFrame:SetScale(db.scale or 1.0)
    trackerFrame:SetClampedToScreen(true)
    trackerFrame:SetMovable(true)
    trackerFrame:EnableMouse(true)
    trackerFrame:RegisterForDrag("LeftButton")
    trackerFrame:SetUserPlaced(false)

    -- Set Position from SavedVariables (Pinned to TOPLEFT for guaranteed downward expansion)
    self:RestorePosition()

    -- Smooth Dragging & Position Saving
    local function StartDragging()
        if ns.db and ns.db.isLocked then return end
        trackerFrame.isMoving = true
        trackerFrame:StartMoving()
    end

    local function StopDragging()
        if not trackerFrame.isMoving then return end
        trackerFrame.isMoving = false
        trackerFrame:StopMovingOrSizing()

        local point, _, relativePoint, x, y = trackerFrame:GetPoint()
        local currentDB = (ns.dbObject and ns.dbObject.profile) or ns.db

        if point and x and y and currentDB then
            currentDB.framePosition = {
                point = point,
                relativePoint = relativePoint or point,
                x = math.floor(x + 0.5),
                y = math.floor(y + 0.5),
            }
            ns.db = currentDB

            trackerFrame:ClearAllPoints()
            trackerFrame:SetPoint(point, UIParent, relativePoint or point, currentDB.framePosition.x, currentDB.framePosition.y)
            trackerFrame:SetUserPlaced(false)

            -- Per-character fail-safe backup
            if not _G["BleakfiberTrackerCharDB"] then
                _G["BleakfiberTrackerCharDB"] = {}
            end
            _G["BleakfiberTrackerCharDB"].framePosition = currentDB.framePosition

            ns.Debug(string.format("[Drag] Saved: %s relative to %s at (%d, %d)", point, relativePoint or point, currentDB.framePosition.x, currentDB.framePosition.y))
        else
            trackerFrame:SetUserPlaced(false)
        end
    end

    trackerFrame:SetScript("OnDragStart", StartDragging)
    trackerFrame:SetScript("OnDragStop", StopDragging)

    -- MouseUp on trackerFrame (handles drag release and settings click)
    trackerFrame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and IsAltKeyDown() then
            if ns.Config then ns.Config:ToggleConfigFrame() end
        elseif button == "LeftButton" and trackerFrame.isMoving then
            StopDragging()
        end
    end)

    trackerFrame:SetScript("OnHide", function(self)
        if trackerFrame.isMoving then
            StopDragging()
        end
    end)

    -- Header Frame
    local header = CreateFrame("Button", nil, trackerFrame)
    trackerFrame.header = header
    header:SetHeight(24)
    header:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", -6, -6)

    -- Header Background Texture
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    header.bg = headerBg
    headerBg:SetAllPoints(header)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", StartDragging)
    header:SetScript("OnDragStop", StopDragging)

    -- Header Tooltip with Controls
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("|cff00c0ffBleakfiber's Quest Tracker|r")
        GameTooltip:AddLine("Left-Click & Drag: Move tracker", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-Click: Quick Options", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cff00ff00Alt + Right-Click: Open Settings|r", 0.2, 1, 0.2)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- MouseUp on Header (handles quick menu, alt+settings, and drag drop)
    header:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            if IsAltKeyDown() then
                if ns.Config then ns.Config:ToggleConfigFrame() end
            elseif ns.Config then
                ns.Config:OpenQuickMenu(header)
            end
        elseif button == "LeftButton" and trackerFrame.isMoving then
            StopDragging()
        end
    end)

    -- Collapse/Expand Toggle Button
    local collapseBtn = CreateFrame("Button", nil, header)
    header.collapseBtn = collapseBtn
    collapseBtn:SetSize(16, 16)
    collapseBtn:SetPoint("LEFT", header, "LEFT", 2, 0)
    collapseBtn:SetNormalFontObject("GameFontNormalSmall")
    collapseBtn:SetHighlightFontObject("GameFontHighlightSmall")
    collapseBtn:SetText("[-]")
    collapseBtn:SetScript("OnClick", function()
        Tracker:ToggleCollapse()
    end)

    -- Header Title Text
    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.titleText = titleText
    titleText:SetPoint("LEFT", collapseBtn, "RIGHT", 4, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    titleText:SetText("Quests")

    -- Header Quest Counter Text (e.g. (14/20))
    local countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.countText = countText
    countText:SetPoint("LEFT", titleText, "RIGHT", 4, 0)
    countText:SetJustifyH("LEFT")
    countText:SetWordWrap(false)
    countText:SetText("")
    countText:EnableMouse(true)
    countText:SetScript("OnEnter", function(self)
        local _, nQuests = ns.GetNumQuestLogEntries()
        local mQuests = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or MAX_QUESTLOG_QUESTS or 40
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Quest Log Capacity", 1, 1, 1)
        GameTooltip:AddLine(string.format("Quests in Log: |cffffffff%d / %d|r", nQuests or 0, mQuests), 0.8, 0.8, 0.8)
        if trackerFrame and trackerFrame.trackedCount then
            GameTooltip:AddLine(string.format("Shown in Tracker: |cffffffff%d|r", trackerFrame.trackedCount), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    countText:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Menu Button [...]
    local menuBtn = CreateFrame("Button", nil, header)
    header.filterMenuBtn = menuBtn
    menuBtn:SetHeight(16)
    menuBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    menuBtn:SetNormalFontObject("GameFontNormalSmall")
    menuBtn:SetHighlightFontObject("GameFontHighlightSmall")
    menuBtn:SetText("[...]")
    menuBtn:SetScript("OnClick", function(self)
        if IsAltKeyDown() then
            if ns.Config then ns.Config:ToggleConfigFrame() end
        elseif ns.Config and ns.Config.OpenFilterMenu then
            ns.Config:OpenFilterMenu(self)
        end
    end)
    menuBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Tracker Options", 1, 1, 1)
        GameTooltip:AddLine("Click: Quick menu & filters\nAlt+Click: Full settings", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    menuBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Zone Filter Button [Zone]
    local zoneBtn = CreateFrame("Button", nil, header)
    header.filterZoneBtn = zoneBtn
    zoneBtn:SetHeight(16)
    zoneBtn:SetPoint("RIGHT", menuBtn, "LEFT", -4, 0)
    zoneBtn:SetNormalFontObject("GameFontNormalSmall")
    zoneBtn:SetHighlightFontObject("GameFontHighlightSmall")
    zoneBtn:SetText("Zone")
    zoneBtn:SetScript("OnClick", function()
        local db = ns.db
        if not db then return end
        if db.filtering.filterMode == "zone" or db.filtering.zoneOnly then
            db.filtering.filterMode = "all"
            db.filtering.zoneOnly = false
        else
            db.filtering.filterMode = "zone"
            db.filtering.zoneOnly = true
        end
        Tracker:UpdateFilterButtons()
        ns:FireCallback("QUEST_DATA_CHANGED")
    end)
    zoneBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Filter: Current Zone", 1, 1, 1)
        GameTooltip:AddLine("Click to show only quests located in your current zone.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    zoneBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- All Filter Button [All]
    local allBtn = CreateFrame("Button", nil, header)
    header.filterAllBtn = allBtn
    allBtn:SetHeight(16)
    allBtn:SetPoint("RIGHT", zoneBtn, "LEFT", -3, 0)
    allBtn:SetNormalFontObject("GameFontNormalSmall")
    allBtn:SetHighlightFontObject("GameFontHighlightSmall")
    allBtn:SetText("All")
    allBtn:SetScript("OnClick", function()
        local db = ns.db
        if not db then return end
        db.filtering.filterMode = "all"
        db.filtering.zoneOnly = false
        Tracker:UpdateFilterButtons()
        ns:FireCallback("QUEST_DATA_CHANGED")
    end)
    allBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Filter: All Quests", 1, 1, 1)
        GameTooltip:AddLine("Click to display all tracked quests from your quest log.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    allBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Quest Log Button [Log]
    local questLogBtn = CreateFrame("Button", nil, header)
    header.questLogBtn = questLogBtn
    questLogBtn:SetHeight(16)
    questLogBtn:SetNormalFontObject("GameFontNormalSmall")
    questLogBtn:SetHighlightFontObject("GameFontHighlightSmall")
    questLogBtn:SetText("Log")
    questLogBtn:SetScript("OnClick", function()
        if ToggleQuestLog then
            ToggleQuestLog()
        elseif QuestLogFrame then
            if QuestLogFrame:IsShown() then
                HideUIPanel(QuestLogFrame)
            else
                ShowUIPanel(QuestLogFrame)
            end
        elseif QuestMapFrame then
            if QuestMapFrame:IsShown() then
                HideUIPanel(QuestMapFrame)
            else
                ShowUIPanel(QuestMapFrame)
            end
        end
    end)
    questLogBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Quest Log", 1, 1, 1)
        GameTooltip:AddLine("Click to open or close your Quest Log.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    questLogBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Scroll Frame for Objectives
    scrollFrame = CreateFrame("ScrollFrame", "BleakfiberQuestTrackerScrollFrame", trackerFrame)
    self.scrollFrame = scrollFrame
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", trackerFrame, "BOTTOMRIGHT", -6, 6)
    scrollFrame:EnableMouseWheel(true)

    -- Smooth MouseWheel Scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local step = 28
        local newScroll = math.max(0, math.min(maxScroll, current - (delta * step)))
        self:SetVerticalScroll(newScroll)
    end)

    -- Alt + Right-Click to open settings from scroll area
    scrollFrame:EnableMouse(true)
    scrollFrame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and IsAltKeyDown() then
            if ns.Config then ns.Config:ToggleConfigFrame() end
        end
    end)

    -- Scroll Child (Content Frame holding Quest Blocks)
    contentFrame = CreateFrame("Frame", nil, scrollFrame)
    self.contentFrame = contentFrame
    contentFrame:SetWidth(trackerFrame:GetWidth() - 12)
    contentFrame:SetHeight(1)
    scrollFrame:SetScrollChild(contentFrame)

    -- Apply Saved Visuals
    self:UpdateBackdrop()
    self:ApplyHeaderSettings()
    self:UpdateTypography()
    self.isCollapsed = false

    -- Register Callbacks
    ns:RegisterCallback("SETTINGS_UPDATED", function()
        Tracker:UpdateSettings()
    end)

    ns:RegisterCallback("PLAYER_ENTERING_WORLD", function()
        Tracker:RestorePosition()
        Tracker:CheckInstanceAutoCollapse()
        Tracker:UpdateTypography()
    end)

    -- Close bounds overlay whenever ESC is pressed or Game Menu is toggled
    if CloseWindows then
        hooksecurefunc("CloseWindows", function()
            if Tracker:IsConfigOverlayShown() then
                Tracker:HideConfigOverlay()
            end
        end)
    end
    if ToggleGameMenu then
        hooksecurefunc("ToggleGameMenu", function()
            if Tracker:IsConfigOverlayShown() then
                Tracker:HideConfigOverlay()
            end
        end)
    end
end

function Tracker:UpdateBackdrop()
    if not trackerFrame then return end
    local db = ns.db and ns.db.backdrop or ns.defaultDB.profile.backdrop

    if db.show then
        trackerFrame:SetBackdrop(GetBackdropConfig())
        local bg = db.bgColor or { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
        local border = db.borderColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.9 }
        trackerFrame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
        trackerFrame:SetBackdropBorderColor(border.r, border.g, border.b, border.a)
    else
        trackerFrame:SetBackdrop(nil)
    end
end

function Tracker:ApplyHeaderSettings()
    if not trackerFrame or not trackerFrame.header then return end
    local header = trackerFrame.header
    local db = ns.db or ns.defaultDB.profile
    local hCfg = db.headers or ns.defaultDB.profile.headers

    local borderColor = (db.backdrop and db.backdrop.borderColor) or { r = 0.15, g = 0.15, b = 0.15, a = 0.9 }
    local bgrColor = hCfg.textureColorShare and borderColor or (hCfg.textureColor or { r = 0.05, g = 0.08, b = 0.12, a = 0.85 })
    local txtColor = hCfg.textColorShare and borderColor or (hCfg.textColor or (ns.GetClassColor and ns.GetClassColor()) or { r = 0.0, g = 0.75, b = 1.0 })
    local btnColor = hCfg.buttonColorShare and borderColor or (hCfg.buttonColor or (ns.GetClassColor and ns.GetClassColor()) or { r = 0.0, g = 0.75, b = 1.0 })

    self.headerBtnColor = btnColor

    -- Background texture
    local bgTex = header.bg
    if bgTex then
        local textureType = hCfg.texture or "flat"
        if textureType == "none" then
            bgTex:Hide()
        elseif textureType == "blizzard" then
            bgTex:Show()
            if bgTex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Objective-Header") then
                bgTex:SetAtlas("Objective-Header")
                bgTex:SetVertexColor(1, 1, 1, bgrColor.a or 1)
            else
                bgTex:SetTexture("Interface\\QuestFrame\\UI-QuestHeader")
                bgTex:SetVertexColor(bgrColor.r, bgrColor.g, bgrColor.b, bgrColor.a or 1)
            end
        elseif textureType == "gradient" then
            bgTex:Show()
            if bgTex.SetGradient and CreateColor then
                bgTex:SetColorTexture(1, 1, 1, 1)
                bgTex:SetGradient("HORIZONTAL", CreateColor(bgrColor.r, bgrColor.g, bgrColor.b, bgrColor.a or 0.85), CreateColor(bgrColor.r, bgrColor.g, bgrColor.b, 0))
            else
                bgTex:SetColorTexture(bgrColor.r, bgrColor.g, bgrColor.b, bgrColor.a or 0.85)
            end
        else -- "flat"
            bgTex:Show()
            bgTex:SetColorTexture(bgrColor.r, bgrColor.g, bgrColor.b, bgrColor.a or 0.85)
        end
    end

    -- Title text color
    if header.titleText then
        header.titleText:SetTextColor(txtColor.r, txtColor.g, txtColor.b)
    end

    -- Collapse button visibility & color
    local collapseBtn = header.collapseBtn
    if collapseBtn then
        if hCfg.showCollapseBtn ~= false then
            collapseBtn:Show()
            local btnHex = string.format("|cff%02x%02x%02x", btnColor.r * 255, btnColor.g * 255, btnColor.b * 255)
            collapseBtn:SetText(btnHex .. (self.isCollapsed and "[+]" or "[-]") .. "|r")
            if header.titleText then
                header.titleText:ClearAllPoints()
                header.titleText:SetPoint("LEFT", collapseBtn, "RIGHT", 4, 0)
            end
        else
            collapseBtn:Hide()
            if header.titleText then
                header.titleText:ClearAllPoints()
                header.titleText:SetPoint("LEFT", header, "LEFT", 4, 0)
            end
        end
    end

    self:UpdateFilterButtons()
end

function Tracker:UpdateFilterButtons()
    if not trackerFrame or not trackerFrame.header then return end
    local header = trackerFrame.header
    local db = ns.db or ns.defaultDB.profile
    local hCfg = db.headers or ns.defaultDB.profile.headers

    local filterMode = (db.filtering and db.filtering.filterMode)
    if not filterMode then
        filterMode = (db.filtering and db.filtering.zoneOnly) and "zone" or "all"
    end

    local btnColor = self.headerBtnColor or hCfg.buttonColor or (ns.GetClassColor and ns.GetClassColor()) or { r = 0.0, g = 0.75, b = 1.0 }
    local activeHex = string.format("|cff%02x%02x%02x", btnColor.r * 255, btnColor.g * 255, btnColor.b * 255)
    local dimHex = string.format("|cff%02x%02x%02x", math.max(60, btnColor.r * 140), math.max(60, btnColor.g * 140), math.max(60, btnColor.b * 140))

    local menuBtn = header.filterMenuBtn
    local zoneBtn = header.filterZoneBtn
    local allBtn = header.filterAllBtn
    local questLogBtn = header.questLogBtn

    -- 1. Apply active / inactive text formatting
    if menuBtn then
        if hCfg.showMenuBtn ~= false then
            menuBtn:Show()
            menuBtn:SetText(activeHex .. "[...]|r")
            menuBtn:SetWidth(18)
        else
            menuBtn:Hide()
        end
    end

    if zoneBtn then
        if hCfg.showZoneBtn ~= false then
            zoneBtn:Show()
            if filterMode == "zone" then
                zoneBtn:SetText(activeHex .. "[Zone]|r")
            else
                zoneBtn:SetText(dimHex .. "Zone|r")
            end
            if zoneBtn:GetFontString() then
                zoneBtn:SetWidth(math.max(28, zoneBtn:GetFontString():GetStringWidth() + 4))
            else
                zoneBtn:SetWidth(32)
            end
        else
            zoneBtn:Hide()
        end
    end

    if allBtn then
        if hCfg.showAllBtn ~= false then
            allBtn:Show()
            if filterMode == "all" then
                allBtn:SetText(activeHex .. "[All]|r")
            else
                allBtn:SetText(dimHex .. "All|r")
            end
            if allBtn:GetFontString() then
                allBtn:SetWidth(math.max(20, allBtn:GetFontString():GetStringWidth() + 4))
            else
                allBtn:SetWidth(22)
            end
        else
            allBtn:Hide()
        end
    end

    if questLogBtn then
        if hCfg.showQuestLogBtn ~= false then
            questLogBtn:Show()
            questLogBtn:SetText(dimHex .. "Log|r")
            if questLogBtn:GetFontString() then
                questLogBtn:SetWidth(math.max(24, questLogBtn:GetFontString():GetStringWidth() + 4))
            else
                questLogBtn:SetWidth(26)
            end
        else
            questLogBtn:Hide()
        end
    end

    -- 2. Dynamically anchor buttons from right to left with zero gaps
    local buttons = { menuBtn, zoneBtn, allBtn, questLogBtn }
    local prevVisibleBtn = nil

    for _, btn in ipairs(buttons) do
        if btn and btn:IsShown() then
            btn:ClearAllPoints()
            if not prevVisibleBtn then
                btn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
            else
                btn:SetPoint("RIGHT", prevVisibleBtn, "LEFT", -4, 0)
            end
            prevVisibleBtn = btn
        end
    end

    if header.countText and header.titleText then
        header.countText:ClearAllPoints()
        header.countText:SetPoint("LEFT", header.titleText, "RIGHT", 4, 0)
        if prevVisibleBtn then
            header.countText:SetPoint("RIGHT", prevVisibleBtn, "LEFT", -4, 0)
        else
            header.countText:SetPoint("RIGHT", header, "RIGHT", -4, 0)
        end
    end
end
Tracker.UpdateFilterButton = Tracker.UpdateFilterButtons

-- Configuration Mode Overlay Frame (Only visible when configuration panel is open)
local configOverlay

function Tracker:CreateConfigOverlay()
    if configOverlay then return configOverlay end

    configOverlay = CreateFrame("Frame", "BleakfiberTrackerConfigOverlay", UIParent, "BackdropTemplate")
    configOverlay:SetFrameStrata("HIGH")
    configOverlay:SetFrameLevel(50)
    configOverlay:SetClampedToScreen(true)
    configOverlay:EnableMouse(true)
    configOverlay:SetMovable(false)

    configOverlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    configOverlay:SetBackdropColor(0.05, 0.45, 0.9, 0.20)
    configOverlay:SetBackdropBorderColor(0.2, 0.7, 1.0, 0.9)

    -- Overlay Header Title
    local title = configOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    configOverlay.title = title
    title:SetPoint("TOP", configOverlay, "TOP", 0, -8)
    title:SetText("|cff00c0ffBleakfiber's Quest Tracker|r - Bounds & Auto-Grow Overlay")

    -- Overlay Dimensions Readout
    local info = configOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    configOverlay.info = info
    info:SetPoint("CENTER", configOverlay, "CENTER", 0, 0)

    -- Drag Resize Handle in the bottom-right corner of the OVERLAY ONLY
    local dragGrip = CreateFrame("Button", "BleakfiberOverlayDragGrip", configOverlay)
    configOverlay.dragGrip = dragGrip
    dragGrip:SetSize(32, 32)
    dragGrip:SetPoint("BOTTOMRIGHT", configOverlay, "BOTTOMRIGHT", 0, 0)
    dragGrip:EnableMouse(true)
    dragGrip:SetFrameLevel(60)

    local gripTex = dragGrip:CreateTexture(nil, "OVERLAY")
    gripTex:SetSize(18, 18)
    gripTex:SetPoint("BOTTOMRIGHT", dragGrip, "BOTTOMRIGHT", -2, 2)
    gripTex:SetColorTexture(0.2, 0.75, 1.0, 0.85)

    local dragHint = dragGrip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dragHint:SetPoint("RIGHT", gripTex, "LEFT", -6, 0)
    dragHint:SetText("|cff00ffffDrag to Resize|r")

    dragGrip:SetScript("OnEnter", function(self)
        gripTex:SetColorTexture(0.4, 0.95, 1.0, 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Resize Bounds", 1, 1, 1)
        GameTooltip:AddLine("Drag to change Tracker Width and Grow Down Range (Max Height)", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    dragGrip:SetScript("OnLeave", function(self)
        gripTex:SetColorTexture(0.2, 0.75, 1.0, 0.85)
        GameTooltip:Hide()
    end)

    configOverlay:SetResizable(true)
    if configOverlay.SetResizeBounds then
        configOverlay:SetResizeBounds(180, 150, 600, 1200)
    elseif configOverlay.SetMinResize then
        configOverlay:SetMinResize(180, 150)
        configOverlay:SetMaxResize(600, 1200)
    end

    local function FinishSizing()
        if dragGrip.isSizing then
            dragGrip.isSizing = false
            configOverlay:StopMovingOrSizing()
            local newW = math.floor(configOverlay:GetWidth() + 0.5)
            local newH = math.floor(configOverlay:GetHeight() + 0.5)
            ns.db.width = math.max(180, math.min(600, newW))
            ns.db.maxHeight = math.max(100, math.min(1200, newH))
            Tracker:UpdateSettings()
            Tracker:UpdateConfigOverlay()
            local ACR = LibStub and LibStub("AceConfigRegistry-3.0", true)
            if ACR then
                ACR:NotifyChange("BleakfiberQuestTracker")
            end
        end
    end

    dragGrip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            configOverlay:StartSizing("BOTTOMRIGHT")
            dragGrip.isSizing = true
        end
    end)

    dragGrip:SetScript("OnMouseUp", FinishSizing)
    configOverlay:SetScript("OnMouseUp", FinishSizing)

    configOverlay:SetScript("OnSizeChanged", function(self, w, h)
        if dragGrip.isSizing then
            local liveW = math.max(180, math.min(600, math.floor(w + 0.5)))
            local liveH = math.max(150, math.min(1200, math.floor(h + 0.5)))
            if configOverlay.info then
                configOverlay.info:SetText(string.format("Width: |cff00ff00%d px|r\nGrow Down Range: |cff00ff00%d px|r", liveW, liveH))
            end
            if ns.Config and ns.Config.SyncInputsLive then
                ns.Config:SyncInputsLive(liveW, liveH)
            end
        end
    end)

    local inSpecial = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "BleakfiberTrackerConfigOverlay" then
            inSpecial = true
            break
        end
    end
    if not inSpecial then
        table.insert(UISpecialFrames, "BleakfiberTrackerConfigOverlay")
    end

    configOverlay:Hide()
    return configOverlay
end

function Tracker:UpdateConfigOverlay()
    if not configOverlay or not configOverlay:IsShown() then return end
    if not trackerFrame then return end

    configOverlay:SetScale(trackerFrame:GetScale() or 1.0)
    configOverlay:ClearAllPoints()
    configOverlay:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", 0, 0)
    local w = ns.db.width or 280
    local h = ns.db.maxHeight or 600
    configOverlay:SetSize(w, h)
    if configOverlay.info then
        configOverlay.info:SetText(string.format("Width: |cff00ff00%d px|r\nGrow Down Range: |cff00ff00%d px|r", w, h))
    end
end

function Tracker:ShowConfigOverlay()
    if trackerFrame then
        trackerFrame:Show()
    end
    local overlay = self:CreateConfigOverlay()
    overlay:Show()
    self:UpdateConfigOverlay()
end

function Tracker:HideConfigOverlay()
    if configOverlay then
        configOverlay:Hide()
    end
    local ACR = LibStub and LibStub("AceConfigRegistry-3.0", true)
    if ACR then
        ACR:NotifyChange("BleakfiberQuestTracker")
    end
    if ns.db and ns.db.filtering and ns.db.filtering.autoHideEmpty then
        if ns.StandaloneTracker and ns.StandaloneTracker.GetTrackedQuests then
            local quests = ns.StandaloneTracker:GetTrackedQuests()
            if #quests == 0 and trackerFrame then
                trackerFrame:Hide()
            end
        end
    end
end

function Tracker:IsConfigOverlayShown()
    return configOverlay and configOverlay:IsShown()
end

function Tracker:UpdateTypography()
    local db = ns.db
    if not db then return end
    local fonts = db.fonts or ns.defaultDB.profile.fonts
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local fontName = fonts.font or fonts.headerFont or "Friz Quadrata TT"
    local fontPath = (LSM and LSM:Fetch("font", fontName, true)) or STANDARD_TEXT_FONT
    local titleSize = fonts.headerSize or 13
    local objSize = fonts.objectiveSize or 11
    local outline = fonts.headerOutline or "OUTLINE"

    if trackerFrame and trackerFrame.header then
        if trackerFrame.header.titleText then
            trackerFrame.header.titleText:SetFont(fontPath, titleSize, outline)
            trackerFrame.header:SetHeight(math.max(24, titleSize + 8))
        end
        if trackerFrame.header.countText then
            trackerFrame.header.countText:SetFont(fontPath, math.max(9, titleSize - 2), outline)
        end
    end

    if ns.StandaloneTracker and ns.StandaloneTracker.ApplyTypography then
        ns.StandaloneTracker:ApplyTypography(fontPath, titleSize, objSize, outline)
    end
end

function Tracker:RestorePosition()
    if not trackerFrame then return end
    local db = (ns.dbObject and ns.dbObject.profile) or ns.db

    trackerFrame:SetUserPlaced(false)
    trackerFrame:ClearAllPoints()

    local pos = (db and db.framePosition) 
        or (_G["BleakfiberTrackerCharDB"] and _G["BleakfiberTrackerCharDB"].framePosition)

    if pos and pos.point and pos.x and pos.y then
        if db and not db.framePosition then
            db.framePosition = pos
        end
        trackerFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x, pos.y)
        ns.Debug(string.format("[Restore] Set %s relative to %s at (%d, %d)", pos.point, pos.relativePoint or pos.point, pos.x, pos.y))
    else
        trackerFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -250, -200)
        ns.Debug("[Restore Fallback] Set default TOPRIGHT -250, -200")
    end
    trackerFrame:SetUserPlaced(false)
end

function Tracker:ResetPosition()
    if not trackerFrame then return end
    local db = (ns.dbObject and ns.dbObject.profile) or ns.db

    if db then
        db.framePosition = nil
        db.point = nil
        db.relativePoint = nil
        db.xOfs = nil
        db.yOfs = nil
    end

    if _G["BleakfiberTrackerCharDB"] then
        _G["BleakfiberTrackerCharDB"].framePosition = nil
    end

    if _G["BleakfiberTrackerDB"] then
        _G["BleakfiberTrackerDB"].rawPosition = nil
    end

    self:RestorePosition()

    if self.UpdateConfigOverlay then
        self:UpdateConfigOverlay()
    end
    ns.Print("Tracker position reset to default.")
end

function Tracker:UpdateSettings()
    if not trackerFrame then return end
    local db = ns.db

    trackerFrame:SetScale(db.scale or 1.0)
    self:RestorePosition()
    local w = db.width or 280
    trackerFrame:SetWidth(w)
    if contentFrame then
        contentFrame:SetWidth(w - 12)
    end

    self:UpdateBackdrop()
    self:ApplyHeaderSettings()
    self:UpdateTypography()

    if configOverlay and configOverlay:IsShown() then
        self:UpdateConfigOverlay()
    end

    -- Trigger quest tracker re-layout to adapt all blocks to new width
    if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
        ns.StandaloneTracker:UpdateTracker()
    end
end

function Tracker:SetLocked(locked)
    ns.db.isLocked = locked
    if locked then
        ns.Print("Tracker locked.")
    else
        ns.Print("Tracker unlocked. Drag header to reposition.")
    end
end

function Tracker:ToggleCollapse()
    self.isCollapsed = not self.isCollapsed
    local header = trackerFrame and trackerFrame.header
    local hCfg = (ns.db and ns.db.headers) or {}
    local collapsedMode = hCfg.collapsedText or "counter"

    if self.isCollapsed then
        scrollFrame:Hide()
        trackerFrame:SetHeight(header:GetHeight() + 12)

        if collapsedMode == "none" then
            header.titleText:Hide()
            header.countText:Hide()
        elseif collapsedMode == "counter" then
            header.titleText:Hide()
            header.countText:Show()
            header.countText:ClearAllPoints()
            if header.collapseBtn and header.collapseBtn:IsShown() then
                header.countText:SetPoint("LEFT", header.collapseBtn, "RIGHT", 4, 0)
            else
                header.countText:SetPoint("LEFT", header, "LEFT", 4, 0)
            end
        else -- "title"
            header.titleText:Show()
            header.countText:Show()
            header.countText:ClearAllPoints()
            header.countText:SetPoint("LEFT", header.titleText, "RIGHT", 4, 0)
        end
    else
        scrollFrame:Show()
        header.titleText:Show()
        header.countText:Show()
        header.countText:ClearAllPoints()
        header.countText:SetPoint("LEFT", header.titleText, "RIGHT", 4, 0)
        self:UpdateHeight(contentFrame:GetHeight())
    end

    self:ApplyHeaderSettings()
end

function Tracker:CheckInstanceAutoCollapse()
    if not ns.db or not ns.db.filtering.autoHideInInstances then return end
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        if not self.isCollapsed then
            self:ToggleCollapse()
        end
    end
end

function Tracker:UpdateHeight(contentHeight)
    if not trackerFrame or self.isCollapsed then return end
    local db = ns.db
    local headerH = trackerFrame.header:GetHeight()
    local pad = 16
    local totalNeeded = contentHeight + headerH + pad
    local maxAllowed = db.maxHeight or 600

    local finalHeight = math.min(maxAllowed, totalNeeded)
    trackerFrame:SetHeight(math.max(finalHeight, headerH + pad))
    contentFrame:SetHeight(contentHeight)
end

function Tracker:SetQuestCount(trackedCount, numQuests, maxQuests)
    if not trackerFrame or not trackerFrame.header then return end
    trackerFrame.trackedCount = trackedCount
    local header = trackerFrame.header
    local countText = header.countText
    if not countText then return end

    if not numQuests then
        local _, n = ns.GetNumQuestLogEntries()
        numQuests = n or 0
    end
    numQuests = tonumber(numQuests) or 0

    if not maxQuests then
        maxQuests = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or MAX_QUESTLOG_QUESTS or 40
    end
    maxQuests = tonumber(maxQuests) or 40

    local hCfg = (ns.db and ns.db.headers) or {}
    local countFormat = hCfg.countFormat or "short"

    if countFormat == "none" and not (self.isCollapsed and (hCfg.collapsedText or "counter") == "counter") then
        countText:SetText("")
    else
        local color = "|cffaaaaaa"
        if numQuests >= maxQuests then
            color = "|cffff3333"
        elseif numQuests >= maxQuests - 2 then
            color = "|cffffaa00"
        end

        if countFormat == "full" or (self.isCollapsed and (hCfg.collapsedText or "counter") == "full") then
            countText:SetText(string.format("%s(%d/%d Quests)|r", color, numQuests, maxQuests))
        else
            countText:SetText(string.format("%s(%d/%d)|r", color, numQuests, maxQuests))
        end
    end

    -- Auto-hide when empty if configured
    if ns.db and ns.db.filtering.autoHideEmpty then
        if (trackedCount or 0) == 0 then
            trackerFrame:Hide()
        else
            trackerFrame:Show()
        end
    end
end

function Tracker:GetContentFrame()
    return contentFrame
end

function Tracker:GetFrame()
    return trackerFrame
end

-- Initialize when addon is ready
ns:RegisterCallback("ON_INITIALIZE", function()
    Tracker:Initialize()
end)

