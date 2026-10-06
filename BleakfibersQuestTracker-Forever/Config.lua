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
                            ["pointer"] = "Cyan Pointer (►)",
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

function Config:EmbedOptionsIntoContainer(containerFrame)
    if not containerFrame then return end

    if not self.initialized then
        self:InitializeOptions()
    end

    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not (AceGUI and ACD) then return end

    local aceContainer = containerFrame.aceContainer
    if not aceContainer then
        aceContainer = AceGUI:Create("SimpleGroup")
        aceContainer.frame:SetParent(containerFrame)
        aceContainer.frame:ClearAllPoints()
        aceContainer.frame:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 0, 0)
        aceContainer.frame:SetPoint("BOTTOMRIGHT", containerFrame, "BOTTOMRIGHT", 0, 0)
        aceContainer:SetLayout("Fill")
        aceContainer.frame:Show()
        containerFrame.aceContainer = aceContainer

        containerFrame:HookScript("OnSizeChanged", function(self, w, h)
            if self.aceContainer and self.aceContainer.frame:IsShown() then
                self.aceContainer:SetWidth(w)
                self.aceContainer:SetHeight(h)
                self.aceContainer:DoLayout()
            end
        end)
    end

    ACD:Open("BleakfiberQuestTracker", aceContainer)
    if aceContainer.DoLayout then
        aceContainer:DoLayout()
    end
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
    versionText:SetText("v" .. (ns.version or "1.0.16"))

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
    local f = self:GetOrCreateStandaloneFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
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

