local addonName, ns = ...

-- Localized Lua & WoW API bindings for performance & garbage reduction
local pairs, ipairs, type, tostring, tonumber, select, pcall = pairs, ipairs, type, tostring, tonumber, select, pcall
local string_format, string_lower, string_match, string_gsub = string.format, string.lower, string.match, string.gsub
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local math_floor, math_ceil, math_max, math_min, math_abs = math.floor, math.ceil, math.max, math.min, math.abs
local math_sqrt, math_atan2, math_pi = math.sqrt, math.atan2, math.pi
local MATH_PI = math.pi
local TWO_PI = 2 * math.pi
local wipe = table.wipe or wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local GetTime, PlaySound = GetTime, PlaySound
local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
local C_Map = C_Map
local C_SuperTrack = C_SuperTrack
local C_QuestLog = C_QuestLog
local GetPlayerFacing = GetPlayerFacing
local UnitOnTaxi = UnitOnTaxi

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
local cachedTargetContinentID = nil
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
local lastDistUnit = nil
local lastDistArrived = nil
local lastTitleFormatted = nil
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
    cachedTargetContinentID = nil
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

-- Helper: Safely unpack (x, y) coordinates from Vector2D userdata or table mixins
local function GetVectorXY(v)
    if not v then return nil, nil end
    if v.GetXY then
        local vx, vy = v:GetXY()
        if vx and vy then return vx, vy end
    end
    if v.x and v.y then
        return v.x, v.y
    end
    return nil, nil
end

function WayfinderModule:FormatDistance(distanceYards)
    if not distanceYards then return "" end
    local db = (ns.db and ns.db.wayfinder) or (ns.defaultDB and ns.defaultDB.profile and ns.defaultDB.profile.wayfinder)
    local unit = (db and db.distanceUnit) or "imperial"
    if unit == "metric" then
        local meters = distanceYards * 0.9144
        if meters >= 1000 then
            local km = math_floor((meters / 1000) * 10 + 0.5) / 10
            return string_format("%.1f km", km)
        else
            return string_format("%d m", math_floor(meters + 0.5))
        end
    else
        local yards = math_floor(distanceYards + 0.5)
        if yards >= 1760 then
            local miles = math_floor((yards / 1760) * 10 + 0.5) / 10
            return string_format("%.1f mi", miles)
        else
            return string_format("%d yd", yards)
        end
    end
end

local reusableMapPos = nil
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
        if not reusableMapPos then
            reusableMapPos = CreateVector2D(currentTarget.x, currentTarget.y)
        elseif reusableMapPos.SetXY then
            reusableMapPos:SetXY(currentTarget.x, currentTarget.y)
        else
            reusableMapPos.x = currentTarget.x
            reusableMapPos.y = currentTarget.y
        end
        if reusableMapPos then
            local contID, targetWorldPos = SafeCall(C_Map.GetWorldPosFromMapPos, mapID, reusableMapPos)
            local twx, twy = GetVectorXY(targetWorldPos)
            if twx and twy then
                cachedTargetWorldX = twx
                cachedTargetWorldY = twy
                cachedTargetContinentID = contID
                cachedTargetMapID = mapID
                cachedTargetRawX = currentTarget.x
                cachedTargetRawY = currentTarget.y
                return
            end
        end
    end

    cachedTargetWorldX = nil
    cachedTargetWorldY = nil
    cachedTargetContinentID = nil
    cachedTargetMapID = mapID
    cachedTargetRawX = currentTarget.x
    cachedTargetRawY = currentTarget.y
end

-- ---------------------------------------------------------------------------
-- Dungeon & Raid Location Database (Direct Entrance Coordinates & Zone Mappings)
-- ---------------------------------------------------------------------------

local DUNGEON_LOCATIONS = {
    ["wailing caverns"]       = { mapID = 1413, x = 0.460, y = 0.365, zone = "Wailing Caverns", parentZone = "The Barrens" },
    ["the deadmines"]         = { mapID = 1436, x = 0.425, y = 0.722, zone = "The Deadmines", parentZone = "Westfall" },
    ["deadmines"]             = { mapID = 1436, x = 0.425, y = 0.722, zone = "The Deadmines", parentZone = "Westfall" },
    ["shadowfang keep"]       = { mapID = 1421, x = 0.448, y = 0.678, zone = "Shadowfang Keep", parentZone = "Silverpine Forest" },
    ["sfk"]                   = { mapID = 1421, x = 0.448, y = 0.678, zone = "Shadowfang Keep", parentZone = "Silverpine Forest" },
    ["blackfathom deeps"]     = { mapID = 1440, x = 0.140, y = 0.144, zone = "Blackfathom Deeps", parentZone = "Ashenvale" },
    ["bfd"]                   = { mapID = 1440, x = 0.140, y = 0.144, zone = "Blackfathom Deeps", parentZone = "Ashenvale" },
    ["the stockade"]          = { mapID = 1453, x = 0.505, y = 0.665, zone = "The Stockade", parentZone = "Stormwind City" },
    ["stockade"]              = { mapID = 1453, x = 0.505, y = 0.665, zone = "The Stockade", parentZone = "Stormwind City" },
    ["gnomeregan"]            = { mapID = 1426, x = 0.240, y = 0.385, zone = "Gnomeregan", parentZone = "Dun Morogh" },
    ["razorfen kraul"]        = { mapID = 1413, x = 0.405, y = 0.945, zone = "Razorfen Kraul", parentZone = "The Barrens" },
    ["rfk"]                   = { mapID = 1413, x = 0.405, y = 0.945, zone = "Razorfen Kraul", parentZone = "The Barrens" },
    ["razorfen downs"]        = { mapID = 1413, x = 0.465, y = 0.915, zone = "Razorfen Downs", parentZone = "The Barrens" },
    ["rfd"]                   = { mapID = 1413, x = 0.465, y = 0.915, zone = "Razorfen Downs", parentZone = "The Barrens" },
    ["scarlet monastery"]     = { mapID = 1420, x = 0.850, y = 0.320, zone = "Scarlet Monastery", parentZone = "Tirisfal Glades" },
    ["sm"]                    = { mapID = 1420, x = 0.850, y = 0.320, zone = "Scarlet Monastery", parentZone = "Tirisfal Glades" },
    ["uldaman"]               = { mapID = 1418, x = 0.425, y = 0.125, zone = "Uldaman", parentZone = "Badlands" },
    ["zul'farrak"]            = { mapID = 1446, x = 0.390, y = 0.200, zone = "Zul'Farrak", parentZone = "Tanaris" },
    ["zulfarrak"]             = { mapID = 1446, x = 0.390, y = 0.200, zone = "Zul'Farrak", parentZone = "Tanaris" },
    ["zf"]                    = { mapID = 1446, x = 0.390, y = 0.200, zone = "Zul'Farrak", parentZone = "Tanaris" },
    ["maraudon"]              = { mapID = 1443, x = 0.290, y = 0.625, zone = "Maraudon", parentZone = "Desolace" },
    ["sunken temple"]         = { mapID = 1435, x = 0.695, y = 0.535, zone = "Sunken Temple", parentZone = "Swamp of Sorrows" },
    ["temple of atal'hakkar"] = { mapID = 1435, x = 0.695, y = 0.535, zone = "Sunken Temple", parentZone = "Swamp of Sorrows" },
    ["blackrock depths"]      = { mapID = 1427, x = 0.350, y = 0.840, zone = "Blackrock Depths", parentZone = "Searing Gorge" },
    ["brd"]                   = { mapID = 1427, x = 0.350, y = 0.840, zone = "Blackrock Depths", parentZone = "Searing Gorge" },
    ["blackrock spire"]       = { mapID = 1428, x = 0.290, y = 0.380, zone = "Blackrock Spire", parentZone = "Burning Steppes" },
    ["lower blackrock spire"] = { mapID = 1428, x = 0.290, y = 0.380, zone = "Lower Blackrock Spire", parentZone = "Burning Steppes" },
    ["lbrs"]                  = { mapID = 1428, x = 0.290, y = 0.380, zone = "Lower Blackrock Spire", parentZone = "Burning Steppes" },
    ["upper blackrock spire"] = { mapID = 1428, x = 0.290, y = 0.380, zone = "Upper Blackrock Spire", parentZone = "Burning Steppes" },
    ["ubrs"]                  = { mapID = 1428, x = 0.290, y = 0.380, zone = "Upper Blackrock Spire", parentZone = "Burning Steppes" },
    ["stratholme"]            = { mapID = 1423, x = 0.270, y = 0.115, zone = "Stratholme", parentZone = "Eastern Plaguelands" },
    ["strat"]                 = { mapID = 1423, x = 0.270, y = 0.115, zone = "Stratholme", parentZone = "Eastern Plaguelands" },
    ["scholomance"]           = { mapID = 1422, x = 0.690, y = 0.730, zone = "Scholomance", parentZone = "Western Plaguelands" },
    ["scholo"]                = { mapID = 1422, x = 0.690, y = 0.730, zone = "Scholomance", parentZone = "Western Plaguelands" },
    ["dire maul"]             = { mapID = 1444, x = 0.590, y = 0.450, zone = "Dire Maul", parentZone = "Feralas" },
    ["dm"]                    = { mapID = 1444, x = 0.590, y = 0.450, zone = "Dire Maul", parentZone = "Feralas" },
    ["ragefire chasm"]        = { mapID = 1454, x = 0.525, y = 0.495, zone = "Ragefire Chasm", parentZone = "Orgrimmar" },
    ["rfc"]                   = { mapID = 1454, x = 0.525, y = 0.495, zone = "Ragefire Chasm", parentZone = "Orgrimmar" },
    ["onyxia's lair"]         = { mapID = 1445, x = 0.520, y = 0.760, zone = "Onyxia's Lair", parentZone = "Dustwallow Marsh" },
    ["molten core"]           = { mapID = 1427, x = 0.350, y = 0.840, zone = "Molten Core", parentZone = "Searing Gorge" },
    ["mc"]                    = { mapID = 1427, x = 0.350, y = 0.840, zone = "Molten Core", parentZone = "Searing Gorge" },
    ["blackwing lair"]        = { mapID = 1428, x = 0.290, y = 0.380, zone = "Blackwing Lair", parentZone = "Burning Steppes" },
    ["bwl"]                   = { mapID = 1428, x = 0.290, y = 0.380, zone = "Blackwing Lair", parentZone = "Burning Steppes" },
    ["zul'gurub"]             = { mapID = 1434, x = 0.520, y = 0.170, zone = "Zul'Gurub", parentZone = "Stranglethorn Vale" },
    ["zulgurub"]              = { mapID = 1434, x = 0.520, y = 0.170, zone = "Zul'Gurub", parentZone = "Stranglethorn Vale" },
    ["zg"]                    = { mapID = 1434, x = 0.520, y = 0.170, zone = "Zul'Gurub", parentZone = "Stranglethorn Vale" },
    ["ruins of ahn'qiraj"]    = { mapID = 1451, x = 0.240, y = 0.870, zone = "Ruins of Ahn'Qiraj", parentZone = "Silithus" },
    ["aq20"]                  = { mapID = 1451, x = 0.240, y = 0.870, zone = "Ruins of Ahn'Qiraj", parentZone = "Silithus" },
    ["temple of ahn'qiraj"]   = { mapID = 1451, x = 0.240, y = 0.870, zone = "Temple of Ahn'Qiraj", parentZone = "Silithus" },
    ["aq40"]                  = { mapID = 1451, x = 0.240, y = 0.870, zone = "Temple of Ahn'Qiraj", parentZone = "Silithus" },
    ["naxxramas"]             = { mapID = 1423, x = 0.395, y = 0.255, zone = "Naxxramas", parentZone = "Eastern Plaguelands" },
    ["naxx"]                  = { mapID = 1423, x = 0.395, y = 0.255, zone = "Naxxramas", parentZone = "Eastern Plaguelands" },
}

local NON_ZONE_HEADERS = {
    ["mage"] = true, ["warrior"] = true, ["paladin"] = true, ["hunter"] = true,
    ["rogue"] = true, ["priest"] = true, ["shaman"] = true, ["warlock"] = true, ["druid"] = true,
    ["death knight"] = true, ["deathknight"] = true,
    ["alchemy"] = true, ["blacksmithing"] = true, ["enchanting"] = true, ["engineering"] = true,
    ["leatherworking"] = true, ["tailoring"] = true, ["herbalism"] = true, ["mining"] = true,
    ["skinning"] = true, ["cooking"] = true, ["first aid"] = true, ["fishing"] = true,
    ["general"] = true, ["special"] = true, ["battlegrounds"] = true, ["seasonal"] = true,
}

