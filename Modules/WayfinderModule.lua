local addonName, ns = ...

local WayfinderModule = {}
ns.WayfinderModule = WayfinderModule
ns:RegisterModule("WayfinderModule", WayfinderModule)

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, res1, res2, res3, res4 = pcall(fn, ...)
    if ok then
        return res1, res2, res3, res4
    end
    return nil
end

-- Multi-Waypoint Registry
WayfinderModule.customWaypoints = {}
local waypointCounter = 0

-- Current active waypoint target
local currentTarget = {
    hasTarget = false,
    questID = nil,
    uiMapID = nil,
    x = nil,
    y = nil,
    title = nil,
    isCustom = false,
    waypointID = nil,
}
WayfinderModule.currentTarget = currentTarget

function WayfinderModule:IsCustomTarget()
    return currentTarget.hasTarget and (currentTarget.isCustom == true)
end

function WayfinderModule:GetCurrentTarget()
    return currentTarget
end

-- Current computed navigation state
local navState = {
    hasTarget = false,
    distanceYards = 0,
    relativeAngle = 0,
    isArrived = false,
    r = 1,
    g = 1,
    b = 1,
    title = "",
}

local playedArrivalSound = false
local arrivedSoundTargetKey = nil
local updateElapsed = 0
local arrivalTimer = 0
local arrivalActive = false
local arrivedQuestIDs = {}

-- Performance & Memory Caching State (Zero-Garbage Architecture)
local cachedTargetWorldX = nil
local cachedTargetWorldY = nil
local cachedTargetMapID = nil
local cachedTargetRawX = nil
local cachedTargetRawY = nil

local lastPlayerMapX = nil
local lastPlayerMapY = nil
local lastPlayerFacing = -999
local stationaryElapsed = 0
local targetWorldAngle = 0

local lastDistFormatted = ""
local lastDistNumber = -1
local lastDistArrived = nil
local lastRotationAngle = -999
local lastColorR, lastColorG, lastColorB = -1, -1, -1
local lastInlineRotation = -999
local lastInlineR, lastInlineG, lastInlineB = -1, -1, -1

-- ETA & Velocity Tracking (Taint-Free Calculation)
local lastEtaDistance = nil
local lastEtaTime = nil
local smoothedSpeed = 0
local lastEtaFormatted = ""

local function InvalidateTargetWorldCache()
    cachedTargetWorldX = nil
    cachedTargetWorldY = nil
    cachedTargetMapID = nil
    cachedTargetRawX = nil
    cachedTargetRawY = nil
    lastPlayerMapX = nil
    lastPlayerMapY = nil
    lastEtaDistance = nil
    lastEtaTime = nil
    smoothedSpeed = 0
    lastEtaFormatted = ""
end

local function UpdateTargetWorldCache()
    if not currentTarget.hasTarget or not currentTarget.x or not currentTarget.y then
        InvalidateTargetWorldCache()
        return
    end

    if cachedTargetWorldX and cachedTargetRawX == currentTarget.x and cachedTargetRawY == currentTarget.y and cachedTargetMapID == currentTarget.uiMapID then
        return
    end

    local mapID = currentTarget.uiMapID or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if mapID and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local targetMapPos = CreateVector2D(currentTarget.x, currentTarget.y)
        if targetMapPos then
            local _, targetWorldPos = C_Map.GetWorldPosFromMapPos(mapID, targetMapPos)
            if targetWorldPos and targetWorldPos.x and targetWorldPos.y then
                cachedTargetWorldX = targetWorldPos.x
                cachedTargetWorldY = targetWorldPos.y
                cachedTargetMapID = mapID
                cachedTargetRawX = currentTarget.x
                cachedTargetRawY = currentTarget.y
                return
            end
        end
    end

    cachedTargetWorldX = nil
    cachedTargetWorldY = nil
    cachedTargetMapID = mapID
    cachedTargetRawX = currentTarget.x
    cachedTargetRawY = currentTarget.y
end

-- ---------------------------------------------------------------------------
-- Zone Name to uiMapID Resolver
-- ---------------------------------------------------------------------------

local function ResolveZoneNameToMapID(zoneName)
    if not zoneName or zoneName == "" then return nil end
    local query = zoneName:lower():gsub("^%s*(.-)%s*$", "%1")
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")

    -- 1. Check player's current map
    if playerMapID and C_Map and C_Map.GetMapInfo then
        local pInfo = C_Map.GetMapInfo(playerMapID)
        if pInfo and pInfo.name and pInfo.name:lower() == query then
            return playerMapID
        end
    end

    -- 2. Check area maps in the current continent/parent map
    if playerMapID and C_Map and C_Map.GetMapInfo then
        local pInfo = C_Map.GetMapInfo(playerMapID)
        local parentID = pInfo and pInfo.parentMapID
        if parentID and parentID > 0 and C_Map.GetMapChildrenInfo then
            local children = C_Map.GetMapChildrenInfo(parentID)
            if children then
                for _, child in ipairs(children) do
                    if child.name and child.name:lower() == query then
                        return child.mapID
                    end
                end
            end
        end
    end

    -- 3. Fallback: Search standard continents
    local continentIDs = { 1414, 1415, 1945, 113, 946 }
    for _, contID in ipairs(continentIDs) do
        if C_Map and C_Map.GetMapChildrenInfo then
            local children = C_Map.GetMapChildrenInfo(contID, 3)
            if children then
                for _, child in ipairs(children) do
                    if child.name and child.name:lower() == query then
                        return child.mapID
                    end
                end
            end
        end
    end

    return playerMapID
end

-- ---------------------------------------------------------------------------
-- Target Coordinate Resolution & Multi-Waypoint Management
-- ---------------------------------------------------------------------------

-- Helper: Locate turn-in NPC or object coordinates for completed quests (Centroid-centered)
local function GetQuestTurnInLocation(questID, questLogIndex)
    if not questID then return nil end

    local tx, ty, tMapID
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and SafeCall(C_Map.GetBestMapForUnit, "player")

    -- 1. Try Blizzard's C_QuestLog.GetQuestsOnMap (center of all turn-in pins on player or parent map)
    if C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local mapsToCheck = {}
        if playerMapID then table.insert(mapsToCheck, playerMapID) end
        if playerMapID and C_Map and C_Map.GetMapInfo then
            local info = SafeCall(C_Map.GetMapInfo, playerMapID)
            if info and info.parentMapID and info.parentMapID > 0 then
                table.insert(mapsToCheck, info.parentMapID)
            end
        end

        for _, mid in ipairs(mapsToCheck) do
            local qList = SafeCall(C_QuestLog.GetQuestsOnMap, mid)
            if qList and type(qList) == "table" then
                -- First pass: find entry marked as complete/turnin
                local sumX, sumY, count = 0, 0, 0
                for _, q in ipairs(qList) do
                    if q.questID == questID and (q.isComplete or q.isTurnIn) and q.x and q.y and q.x > 0 and q.y > 0 then
                        sumX = sumX + q.x
                        sumY = sumY + q.y
                        count = count + 1
                    end
                end
                if count > 0 then
                    tx, ty, tMapID = sumX / count, sumY / count, mid
                    break
                end

                -- Second pass: any entry for this quest on this map
                for _, q in ipairs(qList) do
                    if q.questID == questID and q.x and q.y and q.x > 0 and q.y > 0 then
                        sumX = sumX + q.x
                        sumY = sumY + q.y
                        count = count + 1
                    end
                end
                if count > 0 then
                    tx, ty, tMapID = sumX / count, sumY / count, mid
                    break
                end
            end
        end
    end

    -- 2. Try C_QuestLog.GetNextWaypoint for completed quests
    if not (tx and ty) and C_QuestLog and C_QuestLog.GetNextWaypoint then
        local waypoint = SafeCall(C_QuestLog.GetNextWaypoint, questID)
        if waypoint then
            if waypoint.GetXY then
                tx, ty = waypoint:GetXY()
            elseif waypoint.x and waypoint.y then
                tx, ty = waypoint.x, waypoint.y
            end
            if tx and ty then
                tMapID = (C_QuestLog.GetNextWaypointMapID and SafeCall(C_QuestLog.GetNextWaypointMapID, questID)) or playerMapID
            end
        end
    end

    -- 3. Try Classic QuestPOIGetIconInfo
    if not (tx and ty) and type(QuestPOIGetIconInfo) == "function" then
        local logIdx = questLogIndex or (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and SafeCall(C_QuestLog.GetLogIndexForQuestID, questID))
        if logIdx then
            local poiType, px, py = SafeCall(QuestPOIGetIconInfo, logIdx)
            if px and py and px > 0 and py > 0 then
                tx, ty = px, py
                tMapID = playerMapID
            end
        end
    end

    -- 4. Try C_QuestLog.GetQuestPOIs (Centroid of turn-in POIs)
    if not (tx and ty) and C_QuestLog and C_QuestLog.GetQuestPOIs then
        local pois = SafeCall(C_QuestLog.GetQuestPOIs, questID)
        if pois and type(pois) == "table" and #pois > 0 then
            local sumX, sumY, count = 0, 0, 0
            local poiMapID = nil
            for _, p in ipairs(pois) do
                if p and p.x and p.y and p.x > 0 and p.y > 0 then
                    local pMap = p.mapID or playerMapID
                    if not playerMapID or pMap == playerMapID or count == 0 then
                        poiMapID = pMap
                        sumX = sumX + p.x
                        sumY = sumY + p.y
                        count = count + 1
                    end
                end
            end
            if count > 0 then
                tx = sumX / count
                ty = sumY / count
                tMapID = poiMapID or playerMapID
            end
        end
    end

    return tx, ty, tMapID
end

