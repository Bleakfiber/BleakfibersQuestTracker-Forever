local addonName, ns = ...

-- Localized Lua & WoW API bindings for performance
local pairs, ipairs, tonumber, select, pcall = pairs, ipairs, tonumber, select, pcall
local string_format = string.format
local C_Timer, CreateFrame = C_Timer, CreateFrame
local IsShiftKeyDown = IsShiftKeyDown
local GetNumLootItems, LootSlot, GetLootSlotType = GetNumLootItems, LootSlot, GetLootSlotType
local CanMerchantRepair, GetRepairAllCost, RepairAllItems = CanMerchantRepair, GetRepairAllCost, RepairAllItems
local CanGuildBankRepair, GetGuildBankWithdrawMoney = CanGuildBankRepair, GetGuildBankWithdrawMoney
local GetCoinTextureString, GetMoney = GetCoinTextureString, GetMoney
local C_Container, C_Item = C_Container, C_Item
local GetContainerNumSlots, GetContainerItemInfo, UseContainerItem = GetContainerNumSlots, GetContainerItemInfo, UseContainerItem
local GetItemInfo = GetItemInfo

local QoLModule = {}
ns.QoLModule = QoLModule
ns:RegisterModule("QoLModule", QoLModule)

local eventFrame = CreateFrame("Frame")
QoLModule.eventFrame = eventFrame
QoLModule.isEnabled = false

local function GetQoLCfg()
    local db = (ns.db and ns.db.qol) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.qol)
    return db or {}
end

local function FormatMoneyString(copper)
    if GetCoinTextureString then
        return GetCoinTextureString(copper)
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string_format("%dg %ds %dc", g, s, c)
    elseif s > 0 then
        return string_format("%ds %dc", s, c)
    else
        return string_format("%dc", c)
    end
end

-- ===========================================================================
-- 1. Fast Auto Loot Engine
-- ===========================================================================

local function ProcessFastAutoLoot()
    local cfg = GetQoLCfg()
    if not cfg.fastAutoLoot then return end

    if cfg.shiftBypass ~= false and IsShiftKeyDown() then
        return
    end

    local count = GetNumLootItems()
    if not count or count == 0 then return end

    for i = count, 1, -1 do
        LootSlot(i)
    end
end

-- ===========================================================================
-- 2. Auto Vendor Greys / Junk
-- ===========================================================================

local function ProcessAutoVendorGreys()
    local cfg = GetQoLCfg()
    local isEnabled = (cfg.autoVendorGreys == true or cfg.autoSellJunk == true)
    if not isEnabled then return end
    if cfg.shiftBypass ~= false and IsShiftKeyDown() then return end

    if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
        C_MerchantFrame.SellAllJunkItems()
    else
        for bagID = 0, 4 do
            local numSlots = (C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bagID) or 0
            for slotID = 1, numSlots do
                local info = (C_Container and C_Container.GetContainerItemInfo or GetContainerItemInfo)(bagID, slotID)
                local isJunk = false
                if type(info) == "table" then
                    isJunk = (info.quality == 0 and not info.hasNoValue)
                elseif info ~= nil and GetContainerItemInfo then
                    local _, _, _, quality, _, _, _, _, hasNoValue = GetContainerItemInfo(bagID, slotID)
                    isJunk = (quality == 0 and not hasNoValue)
                end
                if isJunk then
                    (C_Container and C_Container.UseContainerItem or UseContainerItem)(bagID, slotID)
                end
            end
        end
    end
end

-- ===========================================================================
-- 3. Auto Repair
-- ===========================================================================

local function ProcessAutoRepair()
    local cfg = GetQoLCfg()
    if not cfg.autoRepair then return end
    if cfg.shiftBypass ~= false and IsShiftKeyDown() then return end
    if not CanMerchantRepair or not CanMerchantRepair() then return end

    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end

    local usedGuildFunds = false
    if cfg.useGuildRepair and CanGuildBankRepair and CanGuildBankRepair() then
        local withdrawLimit = (GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()) or 0
        if withdrawLimit == -1 or withdrawLimit >= cost then
            RepairAllItems(true)
            usedGuildFunds = true
        end
    end

    if not usedGuildFunds then
        local playerMoney = (GetMoney and GetMoney()) or 0
        if playerMoney >= cost then
            RepairAllItems(false)
        else
            print("|cffff3333[Bleakfiber]|r Insufficient funds to repair gear.")
            return
        end
    end

    local costStr = FormatMoneyString(cost)
    if usedGuildFunds then
        print(string_format("|cff00c0ff[Bleakfiber]|r Repaired all items using |cff00ff00Guild Bank|r funds (%s).", costStr))
    else
        print(string_format("|cff00c0ff[Bleakfiber]|r Repaired all items for %s.", costStr))
    end
end

-- ===========================================================================
-- Lifecycle & Event Handlers
-- ===========================================================================

local function OnEvent(self, event, ...)
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        ProcessFastAutoLoot()
    elseif event == "MERCHANT_SHOW" then
        ProcessAutoVendorGreys()
        ProcessAutoRepair()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function()
                if MerchantFrame and MerchantFrame:IsShown() then
                    ProcessAutoVendorGreys()
                    ProcessAutoRepair()
                end
            end)
        end
    elseif event == "MERCHANT_CLOSED" then
        -- Clean session close
    end
end

function QoLModule:Enable()
    if self.isEnabled then return end
    self.isEnabled = true

    eventFrame:RegisterEvent("LOOT_READY")
    eventFrame:RegisterEvent("LOOT_OPENED")
    eventFrame:RegisterEvent("MERCHANT_SHOW")
    eventFrame:RegisterEvent("MERCHANT_CLOSED")
    eventFrame:SetScript("OnEvent", OnEvent)
end

function QoLModule:Disable()
    if not self.isEnabled then return end
    self.isEnabled = false

    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
end

function QoLModule:Initialize()
    if ns.IsModuleEnabled and not ns.IsModuleEnabled("qol") then
        self:Disable()
        return
    end
    self:Enable()
end
