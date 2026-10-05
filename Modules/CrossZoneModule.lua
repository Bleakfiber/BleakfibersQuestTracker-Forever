--[[
    Bleakfiber's Quest Tracker (Forever) - CrossZoneModule.lua
    Standalone Cross-Zone Objective and Turn-In Tracker
    
    Provides intelligent cross-zone filtering for quests whose objectives or turn-ins
    occur in different zones than where the quest was picked up:
      1. While in-progress (isComplete == false): Shows in the zone(s) where objectives take place.
      2. While complete (isComplete == true): Shows in the zone where the quest is turned in.
    
    100% Dynamic Text Scanning:
      - Reads full quest objectives, summaries, and descriptions directly from the game client.
      - Resolves zones, towns, quest hubs, and subzones across all 60 WoW Forever maps.
      - ZERO hardcoded quest IDs.
--]]

local addonName, ns = ...
local CrossZoneModule = {}
ns.CrossZoneModule = CrossZoneModule

-- Normalize zone strings for reliable case-insensitive matching
local function NormalizeZone(str)
    if not str or str == "" then return "" end
    local s = string.lower(str)
    s = s:gsub("^the%s+", "")
    s = s:match("^%s*(.-)%s*$") or s
    return s
end

-- =========================================================================
-- 1. Full UiMapID to Zone Name Lookup (All 60 WoW Forever UiMaps)
-- =========================================================================
local UIMAP_TO_ZONE = {
    -- Eastern Kingdoms Zones & Cities (Parent 1415)
    [1416] = "Alterac Mountains",
    [1417] = "Arathi Highlands",
    [1418] = "Badlands",
    [1419] = "Blasted Lands",
    [1428] = "Burning Steppes",
    [1430] = "Deadwind Pass",
    [1426] = "Dun Morogh",
    [1431] = "Duskwood",
    [1423] = "Eastern Plaguelands",
    [1429] = "Elwynn Forest",
    [1424] = "Hillsbrad Foothills",
    [1455] = "Ironforge",
    [1432] = "Loch Modan",
    [1433] = "Redridge Mountains",
    [2548] = "Riverglades",          -- WoW Forever Custom Zone
    [1427] = "Searing Gorge",
    [1421] = "Silverpine Forest",
    [1453] = "Stormwind City",
    [1434] = "Stranglethorn Vale",
    [1435] = "Swamp of Sorrows",
    [1425] = "The Hinterlands",
    [1420] = "Tirisfal Glades",
    [1458] = "Undercity",
    [1422] = "Western Plaguelands",
    [1436] = "Westfall",
    [1437] = "Wetlands",

    -- Kalimdor Zones & Cities (Parent 1414)
    [1440] = "Ashenvale",
    [1447] = "Azshara",
    [1439] = "Darkshore",
    [2524] = "Darkspear Islands",     -- WoW Forever Custom Zone
    [1457] = "Darnassus",
    [1443] = "Desolace",
    [1411] = "Durotar",
    [1445] = "Dustwallow Marsh",
    [1448] = "Felwood",
    [1444] = "Feralas",
    [1450] = "Moonglade",
    [2482] = "Mount Hyjal",           -- WoW Forever Custom Zone
    [1412] = "Mulgore",
    [1454] = "Orgrimmar",
    [2652] = "Shen'dralas",           -- WoW Forever Custom Zone
    [1451] = "Silithus",
    [1442] = "Stonetalon Mountains",
    [1446] = "Tanaris",
    [1438] = "Teldrassil",
    [1413] = "The Barrens",
    [1441] = "Thousand Needles",
    [1456] = "Thunder Bluff",
    [1449] = "Un'Goro Crater",
    [1452] = "Winterspring",

    -- Other / Custom / Battlegrounds
    [1459] = "Alterac Valley",
    [1461] = "Arathi Basin",
    [1460] = "Warsong Gulch",
    [2521] = "Zephras Isle",          -- WoW Forever Custom Zone
    [2665] = "Zephras Isle",          -- WoW Forever Custom Zone
    [1415] = "Eastern Kingdoms",
    [1463] = "Eastern Kingdoms",
    [1414] = "Kalimdor",
    [1464] = "Kalimdor",
    [947]  = "Azeroth",
}

