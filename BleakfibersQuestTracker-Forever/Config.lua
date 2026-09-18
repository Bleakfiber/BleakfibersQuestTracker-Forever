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

    local currentMode = db.filtering.filterMode or (db.filtering.zoneOnly and "zone" or "all")

    local rows = {
        { type = "title", text = "|cff00c0ffTracker Options|r" },
        { type = "sep" },
        { type = "header", text = "Filter Quests" },
        {
            type = "radio",
            text = "All Quests",
            checked = (currentMode == "all"),
            onClick = function()
                db.filtering.filterMode = "all"
                db.filtering.zoneOnly = false
                if ns.Tracker and ns.Tracker.UpdateFilterButtons then
                    ns.Tracker:UpdateFilterButtons()
                end
                ns:FireCallback("QUEST_DATA_CHANGED")
            end,
        },
        {
            type = "radio",
            text = "Current Zone Only",
            checked = (currentMode == "zone"),
            onClick = function()
                db.filtering.filterMode = "zone"
                db.filtering.zoneOnly = true
                if ns.Tracker and ns.Tracker.UpdateFilterButtons then
                    ns.Tracker:UpdateFilterButtons()
                end
                ns:FireCallback("QUEST_DATA_CHANGED")
            end,
        },
        {
            type = "radio",
            text = "Watched Only (Shift-Click)",
            checked = (currentMode == "watched"),
            onClick = function()
                db.filtering.filterMode = "watched"
                db.filtering.zoneOnly = false
                if ns.Tracker and ns.Tracker.UpdateFilterButtons then
                    ns.Tracker:UpdateFilterButtons()
                end
                ns:FireCallback("QUEST_DATA_CHANGED")
            end,
        },
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
        text = "Completed to Bottom",
        checked = db.sorting and db.sorting.moveCompletedToBottom,
        onClick = function()
            db.sorting = db.sorting or {}
            db.sorting.moveCompletedToBottom = not db.sorting.moveCompletedToBottom
            ns:FireCallback("QUEST_DATA_CHANGED")
        end,
    })

    table.insert(rows, { type = "sep" })
    table.insert(rows, { type = "header", text = "Party & Group" })
    table.insert(rows, {
        type = "checkbox",
        text = "Party Quest Sync",
        checked = db.social and db.social.enablePartySync,
        onClick = function()
            db.social = db.social or {}
            db.social.enablePartySync = not db.social.enablePartySync
            ns:FireCallback("QUEST_DATA_CHANGED")
        end,
    })
    table.insert(rows, {
        type = "checkbox",
        text = "Announce to Party",
        checked = db.social and db.social.announceToParty,
        onClick = function()
            db.social = db.social or {}
            db.social.announceToParty = not db.social.announceToParty
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
            item:SetScript("OnClick", row.onClick)
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
                            ns.Tracker:SetLocked(val)
                        end,
                    },
                    autoHideEmpty = {
                        name = "Auto-hide Tracker When Empty",
                        desc = "Automatically hide the tracker frame when no quests are being tracked.",
                        type = "toggle",
                        order = 2,
                        get = function() return db.filtering.autoHideEmpty end,
                        set = function(_, val)
                            db.filtering.autoHideEmpty = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    autoHideInInstances = {
                        name = "Auto-collapse in Dungeons & Raids",
                        desc = "Automatically collapse/minimize the tracker inside party dungeons and raid instances.",
                        type = "toggle",
                        order = 3,
                        get = function() return db.filtering.autoHideInInstances end,
                        set = function(_, val)
                            db.filtering.autoHideInInstances = val
                            ns.Tracker:CheckInstanceAutoCollapse()
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
                            return db.filtering.filterMode or (db.filtering.zoneOnly and "zone" or "all")
                        end,
                        set = function(_, val)
                            db.filtering.filterMode = val
                            db.filtering.zoneOnly = (val == "zone")
                            if ns.Tracker and ns.Tracker.UpdateFilterButtons then
                                ns.Tracker:UpdateFilterButtons()
                            end
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    sep = {
                        name = "",
                        type = "header",
                        order = 5,
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
                },
            },
            sizing = {
                name = "Position & Sizing",
                type = "group",
                order = 2,
                args = {
                    desc = {
                        name = "Configure pixel width, scale, and dynamic auto-grow range. Use sliders or type numeric px values directly.\n",
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
                        order = 2,
                        get = function() return db.maxHeight or 600 end,
                        set = function(_, val)
                            db.maxHeight = math.floor(val + 0.5)
                            ns.Tracker:UpdateSettings()
                        end,
                    },
                    showOverlay = {
                        name = "Show Bounds Overlay",
                        desc = "Display the on-screen blue bounding box and [Drag to Resize] handle on the tracker.",
                        type = "toggle",
                        order = 3,
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
                    scale = {
                        name = "Tracker UI Scale",
                        desc = "Adjust overall visual scale of the tracker frame.",
                        type = "range",
                        min = 0.7,
                        max = 1.5,
                        step = 0.05,
                        isPercent = true,
                        order = 4,
                        get = function() return db.scale or 1.0 end,
                        set = function(_, val)
                            db.scale = tonumber(string.format("%.2f", val))
                            ns.Tracker:UpdateSettings()
                        end,
                    },
                    sizingNote = {
                        name = "|cff00ff00Auto-Growth Active:|r Content dynamically auto-resizes the tracker frame, only capping and scrolling when content exceeds the Grow Down Range.",
                        type = "description",
                        order = 5,
                    },
                },
            },
            fonts = {
                name = "Fonts & Typography",
                type = "group",
                order = 3,
                args = {
                    desc = {
                        name = "Customize font family (via SharedMedia), title and objective sizes, and text outlines.\n",
                        type = "description",
                        order = 0,
                    },
                    font = {
                        name = "Font Family",
                        desc = "Select the font typeface for quest titles, objectives, and headers.",
                        type = "select",
                        dialogControl = "LSM30_Font",
                        values = fontList,
                        order = 1,
                        get = function()
                            return db.fonts.font or db.fonts.headerFont or "Friz Quadrata TT"
                        end,
                        set = function(_, val)
                            db.fonts.font = val
                            db.fonts.headerFont = val
                            db.fonts.objectiveFont = val
                            ns.Tracker:UpdateTypography()
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
                        name = "Font Outline",
                        desc = "Select the outline style applied to tracker fonts.",
                        type = "select",
                        values = fontFlags,
                        order = 4,
                        get = function() return db.fonts.headerOutline or "OUTLINE" end,
                        set = function(_, val)
                            db.fonts.headerOutline = val
                            db.fonts.objectiveOutline = val
                            ns.Tracker:UpdateTypography()
                        end,
                    },
                    colorDifficulty = {
                        name = "Color Quest Titles by Difficulty",
                        desc = "Color quest titles according to your character level (Red/Orange/Yellow/Green/Gray).",
                        type = "toggle",
                        order = 5,
                        get = function() return db.fonts.colorDifficulty ~= false end,
                        set = function(_, val)
                            db.fonts.colorDifficulty = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                },
            },
            appearance = {
                name = "Appearance",
                type = "group",
                order = 4,
                args = {
                    desc = {
                        name = "Configure tracker backdrop visibility, background color/opacity, and border.\n",
                        type = "description",
                        order = 0,
                    },
                    showBackdrop = {
                        name = "Show Background & Border",
                        desc = "Toggle tracker background and border visibility.",
                        type = "toggle",
                        order = 1,
                        get = function() return db.backdrop.show end,
                        set = function(_, val)
                            db.backdrop.show = val
                            ns.Tracker:UpdateBackdrop()
                        end,
                    },
                    bgColor = {
                        name = "Background Color & Opacity",
                        desc = "Set tracker background color and opacity.",
                        type = "color",
                        hasAlpha = true,
                        order = 2,
                        get = function()
                            local c = db.backdrop.bgColor or { r = 0.05, g = 0.05, b = 0.05, a = 0.65 }
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            db.backdrop.bgColor = { r = r, g = g, b = b, a = a }
                            ns.Tracker:UpdateBackdrop()
                        end,
                    },
                    borderColor = {
                        name = "Border Color",
                        desc = "Set tracker border color and opacity.",
                        type = "color",
                        hasAlpha = true,
                        order = 3,
                        get = function()
                            local c = db.backdrop.borderColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.9 }
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            db.backdrop.borderColor = { r = r, g = g, b = b, a = a }
                            ns.Tracker:UpdateBackdrop()
                        end,
                    },
                },
            },
            headers = {
                name = "Headers",
                type = "group",
                order = 5,
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
                                end,
                            },
                        },
                    },
                },
            },
            sorting = {
                name = "Sorting",
                type = "group",
                order = 6,
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
                    moveCompletedToBottom = {
                        name = "Move Completed Quests to Bottom",
                        desc = "Place quests that are ready for turn-in at the bottom of the tracker so active objectives remain visible at the top.",
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
            social = {
                name = "Social & Automation",
                type = "group",
                order = 7,
                args = {
                    desc = {
                        name = "Configure party sharing, quest auto-accept, single-choice auto turn-in, and audio alerts.\n",
                        type = "description",
                        order = 0,
                    },
                    headerAuto = {
                        name = "Quest Automation",
                        type = "header",
                        order = 1,
                    },
                    autoShare = {
                        name = "Auto-Share Quests",
                        desc = "Automatically share newly accepted quests with party members when grouped.",
                        type = "toggle",
                        width = "full",
                        order = 2,
                        get = function() return db.social and db.social.autoShare end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.autoShare = val
                        end,
                    },
                    autoAcceptNPC = {
                        name = "Auto-Accept NPC Quests",
                        desc = "Automatically accept quests offered by NPCs.",
                        type = "toggle",
                        width = "full",
                        order = 3,
                        get = function() return db.social and db.social.autoAcceptNPC end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.autoAcceptNPC = val
                        end,
                    },
                    autoAcceptShared = {
                        name = "Auto-Accept Shared Quests",
                        desc = "Automatically accept quests shared by party members.",
                        type = "toggle",
                        width = "full",
                        order = 4,
                        get = function() return db.social and db.social.autoAcceptShared end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.autoAcceptShared = val
                        end,
                    },
                    autoTurnIn = {
                        name = "Auto Turn-In Quests (1 or Less Choice)",
                        desc = "Automatically complete and turn in quests when ready. Only applies to quests with 1 or 0 reward choices (quests with multiple reward items pause so you can choose your gear upgrade).",
                        type = "toggle",
                        width = "full",
                        order = 5,
                        get = function() return db.social and db.social.autoTurnIn end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.autoTurnIn = val
                        end,
                    },
                    shiftBypass = {
                        name = "Shift-Key Bypass",
                        desc = "Holding Shift while interacting with an NPC temporarily pauses auto-accept and auto-turnin so you can read quest text or decline.",
                        type = "toggle",
                        width = "full",
                        order = 6,
                        get = function() return db.social and db.social.shiftBypass ~= false end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.shiftBypass = val
                        end,
                    },
                    enablePartySync = {
                        name = "Party Quest Progress Sync",
                        desc = "Synchronize quest objective progress with party members in real-time and show click-to-share buttons when teammates lack a quest.",
                        type = "toggle",
                        width = "full",
                        order = 7,
                        get = function() return db.social and db.social.enablePartySync end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.enablePartySync = val
                            ns:FireCallback("QUEST_DATA_CHANGED")
                        end,
                    },
                    announceToParty = {
                        name = "Announce to Party Chat",
                        desc = "Send clean milestone messages to party chat when an objective finishes or a quest is ready for turn-in.",
                        type = "toggle",
                        width = "full",
                        order = 8,
                        get = function() return db.social and db.social.announceToParty end,
                        set = function(_, val)
                            db.social = db.social or {}
                            db.social.announceToParty = val
                        end,
                    },
                    headerSound = {
                        name = "Audio Alerts",
                        type = "header",
                        order = 10,
                    },
                    enableCompleteSound = {
                        name = "Enable Completion Sound",
                        desc = "Play a sound effect whenever a quest objective or full quest is completed.",
                        type = "toggle",
                        width = "full",
                        order = 11,
                        get = function() return db.sound and db.sound.enableCompleteSound end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.enableCompleteSound = val
                        end,
                    },
                    soundChoice = {
                        name = "Sound Effect",
                        desc = "Select which sound effect to play on completion.",
                        type = "select",
                        order = 12,
                        values = {
                            peon = "Peon: \"Work complete!\"",
                            quest_complete = "Classic Quest Complete",
                            level_up = "Level Up Fanfare",
                            raid_warning = "Raid Warning Chime",
                            ready_check = "Ready Check Chime",
                            map_ping = "Mini-Map Ping",
                            pvp_horn = "PvP Queue Horn",
                        },
                        get = function() return (db.sound and db.sound.soundChoice) or "peon" end,
                        set = function(_, val)
                            db.sound = db.sound or {}
                            db.sound.soundChoice = val
                            if ns.SocialModule and ns.SocialModule.PlayPreviewSound then
                                ns.SocialModule:PlayPreviewSound(val)
                            end
                        end,
                    },
                    previewBtn = {
                        name = "Play Sound Preview",
                        desc = "Play the currently selected sound effect.",
                        type = "execute",
                        order = 13,
                        func = function()
                            if ns.SocialModule and ns.SocialModule.PlayPreviewSound then
                                local c = (db.sound and db.sound.soundChoice) or "peon"
                                ns.SocialModule:PlayPreviewSound(c)
                            end
                        end,
                    },
                },
            },
        },
    }

    local AceDBOptions = LibStub and LibStub("AceDBOptions-3.0", true)
    if AceDBOptions and ns.dbObject then
        options.args.profiles = AceDBOptions:GetOptionsTable(ns.dbObject)
        options.args.profiles.order = 8
    end

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