-- Helper: Locate quest objective center (centroid of quest zone area / spawns / POIs)
local function GetQuestObjectiveLocation(questID)
    if not questID then return nil, nil, nil end

    local wx, wy, uiMapID
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and SafeCall(C_Map.GetBestMapForUnit, "player")

    -- Identify the first incomplete objective index
    local firstIncompleteIdx = nil
    local objectives = (ns.GetQuestObjectives and SafeCall(ns.GetQuestObjectives, questID))
        or (C_QuestLog and C_QuestLog.GetQuestObjectives and SafeCall(C_QuestLog.GetQuestObjectives, questID))
    if objectives and #objectives > 0 then
        for idx, obj in ipairs(objectives) do
            if not obj.finished then
                firstIncompleteIdx = idx
                break
            end
        end
    end

    -- Blizzard Native Objective POIs (Filter out turn-in and already-completed objectives)
    if not (wx and wy) and C_QuestLog and C_QuestLog.GetQuestPOIs then
        local pois = SafeCall(C_QuestLog.GetQuestPOIs, questID)
        if pois and type(pois) == "table" and #pois > 0 then
            -- Pass A: Specific incomplete objective POIs (matches first incomplete objective)
            if firstIncompleteIdx then
                local sumX, sumY, count = 0, 0, 0
                local poiMapID = nil
                for _, p in ipairs(pois) do
                    if p and p.x and p.y and p.x > 0 and p.y > 0 and not p.isTurnIn and not p.completed then
                        if p.objectiveIndex == firstIncompleteIdx then
                            local pMap = p.mapID or playerMapID
                            if not playerMapID or pMap == playerMapID or count == 0 then
                                poiMapID = pMap
                                sumX = sumX + p.x
                                sumY = sumY + p.y
                                count = count + 1
                            end
                        end
                    end
                end
                if count > 0 and poiMapID then
                    wx = sumX / count
                    wy = sumY / count
                    uiMapID = poiMapID
                end
            end

            -- Pass B: Any active objective POI (explicitly excluding isTurnIn and completed)
            if not (wx and wy) then
                local sumX, sumY, count = 0, 0, 0
                local poiMapID = nil
                for _, p in ipairs(pois) do
                    if p and p.x and p.y and p.x > 0 and p.y > 0 and not p.isTurnIn and not p.completed then
                        local pMap = p.mapID or playerMapID
                        if not playerMapID or pMap == playerMapID or count == 0 then
                            poiMapID = pMap
                            sumX = sumX + p.x
                            sumY = sumY + p.y
                            count = count + 1
                        end
                    end
                end
                if count > 0 and poiMapID then
                    wx = sumX / count
                    wy = sumY / count
                    uiMapID = poiMapID
                end
            end
        end
    end

    -- 3. Blizzard C_QuestLog.GetQuestsOnMap: Centroid of all quest pins on map (excluding isTurnIn and isComplete)
    if not (wx and wy) and C_QuestLog and C_QuestLog.GetQuestsOnMap and playerMapID then
        local qList = SafeCall(C_QuestLog.GetQuestsOnMap, playerMapID)
        if qList and type(qList) == "table" then
            local sumX, sumY, count = 0, 0, 0
            for _, q in ipairs(qList) do
                if q.questID == questID and q.x and q.y and q.x > 0 and q.y > 0 and not q.isTurnIn and not q.isComplete then
                    sumX = sumX + q.x
                    sumY = sumY + q.y
                    count = count + 1
                end
            end
            if count > 0 then
                wx = sumX / count
                wy = sumY / count
                uiMapID = playerMapID
            end
        end
    end

    -- 4. Blizzard C_QuestLog.GetNextWaypoint single point fallback
    if not (wx and wy) and C_QuestLog and C_QuestLog.GetNextWaypoint then
        local waypoint = SafeCall(C_QuestLog.GetNextWaypoint, questID)
        if waypoint then
            if waypoint.GetXY then
                wx, wy = waypoint:GetXY()
            elseif waypoint.x and waypoint.y then
                wx, wy = waypoint.x, waypoint.y
            end
            local wpMapID = C_QuestLog.GetNextWaypointMapID and SafeCall(C_QuestLog.GetNextWaypointMapID, questID)
            if wpMapID and wpMapID > 0 then
                uiMapID = wpMapID
            end
        end
    end

    -- 5. Classic QuestPOIGetIconInfo fallback
    if not (wx and wy) and type(QuestPOIGetIconInfo) == "function" then
        local logIndex = (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and SafeCall(C_QuestLog.GetLogIndexForQuestID, questID))
        if logIndex then
            local _, posX, posY = SafeCall(QuestPOIGetIconInfo, logIndex)
            if posX and posY and posX > 0 and posY > 0 then
                wx, wy = posX, posY
                uiMapID = playerMapID
            end
        end
    end

    return wx, wy, uiMapID
end

function WayfinderModule:SetQuestTarget(questID, skipTrackerUpdate, force)
    if currentTarget.isCustom and not force then
        return
    end

    if not questID or questID == 0 then
        self:ClearWaypoint()
        return
    end

    if not force and arrivedQuestIDs[questID] then
        return
    end

    if force then
        arrivedQuestIDs[questID] = nil
    end

    ns.waypointExplicitlyCleared = false

    local title = (C_QuestLog and C_QuestLog.GetTitleForQuestID and SafeCall(C_QuestLog.GetTitleForQuestID, questID))
        or ("Quest #" .. tostring(questID))

    -- Check if quest objectives are genuinely complete
    local objectives = (ns.GetQuestObjectives and SafeCall(ns.GetQuestObjectives, questID))
        or (C_QuestLog and C_QuestLog.GetQuestObjectives and SafeCall(C_QuestLog.GetQuestObjectives, questID))
    local isComplete = false

    if objectives and #objectives > 0 then
        local allDone = true
        for _, obj in ipairs(objectives) do
            if not obj.finished then
                allDone = false
                break
            end
        end
        if allDone then
            isComplete = true
        end
    else
        if C_QuestLog and C_QuestLog.ReadyForTurnIn and SafeCall(C_QuestLog.ReadyForTurnIn, questID) then
            isComplete = true
        elseif C_QuestLog and C_QuestLog.IsComplete and SafeCall(C_QuestLog.IsComplete, questID) then
            isComplete = true
        elseif ns.IsQuestComplete and SafeCall(ns.IsQuestComplete, questID) then
            isComplete = true
        end
    end

    local wx, wy, uiMapID

    if isComplete then
        title = title .. " (Turn-In)"
        local tx, ty, tMap = GetQuestTurnInLocation(questID)
        if tx and ty then
            wx, wy, uiMapID = tx, ty, tMap
        end
    end

    if not (wx and wy) then
        wx, wy, uiMapID = GetQuestObjectiveLocation(questID)
    end

    if wx and wy and uiMapID then
        currentTarget.hasTarget = true
        currentTarget.questID = questID
        currentTarget.uiMapID = uiMapID
        currentTarget.x = wx
        currentTarget.y = wy
        currentTarget.title = title
        currentTarget.isCustom = false
        currentTarget.isComplete = isComplete
        currentTarget.waypointID = nil
        playedArrivalSound = false
        arrivalActive = false
        arrivalTimer = 0
        UpdateTargetWorldCache()
        self:CalculateNavigation()
        self:UpdateFrameVisibility()
        if self.ForceImmediateUpdate then
            self:ForceImmediateUpdate()
        end
    else
        currentTarget.hasTarget = false
        currentTarget.questID = questID
        currentTarget.uiMapID = nil
        currentTarget.x = nil
        currentTarget.y = nil
        currentTarget.title = title
        currentTarget.isCustom = false
        currentTarget.isComplete = isComplete
        currentTarget.waypointID = nil
        arrivalActive = false
        arrivalTimer = 0
        InvalidateTargetWorldCache()
        self:UpdateFrameVisibility()
    end

    if not skipTrackerUpdate and ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
        ns.StandaloneTracker:UpdateTracker()
    end
end

function WayfinderModule:SetWaypointAsTarget(wp)
    if not wp then return end
    ns.waypointExplicitlyCleared = false
    currentTarget.hasTarget = true
    currentTarget.questID = nil
    currentTarget.uiMapID = wp.uiMapID
    currentTarget.x = wp.x
    currentTarget.y = wp.y
    currentTarget.title = wp.title
    currentTarget.isCustom = true
    currentTarget.waypointID = wp.id
    playedArrivalSound = false
    UpdateTargetWorldCache()
    self:CalculateNavigation()
    self:UpdateFrameVisibility()
    if self.ForceImmediateUpdate then
        self:ForceImmediateUpdate()
    end

    if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
        ns.StandaloneTracker:UpdateTracker()
    end
    if self.RefreshMapPins then
        self:RefreshMapPins()
    end
end

function WayfinderModule:AddCustomWaypoint(uiMapID, x, y, title)
    if not x or not y then return nil end
    if x > 1 or y > 1 then
        x = x / 100
        y = y / 100
    end
    uiMapID = uiMapID or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if not uiMapID then return nil end

    waypointCounter = waypointCounter + 1
    local mapName = "Current Zone"
    if C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(uiMapID)
        if info and info.name then mapName = info.name end
    end

    local wpTitle = title or string.format("Waypoint (%.1f, %.1f)", x * 100, y * 100)
    local wp = {
        id = waypointCounter,
        uiMapID = uiMapID,
        mapName = mapName,
        x = x,
        y = y,
        title = wpTitle,
        created = time(),
    }
    table.insert(self.customWaypoints, wp)
    self:SavePersistentWaypoints()
    if self.RefreshMapPins then self:RefreshMapPins() end

    -- Point active arrow directly to the newly added waypoint
    self:SetWaypointAsTarget(wp)

    -- Auto-enable HUD arrow if user has no arrow enabled so they see their point immediately
    if ns.db and ns.db.wayfinder and not ns.db.wayfinder.enableHUDArrow and not ns.db.wayfinder.enableInlineArrow then
        ns.db.wayfinder.enableHUDArrow = true
        self:RefreshState()
    end

    return wp
end

function WayfinderModule:SetCustomWaypoint(uiMapID, x, y, title)
    return self:AddCustomWaypoint(uiMapID, x, y, title)
end