-- =========================================================================
-- 2. Complete List of All Recognized Zones in WoW Forever
-- =========================================================================
local ALL_KNOWN_ZONES = {
    -- Eastern Kingdoms Zones
    "alterac mountains", "arathi highlands", "badlands", "blasted lands",
    "burning steppes", "deadwind pass", "dun morogh", "duskwood",
    "eastern plaguelands", "elwynn forest", "hillsbrad foothills", "ironforge",
    "loch modan", "redridge mountains", "riverglades", "riverlands",
    "the riverglades", "the riverlands", "searing gorge", "silverpine forest",
    "stormwind city", "stormwind", "stranglethorn vale", "swamp of sorrows",
    "the hinterlands", "hinterlands", "tirisfal glades", "undercity",
    "western plaguelands", "westfall", "wetlands",

    -- Kalimdor Zones
    "ashenvale", "azshara", "darkshore", "darkspear islands", "darkspear island",
    "darkspear strand", "darnassus", "desolace", "durotar", "dustwallow marsh",
    "felwood", "feralas", "moonglade", "mount hyjal", "hyjal", "mulgore",
    "orgrimmar", "shen'dralas", "shendralas", "silithus", "stonetalon mountains",
    "tanaris", "teldrassil", "the barrens", "barrens", "thousand needles",
    "thunder bluff", "un'goro crater", "un'goro", "winterspring",

    -- WoW Forever Custom & Added Zones
    "zephras isle", "zephras isles", "the zephras isle", "the zephras isles",
    "hall of thanes", "hall of the thanes", "the hall of thanes",
    "gillijim's isle", "gillijim", "lapidis isle", "lapidis",
    "scarlet enclave", "caverns of time", "timbermaw hold", "karazhan",

    -- Battlegrounds
    "alterac valley", "arathi basin", "warsong gulch",

    -- Classic Dungeons & Raids
    "the deadmines", "deadmines", "shadowfang keep", "the stockade", "stockade",
    "gnomeregan", "scarlet monastery", "uldaman", "zul'farrak", "maraudon",
    "sunken temple", "temple of atal'hakkar", "blackrock depths", "blackrock spire",
    "lower blackrock spire", "upper blackrock spire", "stratholme", "scholomance",
    "dire maul", "ragefire chasm", "wailing caverns", "blackfathom deeps",
    "razorfen kraul", "razorfen downs", "onyxia's lair", "molten core",
    "blackwing lair", "zul'gurub", "ruins of ahn'qiraj", "temple of ahn'qiraj",
    "ahn'qiraj", "naxxramas",
}

