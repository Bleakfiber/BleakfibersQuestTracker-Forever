local addonName, ns = ...

-- Localized Lua & WoW API bindings for performance & garbage reduction
local pairs, ipairs, type, tostring, tonumber, select, pcall = pairs, ipairs, type, tostring, tonumber, select, pcall
local string_format = string.format
local math_floor, math_max, math_min, math_ceil = math.floor, math.max, math.min, math.ceil
local GetTime = GetTime
local CreateFrame = CreateFrame
local IsShiftKeyDown, IsAltKeyDown = IsShiftKeyDown, IsAltKeyDown
local InCombatLockdown = InCombatLockdown

local Tracker = {}
ns.Tracker = Tracker

-- Main Frame Reference
local trackerFrame
local scrollFrame
local contentFrame

local BG_TEXTURE_PATHS = {
    ["solid"] = "Interface\\Buttons\\WHITE8x8",
    ["tooltip"] = "Interface\\Tooltips\\UI-Tooltip-Background",
    ["marble"] = "Interface\\FrameGeneral\\UI-Background-Marble",
    ["rock"] = "Interface\\FrameGeneral\\UI-Background-Rock",
    ["parchment"] = "Interface\\QuestFrame\\QuestBG",
    ["parchment_clean"] = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal",
}

local function GetBackdropConfig()
    local db = (ns.db and ns.db.backdrop) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.backdrop)
    local borderStyle = (db and db.borderStyle) or "flat"
    local bgTexKey = (db and db.bgTexture) or "solid"

    -- Background texture resolution
    local bgPath = BG_TEXTURE_PATHS[bgTexKey]
    if not bgPath then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        bgPath = (LSM and LSM:Fetch("background", bgTexKey, true)) or "Interface\\Buttons\\WHITE8x8"
    end

    local edgeFile
    local edgeSize = 1
    local insets = { left = 0, right = 0, top = 0, bottom = 0 }

    -- Border edge file & insets resolution
    if borderStyle == "tooltip" then
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border"
        edgeSize = (db and db.edgeSize) or 16
        local autoInset = math.max(4, math.floor(edgeSize * 0.28))
        local ins = (db and db.insets and db.insets > 0) and db.insets or autoInset
        insets.left, insets.right, insets.top, insets.bottom = ins, ins, ins, ins
    elseif borderStyle == "dialog" then
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border"
        edgeSize = (db and db.edgeSize) or 16
        local autoInset = math.max(4, math.floor(edgeSize * 0.28))
        local ins = (db and db.insets and db.insets > 0) and db.insets or autoInset
        insets.left, insets.right, insets.top, insets.bottom = ins, ins, ins, ins
    elseif borderStyle == "toast" then
        edgeFile = "Interface\\FriendsFrame\\UI-Toast-Border"
        edgeSize = (db and db.edgeSize) or 12
        local autoInset = math.max(3, math.floor(edgeSize * 0.25))
        local ins = (db and db.insets and db.insets > 0) and db.insets or autoInset
        insets.left, insets.right, insets.top, insets.bottom = ins, ins, ins, ins
    elseif borderStyle == "thin" then
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border"
        edgeSize = (db and db.edgeSize) or 12
        local autoInset = math.max(4, math.floor(edgeSize * 0.32))
        local ins = (db and db.insets and db.insets > 0) and db.insets or autoInset
        insets.left, insets.right, insets.top, insets.bottom = ins, ins, ins, ins
    elseif borderStyle == "none" then
        edgeFile = nil
        edgeSize = 0
        insets.left, insets.right, insets.top, insets.bottom = 0, 0, 0, 0
    else -- "flat"
        local bw = (db and db.borderWidth)
        if bw == nil then bw = (db and db.edgeSize) or 1 end
        if bw <= 0 then
            edgeFile = nil
            edgeSize = 0
        else
            edgeFile = "Interface\\Buttons\\WHITE8x8"
            edgeSize = bw
        end
        local ins = (db and db.insets) or 0
        insets.left, insets.right, insets.top, insets.bottom = ins, ins, ins, ins
    end

    -- Return a fresh table reference so modern BackdropTemplateMixin never short-circuits on identical pointer
    return {
        bgFile = bgPath,
        edgeFile = edgeFile,
        tile = false,
        tileSize = 0,
        edgeSize = edgeSize,
        insets = insets,
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
    trackerFrame:SetFrameStrata("MEDIUM")
    trackerFrame:SetFrameLevel(10)
    trackerFrame:SetClampedToScreen(true)
    trackerFrame:SetMovable(true)
    trackerFrame:EnableMouse(true)
    trackerFrame:RegisterForDrag("LeftButton")
    trackerFrame:SetUserPlaced(false)

    -- Set Position from SavedVariables (Pinned to TOPLEFT for guaranteed downward expansion)
    self:RestorePosition()

    -- Smooth Dragging & Position Saving
    local function StartDragging()
        if ns.db and ns.db.isLocked then
            -- Shift+Drag bypasses lock for quick repositioning
            if IsShiftKeyDown() then
                -- Allow it — fall through
            else
                -- Brief notification so the user knows WHY it won't move
                if not trackerFrame._lastLockMsg or (GetTime() - trackerFrame._lastLockMsg > 3) then
                    trackerFrame._lastLockMsg = GetTime()
                    ns.Print("|cffff9900Tracker is locked.|r Hold |cff00ff00Shift|r and drag to move, or type |cff00c0ff/bfq unlock|r")
                end
                return
            end
        end
        trackerFrame.isMoving = true
        trackerFrame:StartMoving()

        -- Visual drag feedback: subtle highlight border glow
        if not trackerFrame.dragGlow then
            local glow = trackerFrame:CreateTexture(nil, "OVERLAY")
            glow:SetAllPoints(trackerFrame)
            glow:SetColorTexture(0.0, 0.75, 1.0, 0.12)
            trackerFrame.dragGlow = glow
        end
        trackerFrame.dragGlow:Show()
    end

    local function StopDragging()
        if not trackerFrame.isMoving then return end
        trackerFrame.isMoving = false
        trackerFrame:StopMovingOrSizing()

        if trackerFrame.dragGlow then
            trackerFrame.dragGlow:Hide()
        end

        local uipTop = UIParent:GetTop() or 768
        local uipRight = UIParent:GetRight() or 1024
        local top = trackerFrame:GetTop() or uipTop
        local left = trackerFrame:GetLeft() or 0
        local right = trackerFrame:GetRight() or uipRight

        -- Always anchor from TOP so the frame strictly expands downward and never creeps into the minimap.
        -- Choose TOPRIGHT if placed on the right half of the screen, or TOPLEFT if on the left half.
        local anchorPoint, relX, relY
        local isRightHalf = (left + (trackerFrame:GetWidth() / 2)) > (uipRight / 2)

        if isRightHalf then
            anchorPoint = "TOPRIGHT"
            relX = math.floor((right - uipRight) + 0.5)
            relY = math.floor((top - uipTop) + 0.5)
        else
            anchorPoint = "TOPLEFT"
            relX = math.floor(left + 0.5)
            relY = math.floor((top - uipTop) + 0.5)
        end

        local currentDB = (ns.dbObject and ns.dbObject.profile) or ns.db

        if currentDB then
            currentDB.framePosition = {
                point = anchorPoint,
                relativePoint = anchorPoint,
                x = relX,
                y = relY,
            }
            ns.db = currentDB

            trackerFrame:ClearAllPoints()
            trackerFrame:SetPoint(anchorPoint, UIParent, anchorPoint, relX, relY)
            trackerFrame:SetUserPlaced(false)

            -- Per-character fail-safe backup
            if not _G["BleakfiberTrackerCharDB"] then
                _G["BleakfiberTrackerCharDB"] = {}
            end
            _G["BleakfiberTrackerCharDB"].framePosition = currentDB.framePosition

            if ns.FlushDBToGlobals then
                ns.FlushDBToGlobals()
            end

            ns.Debug(string.format("[Drag] Fixed to TOP: %s at (%d, %d)", anchorPoint, relX, relY))
        else
            trackerFrame:SetUserPlaced(false)
        end

        if ns.StandaloneTracker and ns.StandaloneTracker.UpdateItemButton then
            ns.StandaloneTracker:UpdateItemButton()
        end

        if ns.FireCallback then
            ns:FireCallback("TRACKER_DOCKING_CHANGED")
        end
    end

    self.StartDragging = StartDragging
    self.StopDragging = StopDragging
    Tracker.StartDragging = StartDragging
    Tracker.StopDragging = StopDragging

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
    header:SetFrameLevel(35)
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
        local _, nQuests = ns.GetNumQuestLogEntries()
        local mQuests = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or MAX_QUESTLOG_QUESTS or 40
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("|cff00c0ffBleakfiber's Quest Tracker|r")
        GameTooltip:AddLine(string.format("Quest Log Capacity: |cffffffff%d / %d|r", nQuests or 0, mQuests), 0.8, 0.8, 0.8)
        if trackerFrame and trackerFrame.trackedCount then
            GameTooltip:AddLine(string.format("Shown in Tracker: |cffffffff%d|r", trackerFrame.trackedCount), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-Click & Drag anywhere: Move tracker", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cff00ff00Shift + Drag: Move even when locked|r", 0.2, 1, 0.2)
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
        if InCombatLockdown and InCombatLockdown() then
            if UIErrorsFrame and UIErrorsFrame.AddMessage then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "Cannot toggle quest log in combat", 1.0, 0.1, 0.1, 1.0)
            end
            return
        end
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
        if ns.StandaloneTracker and ns.StandaloneTracker.UpdateItemButtonVisibility then
            ns.StandaloneTracker:UpdateItemButtonVisibility()
        end
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function(self, xrange, yrange)
        if ns.StandaloneTracker and ns.StandaloneTracker.UpdateItemButtonVisibility then
            ns.StandaloneTracker:UpdateItemButtonVisibility()
        end
    end)

    -- Alt + Right-Click to open settings from scroll area, Drag anywhere to reposition
    scrollFrame:EnableMouse(true)
    scrollFrame:RegisterForDrag("LeftButton")
    scrollFrame:SetScript("OnDragStart", StartDragging)
    scrollFrame:SetScript("OnDragStop", StopDragging)
    scrollFrame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and IsAltKeyDown() then
            if ns.Config then ns.Config:ToggleConfigFrame() end
        elseif button == "LeftButton" and trackerFrame.isMoving then
            StopDragging()
        end
    end)

    -- Scroll Child (Content Frame holding Quest Blocks)
    contentFrame = CreateFrame("Frame", nil, scrollFrame)
    self.contentFrame = contentFrame
    contentFrame:SetWidth(trackerFrame:GetWidth() - 12)
    contentFrame:SetHeight(1)
    contentFrame:EnableMouse(true)
    contentFrame:EnableMouseWheel(true)
    contentFrame:SetScript("OnMouseWheel", function(self, delta)
        local onWheel = scrollFrame and scrollFrame:GetScript("OnMouseWheel")
        if onWheel then
            onWheel(scrollFrame, delta)
        end
    end)
    contentFrame:RegisterForDrag("LeftButton")
    contentFrame:SetScript("OnDragStart", StartDragging)
    contentFrame:SetScript("OnDragStop", StopDragging)
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

    if trackerFrame.ClearBackdrop then
        trackerFrame:ClearBackdrop()
    end
    trackerFrame.backdropInfo = nil

    if db.show then
        local cfg = GetBackdropConfig()
        local bg = db.bgColor or { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
        local border = db.borderColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.9 }
        local br, bg_c, bb, ba = border.r, border.g, border.b, (border.a or 0.9)
        if db.classColorBorder and ns.GetClassColor then
            local cc = ns.GetClassColor()
            if cc then
                br, bg_c, bb = cc.r, cc.g, cc.b
            end
        end

        local bgTexKey = (db and db.bgTexture) or "solid"
        if bgTexKey == "parchment" or bgTexKey == "parchment_clean" then
            if not trackerFrame.parchmentTex then
                local tex = trackerFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
                trackerFrame.parchmentTex = tex
            end
            local ins = (cfg.insets and cfg.insets.left) or 4
            trackerFrame.parchmentTex:ClearAllPoints()
            trackerFrame.parchmentTex:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", ins, -ins)
            trackerFrame.parchmentTex:SetPoint("BOTTOMRIGHT", trackerFrame, "BOTTOMRIGHT", -ins, ins)
            if bgTexKey == "parchment_clean" then
                trackerFrame.parchmentTex:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal")
                trackerFrame.parchmentTex:SetTexCoord(0, 1, 0, 1)
            else
                trackerFrame.parchmentTex:SetTexture("Interface\\QuestFrame\\QuestBG")
                -- QuestBG artwork is 300x380 px on a 512x512 canvas (X: 0 to 0.5859, Y: 0 to 0.7422).
                -- Normalized crop (0.005, 0.582, 0.020, 0.650) extracts 100% solid parchment,
                -- eliminating transparent right/bottom margins and curled/torn scroll edges so it spans 100% of the frame.
                trackerFrame.parchmentTex:SetTexCoord(0.005, 0.582, 0.020, 0.650)
            end
            trackerFrame.parchmentTex:SetVertexColor(bg.r, bg.g, bg.b, bg.a)
            trackerFrame.parchmentTex:Show()

            cfg.bgFile = nil
            trackerFrame:SetBackdrop(cfg)
            trackerFrame:SetBackdropColor(0, 0, 0, 0)
        else
            if trackerFrame.parchmentTex then
                trackerFrame.parchmentTex:Hide()
            end
            trackerFrame:SetBackdrop(cfg)
            trackerFrame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
        end

        if cfg.edgeFile then
            trackerFrame:SetBackdropBorderColor(br, bg_c, bb, ba)
        else
            trackerFrame:SetBackdropBorderColor(0, 0, 0, 0)
        end
    else
        if trackerFrame.parchmentTex then
            trackerFrame.parchmentTex:Hide()
        end
        trackerFrame:SetBackdrop(nil)
    end

    if ns.DataBarsModule and ns.DataBarsModule.RefreshBars then
        ns.DataBarsModule:RefreshBars()
    end