function Config:ToggleConfigFrame()
    if not self.initialized then
        self:InitializeOptions()
    end
    if ns.SetupColorPickerEnhancements then
        ns.SetupColorPickerEnhancements()
    end

    if ACD then
        if ACD.OpenFrames and ACD.OpenFrames["BleakfiberQuestTracker"] then
            ACD:Close("BleakfiberQuestTracker")
            if ns.Tracker and ns.Tracker.HideConfigOverlay then
                ns.Tracker:HideConfigOverlay()
            end
        else
            ACD:Open("BleakfiberQuestTracker")
            local f = ACD.OpenFrames and ACD.OpenFrames["BleakfiberQuestTracker"]
            if f and f.frame then
                f.frame:SetClampedToScreen(true)

                -- Register frame in UISpecialFrames so pressing ESC automatically closes it
                _G["BleakfiberConfigFrame"] = f.frame
                local inSpecial = false
                for _, name in ipairs(UISpecialFrames) do
                    if name == "BleakfiberConfigFrame" then
                        inSpecial = true
                        break
                    end
                end
                if not inSpecial then
                    table.insert(UISpecialFrames, "BleakfiberConfigFrame")
                end

                if not f.frame.__bfqHooked then
                    f.frame.__bfqHooked = true

                    -- Catch ESC key directly on the frame to close without opening Game Menu
                    f.frame:EnableKeyboard(true)
                    f.frame:HookScript("OnKeyDown", function(self, key)
                        if key == "ESCAPE" then
                            self:SetPropagateKeyboardInput(false)
                            self:Hide()
                        end
                    end)

                    -- OnHide cleanup ensures overlay is hidden whenever this frame closes
                    f.frame:HookScript("OnHide", function()
                        if ns.Tracker and ns.Tracker.HideConfigOverlay then
                            ns.Tracker:HideConfigOverlay()
                        end
                        if ACD and ACD.Close then
                            ACD:Close("BleakfiberQuestTracker")
                        end
                    end)
                end
            end
        end
    end
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
            ns.Print("Saved in DB: default (TOPRIGHT, -250, -200)")
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
    elseif command == "config" or command == "options" or command == "" then
        Config:ToggleConfigFrame()
    else
        print("|cff00c0ffBleakfiber's Quest Tracker Commands:|r")
        print("  |cff00ff00/bfq|r or |cff00ff00/bqt|r - Open configuration panel")
        print("  |cff00ff00/bfq lock|r - Lock tracker position")
        print("  |cff00ff00/bfq unlock|r - Unlock tracker position")
        print("  |cff00ff00/bfq toggle|r - Expand or collapse tracker")
        print("  |cff00ff00/bfq reset|r - Reset tracker position to default")
        print("  |cff00ff00/bfq pos|r - View live position and saved coordinates debug info")
        print("  |cff00ff00/bfq profile [name]|r - View or switch active profile")
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