-- ---------------------------------------------------------------------------
-- Zone Name to uiMapID Resolver (Comprehensive WoW Forever Map Registry)
-- ---------------------------------------------------------------------------

local ZONE_NAME_TO_UIMAP = {
    -- Eastern Kingdoms Zones (Continent 1415 / 1463)
    ["alterac mountains"]     = 1416,
    ["alterac"]               = 1416,
    ["arathi highlands"]      = 1417,
    ["arathi"]                = 1417,
    ["badlands"]              = 1418,
    ["blasted lands"]         = 1419,
    ["burning steppes"]       = 1428,
    ["deadwind pass"]         = 1430,
    ["dun morogh"]            = 1426,
    ["duskwood"]              = 1431,
    ["eastern plaguelands"]   = 1423,
    ["epl"]                   = 1423,
    ["elwynn forest"]         = 1429,
    ["elwynn"]                = 1429,
    ["hillsbrad foothills"]   = 1424,
    ["hillsbrad"]             = 1424,
    ["ironforge"]             = 1455,
    ["if"]                    = 1455,
    ["loch modan"]            = 1432,
    ["redridge mountains"]    = 1433,
    ["redridge"]              = 1433,
    ["riverglades"]           = 2548,
    ["riverlands"]            = 2548,
    ["the riverglades"]       = 2548,
    ["the riverlands"]        = 2548,
    ["searing gorge"]         = 1427,
    ["silverpine forest"]     = 1421,
    ["silverpine"]            = 1421,
    ["stormwind city"]        = 1453,
    ["stormwind"]             = 1453,
    ["sw"]                    = 1453,
    ["stranglethorn vale"]    = 1434,
    ["stranglethorn"]         = 1434,
    ["stv"]                   = 1434,
    ["swamp of sorrows"]      = 1435,
    ["swamp of sorrow"]       = 1435,
    ["the hinterlands"]       = 1425,
    ["hinterlands"]           = 1425,
    ["tirisfal glades"]       = 1420,
    ["tirisfal"]              = 1420,
    ["undercity"]             = 1458,
    ["uc"]                    = 1458,
    ["western plaguelands"]   = 1422,
    ["wpl"]                   = 1422,
    ["westfall"]              = 1436,
    ["wetlands"]              = 1437,

    -- Kalimdor Zones (Continent 1414 / 1464)
    ["ashenvale"]             = 1440,
    ["azshara"]               = 1447,
    ["darkshore"]             = 1439,
    ["darkspear islands"]     = 2524,
    ["darkspear island"]      = 2524,
    ["darkspear strand"]      = 2524,
    ["darnassus"]             = 1457,
    ["darn"]                  = 1457,
    ["desolace"]              = 1443,
    ["durotar"]               = 1411,
    ["dustwallow marsh"]      = 1445,
    ["dustwallow"]            = 1445,
    ["felwood"]               = 1448,
    ["feralas"]               = 1444,
    ["moonglade"]             = 1450,
    ["mount hyjal"]           = 2482,
    ["hyjal"]                 = 2482,
    ["mulgore"]               = 1412,
    ["orgrimmar"]             = 1454,
    ["org"]                   = 1454,
    ["shen'dralas"]           = 2652,
    ["shendralas"]            = 2652,
    ["silithus"]              = 1451,
    ["stonetalon mountains"]  = 1442,
    ["stonetalon"]            = 1442,
    ["tanaris"]               = 1446,
    ["teldrassil"]            = 1438,
    ["the barrens"]           = 1413,
    ["barrens"]               = 1413,
    ["thousand needles"]      = 1441,
    ["thunder bluff"]         = 1456,
    ["tb"]                    = 1456,
    ["un'goro crater"]        = 1449,
    ["un'goro"]               = 1449,
    ["ungoro"]                = 1449,
    ["winterspring"]          = 1452,

    -- Battlegrounds, Continents & Custom Islands
    ["alterac valley"]        = 1459,
    ["av"]                    = 1459,
    ["arathi basin"]          = 1461,
    ["ab"]                    = 1461,
    ["warsong gulch"]         = 1460,
    ["wsg"]                   = 1460,
    ["zephras isle"]          = 2521,
    ["zephras isles"]         = 2521,
    ["the zephras isle"]      = 2521,
    ["eastern kingdoms"]      = 1415,
    ["kalimdor"]              = 1414,
    ["azeroth"]               = 947,

    -- Prominent Quest Hubs & Settlements Direct Mapping
    ["thelsamar"]             = 1432,
    ["stonewrought dam"]      = 1432,
    ["algor's cabin"]         = 1432,
    ["southshore"]            = 1424,
    ["tarren mill"]           = 1424,
    ["durnholde keep"]        = 1424,
    ["kharanos"]              = 1426,
    ["anvilmar"]              = 1426,
    ["goldshire"]             = 1429,
    ["northshire"]            = 1429,
    ["sentinel hill"]         = 1436,
    ["moonbrook"]             = 1436,
    ["lakeshire"]             = 1433,
    ["darkshire"]             = 1431,
    ["raven hill"]            = 1431,
    ["menethil harbor"]       = 1437,
    ["greenwarden's grove"]   = 1437,
    ["refuge pointe"]         = 1417,
    ["hammerfall"]            = 1417,
    ["aerie peak"]            = 1425,
    ["revantusk village"]     = 1425,
    ["chillwind camp"]        = 1422,
    ["light's hope chapel"]   = 1423,
    ["brill"]                 = 1420,
    ["deathknell"]            = 1420,
    ["sepulcher"]             = 1421,
    ["the sepulcher"]         = 1421,
    ["kargath"]               = 1418,
    ["thorium point"]         = 1427,
    ["morgan's vigil"]        = 1428,
    ["flame crest"]           = 1428,
    ["booty bay"]             = 1434,
    ["grom'gol"]              = 1434,
    ["grom'gol base camp"]    = 1434,
    ["rebel camp"]            = 1434,
    ["stonard"]               = 1435,
    ["nethergarde keep"]      = 1419,
    ["crossroads"]            = 1413,
    ["the crossroads"]        = 1413,
    ["ratchet"]               = 1413,
    ["camp taurajo"]          = 1413,
    ["taurajo"]               = 1413,
    ["razor hill"]            = 1411,
    ["bloodhoof village"]     = 1412,
    ["astranaar"]             = 1440,
    ["auberdine"]             = 1439,
    ["dolanaar"]              = 1438,
    ["sun rock retreat"]      = 1442,
    ["freewind post"]         = 1441,
    ["nijel's point"]         = 1443,
    ["theramore"]             = 1445,
    ["theramore isle"]        = 1445,
    ["feathermoon"]           = 1444,
    ["gadgetzan"]             = 1446,
    ["marshal's refuge"]      = 1449,
    ["cenarion hold"]         = 1451,
    ["everlook"]              = 1452,
    ["bloodvenom post"]       = 1448,
    ["nighthaven"]            = 1450,
}

-- Helper: Inspect quest log hierarchy to locate the zone header for a quest
local function GetQuestLogZone(questID, questLogIndex)
    if not questID and not questLogIndex then return nil end

    -- 1. Fast cache lookup in StandaloneTracker (already parsed and grouped by zone header)
    if questID and ns.StandaloneTracker then
        if ns.StandaloneTracker.activeBlocks and ns.StandaloneTracker.activeBlocks[questID] then
            local qInfo = ns.StandaloneTracker.activeBlocks[questID].questInfo
            if qInfo and qInfo.zone and qInfo.zone ~= "" and qInfo.zone ~= "General" then
                return qInfo.zone
            end
        end
        if ns.StandaloneTracker.cachedTrackedQuests then
            for _, q in ipairs(ns.StandaloneTracker.cachedTrackedQuests) do
                if q.questID == questID and q.zone and q.zone ~= "" and q.zone ~= "General" then
                    return q.zone
                end
            end
        end
    end

    -- 2. Engine-safe quest log iteration across 16001 / Classic / Retail engines
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and SafeCall(C_QuestLog.GetNumQuestLogEntries))
        or (GetNumQuestLogEntries and SafeCall(GetNumQuestLogEntries)) or 0
    if numEntries == 0 then return nil end

    local targetIdx = questLogIndex
    if not targetIdx and questID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        targetIdx = SafeCall(C_QuestLog.GetLogIndexForQuestID, questID)
    end

    local currentHeader = nil
    for i = 1, numEntries do
        local title, _, _, isHeader, _, _, _, qID
        if ns.GetQuestLogTitle then
            title, _, _, isHeader, _, _, _, qID = SafeCall(ns.GetQuestLogTitle, i)
        elseif C_QuestLog and C_QuestLog.GetInfo then
            local info = SafeCall(C_QuestLog.GetInfo, i)
            if info then
                title = info.title
                isHeader = (info.isHeader == 1 or info.isHeader == true)
                qID = info.questID
            end
        end

        if not title and GetQuestLogTitle then
            local numRet = select("#", GetQuestLogTitle(i))
            if numRet >= 9 then
                local qTitle, _, _, _, qHdr, _, _, _, qIdNum = GetQuestLogTitle(i)
                title = qTitle
                isHeader = (qHdr == 1 or qHdr == true)
                qID = tonumber(qIdNum)
            elseif numRet >= 7 then
                local qTitle, _, _, qHdr, _, _, _, qIdNum = GetQuestLogTitle(i)
                title = qTitle
                isHeader = (qHdr == 1 or qHdr == true)
                qID = tonumber(qIdNum)
            else
                local qTitle, _, _, qHdr = GetQuestLogTitle(i)
                title = qTitle
                isHeader = (qHdr == 1 or qHdr == true)
            end
        end

        if isHeader then
            currentHeader = title
        else
            if (targetIdx and i == targetIdx) or (questID and qID and qID == questID) then
                return currentHeader
            end
        end
    end
    return nil
end

local function ResolveZoneNameToMapID(zoneName)
    if type(zoneName) ~= "string" or zoneName == "" then return nil end
    local query = zoneName:lower():gsub("^the%s+", ""):gsub("^%s*(.-)%s*$", "%1")
    local rawLower = zoneName:lower():gsub("^%s*(.-)%s*$", "%1")

    -- 0. Dungeon & Raid entrance map lookup
    if DUNGEON_LOCATIONS[query] then
        return DUNGEON_LOCATIONS[query].mapID
    end
    if DUNGEON_LOCATIONS[rawLower] then
        return DUNGEON_LOCATIONS[rawLower].mapID
    end

    -- 1. Direct O(1) table lookup
    if ZONE_NAME_TO_UIMAP[query] then
        return ZONE_NAME_TO_UIMAP[query]
    end
    if ZONE_NAME_TO_UIMAP[rawLower] then
        return ZONE_NAME_TO_UIMAP[rawLower]
    end

    -- 2. Hub-to-zone fallback from CrossZoneModule
    if ns.CrossZoneModule and ns.CrossZoneModule.HubToZone then
        local parentZone = ns.CrossZoneModule.HubToZone[query] or ns.CrossZoneModule.HubToZone[rawLower]
        if parentZone then
            local normParent = parentZone:lower():gsub("^the%s+", ""):gsub("^%s*(.-)%s*$", "%1")
            local pMap = ZONE_NAME_TO_UIMAP[normParent] or ZONE_NAME_TO_UIMAP[parentZone:lower()]
            if pMap then
                ZONE_NAME_TO_UIMAP[query] = pMap
                return pMap
            end
        end
    end

    -- 3. Check player's current map
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and SafeCall(C_Map.GetBestMapForUnit, "player")
    if playerMapID and C_Map and C_Map.GetMapInfo then
        local pInfo = SafeCall(C_Map.GetMapInfo, playerMapID)
        if pInfo and pInfo.name then
            local pName = pInfo.name:lower():gsub("^the%s+", ""):gsub("^%s*(.-)%s*$", "%1")
            if pName == query or pInfo.name:lower() == rawLower then
                ZONE_NAME_TO_UIMAP[query] = playerMapID
                return playerMapID
            end
        end
    end

    -- 4. Search area maps in current continent/parent map
    if playerMapID and C_Map and C_Map.GetMapInfo then
        local pInfo = SafeCall(C_Map.GetMapInfo, playerMapID)
        local parentID = pInfo and pInfo.parentMapID
        if parentID and parentID > 0 and C_Map.GetMapChildrenInfo then
            local children = SafeCall(C_Map.GetMapChildrenInfo, parentID)
            if children then
                for _, child in ipairs(children) do
                    if child.name then
                        local cName = child.name:lower():gsub("^the%s+", ""):gsub("^%s*(.-)%s*$", "%1")
                        if cName == query or child.name:lower() == rawLower then
                            ZONE_NAME_TO_UIMAP[query] = child.mapID
                            return child.mapID
                        end
                    end
                end
            end
        end
    end

    -- 5. Search standard continents
    local continentIDs = { 1415, 1414, 947, 1945, 113, 946 }
    for _, contID in ipairs(continentIDs) do
        if C_Map and C_Map.GetMapChildrenInfo then
            local children = SafeCall(C_Map.GetMapChildrenInfo, contID, 3)
                or SafeCall(C_Map.GetMapChildrenInfo, contID)
            if children then
                for _, child in ipairs(children) do
                    if child.name then
                        local cName = child.name:lower():gsub("^the%s+", ""):gsub("^%s*(.-)%s*$", "%1")
                        if cName == query or child.name:lower() == rawLower then
                            ZONE_NAME_TO_UIMAP[query] = child.mapID
                            return child.mapID
                        end
                    end
                end
            end
        end
    end

    -- Note: Return nil if zone could not be resolved! Never return playerMapID!
    return nil