function WayfinderModule:SetClosestWaypoint()
    if #self.customWaypoints == 0 then
        print("|cff00c0ff[Wayfinder]|r No custom waypoints are currently set.")
        return nil
    end

    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not playerMapID then return nil end
    local playerMapPos = C_Map.GetPlayerMapPosition(playerMapID, "player")
    if not playerMapPos then return nil end

    local _, playerWorldPos = (C_Map.GetWorldPosFromMapPos and C_Map.GetWorldPosFromMapPos(playerMapID, playerMapPos))

    local closestWP = nil
    local minDistance = math.huge

    for _, wp in ipairs(self.customWaypoints) do
        local dist = math.huge
        local wpMapPos = CreateVector2D and CreateVector2D(wp.x, wp.y)
        local _, wpWorldPos = (wpMapPos and C_Map.GetWorldPosFromMapPos and C_Map.GetWorldPosFromMapPos(wp.uiMapID, wpMapPos))
        if playerWorldPos and wpWorldPos then
            dist = playerWorldPos:GetDistance(wpWorldPos)
        else
            local px, py = playerMapPos:GetXY()
            local dx = wp.x - px
            local dy = wp.y - py
            dist = math.sqrt(dx * dx + dy * dy) * 1000
        end

        if dist < minDistance then
            minDistance = dist
            closestWP = wp
        end
    end

    if closestWP then
        self:SetWaypointAsTarget(closestWP)
        local distStr = (minDistance >= 1760) and string.format("%.1f mi", minDistance / 1760) or string.format("%d yd", math.floor(minDistance + 0.5))
        print(string.format("|cff00c0ff[Wayfinder]|r Pointing to closest waypoint: |cffffffff%s|r (%s).", closestWP.title, distStr))
        return closestWP
    end
    return nil
end

function WayfinderModule:ClearWaypoint(fromTracker)
    currentTarget.hasTarget = false
    currentTarget.questID = nil
    currentTarget.uiMapID = nil
    currentTarget.x = nil
    currentTarget.y = nil
    currentTarget.title = nil
    currentTarget.isCustom = false
    currentTarget.waypointID = nil
    playedArrivalSound = false
    arrivedSoundTargetKey = nil

    navState.hasTarget = false
    navState.targetKey = nil
    navState.distanceYards = 0
    navState.relativeAngle = 0
    navState.isArrived = false

    InvalidateTargetWorldCache()
    self:StopUpdateTimer()
    if self.RefreshMapPins then self:RefreshMapPins() end
    self:UpdateFrameVisibility()

    -- Clear active quest tracking and Blizzard SuperTracking
    ns.activeQuestID = nil
    ns.waypointExplicitlyCleared = true
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        C_SuperTrack.SetSuperTrackedQuestID(0)
    end

    if not fromTracker and ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
        ns.StandaloneTracker:UpdateTracker()
    end
end

function WayfinderModule:SavePersistentWaypoints()
    if not (ns.db and ns.db.wayfinder) then return end
    ns.db.wayfinder.savedWaypoints = {}
    for _, wp in ipairs(self.customWaypoints) do
        table.insert(ns.db.wayfinder.savedWaypoints, {
            uiMapID = wp.uiMapID,
            mapName = wp.mapName,
            x = wp.x,
            y = wp.y,
            title = wp.title,
        })
    end
end

function WayfinderModule:RemoveWaypointByID(id)
    if not id then return end
    local removedTitle = nil
    for i, wp in ipairs(self.customWaypoints) do
        if wp.id == id then
            removedTitle = wp.title
            table.remove(self.customWaypoints, i)
            break
        end
    end

    self:SavePersistentWaypoints()

    if currentTarget.isCustom and currentTarget.waypointID == id then
        if #self.customWaypoints > 0 then
            self:SetClosestWaypoint()
        else
            self:ClearWaypoint()
        end
    end

    if self.RefreshMapPins then self:RefreshMapPins() end
    if removedTitle then
        print(string.format("|cff00c0ff[Wayfinder]|r Removed waypoint: |cffffffff%s|r.", removedTitle))
    end
end

function WayfinderModule:ClearAllCustomWaypoints()
    self.customWaypoints = {}
    self:SavePersistentWaypoints()
    if self.RefreshMapPins then self:RefreshMapPins() end
    if currentTarget.isCustom then
        self:ClearWaypoint()
    end
    print("|cff00c0ff[Wayfinder]|r All custom waypoints cleared.")
end

