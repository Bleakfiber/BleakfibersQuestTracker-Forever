local addonName, ns = ...

-- Localized Lua APIs
local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local string_format = string.format
local CreateFrame, UIParent = CreateFrame, UIParent

local Onboarding = {}
ns.Onboarding = Onboarding

local onboardingFrame = nil
local currentStep = 1
local totalSteps = 6

local function ApplyBackdrop(frame)
    if not frame then return end
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            tileSize = 16,
            edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0.05, 0.07, 0.10, 0.95)
        frame:SetBackdropBorderColor(0.00, 0.75, 1.00, 0.85)
    end
end

function Onboarding:CreateWizardFrame()
    if onboardingFrame then return onboardingFrame end

    local f = CreateFrame("Frame", "BleakfiberOnboardingWizard", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    onboardingFrame = f
    f:SetSize(540, 440)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    ApplyBackdrop(f)

    -- Header Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("|cff00c0ffBleakfiber's Quest Tracker|r - Setup Walkthrough")
    f.title = title

    -- Step Indicator
    local stepText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stepText:SetPoint("TOP", title, "BOTTOM", 0, -4)
    stepText:SetText("Step 1 of 6")
    f.stepText = stepText

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
        if ns.db then ns.db.onboardingCompleted = true end
        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
    end)

    -- Content Container
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -56)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 56)
    f.content = content

    -- Navigation Buttons
    local backBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    backBtn:SetSize(90, 24)
    backBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function()
        if currentStep > 1 then
            currentStep = currentStep - 1
            Onboarding:RenderStep(currentStep)
        end
    end)
    f.backBtn = backBtn

    local nextBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextBtn:SetSize(90, 24)
    nextBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    nextBtn:SetText("Next")
    nextBtn:SetScript("OnClick", function()
        if currentStep < totalSteps then
            currentStep = currentStep + 1
            Onboarding:RenderStep(currentStep)
        else
            f:Hide()
            if ns.db then ns.db.onboardingCompleted = true end
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            ns.Print("|cff00ff00Setup complete!|r Type |cff00c0ff/bfq|r anytime to open full settings.")
        end
    end)
    f.nextBtn = nextBtn

    local skipBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    skipBtn:SetSize(110, 24)
    skipBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    skipBtn:SetText("Skip Walkthrough")
    skipBtn:SetScript("OnClick", function()
        f:Hide()
        if ns.db then ns.db.onboardingCompleted = true end
        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
    end)
    f.skipBtn = skipBtn

    f:SetScript("OnHide", function()
        if CloseDropDownMenus then CloseDropDownMenus() end
    end)

    return f
end

local stepWidgets = {}
local function ClearStepWidgets()
    if CloseDropDownMenus then
        CloseDropDownMenus()
    end
    for _, w in ipairs(stepWidgets) do
        w:Hide()
    end
    wipe(stepWidgets)
end