end

-- Forward declarations for specialized destination map resolvers
local GetQuestObjectiveDestinationMapID
local GetQuestTurnInDestinationMapID

-- Helper: Discover destination uiMapID for a quest (router)
local function GetQuestDestinationMapID(questID, questLogIndex, isTurnIn)
    if not questID then return nil end
    if isTurnIn then
        if GetQuestTurnInDestinationMapID then
            return GetQuestTurnInDestinationMapID(questID, questLogIndex)
        end
    else
        if GetQuestObjectiveDestinationMapID then
            return GetQuestObjectiveDestinationMapID(questID, questLogIndex)
        end
    end
    return nil
end


-- ---------------------------------------------------------------------------
-- Continent Geometry Registry & Cross-Zone Vector Math
-- ---------------------------------------------------------------------------

local ZONE_CONTINENT_DATA = {
    -- Eastern Kingdoms Zones (contID = 1415)
    [1416] = { contID = 1415, left = 0.45, right = 0.51, top = 0.35, bottom = 0.42 }, -- Alterac Mountains
    [1417] = { contID = 1415, left = 0.51, right = 0.60, top = 0.45, bottom = 0.52 }, -- Arathi Highlands
    [1418] = { contID = 1415, left = 0.52, right = 0.60, top = 0.63, bottom = 0.70 }, -- Badlands
    [1419] = { contID = 1415, left = 0.51, right = 0.58, top = 0.79, bottom = 0.89 }, -- Blasted Lands
    [1428] = { contID = 1415, left = 0.46, right = 0.54, top = 0.66, bottom = 0.73 }, -- Burning Steppes
    [1430] = { contID = 1415, left = 0.49, right = 0.53, top = 0.74, bottom = 0.80 }, -- Deadwind Pass
    [1426] = { contID = 1415, left = 0.41, right = 0.52, top = 0.55, bottom = 0.62 }, -- Dun Morogh
    [1431] = { contID = 1415, left = 0.43, right = 0.51, top = 0.72, bottom = 0.79 }, -- Duskwood
    [1423] = { contID = 1415, left = 0.54, right = 0.65, top = 0.21, bottom = 0.33 }, -- Eastern Plaguelands
    [1429] = { contID = 1415, left = 0.40, right = 0.49, top = 0.65, bottom = 0.73 }, -- Elwynn Forest
    [1424] = { contID = 1415, left = 0.46, right = 0.54, top = 0.40, bottom = 0.47 }, -- Hillsbrad Foothills
    [1455] = { contID = 1415, left = 0.46, right = 0.50, top = 0.56, bottom = 0.59 }, -- Ironforge
    [1432] = { contID = 1415, left = 0.53, right = 0.59, top = 0.56, bottom = 0.64 }, -- Loch Modan
    [1433] = { contID = 1415, left = 0.50, right = 0.58, top = 0.69, bottom = 0.76 }, -- Redridge Mountains
    [2548] = { contID = 1415, left = 0.50, right = 0.56, top = 0.33, bottom = 0.39 }, -- Riverglades (Custom)
    [1427] = { contID = 1415, left = 0.45, right = 0.52, top = 0.62, bottom = 0.67 }, -- Searing Gorge
    [1421] = { contID = 1415, left = 0.39, right = 0.47, top = 0.33, bottom = 0.44 }, -- Silverpine Forest
    [1453] = { contID = 1415, left = 0.41, right = 0.45, top = 0.66, bottom = 0.70 }, -- Stormwind City
    [1434] = { contID = 1415, left = 0.39, right = 0.48, top = 0.80, bottom = 0.95 }, -- Stranglethorn Vale
    [1435] = { contID = 1415, left = 0.51, right = 0.58, top = 0.74, bottom = 0.80 }, -- Swamp of Sorrows
    [1425] = { contID = 1415, left = 0.53, right = 0.62, top = 0.37, bottom = 0.46 }, -- The Hinterlands
    [1420] = { contID = 1415, left = 0.38, right = 0.46, top = 0.23, bottom = 0.33 }, -- Tirisfal Glades
    [1458] = { contID = 1415, left = 0.41, right = 0.44, top = 0.28, bottom = 0.31 }, -- Undercity
    [1422] = { contID = 1415, left = 0.47, right = 0.55, top = 0.26, bottom = 0.37 }, -- Western Plaguelands
    [1436] = { contID = 1415, left = 0.36, right = 0.44, top = 0.71, bottom = 0.81 }, -- Westfall
    [1437] = { contID = 1415, left = 0.46, right = 0.56, top = 0.50, bottom = 0.58 }, -- Wetlands
    [1459] = { contID = 1415, left = 0.48, right = 0.50, top = 0.38, bottom = 0.41 }, -- Alterac Valley
    [1461] = { contID = 1415, left = 0.55, right = 0.58, top = 0.47, bottom = 0.50 }, -- Arathi Basin
    [2521] = { contID = 1415, left = 0.32, right = 0.36, top = 0.68, bottom = 0.74 }, -- Zephras Isle
    [2665] = { contID = 1415, left = 0.32, right = 0.36, top = 0.68, bottom = 0.74 }, -- Zephras Isle
    [1415] = { contID = 1415, left = 0.00, right = 1.00, top = 0.00, bottom = 1.00 }, -- Eastern Kingdoms
    [1463] = { contID = 1415, left = 0.00, right = 1.00, top = 0.00, bottom = 1.00 }, -- Eastern Kingdoms

    -- Kalimdor Zones (contID = 1414)
    [1440] = { contID = 1414, left = 0.40, right = 0.56, top = 0.31, bottom = 0.43 }, -- Ashenvale
    [1447] = { contID = 1414, left = 0.53, right = 0.64, top = 0.33, bottom = 0.44 }, -- Azshara
    [1439] = { contID = 1414, left = 0.38, right = 0.45, top = 0.12, bottom = 0.27 }, -- Darkshore
    [2524] = { contID = 1414, left = 0.56, right = 0.61, top = 0.55, bottom = 0.60 }, -- Darkspear Islands
    [1457] = { contID = 1414, left = 0.36, right = 0.40, top = 0.08, bottom = 0.12 }, -- Darnassus
    [1443] = { contID = 1414, left = 0.38, right = 0.46, top = 0.51, bottom = 0.63 }, -- Desolace
    [1411] = { contID = 1414, left = 0.53, right = 0.61, top = 0.45, bottom = 0.58 }, -- Durotar
    [1445] = { contID = 1414, left = 0.52, right = 0.62, top = 0.57, bottom = 0.69 }, -- Dustwallow Marsh
    [1448] = { contID = 1414, left = 0.44, right = 0.51, top = 0.21, bottom = 0.34 }, -- Felwood
    [1444] = { contID = 1414, left = 0.37, right = 0.49, top = 0.62, bottom = 0.75 }, -- Feralas
    [1450] = { contID = 1414, left = 0.48, right = 0.55, top = 0.14, bottom = 0.21 }, -- Moonglade
    [2482] = { contID = 1414, left = 0.49, right = 0.55, top = 0.25, bottom = 0.32 }, -- Mount Hyjal
    [1412] = { contID = 1414, left = 0.42, right = 0.51, top = 0.52, bottom = 0.64 }, -- Mulgore
    [1454] = { contID = 1414, left = 0.55, right = 0.59, top = 0.44, bottom = 0.49 }, -- Orgrimmar
    [2652] = { contID = 1414, left = 0.42, right = 0.46, top = 0.66, bottom = 0.71 }, -- Shen'dralas
    [1451] = { contID = 1414, left = 0.38, right = 0.47, top = 0.76, bottom = 0.87 }, -- Silithus
    [1442] = { contID = 1414, left = 0.40, right = 0.48, top = 0.40, bottom = 0.53 }, -- Stonetalon Mountains
    [1446] = { contID = 1414, left = 0.50, right = 0.61, top = 0.72, bottom = 0.88 }, -- Tanaris
    [1438] = { contID = 1414, left = 0.33, right = 0.43, top = 0.05, bottom = 0.15 }, -- Teldrassil
    [1413] = { contID = 1414, left = 0.45, right = 0.54, top = 0.42, bottom = 0.66 }, -- The Barrens
    [1441] = { contID = 1414, left = 0.47, right = 0.58, top = 0.65, bottom = 0.74 }, -- Thousand Needles
    [1456] = { contID = 1414, left = 0.45, right = 0.49, top = 0.56, bottom = 0.60 }, -- Thunder Bluff
    [1449] = { contID = 1414, left = 0.45, right = 0.53, top = 0.75, bottom = 0.84 }, -- Un'Goro Crater
    [1452] = { contID = 1414, left = 0.50, right = 0.62, top = 0.18, bottom = 0.31 }, -- Winterspring
    [1460] = { contID = 1414, left = 0.46, right = 0.49, top = 0.39, bottom = 0.42 }, -- Warsong Gulch
    [1414] = { contID = 1414, left = 0.00, right = 1.00, top = 0.00, bottom = 1.00 }, -- Kalimdor
    [1464] = { contID = 1414, left = 0.00, right = 1.00, top = 0.00, bottom = 1.00 }, -- Kalimdor
}

-- Calculate continent projected coordinates (for continent-level map pins)
local function GetContinentCoords(mapID, x, y)
    if not mapID or not x or not y then return nil, nil, nil end
    local data = ZONE_CONTINENT_DATA[mapID]
    if not data or not data.contID then return nil, nil, nil end
    local cx = data.left + x * (data.right - data.left)
    local cy = data.top + y * (data.bottom - data.top)
    return cx, cy, data.contID
end

-- Calculate accurate cross-zone continent distance and angle heading
local function CalculateContinentOffset(fromMapID, fromX, fromY, toMapID, toX, toY)
    if not fromMapID or not toMapID then return 8000, 0, false end
    if fromMapID == toMapID then
        local dx = (toX or 0.5) - (fromX or 0.5)
        local dy = (toY or 0.5) - (fromY or 0.5)
        local dist = math_sqrt(dx * dx + dy * dy) * 1000
        local angle = math_atan2(-dx, -dy)
        return dist, angle, true
    end

    local fData = ZONE_CONTINENT_DATA[fromMapID]
    local tData = ZONE_CONTINENT_DATA[toMapID]

    if not fData or not tData then
        return 8000, 0, false
    end

    if fData.contID ~= tData.contID then
        -- Different continents (e.g. Kalimdor vs Eastern Kingdoms)
        local angle = (fData.contID == 1414) and (-MATH_PI / 2) or (MATH_PI / 2)
        return 35000, angle, false
    end

    local contID = fData.contID

    -- 1. Determine player continent coordinates
    local pcx, pcy = nil, nil
    if C_Map and C_Map.GetPlayerMapPosition then
        local pContPos = SafeCall(C_Map.GetPlayerMapPosition, contID, "player")
        pcx, pcy = GetVectorXY(pContPos)
    end

    if not pcx or not pcy or pcx <= 0 or pcy <= 0 then
        local fx = fromX or 0.5
        local fy = fromY or 0.5
        pcx = fData.left + fx * (fData.right - fData.left)
        pcy = fData.top + fy * (fData.bottom - fData.top)
    end

    -- 2. Determine target continent coordinates
    local tx = toX or 0.5
    local ty = toY or 0.5
    local tcx = tData.left + tx * (tData.right - tData.left)
    local tcy = tData.top + ty * (tData.bottom - tData.top)

    -- 3. Calculate continent vector & heading
    local dx = tcx - pcx -- East (+) / West (-)
    local dy = tcy - pcy -- South (+) / North (-)

    local scaleX = (contID == 1414) and 34000 or 32000
    local scaleY = (contID == 1414) and 48000 or 44000

    local deltaNorth = -dy * scaleY
    local deltaWest  = -dx * scaleX

    local distYards = math_sqrt(deltaNorth * deltaNorth + deltaWest * deltaWest)
    local angle = math_atan2(deltaWest, deltaNorth)

    return distYards, angle, true