function WayfinderModule:ListWaypoints()
    if #self.customWaypoints == 0 then
        print("|cff00c0ff[Wayfinder]|r No waypoints currently active.")
        return
    end
    print(string.format("|cff00c0ff[Wayfinder]|r Active Waypoints (%d):", #self.customWaypoints))
    for i, wp in ipairs(self.customWaypoints) do
        local isActive = (currentTarget.hasTarget and currentTarget.waypointID == wp.id)
        local activeTag = isActive and " |cff00ff00[ACTIVE]|r" or ""
        print(string.format("  #%d: |cffffd100%s|r - (%.1f, %.1f) in %s%s", i, wp.title, wp.x * 100, wp.y * 100, wp.mapName or "Zone", activeTag))
    end
end

function WayfinderModule:OnWaypointArrived(wpID)
    if not wpID then return end
    if #self.customWaypoints > 1 then
        for i, wp in ipairs(self.customWaypoints) do
            if wp.id == wpID then
                local title = wp.title or "Waypoint"
                table.remove(self.customWaypoints, i)
                self:SavePersistentWaypoints()
                if self.RefreshMapPins then self:RefreshMapPins() end
                print(string.format("|cff00c0ff[Wayfinder]|r Arrived at |cffffffff%s|r! Switching to next closest waypoint...", title))
                self:SetClosestWaypoint()
                break
            end
        end
    elseif #self.customWaypoints == 1 then
        local wp = self.customWaypoints[1]
        local title = (wp and wp.title) or "Waypoint"
        self.customWaypoints = {}
        self:SavePersistentWaypoints()
        if self.RefreshMapPins then self:RefreshMapPins() end
        print(string.format("|cff00c0ff[Wayfinder]|r Arrived at destination: |cffffffff%s|r!", title))
        self:ClearWaypoint()
    end
end

function WayfinderModule:HasActiveTarget()
    return currentTarget.hasTarget
end

function WayfinderModule:GetNavigationState()
    return navState
end

-- ---------------------------------------------------------------------------
-- Mathematical Navigation Calculation (Zero-Garbage Cached Engine)
-- ---------------------------------------------------------------------------

function WayfinderModule:CalculateNavigation()
    if not currentTarget.hasTarget or not currentTarget.x or not currentTarget.y then
        navState.hasTarget = false
        return false
    end

    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not playerMapID then return false end

    local playerMapPos = C_Map.GetPlayerMapPosition(playerMapID, "player")
    if not playerMapPos then return false end

    local px, py = playerMapPos:GetXY()
    if not px or not py then return false end

    local playerFacing = (GetPlayerFacing and GetPlayerFacing()) or 0

    -- Position and Facing change checks (using map coordinates instead of restricted GetUnitSpeed)
    local posDiff = 0
    if lastPlayerMapX and lastPlayerMapY then
        posDiff = math.abs(px - lastPlayerMapX) + math.abs(py - lastPlayerMapY)
    else
        posDiff = 1
    end
    local facingDiff = math.abs(playerFacing - lastPlayerFacing)

    local isStationary = (posDiff < 0.00001) and navState.hasTarget

    if isStationary and facingDiff < 0.005 and stationaryElapsed < 1.0 then
        -- Standing still and facing same direction: zero calculation needed!
        stationaryElapsed = stationaryElapsed + updateElapsed
        return true
    elseif isStationary and facingDiff >= 0.005 and stationaryElapsed < 1.0 then
        -- Turning on the spot: position is identical! Recalculate relative angle without C_Map world queries!
        stationaryElapsed = stationaryElapsed + updateElapsed
        lastPlayerFacing = playerFacing

        local relativeAngle = (targetWorldAngle - playerFacing) % (2 * math.pi)
        if relativeAngle > math.pi then
            relativeAngle = relativeAngle - (2 * math.pi)
        elseif relativeAngle < -math.pi then
            relativeAngle = relativeAngle + (2 * math.pi)
        end

        local diff = math.abs(relativeAngle)
        local r, g, b
        if diff <= 0.26 then
            r, g, b = 0.1, 1.0, 0.2
        elseif diff <= 1.31 then
            r, g, b = 1.0, 0.85, 0.1
        else
            r, g, b = 1.0, 0.25, 0.25
        end

        navState.relativeAngle = relativeAngle
        navState.r = r
        navState.g = g
        navState.b = b
        return true
    end

    -- Moving or periodic 1s heartbeat: full position recalculation
    stationaryElapsed = 0
    lastPlayerMapX = px
    lastPlayerMapY = py
    lastPlayerFacing = playerFacing

    -- Verify target world cache is populated
    if not cachedTargetWorldX or cachedTargetMapID ~= (currentTarget.uiMapID or playerMapID) then
        UpdateTargetWorldCache()
    end

    local distanceYards = 0
    local targetAngle = 0

    local _, playerWorldPos = (C_Map.GetWorldPosFromMapPos and C_Map.GetWorldPosFromMapPos(playerMapID, playerMapPos))
    if playerWorldPos and playerWorldPos.x and playerWorldPos.y and cachedTargetWorldX and cachedTargetWorldY then
        local deltaNorth = cachedTargetWorldX - playerWorldPos.x
        local deltaWest = cachedTargetWorldY - playerWorldPos.y
        distanceYards = math.sqrt(deltaNorth * deltaNorth + deltaWest * deltaWest)
        targetAngle = math.atan2(deltaWest, deltaNorth)
    else
        -- Fallback: Normalized Map Coordinates
        local px, py = playerMapPos:GetXY()
        local tx, ty = currentTarget.x, currentTarget.y
        local dx = tx - px
        local dy = ty - py
        local deltaNorth = -dy
        local deltaWest = -dx
        targetAngle = math.atan2(deltaWest, deltaNorth)
        distanceYards = math.sqrt(dx * dx + dy * dy) * 1000
    end

    targetWorldAngle = targetAngle

    local relativeAngle = (targetAngle - playerFacing) % (2 * math.pi)
    if relativeAngle > math.pi then
        relativeAngle = relativeAngle - (2 * math.pi)
    elseif relativeAngle < -math.pi then
        relativeAngle = relativeAngle + (2 * math.pi)
    end

    local diff = math.abs(relativeAngle)
    local r, g, b
    if diff <= 0.26 then
        r, g, b = 0.1, 1.0, 0.2
    elseif diff <= 1.31 then
        r, g, b = 1.0, 0.85, 0.1
    else
        r, g, b = 1.0, 0.25, 0.25
    end

    local threshold = (ns.db and ns.db.wayfinder and ns.db.wayfinder.arrivalThreshold) or 15
    local targetKey = (currentTarget.isCustom and ("wp_" .. tostring(currentTarget.waypointID or 0))) or ("quest_" .. tostring(currentTarget.questID or 0))

    local isArrived = false
    if navState.isArrived and navState.hasTarget and (navState.targetKey == targetKey) then
        isArrived = distanceYards <= (threshold + 10)
    else
        isArrived = distanceYards <= threshold
    end

    if isArrived then
        if arrivedSoundTargetKey ~= targetKey then
            arrivedSoundTargetKey = targetKey
            if ns.db and ns.db.wayfinder and ns.db.wayfinder.playArrivalSound then
                PlaySound((SOUNDKIT and SOUNDKIT.MAP_PING) or 3175, "SFX")
            end
        end
        if not arrivalActive then
            arrivalActive = true
            arrivalTimer = 0
        end
    else
        local resetDist = math.max(80, threshold * 4)
        if distanceYards > resetDist and arrivedSoundTargetKey == targetKey then
            arrivedSoundTargetKey = nil
        end
        arrivalActive = false
        arrivalTimer = 0
    end

    -- Smooth velocity and calculate ETA (taint-free using distance/time delta)
    local now = GetTime()
    if lastEtaDistance and lastEtaTime and (now - lastEtaTime) >= 0.5 then
        local dt = now - lastEtaTime
        local distChange = lastEtaDistance - distanceYards
        if distChange > 0 and dt > 0 then
            local currentSpeed = distChange / dt
            if smoothedSpeed == 0 then
                smoothedSpeed = currentSpeed
            else
                smoothedSpeed = smoothedSpeed * 0.7 + currentSpeed * 0.3
            end
        else
            smoothedSpeed = smoothedSpeed * 0.8
            if smoothedSpeed < 0.2 then smoothedSpeed = 0 end
        end
        lastEtaDistance = distanceYards
        lastEtaTime = now
    elseif not lastEtaTime then
        lastEtaDistance = distanceYards
        lastEtaTime = now
    end

    local etaStr = ""
    if smoothedSpeed > 0.8 and not isArrived then
        local sec = distanceYards / smoothedSpeed
        if sec < 60 then
            etaStr = string.format("%ds", math.floor(sec + 0.5))
        elseif sec < 3600 then
            etaStr = string.format("%dm %02ds", math.floor(sec / 60), math.floor(sec % 60))
        else
            etaStr = string.format("%dh %02dm", math.floor(sec / 3600), math.floor((sec % 3600) / 60))
        end
    end
    navState.etaFormatted = etaStr

    navState.hasTarget = true
    navState.targetKey = targetKey
    navState.distanceYards = distanceYards
    navState.relativeAngle = relativeAngle
    navState.isArrived = isArrived
    navState.r = r
    navState.g = g
    navState.b = b
    navState.title = currentTarget.title or ""

    return true
end

-- ---------------------------------------------------------------------------
-- Arrow Textures & Asset Resolver
-- ---------------------------------------------------------------------------

local ARROW_TEXTURES = {
    minimal = "Interface\\AddOns\\BleakfibersQuestTracker-Forever\\Media\\Textures\\wayfinder_minimal.tga",
    classic = "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW",
}

function WayfinderModule:GetArrowTexture()
    local style = (ns.db and ns.db.wayfinder and ns.db.wayfinder.arrowStyle) or "auto"
    if style == "auto" or not ARROW_TEXTURES[style] then
        return ARROW_TEXTURES.minimal
    end
    return ARROW_TEXTURES[style]
end

-- ---------------------------------------------------------------------------
-- HUD Arrow UI Frame
-- ---------------------------------------------------------------------------

function WayfinderModule:CreateHUDFrame()
    if self.hudFrame then return self.hudFrame end

    local frame = CreateFrame("Button", "BleakfiberWayfinderHUD", UIParent, (BackdropTemplateMixin and "BackdropTemplate") or nil)
    frame:SetSize(56, 56)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local pos = ns.db and ns.db.wayfinder and ns.db.wayfinder.hudPosition
    if pos and pos.point and pos.x and pos.y then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    end

    frame:SetScript("OnDragStart", function(self)
        if ns.db and ns.db.wayfinder and ns.db.wayfinder.locked then return end
        self:StartMoving()
        self.isMoving = true
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.isMoving = false
        local pt, _, relPt, x, y = self:GetPoint()
        if ns.db and ns.db.wayfinder then
            ns.db.wayfinder.hudPosition = { point = pt, relativePoint = relPt, x = math.floor(x), y = math.floor(y) }
        end
    end)

    frame:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            WayfinderModule:OpenHUDContextMenu(self)
        end
    end)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetVertexColor(0, 0, 0, 0.45)
    bg:SetShown(ns.db and ns.db.wayfinder and ns.db.wayfinder.showBackdrop == true)
    frame.bg = bg

    local arrow = frame:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(54, 54)
    arrow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    arrow:SetTexture(WayfinderModule:GetArrowTexture())
    frame.arrow = arrow

    local distText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    distText:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    distText:SetJustifyH("CENTER")
    distText:SetShadowColor(0, 0, 0, 1)
    distText:SetShadowOffset(1, -1)
    frame.distText = distText

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cff00c0ffWayfinder Navigation|r", 1, 1, 1)
        if currentTarget.hasTarget then
            GameTooltip:AddLine(currentTarget.title or "Active Objective", 1, 0.82, 0)
            local distStr = string.format("%d yd", math.floor(navState.distanceYards + 0.5))
            GameTooltip:AddDoubleLine("Distance:", distStr, 0.8, 0.8, 0.8, 1, 1, 1)
            if #WayfinderModule.customWaypoints > 1 then
                GameTooltip:AddLine(string.format("|cff00ff00%d active custom waypoints|r", #WayfinderModule.customWaypoints), 0.8, 0.8, 0.8)
            end
        else
            if currentTarget.title then
                GameTooltip:AddLine(currentTarget.title, 1, 0.82, 0)
                GameTooltip:AddLine("No coordinates available from server.", 0.8, 0.8, 0.8)
            else
                GameTooltip:AddLine("No active waypoint set.", 0.8, 0.8, 0.8)
            end
            GameTooltip:AddLine("Type |cff00c0ff/way <x> <y>|r to set a manual destination.", 0.6, 0.8, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffaaaaaaLeft-Click Drag: Move Arrow|r", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("|cffaaaaaaRight-Click: Wayfinder Menu|r", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame:Hide()
    self.hudFrame = frame
    self:ApplyHUDSettings()
    return frame
end

function WayfinderModule:ApplyHUDScale()
    if not self.hudFrame then return end
    local scale = (ns.db and ns.db.wayfinder and ns.db.wayfinder.arrowScale) or 1.0
    self.hudFrame:SetScale(scale)
end

function WayfinderModule:ApplyHUDSettings()
    if not self.hudFrame then return end
    self:ApplyHUDScale()
    if self.hudFrame.bg then
        self.hudFrame.bg:SetShown(ns.db and ns.db.wayfinder and ns.db.wayfinder.showBackdrop == true)
    end
    if self.hudFrame.arrow then
        self.hudFrame.arrow:SetTexture(self:GetArrowTexture())
    end
end

function WayfinderModule:OpenHUDContextMenu(anchor)
    local hasCustom = #WayfinderModule.customWaypoints > 0
    local menu = {
        { text = "|cff00c0ffWayfinder Navigation|r", isTitle = true, notCheckable = true },
        {
            text = (ns.db and ns.db.wayfinder and ns.db.wayfinder.locked) and "Unlock Arrow Position" or "Lock Arrow Position",
            notCheckable = true,
            func = function()
                if ns.db and ns.db.wayfinder then
                    ns.db.wayfinder.locked = not ns.db.wayfinder.locked
                end
            end,
        },
        {
            text = "Reset Arrow Position",
            notCheckable = true,
            func = function()
                if WayfinderModule.hudFrame then
                    WayfinderModule.hudFrame:ClearAllPoints()
                    WayfinderModule.hudFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
                    if ns.db and ns.db.wayfinder then
                        ns.db.wayfinder.hudPosition = { point = "CENTER", x = 0, y = 160 }
                    end
                end
            end,
        },
        {
            text = "Show Backdrop Circle",
            checked = function() return ns.db and ns.db.wayfinder and ns.db.wayfinder.showBackdrop == true end,
            func = function()
                if ns.db and ns.db.wayfinder then
                    ns.db.wayfinder.showBackdrop = not (ns.db.wayfinder.showBackdrop == true)
                    WayfinderModule:ApplyHUDSettings()
                end
            end,
        },
        {
            text = "Hide Arrow in Combat",
            checked = function() return not (ns.db and ns.db.wayfinder and ns.db.wayfinder.hideInCombat == false) end,
            func = function()
                if ns.db and ns.db.wayfinder then
                    ns.db.wayfinder.hideInCombat = not (ns.db.wayfinder.hideInCombat ~= false)
                    WayfinderModule:UpdateFrameVisibility()
                end
            end,
        },
        {
            text = "Point to Closest Waypoint (/cway)",
            notCheckable = true,
            disabled = not hasCustom,
            func = function()
                WayfinderModule:SetClosestWaypoint()
            end,
        },
        {
            text = "List Active Waypoints (/way list)",
            notCheckable = true,
            disabled = not hasCustom,
            func = function()
                WayfinderModule:ListWaypoints()
            end,
        },
        {
            text = "Clear Current Target",
            notCheckable = true,
            disabled = not currentTarget.hasTarget,
            func = function()
                WayfinderModule:ClearWaypoint()
            end,
        },
        {
            text = "Clear All Custom Waypoints",
            notCheckable = true,
            disabled = not hasCustom,
            func = function()
                WayfinderModule:ClearAllCustomWaypoints()
            end,
        },
        {
            text = "Open Wayfinder Settings",
            notCheckable = true,
            func = function()
                if ns.Config and ns.Config.ToggleConfigFrame then
                    ns.Config:ToggleConfigFrame()
                end
            end,
        },
        { text = "Close", notCheckable = true, func = function() end },
    }

    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(anchor or self.hudFrame or UIParent, function(ownerRegion, rootDescription)
            for _, item in ipairs(menu) do
                if item.isTitle then
                    if rootDescription.CreateTitle then
                        rootDescription:CreateTitle(item.text)
                    end
                elseif item.text and item.text ~= "" then
                    if item.text == "Close" then
                        if rootDescription.CreateDivider then rootDescription:CreateDivider() end
                        rootDescription:CreateButton(item.text, function() end)
                    else
                        local btn = rootDescription:CreateButton(item.text, function()
                            if item.func then item.func() end
                        end)
                        if item.disabled and btn and btn.SetEnabled then
                            btn:SetEnabled(false)
                        end
                    end
                end
            end
        end)
        return
    end

    local menuFrame = CreateFrame("Frame", "BleakfiberWayfinderContextMenu", UIParent, "UIDropDownMenuTemplate")
    if EasyMenu then
        EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
    elseif ToggleDropDownMenu and UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(menuFrame, function(_, level)
            for _, item in ipairs(menu) do
                UIDropDownMenu_AddButton(item, level)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
    end
end

-- ---------------------------------------------------------------------------
-- Update Loop & Presentation Sync (Zero-Garbage & Idle Sleep)
-- ---------------------------------------------------------------------------

function WayfinderModule:ShouldShowHUDArrow()
    if not (ns.db and ns.db.wayfinder and ns.db.wayfinder.enableHUDArrow) then
        return false
    end

    if self.previewMode then
        return true
    end

    local hideInCombat = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.hideInCombat == false)
    if hideInCombat and (self.inCombat or (InCombatLockdown and InCombatLockdown())) then
        return false
    end

    if not currentTarget.hasTarget then
        return false
    end

    return true
end

function WayfinderModule:UpdateIdleState()
    local isHudEnabled = ns.db and ns.db.wayfinder and ns.db.wayfinder.enableHUDArrow
    local isInlineEnabled = ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow

    if self.previewMode and isHudEnabled and self.hudFrame then
        if not self.hudFrame:IsShown() then
            self.hudFrame:Show()
        end
        self.hudFrame.arrow:SetRotation(0)
        self.hudFrame.arrow:SetVertexColor(0.1, 1.0, 0.2, 1.0)
        if ns.db and ns.db.wayfinder and ns.db.wayfinder.showDistance then
            self.hudFrame.distText:Show()
            self.hudFrame.distText:SetText("|cff00c0ff(Preview)|r")
        else
            self.hudFrame.distText:Hide()
        end
        return
    end

    if self.hudFrame and not self.previewMode then
        self.hudFrame:Hide()
    end

    if isInlineEnabled and ns.activeQuestID and ns.StandaloneTracker and ns.StandaloneTracker.activeBlocks then
        local block = ns.StandaloneTracker.activeBlocks[ns.activeQuestID]
        if block and block.header and block.header.wayfinderArrow and block.header.wayfinderArrow:IsShown() then
            block.header.wayfinderArrow:SetRotation(0)
            block.header.wayfinderArrow:SetVertexColor(1.0, 0.82, 0.0, 0.85)
        end
        lastInlineRotation = 0
        lastInlineR, lastInlineG, lastInlineB = 1.0, 0.82, 0.0
    end
end

function WayfinderModule:StartUpdateTimer()
    if self.previewMode then
        self:StopUpdateTimer()
        return
    end

    local isHudEnabled = ns.db and ns.db.wayfinder and ns.db.wayfinder.enableHUDArrow
    local isInlineEnabled = ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow
    if not (isHudEnabled or isInlineEnabled) then
        self:StopUpdateTimer()
        return
    end

    local hideInCombat = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.hideInCombat == false)
    if hideInCombat and (self.inCombat or (InCombatLockdown and InCombatLockdown())) then
        self:StopUpdateTimer()
        return
    end

    if not currentTarget.hasTarget then
        -- When idle with no target, ensure arrow is hidden and sleep completely!
        self:UpdateIdleState()
        self:StopUpdateTimer()
        return
    end

    if self.updateFrame and not self.isUpdating then
        self.isUpdating = true
        self.updateFrame:SetScript("OnUpdate", function(_, dt)
            WayfinderModule:OnUpdate(dt)
        end)
    end
end

function WayfinderModule:StopUpdateTimer()
    if self.updateFrame and self.isUpdating then
        self.updateFrame:SetScript("OnUpdate", nil)
        self.isUpdating = false
    end
end

function WayfinderModule:UpdateFrameVisibility()
    if not self.hudFrame then return end

    if self:ShouldShowHUDArrow() then
        if not self.hudFrame:IsShown() then
            self.hudFrame:Show()
        end
        if self.previewMode then
            self.hudFrame.arrow:SetRotation(0)
            self.hudFrame.arrow:SetVertexColor(0.1, 1.0, 0.2, 1.0)
            if ns.db and ns.db.wayfinder and ns.db.wayfinder.showDistance then
                self.hudFrame.distText:Show()
                self.hudFrame.distText:SetText("|cff00c0ff(Preview)|r")
            else
                self.hudFrame.distText:Hide()
            end
            self:StopUpdateTimer()
        else
            self:StartUpdateTimer()
        end
    else
        if self.hudFrame:IsShown() then
            self.hudFrame:Hide()
        end
        self:StopUpdateTimer()
    end
end

function WayfinderModule:OnUpdate(dt)
    updateElapsed = updateElapsed + dt
    if updateElapsed < 0.075 then return end
    updateElapsed = 0

    local isHudEnabled = ns.db and ns.db.wayfinder and ns.db.wayfinder.enableHUDArrow
    local isInlineEnabled = ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow

    if not (isHudEnabled or isInlineEnabled) then
        if self.hudFrame and self.hudFrame:IsShown() then
            self.hudFrame:Hide()
        end
        self:StopUpdateTimer()
        return
    end

    local hideInCombat = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.hideInCombat == false)
    if hideInCombat and (self.inCombat or (InCombatLockdown and InCombatLockdown())) then
        self:UpdateFrameVisibility()
        return
    end

    if not currentTarget.hasTarget then
        self:UpdateFrameVisibility()
        return
    end

    local success = self:CalculateNavigation()
    if not success then return end

    -- Handle Arrival Auto-Clear Timer
    if arrivalActive and navState.isArrived then
        local clearDelay = (ns.db and ns.db.wayfinder and ns.db.wayfinder.arrivalClearDelay)
        if clearDelay == nil then clearDelay = 5 end

        if clearDelay > 0 then
            arrivalTimer = arrivalTimer + dt
            if arrivalTimer >= clearDelay then
                arrivalActive = false
                arrivalTimer = 0

                if currentTarget.isCustom then
                    local wpID = currentTarget.waypointID
                    if wpID then
                        self:OnWaypointArrived(wpID)
                    else
                        self:ClearWaypoint()
                    end
                elseif currentTarget.questID then
                    local qID = currentTarget.questID
                    arrivedQuestIDs[qID] = true
                    print(string.format("|cff00c0ff[Wayfinder]|r Arrived at |cffffffff%s|r!", currentTarget.title or "Quest Target"))
                    self:ClearWaypoint()
                else
                    self:ClearWaypoint()
                end
                return
            end
        end
    end

    -- 1. Update Floating HUD Arrow
    if isHudEnabled and self.hudFrame then
        if not self.hudFrame:IsShown() then
            self.hudFrame:Show()
        end

        if math.abs(navState.relativeAngle - lastRotationAngle) > 0.008 then
            self.hudFrame.arrow:SetRotation(navState.relativeAngle)
            lastRotationAngle = navState.relativeAngle
        end

        if navState.r ~= lastColorR or navState.g ~= lastColorG or navState.b ~= lastColorB then
            self.hudFrame.arrow:SetVertexColor(navState.r, navState.g, navState.b, 1.0)
            lastColorR, lastColorG, lastColorB = navState.r, navState.g, navState.b
        end

        local showDist = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.showDistance == false)
        local showETA = (ns.db and ns.db.wayfinder and ns.db.wayfinder.showETA == true) and (navState.etaFormatted and navState.etaFormatted ~= "")

        if showDist or showETA then
            self.hudFrame.distText:Show()
            if navState.isArrived then
                if lastDistArrived ~= true then
                    lastDistArrived = true
                    lastDistNumber = -1
                    lastDistFormatted = "|cff00ff00Arrived!|r"
                    self.hudFrame.distText:SetText(lastDistFormatted)
                end
            else
                lastDistArrived = false
                local yards = math.floor(navState.distanceYards + 0.5)
                local etaPart = showETA and string.format(" |cff88ccff(%s)|r", navState.etaFormatted) or ""
                if yards ~= lastDistNumber or lastEtaFormatted ~= (navState.etaFormatted or "") then
                    lastDistNumber = yards
                    lastEtaFormatted = navState.etaFormatted or ""
                    if showDist and yards >= 1760 then
                        local miles = math.floor((yards / 1760) * 10 + 0.5) / 10
                        lastDistFormatted = string.format("%.1f mi%s", miles, etaPart)
                    elseif showDist then
                        lastDistFormatted = string.format("%d yd%s", yards, etaPart)
                    else
                        lastDistFormatted = string.format("|cff88ccffETA: %s|r", navState.etaFormatted)
                    end
                    self.hudFrame.distText:SetText(lastDistFormatted)
                end
            end
        else
            self.hudFrame.distText:Hide()
        end
    end

    -- 2. Update Inline Tracker Mini-Arrow for the Active Quest
    if isInlineEnabled and ns.activeQuestID and ns.StandaloneTracker and ns.StandaloneTracker.activeBlocks then
        local block = ns.StandaloneTracker.activeBlocks[ns.activeQuestID]
        if block and block.header and block.header.wayfinderArrow and block.header.wayfinderArrow:IsShown() then
            if math.abs(navState.relativeAngle - lastInlineRotation) > 0.008 then
                block.header.wayfinderArrow:SetRotation(navState.relativeAngle)
                lastInlineRotation = navState.relativeAngle
            end
            if navState.r ~= lastInlineR or navState.g ~= lastInlineG or navState.b ~= lastInlineB then
                block.header.wayfinderArrow:SetVertexColor(navState.r, navState.g, navState.b, 1.0)
                lastInlineR, lastInlineG, lastInlineB = navState.r, navState.g, navState.b
            end
        end
    end
end

function WayfinderModule:RefreshState()
    self:ApplyHUDSettings()
    self:UpdateFrameVisibility()

    if ns.db and ns.db.wayfinder and ns.db.wayfinder.autoTrackActiveQuest and ns.activeQuestID and not currentTarget.isCustom then
        self:SetQuestTarget(ns.activeQuestID)
    end
end

function WayfinderModule:ForceImmediateUpdate()
    updateElapsed = 1.0
    lastRotationAngle = -999
    lastDistNumber = -999
    lastDistFormatted = ""
    lastDistArrived = nil
    lastColorR, lastColorG, lastColorB = -1, -1, -1
    lastInlineRotation = -999
    lastInlineR, lastInlineG, lastInlineB = -1, -1, -1

    self:StartUpdateTimer()
    self:CalculateNavigation()
    self:OnUpdate(0.1)
end

function WayfinderModule:TogglePreviewMode()
    self.previewMode = not self.previewMode
    if self.previewMode then
        print("|cff00c0ff[Wayfinder]|r Arrow preview active (drag to reposition). Run |cffffd100/way test|r again to exit preview.")
    else
        print("|cff00c0ff[Wayfinder]|r Arrow preview closed.")
    end
    self:UpdateFrameVisibility()
end

-- ---------------------------------------------------------------------------
-- Map Pins & Coordinates Overlay Engine
-- ---------------------------------------------------------------------------

local worldMapPins = {}
local coordsFrame = nil

local function ApplyPinTexture(icon, isActive)
    if not icon then return end

    -- 1. Modern Retail Waypoint Atlas (10.0+ / 11.0 / Dragonflight / WoW Forever)
    local atlas = isActive and "Waypoint_MapPin_Green" or "Waypoint_MapPin_Orange"
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then
        atlas = "Waypoint-MapPin-ChatIcon"
    end
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then
        atlas = "poi-travel-waypoint"
    end

    if icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        icon:SetAtlas(atlas, true)
        icon:SetTexCoord(0, 1, 0, 1)
        if isActive then
            icon:SetVertexColor(0.2, 1.0, 0.3, 1.0)
        else
            icon:SetVertexColor(1.0, 0.85, 0.2, 1.0)
        end
        return
    end

    -- 2. Universal High-Contrast Fallback (Minimap POI Pin / Beacon, exists in all WoW clients)
    icon:SetTexture("Interface\\Minimap\\POIIcons")
    icon:SetTexCoord(0.5, 0.625, 0.375, 0.5)
    if isActive then
        icon:SetVertexColor(0.2, 1.0, 0.3, 1.0)
    else
        icon:SetVertexColor(1.0, 0.85, 0.2, 1.0)
    end
end

local function GetOrCreateWorldMapPin(parent)
    for _, pin in ipairs(worldMapPins) do
        if not pin:IsShown() then
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent)
    pin:SetSize(24, 24)
    pin:SetHitRectInsets(-8, -8, -8, -8)
    pin:SetFrameStrata("TOOLTIP")
    pin:SetFrameLevel(9999)
    pin:EnableMouse(true)
    pin:RegisterForClicks("AnyUp", "AnyDown")

    local glow = pin:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER", pin, "CENTER", 0, 0)
    glow:SetSize(30, 30)
    glow:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    glow:SetVertexColor(0, 0, 0, 0.7)
    pin.glow = glow

    local icon = pin:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetAllPoints(pin)
    ApplyPinTexture(icon, false)
    pin.icon = icon

    pin:SetScript("OnEnter", function(self)
        if not self.wp then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cff00c0ff[Wayfinder Waypoint]|r", 1, 1, 1)
        GameTooltip:AddLine(self.wp.title or "Custom Destination", 1, 0.82, 0)
        GameTooltip:AddDoubleLine("Coords:", string.format("%.1f, %.1f", self.wp.x * 100, self.wp.y * 100), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Zone:", self.wp.mapName or "Unknown", 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Left-Click: Set Active Waypoint|r", 0.6, 0.8, 1)
        GameTooltip:AddLine("|cffff8800Right-Click: Remove Waypoint|r", 1, 0.6, 0.4)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local lastClickTime = 0
    local function HandlePinClick(self, button)
        if not self.wp then return end
        local now = GetTime()
        if now - lastClickTime < 0.25 then return end
        lastClickTime = now

        if button == "RightButton" then
            local wpID = self.wp.id
            WayfinderModule:RemoveWaypointByID(wpID)
            if GameTooltip:IsShown() and GameTooltip:GetOwner() == self then
                GameTooltip:Hide()
            end
        else
            WayfinderModule:SetWaypointAsTarget(self.wp)
            print(string.format("|cff00c0ff[Wayfinder]|r Active waypoint set to: |cffffffff%s|r.", self.wp.title))
            if WayfinderModule.RefreshMapPins then
                WayfinderModule:RefreshMapPins()
            end
        end
    end

    pin:SetScript("OnMouseUp", function(self, button)
        HandlePinClick(self, button)
    end)
    pin:SetScript("OnClick", function(self, button)
        HandlePinClick(self, button)
    end)

    table.insert(worldMapPins, pin)
    return pin
end

function WayfinderModule:RefreshMapPins()
    local enabled = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.showMapPins == false)

    -- 1. Refresh World Map Pins
    for _, pin in ipairs(worldMapPins) do
        pin:Hide()
    end

    if enabled and WorldMapFrame and WorldMapFrame:IsShown() and #self.customWaypoints > 0 then
        local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
        local currentMapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
        if canvas and currentMapID then
            local cWidth = canvas:GetWidth()
            local cHeight = canvas:GetHeight()
            if cWidth and cHeight and cWidth > 50 and cHeight > 50 then
                for _, wp in ipairs(self.customWaypoints) do
                    if wp.uiMapID == currentMapID then
                        local pin = GetOrCreateWorldMapPin(canvas)
                        pin.wp = wp
                        pin:ClearAllPoints()
                        pin:SetPoint("CENTER", canvas, "TOPLEFT", wp.x * cWidth, -wp.y * cHeight)
                        local isActive = (currentTarget.hasTarget and currentTarget.waypointID == wp.id)
                        ApplyPinTexture(pin.icon, isActive)
                        if isActive then
                            pin:SetSize(28, 28)
                            if pin.glow then pin.glow:SetSize(34, 34) end
                        else
                            pin:SetSize(24, 24)
                            if pin.glow then pin.glow:SetSize(30, 30) end
                        end
                        pin:Show()
                    end
                end
            end
        end
    end

    if _G["BleakfiberWayfinderMinimapPin"] then
        _G["BleakfiberWayfinderMinimapPin"]:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Player & Cursor Coordinates Display (World Map)