local function CreateSoundDropdown(parent, name, width, items, getVal, setVal, onPreview)
    if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo then
        local dd = _G[name]
        if not dd then
            dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
        else
            dd:SetParent(parent)
            dd:Show()
        end
        UIDropDownMenu_SetWidth(dd, width)

        local function Initialize(self, level)
            local currentVal = getVal()
            for _, item in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.value = item.value
                info.checked = (currentVal == item.value)
                info.func = function()
                    setVal(item.value)
                    UIDropDownMenu_SetSelectedValue(dd, item.value)
                    UIDropDownMenu_SetText(dd, item.text)
                    if onPreview then onPreview(item.value) end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end

        UIDropDownMenu_Initialize(dd, Initialize)
        local cur = getVal()
        for _, item in ipairs(items) do
            if item.value == cur then
                UIDropDownMenu_SetSelectedValue(dd, cur)
                UIDropDownMenu_SetText(dd, item.text)
                break
            end
        end
        return dd
    else
        local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
        btn:SetSize(width, 22)
        local function UpdateText()
            local cur = getVal()
            for _, it in ipairs(items) do
                if it.value == cur then
                    btn:SetText(it.text)
                    return
                end
            end
            btn:SetText(items[1] and items[1].text or "")
        end
        UpdateText()
        btn:SetScript("OnClick", function()
            local cur = getVal()
            local nextIdx = 1
            for idx, it in ipairs(items) do
                if it.value == cur then
                    nextIdx = (idx % #items) + 1
                    break
                end
            end
            local chosen = items[nextIdx]
            if chosen then
                setVal(chosen.value)
                UpdateText()
                if onPreview then onPreview(chosen.value) end
            end
        end)
        return btn
    end
end

function Onboarding:RenderStep(step)
    local f = self:CreateWizardFrame()
    ClearStepWidgets()
    currentStep = step
    f.stepText:SetText(string_format("Step %d of %d", step, totalSteps))

    f.backBtn:SetEnabled(step > 1)
    f.nextBtn:SetText(step == totalSteps and "Finish" or "Next")

    local c = f.content

    if step == 1 then
        -- Step 1: Preset Selection
        local h = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        h:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        h:SetText("|cffffd1001. Choose a Visual Preset|r")
        table.insert(stepWidgets, h)

        local desc = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
        desc:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText("Select an aesthetic theme. DataBars inherit your tracker styling by default, and every color, font, and border can be customized later in /bfq.")
        table.insert(stepWidgets, desc)

        local presets = {
            {
                name = "Modern Dark Glass (Default)",
                desc = "Sleek semi-transparent dark backdrop with clean 1px border and class accents.",
                apply = function()
                    if ns.Config and ns.Config.ApplyModernGlassPreset then
                        ns.Config:ApplyModernGlassPreset()
                    end
                end
            },
            {
                name = "Classic WoW Plus",
                desc = "Traditional Blizzard parchment border with authentic cream paper backdrop and high contrast.",
                apply = function()
                    if ns.Config and ns.Config.ApplyClassicPreset then
                        ns.Config:ApplyClassicPreset()
                    end
                end
            },
            {
                name = "Ultra Minimalist",
                desc = "Zero background borders, compact typography, maximum screen real estate.",
                apply = function()
                    if ns.Config and ns.Config.ApplyMinimalPreset then
                        ns.Config:ApplyMinimalPreset()
                    end
                end
            },
        }

        local prev = desc
        for idx, p in ipairs(presets) do
            local btn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
            btn:SetSize(190, 24)
            btn:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, (idx == 1 and -16 or -26))
            btn:SetText(p.name)
            local pCopy = p
            btn:SetScript("OnClick", function()
                pCopy.apply()
                ns.Print("|cff00c0ffApplied preset:|r " .. pCopy.name)
            end)
            table.insert(stepWidgets, btn)

            local pDesc = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            pDesc:SetPoint("LEFT", btn, "RIGHT", 12, 0)
            pDesc:SetPoint("RIGHT", c, "RIGHT", 0, 0)
            pDesc:SetJustifyH("LEFT")
            pDesc:SetText(p.desc)
            table.insert(stepWidgets, pDesc)

            prev = btn
        end

    elseif step == 2 then
        -- Step 2: Feature & Module Toggles (Inline Vertical Alignment - No Cascading!)
        local h = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        h:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        h:SetText("|cffffd1002. Feature Modules|r")
        table.insert(stepWidgets, h)

        local desc = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
        desc:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText("Turn addon modules on or off according to your preference. Disabled modules unload live with zero memory or event overhead.")
        table.insert(stepWidgets, desc)

        local modules = {
            { key = "wayfinder", name = "Wayfinder Navigation", desc = "Floating 3D HUD waypoint arrow & inline mini tracker arrows pointing to active objectives." },
            { key = "databars", name = "DataBars Suite", desc = "Experience Bar, Precision Coordinates & Location Bar, and Quest Timer Bar." },
            { key = "questAutomation", name = "Quest Automation", desc = "Optional auto-accept and auto-turn-in for quests." },
            { key = "qol", name = "Quality of Life (QoL)", desc = "Instant Fast Auto Loot, junk item vendor selling, and auto repair." },
        }

        for idx, mod in ipairs(modules) do
            local yOffset = -34 - (idx - 1) * 56
            local cb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", c, "TOPLEFT", 8, yOffset)
            local isEnabled = ns.IsModuleEnabled and ns.IsModuleEnabled(mod.key)
            cb:SetChecked(isEnabled)
            local modKey = mod.key
            cb:SetScript("OnClick", function(self)
                local checked = self:GetChecked()
                if ns.SetModuleEnabled then
                    ns.SetModuleEnabled(modKey, checked)
                end
            end)
            table.insert(stepWidgets, cb)

            local label = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            label:SetText(mod.name)
            table.insert(stepWidgets, label)

            local mDesc = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            mDesc:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 28, -2)
            mDesc:SetPoint("RIGHT", c, "RIGHT", -10, 0)
            mDesc:SetJustifyH("LEFT")
            mDesc:SetText(mod.desc)
            table.insert(stepWidgets, mDesc)
        end

    elseif step == 3 then
        -- Step 3: Quest Items & Objectives
        local h = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        h:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        h:SetText("|cffffd1003. Quest Items & Countdown Timers|r")
        table.insert(stepWidgets, h)

        local desc = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
        desc:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText("Configure usable quest items and timed objective displays:")
        table.insert(stepWidgets, desc)

        -- Item button placement label
        local posLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        posLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
        posLabel:SetText("Quest Item Button Placement (Mutually Exclusive):")
        table.insert(stepWidgets, posLabel)

        local curPlacement = (ns.db and ns.db.itemButtonPlacement) or "inside_right"
        if curPlacement ~= "inside_right" and curPlacement ~= "outside_left" then
            curPlacement = "inside_right"
        end
        local placementOptions = {
            { key = "inside_right", text = "Inside Tracker - Right" },
            { key = "outside_left", text = "Outside Tracker - Left" },
        }

        local prevBtn = posLabel
        for idx, opt in ipairs(placementOptions) do
            local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
            b:SetSize(190, 22)
            b:SetPoint("TOPLEFT", prevBtn, "BOTTOMLEFT", 0, -6)
            b:SetText(opt.text .. (curPlacement == opt.key and " |cff00ff00[Active]|r" or ""))
            local optKey = opt.key
            b:SetScript("OnClick", function()
                if ns.db then
                    ns.db.itemButtonPlacement = optKey
                    if ns.StandaloneTracker and ns.StandaloneTracker.UpdateItemButton then
                        ns.StandaloneTracker:UpdateItemButton()
                    end
                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                end
                Onboarding:RenderStep(3)
            end)
            table.insert(stepWidgets, b)
            prevBtn = b
        end

        -- Countdown timer checkbox
        local timerCb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
        timerCb:SetPoint("TOPLEFT", prevBtn, "BOTTOMLEFT", 0, -16)
        local timerOn = not (ns.db and ns.db.showTimerInObjectives == false)
        timerCb:SetChecked(timerOn)
        timerCb:SetScript("OnClick", function(self)
            local val = self:GetChecked()
            if ns.db then ns.db.showTimerInObjectives = val end
            if ns.StandaloneTracker and ns.StandaloneTracker.RequestUpdate then
                ns.StandaloneTracker:RequestUpdate(true)
            end
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
        end)
        table.insert(stepWidgets, timerCb)

        local tLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tLabel:SetPoint("LEFT", timerCb, "RIGHT", 6, 0)
        tLabel:SetText("Show Timers in Objective Text (e.g. [04:12])")
        table.insert(stepWidgets, tLabel)

        local tDesc = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tDesc:SetPoint("TOPLEFT", tLabel, "BOTTOMLEFT", 0, -2)
        tDesc:SetText("Strictly scoped to quests that have an active countdown timer.")
        table.insert(stepWidgets, tDesc)

    elseif step == 4 then
        -- Step 4: Quest Automation
        local h = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        h:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        h:SetText("|cffffd1004. Quest Automation|r")
        table.insert(stepWidgets, h)

        local desc = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
        desc:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText("Streamline your quest interactions. All automation automatically pauses when holding Shift:")
        table.insert(stepWidgets, desc)

        local autoOptions = {
            {
                name = "Auto Accept NPC Quests",
                desc = "Automatically accept available quests when speaking with quest-givers.",
                get = function()
                    return (ns.db and ns.db.questAutomation and ns.db.questAutomation.autoAcceptNPC)
                        or (ns.db and ns.db.social and ns.db.social.autoAcceptNPC) == true
                end,
                set = function(v)
                    if ns.db then
                        ns.db.questAutomation = ns.db.questAutomation or {}
                        ns.db.questAutomation.autoAcceptNPC = v
                        ns.db.social = ns.db.social or {}
                        ns.db.social.autoAcceptNPC = v
                    end
                end,
            },
            {
                name = "Auto Accept Shared Quests",
                desc = "Automatically accept quests shared by party or raid members.",
                get = function()
                    return (ns.db and ns.db.questAutomation and ns.db.questAutomation.autoAcceptShared)
                        or (ns.db and ns.db.social and ns.db.social.autoAcceptShared) == true
                end,
                set = function(v)
                    if ns.db then
                        ns.db.questAutomation = ns.db.questAutomation or {}
                        ns.db.questAutomation.autoAcceptShared = v
                        ns.db.social = ns.db.social or {}
                        ns.db.social.autoAcceptShared = v
                    end
                end,
            },
            {
                name = "Auto Turn-In Quests (1 or Less Choice)",
                desc = "Automatically complete and turn in quests offering 1 or 0 reward choices. Multi-choice rewards remain open for manual selection.",
                get = function()
                    return (ns.db and ns.db.questAutomation and ns.db.questAutomation.autoTurnIn)
                        or (ns.db and ns.db.social and ns.db.social.autoTurnIn) == true
                end,
                set = function(v)
                    if ns.db then
                        ns.db.questAutomation = ns.db.questAutomation or {}
                        ns.db.questAutomation.autoTurnIn = v
                        ns.db.social = ns.db.social or {}
                        ns.db.social.autoTurnIn = v
                    end
                end,
            },
            {
                name = "Auto-Share Quests",
                desc = "Automatically share newly accepted quests with your party when grouped.",
                get = function()
                    return (ns.db and ns.db.questAutomation and ns.db.questAutomation.autoShare)
                        or (ns.db and ns.db.social and ns.db.social.autoShare) == true
                end,
                set = function(v)
                    if ns.db then
                        ns.db.questAutomation = ns.db.questAutomation or {}
                        ns.db.questAutomation.autoShare = v
                        ns.db.social = ns.db.social or {}
                        ns.db.social.autoShare = v
                    end
                end,
            },
            {
                name = "Shift-Key bypass",
                desc = "Hold Shift while talking to an NPC to temporarily pause all automated accepting and turning in.",
                get = function()
                    if ns.db and ns.db.questAutomation and ns.db.questAutomation.shiftBypass ~= nil then
                        return ns.db.questAutomation.shiftBypass ~= false
                    end
                    if ns.db and ns.db.social and ns.db.social.shiftBypass ~= nil then
                        return ns.db.social.shiftBypass ~= false
                    end
                    return true
                end,
                set = function(v)
                    if ns.db then
                        ns.db.questAutomation = ns.db.questAutomation or {}
                        ns.db.questAutomation.shiftBypass = v
                        ns.db.social = ns.db.social or {}
                        ns.db.social.shiftBypass = v
                    end
                end,
            },
        }

        for idx, opt in ipairs(autoOptions) do
            local yOffset = -32 - (idx - 1) * 52
            local cb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", c, "TOPLEFT", 8, yOffset)
            cb:SetChecked(opt.get())
            local optCopy = opt
            cb:SetScript("OnClick", function(self)
                optCopy.set(self:GetChecked())
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            end)
            table.insert(stepWidgets, cb)

            local label = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            label:SetText(opt.name)
            table.insert(stepWidgets, label)

            local oDesc = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            oDesc:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 28, -2)
            oDesc:SetPoint("RIGHT", c, "RIGHT", -10, 0)
            oDesc:SetJustifyH("LEFT")
            oDesc:SetText(opt.desc)
            table.insert(stepWidgets, oDesc)
        end

    elseif step == 5 then
        -- Step 5: Quality of Life (QoL)
        local h = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        h:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        h:SetText("|cffffd1005. Quality of Life (QoL)|r")
        table.insert(stepWidgets, h)

        local desc = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
        desc:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText("Configure automatic merchant utilities and looting:")
        table.insert(stepWidgets, desc)

        local qolOptions = {
            {
                name = "Fast Auto Loot",
                desc = "Instantaneous, unthrottled looting from mobs and containers. Overrides the Blizzard setting entirely.",
                get = function()
                    return (ns.db and ns.db.qol and ns.db.qol.fastAutoLoot ~= false)
                end,
                set = function(v)
                    if ns.db then
                        ns.db.qol = ns.db.qol or {}
                        ns.db.qol.fastAutoLoot = v
                        if ns.db.social then ns.db.social.fastAutoLoot = v end
                    end
                    if ns.QoLModule and ns.QoLModule.UpdateLootEvents then
                        ns.QoLModule:UpdateLootEvents()
                    end
                end,
            },
            {
                name = "Auto Vendor Grey / Junk Items",
                desc = "Automatically sells poor-quality junk items at merchants.",
                get = function()
                    return (ns.db and ns.db.qol and (ns.db.qol.autoVendorGreys == true or ns.db.qol.autoSellJunk == true))
                end,
                set = function(v)
                    if ns.db then
                        ns.db.qol = ns.db.qol or {}
                        ns.db.qol.autoVendorGreys = v
                        ns.db.qol.autoSellJunk = v
                        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                    end
                end,
            },
            {
                name = "Auto-Repair Equipment",
                desc = "Automatically repairs damaged gear whenever visiting an armorer or repair merchant.",
                get = function()
                    return (ns.db and ns.db.qol and ns.db.qol.autoRepair == true)
                end,
                set = function(v)
                    if ns.db then
                        ns.db.qol = ns.db.qol or {}
                        ns.db.qol.autoRepair = v
                    end
                end,
            },
            {
                name = "Use Guild Bank for Repairs",
                desc = "Charges repairs to your guild bank allowance if available, falling back to personal funds if unavailable.",
                get = function()
                    return (ns.db and ns.db.qol and ns.db.qol.useGuildRepair == true)
                end,
                set = function(v)
                    if ns.db then
                        ns.db.qol = ns.db.qol or {}
                        ns.db.qol.useGuildRepair = v
                    end
                end,
            },
            {
                name = "Shift-Key Bypass",
                desc = "Hold Shift while opening a merchant window to temporarily pause auto-selling and auto-repairing.",
                get = function()
                    return not (ns.db and ns.db.qol and ns.db.qol.shiftBypass == false)
                end,
                set = function(v)
                    if ns.db then
                        ns.db.qol = ns.db.qol or {}
                        ns.db.qol.shiftBypass = v
                    end
                end,
            },
        }

        for idx, opt in ipairs(qolOptions) do
            local yOffset = -32 - (idx - 1) * 52
            local cb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", c, "TOPLEFT", 8, yOffset)
            cb:SetChecked(opt.get())
            local optCopy = opt
            cb:SetScript("OnClick", function(self)
                optCopy.set(self:GetChecked())
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            end)
            table.insert(stepWidgets, cb)

            local label = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            label:SetText(opt.name)
            table.insert(stepWidgets, label)

            local oDesc = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            oDesc:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 28, -2)
            oDesc:SetPoint("RIGHT", c, "RIGHT", -10, 0)
            oDesc:SetJustifyH("LEFT")
            oDesc:SetText(opt.desc)
            table.insert(stepWidgets, oDesc)
        end

    elseif step == 6 then
        -- Step 6: Social & Audio
        local h = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        h:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        h:SetText("|cffffd1006. Social & Audio Feedback|r")
        table.insert(stepWidgets, h)

        local desc = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
        desc:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetText("Configure party chat notifications and audio feedback cues:")
        table.insert(stepWidgets, desc)

        -- 1. Announce Quest Progress to Party Chat
        local cb1 = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
        cb1:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -44)
        local partyChecked = (ns.db and ns.db.social and (ns.db.social.announceParty == true or ns.db.social.announceToParty == true)) == true
        cb1:SetChecked(partyChecked)
        cb1:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            if ns.db then
                ns.db.social = ns.db.social or {}
                ns.db.social.announceParty = isChecked
                ns.db.social.announceToParty = isChecked
                if isChecked then
                    ns.db.social.announceQuestComplete = true
                    ns.db.social.announceObjectiveComplete = false
                    ns.db.social.announceObjectiveProgress = false
                end
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            end
        end)
        table.insert(stepWidgets, cb1)

        local label1 = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label1:SetPoint("LEFT", cb1, "RIGHT", 6, 0)
        label1:SetText("Announce Quest Progress to Party Chat")
        table.insert(stepWidgets, label1)

        local oDesc1 = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        oDesc1:SetPoint("TOPLEFT", cb1, "BOTTOMLEFT", 28, -2)
        oDesc1:SetPoint("RIGHT", c, "RIGHT", -10, 0)
        oDesc1:SetJustifyH("LEFT")
        oDesc1:SetText("Sends subtle notifications to your party when quests finish (enables quest completion announcements only).")
        table.insert(stepWidgets, oDesc1)

        -- Sound option definitions
        local objectiveSoundList = {
            { value = "whisper_ping", text = "Whisper Ping (TellMessage)" },
            { value = "coins",        text = "Gold Coin Ding" },
            { value = "loot_clink",   text = "Loot Coin Clink" },
            { value = "map_ping",     text = "Mini-Map Ping" },
            { value = "item_click",   text = "Subtle Click" },
        }

        local completeSoundList = {
            { value = "peon",           text = "Peon: \"Work complete!\"" },
            { value = "quest_complete",  text = "Classic Quest Complete" },
            { value = "whisper_ping",   text = "Whisper Ping (TellMessage)" },
            { value = "coins",          text = "Gold Coin Ding" },
            { value = "loot_clink",     text = "Loot Coin Clink" },
            { value = "level_up",       text = "Level Up Fanfare" },
            { value = "raid_warning",   text = "Raid Warning Chime" },
            { value = "ready_check",    text = "Ready Check Chime" },
            { value = "pvp_horn",       text = "PvP Queue Horn" },
        }

        -- 2. Play Objective Progress Sound & Dropdown
        local cb2 = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
        cb2:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -100)
        local objSoundOn = not (ns.db and ns.db.sound and ns.db.sound.enableObjectiveSound == false)
        cb2:SetChecked(objSoundOn)
        table.insert(stepWidgets, cb2)

        local label2 = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label2:SetPoint("LEFT", cb2, "RIGHT", 6, 0)
        label2:SetText("Play Objective Progress Sound")
        table.insert(stepWidgets, label2)

        local oDesc2 = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        oDesc2:SetPoint("TOPLEFT", cb2, "BOTTOMLEFT", 28, -2)
        oDesc2:SetPoint("RIGHT", c, "RIGHT", -10, 0)
        oDesc2:SetJustifyH("LEFT")
        oDesc2:SetText("Gentle audio cue whenever an objective progresses (e.g. looting 3/4 quest items).")
        table.insert(stepWidgets, oDesc2)

        local objDD = CreateSoundDropdown(c, "BleakfiberOnboardObjSoundDD", 180, objectiveSoundList,
            function()
                return (ns.db and ns.db.sound and ns.db.sound.objectiveSoundChoice) or "whisper_ping"
            end,
            function(v)
                if ns.db then
                    ns.db.sound = ns.db.sound or {}
                    ns.db.sound.objectiveSoundChoice = v
                    ns.db.sound.useCustomObjectiveSound = (v == "custom")
                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                end
            end,
            function(v)
                if ns.SocialModule and ns.SocialModule.PlayPreviewObjectiveSound then
                    ns.SocialModule:PlayPreviewObjectiveSound(v)
                end
            end
        )
        objDD:SetPoint("TOPLEFT", cb2, "BOTTOMLEFT", 12, -20)
        table.insert(stepWidgets, objDD)

        local prevBtn2 = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        prevBtn2:SetSize(70, 22)
        prevBtn2:SetPoint("LEFT", objDD, "RIGHT", 16, 2)
        prevBtn2:SetText("Preview")
        prevBtn2:SetScript("OnClick", function()
            if ns.SocialModule and ns.SocialModule.PlayPreviewObjectiveSound then
                local choice = (ns.db and ns.db.sound and ns.db.sound.objectiveSoundChoice) or "whisper_ping"
                ns.SocialModule:PlayPreviewObjectiveSound(choice)
            end
        end)
        table.insert(stepWidgets, prevBtn2)

        local function UpdateObjSoundEnabled(enabled)
            if enabled then
                if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(objDD) end
                prevBtn2:Enable()
            else
                if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(objDD) end
                prevBtn2:Disable()
            end
        end
        UpdateObjSoundEnabled(objSoundOn)

        cb2:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            if ns.db then
                ns.db.sound = ns.db.sound or {}
                ns.db.sound.enableObjectiveSound = isChecked
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            end
            UpdateObjSoundEnabled(isChecked)
        end)

        -- 3. Play Quest Complete Sound & Dropdown
        local cb3 = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
        cb3:SetPoint("TOPLEFT", c, "TOPLEFT", 8, -178)
        local compSoundOn = not (ns.db and ns.db.sound and ns.db.sound.enableCompleteSound == false)
        cb3:SetChecked(compSoundOn)
        table.insert(stepWidgets, cb3)

        local label3 = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label3:SetPoint("LEFT", cb3, "RIGHT", 6, 0)
        label3:SetText("Play Quest Complete Sound")
        table.insert(stepWidgets, label3)

        local oDesc3 = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        oDesc3:SetPoint("TOPLEFT", cb3, "BOTTOMLEFT", 28, -2)
        oDesc3:SetPoint("RIGHT", c, "RIGHT", -10, 0)
        oDesc3:SetJustifyH("LEFT")
        oDesc3:SetText("Audio fanfare when all objectives are finished and the quest is ready for turn-in.")
        table.insert(stepWidgets, oDesc3)

        local compDD = CreateSoundDropdown(c, "BleakfiberOnboardCompleteSoundDD", 180, completeSoundList,
            function()
                return (ns.db and ns.db.sound and ns.db.sound.soundChoice) or "peon"
            end,
            function(v)
                if ns.db then
                    ns.db.sound = ns.db.sound or {}
                    ns.db.sound.soundChoice = v
                    ns.db.sound.useCustomCompleteSound = (v == "custom")
                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
                end
            end,
            function(v)
                if ns.SocialModule and ns.SocialModule.PlayPreviewSound then
                    ns.SocialModule:PlayPreviewSound(v)
                end
            end
        )
        compDD:SetPoint("TOPLEFT", cb3, "BOTTOMLEFT", 12, -20)
        table.insert(stepWidgets, compDD)

        local prevBtn3 = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        prevBtn3:SetSize(70, 22)
        prevBtn3:SetPoint("LEFT", compDD, "RIGHT", 16, 2)
        prevBtn3:SetText("Preview")
        prevBtn3:SetScript("OnClick", function()
            if ns.SocialModule and ns.SocialModule.PlayPreviewSound then
                local choice = (ns.db and ns.db.sound and ns.db.sound.soundChoice) or "peon"
                ns.SocialModule:PlayPreviewSound(choice)
            end
        end)
        table.insert(stepWidgets, prevBtn3)

        local function UpdateCompSoundEnabled(enabled)
            if enabled then
                if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(compDD) end
                prevBtn3:Enable()
            else
                if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(compDD) end
                prevBtn3:Disable()
            end
        end
        UpdateCompSoundEnabled(compSoundOn)

        cb3:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            if ns.db then
                ns.db.sound = ns.db.sound or {}
                ns.db.sound.enableCompleteSound = isChecked
                if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
            end
            UpdateCompSoundEnabled(isChecked)
        end)

        local foot = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        foot:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 8, 8)
        foot:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        foot:SetJustifyH("LEFT")
        foot:SetText("|cff00c0ffPro Tip:|r Hold |cffffd100Shift|r while talking to an NPC or merchant to temporarily bypass automation.\nType |cff00c0ff/bfq onboard|r anytime to revisit this walkthrough.")
        table.insert(stepWidgets, foot)
    end
end

function Onboarding:ShowWizard()
    local f = self:CreateWizardFrame()
    f:Show()
    self:RenderStep(1)
end

-- Check initial login onboarding
function Onboarding:CheckFirstTimeUser()
    local isCompleted = ns.db and ns.db.onboardingCompleted
    if not isCompleted then
        self:ShowWizard()
    end
end