end

-- ---------------------------------------------------------------------------
-- Classic Flight Master Registry & Intelligent Route Resolution
-- ---------------------------------------------------------------------------

local FLIGHT_MASTERS = {
    -- Eastern Kingdoms (Continent 1415)
    [1424] = { -- Hillsbrad Foothills
        Alliance = { x = 0.493, y = 0.523, name = "Southshore" },
        Horde    = { x = 0.601, y = 0.186, name = "Tarren Mill" },
    },
    [1432] = { -- Loch Modan
        Alliance = { x = 0.339, y = 0.509, name = "Thelsamar" },
        Horde    = { x = 0.040, y = 0.448, name = "Kargath (Badlands)" },
    },
    [1417] = { -- Arathi Highlands
        Alliance = { x = 0.458, y = 0.461, name = "Refuge Pointe" },
        Horde    = { x = 0.731, y = 0.327, name = "Hammerfall" },
    },
    [1437] = { -- Wetlands
        Alliance = { x = 0.095, y = 0.597, name = "Menethil Harbor" },
        Horde    = { x = 0.731, y = 0.327, name = "Hammerfall (Arathi)" },
    },
    [1426] = { -- Dun Morogh
        Alliance = { x = 0.538, y = 0.349, name = "Ironforge" },
        Horde    = { x = 0.040, y = 0.448, name = "Kargath (Badlands)" },
    },
    [1455] = { -- Ironforge City
        Alliance = { x = 0.555, y = 0.478, name = "Ironforge" },
        Horde    = { x = 0.040, y = 0.448, name = "Kargath (Badlands)" },
    },
    [1429] = { -- Elwynn Forest
        Alliance = { x = 0.315, y = 0.080, name = "Stormwind" },
        Horde    = { x = 0.448, y = 0.550, name = "Stonard (Swamp)" },
    },
    [1453] = { -- Stormwind City
        Alliance = { x = 0.663, y = 0.621, name = "Stormwind" },
        Horde    = { x = 0.448, y = 0.550, name = "Stonard (Swamp)" },
    },
    [1420] = { -- Tirisfal Glades
        Alliance = { x = 0.429, y = 0.849, name = "Chillwind Camp (WPL)" },
        Horde    = { x = 0.619, y = 0.589, name = "Undercity" },
    },
    [1458] = { -- Undercity
        Alliance = { x = 0.429, y = 0.849, name = "Chillwind Camp (WPL)" },
        Horde    = { x = 0.638, y = 0.486, name = "Undercity" },
    },
    [1421] = { -- Silverpine Forest
        Alliance = { x = 0.493, y = 0.523, name = "Southshore (Hillsbrad)" },
        Horde    = { x = 0.456, y = 0.426, name = "The Sepulcher" },
    },
    [1422] = { -- Western Plaguelands
        Alliance = { x = 0.429, y = 0.849, name = "Chillwind Camp" },
        Horde    = { x = 0.830, y = 0.680, name = "The Bulwark" },
    },
    [1423] = { -- Eastern Plaguelands
        Alliance = { x = 0.815, y = 0.580, name = "Light's Hope Chapel" },
        Horde    = { x = 0.815, y = 0.580, name = "Light's Hope Chapel" },
    },
    [1425] = { -- The Hinterlands
        Alliance = { x = 0.111, y = 0.461, name = "Aerie Peak" },
        Horde    = { x = 0.781, y = 0.814, name = "Revantusk Village" },
    },
    [1433] = { -- Redridge Mountains
        Alliance = { x = 0.306, y = 0.594, name = "Lakeshire" },
        Horde    = { x = 0.448, y = 0.550, name = "Stonard (Swamp)" },
    },
    [1436] = { -- Westfall
        Alliance = { x = 0.566, y = 0.526, name = "Sentinel Hill" },
        Horde    = { x = 0.325, y = 0.292, name = "Grom'gol (STV)" },
    },
    [1431] = { -- Duskwood
        Alliance = { x = 0.775, y = 0.443, name = "Darkshire" },
        Horde    = { x = 0.325, y = 0.292, name = "Grom'gol (STV)" },
    },
    [1434] = { -- Stranglethorn Vale
        Alliance = { x = 0.275, y = 0.778, name = "Booty Bay" },
        Horde    = { x = 0.325, y = 0.292, name = "Grom'gol" },
    },
    [1418] = { -- Badlands
        Alliance = { x = 0.339, y = 0.509, name = "Thelsamar (Loch Modan)" },
        Horde    = { x = 0.040, y = 0.448, name = "Kargath" },
    },
    [1427] = { -- Searing Gorge
        Alliance = { x = 0.379, y = 0.309, name = "Thorium Point" },
        Horde    = { x = 0.348, y = 0.309, name = "Thorium Point" },
    },
    [1428] = { -- Burning Steppes
        Alliance = { x = 0.843, y = 0.683, name = "Morgan's Vigil" },
        Horde    = { x = 0.657, y = 0.242, name = "Flame Crest" },
    },
    [1435] = { -- Swamp of Sorrows
        Alliance = { x = 0.306, y = 0.594, name = "Lakeshire (Redridge)" },
        Horde    = { x = 0.448, y = 0.550, name = "Stonard" },
    },
    [1419] = { -- Blasted Lands
        Alliance = { x = 0.655, y = 0.243, name = "Nethergarde Keep" },
        Horde    = { x = 0.448, y = 0.550, name = "Stonard (Swamp)" },
    },

    -- Kalimdor (Continent 1414)
    [1411] = { -- Durotar
        Alliance = { x = 0.631, y = 0.372, name = "Ratchet (Barrens)" },
        Horde    = { x = 0.451, y = 0.639, name = "Orgrimmar" },
    },
    [1454] = { -- Orgrimmar
        Alliance = { x = 0.631, y = 0.372, name = "Ratchet (Barrens)" },
        Horde    = { x = 0.451, y = 0.639, name = "Orgrimmar" },
    },
    [1412] = { -- Mulgore
        Alliance = { x = 0.053, y = 0.177, name = "Thalanaar (Needles)" },
        Horde    = { x = 0.468, y = 0.499, name = "Thunder Bluff" },
    },
    [1456] = { -- Thunder Bluff
        Alliance = { x = 0.053, y = 0.177, name = "Thalanaar (Needles)" },
        Horde    = { x = 0.468, y = 0.499, name = "Thunder Bluff" },
    },
    [1413] = { -- The Barrens
        Alliance = { x = 0.631, y = 0.372, name = "Ratchet" },
        Horde    = { x = 0.515, y = 0.303, name = "The Crossroads" },
    },
    [1438] = { -- Teldrassil
        Alliance = { x = 0.584, y = 0.940, name = "Rut'theran Village" },
    },
    [1457] = { -- Darnassus
        Alliance = { x = 0.584, y = 0.940, name = "Rut'theran Village" },
    },
    [1439] = { -- Darkshore
        Alliance = { x = 0.363, y = 0.456, name = "Auberdine" },
        Horde    = { x = 0.122, y = 0.338, name = "Zoram'gar (Ashenvale)" },
    },
    [1440] = { -- Ashenvale
        Alliance = { x = 0.344, y = 0.480, name = "Astranaar" },
        Horde    = { x = 0.732, y = 0.616, name = "Splintertree Post" },
    },
    [1442] = { -- Stonetalon Mountains
        Alliance = { x = 0.364, y = 0.072, name = "Peak Camp" },
        Horde    = { x = 0.451, y = 0.598, name = "Sun Rock Retreat" },
    },
    [1441] = { -- Thousand Needles
        Alliance = { x = 0.053, y = 0.177, name = "Thalanaar" },
        Horde    = { x = 0.451, y = 0.491, name = "Freewind Post" },
    },
    [1443] = { -- Desolace
        Alliance = { x = 0.647, y = 0.105, name = "Nijel's Point" },
        Horde    = { x = 0.216, y = 0.741, name = "Shadowprey Village" },
    },
    [1444] = { -- Feralas
        Alliance = { x = 0.302, y = 0.432, name = "Feathermoon Stronghold" },
        Horde    = { x = 0.754, y = 0.443, name = "Camp Mojache" },
    },
    [1445] = { -- Dustwallow Marsh
        Alliance = { x = 0.675, y = 0.513, name = "Theramore Isle" },
        Horde    = { x = 0.356, y = 0.319, name = "Brackenwall Village" },
    },
    [1446] = { -- Tanaris
        Alliance = { x = 0.514, y = 0.254, name = "Gadgetzan" },
        Horde    = { x = 0.516, y = 0.267, name = "Gadgetzan" },
    },
    [1447] = { -- Azshara
        Alliance = { x = 0.119, y = 0.776, name = "Talrendis Point" },
        Horde    = { x = 0.220, y = 0.496, name = "Valormok" },
    },
    [1448] = { -- Felwood
        Alliance = { x = 0.625, y = 0.242, name = "Talonbranch Glade" },
        Horde    = { x = 0.344, y = 0.538, name = "Bloodvenom Post" },
    },
    [1449] = { -- Un'Goro Crater
        Alliance = { x = 0.514, y = 0.254, name = "Gadgetzan (Tanaris)" },
        Horde    = { x = 0.516, y = 0.267, name = "Gadgetzan (Tanaris)" },
    },
    [1451] = { -- Silithus
        Alliance = { x = 0.506, y = 0.344, name = "Cenarion Hold" },
        Horde    = { x = 0.487, y = 0.367, name = "Cenarion Hold" },
    },
    [1450] = { -- Moonglade
        Alliance = { x = 0.481, y = 0.673, name = "Nighthaven" },
        Horde    = { x = 0.443, y = 0.452, name = "Nighthaven" },
    },
}

local function GetZoneFlightMaster(uiMapID)
    if not uiMapID then return nil end
    local entry = FLIGHT_MASTERS[uiMapID]
    if not entry then return nil end
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Alliance"
    local fm = entry[faction] or entry["Alliance"] or entry["Horde"]
    if fm then
        return {
            x = fm.x,
            y = fm.y,
            name = fm.name,
            uiMapID = uiMapID,
        }
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Target Coordinate Resolution & Multi-Waypoint Management
-- ---------------------------------------------------------------------------

-- Helper: Discover destination uiMapID where quest objectives take place
GetQuestObjectiveDestinationMapID = function(questID, questLogIndex)
    if not questID then return nil end

    -- 1. Check Quest Log Header Zone FIRST (the primary and authoritative source in WoW Classic)
    local headerZone = GetQuestLogZone(questID, questLogIndex)
    if headerZone and headerZone ~= "" then
        local normHeader = headerZone:lower():gsub("^the%s+", ""):gsub("^%s*(.-)%s*$", "%1")
        local rawLower = headerZone:lower():gsub("^%s*(.-)%s*$", "%1")

        -- Dungeon & Raid entrance map lookup
        if DUNGEON_LOCATIONS[normHeader] or DUNGEON_LOCATIONS[rawLower] then
            local dung = DUNGEON_LOCATIONS[normHeader] or DUNGEON_LOCATIONS[rawLower]
            return dung.mapID
        end

        -- Genuine zone header check (e.g. "Westfall", "Darkshore", "Redridge Mountains")
        if not (NON_ZONE_HEADERS[normHeader] or NON_ZONE_HEADERS[rawLower]) then
            local mapID = ResolveZoneNameToMapID(headerZone)
            if mapID and mapID > 0 then
                -- Check if CrossZoneModule specifies a different target zone (e.g. cross-zone quest picked up in Westfall)
                if ns.CrossZoneModule and ns.CrossZoneModule.GetQuestDestinationZone then
                    local crossZoneStr = SafeCall(ns.CrossZoneModule.GetQuestDestinationZone, ns.CrossZoneModule, questID, questLogIndex)
                    if crossZoneStr then
                        local crossMapID = ResolveZoneNameToMapID(crossZoneStr)
                        if crossMapID and crossMapID > 0 then
                            return crossMapID
                        end
                    end
                end
                return mapID
            end
        end
    end

    -- 2. CrossZoneModule text scanning of quest objectives & description (for class, profession, or untracked quests)
    if ns.CrossZoneModule and ns.CrossZoneModule.GetQuestDestinationZone then
        local zoneStr = SafeCall(ns.CrossZoneModule.GetQuestDestinationZone, ns.CrossZoneModule, questID, questLogIndex)
        if zoneStr then
            local mapID = ResolveZoneNameToMapID(zoneStr)
            if mapID and mapID > 0 then
                return mapID
            end
        end
    end

    -- 3. Questie Integration: Query Questie DB for objective coordinates if installed
    if type(QuestieDB) == "table" and QuestieDB.GetQuest then
        local qData = SafeCall(QuestieDB.GetQuest, QuestieDB, questID)
        if qData and qData.Objectives then
            for _, obj in pairs(qData.Objectives) do
                local coordsList = obj.Coordinates or obj.spawnList
                if coordsList and type(coordsList) == "table" then
                    for _, coord in ipairs(coordsList) do
                        local cZone = coord[3]
                        if cZone then
                            local qMap = ResolveZoneNameToMapID(tostring(cZone))
                            if qMap and qMap > 0 then
                                return qMap
                            end
                        end
                    end
                end
            end
        end
    end

    -- 4. Blizzard C_QuestLog.GetMapForQuestPOIs (validated against known zone registry)
    if C_QuestLog and C_QuestLog.GetMapForQuestPOIs then
        local pMap = SafeCall(C_QuestLog.GetMapForQuestPOIs, questID)
        if pMap and pMap > 0 and ZONE_CONTINENT_DATA[pMap] then
            return pMap
        end
    end

    -- 5. Blizzard Next Waypoint Map ID
    if C_QuestLog and C_QuestLog.GetNextWaypointMapID then
        local wpMapID = SafeCall(C_QuestLog.GetNextWaypointMapID, questID)
        if wpMapID and wpMapID > 0 and ZONE_CONTINENT_DATA[wpMapID] then
            return wpMapID
        end
    end

    return nil