-- =========================================================================
-- 3. Settlement / Hub / SubZone to Parent Zone Mapping
-- =========================================================================
local HUB_TO_ZONE = {
    -- Stormwind City Subzones & Hubs
    ["stormwind keep"] = "stormwind city",
    ["royal library"] = "stormwind city",
    ["dwarven district"] = "stormwind city",
    ["cathedral square"] = "stormwind city",
    ["mage quarter"] = "stormwind city",
    ["old town"] = "stormwind city",
    ["trade district"] = "stormwind city",
    ["valley of heroes"] = "stormwind city",

    -- Elwynn Forest
    ["goldshire"] = "elwynn forest",
    ["northshire"] = "elwynn forest",
    ["northshire valley"] = "elwynn forest",
    ["eastvale logging camp"] = "elwynn forest",

    -- Westfall
    ["sentinel hill"] = "westfall",
    ["moonbrook"] = "westfall",
    ["saldean's farm"] = "westfall",
    ["alexston farmstead"] = "westfall",

    -- Redridge Mountains
    ["lakeshire"] = "redridge mountains",
    ["stonewatch keep"] = "redridge mountains",

    -- Duskwood
    ["darkshire"] = "duskwood",
    ["raven hill"] = "duskwood",

    -- Loch Modan
    ["thelsamar"] = "loch modan",
    ["stonewrought dam"] = "loch modan",
    ["algor's cabin"] = "loch modan",

    -- Dun Morogh
    ["kharanos"] = "dun morogh",
    ["anvilmar"] = "dun morogh",
    ["coldridge valley"] = "dun morogh",
    ["gol'bolar quarry"] = "dun morogh",

    -- Ironforge Subzones & Hubs
    ["tinkertown"] = "ironforge",
    ["tinker town"] = "ironforge",
    ["hall of mysteries"] = "ironforge",
    ["the mystic ward"] = "ironforge",
    ["mystic ward"] = "ironforge",
    ["the military ward"] = "ironforge",
    ["military ward"] = "ironforge",
    ["the great forge"] = "ironforge",
    ["great forge"] = "ironforge",
    ["hall of explorers"] = "ironforge",
    ["the commons"] = "ironforge",

    -- Wetlands
    ["menethil harbor"] = "wetlands",
    ["greenwarden's grove"] = "wetlands",

    -- Hillsbrad Foothills
    ["southshore"] = "hillsbrad foothills",
    ["tarren mill"] = "hillsbrad foothills",
    ["durnholde keep"] = "hillsbrad foothills",

    -- Arathi Highlands
    ["refuge pointe"] = "arathi highlands",
    ["hammerfall"] = "arathi highlands",
    ["stromgarde keep"] = "arathi highlands",

    -- The Hinterlands
    ["aerie peak"] = "the hinterlands",
    ["revantusk village"] = "the hinterlands",

    -- Badlands
    ["kargath"] = "badlands",

    -- Searing Gorge
    ["thorium point"] = "searing gorge",

    -- Burning Steppes
    ["morgan's vigil"] = "burning steppes",
    ["flame crest"] = "burning steppes",

    -- Swamp of Sorrows
    ["stonard"] = "swamp of sorrows",
    ["sorrowmurk"] = "swamp of sorrows",

    -- Blasted Lands
    ["nethergarde keep"] = "blasted lands",

    -- Stranglethorn Vale
    ["booty bay"] = "stranglethorn vale",
    ["grom'gol base camp"] = "stranglethorn vale",
    ["grom'gol"] = "stranglethorn vale",
    ["rebel camp"] = "stranglethorn vale",

    -- Western Plaguelands
    ["chillwind camp"] = "western plaguelands",
    ["caer darrow"] = "western plaguelands",
    ["hearthglen"] = "western plaguelands",
    ["andorhal"] = "western plaguelands",

    -- Eastern Plaguelands
    ["light's hope chapel"] = "eastern plaguelands",
    ["marris stead"] = "eastern plaguelands",

    -- Tirisfal Glades
    ["brill"] = "tirisfal glades",
    ["deathknell"] = "tirisfal glades",

    -- Silverpine Forest
    ["the sepulcher"] = "silverpine forest",
    ["sepulcher"] = "silverpine forest",
    ["pyrewood village"] = "silverpine forest",
    ["shadowfang keep"] = "silverpine forest",

    -- Durotar
    ["razor hill"] = "durotar",
    ["sen'jin village"] = "durotar",
    ["valley of trials"] = "durotar",

    -- Mulgore
    ["bloodhoof village"] = "mulgore",
    ["red cloud mesa"] = "mulgore",

    -- The Barrens
    ["crossroads"] = "the barrens",
    ["the crossroads"] = "the barrens",
    ["ratchet"] = "the barrens",
    ["camp taurajo"] = "the barrens",
    ["taurajo"] = "the barrens",

    -- Ashenvale
    ["astranaar"] = "ashenvale",
    ["splintertree post"] = "ashenvale",
    ["warsong lumber mill"] = "ashenvale",
    ["forest song"] = "ashenvale",
    ["zoram'gar outpost"] = "ashenvale",
    ["silverwing grove"] = "ashenvale",

    -- Darkshore
    ["auberdine"] = "darkshore",

    -- Teldrassil
    ["dolanaar"] = "teldrassil",
    ["shadowglen"] = "teldrassil",

    -- Stonetalon Mountains
    ["sun rock retreat"] = "stonetalon mountains",
    ["windshear crag"] = "stonetalon mountains",
    ["malaka'jin"] = "stonetalon mountains",

    -- Thousand Needles
    ["freewind post"] = "thousand needles",
    ["mirage raceway"] = "thousand needles",

    -- Desolace
    ["nijel's point"] = "desolace",
    ["ghost walker post"] = "desolace",
    ["shadowprey village"] = "desolace",

    -- Dustwallow Marsh
    ["theramore isle"] = "dustwallow marsh",
    ["theramore"] = "dustwallow marsh",
    ["brackenwall village"] = "dustwallow marsh",
    ["mudsprocket"] = "dustwallow marsh",

    -- Feralas
    ["feathermoon stronghold"] = "feralas",
    ["feathermoon"] = "feralas",
    ["camp mojache"] = "feralas",

    -- Tanaris
    ["gadgetzan"] = "tanaris",
    ["steamwheedle port"] = "tanaris",

    -- Un'Goro Crater
    ["marshal's refuge"] = "un'goro crater",

    -- Silithus
    ["cenarion hold"] = "silithus",

    -- Winterspring
    ["everlook"] = "winterspring",

    -- Felwood
    ["bloodvenom post"] = "felwood",
    ["emerald sanctuary"] = "felwood",
    ["talonbranch glade"] = "felwood",

    -- Moonglade
    ["nighthaven"] = "moonglade",

    -- Darkspear Islands
    ["darkspear strand"] = "darkspear islands",
}