end

function Tracker:ApplyHeaderSettings()
    if not trackerFrame or not trackerFrame.header then return end
    local header = trackerFrame.header
    header:SetFrameLevel(35)
    local db = ns.db or ns.defaultDB.profile
    local hCfg = db.headers or ns.defaultDB.profile.headers

    local borderColor = (db.backdrop and db.backdrop.borderColor) or { r = 0.15, g = 0.15, b = 0.15, a = 0.9 }
    if db.backdrop and db.backdrop.classColorBorder and ns.GetClassColor then
        local cc = ns.GetClassColor()
        if cc then
            borderColor = { r = cc.r, g = cc.g, b = cc.b, a = borderColor.a or 0.9 }
        end
    end
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
            if ns.FlushDBToGlobals then
                ns.FlushDBToGlobals()
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
        local filtering = ns.db.filtering
        local isFiltering = filtering.filterMode == "zone" or filtering.zoneOnly or filtering.filterMode == "watched" or filtering.watchedOnly
        if not isFiltering then
            local _, numQuests = ns.GetNumQuestLogEntries()
            if (numQuests or 0) == 0 and trackerFrame then
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
    local headerFontName = fonts.headerFont or fonts.font or "Nata Sans Bold"
    local headerFontPath = (ns.FetchFont and ns.FetchFont(headerFontName))
        or (LSM and LSM:Fetch("font", headerFontName, true))
        or ns.DEFAULT_HEADER_FONT_PATH
        or ns.DEFAULT_FONT_PATH
        or STANDARD_TEXT_FONT

    local objectiveFontName = fonts.objectiveFont or "Nata Sans Regular"
    local objectiveFontPath = (ns.FetchFont and ns.FetchFont(objectiveFontName))
        or (LSM and LSM:Fetch("font", objectiveFontName, true))
        or ns.DEFAULT_OBJECTIVE_FONT_PATH
        or headerFontPath
        or STANDARD_TEXT_FONT

    local titleSize = fonts.headerSize or 13
    local objSize = fonts.objectiveSize or 11
    local zoneSize = fonts.zoneHeaderSize or math.max(10, titleSize - 1)
    local enableShadow = fonts.enableTextShadow ~= false
    local outline = fonts.headerOutline
    if not outline or outline == "NONE" or outline == "" then
        outline = nil
    end
    local objOutline = fonts.objectiveOutline
    if not objOutline or objOutline == "NONE" or objOutline == "" then
        objOutline = nil
    end

    if trackerFrame and trackerFrame.header then
        if trackerFrame.header.titleText then
            if outline then
                trackerFrame.header.titleText:SetFont(headerFontPath, titleSize, outline)
            else
                trackerFrame.header.titleText:SetFont(headerFontPath, titleSize)
            end
            if enableShadow then
                trackerFrame.header.titleText:SetShadowColor(0, 0, 0, 0.85)
                trackerFrame.header.titleText:SetShadowOffset(1, -1)
            else
                trackerFrame.header.titleText:SetShadowOffset(0, 0)
            end
            trackerFrame.header:SetHeight(math.max(24, titleSize + 8))
        end
        if trackerFrame.header.countText then
            if outline then
                trackerFrame.header.countText:SetFont(headerFontPath, math.max(9, titleSize - 2), outline)
            else
                trackerFrame.header.countText:SetFont(headerFontPath, math.max(9, titleSize - 2))
            end
            if enableShadow then
                trackerFrame.header.countText:SetShadowColor(0, 0, 0, 0.85)
                trackerFrame.header.countText:SetShadowOffset(1, -1)
            else
                trackerFrame.header.countText:SetShadowOffset(0, 0)
            end
        end
    end

    if ns.StandaloneTracker and ns.StandaloneTracker.ApplyTypography then
        ns.StandaloneTracker:ApplyTypography(headerFontPath, objectiveFontPath, titleSize, objSize, outline, objOutline, zoneSize, enableShadow)
    end
    if ns.DataBarsModule and ns.DataBarsModule.ApplyTypography then
        ns.DataBarsModule:ApplyTypography(headerFontPath)
    end
    if ns.WayfinderModule and ns.WayfinderModule.ApplyTypography then
        ns.WayfinderModule:ApplyTypography(headerFontPath)
    end