end

-- Helper: Discover destination uiMapID where completed quest is turned in
GetQuestTurnInDestinationMapID = function(questID, questLogIndex)
    if not questID then return nil end

    -- 1. Check Quest Log Header Zone FIRST (the primary and authoritative source in WoW Classic)
    local headerZone = GetQuestLogZone(questID, questLogIndex)
    if headerZone and headerZone ~= "" then
        local normHeader = headerZone:lower():gsub("^the%s+", ""):gsub("^%s*(.-)%s*$", "%1")
        local rawLower = headerZone:lower():gsub("^%s*(.-)%s*$", "%1")

        if DUNGEON_LOCATIONS[normHeader] or DUNGEON_LOCATIONS[rawLower] then
            local dung = DUNGEON_LOCATIONS[normHeader] or DUNGEON_LOCATIONS[rawLower]
            return dung.mapID
        end

        if not (NON_ZONE_HEADERS[normHeader] or NON_ZONE_HEADERS[rawLower]) then
            local mapID = ResolveZoneNameToMapID(headerZone)
            if mapID and mapID > 0 then
                return mapID
            end
        end
    end

    -- 2. CrossZoneModule text scan fallback
    if ns.CrossZoneModule and ns.CrossZoneModule.GetQuestDestinationZone then
        local zoneStr = SafeCall(ns.CrossZoneModule.GetQuestDestinationZone, ns.CrossZoneModule, questID, questLogIndex)
        if zoneStr then
            local mapID = ResolveZoneNameToMapID(zoneStr)
            if mapID and mapID > 0 then return mapID end
        end
    end

    -- 3. Blizzard C_QuestLog.GetQuestPOIs (turn-in POIs)
    if C_QuestLog and C_QuestLog.GetQuestPOIs then
        local pois = SafeCall(C_QuestLog.GetQuestPOIs, questID)
        if pois and type(pois) == "table" then
            for _, p in ipairs(pois) do
                if p and p.mapID and p.mapID > 0 and (p.isTurnIn or p.completed) then
                    return p.mapID
                end
            end
        end
    end

    -- 4. Blizzard Next Waypoint fallback
    if C_QuestLog and C_QuestLog.GetNextWaypointMapID then
        local wpMapID = SafeCall(C_QuestLog.GetNextWaypointMapID, questID)
        if wpMapID and wpMapID > 0 then
            return wpMapID
        end
    end

    return nil
end

-- Helper: Extract centroid of eligible objective POIs grouped by map
local function ExtractPOICentroid(pois, matchObjectiveIdx, fallbackMapID, playerMapID)
    if not pois or #pois == 0 then return nil, nil, nil end

    local eligible = {}
    local hasPlayerMap = false
    for _, p in ipairs(pois) do
        if p and p.x and p.y and p.x > 0 and p.y > 0 and not p.isTurnIn and not p.completed then
            if not matchObjectiveIdx or p.objectiveIndex == matchObjectiveIdx then
                -- CRITICAL FIX: Only assign fallbackMapID if known.
                -- NEVER default to playerMapID if the quest objective zone is elsewhere!
                local pMap = p.mapID or fallbackMapID
                if pMap and pMap > 0 then
                    table.insert(eligible, { x = p.x, y = p.y, mapID = pMap })
                    if playerMapID and pMap == playerMapID then
                        hasPlayerMap = true
                    end
                end
            end
        end
    end

    if #eligible == 0 then return nil, nil, nil end

    -- Prefer player's current zone only if active objective POIs genuinely belong to it
    local targetMap = (hasPlayerMap and playerMapID) or eligible[1].mapID
    local sumX, sumY, count = 0, 0, 0
    for _, item in ipairs(eligible) do
        if item.mapID == targetMap then
            sumX = sumX + item.x
            sumY = sumY + item.y
            count = count + 1
        end
    end

    if count > 0 then
        return sumX / count, sumY / count, targetMap
    end
    return nil, nil, nil
end

-- Helper: Locate turn-in NPC or object coordinates for completed quests (Centroid-centered)
local function GetQuestTurnInLocation(questID, questLogIndex, destMapID)
    if not questID then return nil end

    local tx, ty, tMapID
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and SafeCall(C_Map.GetBestMapForUnit, "player")

    -- 0. Check if quest turn-in belongs to a classic dungeon/raid
    local headerZone = GetQuestLogZone(questID, questLogIndex)
    if headerZone then
        local normHeader = headerZone:lower():gsub("^the%s+", ""):gsub("^%s*(.-)%s*$", "%1")
        local dung = DUNGEON_LOCATIONS[normHeader] or DUNGEON_LOCATIONS[headerZone:lower()]
        if dung then
            return dung.x, dung.y, dung.mapID
        end
    end

    -- Resolve destination map for turn-in
    destMapID = destMapID or (GetQuestTurnInDestinationMapID and GetQuestTurnInDestinationMapID(questID, questLogIndex))

    -- 1. Try Blizzard's C_QuestLog.GetQuestsOnMap
    -- Priority: Check destMapID first!
    if C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local mapsToCheck = {}
        if destMapID then
            table.insert(mapsToCheck, destMapID)
            if C_Map and C_Map.GetMapInfo then
                local dInfo = SafeCall(C_Map.GetMapInfo, destMapID)
                if dInfo and dInfo.parentMapID and dInfo.parentMapID > 0 then
                    table.insert(mapsToCheck, dInfo.parentMapID)
                end
            end
        end
        if playerMapID and playerMapID ~= destMapID then
            table.insert(mapsToCheck, playerMapID)
            if C_Map and C_Map.GetMapInfo then
                local pInfo = SafeCall(C_Map.GetMapInfo, playerMapID)
                if pInfo and pInfo.parentMapID and pInfo.parentMapID > 0 and pInfo.parentMapID ~= destMapID then
                    table.insert(mapsToCheck, pInfo.parentMapID)
                end
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
                local wpMap = C_QuestLog.GetNextWaypointMapID and SafeCall(C_QuestLog.GetNextWaypointMapID, questID)
                tMapID = wpMap or destMapID
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
                tMapID = destMapID
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
                if p and p.x and p.y and p.x > 0 and p.y > 0 and (p.isTurnIn or p.completed) then
                    local pMap = p.mapID or destMapID
                    if not poiMapID or pMap == poiMapID or count == 0 then
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
                tMapID = poiMapID or destMapID
            end
        end
    end

    -- 5. Cross-zone fallback: If no coordinates could be found by pin APIs, but we know the destination zone,
    -- direct player to the center of the destination zone so the arrow points in the correct direction!
    if not (tx and ty) and destMapID then
        tx, ty, tMapID = 0.5, 0.5, destMapID
    end

    return tx, ty, tMapID
end