-- ---------------------------------------------------------------------------

function WayfinderModule:UpdateCoordinatesDisplay()
    local enabled = (ns.db and ns.db.wayfinder and ns.db.wayfinder.showCoordinates == true)
    if not enabled then
        if coordsFrame then coordsFrame:Hide() end
        return
    end

    if not coordsFrame and WorldMapFrame then
        local cf = CreateFrame("Frame", "BleakfiberWayfinderCoords", WorldMapFrame)
        cf:SetFrameStrata("HIGH")
        cf:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 20)
        cf:SetSize(320, 20)
        cf:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMLEFT", 12, 10)
        cf:EnableMouse(false)

        local text = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", cf, "LEFT", 0, 0)
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
        cf.text = text

        local elapsed = 0
        cf:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed < 0.1 then return end
            elapsed = 0

            if not WorldMapFrame:IsShown() then return end
            local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
            if not mapID then
                self.text:SetText("")
                return
            end

            -- Player Coordinates
            local playerText = "Player: --.-, --.-"
            local playerPos = C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
            if playerPos then
                local px, py = playerPos:GetXY()
                if px and py and px > 0 and py > 0 then
                    playerText = string.format("Player: |cffffffff%.1f, %.1f|r", px * 100, py * 100)
                end
            end

            -- Cursor Coordinates
            local cursorText = "Cursor: --.-, --.-"
            if WorldMapFrame.GetNormalizedCursorPosition then
                local cx, cy = WorldMapFrame:GetNormalizedCursorPosition()
                if cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
                    cursorText = string.format("Cursor: |cffffffff%.1f, %.1f|r", cx * 100, cy * 100)
                end
            end

            self.text:SetText(string.format("%s   %s", playerText, cursorText))
        end)
        coordsFrame = cf
    end

    if coordsFrame then
        coordsFrame:SetShown(WorldMapFrame and WorldMapFrame:IsShown())
    end
