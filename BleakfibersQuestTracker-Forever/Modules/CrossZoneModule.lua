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

-- Localized Lua & WoW API bindings for performance & garbage reduction
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local string_lower, string_match, string_gsub, string_find = string.lower, string.match, string.gsub, string.find
local table_insert = table.insert
local wipe = table.wipe or wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local CrossZoneModule = {}
ns.CrossZoneModule = CrossZoneModule

-- Normalize zone strings for reliable case-insensitive matching
local function NormalizeZone(str)
    if not str or str == "" then return "" end
    local s = string_lower(str)
    s = string_gsub(s, "^the%s+", "")
    s = string_match(s, "^%s*(.-)%s*$") or s
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
    ["furlbrow's pumpkin farm"] = "westfall",
    ["furlbrow"] = "westfall",
    ["jangolode mine"] = "westfall",
    ["gold coast quarry"] = "westfall",

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

-- Pre-compile and pre-escape patterns to eliminate repetitive gsub churn inside text scanning loops
local PRECOMPILED_ZONES = {}
for _, zone in ipairs(ALL_KNOWN_ZONES) do
    table_insert(PRECOMPILED_ZONES, {
        zone = zone,
        len = #zone,
        escaped = string_gsub(zone, "%-", "%%-"),
    })
end

local PRECOMPILED_HUBS = {}
for hub, parentZone in pairs(HUB_TO_ZONE) do
    table_insert(PRECOMPILED_HUBS, {
        hub = hub,
        parentZone = parentZone,
        escaped = string_gsub(hub, "%-", "%%-"),
    })
end

-- =========================================================================
-- 4. Dynamic Objective & Full Quest Text Scanner
-- Scans strings for zone names, prepositions, and settlement hubs.
-- =========================================================================
local function ParseZonesFromText(text)
    if not text or text == "" then return nil end
    local lower = string_lower(text)
    local found = nil
    local seen = nil

    local function AddFound(zoneName)
        if zoneName then
            if not seen then seen = {} end
            if not seen[zoneName] then
                seen[zoneName] = true
                if not found then found = {} end
                table_insert(found, zoneName)
            end
        end
    end

    -- 1. Check Prepositional Zone Patterns using pre-escaped regex tokens
    -- Note: We deliberately exclude "of <zone>" because lore titles like "Mountaineer of Ironforge"
    -- or "Bishop of Stormwind" refer to NPC origins, not quest destinations.
    for _, zInfo in ipairs(PRECOMPILED_ZONES) do
        local escaped = zInfo.escaped
        if string_find(lower, "%f[%a]in%s+" .. escaped .. "%f[%A]")
            or string_find(lower, "%f[%a]to%s+" .. escaped .. "%f[%A]")
            or string_find(lower, "%f[%a]at%s+" .. escaped .. "%f[%A]")
            or string_find(lower, "%f[%a]into%s+" .. escaped .. "%f[%A]")
            or string_find(lower, "%f[%a]from%s+" .. escaped .. "%f[%A]")
            or string_find(lower, "%f[%a]near%s+" .. escaped .. "%f[%A]")
            or string_find(lower, "%f[%a]around%s+" .. escaped .. "%f[%A]")
            or string_find(lower, "%f[%a]within%s+" .. escaped .. "%f[%A]")
            or string_find(lower, "%f[%a]outside%s+" .. escaped .. "%f[%A]") then
            AddFound(zInfo.zone)
        elseif zInfo.len >= 7 and string_find(lower, "%f[%a]" .. escaped .. "%f[%A]") then
            -- Direct mention of distinctive zones (e.g. "riverlands", "riverglades", "zephras isles", etc.)
            AddFound(zInfo.zone)
        end
    end

    -- 2. Check Settlement / Hub Mappings using pre-escaped regex tokens
    for _, hInfo in ipairs(PRECOMPILED_HUBS) do
        if string_find(lower, "%f[%a]" .. hInfo.escaped .. "%f[%A]") then
            AddFound(hInfo.parentZone)
        end
    end

    return found
end

-- Cache for quest text blocks to avoid re-querying every frame
local questObjCache = {}
local questDescCache = {}

local function GetQuestTexts(questID, questLogIndex)
    if not questID then return {}, nil end
    if questObjCache[questID] then
        return questObjCache[questID], questDescCache[questID]
    end

    if not questLogIndex and questID then
        if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
            local idx = C_QuestLog.GetLogIndexForQuestID(questID)
            if idx and idx > 0 then questLogIndex = idx end
        end
        if not questLogIndex and GetNumQuestLogEntries and GetQuestLogTitle then
            local count = GetNumQuestLogEntries() or 0
            for i = 1, count do
                local _, _, _, isHeader, _, _, _, qID = GetQuestLogTitle(i)
                if not isHeader and qID == questID then
                    questLogIndex = i
                    break
                end
            end
        end
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

local staticNormValid = {}

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

    -- Normalize player's valid zones using static table (zero allocation)
    local normValid = staticNormValid
    wipe(normValid)
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
        local anyObjHadExplicitZone = false
        for _, objStr in ipairs(objTexts) do
            if CheckText(objStr) then
                return true
            end
            local parsed = ParseZonesFromText(objStr)
            if parsed and #parsed > 0 then
                anyObjHadExplicitZone = true
            end
        end
        -- If an objective explicitly specified a destination zone that isn't current, do not fall through to lore backstory.
        -- But if none of the objective lines mentioned any zone or settlement hub at all, fall through to description!
        if anyObjHadExplicitZone then
            return false
        end
    end

    -- Phase 2: Fallback to Quest Description only if objective texts were empty
    if descText and descText ~= "" then
        if CheckText(descText) then
            return true
        end
    end

    return false
end

-- Helper: Discover destination zone parsed from quest objective lines or description text
function CrossZoneModule:GetQuestDestinationZone(questID, questLogIndex)
    if not questID then return nil end
    local objTexts, descText = GetQuestTexts(questID, questLogIndex)
    if objTexts and #objTexts > 0 then
        for _, objStr in ipairs(objTexts) do
            local parsedZones = ParseZonesFromText(objStr)
            if parsedZones and #parsedZones > 0 then
                return parsedZones[1]
            end
        end
    end
    if descText and descText ~= "" then
        local parsedZones = ParseZonesFromText(descText)
        if parsedZones and #parsedZones > 0 then
            return parsedZones[1]
        end
    end
    return nil
end

-- Export tables and methods for external reference if needed
CrossZoneModule.UiMapToZone = UIMAP_TO_ZONE
CrossZoneModule.AllKnownZones = ALL_KNOWN_ZONES
CrossZoneModule.HubToZone = HUB_TO_ZONE
CrossZoneModule.ParseZonesFromText = ParseZonesFromText
CrossZoneModule.GetQuestTexts = GetQuestTexts