end

function Tracker:GetDefaultPosition()
    local uipTop = UIParent:GetTop() or 768
    local minimapBottom
    if Minimap and Minimap.GetBottom and Minimap:GetBottom() then
        minimapBottom = Minimap:GetBottom()
    elseif MinimapCluster and MinimapCluster.GetBottom and MinimapCluster:GetBottom() then
        minimapBottom = MinimapCluster:GetBottom()
    end

    local yOfs
    if minimapBottom and uipTop then
        -- 35px below the bottom of the minimap
        yOfs = math.floor((minimapBottom - 35) - uipTop + 0.5)
    else
        yOfs = -220
    end

    -- Farthest right of the screen (0px offset from right edge)
    return "TOPRIGHT", 0, yOfs
end

function Tracker:RestorePosition()
    if not trackerFrame then return end
    local db = (ns.dbObject and ns.dbObject.profile) or ns.db

    trackerFrame:SetUserPlaced(false)
    trackerFrame:ClearAllPoints()

    local pos = (db and db.framePosition) 
        or (_G["BleakfiberTrackerCharDB"] and _G["BleakfiberTrackerCharDB"].framePosition)

    -- If position is the legacy default (-250, -200) or missing, update to the new default (farthest right, 35px below minimap)
    local isLegacyDefault = pos and (pos.x == -250 and pos.y == -200)

    if pos and pos.point and pos.x and pos.y and not isLegacyDefault then
        if db and not db.framePosition then
            db.framePosition = pos
        end

        -- Ensure anchor is ALWAYS TOPLEFT or TOPRIGHT so the frame exclusively grows downward
        if pos.point ~= "TOPLEFT" and pos.point ~= "TOPRIGHT" then
            trackerFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x, pos.y)

            local uipTop = UIParent:GetTop() or 768
            local uipRight = UIParent:GetRight() or 1024
            local top = trackerFrame:GetTop() or (uipTop - 200)
            local right = trackerFrame:GetRight() or (uipRight - 250)
            local left = trackerFrame:GetLeft() or 0

            local isRight = (pos.point:find("RIGHT") ~= nil) or ((left + (trackerFrame:GetWidth() / 2)) > (uipRight / 2))
            local newPoint = isRight and "TOPRIGHT" or "TOPLEFT"
            local newX = isRight and math.floor((right - uipRight) + 0.5) or math.floor(left + 0.5)
            local newY = math.floor((top - uipTop) + 0.5)

            pos.point = newPoint
            pos.relativePoint = newPoint
            pos.x = newX
            pos.y = newY
            if db then db.framePosition = pos end
            if _G["BleakfiberTrackerCharDB"] then _G["BleakfiberTrackerCharDB"].framePosition = pos end

            trackerFrame:ClearAllPoints()
            trackerFrame:SetPoint(newPoint, UIParent, newPoint, newX, newY)
            ns.Debug(string.format("[Restore Sanitized] Converted legacy anchor to %s at (%d, %d)", newPoint, newX, newY))
        else
            trackerFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x, pos.y)
            ns.Debug(string.format("[Restore] Set %s relative to %s at (%d, %d)", pos.point, pos.relativePoint or pos.point, pos.x, pos.y))
        end
    else
        local defPoint, defX, defY = self:GetDefaultPosition()
        trackerFrame:SetPoint(defPoint, UIParent, defPoint, defX, defY)
        ns.Debug(string.format("[Restore Default] Set %s at (%d, %d) [35px below minimap, farthest right]", defPoint, defX, defY))
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
    if ns.FlushDBToGlobals then
        ns.FlushDBToGlobals()
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

    if ns.FireCallback then
        ns:FireCallback("TRACKER_DOCKING_CHANGED")
    end