-- Helper: Locate quest objective center (centroid of quest zone area / spawns / POIs)
local function GetQuestObjectiveLocation(questID, destMapID)
    if not questID then return nil, nil, nil end

    local wx, wy, uiMapID
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and SafeCall(C_Map.GetBestMapForUnit, "player")

    -- 0. Check if quest objective belongs to a classic dungeon/raid
    local headerZone = GetQuestLogZone(questID)
    if headerZone then
        local normHeader = headerZone:lower():gsub("^the%s+", ""):gsub("^%s*(.-)%s*$", "%1")
        local dung = DUNGEON_LOCATIONS[normHeader] or DUNGEON_LOCATIONS[headerZone:lower()]
        if dung then
            return dung.x, dung.y, dung.mapID
        end
    end

    destMapID = destMapID or (GetQuestObjectiveDestinationMapID and GetQuestObjectiveDestinationMapID(questID))

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

    -- 1. Blizzard Native Objective POIs (Filter out turn-in and already-completed objectives)
    if not (wx and wy) and C_QuestLog and C_QuestLog.GetQuestPOIs then
        local pois = SafeCall(C_QuestLog.GetQuestPOIs, questID)
        if pois and type(pois) == "table" and #pois > 0 then
            -- Pass A: Specific incomplete objective POIs (matches first incomplete objective)
            if firstIncompleteIdx then
                wx, wy, uiMapID = ExtractPOICentroid(pois, firstIncompleteIdx, destMapID, playerMapID)
            end
            -- Pass B: Any active objective POI (explicitly excluding isTurnIn and completed)
            if not (wx and wy) then
                wx, wy, uiMapID = ExtractPOICentroid(pois, nil, destMapID, playerMapID)
            end
        end
    end

    -- 2. Blizzard C_QuestLog.GetQuestsOnMap: Centroid of all quest pins on map (excluding isTurnIn and isComplete)
    if not (wx and wy) and C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local mapsToCheck = {}
        local checked = {}
        local function AddMap(m)
            if m and m > 0 and not checked[m] then
                checked[m] = true
                table.insert(mapsToCheck, m)
            end
        end

        AddMap(destMapID)
        AddMap(playerMapID)

        -- Check parent maps
        if C_Map and C_Map.GetMapInfo then
            if destMapID then
                local dInfo = SafeCall(C_Map.GetMapInfo, destMapID)
                if dInfo and dInfo.parentMapID and dInfo.parentMapID > 0 then
                    AddMap(dInfo.parentMapID)
                end
            end
            if playerMapID then
                local pInfo = SafeCall(C_Map.GetMapInfo, playerMapID)
                if pInfo and pInfo.parentMapID and pInfo.parentMapID > 0 then
                    AddMap(pInfo.parentMapID)
                end
            end
        end

        for _, mid in ipairs(mapsToCheck) do
            local qList = SafeCall(C_QuestLog.GetQuestsOnMap, mid)
            if qList and type(qList) == "table" then
                local sumX, sumY, count = 0, 0, 0
                for _, q in ipairs(qList) do
                    if q.questID == questID and not q.isTurnIn and not q.isComplete and q.x and q.y and q.x > 0 and q.y > 0 then
                        sumX = sumX + q.x
                        sumY = sumY + q.y
                        count = count + 1
                    end
                end
                if count > 0 then
                    wx = sumX / count
                    wy = sumY / count
                    uiMapID = mid
                    break
                end
            end
        end
    end

    -- 3. Questie Integration: Query Questie DB for objective coordinates if installed
    if not (wx and wy) and type(QuestieDB) == "table" and QuestieDB.GetQuest then
        local qData = SafeCall(QuestieDB.GetQuest, QuestieDB, questID)
        if qData and qData.Objectives then
            for _, obj in pairs(qData.Objectives) do
                local coordsList = obj.Coordinates or obj.spawnList
                if coordsList and type(coordsList) == "table" then
                    for _, coord in ipairs(coordsList) do
                        local cx, cy, cZone = coord[1], coord[2], coord[3]
                        if cx and cy and cx > 0 and cy > 0 then
                            local qMap = (cZone and ResolveZoneNameToMapID(tostring(cZone))) or destMapID
                            if qMap then
                                wx, wy, uiMapID = cx / 100, cy / 100, qMap
                                break
                            end
                        end
                    end
                end
                if wx and wy then break end
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
            uiMapID = wpMapID or destMapID
        end
    end

    -- 5. Classic QuestPOIGetIconInfo fallback
    if not (wx and wy) and type(QuestPOIGetIconInfo) == "function" then
        local logIndex = (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and SafeCall(C_QuestLog.GetLogIndexForQuestID, questID))
        if logIndex then
            local _, posX, posY = SafeCall(QuestPOIGetIconInfo, logIndex)
            if posX and posY and posX > 0 and posY > 0 then
                wx, wy = posX, posY
                uiMapID = destMapID
            end
        end
    end

    -- 6. Cross-Zone Fallback: If no coordinates could be found by pin APIs, but we know the objective zone,
    -- direct player to the center of the objective zone so the arrow points in the correct direction!
    if not (wx and wy) and destMapID then
        wx, wy, uiMapID = 0.5, 0.5, destMapID
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

    arrivedQuestIDs[questID] = nil

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

    -- STRICT NAVIGATION DISPATCH:
    -- 1. If objectives ARE complete -> Point to quest turn-in location.
    -- 2. If objectives are NOT complete -> Point to quest objective location.
    if isComplete then
        title = title .. " (Turn-In)"
        local tx, ty, tMap = GetQuestTurnInLocation(questID, nil)
        if tx and ty then
            wx, wy, uiMapID = tx, ty, tMap
        else
            -- Graceful fallback if turn-in NPC position could not be resolved
            wx, wy, uiMapID = GetQuestObjectiveLocation(questID)
        end
    else
        -- Objective logic: Quest is incomplete. Always point to quest objective!
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

        -- Determine zone location name for display on the HUD arrow
        local headerZone = GetQuestLogZone(questID)
        local mapInfo = C_Map and C_Map.GetMapInfo and SafeCall(C_Map.GetMapInfo, uiMapID)
        local normHeader = headerZone and headerZone:lower():gsub("^the%s+", ""):gsub("^%s*(.-)%s*$", "%1")
        local rawLower = headerZone and headerZone:lower():gsub("^%s*(.-)%s*$", "%1")

        if normHeader and (DUNGEON_LOCATIONS[normHeader] or (rawLower and DUNGEON_LOCATIONS[rawLower])) then
            local dung = DUNGEON_LOCATIONS[normHeader] or DUNGEON_LOCATIONS[rawLower]
            currentTarget.zoneName = dung.zone
        elseif normHeader and not (NON_ZONE_HEADERS[normHeader] or (rawLower and NON_ZONE_HEADERS[rawLower])) and (ZONE_NAME_TO_UIMAP[normHeader] or (rawLower and ZONE_NAME_TO_UIMAP[rawLower])) then
            -- Genuine zone header (e.g. "Westfall", "Darkshore", "Redridge Mountains")
            currentTarget.zoneName = headerZone
        elseif mapInfo and mapInfo.name then
            currentTarget.zoneName = mapInfo.name
        elseif headerZone then
            currentTarget.zoneName = headerZone
        else
            currentTarget.zoneName = "Zone"
        end

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
        currentTarget.zoneName = GetQuestLogZone(questID) or "Zone"
        currentTarget.isCustom = false
        currentTarget.isComplete = isComplete
        currentTarget.waypointID = nil
        arrivalActive = false
        arrivalTimer = 0
        InvalidateTargetWorldCache()
        self:UpdateFrameVisibility()
        print(string.format("|cff00c0ff[Wayfinder]|r No map coordinates found for |cffffffff%s|r.", title))
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
    currentTarget.zoneName = wp.mapName or (wp.uiMapID and C_Map and C_Map.GetMapInfo and SafeCall(C_Map.GetMapInfo, wp.uiMapID) and SafeCall(C_Map.GetMapInfo, wp.uiMapID).name) or "Waypoint"
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
    local px, py = GetVectorXY(playerMapPos)
    if not px or not py then return nil end

    local playerContID, playerWorldPos = nil, nil
    if C_Map and C_Map.GetWorldPosFromMapPos then
        playerContID, playerWorldPos = SafeCall(C_Map.GetWorldPosFromMapPos, playerMapID, playerMapPos)
    end
    local pwx, pwy = GetVectorXY(playerWorldPos)

    local closestWP = nil
    local minDistance = math.huge

    for _, wp in ipairs(self.customWaypoints) do
        local dist = math.huge
        if wp.uiMapID == playerMapID then
            local dx = wp.x - px
            local dy = wp.y - py
            dist = math.sqrt(dx * dx + dy * dy) * 1000
        else
            local wwx, wwy = nil, nil
            if pwx and pwy and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
                local wpMapPos = CreateVector2D(wp.x, wp.y)
                local wpCont, wpWorldPos = SafeCall(C_Map.GetWorldPosFromMapPos, wp.uiMapID, wpMapPos)
                if not playerContID or not wpCont or playerContID == wpCont then
                    wwx, wwy = GetVectorXY(wpWorldPos)
                end
            end
            if pwx and pwy and wwx and wwy then
                local dN = wwx - pwx
                local dW = wwy - pwy
                dist = math.sqrt(dN * dN + dW * dW)
            else
                local cDist, _ = CalculateContinentOffset(playerMapID, px, py, wp.uiMapID, wp.x, wp.y)
                dist = cDist or 50000
            end
        end

        if dist < minDistance then
            minDistance = dist
            closestWP = wp
        end
    end

    if closestWP then
        self:SetWaypointAsTarget(closestWP)
        local distStr = self:FormatDistance(minDistance)
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
    currentTarget.flightDestZone = nil
    WayfinderModule.flightDestination = nil
    playedArrivalSound = false
    arrivedSoundTargetKey = nil

    navState.hasTarget = false
    navState.targetKey = nil
    navState.distanceYards = 0
    navState.relativeAngle = 0
    navState.isArrived = false
    navState.title = ""
    lastTitleFormatted = nil

    InvalidateTargetWorldCache()
    self:StopUpdateTimer()
    if self.RefreshMapPins then self:RefreshMapPins() end
    if self.hudFrame and self.hudFrame.titleText then
        self.hudFrame.titleText:SetText("")
        self.hudFrame.titleText:Hide()
    end
    self:UpdateHUDTextAnchors()
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
    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
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
    if UnitOnTaxi and UnitOnTaxi("player") then
        navState.hasTarget = true
        navState.isOnTaxi = true
        navState.distanceYards = 0
        navState.relativeAngle = 0
        navState.r = 0.2
        navState.g = 0.9
        navState.b = 1.0
        navState.isArrived = false
        navState.title = currentTarget.title or WayfinderModule.flightDestination or ""
        return true
    else
        navState.isOnTaxi = false
        WayfinderModule.flightDestination = nil
        if currentTarget then
            currentTarget.flightDestZone = nil
        end
    end

    if not currentTarget.hasTarget or not currentTarget.x or not currentTarget.y then
        navState.hasTarget = false
        return false
    end

    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not playerMapID then return false end

    local playerMapPos = C_Map.GetPlayerMapPosition(playerMapID, "player")
    if not playerMapPos then return false end

    local px, py = GetVectorXY(playerMapPos)
    if not px or not py then return false end

    local playerFacing = (GetPlayerFacing and GetPlayerFacing()) or 0

    lastPlayerMapX = px
    lastPlayerMapY = py
    lastPlayerFacing = playerFacing

    -- Verify target world cache is populated
    local targetMapID = currentTarget.uiMapID or playerMapID
    if not cachedTargetWorldX or cachedTargetMapID ~= targetMapID then
        UpdateTargetWorldCache()
    end

    local distanceYards = 0
    local targetAngle = 0
    local isSameZone = (playerMapID == targetMapID)

    if isSameZone then
        -- Fast Local Map Coordinates (ONLY valid when on the exact same zone map!)
        local dx = currentTarget.x - px
        local dy = currentTarget.y - py
        local deltaNorth = -dy
        local deltaWest = -dx
        targetAngle = math_atan2(deltaWest, deltaNorth)
        distanceYards = math_sqrt(dx * dx + dy * dy) * 1000
    else
        -- Cross-zone navigation
        local pwx, pwy = nil, nil
        local sameContinent = false
        if C_Map and C_Map.GetWorldPosFromMapPos then
            local playerContID, playerWorldPos = SafeCall(C_Map.GetWorldPosFromMapPos, playerMapID, playerMapPos)
            pwx, pwy = GetVectorXY(playerWorldPos)
            sameContinent = (not playerContID or not cachedTargetContinentID or playerContID == cachedTargetContinentID)
        end

        if pwx and pwy and cachedTargetWorldX and cachedTargetWorldY and sameContinent then
            local deltaNorth = cachedTargetWorldX - pwx
            local deltaWest = cachedTargetWorldY - pwy
            distanceYards = math_sqrt(deltaNorth * deltaNorth + deltaWest * deltaWest)
            targetAngle = math_atan2(deltaWest, deltaNorth)
        else
            -- Authoritative Continent Geometry Projection Engine
            local dist, angle = CalculateContinentOffset(playerMapID, px, py, targetMapID, currentTarget.x, currentTarget.y)
            distanceYards = dist
            targetAngle = angle
        end
    end

    targetWorldAngle = targetAngle

    local relativeAngle = (targetAngle - playerFacing) % TWO_PI
    if relativeAngle > MATH_PI then
        relativeAngle = relativeAngle - TWO_PI
    elseif relativeAngle < -MATH_PI then
        relativeAngle = relativeAngle + TWO_PI
    end

    local diff = math_abs(relativeAngle)
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
    -- CRITICAL: Arrival detection can ONLY trigger if player is on the same zone map as the destination!
    if isSameZone then
        if navState.isArrived and navState.hasTarget and (navState.targetKey == targetKey) then
            isArrived = distanceYards <= (threshold + 10)
        else
            isArrived = distanceYards <= threshold
        end
    else
        isArrived = false
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
            if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
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

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleText:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    titleText:SetJustifyH("CENTER")
    titleText:SetShadowColor(0, 0, 0, 1)
    titleText:SetShadowOffset(1, -1)
    titleText:SetWordWrap(false)
    frame.titleText = titleText

    local distText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    distText:SetPoint("TOP", titleText, "BOTTOM", 0, -1)
    distText:SetJustifyH("CENTER")
    distText:SetShadowColor(0, 0, 0, 1)
    distText:SetShadowOffset(1, -1)
    frame.distText = distText

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cff00c0ffWayfinder Navigation|r", 1, 1, 1)
        if currentTarget.hasTarget then
            if navState.isOnTaxi then
                GameTooltip:AddDoubleLine("Status:", "|cff00ffffIn Flight|r", 0.8, 0.8, 0.8, 0, 1, 1)
                if currentTarget.flightDestZone then
                    GameTooltip:AddDoubleLine("Destination:", currentTarget.flightDestZone, 0.8, 0.8, 0.8, 1, 1, 1)
                end
            elseif currentTarget.isFlightLeg then
                GameTooltip:AddDoubleLine("Action:", "|cff00ff00Take Flight|r", 0.8, 0.8, 0.8, 0, 1, 0)
                if currentTarget.title then
                    GameTooltip:AddDoubleLine("Target:", currentTarget.title, 0.8, 0.8, 0.8, 1, 1, 1)
                end
                local distStr = WayfinderModule:FormatDistance(navState.distanceYards)
                GameTooltip:AddDoubleLine("Distance:", distStr, 0.8, 0.8, 0.8, 1, 1, 1)
            elseif currentTarget.checkpointIndex and currentTarget.totalCheckpoints then
                GameTooltip:AddDoubleLine("Action:", "|cffffaa00On-Foot Highway|r", 0.8, 0.8, 0.8, 1, 0.7, 0)
                GameTooltip:AddDoubleLine("Checkpoint:", string.format("%d of %d", currentTarget.checkpointIndex, currentTarget.totalCheckpoints), 0.8, 0.8, 0.8, 1, 1, 1)
                if currentTarget.title then
                    GameTooltip:AddDoubleLine("Target:", currentTarget.title, 0.8, 0.8, 0.8, 1, 1, 1)
                end
                local distStr = WayfinderModule:FormatDistance(navState.distanceYards)
                GameTooltip:AddDoubleLine("Distance:", distStr, 0.8, 0.8, 0.8, 1, 1, 1)
            else
                if currentTarget.title then
                    GameTooltip:AddDoubleLine("Target:", currentTarget.title, 0.8, 0.8, 0.8, 1, 1, 1)
                end
                local distStr = WayfinderModule:FormatDistance(navState.distanceYards)
                GameTooltip:AddDoubleLine("Distance:", distStr, 0.8, 0.8, 0.8, 1, 1, 1)
                if #WayfinderModule.customWaypoints > 1 then
                    GameTooltip:AddLine(string.format("|cff00ff00%d active custom waypoints|r", #WayfinderModule.customWaypoints), 0.8, 0.8, 0.8)
                end
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

function WayfinderModule:UpdateHUDTextAnchors()
    if not self.hudFrame or not self.hudFrame.distText or not self.hudFrame.titleText then return end
    self.hudFrame.distText:ClearAllPoints()
    if self.hudFrame.titleText:IsShown() and (self.hudFrame.titleText:GetText() or "") ~= "" then
        self.hudFrame.distText:SetPoint("TOP", self.hudFrame.titleText, "BOTTOM", 0, -1)
    else
        self.hudFrame.distText:SetPoint("TOP", self.hudFrame, "BOTTOM", 0, -2)
    end
end

function WayfinderModule:ApplyHUDScale()
    if not self.hudFrame then return end
    local scale = (ns.db and ns.db.wayfinder and ns.db.wayfinder.arrowScale) or 1.0
    self.hudFrame:SetScale(scale)
end

function WayfinderModule:ApplyTypography(overrideFontPath)
    if not self.hudFrame then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local fontName = (ns.db and ns.db.fonts and ns.db.fonts.font) or "Nata Sans Bold"
    local fontPath = overrideFontPath or (ns.FetchFont and ns.FetchFont(fontName)) or (LSM and LSM:Fetch("font", fontName, true)) or ns.DEFAULT_FONT_PATH or STANDARD_TEXT_FONT

    local fontSize = (ns.db and ns.db.wayfinder and ns.db.wayfinder.hudFontSize) or 11
    local outline = (ns.db and ns.db.wayfinder and ns.db.wayfinder.hudFontOutline) or "OUTLINE"
    if outline == "NONE" or outline == "" then outline = nil end
    if self.hudFrame.distText and fontPath then
        if outline then
            pcall(self.hudFrame.distText.SetFont, self.hudFrame.distText, fontPath, fontSize, outline)
        else
            pcall(self.hudFrame.distText.SetFont, self.hudFrame.distText, fontPath, fontSize)
        end
    end

    local titleFontSize = (ns.db and ns.db.wayfinder and ns.db.wayfinder.hudTitleFontSize) or 11
    local titleOutline = (ns.db and ns.db.wayfinder and ns.db.wayfinder.hudTitleFontOutline) or "OUTLINE"
    if titleOutline == "NONE" or titleOutline == "" then titleOutline = nil end
    if self.hudFrame.titleText and fontPath then
        if titleOutline then
            pcall(self.hudFrame.titleText.SetFont, self.hudFrame.titleText, fontPath, titleFontSize, titleOutline)
        else
            pcall(self.hudFrame.titleText.SetFont, self.hudFrame.titleText, fontPath, titleFontSize)
        end
    end
end

function WayfinderModule:ApplyHUDSettings()
    if not self.hudFrame then return end
    self:ApplyHUDScale()
    self:ApplyTypography()
    self:UpdateHUDTextAnchors()
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
                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
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
                        if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
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
                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
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
                    if ns.FlushDBToGlobals then ns.FlushDBToGlobals() end
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
    local isWayfinderActive = (self.isEnabled ~= false) and (not ns.IsModuleEnabled or ns.IsModuleEnabled("wayfinder"))
    if not isWayfinderActive then
        return false
    end

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

local function GetPreviewDestinationTitle()
    local titleFormat = (ns.db and ns.db.wayfinder and ns.db.wayfinder.hudTitleFormat) or "zone"
    if titleFormat == "zone" then
        return "Westfall"
    elseif titleFormat == "quest" then
        return "The People's Militia"
    else
        return "Westfall - The People's Militia"
    end
end

function WayfinderModule:UpdateIdleState()
    local isWayfinderActive = self.isEnabled and (not ns.IsModuleEnabled or ns.IsModuleEnabled("wayfinder"))
    local isHudEnabled = isWayfinderActive and ns.db and ns.db.wayfinder and ns.db.wayfinder.enableHUDArrow
    local isInlineEnabled = isWayfinderActive and ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow

    if self.previewMode and isHudEnabled and self.hudFrame then
        if not self.hudFrame:IsShown() then
            self.hudFrame:Show()
        end
        self.hudFrame.arrow:SetRotation(0)
        self.hudFrame.arrow:SetVertexColor(0.1, 1.0, 0.2, 1.0)
        local showDest = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.showDestination == false)
        if showDest and self.hudFrame.titleText then
            self.hudFrame.titleText:Show()
            self.hudFrame.titleText:SetText(GetPreviewDestinationTitle())
        elseif self.hudFrame.titleText then
            self.hudFrame.titleText:Hide()
        end
        self:UpdateHUDTextAnchors()
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

    local isWayfinderActive = (self.isEnabled ~= false) and (not ns.IsModuleEnabled or ns.IsModuleEnabled("wayfinder"))
    local isHudEnabled = isWayfinderActive and ns.db and ns.db.wayfinder and ns.db.wayfinder.enableHUDArrow
    local isInlineEnabled = isWayfinderActive and ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow
    if not (isHudEnabled or isInlineEnabled) then
        self:StopUpdateTimer()
        return
    end

    local hideInCombat = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.hideInCombat == false)
    if hideInCombat and (self.inCombat or (InCombatLockdown and InCombatLockdown())) then
        if not isInlineEnabled then
            self:StopUpdateTimer()
            return
        end
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
            local showDest = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.showDestination == false)
            if showDest and self.hudFrame.titleText then
                self.hudFrame.titleText:Show()
                self.hudFrame.titleText:SetText(GetPreviewDestinationTitle())
            elseif self.hudFrame.titleText then
                self.hudFrame.titleText:Hide()
            end
            self:UpdateHUDTextAnchors()
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
        local isWayfinderActive = (self.isEnabled ~= false) and (not ns.IsModuleEnabled or ns.IsModuleEnabled("wayfinder"))
        local isInlineActive = isWayfinderActive and ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow and currentTarget.hasTarget
        if not isInlineActive then
            self:StopUpdateTimer()
        else
            self:StartUpdateTimer()
        end
    end