end

local mapWaypointBtn = nil
function WayfinderModule:UpdateMapWaypointButton()
    if not mapWaypointBtn and WorldMapFrame then
        local btn = CreateFrame("Button", "BleakfiberWayfinderMapWaypointBtn", WorldMapFrame, (BackdropTemplateMixin and "BackdropTemplate"))
        btn:SetFrameStrata("HIGH")
        btn:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 25)
        btn:SetSize(86, 20)
        btn:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMLEFT", 12, 32)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false,
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        btn:SetBackdropColor(0.08, 0.10, 0.14, 0.90)
        btn:SetBackdropBorderColor(0.25, 0.55, 0.85, 0.80)

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("CENTER")
        t:SetText("+ Waypoint")
        btn.text = t

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.18, 0.28, 0.45, 1.0)
            self:SetBackdropBorderColor(0.40, 0.80, 1.0, 1.0)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Wayfinder Waypoints", 0.0, 0.75, 1.0)
            GameTooltip:AddLine("Click to open the Paste Waypoints dialog.", 1, 1, 1)
            GameTooltip:AddLine("Tip: Alt-Click anywhere on the map to add a waypoint.", 0.7, 0.85, 1.0)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.08, 0.10, 0.14, 0.90)
            self:SetBackdropBorderColor(0.25, 0.55, 0.85, 0.80)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function()
            WayfinderModule:OpenPasteDialog()
        end)
        mapWaypointBtn = btn
    end

    if mapWaypointBtn then
        mapWaypointBtn:SetShown(WorldMapFrame and WorldMapFrame:IsShown())
    end