end

function Tracker:SetLocked(locked)
    ns.db.isLocked = locked
    if ns.FlushDBToGlobals then
        ns.FlushDBToGlobals()
    end
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

    if ns.StandaloneTracker and ns.StandaloneTracker.UpdateItemButton then
        ns.StandaloneTracker:UpdateItemButton()
    end

    if ns.FireCallback then
        ns:FireCallback("TRACKER_DOCKING_CHANGED")
    end
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
    local header = trackerFrame.header
    local headerH = header and header:GetHeight() or 24
    local prevHeight = trackerFrame:GetHeight()

    if (contentHeight or 0) <= 0 then
        -- No quests to display: collapse down to just the frame header bar
        if scrollFrame then scrollFrame:Hide() end
        local newH = headerH + 12
        trackerFrame:SetHeight(newH)
        if contentFrame then contentFrame:SetHeight(1) end
        if prevHeight ~= newH and ns.FireCallback then
            ns:FireCallback("TRACKER_DOCKING_CHANGED")
        end
        return
    end

    if scrollFrame and not scrollFrame:IsShown() then
        scrollFrame:Show()
    end

    local pad = 16
    local totalNeeded = contentHeight + headerH + pad
    local maxAllowed = db.maxHeight or 600

    local finalHeight = math.min(maxAllowed, totalNeeded)
    local targetHeight = math.max(finalHeight, headerH + pad)
    trackerFrame:SetHeight(targetHeight)
    contentFrame:SetHeight(contentHeight)

    if prevHeight ~= targetHeight and ns.FireCallback then
        ns:FireCallback("TRACKER_DOCKING_CHANGED")
    end
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

    local isCombatHidden = ns.db and ns.db.filtering and ns.db.filtering.hideInCombat and (InCombatLockdown and InCombatLockdown())
    if isCombatHidden then
        trackerFrame:Hide()
        return
    end

    -- Auto-hide when empty if configured (outside combat only to prevent ADDON_ACTION_BLOCKED)
    local filtering = ns.db and ns.db.filtering or {}
    local isFiltering = filtering.filterMode == "zone" or filtering.zoneOnly or filtering.filterMode == "watched" or filtering.watchedOnly

    if not InCombatLockdown() then
        if isFiltering and (trackedCount or 0) == 0 then
            -- When filtering (e.g. Current Zone) and no quests match, NEVER disappear entirely;
            -- keep visible and collapsed down to just the frame header so the user can switch filters.
            trackerFrame:Show()
        elseif filtering.autoHideEmpty then
            if (trackedCount or 0) == 0 and (numQuests or 0) == 0 then
                trackerFrame:Hide()
            else
                trackerFrame:Show()
            end
        else
            trackerFrame:Show()
        end
    end
end

function Tracker:UpdateVisibility()
    if not trackerFrame then return end
    local db = ns.db or ns.defaultDB.profile
    local filtering = db.filtering or {}

    if filtering.hideInCombat and (InCombatLockdown and InCombatLockdown()) then
        trackerFrame:Hide()
        if ns.StandaloneTracker and ns.StandaloneTracker.itemButton then
            ns.StandaloneTracker.itemButton:SetAlpha(0)
        end
        return
    end

    local isFiltering = filtering.filterMode == "zone" or filtering.zoneOnly or filtering.filterMode == "watched" or filtering.watchedOnly
    if filtering.autoHideEmpty and not isFiltering then
        local _, numQuests = ns.GetNumQuestLogEntries()
        if (numQuests or 0) == 0 then
            trackerFrame:Hide()
            return
        end
    end

    trackerFrame:Show()
    if ns.StandaloneTracker and ns.StandaloneTracker.itemButton then
        ns.StandaloneTracker.itemButton:SetAlpha(1)
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