end

function WayfinderModule:OnUpdate(dt)
    if ns.IsModuleEnabled and not ns.IsModuleEnabled("wayfinder") then
        if self.hudFrame and self.hudFrame:IsShown() then
            self.hudFrame:Hide()
        end
        self:StopUpdateTimer()
        return
    end

    updateElapsed = updateElapsed + dt
    if updateElapsed < 0.025 then return end
    updateElapsed = 0

    local isWayfinderActive = (self.isEnabled ~= false) and (not ns.IsModuleEnabled or ns.IsModuleEnabled("wayfinder"))
    local isHudEnabled = isWayfinderActive and ns.db and ns.db.wayfinder and ns.db.wayfinder.enableHUDArrow
    local isInlineEnabled = isWayfinderActive and ns.db and ns.db.wayfinder and ns.db.wayfinder.enableInlineArrow

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

    -- Handle Arrival Auto-Clear Timer (custom waypoints only)
    if arrivalActive and navState.isArrived and currentTarget.isCustom then
        local clearDelay = (ns.db and ns.db.wayfinder and ns.db.wayfinder.arrivalClearDelay)
        if clearDelay == nil then clearDelay = 5 end

        if clearDelay > 0 then
            arrivalTimer = arrivalTimer + dt
            if arrivalTimer >= clearDelay then
                arrivalActive = false
                arrivalTimer = 0
                local wpID = currentTarget.waypointID
                if wpID then
                    self:OnWaypointArrived(wpID)
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

        self.hudFrame.arrow:SetRotation(navState.relativeAngle)
        lastRotationAngle = navState.relativeAngle

        if navState.r ~= lastColorR or navState.g ~= lastColorG or navState.b ~= lastColorB then
            self.hudFrame.arrow:SetVertexColor(navState.r, navState.g, navState.b, 1.0)
            lastColorR, lastColorG, lastColorB = navState.r, navState.g, navState.b
        end

        -- Destination Title text above distance
        local showDest = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.showDestination == false)
        local titleFormat = (ns.db and ns.db.wayfinder and ns.db.wayfinder.hudTitleFormat) or "zone"
        local destTitle = ""
        if showDest then
            if navState.isOnTaxi then
                local flightDest = WayfinderModule.flightDestination or currentTarget.flightDestZone or ""
                destTitle = (flightDest ~= "" and flightDest) or currentTarget.title or "Flight Destination"
            elseif currentTarget.isCustom then
                if titleFormat == "zone" and currentTarget.zoneName and currentTarget.zoneName ~= "" then
                    destTitle = currentTarget.zoneName
                elseif titleFormat == "both" and currentTarget.zoneName and currentTarget.title and currentTarget.title ~= currentTarget.zoneName then
                    destTitle = string.format("%s - %s", currentTarget.zoneName, currentTarget.title)
                else
                    destTitle = currentTarget.title or currentTarget.zoneName or "Waypoint"
                end
            else
                local zoneName = currentTarget.zoneName or ""
                local questTitle = currentTarget.title or ""
                if titleFormat == "zone" then
                    destTitle = (zoneName ~= "" and zoneName) or questTitle
                elseif titleFormat == "both" then
                    if zoneName ~= "" and questTitle ~= "" and zoneName ~= questTitle then
                        destTitle = string.format("%s - %s", zoneName, questTitle)
                    else
                        destTitle = (zoneName ~= "" and zoneName) or questTitle
                    end
                else
                    destTitle = (questTitle ~= "" and questTitle) or zoneName
                end
            end
        end

        if self.hudFrame.titleText then
            if showDest and destTitle ~= "" then
                if lastTitleFormatted ~= destTitle then
                    lastTitleFormatted = destTitle
                    self.hudFrame.titleText:SetText(destTitle)
                end
                self.hudFrame.titleText:Show()
            else
                self.hudFrame.titleText:Hide()
                lastTitleFormatted = nil
            end
        end
        self:UpdateHUDTextAnchors()

        local showDist = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.showDistance == false)
        local showETA = (ns.db and ns.db.wayfinder and ns.db.wayfinder.showETA == true) and (navState.etaFormatted and navState.etaFormatted ~= "")

        if showDist or showETA or navState.isOnTaxi then
            self.hudFrame.distText:Show()
            if navState.isOnTaxi then
                local flightDest = WayfinderModule.flightDestination or currentTarget.flightDestZone or ""
                local flightMsg
                if flightDest ~= "" then
                    flightMsg = string.format("|cff00ffffIN FLIGHT to %s|r", flightDest:upper())
                else
                    flightMsg = "|cff00ffffIN FLIGHT|r"
                end
                if lastDistFormatted ~= flightMsg then
                    lastDistFormatted = flightMsg
                    lastDistNumber = -2
                    self.hudFrame.distText:SetText(flightMsg)
                end
            elseif navState.isArrived then
                if lastDistArrived ~= true then
                    lastDistArrived = true
                    lastDistNumber = -1
                    lastDistFormatted = "|cff00ff00Arrived!|r"
                    self.hudFrame.distText:SetText(lastDistFormatted)
                end
            else
                lastDistArrived = false
                local yards = math_floor(navState.distanceYards + 0.5)
                local etaPart = showETA and string_format(" |cff88ccff(%s)|r", navState.etaFormatted) or ""
                local currentUnit = (ns.db and ns.db.wayfinder and ns.db.wayfinder.distanceUnit) or "imperial"
                if yards ~= lastDistNumber or lastEtaFormatted ~= (navState.etaFormatted or "") or lastDistUnit ~= currentUnit then
                    lastDistNumber = yards
                    lastDistUnit = currentUnit
                    lastEtaFormatted = navState.etaFormatted or ""
                    if showDist then
                        lastDistFormatted = string_format("%s%s", self:FormatDistance(navState.distanceYards), etaPart)
                    else
                        lastDistFormatted = string_format("|cff88ccffETA: %s|r", navState.etaFormatted)
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
            block.header.wayfinderArrow:SetRotation(navState.relativeAngle)
            lastInlineRotation = navState.relativeAngle
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
    lastDistUnit = nil
    lastDistFormatted = ""
    lastDistArrived = nil
    lastTitleFormatted = nil
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

local WAYPOINT_PIN_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Media\\Textures\\WaypoinMapPinUI"

local function ApplyPinTexture(icon, isActive)
    if not icon then return end

    icon:SetTexture(WAYPOINT_PIN_TEXTURE)
    if isActive then
        -- Tracked / Active Diamond Sprite: x=[44..68], y=[36..60] in 128x64
        icon:SetTexCoord(44 / 128, 68 / 128, 36 / 64, 60 / 64)
        icon:SetVertexColor(1, 1, 1, 1)
    else
        -- Untracked / Inactive Diamond Sprite: x=[76..100], y=[4..28] in 128x64
        icon:SetTexCoord(76 / 128, 100 / 128, 4 / 64, 28 / 64)
        icon:SetVertexColor(1, 1, 1, 1)
    end
