local addonName, ns = ...

local Config = {}
ns.Config = Config

-- Dedicated Copy URL Dialog Frame
local copyDialogFrame

local function GetOrCreateCopyDialog()
    if copyDialogFrame then return copyDialogFrame end

    copyDialogFrame = CreateFrame("Frame", "BleakfiberCopyURLDialog", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    copyDialogFrame:SetSize(420, 110)
    copyDialogFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    copyDialogFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    copyDialogFrame:SetFrameLevel(110)
    copyDialogFrame:SetClampedToScreen(true)
    copyDialogFrame:EnableMouse(true)
    copyDialogFrame:SetMovable(true)
    copyDialogFrame:RegisterForDrag("LeftButton")
    copyDialogFrame:SetScript("OnDragStart", copyDialogFrame.StartMoving)
    copyDialogFrame:SetScript("OnDragStop", copyDialogFrame.StopMovingOrSizing)

    copyDialogFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    copyDialogFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    copyDialogFrame:SetBackdropBorderColor(0.15, 0.55, 0.95, 0.9)

    -- Header Title
    local title = copyDialogFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    copyDialogFrame.title = title
    title:SetPoint("TOPLEFT", copyDialogFrame, "TOPLEFT", 14, -12)
    title:SetPoint("RIGHT", copyDialogFrame, "RIGHT", -30, 0)
    title:SetJustifyH("LEFT")
    title:SetText("|cff00c0ffBleakfiber's Quest Tracker|r - Copy Wowhead URL")

    -- Instruction text
    local note = copyDialogFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    note:SetText("Press |cff00ff00Ctrl+C|r to copy the link, then press |cff00ff00Enter|r or |cff00ff00Escape|r to close:")

    -- Close Button [X]
    local closeBtn = CreateFrame("Button", nil, copyDialogFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", copyDialogFrame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() copyDialogFrame:Hide() end)

    -- EditBox
    local editBox = CreateFrame("EditBox", "BleakfiberCopyURLEditBox", copyDialogFrame, "InputBoxTemplate")
    copyDialogFrame.editBox = editBox
    editBox:SetSize(390, 24)
    editBox:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 4, -8)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) copyDialogFrame:Hide() end)
    editBox:SetScript("OnEnterPressed", function(self) copyDialogFrame:Hide() end)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    -- Done Button
    local doneBtn = CreateFrame("Button", nil, copyDialogFrame, "UIPanelButtonTemplate")
    doneBtn:SetSize(80, 22)
    doneBtn:SetPoint("BOTTOMRIGHT", copyDialogFrame, "BOTTOMRIGHT", -14, 10)
    doneBtn:SetText("Done")
    doneBtn:SetScript("OnClick", function() copyDialogFrame:Hide() end)

    if UISpecialFrames then
        tinsert(UISpecialFrames, "BleakfiberCopyURLDialog")
    end

    return copyDialogFrame
end

function Config:ShowCopyDialog(url, questTitle)
    local dialog = GetOrCreateCopyDialog()
    if questTitle and questTitle ~= "" then
        dialog.title:SetText("|cff00c0ffBleakfiber's Quest Tracker|r - " .. questTitle)
    else
        dialog.title:SetText("|cff00c0ffBleakfiber's Quest Tracker|r - Copy Wowhead URL")
    end
    dialog:Show()
    dialog:Raise()
    dialog.editBox:SetText(url or "")
    dialog.editBox:SetFocus()
    dialog.editBox:HighlightText()
end

-- Dedicated Custom Quick Menu Frame (Independent of Blizzard UIDropDownMenu)
local quickMenuPopup = nil
local quickMenuCatcher = nil

local function GetOrCreateQuickMenu()
    if quickMenuPopup then return quickMenuPopup end

    -- Fullscreen dismiss click-catcher
    quickMenuCatcher = CreateFrame("Button", "BleakfiberQuickMenuCatcher", UIParent)
    quickMenuCatcher:SetAllPoints(UIParent)
    quickMenuCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
    quickMenuCatcher:SetFrameLevel(90)
    quickMenuCatcher:EnableMouse(true)
    quickMenuCatcher:Hide()
    quickMenuCatcher:SetScript("OnClick", function()
        if quickMenuPopup then quickMenuPopup:Hide() end
    end)

    local menu = CreateFrame("Frame", "BleakfiberQuickMenuPopup", UIParent, "BackdropTemplate")
    if not menu.SetBackdrop and BackdropTemplateMixin then
        Mixin(menu, BackdropTemplateMixin)
    end
    quickMenuPopup = menu
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(100)
    menu:SetWidth(225)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()

    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    menu:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    menu:SetBackdropBorderColor(0.20, 0.60, 0.95, 0.85)

    menu:SetScript("OnShow", function()
        quickMenuCatcher:Show()
    end)
    menu:SetScript("OnHide", function()
        quickMenuCatcher:Hide()
    end)

    return menu
end

-- Filter & Quick Options Menu for Tracker Header
function Config:OpenFilterMenu(anchor)
    local db = ns.db
    if not db then return end

    local menu = GetOrCreateQuickMenu()
    if menu:IsShown() then
        menu:Hide()
        return
    end

    if not menu.items then
        menu.items = {}
    end
    for _, item in ipairs(menu.items) do
        item:Hide()
    end

    local rows = {
        { type = "title", text = "|cff00c0ffTracker Options|r" },
        { type = "sep" },
        { type = "header", text = "Sort Quests" },
        {
            type = "radio",
            text = "Level",
            checked = (db.sorting.mode == "level"),
            onClick = function()
                db.sorting.mode = "level"
                ns:FireCallback("QUEST_DATA_CHANGED")
            end,
        },
        {
            type = "radio",
            text = "Zone",
            checked = (db.sorting.mode == "zone"),
            onClick = function()
                db.sorting.mode = "zone"
                ns:FireCallback("QUEST_DATA_CHANGED")
            end,
        },
    }

    table.insert(rows, {
        type = "checkbox",
        text = "Active Quest on Top",
        checked = not (db.sorting and db.sorting.activeOnTop == false),
        onClick = function()
            db.sorting = db.sorting or {}
            db.sorting.activeOnTop = not (db.sorting.activeOnTop ~= false)
            ns:FireCallback("QUEST_DATA_CHANGED")
        end,
    })

    table.insert(rows, {
        type = "checkbox",
        text = "Completed to Bottom",
        checked = db.sorting and db.sorting.moveCompletedToBottom,
        onClick = function()
            db.sorting = db.sorting or {}
            db.sorting.moveCompletedToBottom = not db.sorting.moveCompletedToBottom
            ns:FireCallback("QUEST_DATA_CHANGED")
        end,
    })

    table.insert(rows, {
        type = "checkbox",
        text = "Color by Difficulty",
        checked = not (db.fonts and db.fonts.colorDifficulty == false),
        onClick = function()
            db.fonts = db.fonts or {}
            db.fonts.colorDifficulty = not (db.fonts.colorDifficulty ~= false)
            ns:FireCallback("QUEST_DATA_CHANGED")
        end,
    })

    table.insert(rows, {
        type = "checkbox",
        text = "Show Complete Icon (?)",
        checked = not (db.headers and db.headers.showCompleteIcon == false),
        onClick = function()
            db.headers = db.headers or {}
            db.headers.showCompleteIcon = not (db.headers.showCompleteIcon ~= false)
            ns:FireCallback("QUEST_DATA_CHANGED")
        end,
    })

    table.insert(rows, {
        type = "checkbox",
        text = "Show Quest Rewards",
        checked = not (db.tooltips and db.tooltips.showRewards == false),
        onClick = function()
            db.tooltips = db.tooltips or {}
            db.tooltips.showRewards = not (db.tooltips.showRewards ~= false)
        end,
    })

    table.insert(rows, {
        type = "checkbox",
        text = "Show Party Members",
        checked = not (db.tooltips and db.tooltips.showPartyStatus == false),
        onClick = function()
            db.tooltips = db.tooltips or {}
            db.tooltips.showPartyStatus = not (db.tooltips.showPartyStatus ~= false)
        end,
    })

    table.insert(rows, { type = "sep" })
    table.insert(rows, { type = "header", text = "Wayfinder Navigation" })
    table.insert(rows, {
        type = "checkbox",
        text = "Show Floating Arrow",
        checked = db.wayfinder and db.wayfinder.enableHUDArrow,
        onClick = function()
            db.wayfinder = db.wayfinder or {}
            db.wayfinder.enableHUDArrow = not db.wayfinder.enableHUDArrow
            if ns.WayfinderModule then ns.WayfinderModule:RefreshState() end
        end,
    })
    table.insert(rows, {
        type = "checkbox",
        text = "Show Inline Mini-Arrow",
        checked = db.wayfinder and db.wayfinder.enableInlineArrow,
        onClick = function()
            db.wayfinder = db.wayfinder or {}
            db.wayfinder.enableInlineArrow = not db.wayfinder.enableInlineArrow
            if ns.WayfinderModule then ns.WayfinderModule:RefreshState() end
            ns:FireCallback("QUEST_DATA_CHANGED")
        end,
    })

    table.insert(rows, { type = "sep" })
    table.insert(rows, { type = "header", text = "Tracker Actions" })
    table.insert(rows, {
        type = "checkbox",
        text = "Show Zone Headers",
        checked = db.headers and db.headers.showZoneHeaders ~= false,
        onClick = function()
            db.headers = db.headers or {}
            db.headers.showZoneHeaders = not (db.headers.showZoneHeaders ~= false)
            ns:FireCallback("QUEST_DATA_CHANGED")
        end,
    })
    table.insert(rows, {
        type = "checkbox",
        text = "Lock Position",
        checked = db.isLocked,
        onClick = function()
            ns.Tracker:SetLocked(not db.isLocked)
        end,
    })
    table.insert(rows, {
        type = "button",
        text = "Expand All Quests",
        onClick = function()
            if db then
                db.collapsedQuests = {}
                ns:FireCallback("QUEST_DATA_CHANGED")
            end
            menu:Hide()
        end,
    })
    table.insert(rows, {
        type = "button",
        text = "Collapse All Quests",
        onClick = function()
            if db and ns.StandaloneTracker and ns.StandaloneTracker.GetTrackedQuests then
                db.collapsedQuests = db.collapsedQuests or {}
                local quests = ns.StandaloneTracker:GetTrackedQuests()
                for _, q in ipairs(quests) do
                    local key = q.questID or q.title
                    if key then
                        db.collapsedQuests[key] = true
                    end
                end
                ns:FireCallback("QUEST_DATA_CHANGED")
            end
            menu:Hide()
        end,
    })
    if db.headers and db.headers.showZoneHeaders ~= false then
        table.insert(rows, {
            type = "button",
            text = "Expand All Zones",
            onClick = function()
                if db then
                    db.collapsedZones = {}
                    ns:FireCallback("QUEST_DATA_CHANGED")
                end
                menu:Hide()
            end,
        })
        table.insert(rows, {
            type = "button",
            text = "Collapse All Zones",
            onClick = function()
                if db and ns.StandaloneTracker and ns.StandaloneTracker.GetTrackedQuests then
                    db.collapsedZones = db.collapsedZones or {}
                    local quests = ns.StandaloneTracker:GetTrackedQuests()
                    for _, q in ipairs(quests) do
                        local z = q.zone or "Other Quests"
                        db.collapsedZones[z] = true
                    end
                    ns:FireCallback("QUEST_DATA_CHANGED")
                end
                menu:Hide()
            end,
        })
    end

    table.insert(rows, { type = "sep" })
    local currentProfile = (ns.dbObject and ns.dbObject.GetCurrentProfile and ns.dbObject:GetCurrentProfile()) or "Default"
    table.insert(rows, { type = "header", text = "Profile: " .. currentProfile })
    table.insert(rows, {
        type = "button",
        text = "Settings & Appearance...",
        onClick = function()
            menu:Hide()
            Config:ToggleConfigFrame()
        end,
    })
    table.insert(rows, {
        type = "button",
        text = "Close",
        onClick = function()
            menu:Hide()
        end,
    })

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local fontPath = (ns.StandaloneTracker and ns.StandaloneTracker.fontPath)
        or (LSM and db.fonts and db.fonts.font and LSM:Fetch("font", db.fonts.font))
        or STANDARD_TEXT_FONT
        or "Fonts\\FRIZQT__.TTF"
    local fontSize = 11

    local function SafeSetFont(fs, path, size, flags)
        if not fs then return end
        if path and pcall(fs.SetFont, fs, path, size, flags or "") then return end
        if STANDARD_TEXT_FONT and pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, flags or "") then return end
    end

    local yOffset = -8
    for idx, row in ipairs(rows) do
        local item = menu.items[idx]
        if not item then
            item = CreateFrame("Button", nil, menu)
            item:SetWidth(209)
            item:SetHeight(18)
            item.highlight = item:CreateTexture(nil, "HIGHLIGHT")
            item.highlight:SetAllPoints()
            item.highlight:SetColorTexture(0, 0.75, 1, 0.15)

            item.line = item:CreateTexture(nil, "ARTWORK")
            item.line:SetHeight(1)
            item.line:SetPoint("LEFT", item, "LEFT", 2, 0)
            item.line:SetPoint("RIGHT", item, "RIGHT", -2, 0)
            item.line:SetColorTexture(1, 1, 1, 0.10)

            item.check = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            item.check:SetPoint("LEFT", item, "LEFT", 4, 0)

            item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            item.text:SetPoint("LEFT", item.check, "RIGHT", 6, 0)
            item.text:SetPoint("RIGHT", item, "RIGHT", -4, 0)
            item.text:SetJustifyH("LEFT")

            menu.items[idx] = item
        end

        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, yOffset)
        item:Show()

        if row.type == "title" then
            item:EnableMouse(false)
            if item.line then item.line:Hide() end
            item.check:SetText("")
            item.text:ClearAllPoints()
            item.text:SetAllPoints(item)
            SafeSetFont(item.text, fontPath, fontSize + 1, "OUTLINE")
            item.text:SetText(row.text)
            item.text:SetJustifyH("CENTER")
            yOffset = yOffset - 22
        elseif row.type == "sep" then
            item:EnableMouse(false)
            item.check:SetText("")
            item.text:SetText("")
            if item.line then item.line:Show() end
            yOffset = yOffset - 8
        elseif row.type == "header" then
            item:EnableMouse(false)
            if item.line then item.line:Hide() end
            item.check:SetText("")
            item.text:ClearAllPoints()
            item.text:SetPoint("LEFT", item, "LEFT", 4, 0)
            item.text:SetPoint("RIGHT", item, "RIGHT", -4, 0)
            SafeSetFont(item.text, fontPath, fontSize - 1, "OUTLINE")
            item.text:SetText("|cff00c0ff" .. row.text:upper() .. "|r")
            item.text:SetJustifyH("LEFT")
            yOffset = yOffset - 16
        elseif row.type == "radio" then
            item:EnableMouse(true)
            if item.line then item.line:Hide() end
            SafeSetFont(item.check, fontPath, fontSize, "")
            SafeSetFont(item.text, fontPath, fontSize, "")
            local mark = row.checked and "|cff00c0ff(*)|r" or "|cff666666( )|r"
            local color = row.checked and "|cffffffff" or "|cffcccccc"
            item.check:ClearAllPoints()
            item.check:SetPoint("LEFT", item, "LEFT", 4, 0)
            item.check:SetText(mark)
            item.text:ClearAllPoints()
            item.text:SetPoint("LEFT", item.check, "RIGHT", 6, 0)
            item.text:SetPoint("RIGHT", item, "RIGHT", -4, 0)
            item.text:SetText(color .. row.text .. "|r")
            item.text:SetJustifyH("LEFT")
            item:SetScript("OnClick", function()
                row.onClick()
                menu:Hide()
                Config:OpenFilterMenu(anchor)
            end)
            yOffset = yOffset - 18
        elseif row.type == "checkbox" then
            item:EnableMouse(true)
            if item.line then item.line:Hide() end
            SafeSetFont(item.check, fontPath, fontSize, "")
            SafeSetFont(item.text, fontPath, fontSize, "")
            local mark = row.checked and "|cff00ff00[x]|r" or "|cff666666[ ]|r"
            local color = row.checked and "|cffffffff" or "|cffcccccc"
            item.check:ClearAllPoints()
            item.check:SetPoint("LEFT", item, "LEFT", 4, 0)
            item.check:SetText(mark)
            item.text:ClearAllPoints()
            item.text:SetPoint("LEFT", item.check, "RIGHT", 6, 0)
            item.text:SetPoint("RIGHT", item, "RIGHT", -4, 0)
            item.text:SetText(color .. row.text .. "|r")
            item.text:SetJustifyH("LEFT")
            item:SetScript("OnClick", function()
                row.onClick()
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                menu:Hide()
                Config:OpenFilterMenu(anchor)
            end)
            yOffset = yOffset - 18
        elseif row.type == "button" then
            item:EnableMouse(true)
            if item.line then item.line:Hide() end
            item.check:SetText("")
            item.text:ClearAllPoints()
            item.text:SetAllPoints(item)
            SafeSetFont(item.text, fontPath, fontSize, "")
            item.text:SetText("|cff00c0ff" .. row.text .. "|r")
            item.text:SetJustifyH("CENTER")
            item:SetScript("OnClick", function()
                row.onClick()
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            end)
            yOffset = yOffset - 20
        end
    end

    menu:SetHeight(math.abs(yOffset) + 10)

    -- Anchor menu
    menu:ClearAllPoints()
    if anchor and anchor.GetRight and anchor:GetRight() then
        menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / scale, (y or 0) / scale)
    end

    menu:Show()
end
Config.OpenQuickMenu = Config.OpenFilterMenu

-- Ace3 & LibSharedMedia Config UI
local ACD = LibStub and LibStub("AceConfigDialog-3.0", true)
local ACR = LibStub and LibStub("AceConfigRegistry-3.0", true)
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local fontFlags = {
    [""] = "None",
    ["OUTLINE"] = "Outline",
    ["THICKOUTLINE"] = "Thick Outline",
    ["MONOCHROME"] = "Monochrome",
    ["OUTLINE, MONOCHROME"] = "Outline Monochrome",
}

local barBorderStyles = {
    ["flat"] = "Sleek 1px (Modern Flat)",
    ["tooltip"] = "Blizzard Tooltip (Classic Rounded)",
    ["dialog"] = "Blizzard Dialog (Classic Window)",
    ["toast"] = "Blizzard Toast (Soft Alert)",
    ["none"] = "None (Borderless)",
}

local function GetCustomSoundList()
    local list = {
        ["beep"] = "Bleakfiber Beep (beep.wav)",
        ["click"] = "Bleakfiber Click (click.wav)",
        ["custom1"] = "Custom Slot 1 (custom1.wav)",
        ["custom2"] = "Custom Slot 2 (custom2.wav)",
        ["custom3"] = "Custom Slot 3 (custom3.wav)",
        ["custom4"] = "Custom Slot 4 (custom4.wav)",
        ["custom5"] = "Custom Slot 5 (custom5.wav)",
        ["manual"] = "Manual File Path (Advanced)",
    }
    if LSM and LSM.List then
        local lsmSounds = LSM:List("sound")
        if type(lsmSounds) == "table" then
            for _, soundName in ipairs(lsmSounds) do
                if not list[soundName] then
                    list[soundName] = soundName
                end
            end
        end
    end
    return list
end

local function GetStatusbarTextureList()
    local list = {
        ["Solid"] = "Solid / Flat",
        ["Blizzard"] = "Blizzard Default Statusbar",
    }
    if LSM and LSM.List then
        local lsmTex = LSM:List("statusbar")
        if type(lsmTex) == "table" then
            for _, texName in ipairs(lsmTex) do
                if not list[texName] then
                    list[texName] = texName
                end
            end
        end
    end
    return list
end

function Config:ApplyModernGlassPreset()
    local db = ns.db
    if not db then return end
    db.backdrop = db.backdrop or {}
    db.backdrop.show = true
    db.backdrop.borderStyle = "flat"
    db.backdrop.borderWidth = 1
    db.backdrop.edgeSize = 1
    db.backdrop.insets = 0
    db.backdrop.bgTexture = "solid"
    db.backdrop.bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
    db.backdrop.borderColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.90 }
    db.backdrop.classColorBorder = false

    db.headers = db.headers or {}
    db.headers.texture = "flat"
    db.headers.textureColor = { r = 0.05, g = 0.08, b = 0.12, a = 0.85 }
    db.headers.zoneHeaderTexture = "gradient"
    db.headers.zoneHeaderColor = { r = 1.0, g = 0.82, b = 0.0, a = 1.0 }

    db.fonts = db.fonts or {}
    db.fonts.headerFont = "Nata Sans Bold"
    db.fonts.objectiveFont = "Nata Sans Regular"
    db.fonts.headerSize = 13
    db.fonts.objectiveSize = 11
    db.fonts.colorDifficulty = true

    if ns.Tracker then
        ns.Tracker:UpdateBackdrop()
        ns.Tracker:ApplyHeaderSettings()
        ns.Tracker:UpdateTypography()
    end
    if ns.StandaloneTracker and ns.StandaloneTracker.RequestUpdate then
        ns.StandaloneTracker:RequestUpdate(true)
    end
    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
end

function Config:ApplyClassicPreset()
    local db = ns.db
    if not db then return end
    db.backdrop = db.backdrop or {}
    db.backdrop.show = true
    db.backdrop.borderStyle = "tooltip"
    db.backdrop.edgeSize = 16
    db.backdrop.insets = 4
    db.backdrop.bgTexture = "parchment"
    db.backdrop.bgColor = { r = 0.96, g = 0.90, b = 0.78, a = 0.90 }
    db.backdrop.borderColor = { r = 0.80, g = 0.65, b = 0.20, a = 0.90 }
    db.backdrop.classColorBorder = false

    db.headers = db.headers or {}
    db.headers.texture = "gradient"
    db.headers.zoneHeaderTexture = "gradient"
    db.headers.zoneHeaderColor = { r = 1.0, g = 0.82, b = 0.0, a = 1.0 }

    db.fonts = db.fonts or {}
    db.fonts.headerFont = "Friz Quadrata TT"
    db.fonts.objectiveFont = "Friz Quadrata TT"
    db.fonts.headerSize = 13
    db.fonts.objectiveSize = 11
    db.fonts.colorDifficulty = true

    if ns.Tracker then
        ns.Tracker:UpdateBackdrop()
        ns.Tracker:ApplyHeaderSettings()
        ns.Tracker:UpdateTypography()
    end
    if ns.StandaloneTracker and ns.StandaloneTracker.RequestUpdate then
        ns.StandaloneTracker:RequestUpdate(true)
    end
    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
end

function Config:ApplyMinimalPreset()
    local db = ns.db
    if not db then return end
    db.backdrop = db.backdrop or {}
    db.backdrop.show = true
    db.backdrop.borderStyle = "none"
    db.backdrop.edgeSize = 0
    db.backdrop.insets = 0
    db.backdrop.bgTexture = "solid"
    db.backdrop.bgColor = { r = 0.0, g = 0.0, b = 0.0, a = 0.35 }
    db.backdrop.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    db.backdrop.classColorBorder = false

    db.headers = db.headers or {}
    db.headers.texture = "none"
    db.headers.zoneHeaderTexture = "none"

    if ns.Tracker then
        ns.Tracker:UpdateBackdrop()
        ns.Tracker:ApplyHeaderSettings()
        ns.Tracker:UpdateTypography()
    end
    if ns.StandaloneTracker and ns.StandaloneTracker.RequestUpdate then
        ns.StandaloneTracker:RequestUpdate(true)
    end
    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
end

