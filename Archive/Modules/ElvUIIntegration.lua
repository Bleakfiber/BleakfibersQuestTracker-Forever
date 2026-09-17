local addonName, ns = ...

local ElvUIModule = {}
ns.ElvUIModule = ElvUIModule
ns:RegisterModule("ElvUIIntegration", ElvUIModule)

function ElvUIModule:IsAvailable()
    return _G.ElvUI ~= nil
end

function ElvUIModule:Initialize()
    -- Safe environment check: if ElvUI is not present or integration is disabled, silently exit
    if not self:IsAvailable() then return end
    if ns.db and ns.db.integrations and not ns.db.integrations.elvui then return end

    local E, L, V, P, G = unpack(_G.ElvUI)
    if not E then return end

    local trackerFrame = ns.Tracker and ns.Tracker:GetFrame()
    if not trackerFrame then return end

    -- 1. Register with ElvUI's Mover Framework
    -- This seamlessly integrates with ElvUI's "/ec -> Toggle Anchors"
    if E.CreateMover then
        E:CreateMover(
            trackerFrame,
            "BleakfiberQuestTrackerMover",
            "Bleakfiber's Quest Tracker",
            nil,
            nil,
            nil,
            "ALL,GENERAL",
            nil,
            "bleakfiber,quest"
        )
    end

    -- 2. Apply ElvUI Pixel-Perfect Skinning
    if trackerFrame.SetTemplate then
        trackerFrame:SetTemplate("Transparent")
    end

    -- 3. Skin Header & Buttons
    if trackerFrame.header and trackerFrame.header.collapseBtn then
        local btn = trackerFrame.header.collapseBtn
        if E.GetModule then
            local S = E:GetModule("Skins", true)
            if S and S.HandleButton then
                S:HandleButton(btn, true)
            end
        end
    end

    -- 4. Typography Enhancement
    -- Inherit ElvUI's primary font and font sizes if available
    if E.media and E.media.normFont then
        if trackerFrame.header and trackerFrame.header.titleText then
            trackerFrame.header.titleText:SetFont(E.media.normFont, 12, "OUTLINE")
        end
        if trackerFrame.header and trackerFrame.header.countText then
            trackerFrame.header.countText:SetFont(E.media.normFont, 11, "OUTLINE")
        end
    end

    ns.Print("ElvUI detected. Native skinning and mover integration applied.")
end

