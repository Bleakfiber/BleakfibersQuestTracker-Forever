-- World of Warcraft: Forever (1.60.1 / Interface 16001) Compatibility Shims
-- Restores removed Blizzard global helper functions needed by embedded libraries (Ace3, LibSharedMedia, etc.)

if not _G.SetDesaturation then
    _G.SetDesaturation = function(texture, desaturation)
        if texture and texture.SetDesaturated then
            texture:SetDesaturated(desaturation and true or false)
        end
    end
end

if not _G.GetItemInfo and C_Item and C_Item.GetItemInfo then
    _G.GetItemInfo = function(item)
        return C_Item.GetItemInfo(item)
    end
end

if not _G.GetItemInfoInstant and C_Item and C_Item.GetItemInfoInstant then
    _G.GetItemInfoInstant = function(item)
        return C_Item.GetItemInfoInstant(item)
    end
end

if not _G.GetSpellInfo and C_Spell and C_Spell.GetSpellInfo then
    _G.GetSpellInfo = function(spellID)
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID, info.originalIconID
        end
    end
end