end

-- ---------------------------------------------------------------------------
-- World Map Alt-Click Waypoint Handler
-- ---------------------------------------------------------------------------

local lastAltClickTime = 0
local function HandleWorldMapClick(self, button)
    if button ~= "LeftButton" or not IsAltKeyDown() then return end

    local now = GetTime()
    if (now - lastAltClickTime) < 0.25 then return end
    lastAltClickTime = now

    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not mapID then return end

    local cx, cy
    if WorldMapFrame.GetNormalizedCursorPosition then
        cx, cy = WorldMapFrame:GetNormalizedCursorPosition()
    else
        local canvas = (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()) or WorldMapFrame.ScrollContainer or _G["WorldMapButton"]
        if canvas and canvas.GetEffectiveScale then
            local scale = canvas:GetEffectiveScale()
            local curX, curY = GetCursorPosition()
            curX = curX / scale
            curY = curY / scale
            local left = canvas:GetLeft() or 0
            local top = canvas:GetTop() or 0
            local width = canvas:GetWidth() or 1
            local height = canvas:GetHeight() or 1
            cx = (curX - left) / width
            cy = (top - curY) / height
        end
    end

    if cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
        local x = math.floor(cx * 1000 + 0.5) / 10
        local y = math.floor(cy * 1000 + 0.5) / 10
        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        local mapName = mapInfo and mapInfo.name or "Map"
        local title = string.format("%s (%.1f, %.1f)", mapName, x, y)
        local wp = WayfinderModule:AddCustomWaypoint(mapID, x, y, title)
        if wp then
            WayfinderModule:SetWaypointAsTarget(wp)
            print(string.format("|cff00c0ff[Wayfinder]|r Waypoint dropped at (%.1f, %.1f) in %s.", x, y, mapName))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Paste Waypoints Dialog GUI
-- ---------------------------------------------------------------------------

function WayfinderModule:CreatePasteDialog()
    if self.pasteDialog then return end

    local f = CreateFrame("Frame", "BleakfiberWayfinderPasteDialog", UIParent, (BackdropTemplateMixin and "BackdropTemplate"))
    f:SetSize(440, 330)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropColor(0.06, 0.08, 0.12, 0.95)
    f:SetBackdropBorderColor(0.20, 0.50, 0.85, 0.90)

    -- Header bar
    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    header:SetHeight(28)
    header:SetColorTexture(0.10, 0.14, 0.22, 0.95)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", header, "LEFT", 10, 0)
    title:SetText("Wayfinder - Paste Waypoints")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Subtitle
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -8)
    subtitle:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -10, -8)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Paste coordinate lines or /way commands below (one per line):")

    -- ScrollFrame container
    local scrollBox = CreateFrame("Frame", nil, f, (BackdropTemplateMixin and "BackdropTemplate"))
    scrollBox:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
    scrollBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 44)
    scrollBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    scrollBox:SetBackdropColor(0.02, 0.03, 0.05, 0.90)
    scrollBox:SetBackdropBorderColor(0.25, 0.30, 0.40, 0.80)

    local scrollFrame = CreateFrame("ScrollFrame", "BleakfiberWayfinderPasteScrollFrame", scrollBox, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", scrollBox, "BOTTOMRIGHT", -26, 6)

    local editBox = CreateFrame("EditBox", "BleakfiberWayfinderPasteEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(50000)
    editBox:EnableMouse(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth() or 380)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)

    scrollFrame:SetScrollChild(editBox)

    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        if editBox and w and w > 0 then
            editBox:SetWidth(w - 10)
        end
    end)

    scrollBox:EnableMouse(true)
    scrollBox:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)

    -- Add Waypoints Button
    local addBtn = CreateFrame("Button", nil, f, (BackdropTemplateMixin and "BackdropTemplate"))
    addBtn:SetSize(116, 22)
    addBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    addBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    addBtn:SetBackdropColor(0.12, 0.30, 0.18, 0.90)
    addBtn:SetBackdropBorderColor(0.20, 0.70, 0.35, 0.90)
    local addText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addText:SetPoint("CENTER")
    addText:SetText("Add Waypoints")
    addBtn.text = addText

    addBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.45, 0.28, 1.0)
    end)
    addBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.30, 0.18, 0.90)
    end)
    addBtn:SetScript("OnClick", function()
        local raw = editBox:GetText() or ""
        local lines = {}
        for line in raw:gmatch("[^\r\n;]+") do
            line = line:gsub("^%s*(.-)%s*$", "%1")
            if line ~= "" then
                table.insert(lines, line)
            end
        end

        local added = 0
        for _, line in ipairs(lines) do
            local wp = WayfinderModule:ParseAndAddWaypoint(line)
            if wp then added = added + 1 end
        end

        if added > 0 then
            print(string.format("|cff00c0ff[Wayfinder]|r Successfully parsed and added %d waypoints (%d active total).",
                added, #WayfinderModule.customWaypoints))
            WayfinderModule:SetClosestWaypoint()
            editBox:SetText("")
            f:Hide()
        else
            print("|cff00c0ff[Wayfinder]|r No valid coordinates found. Format: [Zone] <x> <y> [description]")
        end
    end)

    -- Clear Button
    local clearBtn = CreateFrame("Button", nil, f, (BackdropTemplateMixin and "BackdropTemplate"))
    clearBtn:SetSize(70, 22)
    clearBtn:SetPoint("LEFT", addBtn, "RIGHT", 10, 0)
    clearBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    clearBtn:SetBackdropColor(0.18, 0.20, 0.24, 0.90)
    clearBtn:SetBackdropBorderColor(0.35, 0.40, 0.48, 0.80)
    local clearText = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clearText:SetPoint("CENTER")
    clearText:SetText("Clear")
    clearBtn.text = clearText
    clearBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.28, 0.34, 1.0)
    end)
    clearBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.18, 0.20, 0.24, 0.90)
    end)
    clearBtn:SetScript("OnClick", function()
        editBox:SetText("")
        editBox:SetFocus()
    end)

    -- Close Button
    local cancelBtn = CreateFrame("Button", nil, f, (BackdropTemplateMixin and "BackdropTemplate"))
    cancelBtn:SetSize(70, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    cancelBtn:SetBackdropColor(0.18, 0.20, 0.24, 0.90)
    cancelBtn:SetBackdropBorderColor(0.35, 0.40, 0.48, 0.80)
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Close")
    cancelBtn.text = cancelText
    cancelBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.28, 0.34, 1.0)
    end)
    cancelBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.18, 0.20, 0.24, 0.90)
    end)
    cancelBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    if _G["UISpecialFrames"] then
        table.insert(_G["UISpecialFrames"], "BleakfiberWayfinderPasteDialog")
    end

    f:Hide()
    self.pasteDialog = f
    self.pasteEditBox = editBox
end

function WayfinderModule:OpenPasteDialog()
    if not self.pasteDialog then
        self:CreatePasteDialog()
    end
    self.pasteDialog:Show()
    if self.pasteEditBox then
        self.pasteEditBox:SetFocus()
    end
end

-- ---------------------------------------------------------------------------
-- Slash Commands: /way & /cway (Multi-Line & Paste Support)
-- ---------------------------------------------------------------------------

function WayfinderModule:ParseAndAddWaypoint(text)
    text = (text and text:gsub("^%s*(.-)%s*$", "%1")) or ""
    text = text:gsub("^/[%a%d]+%s*", "")
    text = text:gsub("^%s*(.-)%s*$", "%1")
    if text == "" then return nil end

    local xStr, yStr, desc
    local uiMapID = nil

    -- 1. Try matching: /way <x> <y> [description] (e.g. 45.2 60.1 or 45.2, 60.1)
    xStr, yStr, desc = text:match("^(%d+%.?%d*)%s*[,%s]%s*(%d+%.?%d*)%s*(.*)$")

    -- 2. Try matching: /way #<mapID> <x> <y> [desc] or /way <mapID> <x> <y> [desc]
    if not xStr or not yStr then
        local mapPrefix, mxStr, myStr, mdesc = text:match("^#?(%d+)%s+(%d+%.?%d*)%s*[,%s]%s*(%d+%.?%d*)%s*(.*)$")
        local mapNum = tonumber(mapPrefix)
        if mapNum and mapNum > 10 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapNum) then
            uiMapID = mapNum
            xStr, yStr, desc = mxStr, myStr, mdesc
        end
    end

    -- 3. Try matching: /way <Zone Name> <x> <y> [desc] (e.g. Elwynn Forest 42.5 61.8 Goldshire)
    if not xStr or not yStr then
        local zoneName, zxStr, zyStr, zdesc = text:match("^(.-)%s+(%d+%.?%d*)%s*[,%s]%s*(%d+%.?%d*)%s*(.*)$")
        if zoneName and zxStr and zyStr then
            xStr, yStr, desc = zxStr, zyStr, zdesc
            uiMapID = ResolveZoneNameToMapID(zoneName)
        end
    end

    if xStr and yStr then
        local x = tonumber(xStr)
        local y = tonumber(yStr)
        if x and y then
            local wpTitle = (desc and desc ~= "") and desc or nil
            return self:AddCustomWaypoint(uiMapID, x, y, wpTitle)
        end
    end
    return nil