local function GetOptionsTable()
    local db = ns.db
    if not db then return { type = "group", args = {} } end

    local fontList = (AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.font) 
        or (LSM and LSM:List("font")) 
        or { ["Friz Quadrata TT"] = "Friz Quadrata TT" }

    local options = {
        name = "|cff00c0ffBleakfiber's Quest Tracker|r",
        type = "group",
        childGroups = "tab",
        args = {
            general = {
                name = "General",
                type = "group",
                order = 1,
                args = {
                    desc = {
                        name = "General tracker behavior, position locking, and automation options.\n",
                        type = "description",
                        order = 0,
                    },
                    isLocked = {
                        name = "Lock Tracker Position",
                        desc = "Prevent moving the tracker by dragging its header.",
                        type = "toggle",
                        order = 1,
                        get = function() return db.isLocked end,
                        set = function(_, val)
                            db.isLocked = val
                            ns.Tracker:SetLocked(val)
                        end,
                    },
                    autoHideEmpty = {
                        name = "Auto-hide Tracker When Empty",
                        desc = "Automatically hide the tracker frame completely when you have zero quests in your quest log (disabled while filtering by zone or watched so the header remains accessible).",
                        type = "toggle",
                        width = "full",
                        order = 2,
                        get = function() return db.filtering and db.filtering.autoHideEmpty end,
                        set = function(_, val)
                            db.filtering = db.filtering or {}
                            db.filtering.autoHideEmpty = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    autoHideInInstances = {
                        name = "Auto-collapse in Dungeons & Raids",
                        desc = "Automatically collapse/minimize the tracker inside party dungeons and raid instances.",
                        type = "toggle",
                        width = "full",
                        order = 3,
                        get = function() return db.filtering and db.filtering.autoHideInInstances end,
                        set = function(_, val)
                            db.filtering = db.filtering or {}
                            db.filtering.autoHideInInstances = val
                            ns.Tracker:CheckInstanceAutoCollapse()
                        end,
                    },
                    hideInCombat = {
                        name = "Hide Tracker in Combat",
                        desc = "Automatically hide the quest tracker while engaged in combat, and restore it when combat ends (disabled by default).",
                        type = "toggle",
                        order = 3.5,
                        get = function() return db.filtering and db.filtering.hideInCombat end,
                        set = function(_, val)
                            db.filtering = db.filtering or {}
                            db.filtering.hideInCombat = val
                            if ns.Tracker and ns.Tracker.UpdateVisibility then
                                ns.Tracker:UpdateVisibility()
                            end
                        end,
                    },
                    filterMode = {
                        name = "Quest Filter Mode",
                        desc = "Choose which quests to display in the tracker: All quests, only quests matching your Current Zone, or Watched (shift-clicked) quests.",
                        type = "select",
                        order = 4,
                        values = {
                            ["all"] = "All Quests",
                            ["zone"] = "Current Zone Only",
                            ["watched"] = "Watched (Shift-Clicked) Only",
                        },
                        get = function()
                            return (db.filtering and db.filtering.filterMode) or ((db.filtering and db.filtering.zoneOnly) and "zone" or "all")
                        end,
                        set = function(_, val)
                            db.filtering = db.filtering or {}
                            db.filtering.filterMode = val
                            db.filtering.zoneOnly = (val == "zone")
                            if ns.Tracker and ns.Tracker.UpdateFilterButtons then
                                ns.Tracker:UpdateFilterButtons()
                            end
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    enableCrossZone = {
                        name = "Enable Cross-Zone Objective Tracking",
                        desc = "Intelligently display quests in their active objective or turn-in zones even if accepted elsewhere.",
                        type = "toggle",
                        width = "full",
                        order = 4.5,
                        get = function() return not (db.filtering and db.filtering.enableCrossZone == false) end,
                        set = function(_, val)
                            db.filtering = db.filtering or {}
                            db.filtering.enableCrossZone = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    itemButtonPlacement = {
                        name = "Quest Item Button Placement",
                        desc = "Select where usable quest item buttons are displayed:\n• Inside Tracker - Right: Inside the quest entry block, aligned to the right.\n• Outside Tracker - Left: Outside the tracker frame on the left side.",
                        type = "select",
                        width = "full",
                        order = 4.6,
                        values = {
                            ["inside_right"] = "Inside Tracker - Right",
                            ["outside_left"] = "Outside Tracker - Left",
                        },
                        get = function()
                            local val = db.itemButtonPlacement or "inside_right"
                            if val ~= "inside_right" and val ~= "outside_left" then
                                val = "inside_right"
                            end
                            return val
                        end,
                        set = function(_, val)
                            db.itemButtonPlacement = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            if ns.StandaloneTracker and ns.StandaloneTracker.UpdateItemButton then
                                ns.StandaloneTracker:UpdateItemButton()
                            end
                        end,
                    },
                    questItemKeybind = {
                        name = "Quest Item Keybind",
                        desc = "Click to set a keyboard shortcut to instantly use the active quest item button.",
                        type = "keybinding",
                        width = "full",
                        order = 4.65,
                        get = function()
                            local key1 = GetBindingKey("BLEAKFIBER_USE_QUEST_ITEM")
                            return key1 or ""
                        end,
                        set = function(_, key)
                            if key == "" then
                                local key1, key2 = GetBindingKey("BLEAKFIBER_USE_QUEST_ITEM")
                                if key1 then SetBinding(key1) end
                                if key2 then SetBinding(key2) end
                            else
                                local oldKey = GetBindingKey("BLEAKFIBER_USE_QUEST_ITEM")
                                if oldKey then SetBinding(oldKey) end
                                SetBinding(key, "BLEAKFIBER_USE_QUEST_ITEM")
                            end
                            SaveBindings(GetCurrentBindingSet())
                        end,
                    },
                    showTimerInObjectives = {
                        name = "Show Timers in Objective Descriptions",
                        desc = "Show a live countdown timer directly next to timed quest objectives (e.g. [04:12]). Only appears on quests with an active countdown timer.",
                        type = "toggle",
                        width = "full",
                        order = 4.7,
                        get = function() return db.showTimerInObjectives ~= false end,
                        set = function(_, val)
                            db.showTimerInObjectives = val
                            if ns.StandaloneTracker and ns.StandaloneTracker.RequestUpdate then
                                ns.StandaloneTracker:RequestUpdate(true)
                            end
                        end,
                    },
                    sizingHeader = {
                        name = "Tracker Dimensions & Sizing",
                        type = "header",
                        order = 4.8,
                    },
                    width = {
                        name = "Tracker Width (px)",
                        desc = "Set exact pixel width of the tracker frame (type px number or use slider).",
                        type = "range",
                        min = 180,
                        max = 600,
                        step = 5,
                        bigStep = 10,
                        order = 4.81,
                        get = function() return db.width or 280 end,
                        set = function(_, val)
                            db.width = math.floor(val + 0.5)
                            ns.Tracker:UpdateSettings()
                        end,
                    },
                    growCorner = {
                        name = "Grow Direction & Anchor Corner",
                        desc = "Sets which corner the tracker anchors to and grows from as quests are added.\n\n• Auto: Anchors to nearest screen corner based on where you drag it.\n• Bottom-Right: Anchors bottom-right and grows UP & LEFT.\n• Bottom-Left: Anchors bottom-left and grows UP & RIGHT.\n• Top-Right: Anchors top-right and grows DOWN & LEFT.\n• Top-Left: Anchors top-left and grows DOWN & RIGHT.",
                        type = "select",
                        order = 4.815,
                        values = {
                            ["AUTO"] = "Auto (Snap to Nearest Screen Corner)",
                            ["BOTTOMRIGHT"] = "Bottom-Right (Grows Up & Left)",
                            ["BOTTOMLEFT"] = "Bottom-Left (Grows Up & Right)",
                            ["TOPRIGHT"] = "Top-Right (Grows Down & Left)",
                            ["TOPLEFT"] = "Top-Left (Grows Down & Right)",
                        },
                        get = function() return db.growCorner or "AUTO" end,
                        set = function(_, val)
                            db.growCorner = val
                            if ns.Tracker and ns.Tracker.UpdateAnchorCorner then
                                ns.Tracker:UpdateAnchorCorner(val)
                            end
                        end,
                    },
                    maxHeight = {
                        name = "Grow Down Range / Max Height (px)",
                        desc = "The tracker dynamically auto-grows down to match active quest count. If content height exceeds this value, smooth scrolling begins.",
                        type = "range",
                        min = 100,
                        max = 1200,
                        step = 10,
                        bigStep = 25,
                        width = "full",
                        order = 4.82,
                        get = function() return db.maxHeight or 600 end,
                        set = function(_, val)
                            db.maxHeight = math.floor(val + 0.5)
                            ns.Tracker:UpdateSettings()
                        end,
                    },
                    scale = {
                        name = "Tracker UI Scale",
                        desc = "Adjust overall visual scale of the tracker frame.",
                        type = "range",
                        min = 0.7,
                        max = 1.5,
                        step = 0.05,
                        isPercent = true,
                        order = 4.83,
                        get = function() return db.scale or 1.0 end,
                        set = function(_, val)
                            db.scale = tonumber(string.format("%.2f", val))
                            ns.Tracker:UpdateSettings()
                        end,
                    },
                    showOverlay = {
                        name = "Show Bounds Overlay & Resize Handle",
                        desc = "Display the on-screen blue bounding box and [Drag to Resize] handle on the tracker.",
                        type = "toggle",
                        width = "full",
                        order = 4.84,
                        get = function()
                            return ns.Tracker and ns.Tracker.IsConfigOverlayShown and ns.Tracker:IsConfigOverlayShown()
                        end,
                        set = function(_, val)
                            if val then
                                ns.Tracker:ShowConfigOverlay()
                            else
                                ns.Tracker:HideConfigOverlay()
                            end
                        end,
                    },
                    sep = {
                        name = "",
                        type = "header",
                        order = 5,
                    },
                    onboardingBtn = {
                        name = "Run Setup Walkthrough",
                        desc = "Open the interactive first-time setup walkthrough modal (/bfq onboard).",
                        type = "execute",
                        order = 5.5,
                        func = function()
                            if ns.Onboarding and ns.Onboarding.ShowWizard then
                                ns.Onboarding:ShowWizard()
                            end
                        end,
                    },
                    resetPosition = {
                        name = "Reset Tracker Position",
                        desc = "Reset the tracker to the default screen position (top-right).",
                        type = "execute",
                        order = 6,
                        func = function()
                            if ns.Tracker and ns.Tracker.ResetPosition then
                                ns.Tracker:ResetPosition()
                            end
                            ns.Print("Position reset to default.")
                        end,
                    },
                    resetUntrackedQuests = {
                        name = "Reset Untracked Quests",
                        desc = "Restores all quests that were hidden from the tracker using the right-click 'Untrack Quest' menu.",
                        type = "execute",
                        order = 7,
                        func = function()
                            if db.filtering then
                                db.filtering.untrackedQuests = {}
                            end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                                ns.StandaloneTracker:UpdateTracker()
                            end
                            ns.Print("All untracked quests have been restored to the tracker.")
                        end,
                    },
                },
            },
            appearance = {
                name = "Appearance",
                type = "group",
                order = 2,
                childGroups = "tab",
                args = {
                    background = {
                        name = "Background",
                        type = "group",
                        order = 1,
                        args = {
                            desc = {
                                name = "Configure tracker window background surface textures, colors, and opacity.\n",
                                type = "description",
                                order = 0,
                            },
                            showBackdrop = {
                                name = "Show Background & Backdrop",
                                desc = "Toggle tracker background surface and backdrop visibility on or off.",
                                type = "toggle",
                                width = "full",
                                order = 1,
                                get = function() return db.backdrop.show end,
                                set = function(_, val)
                                    db.backdrop.show = val
                                    ns.Tracker:UpdateBackdrop()
                                end,
                            },
                            bgTexture = {
                                name = "Background Surface Texture",
                                desc = "Select the background surface texture for the tracker window:\n• Solid / Flat: Sleek modern dark backdrop.\n• Blizzard Tooltip Dark: Authentic dark tooltip parchment.\n• Blizzard Marble: Classic World of Warcraft marble stone.\n• Blizzard Rock: Rugged stone background.\n• Blizzard Quest Parchment: Authentic Classic quest parchment with 100% full-bleed rectangular cropping.\n• Blizzard Parchment (Clean): Seamless horizontal parchment from Blizzard achievements.",
                                type = "select",
                                width = "full",
                                order = 2,
                                disabled = function() return not db.backdrop.show end,
                                values = {
                                    ["solid"] = "Solid / Flat",
                                    ["tooltip"] = "Blizzard Tooltip Dark",
                                    ["marble"] = "Blizzard Marble",
                                    ["rock"] = "Blizzard Rock",
                                    ["parchment"] = "Blizzard Quest Parchment",
                                    ["parchment_clean"] = "Blizzard Parchment (Clean)",
                                },
                                get = function() return db.backdrop.bgTexture or "solid" end,
                                set = function(_, val)
                                    local prev = db.backdrop.bgTexture or "solid"
                                    db.backdrop.bgTexture = val
                                    local isParchment = (val == "parchment" or val == "parchment_clean")
                                    local wasParchment = (prev == "parchment" or prev == "parchment_clean")
                                    if isParchment and not wasParchment then
                                        db.backdrop.bgColor = { r = 0.96, g = 0.90, b = 0.78, a = 0.90 }
                                    elseif not isParchment and wasParchment then
                                        db.backdrop.bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                                    end
                                    ns.Tracker:UpdateBackdrop()
                                    if ns.DataBarsModule and ns.DataBarsModule.RefreshBars then
                                        ns.DataBarsModule:RefreshBars()
                                    end
                                end,
                            },
                            bgColor = {
                                name = "Background Color & Opacity",
                                desc = "Set tracker background backdrop color and opacity. When Parchment is selected, warm paper colors are automatically applied.",
                                type = "color",
                                hasAlpha = true,
                                width = "full",
                                order = 3,
                                disabled = function() return not db.backdrop.show end,
                                get = function()
                                    local c = db.backdrop.bgColor or { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                                    return c.r, c.g, c.b, c.a
                                end,
                                set = function(_, r, g, b, a)
                                    db.backdrop.bgColor = { r = r, g = g, b = b, a = a }
                                    ns.Tracker:UpdateBackdrop()
                                end,
                            },
                            resetBgColor = {
                                name = "Reset Background Color to Default",
                                desc = "Reset the background color and opacity to default.",
                                type = "execute",
                                width = "full",
                                order = 4,
                                disabled = function() return not db.backdrop.show end,
                                func = function()
                                    if db.backdrop.bgTexture == "parchment" or db.backdrop.bgTexture == "parchment_clean" then
                                        db.backdrop.bgColor = { r = 0.96, g = 0.90, b = 0.78, a = 0.90 }
                                    else
                                        db.backdrop.bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                                    end
                                    ns.Tracker:UpdateBackdrop()
                                end,
                            },
                            textureNotes = {
                                name = "\n|cff00c0ffBackground & Texture Notes:|r\n• |cffffd100Solid / Flat|r: Minimalist dark glassmorphism aesthetic.\n• |cffffd100Blizzard Quest Parchment|r: Authentic Classic quest parchment automatically cropped to 100% full frame coverage.\n• |cffffd100Blizzard Parchment (Clean)|r: Modern seamless achievement parchment backdrop.\n• DataBars (XP Bar, Location Bar, Timer Bar) automatically inherit this texture and color by default unless overridden in the DataBars tab.",
                                type = "description",
                                order = 5,
                            },
                        },
                    },
                    borders = {
                        name = "Borders & Spacing",
                        type = "group",
                        order = 2,
                        args = {
                            desc = {
                                name = "Configure tracker border frame styles, corner rounding, thickness, class coloring, and module docking spacing.\n",
                                type = "description",
                                order = 0,
                            },
                            borderStyle = {
                                name = "Border Style",
                                desc = "Select the border frame style for the tracker window:\n• Sleek 1px: Modern flat border.\n• Blizzard Tooltip: Classic World of Warcraft rounded corner border.\n• Blizzard Dialog: Classic window border.\n• Blizzard Toast: Soft alert window border.\n• Blizzard Thin: Slim tooltip border.\n• None: Clean borderless backdrop.",
                                type = "select",
                                width = "full",
                                order = 1,
                                values = {
                                    ["flat"] = "Sleek 1px (Modern Flat)",
                                    ["tooltip"] = "Blizzard Tooltip (Classic Rounded)",
                                    ["dialog"] = "Blizzard Dialog (Classic Window)",
                                    ["toast"] = "Blizzard Toast (Soft Alert)",
                                    ["thin"] = "Blizzard Thin (Slim Border)",
                                    ["none"] = "None (Borderless)",
                                },
                                get = function() return db.backdrop.borderStyle or "flat" end,
                                set = function(_, val)
                                    db.backdrop.borderStyle = val
                                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                                    ns.Tracker:UpdateBackdrop()
                                    ns.Tracker:ApplyHeaderSettings()
                                    if ns.StandaloneTracker and ns.StandaloneTracker.RequestUpdate then
                                        ns.StandaloneTracker:RequestUpdate(true)
                                    end
                                end,
                            },
                            classColorBorder = {
                                name = "Class-Colored Border",
                                desc = "Automatically color the tracker border using your character's class color (e.g. green for Hunter, blue for Shaman).",
                                type = "toggle",
                                width = "full",
                                order = 2,
                                disabled = function() return db.backdrop.borderStyle == "none" end,
                                get = function() return db.backdrop.classColorBorder or false end,
                                set = function(_, val)
                                    db.backdrop.classColorBorder = val
                                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                                    ns.Tracker:UpdateBackdrop()
                                    ns.Tracker:ApplyHeaderSettings()
                                    if ns.StandaloneTracker and ns.StandaloneTracker.RequestUpdate then
                                        ns.StandaloneTracker:RequestUpdate(true)
                                    end
                                end,
                            },
                            borderColor = {
                                name = "Custom Border Color & Opacity",
                                desc = "Set tracker border color and opacity (used when Class-Colored Border is disabled).",
                                type = "color",
                                hasAlpha = true,
                                width = "full",
                                order = 3,
                                disabled = function() return db.backdrop.classColorBorder or db.backdrop.borderStyle == "none" end,
                                get = function()
                                    local c = db.backdrop.borderColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.9 }
                                    return c.r, c.g, c.b, c.a
                                end,
                                set = function(_, r, g, b, a)
                                    db.backdrop.borderColor = { r = r, g = g, b = b, a = a }
                                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                                    ns.Tracker:UpdateBackdrop()
                                    ns.Tracker:ApplyHeaderSettings()
                                    if ns.StandaloneTracker and ns.StandaloneTracker.RequestUpdate then
                                        ns.StandaloneTracker:RequestUpdate(true)
                                    end
                                end,
                            },
                            borderWidth = {
                                name = "Border Thickness (px)",
                                desc = "Set the pixel thickness of the flat border (0 for no border, up to 5px).",
                                type = "range",
                                min = 0,
                                max = 5,
                                step = 1,
                                bigStep = 1,
                                width = "full",
                                order = 4,
                                hidden = function() return (db.backdrop.borderStyle and db.backdrop.borderStyle ~= "flat") end,
                                get = function()
                                    if db.backdrop and db.backdrop.borderWidth ~= nil then
                                        return db.backdrop.borderWidth
                                    end
                                    return (db.backdrop and db.backdrop.edgeSize) or 1
                                end,
                                set = function(_, val)
                                    db.backdrop.borderWidth = val
                                    db.backdrop.edgeSize = val
                                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                                    ns.Tracker:UpdateBackdrop()
                                    if ns.DataBarsModule and ns.DataBarsModule.RefreshBars then
                                        ns.DataBarsModule:RefreshBars()
                                    end
                                end,
                            },
                            edgeSize = {
                                name = "Corner & Border Sizing (px)",
                                desc = "Adjust edge and corner size in pixels for classic rounded borders (default: 16px).",
                                type = "range",
                                width = "full",
                                min = 8,
                                max = 24,
                                step = 1,
                                order = 5,
                                hidden = function() return (not db.backdrop.borderStyle or db.backdrop.borderStyle == "flat" or db.backdrop.borderStyle == "none") end,
                                get = function() return db.backdrop.edgeSize or 16 end,
                                set = function(_, val)
                                    db.backdrop.edgeSize = val
                                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                                    ns.Tracker:UpdateBackdrop()
                                end,
                            },
                            dockSpacing = {
                                name = "DataBar Docking Spacing (px)",
                                desc = "Adjust the pixel spacing between the quest tracker frame and docked DataBars (XP bar, Location bar, Quest Timer bar), as well as between stacked bars. Range: 0 (seamless edge-to-edge docking) to 5px.",
                                type = "range",
                                min = 0,
                                max = 5,
                                step = 1,
                                bigStep = 1,
                                width = "full",
                                order = 6,
                                get = function() return (db.databars and db.databars.dockSpacing) or 0 end,
                                set = function(_, val)
                                    db.databars = db.databars or {}
                                    db.databars.dockSpacing = val
                                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                                    if ns.DataBarsModule then ns.DataBarsModule:UpdateAllDocking() end
                                end,
                            },
                        },
                    },
                    sizing = {
                        name = "Window Sizing",
                        type = "group",
                        order = 3,
                        args = {
                            desc = {
                                name = "Configure tracker frame dimensions, auto-growth height range, and display scaling.\n",
                                type = "description",
                                order = 0,
                            },
                            width = {
                                name = "Tracker Width (px)",
                                desc = "Set exact pixel width of the tracker frame (type px number or use slider).",
                                type = "range",
                                min = 180,
                                max = 600,
                                step = 5,
                                bigStep = 10,
                                width = "full",
                                order = 1,
                                get = function() return db.width or 280 end,
                                set = function(_, val)
                                    db.width = math.floor(val + 0.5)
                                    ns.Tracker:UpdateSettings()
                                end,
                            },
                            maxHeight = {
                                name = "Grow Down Range / Max Height (px)",
                                desc = "The tracker dynamically auto-grows down to match active quest count. If content height exceeds this value, smooth scrolling begins.",
                                type = "range",
                                min = 100,
                                max = 1200,
                                step = 10,
                                bigStep = 25,
                                width = "full",
                                order = 2,
                                get = function() return db.maxHeight or 600 end,
                                set = function(_, val)
                                    db.maxHeight = math.floor(val + 0.5)
                                    ns.Tracker:UpdateSettings()
                                end,
                            },
                            scale = {
                                name = "Tracker UI Scale",
                                desc = "Adjust overall visual scale of the tracker frame.",
                                type = "range",
                                min = 0.7,
                                max = 1.5,
                                step = 0.05,
                                isPercent = true,
                                width = "full",
                                order = 3,
                                get = function() return db.scale or 1.0 end,
                                set = function(_, val)
                                    db.scale = tonumber(string.format("%.2f", val))
                                    ns.Tracker:UpdateSettings()
                                end,
                            },
                            showOverlay = {
                                name = "Show Bounds Overlay & Resize Handle",
                                desc = "Display the on-screen blue bounding box and [Drag to Resize] handle on the tracker.",
                                type = "toggle",
                                width = "full",
                                order = 4,
                                get = function()
                                    return ns.Tracker and ns.Tracker.IsConfigOverlayShown and ns.Tracker:IsConfigOverlayShown()
                                end,
                                set = function(_, val)
                                    if val then
                                        ns.Tracker:ShowConfigOverlay()
                                    else
                                        ns.Tracker:HideConfigOverlay()
                                    end
                                end,
                            },
                            sizingNote = {
                                name = "|cff00c0ffAuto-Growth Active:|r Content dynamically auto-resizes the tracker frame, only capping and scrolling when content exceeds the Grow Down Range.",
                                type = "description",
                                order = 5,
                            },
                        },
                    },
                    headers = {
                        name = "Headers & Sections",
                        type = "group",
                        order = 4,
                        args = {
                            desc = {
                                name = "Configure tracker header bar textures, colors, counter formatting, buttons, and collapsible zone headers.\n",
                                type = "description",
                                order = 0,
                            },
                    mainHeader = {
                        name = "Tracker Header Bar",
                        type = "group",
                        inline = true,
                        order = 1,
                        args = {
                            texture = {
                                name = "Background Texture",
                                desc = "Select the background texture for the tracker header.",
                                type = "select",
                                order = 1,
                                values = {
                                    ["none"] = "None",
                                    ["flat"] = "Flat Bar",
                                    ["gradient"] = "Gradient Bar",
                                    ["blizzard"] = "Blizzard Objective Header",
                                },
                                get = function() return db.headers and db.headers.texture or "flat" end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.texture = val
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            textureColor = {
                                name = "Background Color",
                                desc = "Sets the color and opacity of the header background texture.",
                                type = "color",
                                hasAlpha = true,
                                order = 2,
                                disabled = function()
                                    return ((db.headers and db.headers.texture == "none") or (db.headers and db.headers.textureColorShare))
                                end,
                                get = function()
                                    local c = (db.headers and db.headers.textureColor) or { r = 0.05, g = 0.08, b = 0.12, a = 0.85 }
                                    return c.r, c.g, c.b, c.a
                                end,
                                set = function(_, r, g, b, a)
                                    db.headers = db.headers or {}
                                    db.headers.textureColor = { r = r, g = g, b = b, a = a }
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            textureColorShare = {
                                name = "Use Border Color",
                                desc = "Share the header texture color with the tracker frame's border color.",
                                type = "toggle",
                                order = 3,
                                disabled = function()
                                    return (db.headers and db.headers.texture == "none")
                                end,
                                get = function() return db.headers and db.headers.textureColorShare end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.textureColorShare = val
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            sepText = {
                                name = "",
                                type = "header",
                                order = 4,
                            },
                            textColor = {
                                name = "Header Text Color",
                                desc = "Sets the color of the header title text. (Defaults to your Class Color)",
                                type = "color",
                                order = 5,
                                disabled = function()
                                    return db.headers and db.headers.textColorShare
                                end,
                                get = function()
                                    local c = (db.headers and db.headers.textColor) or (ns.GetClassColor and ns.GetClassColor()) or { r = 0.0, g = 0.75, b = 1.0 }
                                    return c.r, c.g, c.b
                                end,
                                set = function(_, r, g, b)
                                    db.headers = db.headers or {}
                                    db.headers.textColor = { r = r, g = g, b = b }
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            resetTextColor = {
                                name = "Reset to Class Color",
                                desc = "Reset the header text color back to your class color default.",
                                type = "execute",
                                order = 5.5,
                                disabled = function()
                                    return (db.headers and db.headers.textColorShare) or (db.headers and db.headers.textColor == nil)
                                end,
                                func = function()
                                    if db.headers then
                                        db.headers.textColor = nil
                                    end
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            textColorShare = {
                                name = "Use Border Color",
                                desc = "Share the header text color with the tracker frame's border color.",
                                type = "toggle",
                                order = 6,
                                get = function() return db.headers and db.headers.textColorShare end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.textColorShare = val
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            sepButtons = {
                                name = "",
                                type = "header",
                                order = 7,
                            },
                            buttonColor = {
                                name = "Header Buttons Color",
                                desc = "Sets the color of all tracker header buttons ([Log], [Zone], [All], [...], [-]). (Defaults to your Class Color)",
                                type = "color",
                                order = 8,
                                disabled = function()
                                    return db.headers and db.headers.buttonColorShare
                                end,
                                get = function()
                                    local c = (db.headers and db.headers.buttonColor) or (ns.GetClassColor and ns.GetClassColor()) or { r = 0.0, g = 0.75, b = 1.0 }
                                    return c.r, c.g, c.b
                                end,
                                set = function(_, r, g, b)
                                    db.headers = db.headers or {}
                                    db.headers.buttonColor = { r = r, g = g, b = b }
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            resetButtonColor = {
                                name = "Reset to Class Color",
                                desc = "Reset the header buttons color back to your class color default.",
                                type = "execute",
                                order = 8.5,
                                disabled = function()
                                    return (db.headers and db.headers.buttonColorShare) or (db.headers and db.headers.buttonColor == nil)
                                end,
                                func = function()
                                    if db.headers then
                                        db.headers.buttonColor = nil
                                    end
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            buttonColorShare = {
                                name = "Use Border Color",
                                desc = "Share the header button colors with the tracker frame's border color.",
                                type = "toggle",
                                order = 9,
                                get = function() return db.headers and db.headers.buttonColorShare end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.buttonColorShare = val
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            sepFormats = {
                                name = "",
                                type = "header",
                                order = 10,
                            },
                            countFormat = {
                                name = "Quest Counter Format",
                                desc = "Format of the quest capacity counter displayed in the header.",
                                type = "select",
                                order = 11,
                                values = {
                                    ["none"] = "None",
                                    ["short"] = "(5/40) - Short",
                                    ["full"] = "(5/40 Quests) - Full",
                                },
                                get = function() return db.headers and db.headers.countFormat or "short" end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.countFormat = val
                                    if ns.StandaloneTracker then ns.StandaloneTracker:UpdateTracker() end
                                end,
                            },
                            collapsedText = {
                                name = "Collapsed Tracker Text",
                                desc = "What text to display on the tracker header when collapsed.",
                                type = "select",
                                order = 12,
                                values = {
                                    ["none"] = "None (Minimal [+])",
                                    ["counter"] = "Counter Only",
                                    ["title"] = "Title & Counter",
                                },
                                get = function() return db.headers and db.headers.collapsedText or "counter" end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.collapsedText = val
                                    if ns.Tracker.isCollapsed then
                                        ns.Tracker:ApplyHeaderSettings()
                                    end
                                end,
                            },
                            sepToggles = {
                                name = "Header Buttons Visibility",
                                type = "header",
                                order = 13,
                            },
                            showQuestLogBtn = {
                                name = "Show Quest Log Button [Log]",
                                desc = "Display the [Log] button on the header to quickly open or close your Quest Log.",
                                type = "toggle",
                                width = "full",
                                order = 14,
                                get = function() return not (db.headers and db.headers.showQuestLogBtn == false) end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.showQuestLogBtn = val
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            showZoneBtn = {
                                name = "Show Zone Filter Button [Zone]",
                                desc = "Display the [Zone] filter toggle button on the header.",
                                type = "toggle",
                                width = "full",
                                order = 15,
                                get = function() return not (db.headers and db.headers.showZoneBtn == false) end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.showZoneBtn = val
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            showAllBtn = {
                                name = "Show All Quests Filter Button [All]",
                                desc = "Display the [All] filter toggle button on the header.",
                                type = "toggle",
                                width = "full",
                                order = 16,
                                get = function() return not (db.headers and db.headers.showAllBtn == false) end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.showAllBtn = val
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            showMenuBtn = {
                                name = "Show Quick Menu Button [...]",
                                desc = "Display the [...] quick options menu button on the header.",
                                type = "toggle",
                                width = "full",
                                order = 17,
                                get = function() return not (db.headers and db.headers.showMenuBtn == false) end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.showMenuBtn = val
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                            showCollapseBtn = {
                                name = "Show Collapse Button [-]",
                                desc = "Display the [-]/[+] button to collapse or expand the tracker.",
                                type = "toggle",
                                width = "full",
                                order = 18,
                                get = function() return not (db.headers and db.headers.showCollapseBtn == false) end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.showCollapseBtn = val
                                    ns.Tracker:ApplyHeaderSettings()
                                end,
                            },
                        },
                    },
                    zoneHeaders = {
                        name = "Zone / Section Headers",
                        type = "group",
                        inline = true,
                        order = 2,
                        args = {
                            showZoneHeaders = {
                                name = "Group Quests by Zone",
                                desc = "Organize quests under collapsible zone headers (e.g. [-] Durotar (3)).",
                                type = "toggle",
                                width = "full",
                                order = 1,
                                get = function() return not (db.headers and db.headers.showZoneHeaders == false) end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.showZoneHeaders = val
                                    ns:FireCallback("QUEST_DATA_CHANGED")
                                end,
                            },
                            showZoneCount = {
                                name = "Show Quest Count in Zone Header",
                                desc = "Display the number of active quests in each zone header (e.g. (3)).",
                                type = "toggle",
                                width = "full",
                                order = 2,
                                disabled = function() return db.headers and db.headers.showZoneHeaders == false end,
                                get = function() return not (db.headers and db.headers.showZoneCount == false) end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.showZoneCount = val
                                    ns:FireCallback("QUEST_DATA_CHANGED")
                                end,
                            },
                            zoneHeaderTexture = {
                                name = "Zone Header Texture",
                                desc = "Select the background texture for zone headers.",
                                type = "select",
                                order = 3,
                                disabled = function() return db.headers and db.headers.showZoneHeaders == false end,
                                values = {
                                    ["none"] = "None",
                                    ["flat"] = "Flat Bar",
                                    ["gradient"] = "Gradient Bar",
                                    ["blizzard"] = "Blizzard Header",
                                },
                                get = function() return db.headers and db.headers.zoneHeaderTexture or "gradient" end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.zoneHeaderTexture = val
                                    ns:FireCallback("QUEST_DATA_CHANGED")
                                end,
                            },
                            zoneHeaderColor = {
                                name = "Zone Header Color",
                                desc = "Sets the color of zone headers.",
                                type = "color",
                                order = 4,
                                disabled = function()
                                    return (db.headers and (db.headers.showZoneHeaders == false or db.headers.zoneHeaderColorShare))
                                end,
                                get = function()
                                    local c = (db.headers and db.headers.zoneHeaderColor) or { r = 1.0, g = 0.82, b = 0.0 }
                                    return c.r, c.g, c.b
                                end,
                                set = function(_, r, g, b)
                                    db.headers = db.headers or {}
                                    db.headers.zoneHeaderColor = { r = r, g = g, b = b, a = 1.0 }
                                    ns:FireCallback("QUEST_DATA_CHANGED")
                                end,
                            },
                            zoneHeaderColorShare = {
                                name = "Use Border Color",
                                desc = "Share the zone header color with the tracker frame's border color.",
                                type = "toggle",
                                order = 5,
                                disabled = function() return db.headers and db.headers.showZoneHeaders == false end,
                                get = function() return db.headers and db.headers.zoneHeaderColorShare end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.zoneHeaderColorShare = val
                                    ns:FireCallback("QUEST_DATA_CHANGED")
                                end,
                            },
                            sepActions = {
                                name = "",
                                type = "header",
                                order = 6,
                            },
                            expandAllZones = {
                                name = "Expand All Zones",
                                desc = "Expand all collapsed zone sections.",
                                type = "execute",
                                order = 7,
                                disabled = function() return db.headers and db.headers.showZoneHeaders == false end,
                                func = function()
                                    db.collapsedZones = {}
                                    ns:FireCallback("QUEST_DATA_CHANGED")
                                end,
                            },
                            collapseAllZones = {
                                name = "Collapse All Zones",
                                desc = "Collapse all zone sections.",
                                type = "execute",
                                order = 8,
                                disabled = function() return db.headers and db.headers.showZoneHeaders == false end,
                                func = function()
                                    if ns.StandaloneTracker and ns.StandaloneTracker.GetTrackedQuests then
                                        db.collapsedZones = db.collapsedZones or {}
                                        local quests = ns.StandaloneTracker:GetTrackedQuests()
                                        for _, q in ipairs(quests) do
                                            local z = q.zone or "Other Quests"
                                            db.collapsedZones[z] = true
                                        end
                                        ns:FireCallback("QUEST_DATA_CHANGED")
                                    end
                                end
                            },
                        },
                    },
                    questHeaders = {
                        name = "Quest Titles & Headers",
                        type = "group",
                        inline = true,
                        order = 3,
                        args = {
                            colorDifficulty = {
                                name = "Color Quest Headers by Difficulty",
                                desc = "Color quest headers and titles according to their difficulty relative to your level (Red, Orange, Yellow, Green, Gray).",
                                type = "toggle",
                                width = "full",
                                order = 1,
                                get = function() return db.fonts and db.fonts.colorDifficulty ~= false end,
                                set = function(_, val)
                                    db.fonts = db.fonts or {}
                                    db.fonts.colorDifficulty = val
                                    ns:FireCallback("QUEST_DATA_CHANGED")
                                end,
                            },
                            showCompleteIcon = {
                                name = "Show Complete Icon (?) on Finished Quests",
                                desc = "Display the Blizzard gold question mark (?) in front of quests that are ready for turn-in.",
                                type = "toggle",
                                width = "full",
                                order = 2,
                                get = function() return not (db.headers and db.headers.showCompleteIcon == false) end,
                                set = function(_, val)
                                    db.headers = db.headers or {}
                                    db.headers.showCompleteIcon = val
                                    ns:FireCallback("QUEST_DATA_CHANGED")
                                end,
                            },
                            showQuestRewards = {
                                name = "Show Quest Rewards in Tooltip",
                                desc = "Show detailed quest rewards (XP, money, choice and guaranteed item rewards with quality links) when hovering over a quest title.",
                                type = "toggle",
                                width = "full",
                                order = 3,
                                get = function() return not (db.tooltips and db.tooltips.showRewards == false) end,
                                set = function(_, val)
                                    db.tooltips = db.tooltips or {}
                                    db.tooltips.showRewards = val
                                end,
                            },
                            showXpPercent = {
                                name = "Show XP % Towards Current Level",
                                desc = "Display what percentage of your current level the quest XP reward grants (e.g. 18.5% of lvl 24). Automatically hidden at maximum level.",
                                type = "toggle",
                                width = "full",
                                order = 3.1,
                                disabled = function() return db.tooltips and db.tooltips.showRewards == false end,
                                get = function() return not (db.tooltips and db.tooltips.showXpPercent == false) end,
                                set = function(_, val)
                                    db.tooltips = db.tooltips or {}
                                    db.tooltips.showXpPercent = val
                                end,
                            },
                            showUsableGear = {
                                name = "Highlight Class-Usable Gear Rewards",
                                desc = "Add a green [Usable] tag to weapons and armor wearable by your class, and dim unusable equipment with a gray [Unusable] tag.",
                                type = "toggle",
                                width = "full",
                                order = 3.2,
                                disabled = function() return db.tooltips and db.tooltips.showRewards == false end,
                                get = function() return not (db.tooltips and db.tooltips.showUsableGear == false) end,
                                set = function(_, val)
                                    db.tooltips = db.tooltips or {}
                                    db.tooltips.showUsableGear = val
                                end,
                            },
                            showBestSell = {
                                name = "Highlight Most Valuable Choice Reward (Best Sell)",
                                desc = "For quests with multiple reward choices (Choose One), highlight the item with the highest vendor resale price with a gold coin icon and price tag.",
                                type = "toggle",
                                width = "full",
                                order = 3.3,
                                disabled = function() return db.tooltips and db.tooltips.showRewards == false end,
                                get = function() return not (db.tooltips and db.tooltips.showBestSell == false) end,
                                set = function(_, val)
                                    db.tooltips = db.tooltips or {}
                                    db.tooltips.showBestSell = val
                                end,
                            },
                            showPartyStatus = {
                                name = "Show Party Members on Quest",
                                desc = "Show which party members are currently on the quest when hovering over a quest in the tracker.",
                                type = "toggle",
                                width = "full",
                                order = 3.4,
                                get = function() return not (db.tooltips and db.tooltips.showPartyStatus == false) end,
                                set = function(_, val)
                                    db.tooltips = db.tooltips or {}
                                    db.tooltips.showPartyStatus = val
                                end,
                            },
                            showMissingParty = {
                                name = "Show Missing Party Members",
                                desc = "Display group members who do not currently have the quest, noting if the quest can be shared with them.",
                                type = "toggle",
                                width = "full",
                                order = 3.5,
                                disabled = function() return db.tooltips and db.tooltips.showPartyStatus == false end,
                                get = function() return not (db.tooltips and db.tooltips.showMissingParty == false) end,
                                set = function(_, val)
                                    db.tooltips = db.tooltips or {}
                                    db.tooltips.showMissingParty = val
                                end,
                            },
                            classColorParty = {
                                name = "Class Color Party Names",
                                desc = "Format party member names in tooltips using their character class colors.",
                                type = "toggle",
                                width = "full",
                                order = 3.6,
                                disabled = function() return db.tooltips and db.tooltips.showPartyStatus == false end,
                                get = function() return not (db.tooltips and db.tooltips.classColorParty == false) end,
                                set = function(_, val)
                                    db.tooltips = db.tooltips or {}
                                    db.tooltips.classColorParty = val
                                end,
                            },
                            showPartyBadge = {
                                name = "Show Party Count Badge on Tracker",
                                desc = "Appends a [P #] group count badge next to quest titles in the tracker when party members share the quest.",
                                type = "toggle",
                                width = "full",
                                order = 3.7,
                                get = function() return db.tooltips and db.tooltips.showPartyBadge == true end,
                                set = function(_, val)
                                    db.tooltips = db.tooltips or {}
                                    db.tooltips.showPartyBadge = val
                                    ns:FireCallback("QUEST_DATA_CHANGED")
                                end,
                            },
                        },
                    },
                },
                        },
                    typography = {
                        name = "Fonts & Typography",
                        type = "group",
                        order = 5,
                        args = {
                            desc = {
                                name = "Customize font family (via SharedMedia), title and objective sizes, outlines, and text shadows.\n",
                                type = "description",
                                order = 0,
                            },
                    headerFont = {
                        name = "Header & Title Font",
                        desc = "Select the font typeface for tracker headers, zone headers, and quest titles (Default: Nata Sans Bold).",
                        type = "select",
                        dialogControl = "LSM30_Font",
                        values = fontList,
                        order = 1,
                        get = function()
                            return db.fonts.headerFont or db.fonts.font or "Nata Sans Bold"
                        end,
                        set = function(_, val)
                            db.fonts.headerFont = val
                            db.fonts.font = val
                            ns.Tracker:UpdateTypography()
                            if ns.FlushDBToGlobals then
                                ns.FlushDBToGlobals()
                            end
                        end,
                    },
                    objectiveFont = {
                        name = "Description & Objective Font",
                        desc = "Select the font typeface for quest objectives, descriptions, and party progress (Default: Nata Sans Regular).",
                        type = "select",
                        width = "full",
                        dialogControl = "LSM30_Font",
                        values = fontList,
                        order = 1.5,
                        get = function()
                            return db.fonts.objectiveFont or "Nata Sans Regular"
                        end,
                        set = function(_, val)
                            db.fonts.objectiveFont = val
                            ns.Tracker:UpdateTypography()
                            if ns.FlushDBToGlobals then
                                ns.FlushDBToGlobals()
                            end
                        end,
                    },
                    headerSize = {
                        name = "Quest Title Size (px)",
                        desc = "Font size in pixels for quest title headers.",
                        type = "range",
                        min = 9,
                        max = 24,
                        step = 1,
                        order = 2,
                        get = function() return db.fonts.headerSize or 13 end,
                        set = function(_, val)
                            db.fonts.headerSize = val
                            ns.Tracker:UpdateTypography()
                        end,
                    },
                    zoneHeaderSize = {
                        name = "Zone Header Size (px)",
                        desc = "Font size in pixels for collapsible zone headers (e.g. Westfall (3)).",
                        type = "range",
                        min = 9,
                        max = 22,
                        step = 1,
                        order = 2.5,
                        get = function() return db.fonts.zoneHeaderSize or 12 end,
                        set = function(_, val)
                            db.fonts.zoneHeaderSize = val
                            ns.Tracker:UpdateTypography()
                        end,
                    },
                    objectiveSize = {
                        name = "Objective Text Size (px)",
                        desc = "Font size in pixels for quest objective lines.",
                        type = "range",
                        min = 8,
                        max = 20,
                        step = 1,
                        order = 3,
                        get = function() return db.fonts.objectiveSize or 11 end,
                        set = function(_, val)
                            db.fonts.objectiveSize = val
                            ns.Tracker:UpdateTypography()
                        end,
                    },
                    headerOutline = {
                        name = "Header & Title Outline",
                        desc = "Select the outline style applied to quest titles, zone headers, and the tracker header.",
                        type = "select",
                        values = fontFlags,
                        order = 4,
                        get = function() return db.fonts.headerOutline or "OUTLINE" end,
                        set = function(_, val)
                            db.fonts.headerOutline = val
                            ns.Tracker:UpdateTypography()
                        end,
                    },
                    objectiveOutline = {
                        name = "Objective Text Outline",
                        desc = "Select the outline style applied to quest objective lines, counts, and descriptions.",
                        type = "select",
                        values = fontFlags,
                        order = 4.5,
                        get = function() return db.fonts.objectiveOutline or "" end,
                        set = function(_, val)
                            db.fonts.objectiveOutline = val
                            ns.Tracker:UpdateTypography()
                        end,
                    },
                    enableTextShadow = {
                        name = "Enable Text Drop Shadow",
                        desc = "Render a soft, subtle drop shadow behind all tracker text for enhanced readability against transparent backdrops.",
                        type = "toggle",
                        order = 4.8,
                        get = function() return db.fonts.enableTextShadow ~= false end,
                        set = function(_, val)
                            db.fonts.enableTextShadow = val
                            ns.Tracker:UpdateTypography()
                        end,
                    },
                    colorDifficulty = {
                        name = "Color Quest Headers by Difficulty",
                        desc = "Color quest headers and titles according to their difficulty relative to your level (Red, Orange, Yellow, Green, Gray).",
                        type = "toggle",
                        width = "full",
                        order = 5,
                        get = function() return db.fonts.colorDifficulty ~= false end,
                        set = function(_, val)
                            db.fonts.colorDifficulty = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    activeQuestIcon = {
                        name = "Active Quest Marker Icon",
                        desc = "Choose the icon displayed next to the active quest in the tracker. Hidden when inline wayfinder navigation arrows are active.",
                        type = "select",
                        width = "full",
                        order = 6,
                        hidden = function()
                            local isWayfinderActive = (not ns.IsModuleEnabled or ns.IsModuleEnabled("wayfinder"))
                            return isWayfinderActive and db.wayfinder and db.wayfinder.enableInlineArrow
                        end,
                        values = {
                            ["star"] = "Gold Star (Blizzard)",
                            ["arrow"] = "Gold Arrow",
                            ["blizz"] = "Blizzard Quest Icon",
                            ["pointer"] = "Cyan Pointer (>)",
                            ["none"] = "None",
                        },
                        get = function() return db.activeQuestIcon or "star" end,
                        set = function(_, val)
                            db.activeQuestIcon = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                },
                        },
                    presets = {
                        name = "Visual Presets",
                        type = "group",
                        order = 6,
                        args = {
                            desc = {
                                name = "Apply one-click visual themes to instantly configure borders, backdrops, typography, and headers.\n",
                                type = "description",
                                order = 0,
                            },
                            glassPreset = {
                                name = "Modern Dark Glass (Default)",
                                desc = "Clean 1px flat border, sleek semi-transparent dark backdrop, modern typography.",
                                type = "execute",
                                order = 1,
                                func = function()
                                    Config:ApplyModernGlassPreset()
                                    ns.Print("Applied Modern Dark Glass preset.")
                                end,
                            },
                            classicPreset = {
                                name = "Classic WoW Plus",
                                desc = "Classic World of Warcraft parchment tooltip border with gold headers and high contrast.",
                                type = "execute",
                                order = 2,
                                func = function()
                                    Config:ApplyClassicPreset()
                                    ns.Print("Applied Classic WoW Plus preset.")
                                end,
                            },
                            minimalPreset = {
                                name = "Ultra Minimalist",
                                desc = "Borderless flat backdrop with compact typography for maximum screen space.",
                                type = "execute",
                                order = 3,
                                func = function()
                                    Config:ApplyMinimalPreset()
                                    ns.Print("Applied Ultra Minimalist preset.")
                                end,
                            },
                        },
                    },
                },
            },
            sorting = {
                name = "Sorting",
                type = "group",
                order = 3,
                args = {
                    desc = {
                        name = "Choose how active quests are ordered inside the tracker.\n",
                        type = "description",
                        order = 0,
                    },
                    mode = {
                        name = "Default Sorting Mode",
                        type = "select",
                        order = 1,
                        values = {
                            ["level"] = "By Quest Level",
                            ["zone"] = "By Zone",
                        },
                        get = function() return db.sorting.mode or "level" end,
                        set = function(_, val)
                            db.sorting.mode = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    activeOnTop = {
                        name = "Pin Active Quest to Top",
                        desc = "Keep the active quest (★) pinned to the very top of the tracker regardless of sort order or level, ensuring it never scrolls off screen.",
                        type = "toggle",
                        width = "full",
                        order = 1.5,
                        get = function() return not (db.sorting and db.sorting.activeOnTop == false) end,
                        set = function(_, val)
                            db.sorting = db.sorting or {}
                            db.sorting.activeOnTop = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    moveCompletedToBottom = {
                        name = "Move Completed Quests to Bottom",
                        desc = "Place quests that are ready for turn-in at the bottom of their zone and tracker so active objectives remain visible at the top.",
                        type = "toggle",
                        width = "full",
                        order = 2,
                        get = function() return db.sorting.moveCompletedToBottom end,
                        set = function(_, val)
                            db.sorting.moveCompletedToBottom = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    showGroupTags = {
                        name = "Show Elite / Group Badges",
                        desc = "Display badges like [11+] for group/elite quests, [20D] for dungeon quests, and [60R] for raid quests.",
                        type = "toggle",
                        width = "full",
                        order = 3,
                        get = function() return db.sorting.showGroupTags ~= false end,
                        set = function(_, val)
                            db.sorting.showGroupTags = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                },
            },
            modules = {
                name = "Modules",
                type = "group",
                order = 4,
                args = {
                    desc = {
                        name = "Enable or disable standalone modules in real time. When a module is turned off, its events, timers, and UI frames are immediately disabled without requiring a /reload.\n",
                        type = "description",
                        order = 0,
                    },
                    enableWayfinder = {
                        name = "Wayfinder Navigation Module",
                        desc = "3D floating HUD waypoint arrow, inline tracker mini arrows, and distance readouts.",
                        type = "toggle",
                        width = "full",
                        order = 1,
                        get = function() return ns.IsModuleEnabled("wayfinder") end,
                        set = function(_, val)
                            ns.SetModuleEnabled("wayfinder", val)
                        end,
                    },
                    enableDataBars = {
                        name = "DataBars Suite Module",
                        desc = "Standalone Experience / Reputation progress bar, Location & precision coordinates header bar, and timed quest bar.",
                        type = "toggle",
                        width = "full",
                        order = 2,
                        get = function() return ns.IsModuleEnabled("databars") end,
                        set = function(_, val)
                            ns.SetModuleEnabled("databars", val)
                        end,
                    },
                    enableQuestAutomation = {
                        name = "Quest Automation Module",
                        desc = "Automated quest accepting, auto-sharing with party members, and smart turn-in completion.",
                        type = "toggle",
                        width = "full",
                        order = 3,
                        get = function() return ns.IsModuleEnabled("questAutomation") end,
                        set = function(_, val)
                            ns.SetModuleEnabled("questAutomation", val)
                        end,
                    },
                    enableQoL = {
                        name = "Quality of Life (QoL) Module",
                        desc = "Instant Fast Auto Loot, automatic grey/junk selling at vendors, and merchant equipment repair.",
                        type = "toggle",
                        width = "full",
                        order = 4,
                        get = function() return ns.IsModuleEnabled("qol") end,
                        set = function(_, val)
                            ns.SetModuleEnabled("qol", val)
                        end,
                    },
                },
            },
            questAutomation = {
                name = "Quest Automation",
                type = "group",
                order = 7,
                hidden = function() return not ns.IsModuleEnabled("questAutomation") end,
                args = {
                    desc = {
                        name = "Configure automated quest interaction options. Holding Shift temporarily pauses automation while interacting with questgivers.\n",
                        type = "description",
                        order = 0,
                    },
                    autoAcceptNPC = {
                        name = "Auto-Accept NPC Quests",
                        desc = "Automatically accept quests offered by friendly NPCs.",
                        type = "toggle",
                        width = "full",
                        order = 1,
                        get = function() return db.questAutomation and db.questAutomation.autoAcceptNPC end,
                        set = function(_, val)
                            db.questAutomation = db.questAutomation or {}
                            db.questAutomation.autoAcceptNPC = val
                            if db.social then db.social.autoAcceptNPC = val end
                        end,
                    },
                    autoAcceptShared = {
                        name = "Auto-Accept Shared Quests",
                        desc = "Automatically accept quests shared by party or raid members.",
                        type = "toggle",
                        width = "full",
                        order = 2,
                        get = function() return db.questAutomation and db.questAutomation.autoAcceptShared end,
                        set = function(_, val)
                            db.questAutomation = db.questAutomation or {}
                            db.questAutomation.autoAcceptShared = val
                            if db.social then db.social.autoAcceptShared = val end
                        end,
                    },
                    autoTurnIn = {
                        name = "Auto Turn-In Quests (1 or Less Choice)",
                        desc = "Automatically complete and turn in ready quests. Only triggers on quests with 1 or 0 reward choices (quests offering multiple choices remain open so you can select your reward upgrade).",
                        type = "toggle",
                        width = "full",
                        order = 3,
                        get = function() return db.questAutomation and db.questAutomation.autoTurnIn end,
                        set = function(_, val)
                            db.questAutomation = db.questAutomation or {}
                            db.questAutomation.autoTurnIn = val
                            if db.social then db.social.autoTurnIn = val end
                        end,
                    },
                    autoShare = {
                        name = "Auto-Share Quests",
                        desc = "Automatically share newly accepted quests with your party when grouped.",
                        type = "toggle",
                        width = "full",
                        order = 4,
                        get = function() return db.questAutomation and db.questAutomation.autoShare end,
                        set = function(_, val)
                            db.questAutomation = db.questAutomation or {}
                            db.questAutomation.autoShare = val
                            if db.social then db.social.autoShare = val end
                        end,
                    },
                    shiftBypass = {
                        name = "Shift-Key Bypass",
                        desc = "Holding Shift temporarily pauses automation while talking to questgivers.",
                        type = "toggle",
                        width = "full",
                        order = 5,
                        get = function() return db.questAutomation and db.questAutomation.shiftBypass ~= false end,
                        set = function(_, val)
                            db.questAutomation = db.questAutomation or {}
                            db.questAutomation.shiftBypass = val
                            if db.social then db.social.shiftBypass = val end
                        end,
                    },
                },
            },
            qol = {
                name = "Quality of Life",
                type = "group",
                order = 8,
                hidden = function() return not ns.IsModuleEnabled("qol") end,
                args = {
                    desc = {
                        name = "Streamline everyday gameplay with fast looting, automated vendor sales, and merchant equipment repairs.\n",
                        type = "description",
                        order = 0,
                    },
                    fastAutoLoot = {
                        name = "Fast Auto Loot",
                        desc = "Instantly and automatically loot all items from corpses and containers without delay.",
                        type = "toggle",
                        width = "full",
                        order = 1,
                        get = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            return curDB and curDB.qol and curDB.qol.fastAutoLoot ~= false
                        end,
                        set = function(_, val)
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            if curDB then
                                curDB.qol = curDB.qol or {}
                                curDB.qol.fastAutoLoot = val
                                if curDB.social then curDB.social.fastAutoLoot = val end
                            end
                            if ns.QoLModule and ns.QoLModule.UpdateLootEvents then
                                ns.QoLModule:UpdateLootEvents()
                            end
                        end,
                    },
                    autoVendorGreys = {
                        name = "Auto-Vendor Grey / Junk Items",
                        desc = "Automatically sell all poor-quality (grey) junk items upon opening a merchant window.",
                        type = "toggle",
                        width = "full",
                        order = 2,
                        get = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            return curDB and curDB.qol and (curDB.qol.autoVendorGreys == true or curDB.qol.autoSellJunk == true)
                        end,
                        set = function(_, val)
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            if curDB then
                                curDB.qol = curDB.qol or {}
                                curDB.qol.autoVendorGreys = val
                                curDB.qol.autoSellJunk = val
                                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            end
                        end,
                    },
                    autoRepair = {
                        name = "Auto-Repair Equipment",
                        desc = "Automatically repair all damaged gear when visiting a repair merchant.",
                        type = "toggle",
                        width = "full",
                        order = 3,
                        get = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            return curDB and curDB.qol and curDB.qol.autoRepair == true
                        end,
                        set = function(_, val)
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            if curDB then
                                curDB.qol = curDB.qol or {}
                                curDB.qol.autoRepair = val
                            end
                        end,
                    },
                    useGuildRepair = {
                        name = "Use Guild Bank for Repairs",
                        desc = "Attempt to use Guild Bank repair allowances if available, falling back to personal funds if unavailable.",
                        type = "toggle",
                        width = "full",
                        order = 4,
                        disabled = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            return not (curDB and curDB.qol and curDB.qol.autoRepair)
                        end,
                        get = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            return curDB and curDB.qol and curDB.qol.useGuildRepair == true
                        end,
                        set = function(_, val)
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            if curDB then
                                curDB.qol = curDB.qol or {}
                                curDB.qol.useGuildRepair = val
                            end
                        end,
                    },
                    shiftBypass = {
                        name = "Shift-Key Bypass",
                        desc = "Hold Shift while opening a merchant window to temporarily pause auto-selling and auto-repairing.",
                        type = "toggle",
                        width = "full",
                        order = 5,
                        get = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            return curDB and curDB.qol and curDB.qol.shiftBypass ~= false
                        end,
                        set = function(_, val)
                            local curDB = (ns.dbObject and ns.dbObject.profile) or ns.db
                            if curDB then
                                curDB.qol = curDB.qol or {}
                                curDB.qol.shiftBypass = val
                            end
                        end,
                    },
                },
            },
            social = {
                name = "Social & Audio",
                type = "group",
                order = 9,
                args = {
                    desc = {
                        name = "Configure party chat quest announcements and audible alerts.\n",
                        type = "description",
                        order = 0,
                    },
                    announceToParty = {
                        name = "Announce to Party Chat",
                        desc = "Master toggle to send quest milestone messages to party chat when grouped.",
                        type = "toggle",
                        width = "full",
                        order = 8,
                        get = function() return db.social and db.social.announceToParty end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.announceToParty = val
                        end,
                    },
                    announceQuestComplete = {
                        name = "Announce Quest Complete",
                        desc = "Send a message to party chat when a quest is fully finished and ready for turn-in (e.g. [BFQ] The People's Militia (Complete)).",
                        type = "toggle",
                        width = "full",
                        order = 8.1,
                        disabled = function() return not (db.social and db.social.announceToParty) end,
                        get = function() return not (db.social and db.social.announceQuestComplete == false) end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.announceQuestComplete = val
                        end,
                    },
                    announceObjectiveComplete = {
                        name = "Announce Objective Complete",
                        desc = "Send a message to party chat when an individual objective completes (e.g. [BFQ] The People's Militia: 15 Defias Traitors slain (Complete)).",
                        type = "toggle",
                        width = "full",
                        order = 8.2,
                        disabled = function() return not (db.social and db.social.announceToParty) end,
                        get = function() return not (db.social and db.social.announceObjectiveComplete == false) end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.announceObjectiveComplete = val
                        end,
                    },
                    announceObjectiveProgress = {
                        name = "Announce Objective Progress (N/X)",
                        desc = "Send incremental objective progress updates to party chat (e.g. [BFQ] The People's Militia: Defias Traitors 5/15).",
                        type = "toggle",
                        width = "full",
                        order = 8.3,
                        disabled = function() return not (db.social and db.social.announceToParty) end,
                        get = function() return db.social and db.social.announceObjectiveProgress == true end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.announceObjectiveProgress = val
                        end,
                    },
                    headerSound = {
                        name = "Audio Alerts",
                        type = "header",
                        order = 10,
                    },
                    enableCompleteSound = {
                        name = "Enable Quest Completion Sound",
                        desc = "Play a sound effect whenever a quest is completed and ready for turn-in.",
                        type = "toggle",
                        width = "full",
                        order = 11,
                        get = function() return not db.sound or db.sound.enableCompleteSound ~= false end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.enableCompleteSound = val
                        end,
                    },
                    soundChoice = {
                        name = "Quest Complete Sound",
                        desc = "Select which sound effect to play when a quest is ready for turn-in.",
                        type = "select",
                        order = 12,
                        values = {
                            peon = "Peon: \"Work complete!\"",
                            quest_complete = "Classic Quest Complete",
                            whisper_ping = "Whisper Ping (TellMessage)",
                            coins = "Gold Coin Ding",
                            loot_clink = "Loot Coin Clink",
                            level_up = "Level Up Fanfare",
                            raid_warning = "Raid Warning Chime",
                            ready_check = "Ready Check Chime",
                            pvp_horn = "PvP Queue Horn",
                            custom = "Custom Sound File / Slot",
                        },
                        get = function() return (db.sound and db.sound.soundChoice) or "peon" end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.soundChoice = val
                            if val == "custom" then
                                db.sound.useCustomCompleteSound = true
                            else
                                db.sound.useCustomCompleteSound = false
                            end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            if ns.SocialModule and ns.SocialModule.PlayPreviewSound then
                                ns.SocialModule:PlayPreviewSound(val)
                            end
                        end,
                    },
                    completeSoundVolume = {
                        name = "Complete Sound Volume",
                        desc = "Adjust playback volume for quest completion audio alerts (5% to 100%).",
                        type = "range",
                        min = 5,
                        max = 100,
                        step = 5,
                        order = 13,
                        get = function() return (db.sound and db.sound.completeSoundVolume) or 100 end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.completeSoundVolume = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            if ns.SocialModule and ns.SocialModule.PlayPreviewSound then
                                ns.SocialModule:PlayPreviewSound(nil, nil, val)
                            end
                        end,
                    },
                    completeSoundChannel = {
                        name = "Complete Sound Channel",
                        desc = "Select audio channel for completion sound playback.",
                        type = "select",
                        order = 14,
                        values = {
                            Master = "Master Channel",
                            SFX = "Sound Effects (SFX)",
                            Ambience = "Ambience Channel",
                        },
                        get = function() return (db.sound and db.sound.completeSoundChannel) or "Master" end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.completeSoundChannel = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    useCustomCompleteSound = {
                        name = "Use Custom Complete Sound",
                        desc = "Select a custom sound slot or custom audio file instead of the built-in preset.",
                        type = "toggle",
                        order = 15,
                        get = function()
                            return (db.sound and db.sound.useCustomCompleteSound) or (db.sound and db.sound.soundChoice == "custom")
                        end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.useCustomCompleteSound = val
                            if val then
                                db.sound.soundChoice = "custom"
                            elseif db.sound.soundChoice == "custom" then
                                db.sound.soundChoice = "peon"
                            end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    customCompleteSoundChoice = {
                        name = "Custom Complete Sound Slot",
                        desc = "Select a bundled sound slot (beep.wav, click.wav, custom1..custom5) or choose manual file path.",
                        type = "select",
                        order = 15.5,
                        hidden = function()
                            return not (db.sound and (db.sound.useCustomCompleteSound or db.sound.soundChoice == "custom"))
                        end,
                        values = GetCustomSoundList,
                        get = function()
                            return (db.sound and db.sound.customCompleteSoundChoice) or "beep"
                        end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.customCompleteSoundChoice = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            if ns.SocialModule and ns.SocialModule.PlayPreviewSound then
                                ns.SocialModule:PlayPreviewSound("custom")
                            end
                        end,
                    },
                    customCompleteSoundPath = {
                        name = "Custom Complete Sound Path (Manual)",
                        desc = "File path or LibSharedMedia sound name (e.g. Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Sounds\\beep.wav).",
                        type = "input",
                        width = "double",
                        order = 16,
                        hidden = function()
                            return not (db.sound and (db.sound.useCustomCompleteSound or db.sound.soundChoice == "custom") and db.sound.customCompleteSoundChoice == "manual")
                        end,
                        get = function()
                            return (db.sound and db.sound.customCompleteSoundPath) or "Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Sounds\\beep.wav"
                        end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.customCompleteSoundPath = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    previewBtn = {
                        name = "Preview Complete Sound",
                        desc = "Play the currently selected quest completion sound effect at the configured volume.",
                        type = "execute",
                        order = 17,
                        func = function()
                            if ns.SocialModule and ns.SocialModule.PlayPreviewSound then
                                local c = (db.sound and db.sound.soundChoice) or "peon"
                                local ch = (db.sound and db.sound.completeSoundChannel) or "Master"
                                local vol = (db.sound and db.sound.completeSoundVolume) or 100
                                ns.SocialModule:PlayPreviewSound(c, ch, vol)
                            end
                        end,
                    },
                    enableObjectiveSound = {
                        name = "Enable Objective Progress Sound",
                        desc = "Play a subtle sound effect when an objective makes progress or an objective requirement is met (e.g. looting 3/4 Raptor Horns).",
                        type = "toggle",
                        width = "full",
                        order = 20,
                        get = function() return not db.sound or db.sound.enableObjectiveSound ~= false end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.enableObjectiveSound = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    objectiveSoundChoice = {
                        name = "Objective Progress Sound (Subtle)",
                        desc = "Select which subtle sound effect to play when an objective progresses (Max 5 classic choices, or choose Custom Slot).",
                        type = "select",
                        width = "full",
                        order = 21,
                        values = {
                            whisper_ping = "Whisper Ping (TellMessage)",
                            coins = "Gold Coin Ding",
                            loot_clink = "Loot Coin Clink",
                            map_ping = "Mini-Map Ping",
                            item_click = "Subtle Click",
                            custom = "Custom Sound File / Slot",
                        },
                        get = function() return (db.sound and db.sound.objectiveSoundChoice) or "whisper_ping" end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.objectiveSoundChoice = val
                            if val == "custom" then
                                db.sound.useCustomObjectiveSound = true
                            else
                                db.sound.useCustomObjectiveSound = false
                            end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            if ns.SocialModule and ns.SocialModule.PlayPreviewObjectiveSound then
                                ns.SocialModule:PlayPreviewObjectiveSound(val)
                            end
                        end,
                    },
                    objectiveSoundVolume = {
                        name = "Objective Sound Volume",
                        desc = "Adjust playback volume for objective progress audio alerts (5% to 100%).",
                        type = "range",
                        min = 5,
                        max = 100,
                        step = 5,
                        order = 22,
                        get = function() return (db.sound and db.sound.objectiveSoundVolume) or 100 end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.objectiveSoundVolume = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            if ns.SocialModule and ns.SocialModule.PlayPreviewObjectiveSound then
                                ns.SocialModule:PlayPreviewObjectiveSound(nil, nil, val)
                            end
                        end,
                    },
                    objectiveSoundChannel = {
                        name = "Objective Sound Channel",
                        desc = "Select audio channel for objective progress sound playback.",
                        type = "select",
                        order = 23,
                        values = {
                            Master = "Master Channel",
                            SFX = "Sound Effects (SFX)",
                            Ambience = "Ambience Channel",
                        },
                        get = function() return (db.sound and db.sound.objectiveSoundChannel) or "Master" end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.objectiveSoundChannel = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    useCustomObjectiveSound = {
                        name = "Use Custom Objective Sound",
                        desc = "Select a custom sound slot or custom audio file instead of the subtle presets above.",
                        type = "toggle",
                        order = 24,
                        get = function()
                            return (db.sound and db.sound.useCustomObjectiveSound) or (db.sound and db.sound.objectiveSoundChoice == "custom")
                        end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.useCustomObjectiveSound = val
                            if val then
                                db.sound.objectiveSoundChoice = "custom"
                            elseif db.sound.objectiveSoundChoice == "custom" then
                                db.sound.objectiveSoundChoice = "whisper_ping"
                            end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    customObjectiveSoundChoice = {
                        name = "Custom Objective Sound Slot",
                        desc = "Select a bundled sound slot (beep.wav, click.wav, custom1..custom5) or choose manual file path.",
                        type = "select",
                        width = "full",
                        order = 24.5,
                        hidden = function()
                            return not (db.sound and (db.sound.useCustomObjectiveSound or db.sound.objectiveSoundChoice == "custom"))
                        end,
                        values = GetCustomSoundList,
                        get = function()
                            return (db.sound and db.sound.customObjectiveSoundChoice) or "beep"
                        end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.customObjectiveSoundChoice = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            if ns.SocialModule and ns.SocialModule.PlayPreviewObjectiveSound then
                                ns.SocialModule:PlayPreviewObjectiveSound("custom")
                            end
                        end,
                    },
                    customObjectiveSoundPath = {
                        name = "Custom Objective Sound Path (Manual)",
                        desc = "File path or LibSharedMedia sound name (e.g. Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Sounds\\beep.wav).",
                        type = "input",
                        width = "double",
                        order = 25,
                        hidden = function()
                            return not (db.sound and (db.sound.useCustomObjectiveSound or db.sound.objectiveSoundChoice == "custom") and db.sound.customObjectiveSoundChoice == "manual")
                        end,
                        get = function()
                            return (db.sound and db.sound.customObjectiveSoundPath) or "Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Sounds\\beep.wav"
                        end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.customObjectiveSoundPath = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    previewObjectiveBtn = {
                        name = "Preview Objective Sound",
                        desc = "Play the currently selected objective progress sound effect at the configured volume.",
                        type = "execute",
                        order = 26,
                        func = function()
                            if ns.SocialModule and ns.SocialModule.PlayPreviewObjectiveSound then
                                local c = (db.sound and db.sound.objectiveSoundChoice) or "whisper_ping"
                                local ch = (db.sound and db.sound.objectiveSoundChannel) or "Master"
                                local vol = (db.sound and db.sound.objectiveSoundVolume) or 100
                                ns.SocialModule:PlayPreviewObjectiveSound(c, ch, vol)
                            end
                        end,
                    },
                    customSoundNotes = {
                        name = "\n|cff00c0ffCustom Audio Notes & Slots:|r\n• To use your own sounds without typing paths, drop audio files into:\n  |cffffd100Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Sounds\\|r\n  named |cffffffffcustom1.wav|r, |cffffffffcustom2.wav|r, etc. (up to 5 slots).\n• Bundled ready-to-use sounds: |cffffffffbeep.wav|r (clean subtle tone) and |cffffffffclick.wav|r (soft tick).\n• Any sound registered through LibSharedMedia also automatically appears in the dropdown.\n• 16-bit 44.1kHz PCM .wav files are recommended for universal WoW compatibility.",
                        type = "description",
                        order = 30,
                    },
                },
            },
            wayfinder = {
                name = "Wayfinder",
                type = "group",
                order = 7,
                hidden = function() return not ns.IsModuleEnabled("wayfinder") end,
                args = {
                    desc = {
                        name = "Configure Wayfinder waypoint navigation, floating HUD arrow, and tracker inline directional mini-arrows.\n",
                        type = "description",
                        order = 0,
                    },
                    hudHeader = {
                        name = "Floating HUD Waypoint Arrow",
                        type = "header",
                        order = 1,
                    },
                    enableHUDArrow = {
                        name = "Enable Floating HUD Arrow",
                        desc = "Show a standalone 360° rotating navigation waypoint arrow that points directly to your destination.",
                        type = "toggle",
                        order = 2,
                        width = "double",
                        get = function() return db.wayfinder and db.wayfinder.enableHUDArrow end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.enableHUDArrow = val
                            if ns.WayfinderModule then ns.WayfinderModule:RefreshState() end
                        end,
                    },
                    locked = {
                        name = "Lock Arrow Position",
                        desc = "Prevent dragging and moving the floating HUD arrow.",
                        type = "toggle",
                        order = 3,
                        get = function() return db.wayfinder and db.wayfinder.locked end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.locked = val
                        end,
                    },
                    hideInCombat = {
                        name = "Hide Arrow in Combat",
                        desc = "Automatically hide the floating navigation arrow while in combat to prevent screen distraction (default: On).",
                        type = "toggle",
                        order = 3.5,
                        get = function() return not (db.wayfinder and db.wayfinder.hideInCombat == false) end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.hideInCombat = val
                            if ns.WayfinderModule then ns.WayfinderModule:UpdateFrameVisibility() end
                        end,
                    },
                    arrowScale = {
                        name = "Arrow Scale",
                        desc = "Set the display scale of the floating HUD arrow.",
                        type = "range",
                        order = 4,
                        min = 0.5,
                        max = 1.8,
                        step = 0.05,
                        isPercent = true,
                        get = function() return (db.wayfinder and db.wayfinder.arrowScale) or 1.0 end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.arrowScale = val
                            if ns.WayfinderModule then ns.WayfinderModule:ApplyHUDSettings() end
                        end,
                    },
                    showBackdrop = {
                        name = "Show Backdrop Circle",
                        desc = "Display a semi-transparent circular backdrop behind the floating HUD navigation arrow (default: Off).",
                        type = "toggle",
                        order = 5,
                        get = function() return db.wayfinder and db.wayfinder.showBackdrop == true end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.showBackdrop = val
                            if ns.WayfinderModule then ns.WayfinderModule:ApplyHUDSettings() end
                        end,
                    },
                    arrowStyle = {
                        name = "Arrow Style",
                        desc = "Choose the visual design of the Wayfinder navigation arrow.",
                        type = "select",
                        order = 6,
                        values = {
                            ["auto"] = "Auto (Modern Minimalist)",
                            ["minimal"] = "Modern Minimalist Wedge",
                            ["classic"] = "Classic Minimap Chevron",
                        },
                        get = function() return (db.wayfinder and db.wayfinder.arrowStyle) or "auto" end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.arrowStyle = val
                            if ns.WayfinderModule then ns.WayfinderModule:ApplyHUDSettings() end
                            if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                                ns.StandaloneTracker:UpdateTracker()
                            end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    showDestination = {
                        name = "Show Destination Name",
                        desc = "Display the destination quest, custom waypoint, or flight destination name above the distance readout.",
                        type = "toggle",
                        order = 6.1,
                        get = function() return not (db.wayfinder and db.wayfinder.showDestination == false) end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.showDestination = val
                            if ns.WayfinderModule then
                                ns.WayfinderModule:ApplyHUDSettings()
                                if ns.WayfinderModule.ForceImmediateUpdate then
                                    ns.WayfinderModule:ForceImmediateUpdate()
                                end
                            end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    hudTitleFormat = {
                        name = "Destination Name Format",
                        desc = "Choose what information is displayed above the distance readout on the floating navigation arrow.",
                        type = "select",
                        order = 6.15,
                        values = {
                            ["zone"] = "Zone Location (e.g. Westfall)",
                            ["quest"] = "Quest Title (e.g. The People's Militia)",
                            ["both"] = "Zone & Quest Title (e.g. Westfall - The People's Militia)",
                        },
                        get = function() return (db.wayfinder and db.wayfinder.hudTitleFormat) or "zone" end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.hudTitleFormat = val
                            if ns.WayfinderModule then
                                ns.WayfinderModule:ApplyHUDSettings()
                                if ns.WayfinderModule.ForceImmediateUpdate then
                                    ns.WayfinderModule:ForceImmediateUpdate()
                                end
                            end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    hudTitleFontSize = {
                        name = "Destination Text Size (px)",
                        desc = "Font size in pixels for the destination name displayed above the distance readout.",
                        type = "range",
                        min = 8,
                        max = 18,
                        step = 1,
                        order = 6.2,
                        get = function() return (db.wayfinder and db.wayfinder.hudTitleFontSize) or 11 end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.hudTitleFontSize = val
                            if ns.WayfinderModule then ns.WayfinderModule:ApplyHUDSettings() end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    hudTitleFontOutline = {
                        name = "Destination Text Outline",
                        desc = "Outline style applied to the destination name above the distance readout.",
                        type = "select",
                        values = fontFlags,
                        order = 6.3,
                        get = function() return (db.wayfinder and db.wayfinder.hudTitleFontOutline) or "OUTLINE" end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.hudTitleFontOutline = val
                            if ns.WayfinderModule then ns.WayfinderModule:ApplyHUDSettings() end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    hudFontSize = {
                        name = "Distance Text Size (px)",
                        desc = "Font size in pixels for the floating HUD arrow distance readout.",
                        type = "range",
                        min = 8,
                        max = 18,
                        step = 1,
                        order = 6.4,
                        get = function() return (db.wayfinder and db.wayfinder.hudFontSize) or 11 end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.hudFontSize = val
                            if ns.WayfinderModule then ns.WayfinderModule:ApplyHUDSettings() end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    hudFontOutline = {
                        name = "Distance Text Outline",
                        desc = "Outline style applied to the floating HUD arrow distance readout.",
                        type = "select",
                        values = fontFlags,
                        order = 6.5,
                        get = function() return (db.wayfinder and db.wayfinder.hudFontOutline) or "OUTLINE" end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.hudFontOutline = val
                            if ns.WayfinderModule then ns.WayfinderModule:ApplyHUDSettings() end
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                        end,
                    },
                    resetHUDPos = {
                        name = "Reset Arrow Position",
                        desc = "Reset the floating HUD arrow back to its default position above center screen.",
                        type = "execute",
                        order = 7,
                        func = function()
                            if ns.WayfinderModule and ns.WayfinderModule.hudFrame then
                                ns.WayfinderModule.hudFrame:ClearAllPoints()
                                ns.WayfinderModule.hudFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
                                if db.wayfinder then
                                    db.wayfinder.hudPosition = { point = "CENTER", x = 0, y = 160 }
                                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                                end
                            end
                        end,
                    },
                    previewArrow = {
                        name = "Preview / Move Arrow",
                        desc = "Temporarily toggle the navigation arrow on screen so you can test size, appearance, and drag it to a new location even when no waypoint is active.",
                        type = "execute",
                        order = 7.5,
                        func = function()
                            if ns.WayfinderModule then
                                ns.WayfinderModule:TogglePreviewMode()
                            end
                        end,
                    },
                    trackerHeader = {
                        name = "Tracker Inline Mini-Arrow",
                        type = "header",
                        order = 10,
                    },
                    enableInlineArrow = {
                        name = "Enable Inline Tracker Mini-Arrow",
                        desc = "Show a compact rotating directional arrow directly inside the quest tracker next to the Active Quest (★) title.",
                        type = "toggle",
                        order = 11,
                        width = "double",
                        get = function() return db.wayfinder and db.wayfinder.enableInlineArrow end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.enableInlineArrow = val
                            if ns.WayfinderModule then ns.WayfinderModule:RefreshState() end
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    inlineArrowSize = {
                        name = "Inline Arrow Size",
                        desc = "Adjust the size (in pixels) of the rotating arrow embedded inside the quest tracker header (default: 22px).",
                        type = "range",
                        order = 12,
                        min = 14,
                        max = 32,
                        step = 1,
                        get = function() return (db.wayfinder and db.wayfinder.inlineArrowSize) or 22 end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.inlineArrowSize = val
                            if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                                ns.StandaloneTracker:UpdateTracker()
                            end
                        end,
                    },
                    inlineArrowPosition = {
                        name = "Inline Arrow Position",
                        desc = "Choose where the rotating mini-arrow appears relative to the active quest title.",
                        type = "select",
                        order = 13,
                        values = {
                            ["left"] = "Left (In Front of Title)",
                            ["right"] = "Right (Tracker Margin)",
                        },
                        get = function() return (db.wayfinder and db.wayfinder.inlineArrowPosition) or "left" end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.inlineArrowPosition = val
                            if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
                                ns.StandaloneTracker:UpdateTracker()
                            end
                        end,
                    },
                    behaviorHeader = {
                        name = "Navigation & Arrival Settings",
                        type = "header",
                        order = 20,
                    },
                    autoTrackActiveQuest = {
                        name = "Auto-Track Active Quest",
                        desc = "Automatically point the Wayfinder arrow toward whichever quest is selected as the Active Quest (★) or SuperTracked.",
                        type = "toggle",
                        order = 21,
                        width = "double",
                        get = function() return not (db.wayfinder and db.wayfinder.autoTrackActiveQuest == false) end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.autoTrackActiveQuest = val
                            if ns.WayfinderModule then ns.WayfinderModule:RefreshState() end
                        end,
                    },
                    showDistance = {
                        name = "Show Distance Readout",
                        desc = "Display exact distance (e.g. 142 yd or 130 m) below the floating navigation arrow.",
                        type = "toggle",
                        order = 22,
                        get = function() return not (db.wayfinder and db.wayfinder.showDistance == false) end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.showDistance = val
                            if ns.WayfinderModule then
                                ns.WayfinderModule:ApplyHUDSettings()
                                if ns.WayfinderModule.ForceImmediateUpdate then
                                    ns.WayfinderModule:ForceImmediateUpdate()
                                end
                            end
                        end,
                    },
                    distanceUnit = {
                        name = "Distance Unit System",
                        desc = "Choose between Imperial (Yards & Miles) or Metric (Meters & Kilometers) for all Wayfinder navigation readouts.",
                        type = "select",
                        order = 22.3,
                        values = {
                            ["imperial"] = "Imperial (Yards / Miles)",
                            ["metric"] = "Metric (Meters / Kilometers)",
                        },
                        get = function() return (db.wayfinder and db.wayfinder.distanceUnit) or "imperial" end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.distanceUnit = val
                            if ns.WayfinderModule then
                                ns.WayfinderModule:ApplyHUDSettings()
                                if ns.WayfinderModule.ForceImmediateUpdate then
                                    ns.WayfinderModule:ForceImmediateUpdate()
                                end
                            end
                        end,
                    },
                    showETA = {
                        name = "Show Estimated Time of Arrival (ETA)",
                        desc = "Display a dynamic ETA countdown timer (e.g. 1m 24s) below the navigation arrow based on your current movement velocity.",
                        type = "toggle",
                        width = "full",
                        order = 22.5,
                        get = function() return db.wayfinder and db.wayfinder.showETA == true end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.showETA = val
                        end,
                    },
                    showMapPins = {
                        name = "Show World Map Waypoint Pins",
                        desc = "Display visual pin markers on your World Map for custom waypoints.",
                        type = "toggle",
                        width = "full",
                        order = 22.6,
                        get = function() return not (db.wayfinder and db.wayfinder.showMapPins == false) end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.showMapPins = val
                            if ns.WayfinderModule and ns.WayfinderModule.RefreshMapPins then
                                ns.WayfinderModule:RefreshMapPins()
                            end
                        end,
                    },
                    showCoordinates = {
                        name = "Show Player & Cursor Coordinates",
                        desc = "Display live player and cursor map coordinates on the World Map footer.",
                        type = "toggle",
                        width = "full",
                        order = 22.7,
                        get = function() return db.wayfinder and db.wayfinder.showCoordinates == true end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.showCoordinates = val
                            if ns.WayfinderModule and ns.WayfinderModule.UpdateCoordinatesDisplay then
                                ns.WayfinderModule:UpdateCoordinatesDisplay()
                            end
                        end,
                    },
                    playArrivalSound = {
                        name = "Play Arrival Sound",
                        desc = "Play a subtle audio chime when you arrive within the arrival threshold.",
                        type = "toggle",
                        order = 23,
                        get = function() return not (db.wayfinder and db.wayfinder.playArrivalSound == false) end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.playArrivalSound = val
                        end,
                    },
                    arrivalThreshold = {
                        name = "Arrival Distance (Yards)",
                        desc = "How close you must be to the objective before the arrow triggers 'Arrived!'.",
                        type = "range",
                        order = 24,
                        min = 5,
                        max = 50,
                        step = 1,
                        get = function() return (db.wayfinder and db.wayfinder.arrivalThreshold) or 15 end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.arrivalThreshold = val
                        end,
                    },
                    arrivalClearDelay = {
                        name = "Arrival Auto-Clear Delay (Seconds)",
                        desc = "How many seconds the arrow will display 'Arrived!' before automatically clearing the reached waypoint or turn-in destination (default: 5 seconds). Set to 0 to disable auto-clearing and keep the reached waypoint on screen.",
                        type = "range",
                        width = "full",
                        order = 25,
                        min = 0,
                        max = 30,
                        step = 1,
                        get = function()
                            local val = db.wayfinder and db.wayfinder.arrivalClearDelay
                            return (val ~= nil) and val or 5
                        end,
                        set = function(_, val)
                            db.wayfinder = db.wayfinder or {}
                            db.wayfinder.arrivalClearDelay = val
                        end,
                    },
                    commandsHeader = {
                        name = "Custom Waypoint Commands",
                        type = "header",
                        order = 30,
                    },
                    cmdDesc = {
                        name = "You can manually create waypoints anytime using standard slash commands:\n" ..
                                "• |cffffd100/way <x> <y>|r - Place a waypoint at coordinates (e.g. |cffffffff/way 45.2 60.1|r)\n" ..
                                "• |cffffd100/way <x> <y> <label>|r - Place a labeled waypoint (e.g. |cffffffff/way 45.2 60.1 Rare Chest|r)\n" ..
                                "• |cffffd100/way <zone> <x> <y>|r - Place a waypoint in another zone (e.g. |cffffffff/way Elwynn Forest 42.5 61.8|r)\n" ..
                                "• |cffffd100/cway|r - Point the arrow to the closest active waypoint\n" ..
                                "• |cffffd100/way list|r - List all active custom waypoints in chat\n" ..
                                "• |cffffd100/way reset|r - Clear all custom waypoints\n",
                        type = "description",
                        order = 31,
                    },
                    pointClosestBtn = {
                        name = "Point to Closest Waypoint (/cway)",
                        desc = "Direct the arrow to the closest active custom waypoint.",
                        type = "execute",
                        width = "full",
                        order = 32,
                        func = function()
                            if ns.WayfinderModule then
                                ns.WayfinderModule:SetClosestWaypoint()
                            end
                        end,
                    },
                    clearAllWaypointsBtn = {
                        name = "Clear All Custom Waypoints",
                        desc = "Remove all manually created custom waypoints.",
                        type = "execute",
                        width = "full",
                        order = 33,
                        func = function()
                            if ns.WayfinderModule then
                                ns.WayfinderModule:ClearAllCustomWaypoints()
                            end
                        end,
                    },
                },
            },
            databars = {
                name = "DataBars",
                type = "group",
                order = 8,
                hidden = function() return not ns.IsModuleEnabled("databars") end,
                args = {
                    desc = {
                        name = "Configure the Experience & Completed Quest Log Progress Bar and the Location & Precision Coordinates Header Bar.\n",
                        type = "description",
                        order = 0,
                    },
                    hideInCombat = {
                        name = "Hide DataBars in Combat",
                        desc = "Automatically hide the Experience Bar and Location Bar while engaged in combat, and restore them when combat ends (disabled by default).",
                        type = "toggle",
                        width = "full",
                        order = 0.5,
                        get = function() return db.databars and db.databars.hideInCombat end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.hideInCombat = val
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    useTrackerAppearance = {
                        name = "Inherit Tracker Frame Appearance",
                        desc = "When enabled, DataBars automatically share the tracker frame's background surface texture, background color & opacity, border style, corner sizing, border color, and class coloring. Turn off to configure bar appearance independently.",
                        type = "toggle",
                        width = "full",
                        order = 0.6,
                        get = function() return not (db.databars and db.databars.useTrackerAppearance == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.useTrackerAppearance = val
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    dockSpacing = {
                        name = "Docked Module Spacing",
                        desc = "Adjust the spacing (in pixels) between the quest tracker frame and docked DataBars (XP bar, Location bar, Quest Timer bar), as well as between stacked bars. Range: 0 (seamless edge-to-edge docking) to 5px.",
                        type = "range",
                        min = 0,
                        max = 5,
                        step = 1,
                        bigStep = 1,
                        order = 0.7,
                        get = function() return (db.databars and db.databars.dockSpacing) or 0 end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.dockSpacing = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateAllDocking() end
                        end,
                    },

                    -- XP Bar Section
                    xpHeader = {
                        name = "Experience & Quest Log Progress Bar",
                        type = "header",
                        order = 1,
                    },
                    enableXPBar = {
                        name = "Enable XP & Quest Log Progress Bar",
                        desc = "Show a lightweight, modular XP progress bar that visualizes player XP, rested bonus, and completed quest turn-in XP.",
                        type = "toggle",
                        width = "full",
                        order = 2,
                        get = function() return db.databars and db.databars.enableXPBar end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.enableXPBar = val
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    xpDockMode = {
                        name = "XP Bar Docking Position",
                        desc = "Choose where to dock the XP Progress Bar:\n• Re-skin Default Bar: Replaces Blizzard's XP bar at the bottom center of your screen.\n• Dock to Tracker Bottom: Dynamically size-snaps to the bottom of the quest tracker container.\n• Free Floating: Movable anywhere on screen.",
                        type = "select",
                        order = 3,
                        values = {
                            ["default_bar"] = "Re-skin Default Bar (Screen Bottom)",
                            ["tracker_bottom"] = "Dock to Tracker Bottom (Auto-Snap)",
                            ["free"] = "Free Floating (Movable)",
                        },
                        get = function() return (db.databars and db.databars.xpDockMode) or "default_bar" end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.xpDockMode = val
                            if ns.DataBarsModule then
                                ns.DataBarsModule:UpdateXPDocking()
                                ns.DataBarsModule:UpdateXPBar()
                            end
                        end,
                    },
                    hideBlizzardXPBar = {
                        name = "Hide Blizzard Default XP Bar",
                        desc = "Automatically hide Blizzard's default status tracking bar (StatusTrackingBarManager / MainStatusTrackingBarContainer). Live toggle without requiring /reload.",
                        type = "toggle",
                        width = "full",
                        order = 4,
                        get = function() return not (db.databars and (db.databars.hideBlizzardXPBar == false or db.databars.replaceBlizzardXP == false)) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.hideBlizzardXPBar = val
                            db.databars.replaceBlizzardXP = val
                            if ns.DataBarsModule then ns.DataBarsModule:SuppressBlizzardXP(val) end
                        end,
                    },
                    showCompletedQuestXP = {
                        name = "Show Completed Quest XP (Ghost Bar)",
                        desc = "Display a stacked overlay bar indicating how much XP you will gain when turning in all currently completed quests in your log.",
                        type = "toggle",
                        width = "full",
                        order = 5,
                        get = function() return not (db.databars and db.databars.showCompletedQuestXP == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.showCompletedQuestXP = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    showAllQuestXP = {
                        name = "Show All Quests XP (Ghost Bar)",
                        desc = "Display a stacked overlay bar indicating total XP from all active quests in your log (both in-progress and completed), filling up as you quest and level.",
                        type = "toggle",
                        width = "full",
                        order = 5.5,
                        get = function() return (db.databars and db.databars.showAllQuestXP == true) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.showAllQuestXP = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    hideQuestXPText = {
                        name = "Hide Quest XP Text on Bar (Ghost Bars)",
                        desc = "Hide bonus quest XP readouts (+Done and +All) from the XP progress bar. The visual ghost bars will still be drawn on the bar, and full quest XP details remain accessible on the tooltip.",
                        type = "toggle",
                        width = "full",
                        order = 5.6,
                        get = function() return (db.databars and db.databars.hideQuestXPText == true) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.hideQuestXPText = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    showDingReadyText = {
                        name = "Show [Ding Ready!] Alert",
                        desc = "Display an eye-catching [Ding Ready!] indicator when your completed quest turn-ins exceed the XP required to reach the next level.",
                        type = "toggle",
                        width = "full",
                        order = 6,
                        get = function() return not (db.databars and db.databars.showDingReadyText == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.showDingReadyText = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    showRestedXP = {
                        name = "Show Rested XP Overlay",
                        desc = "Show a rested XP bonus segment on the bar.",
                        type = "toggle",
                        order = 7,
                        get = function() return not (db.databars and db.databars.showRestedXP == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.showRestedXP = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    showReputationAtMax = {
                        name = "Show Watched Reputation at Max Level",
                        desc = "Automatically switch the bar to display your watched faction reputation standing and progress when you reach maximum character level.",
                        type = "toggle",
                        width = "full",
                        order = 8,
                        get = function() return not (db.databars and db.databars.showReputationAtMax == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.showReputationAtMax = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    xpHeight = {
                        name = "Bar Height",
                        desc = "Height of the XP progress bar in pixels (default: 14px).",
                        type = "range",
                        order = 9,
                        min = 8,
                        max = 32,
                        step = 1,
                        get = function() return (db.databars and db.databars.xpHeight) or 14 end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.xpHeight = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPDocking() end
                        end,
                    },
                    xpWidth = {
                        name = "Bar Width (Default / Free Mode)",
                        desc = "Width of the XP progress bar when placed at screen bottom or in free floating mode (default: 512px). When docked to the tracker bottom, width automatically snaps to the tracker width.",
                        type = "range",
                        width = "full",
                        order = 10,
                        min = 180,
                        max = 900,
                        step = 10,
                        get = function() return (db.databars and db.databars.xpWidth) or 512 end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.xpWidth = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPDocking() end
                        end,
                    },
                    xpTextFormat = {
                        name = "Text Display Format",
                        desc = "Choose how the XP text is formatted across the bar.",
                        type = "select",
                        order = 11,
                        values = {
                            ["smart"] = "Smart (Current / Max (Pct%) + Quest XP)",
                            ["cur_max"] = "Current / Max",
                            ["cur_pct"] = "Percentage (Pct%) Only",
                            ["remain"] = "XP Remaining to Level",
                            ["none"] = "Hide Text (Clean Bar)",
                        },
                        get = function() return (db.databars and db.databars.xpTextFormat) or "smart" end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.xpTextFormat = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    xpFontSize = {
                        name = "XP Text Size (px)",
                        desc = "Font size in pixels for the XP progress bar text readout.",
                        type = "range",
                        min = 8,
                        max = 18,
                        step = 1,
                        order = 11.1,
                        get = function() return (db.databars and db.databars.xpFontSize) or 11 end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.xpFontSize = val
                            if ns.DataBarsModule then ns.DataBarsModule:ApplyTypography() end
                        end,
                    },
                    xpFontOutline = {
                        name = "XP Text Outline",
                        desc = "Outline style applied to the XP progress bar text readout.",
                        type = "select",
                        values = fontFlags,
                        order = 11.2,
                        get = function() return (db.databars and db.databars.xpFontOutline) or "OUTLINE" end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.xpFontOutline = val
                            if ns.DataBarsModule then ns.DataBarsModule:ApplyTypography() end
                        end,
                    },
                    resetXPPos = {
                        name = "Reset Free XP Bar Position",
                        desc = "Reset the free floating XP bar back to its default screen position.",
                        type = "execute",
                        order = 12,
                        func = function()
                            if db.databars then db.databars.xpFreePosition = nil end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPDocking() end
                        end,
                    },

                    -- XP Bar Colors
                    xpColorHeader = {
                        name = "XP Bar Colors",
                        type = "header",
                        order = 13,
                    },
                    xpColor = {
                        name = "Player XP Bar Color",
                        desc = "Color of the main player experience progress bar (default: Purple).",
                        type = "color",
                        hasAlpha = true,
                        order = 14,
                        get = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            local c = (curDB and curDB.xpColor) or { r = 0.58, g = 0.00, b = 0.83, a = 1.00 }
                            return c.r, c.g, c.b, c.a or 1.00
                        end,
                        set = function(_, r, g, b, a)
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            if not curDB then
                                if ns.db then ns.db.databars = {} curDB = ns.db.databars end
                            end
                            if curDB then
                                curDB.xpColor = { r = r, g = g, b = b, a = a }
                            end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    restedColor = {
                        name = "Rested XP Color",
                        desc = "Color of the rested bonus XP segment (default: Blue).",
                        type = "color",
                        hasAlpha = true,
                        order = 15,
                        get = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            local c = (curDB and curDB.restedColor) or { r = 0.00, g = 0.44, b = 0.88, a = 1.00 }
                            return c.r, c.g, c.b, c.a or 1.00
                        end,
                        set = function(_, r, g, b, a)
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            if not curDB then
                                if ns.db then ns.db.databars = {} curDB = ns.db.databars end
                            end
                            if curDB then
                                curDB.restedColor = { r = r, g = g, b = b, a = a }
                            end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    questXPColor = {
                        name = "Completed Quest XP Color",
                        desc = "Color of the completed quest turn-in ghost bar (default: Green).",
                        type = "color",
                        hasAlpha = true,
                        order = 16,
                        get = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            local c = (curDB and curDB.questXPColor) or { r = 0.15, g = 0.80, b = 0.45, a = 1.00 }
                            return c.r, c.g, c.b, c.a or 1.00
                        end,
                        set = function(_, r, g, b, a)
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            if not curDB then
                                if ns.db then ns.db.databars = {} curDB = ns.db.databars end
                            end
                            if curDB then
                                curDB.questXPColor = { r = r, g = g, b = b, a = a }
                            end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    allQuestXPColor = {
                        name = "All Quests XP Color",
                        desc = "Color of the all active quests ghost bar (default: Darker Green 80% opacity).",
                        type = "color",
                        hasAlpha = true,
                        order = 16.5,
                        get = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            local c = (curDB and curDB.allQuestXPColor) or { r = 0.12, g = 0.45, b = 0.25, a = 0.80 }
                            return c.r, c.g, c.b, c.a or 0.80
                        end,
                        set = function(_, r, g, b, a)
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            if not curDB then
                                if ns.db then ns.db.databars = {} curDB = ns.db.databars end
                            end
                            if curDB then
                                curDB.allQuestXPColor = { r = r, g = g, b = b, a = a }
                            end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    dingReadyColor = {
                        name = "Ding Ready Alert Color",
                        desc = "Color of the quest XP bar when turn-ins exceed level requirement (default: Gold).",
                        type = "color",
                        hasAlpha = true,
                        order = 17,
                        get = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            local c = (curDB and curDB.dingReadyColor) or { r = 1.00, g = 0.82, b = 0.00, a = 1.00 }
                            return c.r, c.g, c.b, c.a or 1.00
                        end,
                        set = function(_, r, g, b, a)
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            if not curDB then
                                if ns.db then ns.db.databars = {} curDB = ns.db.databars end
                            end
                            if curDB then
                                curDB.dingReadyColor = { r = r, g = g, b = b, a = a }
                            end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                        end,
                    },
                    resetXPColors = {
                        name = "Reset XP Colors to Default",
                        desc = "Reset all XP bar colors back to defaults (Purple XP, Blue Rested, Lighter Green Completed Quests, Darker Green All Quests, Gold Ding Ready).",
                        type = "execute",
                        order = 18,
                        func = function()
                            local curDB = (ns.dbObject and ns.dbObject.profile and ns.dbObject.profile.databars) or (ns.db and ns.db.databars)
                            if not curDB then
                                if ns.db then ns.db.databars = {} curDB = ns.db.databars end
                            end
                            if curDB then
                                curDB.xpBgColor = { r = 0.00, g = 0.00, b = 0.00, a = 0.00 }
                                curDB.xpColor = { r = 0.58, g = 0.00, b = 0.83, a = 1.00 }
                                curDB.restedColor = { r = 0.00, g = 0.44, b = 0.88, a = 1.00 }
                                curDB.questXPColor = { r = 0.25, g = 0.85, b = 0.45, a = 0.65 }
                                curDB.allQuestXPColor = { r = 0.12, g = 0.45, b = 0.25, a = 0.80 }
                                curDB.dingReadyColor = { r = 1.00, g = 0.82, b = 0.00, a = 1.00 }
                            end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateXPBar() end
                            print("|cff00c0ff[Bleakfiber Tracker]|r XP bar colors have been reset to defaults.")
                        end,
                    },
                    xpBorderStyle = {
                        name = "XP Bar Border Style",
                        desc = "Select border frame style for the XP progress bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "select",
                        order = 18.1,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) end,
                        values = barBorderStyles,
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                return (db.backdrop and db.backdrop.borderStyle) or "flat"
                            end
                            return (db.databars and db.databars.xpBorderStyle) or "flat"
                        end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.xpBorderStyle = val
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    xpBarTexture = {
                        name = "XP Statusbar Texture",
                        desc = "Select texture pattern for the XP progress bar.",
                        type = "select",
                        order = 18.2,
                        values = GetStatusbarTextureList,
                        get = function() return (db.databars and db.databars.xpBarTexture) or "Solid" end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.xpBarTexture = val
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    xpBgTexture = {
                        name = "XP Base / Background Texture",
                        desc = "Select the background surface texture behind the XP progress bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "select",
                        order = 18.25,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) end,
                        values = {
                            ["solid"] = "Solid / Flat",
                            ["tooltip"] = "Blizzard Tooltip Dark",
                            ["marble"] = "Blizzard Marble",
                            ["rock"] = "Blizzard Rock",
                            ["parchment"] = "Blizzard Quest Parchment",
                            ["parchment_clean"] = "Blizzard Parchment (Clean)",
                        },
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                return (db.backdrop and db.backdrop.bgTexture) or "solid"
                            end
                            return (db.databars and db.databars.xpBgTexture) or "solid"
                        end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            local prev = db.databars.xpBgTexture or "solid"
                            db.databars.xpBgTexture = val
                            local isParchment = (val == "parchment" or val == "parchment_clean")
                            local wasParchment = (prev == "parchment" or prev == "parchment_clean")
                            if isParchment and not wasParchment then
                                db.databars.xpBgColor = { r = 0.96, g = 0.90, b = 0.78, a = 0.90 }
                            elseif not isParchment and wasParchment then
                                db.databars.xpBgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                            end
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    xpBgColor = {
                        name = "XP Base / Background Color & Opacity",
                        desc = "Set the background backdrop color and opacity behind the XP bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "color",
                        hasAlpha = true,
                        order = 18.3,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) end,
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                local c = (db.backdrop and db.backdrop.bgColor) or { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                                return c.r, c.g, c.b, c.a or 0.65
                            end
                            local c = (db.databars and db.databars.xpBgColor) or { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                            return c.r, c.g, c.b, c.a or 0.65
                        end,
                        set = function(_, r, g, b, a)
                            db.databars = db.databars or {}
                            db.databars.xpBgColor = { r = r, g = g, b = b, a = a }
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    xpBorderColor = {
                        name = "XP Border Color & Opacity",
                        desc = "Set the border color and opacity around the XP bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "color",
                        hasAlpha = true,
                        order = 18.4,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) or (db.databars and db.databars.xpBorderStyle == "none") end,
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                if db.backdrop and db.backdrop.classColorBorder and ns.GetClassColor then
                                    local cc = ns.GetClassColor()
                                    if cc then
                                        return cc.r, cc.g, cc.b, (db.backdrop.borderColor and db.backdrop.borderColor.a) or 0.90
                                    end
                                end
                                local c = (db.backdrop and db.backdrop.borderColor) or { r = 0.15, g = 0.15, b = 0.15, a = 0.90 }
                                return c.r, c.g, c.b, c.a or 0.90
                            end
                            local c = (db.databars and db.databars.xpBorderColor) or { r = 0.12, g = 0.12, b = 0.16, a = 0.95 }
                            return c.r, c.g, c.b, c.a or 0.95
                        end,
                        set = function(_, r, g, b, a)
                            db.databars = db.databars or {}
                            db.databars.xpBorderColor = { r = r, g = g, b = b, a = a }
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },

                    -- Location Bar Section
                    locHeader = {
                        name = "Location & Precision Coordinates Header Bar",
                        type = "header",
                        order = 20,
                    },
                    enableLocationBar = {
                        name = "Enable Location Header Bar",
                        desc = "Display a clean, stylized header bar showing your current Zone, Subzone, territory PvP status color, and live coordinates.",
                        type = "toggle",
                        width = "full",
                        order = 21,
                        get = function() return db.databars and db.databars.enableLocationBar end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.enableLocationBar = val
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    locDockMode = {
                        name = "Location Bar Docking Position",
                        desc = "Choose where to dock the Location Bar:\n• Dock to Tracker Top: Dynamically size-snaps above the quest tracker header.\n• Dock to Minimap Top: Centers directly above the minimap cluster.\n• Free Floating: Movable anywhere on screen.",
                        type = "select",
                        width = "full",
                        order = 22,
                        values = {
                            ["tracker_top"] = "Dock to Tracker Top (Auto-Snap)",
                            ["minimap_top"] = "Dock to Minimap Top",
                            ["free"] = "Free Floating (Movable)",
                        },
                        get = function() return (db.databars and db.databars.locDockMode) or "tracker_top" end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.locDockMode = val
                            if ns.DataBarsModule then
                                ns.DataBarsModule:UpdateLocationDocking()
                                ns.DataBarsModule:UpdateLocationBar()
                            end
                        end,
                    },
                    hideMinimapHeader = {
                        name = "Hide Default Minimap Zone Header",
                        desc = "Hide Blizzard's default minimap zone header text and border (MinimapCluster.ZoneTextButton / BorderTop) when Location Bar is enabled.",
                        type = "toggle",
                        width = "full",
                        order = 23,
                        get = function() return not (db.databars and db.databars.hideMinimapHeader == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.hideMinimapHeader = val
                            if ns.DataBarsModule then
                                ns.DataBarsModule:ApplyMinimapHeaderSuppression(val)
                            end
                        end,
                    },
                    colorTerritory = {
                        name = "Color Zone by PvP Territory",
                        desc = "Color the zone text based on territory type: Friendly (Green), Sanctuary (Cyan), Contested (Gold), Hostile (Red).",
                        type = "toggle",
                        width = "full",
                        order = 24,
                        get = function() return not (db.databars and db.databars.colorTerritory == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.colorTerritory = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateLocationBar(true) end
                        end,
                    },
                    showCoords = {
                        name = "Show Player Coordinates",
                        desc = "Show high-precision player coordinates (XX.X, YY.Y) in the location header.",
                        type = "toggle",
                        order = 25,
                        get = function() return not (db.databars and db.databars.showCoords == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.showCoords = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateLocationBar(true) end
                        end,
                    },
                    showSubzone = {
                        name = "Show Subzone Text",
                        desc = "Display specific subzone/area name next to the zone name.",
                        type = "toggle",
                        order = 26,
                        get = function() return not (db.databars and db.databars.showSubzone == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.showSubzone = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateLocationBar(true) end
                        end,
                    },
                    locFormat = {
                        name = "Location Text Format",
                        desc = "Choose how zone and subzone names are formatted:\n  Subzone When Available: Shows subzone when in a landmark, or zone when in the wild.\n  Smart Auto-Fit: Displays both if they fit, or collapses to specific subzone/zone when cramped to prevent overflowing.\n  Zone Only: Always displays the parent zone name.\n  Both: Always shows Zone • Subzone (truncates with ... if too wide).",
                        type = "select",
                        order = 26.5,
                        values = {
                            ["subzone_only"] = "Subzone When Available (Recommended)",
                            ["smart"] = "Smart Auto-Fit",
                            ["zone_only"] = "Zone Only",
                            ["both"] = "Both (Zone • Subzone)",
                        },
                        get = function() return (db.databars and db.databars.locFormat) or "subzone_only" end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.locFormat = val
                            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateLocationBar(true) end
                        end,
                    },
                    locHeight = {
                        name = "Location Bar Height",
                        desc = "Height of the location header bar in pixels (default: 22px).",
                        type = "range",
                        order = 27,
                        min = 16,
                        max = 36,
                        step = 1,
                        get = function() return (db.databars and db.databars.locHeight) or 22 end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.locHeight = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateLocationDocking() end
                        end,
                    },
                    locFontSize = {
                        name = "Location Text Size (px)",
                        desc = "Font size in pixels for the Location Bar text readout.",
                        type = "range",
                        min = 8,
                        max = 18,
                        step = 1,
                        order = 27.1,
                        get = function() return (db.databars and db.databars.locFontSize) or 11 end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.locFontSize = val
                            if ns.DataBarsModule then ns.DataBarsModule:ApplyTypography() end
                        end,
                    },
                    locFontOutline = {
                        name = "Location Text Outline",
                        desc = "Outline style applied to the Location Bar text readout.",
                        type = "select",
                        values = fontFlags,
                        order = 27.2,
                        get = function() return (db.databars and db.databars.locFontOutline) or "OUTLINE" end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.locFontOutline = val
                            if ns.DataBarsModule then ns.DataBarsModule:ApplyTypography() end
                        end,
                    },
                    resetLocPos = {
                        name = "Reset Free Location Bar Position",
                        desc = "Reset the free floating Location Bar back to its default position.",
                        type = "execute",
                        width = "full",
                        order = 28,
                        func = function()
                            if db.databars then db.databars.locFreePosition = nil end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateLocationDocking() end
                        end,
                    },
                    locBorderStyle = {
                        name = "Location Bar Border Style",
                        desc = "Select border frame style for the Location Bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "select",
                        order = 28.1,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) end,
                        values = barBorderStyles,
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                return (db.backdrop and db.backdrop.borderStyle) or "flat"
                            end
                            return (db.databars and db.databars.locBorderStyle) or "flat"
                        end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.locBorderStyle = val
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    locBgTexture = {
                        name = "Location Background Texture",
                        desc = "Select the background surface texture behind the Location Bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "select",
                        order = 28.15,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) end,
                        values = {
                            ["solid"] = "Solid / Flat",
                            ["tooltip"] = "Blizzard Tooltip Dark",
                            ["marble"] = "Blizzard Marble",
                            ["rock"] = "Blizzard Rock",
                            ["parchment"] = "Blizzard Quest Parchment",
                            ["parchment_clean"] = "Blizzard Parchment (Clean)",
                        },
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                return (db.backdrop and db.backdrop.bgTexture) or "solid"
                            end
                            return (db.databars and db.databars.locBgTexture) or "solid"
                        end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            local prev = db.databars.locBgTexture or "solid"
                            db.databars.locBgTexture = val
                            local isParchment = (val == "parchment" or val == "parchment_clean")
                            local wasParchment = (prev == "parchment" or prev == "parchment_clean")
                            if isParchment and not wasParchment then
                                db.databars.locBgColor = { r = 0.96, g = 0.90, b = 0.78, a = 0.90 }
                            elseif not isParchment and wasParchment then
                                db.databars.locBgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                            end
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    locBgColor = {
                        name = "Location Background Color & Opacity",
                        desc = "Set the background backdrop color and opacity behind the Location Bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "color",
                        hasAlpha = true,
                        order = 28.2,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) end,
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                local c = (db.backdrop and db.backdrop.bgColor) or { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                                return c.r, c.g, c.b, c.a or 0.65
                            end
                            local c = (db.databars and db.databars.locBgColor) or { r = 0.06, g = 0.08, b = 0.12, a = 0.90 }
                            return c.r, c.g, c.b, c.a or 0.90
                        end,
                        set = function(_, r, g, b, a)
                            db.databars = db.databars or {}
                            db.databars.locBgColor = { r = r, g = g, b = b, a = a }
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    locBorderColor = {
                        name = "Location Border Color & Opacity",
                        desc = "Set the border color and opacity around the Location Bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "color",
                        hasAlpha = true,
                        order = 28.3,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) or (db.databars and db.databars.locBorderStyle == "none") end,
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                if db.backdrop and db.backdrop.classColorBorder and ns.GetClassColor then
                                    local cc = ns.GetClassColor()
                                    if cc then
                                        return cc.r, cc.g, cc.b, (db.backdrop.borderColor and db.backdrop.borderColor.a) or 0.90
                                    end
                                end
                                local c = (db.backdrop and db.backdrop.borderColor) or { r = 0.15, g = 0.15, b = 0.15, a = 0.90 }
                                return c.r, c.g, c.b, c.a or 0.90
                            end
                            local c = (db.databars and db.databars.locBorderColor) or { r = 0.15, g = 0.55, b = 0.95, a = 0.85 }
                            return c.r, c.g, c.b, c.a or 0.85
                        end,
                        set = function(_, r, g, b, a)
                            db.databars = db.databars or {}
                            db.databars.locBorderColor = { r = r, g = g, b = b, a = a }
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    locCustomTextColor = {
                        name = "Override PvP Territory Text Color",
                        desc = "Use a custom static text color instead of dynamically coloring zone text by PvP territory status.",
                        type = "toggle",
                        width = "full",
                        order = 28.4,
                        get = function() return db.databars and db.databars.locCustomTextColor == true end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.locCustomTextColor = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateLocationBar(true) end
                        end,
                    },
                    locTextColor = {
                        name = "Custom Location Text Color",
                        desc = "Custom text color for the location and zone name.",
                        type = "color",
                        order = 28.5,
                        disabled = function() return not (db.databars and db.databars.locCustomTextColor) end,
                        get = function()
                            local c = (db.databars and db.databars.locTextColor) or { r = 1.00, g = 0.82, b = 0.00 }
                            return c.r, c.g, c.b
                        end,
                        set = function(_, r, g, b)
                            db.databars = db.databars or {}
                            db.databars.locTextColor = { r = r, g = g, b = b, a = 1.00 }
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateLocationBar(true) end
                        end,
                    },

                    -- Quest Timer Bar Section
                    timerHeader = {
                        name = "Quest Timer DataBar (Timed Quests)",
                        type = "header",
                        order = 30,
                    },
                    enableTimerBar = {
                        name = "Enable Quest Timer Bar",
                        desc = "Display a standalone status bar showing time remaining for active timed quests (e.g. Dun Morogh's 5-minute Hot Mug run). Automatically hides when no timed quest is active.",
                        type = "toggle",
                        width = "full",
                        order = 31,
                        get = function() return not (db.databars and db.databars.enableTimerBar == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.enableTimerBar = val
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    timerDockMode = {
                        name = "Timer Bar Docking Position",
                        desc = "Choose where to dock the Quest Timer Bar:\n• Dock to Tracker Top: Snaps above tracker header.\n• Dock to Tracker Bottom: Snaps below tracker.\n• Free Floating: Movable anywhere on screen.",
                        type = "select",
                        order = 32,
                        values = {
                            ["tracker_top"] = "Dock to Tracker Top",
                            ["tracker_bottom"] = "Dock to Tracker Bottom",
                            ["free"] = "Free Floating (Movable)",
                        },
                        get = function() return (db.databars and db.databars.timerDockMode) or "tracker_top" end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.timerDockMode = val
                            if ns.DataBarsModule then
                                ns.DataBarsModule:UpdateTimerDocking()
                                ns.DataBarsModule:UpdateTimerBar()
                            end
                        end,
                    },
                    timerShowTitle = {
                        name = "Show Quest Title on Timer Bar",
                        desc = "Display the quest name alongside the countdown timer (e.g. 'A Hot Mug: 04:12').",
                        type = "toggle",
                        width = "full",
                        order = 33,
                        get = function() return not (db.databars and db.databars.timerShowTitle == false) end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.timerShowTitle = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateTimerBar() end
                        end,
                    },
                    timerHeight = {
                        name = "Timer Bar Height (px)",
                        desc = "Height of the timer bar in pixels (default: 22px).",
                        type = "range",
                        order = 34,
                        min = 16,
                        max = 36,
                        step = 1,
                        get = function() return (db.databars and db.databars.timerHeight) or 22 end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.timerHeight = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateTimerDocking() end
                        end,
                    },
                    timerWidth = {
                        name = "Timer Bar Width (px)",
                        desc = "Width of the timer bar in pixels when in free floating mode (default: 220px).",
                        type = "range",
                        order = 35,
                        min = 140,
                        max = 400,
                        step = 5,
                        get = function() return (db.databars and db.databars.timerWidth) or 220 end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.timerWidth = val
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateTimerDocking() end
                        end,
                    },
                    timerFontSize = {
                        name = "Timer Text Size (px)",
                        desc = "Font size in pixels for the Timer Bar countdown text.",
                        type = "range",
                        min = 8,
                        max = 18,
                        step = 1,
                        order = 36,
                        get = function() return (db.databars and db.databars.timerFontSize) or 11 end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.timerFontSize = val
                            if ns.DataBarsModule then ns.DataBarsModule:ApplyTypography() end
                        end,
                    },
                    timerFontOutline = {
                        name = "Timer Text Outline",
                        desc = "Outline style applied to the Timer Bar text readout.",
                        type = "select",
                        values = fontFlags,
                        order = 37,
                        get = function() return (db.databars and db.databars.timerFontOutline) or "OUTLINE" end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.timerFontOutline = val
                            if ns.DataBarsModule then ns.DataBarsModule:ApplyTypography() end
                        end,
                    },
                    timerBorderStyle = {
                        name = "Timer Bar Border Style",
                        desc = "Select border frame style for the Quest Timer Bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "select",
                        order = 37.1,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) end,
                        values = barBorderStyles,
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                return (db.backdrop and db.backdrop.borderStyle) or "flat"
                            end
                            return (db.databars and db.databars.timerBorderStyle) or "flat"
                        end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.timerBorderStyle = val
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    timerBarTexture = {
                        name = "Timer Statusbar Texture",
                        desc = "Select texture pattern for the Quest Timer progress bar.",
                        type = "select",
                        order = 37.2,
                        values = GetStatusbarTextureList,
                        get = function() return (db.databars and db.databars.timerBarTexture) or "Solid" end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            db.databars.timerBarTexture = val
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    timerColor = {
                        name = "Timer Bar Fill Color & Opacity",
                        desc = "Set the default fill color and opacity for the timer status bar (during non-critical time remaining).",
                        type = "color",
                        hasAlpha = true,
                        order = 37.3,
                        get = function()
                            local c = (db.databars and db.databars.timerColor) or { r = 1.00, g = 0.82, b = 0.00, a = 0.50 }
                            return c.r, c.g, c.b, c.a or 0.50
                        end,
                        set = function(_, r, g, b, a)
                            db.databars = db.databars or {}
                            db.databars.timerColor = { r = r, g = g, b = b, a = a }
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateTimerBar(true) end
                        end,
                    },
                    timerBgTexture = {
                        name = "Timer Bar Background Texture",
                        desc = "Select the background surface texture behind the Quest Timer Bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "select",
                        order = 37.35,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) end,
                        values = {
                            ["solid"] = "Solid / Flat",
                            ["tooltip"] = "Blizzard Tooltip Dark",
                            ["marble"] = "Blizzard Marble",
                            ["rock"] = "Blizzard Rock",
                            ["parchment"] = "Blizzard Quest Parchment",
                            ["parchment_clean"] = "Blizzard Parchment (Clean)",
                        },
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                return (db.backdrop and db.backdrop.bgTexture) or "solid"
                            end
                            return (db.databars and db.databars.timerBgTexture) or "solid"
                        end,
                        set = function(_, val)
                            db.databars = db.databars or {}
                            local prev = db.databars.timerBgTexture or "solid"
                            db.databars.timerBgTexture = val
                            local isParchment = (val == "parchment" or val == "parchment_clean")
                            local wasParchment = (prev == "parchment" or prev == "parchment_clean")
                            if isParchment and not wasParchment then
                                db.databars.timerBgColor = { r = 0.96, g = 0.90, b = 0.78, a = 0.90 }
                            elseif not isParchment and wasParchment then
                                db.databars.timerBgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                            end
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    timerBgColor = {
                        name = "Timer Background Color & Opacity",
                        desc = "Set the background backdrop color and opacity behind the Timer Bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "color",
                        hasAlpha = true,
                        order = 37.4,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) end,
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                local c = (db.backdrop and db.backdrop.bgColor) or { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                                return c.r, c.g, c.b, c.a or 0.65
                            end
                            local c = (db.databars and db.databars.timerBgColor) or { r = 0.06, g = 0.08, b = 0.12, a = 0.90 }
                            return c.r, c.g, c.b, c.a or 0.90
                        end,
                        set = function(_, r, g, b, a)
                            db.databars = db.databars or {}
                            db.databars.timerBgColor = { r = r, g = g, b = b, a = a }
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    timerBorderColor = {
                        name = "Timer Border Color & Opacity",
                        desc = "Set the border color and opacity around the Timer Bar (Inherited from tracker frame when Inherit Tracker Frame Appearance is enabled).",
                        type = "color",
                        hasAlpha = true,
                        order = 37.5,
                        disabled = function() return not (db.databars and db.databars.useTrackerAppearance == false) or (db.databars and db.databars.timerBorderStyle == "none") end,
                        get = function()
                            if not (db.databars and db.databars.useTrackerAppearance == false) then
                                if db.backdrop and db.backdrop.classColorBorder and ns.GetClassColor then
                                    local cc = ns.GetClassColor()
                                    if cc then
                                        return cc.r, cc.g, cc.b, (db.backdrop.borderColor and db.backdrop.borderColor.a) or 0.85
                                    end
                                end
                                local c = (db.backdrop and db.backdrop.borderColor) or { r = 1.00, g = 0.82, b = 0.00, a = 0.85 }
                                return c.r, c.g, c.b, c.a or 0.85
                            end
                            local c = (db.databars and db.databars.timerBorderColor) or { r = 1.00, g = 0.82, b = 0.00, a = 0.85 }
                            return c.r, c.g, c.b, c.a or 0.85
                        end,
                        set = function(_, r, g, b, a)
                            db.databars = db.databars or {}
                            db.databars.timerBorderColor = { r = r, g = g, b = b, a = a }
                            if ns.DataBarsModule then ns.DataBarsModule:RefreshBars() end
                        end,
                    },
                    previewTimer = {
                        name = "Preview / Move Timer Bar",
                        desc = "Temporarily toggle preview mode for the Quest Timer Bar so you can adjust its position even when no timed quest is active.",
                        type = "execute",
                        order = 38,
                        func = function()
                            if ns.DataBarsModule then
                                ns.DataBarsModule.timerPreviewMode = not ns.DataBarsModule.timerPreviewMode
                                ns.DataBarsModule:RefreshBars()
                            end
                        end,
                    },
                    resetTimerPos = {
                        name = "Reset Timer Bar Position",
                        desc = "Reset the free floating Timer Bar back to its default position.",
                        type = "execute",
                        order = 39,
                        func = function()
                            if db.databars then db.databars.timerFreePosition = nil end
                            if ns.DataBarsModule then ns.DataBarsModule:UpdateTimerDocking() end
                        end,
                    },
                },
            },
        },
    }

    local AceDBOptions = LibStub and LibStub("AceDBOptions-3.0", true)
    if AceDBOptions and ns.dbObject then
        options.args.profiles = AceDBOptions:GetOptionsTable(ns.dbObject)
        options.args.profiles.order = 10
    end

    -- Universal persistence wrapper: guarantee that ANY setting modified across
    -- the entire options tree immediately invokes ns.FlushDBToGlobals()
    local function WrapSettersWithFlush(group)
        if not group or type(group) ~= "table" or not group.args then return end
        for _, arg in pairs(group.args) do
            if type(arg) == "table" then
                if arg.type == "group" then
                    WrapSettersWithFlush(arg)
                elseif type(arg.set) == "function" then
                    local origSet = arg.set
                    arg.set = function(...)
                        local res = origSet(...)
                        if ns.FlushDBToGlobals then
                            ns.FlushDBToGlobals()
                        end
                        return res
                    end
                end
            end
        end
    end
    WrapSettersWithFlush(options)

    return options
end

function Config:InitializeOptions()
    if self.initialized then return end
    self.initialized = true

    if ACR and ACD then
        ACR:RegisterOptionsTable("BleakfiberQuestTracker", GetOptionsTable)
        self.optionsFrame, self.categoryID = ACD:AddToBlizOptions("BleakfiberQuestTracker", "Bleakfiber's Quest Tracker")

        local AceDBOptions = LibStub and LibStub("AceDBOptions-3.0", true)
        if AceDBOptions and ns.dbObject then
            local profileOptions = AceDBOptions:GetOptionsTable(ns.dbObject)
            ACR:RegisterOptionsTable("BleakfiberQuestTracker_Profiles", profileOptions)
            ACD:AddToBlizOptions("BleakfiberQuestTracker_Profiles", "Profiles", "Bleakfiber's Quest Tracker")
        end

        local function OnConfigClosed()
            if ns.Tracker and ns.Tracker.HideConfigOverlay then
                ns.Tracker:HideConfigOverlay()
            end
        end

        if self.optionsFrame and self.optionsFrame.HookScript then
            self.optionsFrame:HookScript("OnHide", OnConfigClosed)
        end
        if InterfaceOptionsFrame and InterfaceOptionsFrame.HookScript then
            InterfaceOptionsFrame:HookScript("OnHide", OnConfigClosed)
        end
        if SettingsPanel and SettingsPanel.HookScript then
            SettingsPanel:HookScript("OnHide", OnConfigClosed)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Master Config Addon Integration & Dark Slate / Gold Standalone Theme
-- ---------------------------------------------------------------------------

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local MAIN_WINDOW_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
}

local INSET_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 12,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

local COLORS = {
    bgSlate      = { 0.08, 0.10, 0.13, 0.96 }, -- Dark iron / slate
    sidebarBg    = { 0.06, 0.07, 0.09, 0.92 }, -- Deep inset background
    contentBg    = { 0.05, 0.06, 0.08, 0.94 }, -- Dark content background
    goldBorder   = { 0.82, 0.68, 0.28, 1.00 }, -- Bright beveled gold
    goldMuted    = { 0.50, 0.42, 0.20, 0.85 }, -- Muted gold border
    goldText     = { 1.00, 0.82, 0.25 },       -- #FFD140
    whiteText    = { 0.90, 0.92, 0.94 },
    dimText      = { 0.55, 0.58, 0.63 },
    tabNormal    = { 0.12, 0.14, 0.17, 0.65 },
    tabHighlight = { 0.20, 0.22, 0.27, 0.80 },
    tabActive    = { 0.22, 0.19, 0.12, 0.95 }, -- Gold-tinted active tab
}

--[[-----------------------------------------------------------------------------
    Native Bleakfiber UI Widgets & Responsive Layout Engine for Quest Tracker
-------------------------------------------------------------------------------]]
local function SetupAutoScroll(scrollFrame, scrollChild)
    if not (scrollFrame and scrollChild) then return end
    local scrollBar = _G[scrollFrame:GetName() and (scrollFrame:GetName() .. "ScrollBar")]

    local function UpdateScrollState()
        local frameHeight = scrollFrame:GetHeight()
        local childHeight = scrollChild:GetHeight()
        if not frameHeight or frameHeight <= 0 then return end
        if childHeight <= frameHeight + 2 then
            if scrollBar and scrollBar:IsShown() then
                scrollBar:Hide()
            end
            scrollFrame:EnableMouseWheel(false)
            scrollFrame:SetVerticalScroll(0)
        else
            if scrollBar and not scrollBar:IsShown() then
                scrollBar:Show()
            end
            scrollFrame:EnableMouseWheel(true)
        end
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local frameHeight = self:GetHeight()
        local childHeight = scrollChild:GetHeight()
        if not frameHeight or childHeight <= frameHeight + 2 then return end
        local cur = self:GetVerticalScroll()
        local maxScroll = math.max(0, childHeight - frameHeight)
        local step = 32
        local newScroll = cur - (delta * step)
        if newScroll < 0 then newScroll = 0 end
        if newScroll > maxScroll then newScroll = maxScroll end
        self:SetVerticalScroll(newScroll)
    end)

    scrollFrame:HookScript("OnSizeChanged", UpdateScrollState)
    scrollChild:HookScript("OnSizeChanged", UpdateScrollState)
    scrollFrame:HookScript("OnShow", UpdateScrollState)
    UpdateScrollState()
    return UpdateScrollState
end

local function CreateSectionHeader(parent, text, xOfs, yOfs)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", xOfs or 16, yOfs or -10)
    header:SetText(text)
    header:SetTextColor(COLORS.goldText[1], COLORS.goldText[2], COLORS.goldText[3])

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    divider:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    divider:SetColorTexture(COLORS.goldMuted[1], COLORS.goldMuted[2], COLORS.goldMuted[3], 0.5)

    return header, divider
end

local function CreateStyledCheckbox(parent, labelText, tooltipText, getFunc, setFunc)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)

    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 6, 1)
    text:SetText(labelText)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")
    cb.Text = text

    if tooltipText then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(labelText, COLORS.goldText[1], COLORS.goldText[2], COLORS.goldText[3])
            GameTooltip:AddLine(tooltipText, COLORS.whiteText[1], COLORS.whiteText[2], COLORS.whiteText[3], true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        if setFunc then setFunc(checked) end
        if ns.Tracker and ns.Tracker.UpdateSettings then ns.Tracker:UpdateSettings() end
        if ns.FireCallback then ns:FireCallback("SETTINGS_UPDATED") end
        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
    end)

    cb.Sync = function()
        if getFunc then cb:SetChecked(getFunc() == true) end
    end

    return cb
end

local function CreateStyledSlider(parent, name, labelText, tooltipText, minVal, maxVal, step, getFunc, setFunc, formatStr)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetWidth(190)
    slider:SetHeight(16)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
    label:SetText(labelText)
    label:SetTextColor(COLORS.goldText[1], COLORS.goldText[2], COLORS.goldText[3])
    slider.Label = label

    local lowText = _G[slider:GetName() .. "Low"]
    local highText = _G[slider:GetName() .. "High"]
    local valText = _G[slider:GetName() .. "Text"]

    if lowText then
        lowText:SetText(tostring(minVal))
        lowText:SetTextColor(COLORS.dimText[1], COLORS.dimText[2], COLORS.dimText[3])
    end
    if highText then
        highText:SetText(tostring(maxVal))
        highText:SetTextColor(COLORS.dimText[1], COLORS.dimText[2], COLORS.dimText[3])
    end

    if valText then
        valText:ClearAllPoints()
        valText:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", 0, 4)
        valText:SetJustifyH("RIGHT")
        valText:SetTextColor(COLORS.whiteText[1], COLORS.whiteText[2], COLORS.whiteText[3])
    end

    formatStr = formatStr or "%d"

    local function UpdateValText(val)
        if valText then
            valText:SetText(string.format(formatStr, val))
        end
    end

    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor((val / step) + 0.5) * step
        UpdateValText(val)
        if self._isSyncing then return end
        if setFunc then setFunc(val) end
        if ns.Tracker and ns.Tracker.UpdateSettings then ns.Tracker:UpdateSettings() end
        if ns.FireCallback then ns:FireCallback("SETTINGS_UPDATED") end
        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
    end)

    if tooltipText then
        slider:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(labelText, COLORS.goldText[1], COLORS.goldText[2], COLORS.goldText[3])
            GameTooltip:AddLine(tooltipText, COLORS.whiteText[1], COLORS.whiteText[2], COLORS.whiteText[3], true)
            GameTooltip:Show()
        end)
        slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    slider.Sync = function()
        if getFunc then
            slider._isSyncing = true
            local cur = getFunc() or minVal
            slider:SetValue(cur)
            UpdateValText(cur)
            slider._isSyncing = false
        end
    end

    return slider
end

local function CreateStyledButton(parent, text, width, height, onClick, tooltipText)
    local btn = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    btn:SetSize(width or 120, height or 22)
    btn:SetBackdrop(INSET_BACKDROP)
    btn:SetBackdropColor(unpack(COLORS.tabNormal))
    btn:SetBackdropBorderColor(unpack(COLORS.goldMuted))

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(text)
    btn.Label = label

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.22, 0.28, 0.95)
        self:SetBackdropBorderColor(unpack(COLORS.goldBorder))
        label:SetTextColor(COLORS.goldText[1], COLORS.goldText[2], COLORS.goldText[3])
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text, COLORS.goldText[1], COLORS.goldText[2], COLORS.goldText[3])
            GameTooltip:AddLine(tooltipText, COLORS.whiteText[1], COLORS.whiteText[2], COLORS.whiteText[3], true)
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(COLORS.tabNormal))
        self:SetBackdropBorderColor(unpack(COLORS.goldMuted))
        label:SetTextColor(COLORS.whiteText[1], COLORS.whiteText[2], COLORS.whiteText[3])
        if tooltipText then GameTooltip:Hide() end
    end)

    if onClick then
        btn:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
            onClick(self)
        end)
    end

    return btn
end

--[[-----------------------------------------------------------------------------
    Custom Dark Slate & Gold Dropdown Menu System
-------------------------------------------------------------------------------]]
local sharedDropdownMenu = nil
local sharedDropdownCatcher = nil

local function GetOrCreateLocalDropdownMenu()
    if sharedDropdownMenu then return sharedDropdownMenu end

    sharedDropdownCatcher = CreateFrame("Button", "BFQ_DropdownCatcher", UIParent)
    sharedDropdownCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
    sharedDropdownCatcher:SetFrameLevel(98)
    sharedDropdownCatcher:SetAllPoints(UIParent)
    sharedDropdownCatcher:EnableMouse(true)
    sharedDropdownCatcher:Hide()
    sharedDropdownCatcher:SetScript("OnClick", function()
        if sharedDropdownMenu then sharedDropdownMenu:Hide() end
    end)

    local menu = CreateFrame("Frame", "BFQ_DropdownMenu", UIParent, BACKDROP_TEMPLATE)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(99)
    menu:SetClampedToScreen(true)
    menu:SetBackdrop(INSET_BACKDROP)
    menu:SetBackdropColor(0.08, 0.10, 0.13, 0.98)
    menu:SetBackdropBorderColor(unpack(COLORS.goldBorder))
    menu:EnableMouse(true)
    menu:Hide()

    menu:SetScript("OnShow", function()
        sharedDropdownCatcher:Show()
    end)
    menu:SetScript("OnHide", function()
        sharedDropdownCatcher:Hide()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", "BFQ_DropdownScrollFrame", menu, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -22, 4)
    menu.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(150, 100)
    scrollFrame:SetScrollChild(scrollChild)
    menu.scrollChild = scrollChild

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxS = math.max(0, scrollChild:GetHeight() - self:GetHeight())
        local newS = math.min(maxS, math.max(0, cur - (delta * 22)))
        self:SetVerticalScroll(newS)
    end)

    menu.buttons = {}
    sharedDropdownMenu = menu
    return menu
end

local function NormalizeDropdownOptions(options)
    local list = {}
    if type(options) == "table" then
        if #options > 0 then
            for _, item in ipairs(options) do
                if type(item) == "table" then
                    local k = (item.key ~= nil) and item.key or ((item.value ~= nil) and item.value or item[1])
                    local l = item.label or item.text or item[2] or tostring(k)
                    table.insert(list, { key = k, label = l, raw = item })
                else
                    table.insert(list, { key = item, label = tostring(item), raw = item })
                end
            end
        else
            for k, v in pairs(options) do
                table.insert(list, { key = k, label = tostring(v) })
            end
            table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
        end
    end
    return list
end

local function GetAvailableFonts()
    local fonts = {}
    local seen = {}
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and LSM.List then
        local lsmList = LSM:List("font")
        if lsmList then
            for _, f in ipairs(lsmList) do
                if not seen[f] then
                    table.insert(fonts, { key = f, label = f })
                    seen[f] = true
                end
            end
        end
    end
    local standardFonts = {
        "Nata Sans Bold", "Nata Sans Regular", "Nata Sans Medium",
        "BleakUI Bold", "BleakUI Regular",
        "Friz Quadrata TT", "Arial Narrow", "Skurri", "Morpheus"
    }
    for _, f in ipairs(standardFonts) do
        if not seen[f] then
            table.insert(fonts, { key = f, label = f })
            seen[f] = true
        end
    end
    table.sort(fonts, function(a, b) return a.label:lower() < b.label:lower() end)
    return fonts
end

local function CreateStyledDropdown(parent, labelPrefix, width, height, options, getFunc, setFunc, tooltipText, isFont)
    local btn = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    btn:SetSize(width or 180, height or 22)
    btn:SetBackdrop(INSET_BACKDROP)
    btn:SetBackdropColor(unpack(COLORS.tabNormal))
    btn:SetBackdropBorderColor(unpack(COLORS.goldMuted))

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", btn, "LEFT", 8, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    btn.Label = label

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetText("|cFFFFD100v|r")

    local function GetOptionsList()
        if type(options) == "function" then
            return NormalizeDropdownOptions(options())
        end
        return NormalizeDropdownOptions(options)
    end

    local function GetSelectedLabel(curVal)
        local curOpts = GetOptionsList()
        for _, opt in ipairs(curOpts) do
            if opt.key == curVal then return opt.label end
        end
        return tostring(curVal or "N/A")
    end

    local function UpdateLabel()
        local cur = getFunc and getFunc()
        local disp = GetSelectedLabel(cur)
        label:SetText((labelPrefix and (labelPrefix .. ": ") or "") .. disp)
        if isFont then
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            local fPath = LSM and LSM:Fetch("font", cur, true)
            if not fPath and ns.Media and ns.Media.FetchFont then
                fPath = ns.Media:FetchFont(cur)
            end
            if fPath then
                pcall(function() label:SetFont(fPath, 11, "") end)
            end
        end
    end

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.22, 0.28, 0.95)
        self:SetBackdropBorderColor(unpack(COLORS.goldBorder))
        label:SetTextColor(COLORS.goldText[1], COLORS.goldText[2], COLORS.goldText[3])
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(labelPrefix or "Option", COLORS.goldText[1], COLORS.goldText[2], COLORS.goldText[3])
            GameTooltip:AddLine(tooltipText, COLORS.whiteText[1], COLORS.whiteText[2], COLORS.whiteText[3], true)
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(COLORS.tabNormal))
        self:SetBackdropBorderColor(unpack(COLORS.goldMuted))
        label:SetTextColor(COLORS.whiteText[1], COLORS.whiteText[2], COLORS.whiteText[3])
        if tooltipText then GameTooltip:Hide() end
    end)

    btn:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        local menu = GetOrCreateLocalDropdownMenu()
        if menu:IsShown() and menu.currentButton == self then
            menu:Hide()
            return
        end

        local curOpts = GetOptionsList()
        local curVal = getFunc and getFunc()
        menu.currentButton = self

        for _, b in ipairs(menu.buttons) do b:Hide() end

        local btnHeight = 22
        local maxVisible = 8
        local visibleCount = math.min(#curOpts, maxVisible)
        local menuWidth = math.max(width or 180, 160)
        local totalContentHeight = #curOpts * btnHeight

        local hasScroll = (#curOpts > maxVisible)
        menu.scrollChild:SetSize(menuWidth - (hasScroll and 28 or 10), totalContentHeight)

        local scrollBar = _G["BFQ_DropdownScrollFrameScrollBar"]
        if scrollBar then
            if hasScroll then
                scrollBar:Show()
                menu.scrollFrame:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -22, 4)
            else
                scrollBar:Hide()
                menu.scrollFrame:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -4, 4)
            end
        end

        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local selectedIndex = 1

        for i, itm in ipairs(curOpts) do
            local b = menu.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, menu.scrollChild, BACKDROP_TEMPLATE)
                b:SetHeight(btnHeight)
                b:SetBackdrop(INSET_BACKDROP)

                b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                b.text:SetPoint("LEFT", b, "LEFT", 8, 0)
                b.text:SetPoint("RIGHT", b, "RIGHT", -8, 0)
                b.text:SetJustifyH("LEFT")

                b:SetScript("OnEnter", function(s)
                    s:SetBackdropColor(0.20, 0.22, 0.28, 0.95)
                    s:SetBackdropBorderColor(unpack(COLORS.goldBorder))
                end)
                b:SetScript("OnLeave", function(s)
                    if s.isActive then
                        s:SetBackdropColor(0.22, 0.19, 0.12, 0.95)
                        s:SetBackdropBorderColor(unpack(COLORS.goldBorder))
                    else
                        s:SetBackdropColor(0.10, 0.12, 0.15, 0.50)
                        s:SetBackdropBorderColor(unpack(COLORS.goldMuted))
                    end
                end)
                menu.buttons[i] = b
            end

            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", menu.scrollChild, "TOPLEFT", 2, -((i - 1) * btnHeight))
            b:SetPoint("RIGHT", menu.scrollChild, "RIGHT", -2, 0)

            local isActive = (itm.key == curVal)
            b.isActive = isActive
            if isActive then
                selectedIndex = i
                b.text:SetText("|cFFFFD100* |r" .. itm.label)
                b:SetBackdropColor(0.22, 0.19, 0.12, 0.95)
                b:SetBackdropBorderColor(unpack(COLORS.goldBorder))
            else
                b.text:SetText("   " .. itm.label)
                b:SetBackdropColor(0.10, 0.12, 0.15, 0.50)
                b:SetBackdropBorderColor(unpack(COLORS.goldMuted))
            end

            if isFont then
                local fPath = LSM and LSM:Fetch("font", itm.key, true)
                if not fPath and ns.Media and ns.Media.FetchFont then
                    fPath = ns.Media:FetchFont(itm.key)
                end
                if fPath then
                    pcall(function() b.text:SetFont(fPath, 11, "") end)
                end
            else
                b.text:SetFontObject("GameFontHighlightSmall")
            end

            local chosenKey = itm.key
            local chosenRaw = itm.raw
            b:SetScript("OnClick", function()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
                if setFunc then
                    setFunc(chosenKey, chosenRaw)
                end
                UpdateLabel()
                menu:Hide()
                if ns.Tracker and ns.Tracker.UpdateSettings then ns.Tracker:UpdateSettings() end
                if ns.Tracker and ns.Tracker.UpdateTypography then ns.Tracker:UpdateTypography() end
                if ns.FireCallback then ns:FireCallback("SETTINGS_UPDATED") end
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            end)
            b:Show()
        end

        local menuHeight = (visibleCount * btnHeight) + 8
        menu:SetSize(menuWidth, menuHeight)

        local screenHeight = UIParent:GetHeight() or 768
        local btnBottom = self:GetBottom() or (screenHeight / 2)
        menu:ClearAllPoints()
        if btnBottom < (menuHeight + 20) then
            menu:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
        else
            menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        end

        menu:Show()
        menu:Raise()

        if hasScroll then
            local scrollPos = math.max(0, math.min(totalContentHeight - (visibleCount * btnHeight), (selectedIndex - 1) * btnHeight))
            menu.scrollFrame:SetVerticalScroll(scrollPos)
        else
            menu.scrollFrame:SetVerticalScroll(0)
        end
    end)

    btn.Sync = UpdateLabel
    UpdateLabel()
    return btn
end

local function CreateStyledFontDropdown(parent, labelPrefix, width, height, getFunc, setFunc, tooltipText)
    return CreateStyledDropdown(parent, labelPrefix, width, height, GetAvailableFonts, getFunc, setFunc, tooltipText, true)
end

local function CreateStyledCycleButton(parent, labelPrefix, width, height, options, getFunc, setFunc, tooltipText)
    return CreateStyledDropdown(parent, labelPrefix, width, height, options, getFunc, setFunc, tooltipText)
end

--[[-----------------------------------------------------------------------------
    Native Tab Builders for Quest Tracker
-------------------------------------------------------------------------------]]
local OUTLINE_OPTIONS = {
    { key = "OUTLINE",      label = "Outline" },
    { key = "THICKOUTLINE", label = "Thick Outline" },
    { key = "",             label = "None" },
}

local BORDER_STYLES = {
    { key = "flat",    label = "Flat (Sleek 1px)" },
    { key = "tooltip", label = "Blizzard Tooltip" },
    { key = "dialog",  label = "Blizzard Dialog" },
    { key = "none",    label = "None (Borderless)" },
}

local SORT_MODES = {
    { key = "level", label = "By Quest Level" },
    { key = "zone",  label = "By Current Zone" },
}

local DISTANCE_UNITS = {
    { key = "imperial", label = "Imperial (Yards)" },
    { key = "metric",   label = "Metric (Meters)" },
}

local ITEM_POSITIONS = {
    { key = "left",  label = "Left Margin" },
    { key = "right", label = "Right Margin" },
}

local GROW_CORNERS = {
    { key = "AUTO",        label = "Auto (Snap to Nearest Screen Corner)" },
    { key = "BOTTOMRIGHT", label = "Bottom-Right (Grows Up & Left)" },
    { key = "BOTTOMLEFT",  label = "Bottom-Left (Grows Up & Right)" },
    { key = "TOPRIGHT",    label = "Top-Right (Grows Down & Left)" },
    { key = "TOPLEFT",     label = "Top-Left (Grows Down & Right)" },
}

local XP_DOCK_MODES = {
    { key = "tracker_bottom", label = "Dock Tracker Bottom" },
    { key = "free",           label = "Free Floating" },
}

local LOC_DOCK_MODES = {
    { key = "tracker_top",  label = "Dock Tracker Top" },
    { key = "minimap_top",  label = "Dock Minimap Top" },
    { key = "free",         label = "Free Floating" },
}

local SOUND_CHANNELS = {
    { key = "Master",   label = "Master Channel" },
    { key = "SFX",      label = "Sound Effects (SFX)" },
    { key = "Ambience", label = "Ambience Channel" },
}

local COMPLETE_SOUNDS = {
    { key = "peon",           label = "Peon: \"Work complete!\"" },
    { key = "quest_complete", label = "Classic Quest Complete" },
    { key = "whisper_ping",   label = "Whisper Ping" },
    { key = "coins",          label = "Gold Coin Ding" },
    { key = "loot_clink",     label = "Loot Coin Clink" },
    { key = "level_up",       label = "Level Up Fanfare" },
    { key = "raid_warning",   label = "Raid Warning Chime" },
    { key = "ready_check",    label = "Ready Check Chime" },
    { key = "pvp_horn",       label = "PvP Queue Horn" },
    { key = "custom",         label = "Custom Sound Slot" },
}

local OBJECTIVE_SOUNDS = {
    { key = "whisper_ping", label = "Whisper Ping" },
    { key = "coins",        label = "Gold Coin Ding" },
    { key = "loot_clink",   label = "Loot Coin Clink" },
    { key = "map_ping",     label = "Mini-Map Ping" },
    { key = "item_click",   label = "Subtle Click" },
    { key = "custom",       label = "Custom Sound Slot" },
}

-- TAB 1: General Settings
local function BuildGeneralTab(content, syncList)
    local db = ns.db or {}
    local filterDb = db.filtering or {}

    local h1, d1 = CreateSectionHeader(content, "FRAME LOCK & SIZING", 12, 0)
    local cbLock = CreateStyledCheckbox(content, "Lock Tracker Frame (Shift-drag unlock)",
        "Locks the tracker frame in place. When unlocked, hold Shift + Left Click to drag anywhere on screen.",
        function() return db.isLocked == true end,
        function(v)
            db.isLocked = v
            if ns.Tracker and ns.Tracker.SetLocked then ns.Tracker:SetLocked(v) end
        end
    )
    table.insert(syncList, cbLock)

    local slScale = CreateStyledSlider(content, "BFQ_SlScale", "Tracker Scale:",
        "Adjusts overall tracker UI scale (50% - 150%).",
        0.5, 1.5, 0.05,
        function() return db.scale or 1.0 end,
        function(v) db.scale = v end,
        "%.2f"
    )
    table.insert(syncList, slScale)

    local slAlpha = CreateStyledSlider(content, "BFQ_SlAlpha", "Tracker Alpha:",
        "Adjusts overall tracker frame transparency.",
        0.2, 1.0, 0.05,
        function() return db.alpha or 1.0 end,
        function(v) db.alpha = v end,
        "%.2f"
    )
    table.insert(syncList, slAlpha)

    local slWidth = CreateStyledSlider(content, "BFQ_SlWidth", "Tracker Width (Pixels):",
        "Sets the horizontal pixel width of the quest tracker container.",
        180, 450, 5,
        function() return db.width or 280 end,
        function(v) db.width = v end,
        "%d px"
    )
    table.insert(syncList, slWidth)

    local slHeight = CreateStyledSlider(content, "BFQ_SlMaxHeight", "Max Height (Pixels):",
        "Sets maximum vertical height before the quest list begins clipping or scrolling.",
        200, 1200, 20,
        function() return db.maxHeight or 600 end,
        function(v) db.maxHeight = v end,
        "%d px"
    )
    table.insert(syncList, slHeight)

    local ddGrowCorner = CreateStyledDropdown(content, "Grow Anchor Corner", 190, 22, GROW_CORNERS,
        function() return db.growCorner or "AUTO" end,
        function(v)
            db.growCorner = v
            if ns.Tracker and ns.Tracker.UpdateAnchorCorner then
                ns.Tracker:UpdateAnchorCorner(v)
            end
        end,
        "Determines which screen corner the tracker anchors to and expands from. 'Auto' dynamically detects the nearest corner when dragged. Bottom-Right anchors to the bottom-right and grows upward and to the left as quests are added."
    )
    table.insert(syncList, ddGrowCorner)

    local h2, d2 = CreateSectionHeader(content, "VISIBILITY & COMBAT BEHAVIOR", 12, 0)
    local cbEmpty = CreateStyledCheckbox(content, "Auto-Hide When Empty",
        "Automatically hides the quest tracker backdrop when you have no active tracked quests.",
        function() return filterDb.autoHideEmpty == true end,
        function(v) filterDb.autoHideEmpty = v end
    )
    table.insert(syncList, cbEmpty)

    local cbInstance = CreateStyledCheckbox(content, "Auto-Hide Inside Instances",
        "Automatically conceals the quest tracker while inside dungeons, raids, or battlegrounds.",
        function() return filterDb.autoHideInInstances == true end,
        function(v) filterDb.autoHideInInstances = v end
    )
    table.insert(syncList, cbInstance)

    local cbCombatHide = CreateStyledCheckbox(content, "Hide Tracker In Combat",
        "Automatically hides the entire quest tracker frame during combat encounters.",
        function() return filterDb.hideInCombat == true end,
        function(v) filterDb.hideInCombat = v end
    )
    table.insert(syncList, cbCombatHide)

    local cbCombatCollapse = CreateStyledCheckbox(content, "Collapse Tracker In Combat",
        "Collapses quest objectives down to a compact single header bar while in combat.",
        function() return filterDb.collapseInCombat == true end,
        function(v) filterDb.collapseInCombat = v end
    )
    table.insert(syncList, cbCombatCollapse)

    local h3, d3 = CreateSectionHeader(content, "MODULE MANAGEMENT", 12, 0)
    local cbModWayfinder = CreateStyledCheckbox(content, "Wayfinder Navigation Module",
        "3D floating HUD waypoint arrow, inline tracker mini arrows, and distance readouts.",
        function() return ns.IsModuleEnabled("wayfinder") end,
        function(v) ns.SetModuleEnabled("wayfinder", v) end
    )
    table.insert(syncList, cbModWayfinder)

    local cbModDataBars = CreateStyledCheckbox(content, "DataBars Suite Module",
        "Standalone Experience / Reputation progress bar, Location & precision coordinates header bar, and timed quest bar.",
        function() return ns.IsModuleEnabled("databars") end,
        function(v) ns.SetModuleEnabled("databars", v) end
    )
    table.insert(syncList, cbModDataBars)

    local cbModQuestAuto = CreateStyledCheckbox(content, "Quest Automation Module",
        "Automated quest accepting, auto-sharing with party members, and smart turn-in completion.",
        function() return ns.IsModuleEnabled("questAutomation") end,
        function(v) ns.SetModuleEnabled("questAutomation", v) end
    )
    table.insert(syncList, cbModQuestAuto)

    local cbModQoL = CreateStyledCheckbox(content, "Quality of Life (QoL) Module",
        "Instant Fast Auto Loot, automatic grey/junk selling at vendors, and merchant equipment repair.",
        function() return ns.IsModuleEnabled("qol") end,
        function(v) ns.SetModuleEnabled("qol", v) end
    )
    table.insert(syncList, cbModQoL)

    local h4, d4 = CreateSectionHeader(content, "UTILITY & POSITION ACTIONS", 12, 0)
    local cbOverlay = CreateStyledCheckbox(content, "Show Bounds Overlay & Resize Handle",
        "Display the on-screen blue bounding box and [Drag to Resize] handle on the tracker.",
        function()
            return ns.Tracker and ns.Tracker.IsConfigOverlayShown and ns.Tracker:IsConfigOverlayShown()
        end,
        function(v)
            if ns.Tracker then
                if v then
                    if ns.Tracker.ShowConfigOverlay then ns.Tracker:ShowConfigOverlay() end
                else
                    if ns.Tracker.HideConfigOverlay then ns.Tracker:HideConfigOverlay() end
                end
            end
        end
    )
    table.insert(syncList, cbOverlay)

    local btnOnboard = CreateStyledButton(content, "Run Setup Walkthrough", 190, 22, function()
        if ns.Onboarding and ns.Onboarding.ShowWizard then
            ns.Onboarding:ShowWizard()
        end
    end, "Open the interactive first-time setup walkthrough modal (/bfq onboard).")

    local btnResetPos = CreateStyledButton(content, "Reset Tracker Position", 190, 22, function()
        if ns.Tracker and ns.Tracker.ResetPosition then
            ns.Tracker:ResetPosition()
        end
        if ns.Print then ns.Print("Tracker position reset to default.") end
    end, "Reset the tracker to the default screen position (top-right).")

    local btnResetUntracked = CreateStyledButton(content, "Reset Untracked Quests", 190, 22, function()
        if db.filtering then
            db.filtering.untrackedQuests = {}
        end
        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
        if ns.StandaloneTracker and ns.StandaloneTracker.RefreshQuests then
            ns.StandaloneTracker:RefreshQuests()
        end
        if ns.Print then ns.Print("Untracked quests restored.") end
    end, "Restores all quests that were hidden from the tracker using the right-click 'Untrack Quest' menu.")

    local function Layout(w)
        if not w or w < 100 then w = content:GetWidth() or 500 end
        local y = -10
        h1:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
        y = y - 30

        if w >= 470 then
            local colWidth = math.floor((w - 48) / 2)
            local col1X = 16
            local col2X = col1X + colWidth + 16

            cbLock:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbLock.Text:SetWidth(colWidth - 32)
            slScale:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            slScale:SetWidth(math.min(190, colWidth - 20))
            y = y - 48

            slAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slAlpha:SetWidth(math.min(190, colWidth - 20))
            slWidth:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            slWidth:SetWidth(math.min(190, colWidth - 20))
            y = y - 48

            slHeight:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slHeight:SetWidth(math.min(190, colWidth - 20))
            ddGrowCorner:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            ddGrowCorner:SetWidth(math.min(190, colWidth - 20))
            y = y - 48

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbEmpty:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbEmpty.Text:SetWidth(colWidth - 32)
            cbInstance:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbInstance.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbCombatHide:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCombatHide.Text:SetWidth(colWidth - 32)
            cbCombatCollapse:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbCombatCollapse.Text:SetWidth(colWidth - 32)
            y = y - 40

            h3:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbModWayfinder:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbModWayfinder.Text:SetWidth(colWidth - 32)
            cbModDataBars:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbModDataBars.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbModQuestAuto:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbModQuestAuto.Text:SetWidth(colWidth - 32)
            cbModQoL:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbModQoL.Text:SetWidth(colWidth - 32)
            y = y - 40

            h4:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbOverlay:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbOverlay.Text:SetWidth(colWidth - 32)
            btnOnboard:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnOnboard:SetWidth(math.min(190, colWidth - 20))
            y = y - 36

            btnResetPos:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetPos:SetWidth(math.min(190, colWidth - 20))
            btnResetUntracked:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnResetUntracked:SetWidth(math.min(190, colWidth - 20))
            y = y - 36
        else
            local colWidth = w - 36
            local col1X = 16

            cbLock:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbLock.Text:SetWidth(colWidth - 32)
            y = y - 32
            slScale:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slScale:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            slAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slAlpha:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            slWidth:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slWidth:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            slHeight:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slHeight:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            ddGrowCorner:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            ddGrowCorner:SetWidth(math.min(220, colWidth - 20))
            y = y - 46

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbEmpty:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbEmpty.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbInstance:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbInstance.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbCombatHide:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCombatHide.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbCombatCollapse:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCombatCollapse.Text:SetWidth(colWidth - 32)
            y = y - 38

            h3:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbModWayfinder:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbModWayfinder.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbModDataBars:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbModDataBars.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbModQuestAuto:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbModQuestAuto.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbModQoL:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbModQoL.Text:SetWidth(colWidth - 32)
            y = y - 38

            h4:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbOverlay:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbOverlay.Text:SetWidth(colWidth - 32)
            y = y - 32
            btnOnboard:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnOnboard:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnResetPos:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetPos:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnResetUntracked:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetUntracked:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
        end

        content:SetHeight(math.abs(y) + 20)
    end

    content.LayoutTab = Layout
    Layout(content:GetWidth())
end

-- TAB 2: Quests & Items
local function BuildQuestsTab(content, syncList)
    local db = ns.db or {}
    local itemDb = db.itemButtons or {}
    local headerDb = db.headers or {}
    local fontDb = db.fonts or {}
    local sortDb = db.sorting or {}
    local tipDb = db.tooltips or {}

    local h1, d1 = CreateSectionHeader(content, "QUEST ITEM ACTION BUTTONS", 12, 0)
    local cbItemBtn = CreateStyledCheckbox(content, "Enable Quest Item Buttons",
        "Renders clickable quest item shortcut buttons next to objectives (e.g. Hearthstone, quest items).",
        function() return itemDb.enabled ~= false end,
        function(v) itemDb.enabled = v end
    )
    table.insert(syncList, cbItemBtn)

    local slItemSize = CreateStyledSlider(content, "BFQ_SlItemSize", "Item Button Size:",
        "Pixel dimensions of quest item shortcut buttons (20 - 48px).",
        20, 48, 1,
        function() return itemDb.size or 26 end,
        function(v) itemDb.size = v end,
        "%d px"
    )
    table.insert(syncList, slItemSize)

    local cbItemAuto = CreateStyledCheckbox(content, "Auto-Detect Usable Quest Items",
        "Automatically identifies quest item bags and slots matching active quest requirements.",
        function() return itemDb.autoDetect ~= false end,
        function(v) itemDb.autoDetect = v end
    )
    table.insert(syncList, cbItemAuto)

    local btnItemPos = CreateStyledDropdown(content, "Item Docking", 190, 22, ITEM_POSITIONS,
        function() return itemDb.position or "left" end,
        function(v) itemDb.position = v end,
        "Dock quest item buttons on the left margin or right margin of the tracker."
    )
    table.insert(syncList, btnItemPos)

    local h2, d2 = CreateSectionHeader(content, "OBJECTIVES, BADGES & TOOLTIPS", 12, 0)
    local cbCompleteIcon = CreateStyledCheckbox(content, "Show Completed ? Checkmark Icon",
        "Shows a prominent gold question mark or checkmark when a quest is ready to turn in.",
        function() return headerDb.showCompleteIcon ~= false end,
        function(v) headerDb.showCompleteIcon = v end
    )
    table.insert(syncList, cbCompleteIcon)

    local cbDiffColor = CreateStyledCheckbox(content, "Color Quests by Difficulty Level",
        "Tints quest titles based on character level (Red = Impossible, Orange = Hard, Yellow = Normal, Green = Easy, Grey = Trivial).",
        function() return fontDb.colorDifficulty ~= false end,
        function(v) fontDb.colorDifficulty = v end
    )
    table.insert(syncList, cbDiffColor)

    local cbGroupTags = CreateStyledCheckbox(content, "Show Group & Elite Badges",
        "Displays elite, dungeon, and recommended player count tags ([11+], [Elite], [Dungeon]).",
        function() return sortDb.showGroupTags ~= false end,
        function(v) sortDb.showGroupTags = v end
    )
    table.insert(syncList, cbGroupTags)

    local cbRewards = CreateStyledCheckbox(content, "Show Quest Rewards in Tooltips",
        "Displays experience, copper/silver/gold rewards, and items upon hovering over a quest in the tracker.",
        function() return tipDb.showRewards ~= false end,
        function(v) tipDb.showRewards = v end
    )
    table.insert(syncList, cbRewards)

    local cbXpPct = CreateStyledCheckbox(content, "Show XP Reward Percentage",
        "Displays what percent of your current level will be granted by completing the quest.",
        function() return tipDb.showXpPercent ~= false end,
        function(v) tipDb.showXpPercent = v end
    )
    table.insert(syncList, cbXpPct)

    local cbUsableGear = CreateStyledCheckbox(content, "Highlight Usable Equipment Upgrades",
        "Highlights equipment rewards that match your character class and armor proficiencies.",
        function() return tipDb.showUsableGear ~= false end,
        function(v) tipDb.showUsableGear = v end
    )
    table.insert(syncList, cbUsableGear)

    local cbPartyStatus = CreateStyledCheckbox(content, "Show Party Members on Quest",
        "Shows which party members are currently on the quest when hovering over a quest in the tracker.",
        function() return tipDb.showPartyStatus ~= false end,
        function(v) tipDb.showPartyStatus = v end
    )
    table.insert(syncList, cbPartyStatus)

    local cbMissingParty = CreateStyledCheckbox(content, "Show Missing Party Members",
        "Displays group members who do not currently have the quest, noting if it can be shared with them.",
        function() return tipDb.showMissingParty ~= false end,
        function(v) tipDb.showMissingParty = v end
    )
    table.insert(syncList, cbMissingParty)

    local cbClassColorParty = CreateStyledCheckbox(content, "Class Color Party Names",
        "Formats party member names in tooltips using their character class colors.",
        function() return tipDb.classColorParty ~= false end,
        function(v) tipDb.classColorParty = v end
    )
    table.insert(syncList, cbClassColorParty)

    local cbPartyBadge = CreateStyledCheckbox(content, "Show Party Count Badge [P #]",
        "Appends a [P #] group count badge next to quest titles in the tracker when party members share the quest.",
        function() return tipDb.showPartyBadge == true end,
        function(v)
            tipDb.showPartyBadge = v
            if ns.FireCallback then ns:FireCallback("QUEST_DATA_CHANGED") end
        end
    )
    table.insert(syncList, cbPartyBadge)

    local h3, d3 = CreateSectionHeader(content, "ZONE EXPANSION ACTIONS", 12, 0)
    local btnExpandAll = CreateStyledButton(content, "Expand All Zones", 190, 22, function()
        if db then
            db.collapsedZones = {}
            if ns.FireCallback then ns:FireCallback("QUEST_DATA_CHANGED") end
        end
    end, "Expand all collapsible zone headers inside the tracker.")

    local btnCollapseAll = CreateStyledButton(content, "Collapse All Zones", 190, 22, function()
        if ns.StandaloneTracker and ns.StandaloneTracker.GetTrackedQuests then
            db.collapsedZones = db.collapsedZones or {}
            local quests = ns.StandaloneTracker:GetTrackedQuests()
            for _, q in ipairs(quests) do
                local z = q.zone or "Other Quests"
                db.collapsedZones[z] = true
            end
            if ns.FireCallback then ns:FireCallback("QUEST_DATA_CHANGED") end
        end
    end, "Collapse all zone headers down to compact single bars.")

    local function Layout(w)
        if not w or w < 100 then w = content:GetWidth() or 500 end
        local y = -10
        h1:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
        y = y - 30

        if w >= 470 then
            local colWidth = math.floor((w - 48) / 2)
            local col1X = 16
            local col2X = col1X + colWidth + 16

            cbItemBtn:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbItemBtn.Text:SetWidth(colWidth - 32)
            slItemSize:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            slItemSize:SetWidth(math.min(190, colWidth - 20))
            y = y - 48

            cbItemAuto:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbItemAuto.Text:SetWidth(colWidth - 32)
            btnItemPos:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnItemPos:SetWidth(math.min(190, colWidth - 20))
            y = y - 40

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbCompleteIcon:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCompleteIcon.Text:SetWidth(colWidth - 32)
            cbDiffColor:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbDiffColor.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbGroupTags:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbGroupTags.Text:SetWidth(colWidth - 32)
            cbPartyBadge:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbPartyBadge.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbRewards:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbRewards.Text:SetWidth(colWidth - 32)
            cbXpPct:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbXpPct.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbUsableGear:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbUsableGear.Text:SetWidth(colWidth - 32)
            cbPartyStatus:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbPartyStatus.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbMissingParty:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbMissingParty.Text:SetWidth(colWidth - 32)
            cbClassColorParty:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbClassColorParty.Text:SetWidth(colWidth - 32)
            y = y - 40

            h3:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            btnExpandAll:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnExpandAll:SetWidth(math.min(190, colWidth - 20))
            btnCollapseAll:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnCollapseAll:SetWidth(math.min(190, colWidth - 20))
            y = y - 36
        else
            local colWidth = w - 36
            local col1X = 16

            cbItemBtn:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbItemBtn.Text:SetWidth(colWidth - 32)
            y = y - 32
            slItemSize:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slItemSize:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            cbItemAuto:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbItemAuto.Text:SetWidth(colWidth - 32)
            y = y - 32
            btnItemPos:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnItemPos:SetWidth(math.min(220, colWidth - 20))
            y = y - 38

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbCompleteIcon:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCompleteIcon.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbDiffColor:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbDiffColor.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbGroupTags:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbGroupTags.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbPartyBadge:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbPartyBadge.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbRewards:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbRewards.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbXpPct:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbXpPct.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbUsableGear:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbUsableGear.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbPartyStatus:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbPartyStatus.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbMissingParty:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbMissingParty.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbClassColorParty:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbClassColorParty.Text:SetWidth(colWidth - 32)
            y = y - 38

            h3:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            btnExpandAll:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnExpandAll:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnCollapseAll:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnCollapseAll:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
        end

        content:SetHeight(math.abs(y) + 20)
    end

    content.LayoutTab = Layout
    Layout(content:GetWidth())
end

-- TAB 3: Colors & Fonts
local function BuildColorsTab(content, syncList)
    local db = ns.db or {}
    local bgDb = db.backdrop or {}
    local fontDb = db.fonts or {}

    local h1, d1 = CreateSectionHeader(content, "TRACKER BACKDROP & BORDER", 12, 0)
    local btnBorder = CreateStyledDropdown(content, "Border Style", 190, 22, BORDER_STYLES,
        function() return bgDb.borderStyle or "flat" end,
        function(v) bgDb.borderStyle = v end,
        "Choose between Flat 1px border, Blizzard Tooltip rounded corners, Dialog, or borderless."
    )
    table.insert(syncList, btnBorder)

    local cbClassBorder = CreateStyledCheckbox(content, "Class-Colored Tracker Border",
        "Tints the tracker frame border using your player character's class color.",
        function() return bgDb.classColorBorder == true end,
        function(v) bgDb.classColorBorder = v end
    )
    table.insert(syncList, cbClassBorder)

    local slBgAlpha = CreateStyledSlider(content, "BFQ_SlBgAlpha", "Background Opacity:",
        "Controls the dark backdrop fill opacity (0% - 100%).",
        0.0, 1.0, 0.05,
        function() return (bgDb.bgColor and bgDb.bgColor.a) or 0.65 end,
        function(v)
            bgDb.bgColor = bgDb.bgColor or { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
            bgDb.bgColor.a = v
        end,
        "%.2f"
    )
    table.insert(syncList, slBgAlpha)

    local slBorderAlpha = CreateStyledSlider(content, "BFQ_SlBorderAlpha", "Border Opacity:",
        "Controls the border opacity (0% - 100%).",
        0.0, 1.0, 0.05,
        function() return (bgDb.borderColor and bgDb.borderColor.a) or 0.90 end,
        function(v)
            bgDb.borderColor = bgDb.borderColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.90 }
            bgDb.borderColor.a = v
        end,
        "%.2f"
    )
    table.insert(syncList, slBorderAlpha)

    local h2, d2 = CreateSectionHeader(content, "TYPOGRAPHY & TEXT SIZES", 12, 0)

    local ddHeaderFont = CreateStyledFontDropdown(content, "Header Font", 190, 22,
        function() return fontDb.headerFont or fontDb.font or "Nata Sans Bold" end,
        function(v)
            fontDb.headerFont = v
            fontDb.font = v
            if ns.Tracker and ns.Tracker.UpdateTypography then ns.Tracker:UpdateTypography() end
        end,
        "Select the typography face for tracker headers, zone titles, and quest titles."
    )
    table.insert(syncList, ddHeaderFont)

    local ddHeaderOutline = CreateStyledDropdown(content, "Header Outline", 190, 22, OUTLINE_OPTIONS,
        function() return fontDb.headerOutline or "OUTLINE" end,
        function(v)
            fontDb.headerOutline = v
            if ns.Tracker and ns.Tracker.UpdateTypography then ns.Tracker:UpdateTypography() end
        end,
        "Select the font outline rendering style for headers and quest titles."
    )
    table.insert(syncList, ddHeaderOutline)

    local ddObjFont = CreateStyledFontDropdown(content, "Objective Font", 190, 22,
        function() return fontDb.objectiveFont or "Nata Sans Regular" end,
        function(v)
            fontDb.objectiveFont = v
            if ns.Tracker and ns.Tracker.UpdateTypography then ns.Tracker:UpdateTypography() end
        end,
        "Select the typography face for quest objectives, progress text, and descriptions."
    )
    table.insert(syncList, ddObjFont)

    local ddObjOutline = CreateStyledDropdown(content, "Objective Outline", 190, 22, OUTLINE_OPTIONS,
        function() return fontDb.objectiveOutline or "" end,
        function(v)
            fontDb.objectiveOutline = v
            if ns.Tracker and ns.Tracker.UpdateTypography then ns.Tracker:UpdateTypography() end
        end,
        "Select the font outline rendering style for objective lines."
    )
    table.insert(syncList, ddObjOutline)

    local slHeaderSize = CreateStyledSlider(content, "BFQ_SlHdrSize", "Header Font Size:",
        "Font size for quest title headers in the tracker (9 - 20 pt).",
        9, 20, 1,
        function() return fontDb.headerSize or 13 end,
        function(v) fontDb.headerSize = v end,
        "%d pt"
    )
    table.insert(syncList, slHeaderSize)

    local slObjSize = CreateStyledSlider(content, "BFQ_SlObjSize", "Objective Font Size:",
        "Font size for objective lines and progress counters (8 - 18 pt).",
        8, 18, 1,
        function() return fontDb.objectiveSize or 11 end,
        function(v) fontDb.objectiveSize = v end,
        "%d pt"
    )
    table.insert(syncList, slObjSize)

    local slZoneSize = CreateStyledSlider(content, "BFQ_SlZoneSize", "Zone Header Font Size:",
        "Font size for collapsible zone title headers (9 - 18 pt).",
        9, 18, 1,
        function() return fontDb.zoneHeaderSize or 12 end,
        function(v) fontDb.zoneHeaderSize = v end,
        "%d pt"
    )
    table.insert(syncList, slZoneSize)

    local cbShadow = CreateStyledCheckbox(content, "Enable Text Dropshadows",
        "Adds crisp dropshadows behind all tracker text for maximum readability.",
        function() return fontDb.enableTextShadow ~= false end,
        function(v) fontDb.enableTextShadow = v end
    )
    table.insert(syncList, cbShadow)

    local h3, d3 = CreateSectionHeader(content, "THEME PRESETS", 12, 0)
    local btnPresetGlass = CreateStyledButton(content, "Modern Dark Glass", 190, 22, function()
        if Config.ApplyModernGlassPreset then Config:ApplyModernGlassPreset() end
        if ns.Print then ns.Print("Applied Modern Dark Glass preset.") end
        for _, w in ipairs(syncList) do if w.Sync then w.Sync() end end
    end, "Modern dark glassmorphism preset with sleek flat 1px border and crisp white text.")

    local btnPresetClassic = CreateStyledButton(content, "Classic WoW Plus", 190, 22, function()
        if Config.ApplyClassicPreset then Config:ApplyClassicPreset() end
        if ns.Print then ns.Print("Applied Classic WoW Plus preset.") end
        for _, w in ipairs(syncList) do if w.Sync then w.Sync() end end
    end, "Classic World of Warcraft parchment tooltip border with gold headers and high contrast.")

    local btnPresetMinimal = CreateStyledButton(content, "Ultra Minimalist", 190, 22, function()
        if Config.ApplyMinimalPreset then Config:ApplyMinimalPreset() end
        if ns.Print then ns.Print("Applied Ultra Minimalist preset.") end
        for _, w in ipairs(syncList) do if w.Sync then w.Sync() end end
    end, "Borderless flat backdrop with compact typography for maximum screen space.")

    local h4, d4 = CreateSectionHeader(content, "RESET COLORS", 12, 0)
    local btnResetBg = CreateStyledButton(content, "Reset Background Color", 190, 22, function()
        if bgDb then
            if bgDb.bgTexture == "parchment" or bgDb.bgTexture == "parchment_clean" then
                bgDb.bgColor = { r = 0.96, g = 0.90, b = 0.78, a = 0.90 }
            else
                bgDb.bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
            end
        end
        if ns.Tracker and ns.Tracker.UpdateBackdrop then ns.Tracker:UpdateBackdrop() end
        for _, w in ipairs(syncList) do if w.Sync then w.Sync() end end
    end, "Reset tracker background color and opacity back to defaults.")

    local btnResetText = CreateStyledButton(content, "Reset Text to Class Color", 190, 22, function()
        if db.headers then db.headers.textColor = nil end
        if ns.Tracker and ns.Tracker.UpdateSettings then ns.Tracker:UpdateSettings() end
        for _, w in ipairs(syncList) do if w.Sync then w.Sync() end end
    end, "Reset header title text color back to your class color default.")

    local btnResetBtnColor = CreateStyledButton(content, "Reset Buttons to Class Color", 190, 22, function()
        if db.headers then db.headers.buttonColor = nil end
        if ns.Tracker and ns.Tracker.UpdateSettings then ns.Tracker:UpdateSettings() end
        for _, w in ipairs(syncList) do if w.Sync then w.Sync() end end
    end, "Reset header button tint back to your class color default.")

    local function Layout(w)
        if not w or w < 100 then w = content:GetWidth() or 500 end
        local y = -10
        h1:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
        y = y - 30

        if w >= 470 then
            local colWidth = math.floor((w - 48) / 2)
            local col1X = 16
            local col2X = col1X + colWidth + 16

            btnBorder:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnBorder:SetWidth(math.min(190, colWidth - 20))
            cbClassBorder:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbClassBorder.Text:SetWidth(colWidth - 32)
            y = y - 48

            slBgAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slBgAlpha:SetWidth(math.min(190, colWidth - 20))
            slBorderAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            slBorderAlpha:SetWidth(math.min(190, colWidth - 20))
            y = y - 48

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            ddHeaderFont:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            ddHeaderFont:SetWidth(math.min(190, colWidth - 20))
            ddHeaderOutline:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            ddHeaderOutline:SetWidth(math.min(190, colWidth - 20))
            y = y - 38

            slHeaderSize:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slHeaderSize:SetWidth(math.min(190, colWidth - 20))
            slZoneSize:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            slZoneSize:SetWidth(math.min(190, colWidth - 20))
            y = y - 48

            ddObjFont:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            ddObjFont:SetWidth(math.min(190, colWidth - 20))
            ddObjOutline:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            ddObjOutline:SetWidth(math.min(190, colWidth - 20))
            y = y - 38

            slObjSize:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slObjSize:SetWidth(math.min(190, colWidth - 20))
            cbShadow:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbShadow.Text:SetWidth(colWidth - 32)
            y = y - 48

            h3:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            btnPresetGlass:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPresetGlass:SetWidth(math.min(190, colWidth - 20))
            btnPresetClassic:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnPresetClassic:SetWidth(math.min(190, colWidth - 20))
            y = y - 36

            btnPresetMinimal:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPresetMinimal:SetWidth(math.min(190, colWidth - 20))
            y = y - 40

            h4:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            btnResetBg:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetBg:SetWidth(math.min(190, colWidth - 20))
            btnResetText:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnResetText:SetWidth(math.min(190, colWidth - 20))
            y = y - 36

            btnResetBtnColor:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetBtnColor:SetWidth(math.min(190, colWidth - 20))
            y = y - 36
        else
            local colWidth = w - 36
            local col1X = 16

            btnBorder:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnBorder:SetWidth(math.min(220, colWidth - 20))
            y = y - 38
            cbClassBorder:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbClassBorder.Text:SetWidth(colWidth - 32)
            y = y - 32
            slBgAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slBgAlpha:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            slBorderAlpha:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slBorderAlpha:SetWidth(math.min(220, colWidth - 20))
            y = y - 46

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            ddHeaderFont:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            ddHeaderFont:SetWidth(math.min(220, colWidth - 20))
            y = y - 38
            ddHeaderOutline:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            ddHeaderOutline:SetWidth(math.min(220, colWidth - 20))
            y = y - 38
            slHeaderSize:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slHeaderSize:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            slZoneSize:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slZoneSize:SetWidth(math.min(220, colWidth - 20))
            y = y - 46

            ddObjFont:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            ddObjFont:SetWidth(math.min(220, colWidth - 20))
            y = y - 38
            ddObjOutline:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            ddObjOutline:SetWidth(math.min(220, colWidth - 20))
            y = y - 38
            slObjSize:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slObjSize:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            cbShadow:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbShadow.Text:SetWidth(colWidth - 32)
            y = y - 38

            h3:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            btnPresetGlass:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPresetGlass:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnPresetClassic:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPresetClassic:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnPresetMinimal:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPresetMinimal:SetWidth(math.min(220, colWidth - 20))
            y = y - 38

            h4:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            btnResetBg:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetBg:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnResetText:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetText:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnResetBtnColor:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetBtnColor:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
        end

        content:SetHeight(math.abs(y) + 20)
    end

    content.LayoutTab = Layout
    Layout(content:GetWidth())
end

-- TAB 4: Headers & Filters
local function BuildHeadersTab(content, syncList)
    local db = ns.db or {}
    local headerDb = db.headers or {}
    local sortDb = db.sorting or {}

    local h1, d1 = CreateSectionHeader(content, "MAIN HEADER BAR BUTTONS", 12, 0)
    local cbLog = CreateStyledCheckbox(content, "Show [Log] Button",
        "Shows the [Log] button to instantly toggle Blizzard QuestLogFrame.",
        function() return headerDb.showQuestLogBtn ~= false end,
        function(v) headerDb.showQuestLogBtn = v end
    )
    table.insert(syncList, cbLog)

    local cbZone = CreateStyledCheckbox(content, "Show [Zone] Filter Button",
        "Shows the [Zone] button to filter tracker quests strictly to your current zone.",
        function() return headerDb.showZoneBtn ~= false end,
        function(v) headerDb.showZoneBtn = v end
    )
    table.insert(syncList, cbZone)

    local cbAll = CreateStyledCheckbox(content, "Show [All] Show-All Button",
        "Shows the [All] button to display all active quest log entries.",
        function() return headerDb.showAllBtn ~= false end,
        function(v) headerDb.showAllBtn = v end
    )
    table.insert(syncList, cbAll)

    local cbMenu = CreateStyledCheckbox(content, "Show [...] Options Menu Button",
        "Shows the [...] button to open options and quick settings.",
        function() return headerDb.showMenuBtn ~= false end,
        function(v) headerDb.showMenuBtn = v end
    )
    table.insert(syncList, cbMenu)

    local cbCollapse = CreateStyledCheckbox(content, "Show [-] Collapse Button",
        "Shows the [-] button to minimize or expand the tracker body.",
        function() return headerDb.showCollapseBtn ~= false end,
        function(v) headerDb.showCollapseBtn = v end
    )
    table.insert(syncList, cbCollapse)

    local h2, d2 = CreateSectionHeader(content, "ZONE GROUPING & SORTING", 12, 0)
    local cbZoneHeaders = CreateStyledCheckbox(content, "Group Quests Under Zone Headers",
        "Groups quests into collapsible zone header categories.",
        function() return headerDb.showZoneHeaders ~= false end,
        function(v) headerDb.showZoneHeaders = v end
    )
    table.insert(syncList, cbZoneHeaders)

    local cbZoneCount = CreateStyledCheckbox(content, "Show Zone Quest Counts",
        "Displays the active quest count next to each zone name (e.g. Westfall (3)).",
        function() return headerDb.showZoneCount ~= false end,
        function(v) headerDb.showZoneCount = v end
    )
    table.insert(syncList, cbZoneCount)

    local btnSort = CreateStyledDropdown(content, "Sorting Mode", 190, 22, SORT_MODES,
        function() return sortDb.mode or "level" end,
        function(v) sortDb.mode = v end,
        "Sort quests by quest level or group them by current zone."
    )
    table.insert(syncList, btnSort)

    local cbCompletedBottom = CreateStyledCheckbox(content, "Move Completed Quests to Bottom",
        "Pushes completed turn-in quests down to the bottom of the list.",
        function() return sortDb.moveCompletedToBottom == true end,
        function(v) sortDb.moveCompletedToBottom = v end
    )
    table.insert(syncList, cbCompletedBottom)

    local cbActiveTop = CreateStyledCheckbox(content, "Pin Active Quest (Star) to the Top",
        "Always pins your currently tracked/starred active quest at the very top.",
        function() return sortDb.activeOnTop ~= false end,
        function(v) sortDb.activeOnTop = v end
    )
    table.insert(syncList, cbActiveTop)

    local function Layout(w)
        if not w or w < 100 then w = content:GetWidth() or 500 end
        local y = -10
        h1:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
        y = y - 30

        if w >= 470 then
            local colWidth = math.floor((w - 48) / 2)
            local col1X = 16
            local col2X = col1X + colWidth + 16

            cbLog:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbLog.Text:SetWidth(colWidth - 32)
            cbZone:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbZone.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbAll:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAll.Text:SetWidth(colWidth - 32)
            cbMenu:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbMenu.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbCollapse:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCollapse.Text:SetWidth(colWidth - 32)
            y = y - 40

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbZoneHeaders:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbZoneHeaders.Text:SetWidth(colWidth - 32)
            cbZoneCount:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbZoneCount.Text:SetWidth(colWidth - 32)
            y = y - 34

            btnSort:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnSort:SetWidth(math.min(190, colWidth - 20))
            cbCompletedBottom:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbCompletedBottom.Text:SetWidth(colWidth - 32)
            y = y - 40

            cbActiveTop:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbActiveTop.Text:SetWidth(colWidth - 32)
            y = y - 34
        else
            local colWidth = w - 36
            local col1X = 16

            cbLog:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbLog.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbZone:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbZone.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbAll:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAll.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbMenu:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbMenu.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbCollapse:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCollapse.Text:SetWidth(colWidth - 32)
            y = y - 38

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbZoneHeaders:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbZoneHeaders.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbZoneCount:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbZoneCount.Text:SetWidth(colWidth - 32)
            y = y - 32
            btnSort:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnSort:SetWidth(math.min(220, colWidth - 20))
            y = y - 38
            cbCompletedBottom:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCompletedBottom.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbActiveTop:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbActiveTop.Text:SetWidth(colWidth - 32)
            y = y - 32
        end

        content:SetHeight(math.abs(y) + 20)
    end

    content.LayoutTab = Layout
    Layout(content:GetWidth())
end

-- TAB 5: Automation & QoL
local function BuildAutomationTab(content, syncList)
    local db = ns.db or {}
    local qolDb = db.qol or {}
    local socialDb = db.social or {}

    local h1, d1 = CreateSectionHeader(content, "QUEST & LOOT AUTOMATION", 12, 0)
    local cbFastLoot = CreateStyledCheckbox(content, "Fast Auto Loot (Instant Looting)",
        "Dramatically accelerates looting by instantly querying and collecting all loot window items simultaneously.",
        function() return qolDb.fastAutoLoot ~= false end,
        function(v) qolDb.fastAutoLoot = v end
    )
    table.insert(syncList, cbFastLoot)

    local cbAutoAcceptNPC = CreateStyledCheckbox(content, "Auto-Accept Quests from NPCs",
        "Automatically accepts quests offered by friendly questgiver NPCs.",
        function() return socialDb.autoAcceptNPC == true end,
        function(v) socialDb.autoAcceptNPC = v end
    )
    table.insert(syncList, cbAutoAcceptNPC)

    local cbAutoAcceptShared = CreateStyledCheckbox(content, "Auto-Accept Quests Shared by Party",
        "Automatically accepts quests shared by group or raid members.",
        function() return socialDb.autoAcceptShared == true end,
        function(v) socialDb.autoAcceptShared = v end
    )
    table.insert(syncList, cbAutoAcceptShared)

    local cbAutoTurnIn = CreateStyledCheckbox(content, "Auto-Turn In Quests (Single Reward)",
        "Automatically turns in completed quests when there is 0 or only 1 item reward choice.",
        function() return socialDb.autoTurnIn == true end,
        function(v) socialDb.autoTurnIn = v end
    )
    table.insert(syncList, cbAutoTurnIn)

    local cbShiftBypass = CreateStyledCheckbox(content, "Hold Shift to Temporarily Bypass",
        "Holding Shift disables automated loot and quest accept/turn-in while interacting.",
        function() return socialDb.shiftBypass ~= false end,
        function(v) socialDb.shiftBypass = v end
    )
    table.insert(syncList, cbShiftBypass)

    local cbAutoShare = CreateStyledCheckbox(content, "Auto-Share Quests with Party",
        "Automatically shares newly accepted quests with your party or raid members.",
        function() return db.questAutomation and db.questAutomation.autoShare == true end,
        function(v)
            db.questAutomation = db.questAutomation or {}
            db.questAutomation.autoShare = v
            if db.social then db.social.autoShare = v end
        end
    )
    table.insert(syncList, cbAutoShare)

    local h2, d2 = CreateSectionHeader(content, "MERCHANT & SOCIAL QOL", 12, 0)
    local cbSellJunk = CreateStyledCheckbox(content, "Auto-Sell Grey Junk Items at Vendors",
        "Automatically sells all low-quality grey items when opening vendor merchant frames.",
        function() return qolDb.autoSellJunk == true end,
        function(v) qolDb.autoSellJunk = v end
    )
    table.insert(syncList, cbSellJunk)

    local cbAutoRepair = CreateStyledCheckbox(content, "Auto-Repair Equipment at Vendors",
        "Automatically repairs all damaged gear and weapons when speaking with repair vendors.",
        function() return qolDb.autoRepair == true end,
        function(v) qolDb.autoRepair = v end
    )
    table.insert(syncList, cbAutoRepair)

    local cbGuildRepair = CreateStyledCheckbox(content, "Use Guild Bank for Repairs",
        "Attempt to use Guild Bank repair allowances if available, falling back to personal funds if unavailable.",
        function() return qolDb.useGuildRepair == true end,
        function(v) qolDb.useGuildRepair = v end
    )
    table.insert(syncList, cbGuildRepair)

    local cbMerchantShift = CreateStyledCheckbox(content, "Hold Shift to Bypass Vendor Auto-Sell/Repair",
        "Hold Shift while opening a merchant window to temporarily pause auto-selling and auto-repairing.",
        function() return qolDb.shiftBypass ~= false end,
        function(v) qolDb.shiftBypass = v end
    )
    table.insert(syncList, cbMerchantShift)

    local cbAnnouncePartyMaster = CreateStyledCheckbox(content, "Announce to Party Chat (Master Toggle)",
        "Master toggle to send quest milestone messages to party chat when grouped.",
        function() return socialDb.announceToParty == true end,
        function(v) socialDb.announceToParty = v end
    )
    table.insert(syncList, cbAnnouncePartyMaster)

    local cbAnnounceQuest = CreateStyledCheckbox(content, "Announce Full Quest Complete to Party",
        "Sends a friendly announcement to party chat when you complete all objectives for a quest.",
        function() return socialDb.announceQuestComplete ~= false end,
        function(v) socialDb.announceQuestComplete = v end
    )
    table.insert(syncList, cbAnnounceQuest)

    local cbAnnounceObj = CreateStyledCheckbox(content, "Announce Objective Complete to Party",
        "Announces individual objective completions (e.g. 8/8 Kobold Ears) to party chat.",
        function() return socialDb.announceObjectiveComplete ~= false end,
        function(v) socialDb.announceObjectiveComplete = v end
    )
    table.insert(syncList, cbAnnounceObj)

    local cbAnnounceObjProg = CreateStyledCheckbox(content, "Announce Objective Progress (N/X)",
        "Send incremental objective progress updates to party chat (e.g. Defias Traitors 5/15).",
        function() return socialDb.announceObjectiveProgress == true end,
        function(v) socialDb.announceObjectiveProgress = v end
    )
    table.insert(syncList, cbAnnounceObjProg)

    local function Layout(w)
        if not w or w < 100 then w = content:GetWidth() or 500 end
        local y = -10
        h1:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
        y = y - 30

        if w >= 470 then
            local colWidth = math.floor((w - 48) / 2)
            local col1X = 16
            local col2X = col1X + colWidth + 16

            cbFastLoot:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbFastLoot.Text:SetWidth(colWidth - 32)
            cbAutoAcceptNPC:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbAutoAcceptNPC.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbAutoAcceptShared:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAutoAcceptShared.Text:SetWidth(colWidth - 32)
            cbAutoTurnIn:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbAutoTurnIn.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbAutoShare:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAutoShare.Text:SetWidth(colWidth - 32)
            cbShiftBypass:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbShiftBypass.Text:SetWidth(colWidth - 32)
            y = y - 40

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbSellJunk:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbSellJunk.Text:SetWidth(colWidth - 32)
            cbAutoRepair:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbAutoRepair.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbGuildRepair:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbGuildRepair.Text:SetWidth(colWidth - 32)
            cbMerchantShift:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbMerchantShift.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbAnnouncePartyMaster:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAnnouncePartyMaster.Text:SetWidth(colWidth - 32)
            cbAnnounceQuest:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbAnnounceQuest.Text:SetWidth(colWidth - 32)
            y = y - 34

            cbAnnounceObj:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAnnounceObj.Text:SetWidth(colWidth - 32)
            cbAnnounceObjProg:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbAnnounceObjProg.Text:SetWidth(colWidth - 32)
            y = y - 34
        else
            local colWidth = w - 36
            local col1X = 16

            cbFastLoot:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbFastLoot.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbAutoAcceptNPC:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAutoAcceptNPC.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbAutoAcceptShared:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAutoAcceptShared.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbAutoTurnIn:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAutoTurnIn.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbAutoShare:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAutoShare.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbShiftBypass:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbShiftBypass.Text:SetWidth(colWidth - 32)
            y = y - 38

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbSellJunk:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbSellJunk.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbAutoRepair:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAutoRepair.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbGuildRepair:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbGuildRepair.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbMerchantShift:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbMerchantShift.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbAnnouncePartyMaster:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAnnouncePartyMaster.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbAnnounceQuest:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAnnounceQuest.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbAnnounceObj:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAnnounceObj.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbAnnounceObjProg:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbAnnounceObjProg.Text:SetWidth(colWidth - 32)
            y = y - 32
        end

        content:SetHeight(math.abs(y) + 20)
    end

    content.LayoutTab = Layout
    Layout(content:GetWidth())
end

-- TAB 6: Wayfinder & Audio
local function BuildWayfinderTab(content, syncList)
    local db = ns.db or {}
    local wfDb = db.wayfinder or {}
    local soundDb = db.sound or {}

    local h1, d1 = CreateSectionHeader(content, "WAYFINDER HUD NAVIGATION", 12, 0)
    local cbHUDArrow = CreateStyledCheckbox(content, "Enable Floating HUD Arrow",
        "Shows a floating navigation arrow pointing toward your active quest objective.",
        function() return wfDb.enableHUDArrow ~= false end,
        function(v) wfDb.enableHUDArrow = v end
    )
    table.insert(syncList, cbHUDArrow)

    local cbInlineArrow = CreateStyledCheckbox(content, "Enable Inline Tracker Arrow",
        "Shows a mini directional arrow directly inside the tracker next to each quest.",
        function() return wfDb.enableInlineArrow ~= false end,
        function(v) wfDb.enableInlineArrow = v end
    )
    table.insert(syncList, cbInlineArrow)

    local slArrowScale = CreateStyledSlider(content, "BFQ_SlWfScale", "HUD Arrow Scale:",
        "Scales the size of the floating HUD navigation arrow (60% - 160%).",
        0.6, 1.6, 0.05,
        function() return wfDb.arrowScale or 1.0 end,
        function(v) wfDb.arrowScale = v end,
        "%.2f"
    )
    table.insert(syncList, slArrowScale)

    local slInlineSize = CreateStyledSlider(content, "BFQ_SlWfInlineSize", "Inline Arrow Size:",
        "Pixel dimensions of mini arrows in the tracker (14 - 32px).",
        14, 32, 1,
        function() return wfDb.inlineArrowSize or 22 end,
        function(v) wfDb.inlineArrowSize = v end,
        "%d px"
    )
    table.insert(syncList, slInlineSize)

    local btnUnits = CreateStyledDropdown(content, "Distance Units", 190, 22, DISTANCE_UNITS,
        function() return wfDb.distanceUnit or "imperial" end,
        function(v) wfDb.distanceUnit = v end,
        "Choose Imperial yards/miles or Metric meters/kilometers for distance readouts."
    )
    table.insert(syncList, btnUnits)

    local cbArrivalSound = CreateStyledCheckbox(content, "Play Arrival Chime",
        "Plays an arrival sound effect when entering destination range.",
        function() return wfDb.playArrivalSound ~= false end,
        function(v) wfDb.playArrivalSound = v end
    )
    table.insert(syncList, cbArrivalSound)

    local cbHideCombat = CreateStyledCheckbox(content, "Hide Waypoint in Combat",
        "Hides waypoint arrows and distance readouts during combat.",
        function() return wfDb.hideInCombat ~= false end,
        function(v) wfDb.hideInCombat = v end
    )
    table.insert(syncList, cbHideCombat)

    local h1b, d1b = CreateSectionHeader(content, "WAYFINDER UTILITY ACTIONS", 12, 0)
    local btnPreviewArrow = CreateStyledButton(content, "Preview / Move Arrow", 190, 22, function()
        if ns.WayfinderModule and ns.WayfinderModule.TogglePreviewMode then
            ns.WayfinderModule:TogglePreviewMode()
        end
    end, "Temporarily toggle the HUD arrow on screen so you can test appearance and drag it to a new location.")

    local btnResetHUDPos = CreateStyledButton(content, "Reset Arrow Position", 190, 22, function()
        if ns.WayfinderModule and ns.WayfinderModule.hudFrame then
            ns.WayfinderModule.hudFrame:ClearAllPoints()
            ns.WayfinderModule.hudFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
            if db.wayfinder then
                db.wayfinder.hudPosition = { point = "CENTER", x = 0, y = 160 }
            end
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            if ns.Print then ns.Print("HUD arrow position reset.") end
        end
    end, "Reset the floating HUD arrow back to its default position above center screen.")

    local btnPointClosest = CreateStyledButton(content, "Point Closest (/cway)", 190, 22, function()
        if ns.WayfinderModule and ns.WayfinderModule.SetClosestWaypoint then
            ns.WayfinderModule:SetClosestWaypoint()
        end
    end, "Direct the HUD arrow to the closest active custom waypoint.")

    local btnClearWaypoints = CreateStyledButton(content, "Clear All Custom Waypoints", 190, 22, function()
        if ns.WayfinderModule and ns.WayfinderModule.ClearAllCustomWaypoints then
            ns.WayfinderModule:ClearAllCustomWaypoints()
        end
    end, "Remove all manually created custom waypoints.")

    local h2, d2 = CreateSectionHeader(content, "AUDIO & SOUND EFFECTS", 12, 0)
    local cbCompleteSound = CreateStyledCheckbox(content, "Play Sound on Quest Complete",
        "Plays an audio alert when you achieve 100% completion on a quest.",
        function() return soundDb.enableCompleteSound ~= false end,
        function(v) soundDb.enableCompleteSound = v end
    )
    table.insert(syncList, cbCompleteSound)

    local slCompleteVol = CreateStyledSlider(content, "BFQ_SlVolComplete", "Complete Sound Volume:",
        "Volume percentage for quest completion sounds.",
        10, 100, 5,
        function() return soundDb.completeSoundVolume or 100 end,
        function(v) soundDb.completeSoundVolume = v end,
        "%d%%"
    )
    table.insert(syncList, slCompleteVol)

    local btnCompleteSound = CreateStyledDropdown(content, "Complete Sound", 190, 22, COMPLETE_SOUNDS,
        function() return soundDb.soundChoice or "peon" end,
        function(v)
            soundDb.soundChoice = v
            soundDb.useCustomCompleteSound = (v == "custom")
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            if ns.SocialModule and ns.SocialModule.PlayPreviewSound then
                ns.SocialModule:PlayPreviewSound(v)
            end
        end,
        "Select which sound effect to play when a quest is ready for turn-in."
    )
    table.insert(syncList, btnCompleteSound)

    local btnCompleteChannel = CreateStyledDropdown(content, "Complete Channel", 190, 22, SOUND_CHANNELS,
        function() return soundDb.completeSoundChannel or "Master" end,
        function(v)
            soundDb.completeSoundChannel = v
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
        end,
        "Select audio channel for completion sound playback."
    )
    table.insert(syncList, btnCompleteChannel)

    local btnPreviewComplete = CreateStyledButton(content, "Preview Complete Sound", 190, 22, function()
        if ns.SocialModule and ns.SocialModule.PlayPreviewSound then
            local c = soundDb.soundChoice or "peon"
            local ch = soundDb.completeSoundChannel or "Master"
            local vol = soundDb.completeSoundVolume or 100
            ns.SocialModule:PlayPreviewSound(c, ch, vol)
        end
    end, "Play the currently selected quest completion sound effect at configured volume.")

    local cbObjSound = CreateStyledCheckbox(content, "Play Sound on Objective Update",
        "Plays a subtle chime whenever objective progress advances (e.g. 3/4).",
        function() return soundDb.enableObjectiveSound ~= false end,
        function(v) soundDb.enableObjectiveSound = v end
    )
    table.insert(syncList, cbObjSound)

    local slObjVol = CreateStyledSlider(content, "BFQ_SlVolObj", "Objective Sound Volume:",
        "Volume percentage for objective update sounds.",
        10, 100, 5,
        function() return soundDb.objectiveSoundVolume or 100 end,
        function(v) soundDb.objectiveSoundVolume = v end,
        "%d%%"
    )
    table.insert(syncList, slObjVol)

    local btnObjSound = CreateStyledDropdown(content, "Objective Sound", 190, 22, OBJECTIVE_SOUNDS,
        function() return soundDb.objectiveSoundChoice or "whisper_ping" end,
        function(v)
            soundDb.objectiveSoundChoice = v
            soundDb.useCustomObjectiveSound = (v == "custom")
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            if ns.SocialModule and ns.SocialModule.PlayPreviewObjectiveSound then
                ns.SocialModule:PlayPreviewObjectiveSound(v)
            end
        end,
        "Select which subtle sound effect to play when an objective progresses."
    )
    table.insert(syncList, btnObjSound)

    local btnObjChannel = CreateStyledDropdown(content, "Objective Channel", 190, 22, SOUND_CHANNELS,
        function() return soundDb.objectiveSoundChannel or "Master" end,
        function(v)
            soundDb.objectiveSoundChannel = v
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
        end,
        "Select audio channel for objective progress sound playback."
    )
    table.insert(syncList, btnObjChannel)

    local btnPreviewObj = CreateStyledButton(content, "Preview Objective Sound", 190, 22, function()
        if ns.SocialModule and ns.SocialModule.PlayPreviewObjectiveSound then
            local c = soundDb.objectiveSoundChoice or "whisper_ping"
            local ch = soundDb.objectiveSoundChannel or "Master"
            local vol = soundDb.objectiveSoundVolume or 100
            ns.SocialModule:PlayPreviewObjectiveSound(c, ch, vol)
        end
    end, "Play the currently selected objective progress sound effect at configured volume.")

    local function Layout(w)
        if not w or w < 100 then w = content:GetWidth() or 500 end
        local y = -10
        h1:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
        y = y - 30

        if w >= 470 then
            local colWidth = math.floor((w - 48) / 2)
            local col1X = 16
            local col2X = col1X + colWidth + 16

            cbHUDArrow:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbHUDArrow.Text:SetWidth(colWidth - 32)
            cbInlineArrow:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbInlineArrow.Text:SetWidth(colWidth - 32)
            y = y - 34

            slArrowScale:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slArrowScale:SetWidth(math.min(190, colWidth - 20))
            slInlineSize:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            slInlineSize:SetWidth(math.min(190, colWidth - 20))
            y = y - 48

            btnUnits:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnUnits:SetWidth(math.min(190, colWidth - 20))
            cbArrivalSound:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbArrivalSound.Text:SetWidth(colWidth - 32)
            y = y - 38

            cbHideCombat:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbHideCombat.Text:SetWidth(colWidth - 32)
            y = y - 40

            h1b:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            btnPreviewArrow:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPreviewArrow:SetWidth(math.min(190, colWidth - 20))
            btnResetHUDPos:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnResetHUDPos:SetWidth(math.min(190, colWidth - 20))
            y = y - 36

            btnPointClosest:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPointClosest:SetWidth(math.min(190, colWidth - 20))
            btnClearWaypoints:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnClearWaypoints:SetWidth(math.min(190, colWidth - 20))
            y = y - 40

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbCompleteSound:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCompleteSound.Text:SetWidth(colWidth - 32)
            slCompleteVol:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            slCompleteVol:SetWidth(math.min(190, colWidth - 20))
            y = y - 48

            btnCompleteSound:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnCompleteSound:SetWidth(math.min(190, colWidth - 20))
            btnCompleteChannel:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnCompleteChannel:SetWidth(math.min(190, colWidth - 20))
            y = y - 36

            btnPreviewComplete:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPreviewComplete:SetWidth(math.min(190, colWidth - 20))
            y = y - 40

            cbObjSound:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbObjSound.Text:SetWidth(colWidth - 32)
            slObjVol:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            slObjVol:SetWidth(math.min(190, colWidth - 20))
            y = y - 48

            btnObjSound:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnObjSound:SetWidth(math.min(190, colWidth - 20))
            btnObjChannel:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnObjChannel:SetWidth(math.min(190, colWidth - 20))
            y = y - 36

            btnPreviewObj:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPreviewObj:SetWidth(math.min(190, colWidth - 20))
            y = y - 36
        else
            local colWidth = w - 36
            local col1X = 16

            cbHUDArrow:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbHUDArrow.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbInlineArrow:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbInlineArrow.Text:SetWidth(colWidth - 32)
            y = y - 32
            slArrowScale:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slArrowScale:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            slInlineSize:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slInlineSize:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            btnUnits:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnUnits:SetWidth(math.min(220, colWidth - 20))
            y = y - 38
            cbArrivalSound:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbArrivalSound.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbHideCombat:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbHideCombat.Text:SetWidth(colWidth - 32)
            y = y - 38

            h1b:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            btnPreviewArrow:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPreviewArrow:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnResetHUDPos:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetHUDPos:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnPointClosest:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPointClosest:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnClearWaypoints:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnClearWaypoints:SetWidth(math.min(220, colWidth - 20))
            y = y - 38

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbCompleteSound:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCompleteSound.Text:SetWidth(colWidth - 32)
            y = y - 32
            slCompleteVol:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slCompleteVol:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            btnCompleteSound:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnCompleteSound:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnCompleteChannel:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnCompleteChannel:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnPreviewComplete:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPreviewComplete:SetWidth(math.min(220, colWidth - 20))
            y = y - 38

            cbObjSound:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbObjSound.Text:SetWidth(colWidth - 32)
            y = y - 32
            slObjVol:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slObjVol:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            btnObjSound:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnObjSound:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnObjChannel:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnObjChannel:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnPreviewObj:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPreviewObj:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
        end

        content:SetHeight(math.abs(y) + 20)
    end

    content.LayoutTab = Layout
    Layout(content:GetWidth())
end

-- TAB 7: DataBars
local function BuildDataBarsTab(content, syncList)
    local db = ns.db or {}
    local dataDb = db.databars or {}

    local h1, d1 = CreateSectionHeader(content, "EXPERIENCE & QUEST LOG PROGRESS BAR", 12, 0)
    local cbXPBar = CreateStyledCheckbox(content, "Enable Standalone XP DataBar",
        "Renders a customizable experience and completed quest turn-in progress bar.",
        function() return dataDb.enableXPBar == true end,
        function(v) dataDb.enableXPBar = v end
    )
    table.insert(syncList, cbXPBar)

    local btnXPDock = CreateStyledDropdown(content, "XP Dock Mode", 190, 22, XP_DOCK_MODES,
        function() return dataDb.xpDockMode or "tracker_bottom" end,
        function(v) dataDb.xpDockMode = v end,
        "Dock experience bar directly underneath the tracker or unlock for free movement."
    )
    table.insert(syncList, btnXPDock)

    local slXPHeight = CreateStyledSlider(content, "BFQ_SlXpHeight", "XP Bar Height:",
        "Pixel height of the experience bar (8 - 32px).",
        8, 32, 1,
        function() return dataDb.xpHeight or 14 end,
        function(v) dataDb.xpHeight = v end,
        "%d px"
    )
    table.insert(syncList, slXPHeight)

    local cbQuestXP = CreateStyledCheckbox(content, "Show Completed Turn-in Ghost Bar",
        "Overlays anticipated experience from completed turn-in quests onto the XP bar.",
        function() return dataDb.showCompletedQuestXP ~= false end,
        function(v) dataDb.showCompletedQuestXP = v end
    )
    table.insert(syncList, cbQuestXP)

    local cbDingReady = CreateStyledCheckbox(content, "Show [Ding Ready!] Alert",
        "Displays [Ding Ready!] in glowing gold when completed quests provide enough XP to level.",
        function() return dataDb.showDingReadyText ~= false end,
        function(v) dataDb.showDingReadyText = v end
    )
    table.insert(syncList, cbDingReady)

    local cbRestedXP = CreateStyledCheckbox(content, "Show Rested XP Bonus Segment",
        "Renders rested experience bonus segment in blue.",
        function() return dataDb.showRestedXP ~= false end,
        function(v) dataDb.showRestedXP = v end
    )
    table.insert(syncList, cbRestedXP)

    local h2, d2 = CreateSectionHeader(content, "LOCATION & COORDINATES HEADER BAR", 12, 0)
    local cbLocBar = CreateStyledCheckbox(content, "Enable Location & Coordinates Bar",
        "Renders a precision zone, subzone, and coordinates bar.",
        function() return dataDb.enableLocationBar == true end,
        function(v) dataDb.enableLocationBar = v end
    )
    table.insert(syncList, cbLocBar)

    local btnLocDock = CreateStyledDropdown(content, "Loc Dock Mode", 190, 22, LOC_DOCK_MODES,
        function() return dataDb.locDockMode or "tracker_top" end,
        function(v) dataDb.locDockMode = v end,
        "Dock location bar above tracker, above minimap, or unlock for free movement."
    )
    table.insert(syncList, btnLocDock)

    local cbCoords = CreateStyledCheckbox(content, "Show Precision Coordinates",
        "Displays player map coordinates (e.g. 45.2, 58.6) on the location bar.",
        function() return dataDb.showCoords ~= false end,
        function(v) dataDb.showCoords = v end
    )
    table.insert(syncList, cbCoords)

    local cbTerritory = CreateStyledCheckbox(content, "Color by PvP Territory Status",
        "Colors zone and subzone names by PvP status (Sanctuary, Friendly, Contested, Hostile).",
        function() return dataDb.colorTerritory ~= false end,
        function(v) dataDb.colorTerritory = v end
    )
    table.insert(syncList, cbTerritory)

    local btnResetXPPos = CreateStyledButton(content, "Reset Free XP Position", 190, 22, function()
        if dataDb then dataDb.xpFreePosition = nil end
        if ns.DataBarsModule and ns.DataBarsModule.UpdateXPDocking then ns.DataBarsModule:UpdateXPDocking() end
        if ns.Print then ns.Print("XP Bar position reset.") end
    end, "Reset the free floating XP bar back to its default position.")

    local btnResetXPColors = CreateStyledButton(content, "Reset XP Colors", 190, 22, function()
        if dataDb then
            dataDb.xpBgColor = { r = 0.00, g = 0.00, b = 0.00, a = 0.00 }
            dataDb.xpColor = { r = 0.58, g = 0.00, b = 0.83, a = 1.00 }
            dataDb.restedColor = { r = 0.00, g = 0.44, b = 0.88, a = 1.00 }
            dataDb.questXPColor = { r = 0.25, g = 0.85, b = 0.45, a = 0.65 }
            dataDb.allQuestXPColor = { r = 0.12, g = 0.45, b = 0.25, a = 0.80 }
            dataDb.dingReadyColor = { r = 1.00, g = 0.82, b = 0.00, a = 1.00 }
        end
        if ns.DataBarsModule and ns.DataBarsModule.UpdateXPBar then ns.DataBarsModule:UpdateXPBar() end
        if ns.Print then ns.Print("XP Bar colors reset to defaults.") end
    end, "Reset all XP bar colors back to defaults.")

    local btnResetLocPos = CreateStyledButton(content, "Reset Free Loc Position", 190, 22, function()
        if dataDb then dataDb.locFreePosition = nil end
        if ns.DataBarsModule and ns.DataBarsModule.UpdateLocDocking then ns.DataBarsModule:UpdateLocDocking() end
        if ns.Print then ns.Print("Location Bar position reset.") end
    end, "Reset the free floating Location Bar back to its default position.")

    local h3, d3 = CreateSectionHeader(content, "QUEST TIMER BAR & DOCKING", 12, 0)
    local btnPreviewTimer = CreateStyledButton(content, "Preview / Move Timer Bar", 190, 22, function()
        if ns.DataBarsModule then
            ns.DataBarsModule.timerPreviewMode = not ns.DataBarsModule.timerPreviewMode
            if ns.DataBarsModule.RefreshBars then ns.DataBarsModule:RefreshBars() end
        end
    end, "Temporarily toggle preview mode for the Quest Timer Bar so you can adjust its position.")

    local btnResetTimerPos = CreateStyledButton(content, "Reset Timer Bar Position", 190, 22, function()
        if dataDb then dataDb.timerFreePosition = nil end
        if ns.DataBarsModule and ns.DataBarsModule.UpdateTimerDocking then ns.DataBarsModule:UpdateTimerDocking() end
        if ns.Print then ns.Print("Timer Bar position reset.") end
    end, "Reset the free floating Timer Bar back to its default position.")

    local function Layout(w)
        if not w or w < 100 then w = content:GetWidth() or 500 end
        local y = -10
        h1:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
        y = y - 30

        if w >= 470 then
            local colWidth = math.floor((w - 48) / 2)
            local col1X = 16
            local col2X = col1X + colWidth + 16

            cbXPBar:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbXPBar.Text:SetWidth(colWidth - 32)
            btnXPDock:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnXPDock:SetWidth(math.min(190, colWidth - 20))
            y = y - 40

            slXPHeight:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slXPHeight:SetWidth(math.min(190, colWidth - 20))
            cbQuestXP:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbQuestXP.Text:SetWidth(colWidth - 32)
            y = y - 48

            cbDingReady:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbDingReady.Text:SetWidth(colWidth - 32)
            cbRestedXP:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbRestedXP.Text:SetWidth(colWidth - 32)
            y = y - 34

            btnResetXPPos:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetXPPos:SetWidth(math.min(190, colWidth - 20))
            btnResetXPColors:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnResetXPColors:SetWidth(math.min(190, colWidth - 20))
            y = y - 40

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbLocBar:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbLocBar.Text:SetWidth(colWidth - 32)
            btnLocDock:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnLocDock:SetWidth(math.min(190, colWidth - 20))
            y = y - 40

            cbCoords:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCoords.Text:SetWidth(colWidth - 32)
            cbTerritory:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            cbTerritory.Text:SetWidth(colWidth - 32)
            y = y - 34

            btnResetLocPos:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetLocPos:SetWidth(math.min(190, colWidth - 20))
            y = y - 40

            h3:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            btnPreviewTimer:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPreviewTimer:SetWidth(math.min(190, colWidth - 20))
            btnResetTimerPos:SetPoint("TOPLEFT", content, "TOPLEFT", col2X, y)
            btnResetTimerPos:SetWidth(math.min(190, colWidth - 20))
            y = y - 36
        else
            local colWidth = w - 36
            local col1X = 16

            cbXPBar:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbXPBar.Text:SetWidth(colWidth - 32)
            y = y - 32
            btnXPDock:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnXPDock:SetWidth(math.min(220, colWidth - 20))
            y = y - 38
            slXPHeight:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            slXPHeight:SetWidth(math.min(220, colWidth - 20))
            y = y - 46
            cbQuestXP:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbQuestXP.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbDingReady:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbDingReady.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbRestedXP:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbRestedXP.Text:SetWidth(colWidth - 32)
            y = y - 34
            btnResetXPPos:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetXPPos:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnResetXPColors:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetXPColors:SetWidth(math.min(220, colWidth - 20))
            y = y - 38

            h2:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            cbLocBar:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbLocBar.Text:SetWidth(colWidth - 32)
            y = y - 32
            btnLocDock:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnLocDock:SetWidth(math.min(220, colWidth - 20))
            y = y - 38
            cbCoords:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbCoords.Text:SetWidth(colWidth - 32)
            y = y - 32
            cbTerritory:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            cbTerritory.Text:SetWidth(colWidth - 32)
            y = y - 34
            btnResetLocPos:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetLocPos:SetWidth(math.min(220, colWidth - 20))
            y = y - 38

            h3:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
            y = y - 30

            btnPreviewTimer:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnPreviewTimer:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
            btnResetTimerPos:SetPoint("TOPLEFT", content, "TOPLEFT", col1X, y)
            btnResetTimerPos:SetWidth(math.min(220, colWidth - 20))
            y = y - 36
        end

        content:SetHeight(math.abs(y) + 20)
    end

    content.LayoutTab = Layout
    Layout(content:GetWidth())
end

-- TAB 8: Profiles
local function BuildProfilesTab(content, syncList)
    local h1, d1 = CreateSectionHeader(content, "PROFILE MANAGEMENT", 12, 0)

    local lblCurrent = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblCurrent:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -42)
    local function UpdateCurrent()
        local cur = (ns.dbObject and ns.dbObject.GetCurrentProfile and ns.dbObject:GetCurrentProfile()) or "Default"
        lblCurrent:SetText("Active Profile: |cFFFFD100" .. cur .. "|r")
    end
    UpdateCurrent()

    local btnReset = CreateStyledButton(content, "Reset to Defaults", 160, 24, function()
        if ns.dbObject and ns.dbObject.ResetProfile then
            ns.dbObject:ResetProfile()
            if ns.Tracker and ns.Tracker.UpdateSettings then ns.Tracker:UpdateSettings() end
            if ns.Print then ns.Print("Active profile reset to defaults.") end
            UpdateCurrent()
        end
    end, "Resets all quest tracker settings in the active profile back to defaults.")

    local function Layout(w)
        if not w or w < 100 then w = content:GetWidth() or 500 end
        local y = -10
        h1:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
        y = y - 34

        lblCurrent:ClearAllPoints()
        lblCurrent:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
        y = y - 30

        btnReset:ClearAllPoints()
        btnReset:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
        y = y - 40

        content:SetHeight(math.abs(y) + 20)
    end

    content.LayoutTab = Layout
    Layout(content:GetWidth())
end

--[[-----------------------------------------------------------------------------
    Master Native Options Panel for Quest Tracker
-------------------------------------------------------------------------------]]
function Config:BuildNativeOptions(containerFrame, isMasterHub)
    if not containerFrame then return end

    if not self.initialized then
        self:InitializeOptions()
    end

    if containerFrame.nativeOptionsBuilt then
        if containerFrame.SyncAll then containerFrame.SyncAll() end
        return containerFrame
    end

    local tabs = {
        { id = "general",    label = "General",        builder = BuildGeneralTab },
        { id = "quests",     label = "Quests & Items", builder = BuildQuestsTab },
        { id = "appearance", label = "Colors & Fonts", builder = BuildColorsTab },
        { id = "headers",    label = "Headers & Sort", builder = BuildHeadersTab },
        { id = "automation", label = "Automation",     builder = BuildAutomationTab },
        { id = "wayfinder",  label = "Wayfinder/Audio",builder = BuildWayfinderTab },
        { id = "databars",   label = "DataBars",       builder = BuildDataBarsTab },
        { id = "profiles",   label = "Profiles",       builder = BuildProfilesTab },
    }

    local tabBar = CreateFrame("Frame", nil, containerFrame)
    tabBar:SetHeight(28)
    tabBar:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", containerFrame, "TOPRIGHT", 0, 0)

    local insetBox = CreateFrame("Frame", nil, containerFrame, BACKDROP_TEMPLATE)
    insetBox:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -4)
    insetBox:SetPoint("BOTTOMRIGHT", containerFrame, "BOTTOMRIGHT", -4, 4)
    insetBox:SetBackdrop(INSET_BACKDROP)
    insetBox:SetBackdropColor(unpack(COLORS.contentBg))
    insetBox:SetBackdropBorderColor(unpack(COLORS.goldMuted))

    local tabButtons = {}
    local tabScrolls = {}
    local syncLists = {}
    local tabChildren = {}

    local function SelectTab(tabID)
        for _, t in ipairs(tabs) do
            local btn = tabButtons[t.id]
            local scroll = tabScrolls[t.id]
            if t.id == tabID then
                if btn then
                    btn:SetBackdropColor(unpack(COLORS.tabActive))
                    btn:SetBackdropBorderColor(unpack(COLORS.goldBorder))
                    btn.label:SetTextColor(COLORS.goldText[1], COLORS.goldText[2], COLORS.goldText[3])
                end
                if scroll then
                    scroll:Show()
                    local child = tabChildren[t.id]
                    if child and child.LayoutTab then
                        child.LayoutTab(scroll:GetWidth() - 24)
                    end
                    if syncLists[t.id] then
                        for _, w in ipairs(syncLists[t.id]) do
                            if w.Sync then w:Sync() end
                        end
                    end
                end
            else
                if btn then
                    btn:SetBackdropColor(unpack(COLORS.tabNormal))
                    btn:SetBackdropBorderColor(unpack(COLORS.goldMuted))
                    btn.label:SetTextColor(COLORS.whiteText[1], COLORS.whiteText[2], COLORS.whiteText[3])
                end
                if scroll then scroll:Hide() end
            end
        end
    end

    local function LayoutTabBar(w)
        if not w or w < 100 then w = containerFrame:GetWidth() or 540 end
        local gap = 4

        if w >= 620 then
            -- 1 Row
            tabBar:SetHeight(28)
            local btnW = math.floor((w - ((#tabs - 1) * gap)) / #tabs)
            if btnW > 92 then btnW = 92 end
            local curX = 0
            for _, t in ipairs(tabs) do
                local b = tabButtons[t.id]
                if b then
                    b:SetSize(btnW, 24)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", tabBar, "TOPLEFT", curX, 0)
                end
                curX = curX + btnW + gap
            end
        else
            -- 2 Rows (Line break to prevent cramping)
            tabBar:SetHeight(52)
            local row1Count = 4
            local btnW1 = math.floor((w - ((row1Count - 1) * gap)) / row1Count)
            local curX = 0
            for i = 1, row1Count do
                local t = tabs[i]
                local b = tabButtons[t.id]
                if b then
                    b:SetSize(btnW1, 22)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", tabBar, "TOPLEFT", curX, 0)
                end
                curX = curX + btnW1 + gap
            end
            local row2Count = #tabs - row1Count
            local btnW2 = math.floor((w - ((row2Count - 1) * gap)) / row2Count)
            curX = 0
            for i = row1Count + 1, #tabs do
                local t = tabs[i]
                local b = tabButtons[t.id]
                if b then
                    b:SetSize(btnW2, 22)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", tabBar, "TOPLEFT", curX, -26)
                end
                curX = curX + btnW2 + gap
            end
        end
    end

    for _, t in ipairs(tabs) do
        local tID = t.id
        local btn = CreateFrame("Button", nil, tabBar, BACKDROP_TEMPLATE)
        btn:SetSize(72, 24)
        btn:SetBackdrop(INSET_BACKDROP)
        btn:SetBackdropColor(unpack(COLORS.tabNormal))
        btn:SetBackdropBorderColor(unpack(COLORS.goldMuted))

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER", btn, "CENTER", 0, 0)
        lbl:SetText(t.label)
        btn.label = lbl

        btn:SetScript("OnClick", function() SelectTab(tID) end)
        tabButtons[tID] = btn

        -- ScrollFrame for this tab inside insetBox
        local scroll = CreateFrame("ScrollFrame", "BFQ_Scroll_" .. tID, insetBox, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", insetBox, "TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", insetBox, "BOTTOMRIGHT", -26, 6)

        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(500, 500)
        scroll:SetScrollChild(child)

        local updateScroll = SetupAutoScroll(scroll, child)

        local sList = {}
        syncLists[tID] = sList
        t.builder(child, sList)
        tabChildren[tID] = child

        scroll:HookScript("OnSizeChanged", function(self, sw)
            if sw and sw > 60 and child.LayoutTab then
                child.LayoutTab(sw - 24)
                if updateScroll then updateScroll() end
            end
        end)

        scroll:Hide()
        tabScrolls[tID] = scroll
    end

    local function SyncAll()
        for _, sList in pairs(syncLists) do
            for _, widget in ipairs(sList) do
                if widget.Sync then widget:Sync() end
            end
        end
    end
    containerFrame.SyncAll = SyncAll

    containerFrame:HookScript("OnSizeChanged", function(self, w)
        if w and w > 60 then
            LayoutTabBar(w)
        end
    end)

    LayoutTabBar(containerFrame:GetWidth())
    SelectTab("general")
    SyncAll()

    containerFrame.nativeOptionsBuilt = true
    return containerFrame
end

function Config:EmbedOptionsIntoContainer(containerFrame)
    if not containerFrame then return end
    return Config:BuildNativeOptions(containerFrame, true)
end

function Config:GetOrCreateStandaloneFrame()
    if self.standaloneFrame then return self.standaloneFrame end

    local db = (ns.db and ns.db.configWindow) or {}
    local width = db.width or 820
    local height = db.height or 580
    local point = db.point or "CENTER"
    local relPoint = db.relativePoint or "CENTER"
    local xOfs = db.xOfs or 0
    local yOfs = db.yOfs or 0

    local f = CreateFrame("Frame", "BleakfibersStandaloneConfigFrame", UIParent, BACKDROP_TEMPLATE)
    f:Hide()
    f:SetSize(width, height)
    f:SetPoint(point, UIParent, relPoint, xOfs, yOfs)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)

    tinsert(UISpecialFrames, "BleakfibersStandaloneConfigFrame")

    if f.SetResizeBounds then
        f:SetResizeBounds(640, 420, 1200, 850)
    else
        f:SetMinResize(640, 420)
        f:SetMaxResize(1200, 850)
    end

    f:SetBackdrop(MAIN_WINDOW_BACKDROP)
    f:SetBackdropColor(unpack(COLORS.bgSlate))
    f:SetBackdropBorderColor(unpack(COLORS.goldBorder))

    -- Title Bar Area (Draggable)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -6)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")

    titleBar:SetScript("OnDragStart", function()
        f:StartMoving()
    end)

    titleBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local pt, _, relPt, x, y = f:GetPoint()
        if ns.db then
            ns.db.configWindow = ns.db.configWindow or {}
            ns.db.configWindow.point = pt
            ns.db.configWindow.relativePoint = relPt or pt
            ns.db.configWindow.xOfs = math.floor(x + 0.5)
            ns.db.configWindow.yOfs = math.floor(y + 0.5)
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
        end
    end)

    -- Title Icon / Emblem
    local titleIcon = titleBar:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(18, 18)
    titleIcon:SetPoint("LEFT", titleBar, "LEFT", 6, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_07")
    titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Title Text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    titleText:SetText("|cFFFFD100Bleakfiber's Quest Tracker|r  |cFF8899A6Forever|r")

    -- Version Subtitle
    local versionText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    versionText:SetPoint("LEFT", titleText, "RIGHT", 8, -1)
    versionText:SetText("v" .. (ns.version or "1.0.18"))

    -- Title Bar Action Buttons
    local refreshBtn = CreateStyledButton(titleBar, "Refresh", 65, 20, function()
        if ns.Tracker and ns.Tracker.UpdateSettings then ns.Tracker:UpdateSettings() end
        if f.contentPane and f.contentPane.SyncAll then f.contentPane.SyncAll() end
        if ns.Print then ns.Print("Quest Tracker settings refreshed.") end
    end, "Reapplies all visual settings and refreshes quest tracker.")
    refreshBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)

    local btnMovers = CreateStyledButton(titleBar, "Toggle Movers", 95, 20, function()
        if ns.Tracker and ns.Tracker.SetLocked then
            local locked = ns.db and ns.db.isLocked
            ns.Tracker:SetLocked(not locked)
            if ns.Print then
                ns.Print(string.format("Quest Tracker %s.", (not locked) and "|cFFFF0000Locked|r" or "|cFF00FF00Unlocked|r"))
            end
        end
    end, "Unlocks or locks quest tracker anchor for click-and-drag repositioning.")
    btnMovers:SetPoint("RIGHT", refreshBtn, "LEFT", -6, 0)

    -- Gold Divider below Title Bar
    local titleDivider = f:CreateTexture(nil, "ARTWORK")
    titleDivider:SetHeight(1)
    titleDivider:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -36)
    titleDivider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -36)
    titleDivider:SetColorTexture(COLORS.goldBorder[1], COLORS.goldBorder[2], COLORS.goldBorder[3], 0.6)

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    -- Bottom-right Resize Grip
    local resizeGrip = CreateFrame("Button", nil, f)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    resizeGrip:EnableMouse(true)

    local gripTex = resizeGrip:CreateTexture(nil, "ARTWORK")
    gripTex:SetAllPoints(resizeGrip)
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

    resizeGrip:SetScript("OnEnter", function()
        gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    end)
    resizeGrip:SetScript("OnLeave", function()
        gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    end)
    resizeGrip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if ns.db then
            ns.db.configWindow = ns.db.configWindow or {}
            ns.db.configWindow.width = math.floor(f:GetWidth() + 0.5)
            ns.db.configWindow.height = math.floor(f:GetHeight() + 0.5)
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
        end
    end)

    -- Footer hint text
    local footerText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    footerText:SetText("|cFF667788Use /bfq or /bqt to toggle this window|r")

    -- Content Pane (Houses the full options tabs)
    local contentPane = CreateFrame("Frame", nil, f, BACKDROP_TEMPLATE)
    contentPane:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -42)
    contentPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 24)
    contentPane:SetBackdrop(INSET_BACKDROP)
    contentPane:SetBackdropColor(unpack(COLORS.contentBg))
    contentPane:SetBackdropBorderColor(unpack(COLORS.goldMuted))
    f.contentPane = contentPane

    f:SetScript("OnShow", function()
        if not self.initialized then
            self:InitializeOptions()
        end
        if ns.SetupColorPickerEnhancements then
            ns.SetupColorPickerEnhancements()
        end
        Config:EmbedOptionsIntoContainer(contentPane)
    end)

    f:SetScript("OnHide", function()
        if ns.Tracker and ns.Tracker.HideConfigOverlay then
            ns.Tracker:HideConfigOverlay()
        end
    end)

    self.standaloneFrame = f
    return f
end

function Config:ToggleConfigFrame()
    if not self.standaloneFrame then
        local f = self:GetOrCreateStandaloneFrame()
        f:Show()
        return
    end
    if self.standaloneFrame:IsShown() then
        self.standaloneFrame:Hide()
    else
        self.standaloneFrame:Show()
    end
end

local PublicAPI = ns.PublicAPI or _G["BleakfibersQuestTrackerForever"]

function PublicAPI:BuildMasterConfigUI(parentContainer)
    if not parentContainer then return end
    local content = parentContainer.content or parentContainer
    Config:EmbedOptionsIntoContainer(content)
end

-- Slash Command Handler
local function HandleSlashCommands(msg)
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")

    if command == "lock" then
        ns.Tracker:SetLocked(true)
    elseif command == "unlock" then
        ns.Tracker:SetLocked(false)
    elseif command == "reset" then
        if ns.Tracker and ns.Tracker.ResetPosition then
            ns.Tracker:ResetPosition()
        end
        if ns.db then
            ns.db.itemButtonPosition = nil
        end
        if ns.StandaloneTracker and ns.StandaloneTracker.UpdateItemButton then
            ns.StandaloneTracker:UpdateItemButton()
        end
        if ns.FlushDBToGlobals then
            ns.FlushDBToGlobals()
        end
        ns.Print("Position reset to default.")
    elseif command == "toggle" then
        ns.Tracker:ToggleCollapse()
    elseif command == "profile" then
        if rest and rest ~= "" then
            if ns.dbObject and ns.dbObject.SetProfile then
                ns.dbObject:SetProfile(rest)
                ns.Print("Switched profile to: |cff00ff00" .. rest .. "|r")
            end
        else
            local currentProfile = (ns.dbObject and ns.dbObject.GetCurrentProfile and ns.dbObject:GetCurrentProfile()) or "Default"
            ns.Print("Active Profile: |cff00ff00" .. currentProfile .. "|r. Use |cff00c0ff/bfq profile <name>|r to switch.")
        end
    elseif command == "pos" or command == "position" then
        local frame = ns.Tracker and ns.Tracker:GetFrame()
        local db = (ns.dbObject and ns.dbObject.profile) or ns.db
        local prof = (ns.dbObject and ns.dbObject.GetCurrentProfile and ns.dbObject:GetCurrentProfile()) or "none"
        ns.Print("--- Tracker Position Debug ---")
        local pos = db and db.framePosition
        if pos then
            ns.Print(string.format("Saved in DB: %s relative to %s at (%d, %d)", tostring(pos.point), tostring(pos.relativePoint), pos.x or 0, pos.y or 0))
        else
            ns.Print("Saved in DB: default (TOPRIGHT, farthest right, 35px below minimap)")
        end
        if frame then
            ns.Print(string.format("Live Frame: left=%.1f, top=%.1f, scale=%.2f, isUserPlaced=%s", frame:GetLeft() or -1, frame:GetTop() or -1, frame:GetScale() or 1, tostring(frame:IsUserPlaced())))
        else
            ns.Print("Live Frame: nil!")
        end
    elseif command == "debug" then
        ns.debugMode = not ns.debugMode
        if ns.debugMode then
            ns.Print("Debug messages |cff00ff00ENABLED|r.")
        else
            ns.Print("Debug messages |cffff3333DISABLED|r.")
        end
    elseif command == "sharetest" or command == "testshare" then
        ns.Print("--- Quest Share Pipeline Diagnostic (Retail/Midnight API) ---")
        local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
            or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0

        local foundQuests = 0
        local firstPushableID = nil
        local firstPushableIndex = nil
        local firstPushableTitle = nil

        for i = 1, numEntries do
            local title, questID, isHeader
            if C_QuestLog and C_QuestLog.GetInfo then
                local info = C_QuestLog.GetInfo(i)
                if info then
                    title = info.title
                    questID = info.questID
                    isHeader = info.isHeader
                end
            elseif GetQuestLogTitle then
                local t, _, _, h, _, _, _, id = GetQuestLogTitle(i)
                title, questID, isHeader = t, id, h
            end

            if not isHeader and questID and questID > 0 then
                foundQuests = foundQuests + 1

                -- 1. Select the quest
                if C_QuestLog and C_QuestLog.SetSelectedQuest then
                    C_QuestLog.SetSelectedQuest(questID)
                end
                if SelectQuestLogEntry then
                    SelectQuestLogEntry(i)
                end

                -- 2. Check pushability
                local cPush = (C_QuestLog and C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questID))
                local gPush = (GetQuestLogPushable and GetQuestLogPushable())
                local isPushable = cPush or (gPush and true or false)

                local statusText = isPushable and "|cff00ff00YES (Shareable)|r" or "|cffff4444NO (Solo-only)|r"
                ns.Print(string.format("  [%d] '%s' (ID: %d) -> %s", foundQuests, title or "Quest", questID, statusText))

                if isPushable and not firstPushableID then
                    firstPushableID = questID
                    firstPushableIndex = i
                    firstPushableTitle = title
                end
            end
        end

        if foundQuests == 0 then
            ns.Print("No active quests found in quest log.")
        elseif firstPushableID then
            ns.Print(string.format("Executing live share test on: '%s' (ID: %d, index: %d)...", firstPushableTitle or "Quest", firstPushableID, firstPushableIndex or 0))
            if C_QuestLog and C_QuestLog.SetSelectedQuest then
                C_QuestLog.SetSelectedQuest(firstPushableID)
            end
            if SelectQuestLogEntry and firstPushableIndex then
                SelectQuestLogEntry(firstPushableIndex)
            end
            if C_QuestLog and C_QuestLog.ShareQuest then
                C_QuestLog.ShareQuest(firstPushableID)
                ns.Print("Called C_QuestLog.ShareQuest(" .. firstPushableID .. "). If solo, Blizzard will print 'You are not in a party.'")
            elseif QuestLogPushQuest then
                QuestLogPushQuest()
                ns.Print("Called QuestLogPushQuest(). If solo, Blizzard will print 'You are not in a party.'")
            end
        else
            ns.Print("None of your current quests are flagged as shareable by Blizzard.")
        end
    elseif command == "poi" or command == "testzone" or command == "crosszone" then
        local pZone = (GetZoneText and GetZoneText()) or "Unknown"
        local pReal = (GetRealZoneText and GetRealZoneText()) or "Unknown"
        local pSub = (GetSubZoneText and GetSubZoneText()) or ""
        local pMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local mapInfo = pMapID and C_Map.GetMapInfo and C_Map.GetMapInfo(pMapID)
        local mapName = (mapInfo and mapInfo.name) or "nil"

        print(string.format("|cff00c0ff[BFQ Cross-Zone Diagnostics]|r Player Location:"))
        print(string.format("  Zone: |cffffff00%s|r | Real: |cffffff00%s|r | Sub: |cffffff00%s|r", pZone, pReal, pSub ~= "" and pSub or "none"))
        print(string.format("  MapID: |cffffff00%s|r (%s) | MapType: |cffffff00%s|r", tostring(pMapID), mapName, tostring(mapInfo and mapInfo.mapType)))

        local numEntries = (ns.GetNumQuestLogEntries and select(1, ns.GetNumQuestLogEntries())) or (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries())) or 0
        local curHeader = "General"
        local count = 0

        for i = 1, numEntries do
            local title, isH, isComplete, questID
            if C_QuestLog and C_QuestLog.GetInfo then
                local info = C_QuestLog.GetInfo(i)
                if info then
                    title = info.title
                    isH = info.isHeader
                    isComplete = info.isComplete
                    questID = info.questID
                end
            end
            if not title and GetQuestLogTitle then
                local t, _, _, h, _, c, _, q = GetQuestLogTitle(i)
                title, isH, isComplete, questID = t, h, c, q
            end

            if isH then
                curHeader = title or "General"
            elseif title and questID then
                count = count + 1
                local poiMap = (C_QuestLog and C_QuestLog.GetMapForQuestPOIs and C_QuestLog.GetMapForQuestPOIs(questID))
                local poiMapName = "none"
                if poiMap and poiMap > 0 and C_Map and C_Map.GetMapInfo then
                    local pInfo = C_Map.GetMapInfo(poiMap)
                    poiMapName = (pInfo and pInfo.name) or tostring(poiMap)
                end

                local poiCount = 0
                local poiMapsList = {}
                if C_QuestLog and C_QuestLog.GetQuestPOIs then
                    local pois = C_QuestLog.GetQuestPOIs(questID)
                    if pois and type(pois) == "table" then
                        poiCount = #pois
                        for _, p in ipairs(pois) do
                            if p and p.mapID then
                                table.insert(poiMapsList, tostring(p.mapID))
                            end
                        end
                    end
                end

                local completeStr = (isComplete == 1 or isComplete == true) and "|cff00ff00[Turn-in]|r" or "|cffffcc00[Incomplete]|r"
                print(string.format("  |cff00e5ff[%d]|r %s %s", questID, title, completeStr))
                print(string.format("     Header: |cffffff00%s|r | POIMap: |cffffff00%s|r (%s)", curHeader, tostring(poiMap), poiMapName))
                if poiCount > 0 then
                    print(string.format("     Points: %d | POI MapIDs: [%s]", poiCount, table.concat(poiMapsList, ", ")))
                end
            end
        end
        if count == 0 then
            print("  No quests found in quest log.")
        end
    elseif command == "onboard" or command == "onboarding" then
        if ns.Onboarding and ns.Onboarding.ShowWizard then
            ns.Onboarding:ShowWizard()
        end
    elseif command == "standalone" then
        Config:ToggleConfigFrame()
    elseif command == "config" or command == "options" or command == "" then
        if BleakfibersAddonConfigForever and BleakfibersAddonConfigForever.OpenToModule and not IsShiftKeyDown() then
            BleakfibersAddonConfigForever:OpenToModule("BleakfibersQuestTracker")
        else
            Config:ToggleConfigFrame()
        end
    else
        print("|cff00c0ffBleakfiber's Quest Tracker Commands:|r")
        print("  |cff00ff00/bfq|r or |cff00ff00/bqt|r - Open configuration panel")
        print("  |cff00ff00/bfq standalone|r - Force open standalone settings panel")
        print("  |cff00ff00/bfq onboard|r - Open interactive setup walkthrough")
        print("  |cff00ff00/bfq poi|r - Inspect live quest objective and turn-in map coordinates")
        print("  |cff00ff00/bfq lock|r - Lock tracker position")
        print("  |cff00ff00/bfq unlock|r - Unlock tracker position")
        print("  |cff00ff00/bfq toggle|r - Expand or collapse tracker")
        print("  |cff00ff00/bfq reset|r - Reset tracker position to default")
        print("  |cff00ff00/bfq pos|r - View live position and saved coordinates debug info")
        print("  |cff00ff00/bfq profile [name]|r - View or switch active profile")
        print("  |cff00ff00/bfq sharetest|r - Test quest share pipeline and pushability")
        print("  |cff00ff00/bfq debug|r - Toggle debug log messages")
    end
end

SLASH_BLEAKFIBERQUESTTRACKER1 = "/bfq"
SLASH_BLEAKFIBERQUESTTRACKER2 = "/bleaktracker"
SLASH_BLEAKFIBERQUESTTRACKER3 = "/bqt"
SlashCmdList["BLEAKFIBERQUESTTRACKER"] = HandleSlashCommands

ns:RegisterCallback("ON_INITIALIZE", function()
    Config:InitializeOptions()
end)