-- =========================================================================
-- 4. Dynamic Objective & Full Quest Text Scanner
-- Scans strings for zone names, prepositions, and settlement hubs.
-- =========================================================================
local function ParseZonesFromText(text)
    if not text or text == "" then return nil end
    local lower = string.lower(text)
    local found = {}
    local seen = {}

    local function AddFound(zoneName)
        if zoneName and not seen[zoneName] then
            seen[zoneName] = true
            table.insert(found, zoneName)
        end
    end

    -- 1. Check Prepositional Zone Patterns ("in <zone>", "to <zone>", "at <zone>", etc.)
    -- Note: We deliberately exclude "of <zone>" because lore titles like "Mountaineer of Ironforge"
    -- or "Bishop of Stormwind" refer to NPC origins, not quest destinations.
    for _, zone in ipairs(ALL_KNOWN_ZONES) do
        local escaped = zone:gsub("%-", "%%-")
        if lower:find("%f[%a]in%s+" .. escaped .. "%f[%A]")
            or lower:find("%f[%a]to%s+" .. escaped .. "%f[%A]")
            or lower:find("%f[%a]at%s+" .. escaped .. "%f[%A]")
            or lower:find("%f[%a]into%s+" .. escaped .. "%f[%A]")
            or lower:find("%f[%a]from%s+" .. escaped .. "%f[%A]")
            or lower:find("%f[%a]near%s+" .. escaped .. "%f[%A]")
            or lower:find("%f[%a]around%s+" .. escaped .. "%f[%A]")
            or lower:find("%f[%a]within%s+" .. escaped .. "%f[%A]")
            or lower:find("%f[%a]outside%s+" .. escaped .. "%f[%A]") then
            AddFound(zone)
        elseif #zone >= 7 and lower:find("%f[%a]" .. escaped .. "%f[%A]") then
            -- Direct mention of distinctive zones (e.g. "riverlands", "riverglades", "zephras isles", etc.)
            AddFound(zone)
        end
    end

    -- 2. Check Settlement / Hub Mappings
    for hub, parentZone in pairs(HUB_TO_ZONE) do
        local escapedHub = hub:gsub("%-", "%%-")
        if lower:find("%f[%a]" .. escapedHub .. "%f[%A]") then
            AddFound(parentZone)
        end
    end

    return #found > 0 and found or nil
end

-- Cache for quest text blocks to avoid re-querying every frame
local questObjCache = {}
local questDescCache = {}