end

function WayfinderModule:HandleWaySlash(msg)
    msg = (msg and msg:gsub("^%s*(.-)%s*$", "%1")) or ""
    if msg == "" then
        print("|cff00c0ff[Wayfinder]|r Usage: /way <x> <y> [description]")
        print("  |cff00c0ff/way <zone> <x> <y>|r - Set waypoint in a specific zone")
        print("  |cff00c0ff/way paste|r - Open multi-line waypoint paste window")
        print("  |cff00c0ff/cway|r - Point arrow to the closest active waypoint")
        print("  |cff00c0ff/way list|r - List all active custom waypoints")
        print("  |cff00c0ff/way reset|r - Clear all custom waypoints")
        print("  |cff00c0ff/way test|r - Preview and reposition navigation arrow")
        return
    end

    -- Multi-line or semicolon separated paste support
    local lines = {}
    for line in msg:gmatch("[^\r\n;]+") do
        line = line:gsub("^%s*(.-)%s*$", "%1")
        if line ~= "" then
            table.insert(lines, line)
        end
    end

    if #lines > 1 then
        local added = 0
        for _, line in ipairs(lines) do
            local wp = self:ParseAndAddWaypoint(line)
            if wp then added = added + 1 end
        end
        print(string.format("|cff00c0ff[Wayfinder]|r Successfully parsed and added %d waypoints (%d active total).",
            added, #self.customWaypoints))
        return
    end

    local lower = msg:lower()
    if lower == "paste" or lower == "multi" or lower == "box" or lower == "gui" or lower == "dialog" then
        self:OpenPasteDialog()
        return
    elseif lower == "reset" or lower == "clear" or lower == "reset all" or lower == "clear all" then
        self:ClearAllCustomWaypoints()
        self:ClearWaypoint()
        print("|cff00c0ff[Wayfinder]|r All waypoints and quest navigation cleared.")
        return
    elseif lower == "list" then
        self:ListWaypoints()
        return
    elseif lower == "closest" or lower == "cway" then
        self:SetClosestWaypoint()
        return
    elseif lower == "test" or lower == "preview" then
        self:TogglePreviewMode()
        return
    end

    local wp = self:ParseAndAddWaypoint(msg)
    if wp then
        local count = #self.customWaypoints
        local countStr = (count > 1) and string.format(" (%d active waypoints)", count) or ""
        print(string.format("|cff00c0ff[Wayfinder]|r Waypoint added: |cffffffff%s|r at (%.1f, %.1f) in %s%s.",
            wp.title, wp.x * 100, wp.y * 100, wp.mapName, countStr))
        return
    end

    print("|cff00c0ff[Wayfinder]|r Invalid format. Use: /way <x> <y> [description], /way paste, or /cway")
end

-- ---------------------------------------------------------------------------
-- Initialization & Event Listeners
-- ---------------------------------------------------------------------------

function WayfinderModule:Initialize()
    self.inCombat = (InCombatLockdown and InCombatLockdown()) or false
    self.previewMode = false

    self:CreateHUDFrame()
    self:UpdateFrameVisibility()

    local updateFrame = CreateFrame("Frame")
    self.updateFrame = updateFrame
    self.isUpdating = false
    self:StartUpdateTimer()

    -- Restore persistent custom waypoints from SavedVariables
    if ns.db and ns.db.wayfinder and ns.db.wayfinder.savedWaypoints then
        for _, wpData in ipairs(ns.db.wayfinder.savedWaypoints) do
            if wpData.x and wpData.y then
                waypointCounter = waypointCounter + 1
                local wp = {
                    id = waypointCounter,
                    uiMapID = wpData.uiMapID,
                    mapName = wpData.mapName or "Zone",
                    x = wpData.x,
                    y = wpData.y,
                    title = wpData.title or string.format("Waypoint %d", waypointCounter),
                    created = time(),
                }
                table.insert(self.customWaypoints, wp)
            end
        end
        if #self.customWaypoints > 0 and not currentTarget.hasTarget then
            self:SetClosestWaypoint()
        end
    end

    -- Hook WorldMapFrame for pin overlay, coordinates display, and + Waypoint button
    if WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", function()
            WayfinderModule:RefreshMapPins()
            WayfinderModule:UpdateCoordinatesDisplay()
            WayfinderModule:UpdateMapWaypointButton()
        end)
        WorldMapFrame:HookScript("OnHide", function()
            WayfinderModule:RefreshMapPins()
            WayfinderModule:UpdateCoordinatesDisplay()
            WayfinderModule:UpdateMapWaypointButton()
        end)
    end

    -- Hook click on WorldMap ScrollContainer to drop waypoints on Alt-Click and handle Right-Click zoom out
    local scrollContainer = WorldMapFrame and WorldMapFrame.ScrollContainer
    if scrollContainer and scrollContainer.HookScript then
        scrollContainer:HookScript("OnMouseUp", HandleWorldMapClick)
    elseif WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnMouseUp", HandleWorldMapClick)
    end

    self:UpdateMapWaypointButton()

    -- Register callbacks
    if ns.RegisterCallback then
        ns:RegisterCallback("QUEST_DATA_CHANGED", function()
            if ns.db and ns.db.wayfinder and ns.db.wayfinder.autoTrackActiveQuest and ns.activeQuestID and not currentTarget.isCustom then
                WayfinderModule:SetQuestTarget(ns.activeQuestID)
            end
        end)
    end

    -- Event listener for combat, SuperTrack, world entry, and zone changes
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("SUPER_TRACKING_CHANGED")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("ZONE_CHANGED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("QUEST_TURNED_IN")
    eventFrame:RegisterEvent("QUEST_REMOVED")
    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_REGEN_DISABLED" then
            WayfinderModule.inCombat = true
            WayfinderModule:UpdateFrameVisibility()
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            WayfinderModule.inCombat = false
            WayfinderModule:UpdateFrameVisibility()
            if currentTarget.hasTarget then
                WayfinderModule:CalculateNavigation()
            end
            return
        end

        if event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
            if arg1 and arrivedQuestIDs[arg1] then
                arrivedQuestIDs[arg1] = nil
            end
            if currentTarget.questID and currentTarget.questID == arg1 then
                WayfinderModule:ClearWaypoint()
            end
            return
        end

        if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
            UpdateTargetWorldCache()
            if currentTarget.hasTarget then
                WayfinderModule:CalculateNavigation()
            end
            WayfinderModule:RefreshMapPins()
            WayfinderModule:UpdateCoordinatesDisplay()
        end

        if not (ns.db and ns.db.wayfinder and ns.db.wayfinder.autoTrackActiveQuest) then return end
        if currentTarget.isCustom then return end -- Don't override custom /way pins

        if event == "SUPER_TRACKING_CHANGED" then
            if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
                local stQuestID = C_SuperTrack.GetSuperTrackedQuestID()
                if stQuestID and stQuestID > 0 and stQuestID ~= ns.activeQuestID then
                    if ns.StandaloneTracker and ns.StandaloneTracker.SetActiveQuest then
                        ns.StandaloneTracker:SetActiveQuest(stQuestID)
                    end
                elseif (not stQuestID or stQuestID == 0) and ns.activeQuestID then
                    WayfinderModule:ClearWaypoint()
                end
            end
        elseif event == "QUEST_LOG_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            if ns.activeQuestID and not ns.waypointExplicitlyCleared then
                WayfinderModule:SetQuestTarget(ns.activeQuestID)
            end
        end
    end)
    self.eventFrame = eventFrame

    -- Slash Command Registrations: /way, /waypoint, /bfqway
    SLASH_WAYFINDER_WAY1 = "/way"
    SLASH_WAYFINDER_WAY2 = "/waypoint"
    SLASH_WAYFINDER_WAY3 = "/bfqway"
    SlashCmdList["WAYFINDER_WAY"] = function(msg)
        WayfinderModule:HandleWaySlash(msg)
    end

    -- Slash Command Registrations: /cway, /closestway
    SLASH_WAYFINDER_CWAY1 = "/cway"
    SLASH_WAYFINDER_CWAY2 = "/closestway"
    SlashCmdList["WAYFINDER_CWAY"] = function()
        WayfinderModule:SetClosestWaypoint()
    end

    -- Slash Command Registration: /waypaste
    SLASH_WAYFINDER_PASTE1 = "/waypaste"
    SlashCmdList["WAYFINDER_PASTE"] = function()
        WayfinderModule:OpenPasteDialog()
    end

    -- Hook into /bfq arrow
    local origSlashHandler = SlashCmdList["BLEAKFIBER_TRACKER"]
    SlashCmdList["BLEAKFIBER_TRACKER"] = function(msg)
        local cmd, rest = msg:match("^(%S*)%s*(.-)$")
        cmd = cmd:lower()
        if cmd == "arrow" or cmd == "wp" or cmd == "waypoint" then
            WayfinderModule:HandleWaySlash(rest)
        elseif cmd == "cway" then
            WayfinderModule:SetClosestWaypoint()
        elseif cmd == "paste" or cmd == "waypaste" then
            WayfinderModule:OpenPasteDialog()
        else
            if origSlashHandler then
                origSlashHandler(msg)
            end
        end
    end
end