end

local function ApplyPinVisual(pin, isActive)
    if not pin then return end
    if pin.label then pin.label:SetText("") end
    ApplyPinTexture(pin.icon, isActive)
    if isActive then
        pin:SetSize(30, 30)
    else
        pin:SetSize(26, 26)
    end
    if pin.glow then
        pin.glow:Hide()
    end
end

local mapPinOverlay = nil
local function GetWorldMapPinOverlay(canvas)
    if not mapPinOverlay and canvas then
        mapPinOverlay = CreateFrame("Frame", "BleakfiberWayfinderMapPinOverlay", canvas)
        mapPinOverlay:SetAllPoints(canvas)
        mapPinOverlay:SetFrameStrata("TOOLTIP")
        mapPinOverlay:SetFrameLevel(9990)
    end
    return mapPinOverlay or canvas
end

local function GetOrCreateWorldMapPin(parent)
    for _, pin in ipairs(worldMapPins) do
        if not pin:IsShown() then
            return pin
        end
    end

    local pinParent = GetWorldMapPinOverlay(parent)
    local pin = CreateFrame("Button", nil, pinParent)
    pin:SetSize(26, 26)
    pin:SetHitRectInsets(-6, -6, -6, -6)
    pin:SetFrameStrata("TOOLTIP")
    pin:SetFrameLevel(9999)
    pin:EnableMouse(true)
    pin:RegisterForClicks("AnyUp", "AnyDown")

    local glow = pin:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER", pin, "CENTER", 0, 0)
    glow:SetSize(26, 26)
    glow:Hide()
    pin.glow = glow

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(pin)
    ApplyPinTexture(icon, false)
    pin.icon = icon

    local highlight = pin:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(pin)
    highlight:SetTexture(WAYPOINT_PIN_TEXTURE)
    highlight:SetTexCoord(43 / 128, 69 / 128, 3 / 64, 29 / 64)
    highlight:SetBlendMode("ADD")
    pin.highlight = highlight

    local label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", pin, "CENTER", 0, 0)
    if ns.DEFAULT_HEADER_FONT_PATH then
        pcall(label.SetFont, label, ns.DEFAULT_HEADER_FONT_PATH, 10, "OUTLINE")
    end
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    pin.label = label

    pin:SetScript("OnEnter", function(self)
        if self.wp then
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
        end
    end)
    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local lastClickTime = 0
    local function HandlePinClick(self, button)
        local now = GetTime()
        if now - lastClickTime < 0.25 then return end
        lastClickTime = now

        if not self.wp then return end
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
    if InCombatLockdown and InCombatLockdown() then return end
    local enabled = not (ns.db and ns.db.wayfinder and ns.db.wayfinder.showMapPins == false)

    -- 1. Refresh & Reset World Map Pins
    for _, pin in ipairs(worldMapPins) do
        pin:Hide()
        pin.wp = nil
        pin.pinType = nil
        if pin.label then pin.label:SetText("") end
    end

    if not enabled or not WorldMapFrame or not WorldMapFrame:IsShown() then
        return
    end

    local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    local currentMapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not canvas or not currentMapID then return end

    local cWidth = canvas:GetWidth()
    local cHeight = canvas:GetHeight()
    if not cWidth or not cHeight or cWidth <= 50 or cHeight <= 50 then return end

    local isContinent = (currentMapID == 1414 or currentMapID == 1415)

    -- 2. Render Custom Waypoints
    if #self.customWaypoints > 0 then
        for _, wp in ipairs(self.customWaypoints) do
            local showWP = false
            local wx, wy = wp.x, wp.y

            if wp.uiMapID == currentMapID then
                showWP = true
            elseif isContinent and GetContinentCoords then
                local cx, cy, contID = GetContinentCoords(wp.uiMapID, wp.x, wp.y)
                if contID == currentMapID and cx and cy then
                    showWP = true
                    wx, wy = cx, cy
                end
            end

            if showWP and wx and wy then
                local pin = GetOrCreateWorldMapPin(canvas)
                pin.pinType = "custom"
                pin.wp = wp
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", wx * cWidth, -wy * cHeight)
                local isActive = (currentTarget.hasTarget and currentTarget.waypointID == wp.id)
                ApplyPinVisual(pin, isActive)
                pin:Show()
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
    if InCombatLockdown and InCombatLockdown() then return end
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

            if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
            if InCombatLockdown and InCombatLockdown() then return end
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
    if InCombatLockdown and InCombatLockdown() then return end
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
    if InCombatLockdown and InCombatLockdown() then return end
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
    self.isEnabled = true
    self.inCombat = (InCombatLockdown and InCombatLockdown()) or false
    self.previewMode = false

    local updateFrame = self.updateFrame or CreateFrame("Frame")
    self.updateFrame = updateFrame
    self.isUpdating = false

    self:CreateHUDFrame()
    self:UpdateFrameVisibility()
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

    -- Hook taxi map interactions to track destination name during flight
    local function HandleTaxiNodeTaken(nodeName)
        if not nodeName or nodeName == "" then return end
        local cleanName = nodeName:match("^([^,]+)") or nodeName
        cleanName = cleanName:match("^%s*(.-)%s*$")
        if cleanName and cleanName ~= "" then
            WayfinderModule.flightDestination = cleanName
            if currentTarget then
                currentTarget.flightDestZone = cleanName
            end
        end
    end

    if hooksecurefunc then
        if TakeTaxiNode then
            hooksecurefunc("TakeTaxiNode", function(slot)
                if TaxiNodeName and slot then
                    local name = TaxiNodeName(slot)
                    HandleTaxiNodeTaken(name)
                end
            end)
        end
        if C_TaxiMap and C_TaxiMap.TakeTaxiNode then
            hooksecurefunc(C_TaxiMap, "TakeTaxiNode", function(nodeID)
                local name
                if C_TaxiMap.GetTaxiMapNodeInfo and nodeID then
                    local info = C_TaxiMap.GetTaxiMapNodeInfo(nodeID)
                    name = info and info.name
                end
                if not name and TaxiNodeName and type(nodeID) == "number" then
                    name = TaxiNodeName(nodeID)
                end
                HandleTaxiNodeTaken(name)
            end)
        end
    end

    -- Hook WorldMapFrame for pin overlay, coordinates display, and + Waypoint button
    local isMapRefreshPending = false
    local function RequestMapRefresh()
        if InCombatLockdown and InCombatLockdown() then return end
        if isMapRefreshPending then return end
        isMapRefreshPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.04, function()
                isMapRefreshPending = false
                if InCombatLockdown and InCombatLockdown() then return end
                if WorldMapFrame and WorldMapFrame:IsShown() then
                    WayfinderModule:RefreshMapPins()
                    WayfinderModule:UpdateCoordinatesDisplay()
                    WayfinderModule:UpdateMapWaypointButton()
                end
            end)
        else
            isMapRefreshPending = false
            if InCombatLockdown and InCombatLockdown() then return end
            if WorldMapFrame and WorldMapFrame:IsShown() then
                WayfinderModule:RefreshMapPins()
                WayfinderModule:UpdateCoordinatesDisplay()
                WayfinderModule:UpdateMapWaypointButton()
            end
        end
    end

    if hooksecurefunc and WorldMapFrame then
        hooksecurefunc(WorldMapFrame, "Show", function()
            RequestMapRefresh()
        end)
        hooksecurefunc(WorldMapFrame, "Hide", function()
            isMapRefreshPending = false
            if coordsFrame then coordsFrame:Hide() end
        end)
    elseif WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", function()
            RequestMapRefresh()
        end)
        WorldMapFrame:HookScript("OnHide", function()
            isMapRefreshPending = false
            if coordsFrame then coordsFrame:Hide() end
        end)
    end

    if hooksecurefunc and WorldMapFrame and WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
            if InCombatLockdown and InCombatLockdown() then return end
            if WorldMapFrame:IsShown() then
                RequestMapRefresh()
            end
        end)
    end

    -- Hook click on WorldMap ScrollContainer to drop waypoints on Alt-Click and handle Right-Click zoom out
    local scrollContainer = WorldMapFrame and WorldMapFrame.ScrollContainer
    if scrollContainer and scrollContainer.HookScript then
        scrollContainer:HookScript("OnMouseUp", HandleWorldMapClick)
    elseif WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnMouseUp", HandleWorldMapClick)
    end

    -- Pre-initialize map UI elements at startup so opening the map causes zero allocation hitch
    self:UpdateCoordinatesDisplay()
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
    eventFrame:RegisterEvent("TAXIMAP_OPENED")
    eventFrame:RegisterEvent("TAXIMAP_CLOSED")
    eventFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
    eventFrame:RegisterEvent("PLAYER_CONTROL_LOST")
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
            if WorldMapFrame and WorldMapFrame:IsShown() then
                RequestMapRefresh()
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

        if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "PLAYER_CONTROL_GAINED" or event == "TAXIMAP_CLOSED" then
            UpdateTargetWorldCache()
            if currentTarget.hasTarget then
                WayfinderModule:CalculateNavigation()
            end
            WayfinderModule:RefreshMapPins()
            WayfinderModule:UpdateCoordinatesDisplay()
        end

        if event == "PLAYER_CONTROL_LOST" then
            if UnitOnTaxi and UnitOnTaxi("player") and currentTarget.hasTarget then
                WayfinderModule:CalculateNavigation()
            end
            return
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
                WayfinderModule:SetQuestTarget(ns.activeQuestID, true)
            end
        end
    end)
    self.eventFrame = eventFrame

    -- Slash Command Registrations: /way, /waypoint, /bfqway
    _G["SLASH_BLEAKFIBER_WAY1"] = "/way"
    _G["SLASH_BLEAKFIBER_WAY2"] = "/waypoint"
    _G["SLASH_BLEAKFIBER_WAY3"] = "/bfqway"
    SlashCmdList["BLEAKFIBER_WAY"] = function(msg)
        WayfinderModule:HandleWaySlash(msg)
    end

    -- Slash Command Registrations: /cway, /closestway
    _G["SLASH_BLEAKFIBER_CWAY1"] = "/cway"
    _G["SLASH_BLEAKFIBER_CWAY2"] = "/closestway"
    SlashCmdList["BLEAKFIBER_CWAY"] = function()
        WayfinderModule:SetClosestWaypoint()
    end

    -- Slash Command Registration: /waypaste
    _G["SLASH_BLEAKFIBER_PASTE1"] = "/waypaste"
    SlashCmdList["BLEAKFIBER_PASTE"] = function()
        WayfinderModule:OpenPasteDialog()
    end

    -- Hook into /bfq arrow, /bfq cway, and /bfq paste
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

function WayfinderModule:Disable()
    self.isEnabled = false
    self:StopUpdateTimer()
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
    end
    if self.hudFrame then
        self.hudFrame:Hide()
    end
    if self.coordFrame then
        self.coordFrame:Hide()
    end
    if self.pinOverlayFrame then
        self.pinOverlayFrame:Hide()
    end
    -- Hide all inline mini-arrows in quest tracker
    if ns.StandaloneTracker and ns.StandaloneTracker.activeBlocks then
        for _, block in pairs(ns.StandaloneTracker.activeBlocks) do
            if block.header and block.header.wayfinderArrow then
                block.header.wayfinderArrow:Hide()
            end
        end
        if ns.StandaloneTracker.UpdateTracker then
            ns.StandaloneTracker:UpdateTracker()
        end
    end
end

function WayfinderModule:Enable()
    self.isEnabled = true
    if self.eventFrame then
        self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        self.eventFrame:RegisterEvent("SUPER_TRACKING_CHANGED")
        self.eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
        self.eventFrame:RegisterEvent("QUEST_TURNED_IN")
        self.eventFrame:RegisterEvent("QUEST_REMOVED")
        self.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self.eventFrame:RegisterEvent("ZONE_CHANGED")
        self.eventFrame:RegisterEvent("PLAYER_CONTROL_LOST")
        self.eventFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
        self.eventFrame:RegisterEvent("TAXIMAP_CLOSED")
        self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    self:StartUpdateTimer()
    self:UpdateFrameVisibility()
    if self.pinOverlayFrame then
        self.pinOverlayFrame:Show()
        self:RefreshMapPins()
    end
    if ns.StandaloneTracker and ns.StandaloneTracker.UpdateTracker then
        ns.StandaloneTracker:UpdateTracker()
    end
end