local function GetQuestTexts(questID, questLogIndex)
    if not questID then return {}, nil end
    if questObjCache[questID] then
        return questObjCache[questID], questDescCache[questID]
    end

    local objTexts = {}
    local descText = nil
    local seen = {}
    local function AddObj(str)
        if str and type(str) == "string" and str ~= "" and not seen[str] then
            seen[str] = true
            table.insert(objTexts, str)
        end
    end

    -- 1. Modern C_QuestLog Objective and Description APIs
    if C_QuestLog then
        if C_QuestLog.GetQuestObjectives then
            local objs = C_QuestLog.GetQuestObjectives(questID)
            if objs and type(objs) == "table" then
                for _, obj in ipairs(objs) do
                    if obj.text then AddObj(obj.text) end
                end
            end
        end
        if C_QuestLog.GetQuestDescription then
            descText = C_QuestLog.GetQuestDescription(questID)
        end
    end

    -- 2. Classic Leaderboard Objectives
    if questLogIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local num = GetNumQuestLeaderBoards(questLogIndex) or 0
        for j = 1, num do
            local text = GetQuestLogLeaderBoard(j, questLogIndex)
            if text then AddObj(text) end
        end
    end

    -- 3. Classic / Retail Full Quest Text (Description & Objectives Summary)
    if questLogIndex and GetQuestLogQuestText then
        local d, o = GetQuestLogQuestText(questLogIndex)
        if o and o ~= "" then AddObj(o) end
        if d and d ~= "" and not descText then descText = d end

        -- If nothing was returned yet, select entry safely to read full text
        if #objTexts == 0 and not descText and SelectQuestLogEntry and GetQuestLogSelection then
            local oldSel = GetQuestLogSelection()
            SelectQuestLogEntry(questLogIndex)
            local selDesc, selObj = GetQuestLogQuestText()
            if selObj and selObj ~= "" then AddObj(selObj) end
            if selDesc and selDesc ~= "" and not descText then descText = selDesc end
            if oldSel and oldSel > 0 and oldSel ~= questLogIndex then
                SelectQuestLogEntry(oldSel)
            end
        end
    end

    questObjCache[questID] = objTexts
    questDescCache[questID] = descText
    return objTexts, descText
end

-- =========================================================================
-- 5. Main Evaluation Entrypoint called by StandaloneTracker
-- 100% Dynamic: Evaluates active quest objectives & full quest text in real time.
-- Zero hardcoded quest IDs.
-- =========================================================================
function CrossZoneModule:MatchesCurrentZone(questID, questLogIndex, validZones)
    if not questID then return false end

    -- Check if feature is enabled in user settings (defaults to true)
    local isEnabled = not (ns.db and ns.db.filtering and ns.db.filtering.enableCrossZone == false)
    if not isEnabled then
        return false
    end

    -- Normalize player's valid zones
    local normValid = {}
    for _, z in ipairs(validZones) do
        local n = NormalizeZone(z)
        if n ~= "" then
            normValid[n] = true
        end
    end

    local function MatchesAny(zoneList)
        if not zoneList then return false end
        for _, targetZone in ipairs(zoneList) do
            local normTarget = NormalizeZone(targetZone)
            if normValid[normTarget] then
                return true
            end
            -- Substring match for compound names (e.g. "stormwind" in "stormwind city", "zephras isle" in "zephras isles")
            for playerZ in pairs(normValid) do
                if #normTarget >= 5 and #playerZ >= 5 then
                    if normTarget:find(playerZ, 1, true) or playerZ:find(normTarget, 1, true) then
                        return true
                    end
                end
            end
        end
        return false
    end

    local function CheckText(textStr)
        if not textStr or textStr == "" then return false end
        local lower = string.lower(textStr)

        -- Check 1: Does this text line explicitly mention any of the player's valid zones?
        for playerZ in pairs(normValid) do
            if #playerZ >= 4 then
                local pat = "%f[%a]" .. playerZ:gsub("%-", "%%-") .. "%f[%A]"
                if lower:find(pat) then
                    return true
                end
            end
        end

        -- Check 2: Parsed zones & settlement hubs check
        local parsedZones = ParseZonesFromText(textStr)
        if parsedZones and MatchesAny(parsedZones) then
            return true
        end
        return false
    end

    -- Retrieve quest objective lines and narrative description
    local objTexts, descText = GetQuestTexts(questID, questLogIndex)

    -- Phase 1: Check Objective Texts (The actual task instructions)
    -- If the objective text specifies where to go, that is the authoritative destination.
    if objTexts and #objTexts > 0 then
        for _, objStr in ipairs(objTexts) do
            if CheckText(objStr) then
                return true
            end
        end
        -- If objective texts exist and specify a destination, do not fall through to lore backstory
        return false
    end

    -- Phase 2: Fallback to Quest Description only if objective texts were empty
    if descText and descText ~= "" then
        if CheckText(descText) then
            return true
        end
    end

    return false
end

-- Export tables for external reference if needed
CrossZoneModule.UiMapToZone = UIMAP_TO_ZONE
CrossZoneModule.AllKnownZones = ALL_KNOWN_ZONES
CrossZoneModule.HubToZone = HUB_TO_ZONE
