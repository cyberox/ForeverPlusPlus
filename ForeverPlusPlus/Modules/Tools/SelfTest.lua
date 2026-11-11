-- Self Test: a Debug module button (and `/fpp selftest`) that probes every Forever client API and
-- behavior the addon depends on but nobody has confirmed, and writes what it found to
-- ForeverPlusPlusDB.selfTest. `/reload` (or logging out) saves it to the SavedVariables file, so
-- the results can be read there. Some things need the player to do something (fly, die, fight):
-- running the test also starts a short recorder for those, and the manual steps are in the log.
-- The log is developer output, so it stays in English. Nothing runs until the button is pressed.
local _, ns = ...

local ipairs, pairs, type, pcall, tostring, tonumber = ipairs, pairs, type, pcall, tostring, tonumber
local format, sort, tconcat, date = string.format, table.sort, table.concat, date
local CreateFrame, GetTime, InCombatLockdown = CreateFrame, GetTime, InCombatLockdown
local L = ns.L

local module = ns.NewModule("SelfTest", L.SELFTEST_DESC, { enabled = true })
module.title = L.SELFTEST_TITLE
module.alwaysOn = true -- a debugging tool, not a change to the game

local MAX_LINES = 600
local lines -- the log being written: ForeverPlusPlusDB.selfTest.lines

-- Reading things safely ------------------------------------------------------------------------

-- A value as text, without touching a secret one.
local function text(value)
    if not ns.IsReadable(value) then
        return "<secret>"
    end
    if type(value) == "table" then
        return "<table>"
    end
    return tostring(value)
end

-- Several values as one line.
local function join(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = text((select(i, ...)))
    end
    return tconcat(parts, ", ")
end

-- A global by its dotted name ("C_TaxiMap.GetAllTaxiNodes"), or nil.
local function get(name)
    local value = _G
    for part in name:gmatch("[^.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
    end
    return value
end

-- Calls a global by name in protected mode: whether it worked, then what it returned.
local function call(name, ...)
    local fn = get(name)
    if type(fn) ~= "function" then
        return false, "missing"
    end
    return pcall(fn, ...)
end

-- The keys of a table, sorted, as one line.
local function keys(tbl)
    local list = {}
    for key in pairs(tbl) do
        list[#list + 1] = text(key)
    end
    sort(list)
    return tconcat(list, " ")
end

-- The log -------------------------------------------------------------------------------------

local function add(status, id, detail)
    if not lines or #lines >= MAX_LINES then
        return
    end
    lines[#lines + 1] = format("%-5s %s%s", status, id, detail and (": " .. detail) or "")
end

local function pass(id, detail) add("PASS", id, detail) end
local function fail(id, detail) add("FAIL", id, detail) end
local function info(id, detail) add("INFO", id, detail) end
local function skip(id, detail) add("SKIP", id, detail) end

local function section(title)
    if lines and #lines < MAX_LINES then
        lines[#lines + 1] = "== " .. title
    end
end

-- One line saying every named global is there (pass) or which ones are missing (fail).
local function present(id, names)
    local missing = {}
    for _, name in ipairs(names) do
        if get(name) == nil then
            missing[#missing + 1] = name
        end
    end
    if #missing == 0 then
        pass(id, "all present")
    else
        fail(id, "missing " .. tconcat(missing, ", "))
    end
end

-- Runs a check in protected mode so one error can't stop the rest.
local function check(fn)
    local ok, err = pcall(fn)
    if not ok then
        fail("error", text(err))
    end
end

local scratch -- a frame the checks try things on

-- The checks --------------------------------------------------------------------------------

local function checkClient()
    section("client")
    local version, build, _, toc = GetBuildInfo()
    info("client.build", join(version, build, toc))
    info("client.project", "WOW_PROJECT_ID " .. text(WOW_PROJECT_ID))
    info("client.beta", "IsBetaBuild " .. join(call("IsBetaBuild")) .. "; IsPublicTestClient "
        .. join(call("IsPublicTestClient")))
    info("client.surname", "UnitName " .. join(UnitName("player")) .. "; ShouldDisplaySurname "
        .. join(call("C_PlayerInfo.ShouldDisplaySurname")))
    info("client.combat", "InCombatLockdown " .. text(InCombatLockdown()))
    info("client.instance", "IsInInstance " .. join(IsInInstance()))
end

local function checkSettings()
    section("settings api")
    -- The ones Settings/ draws its pages with (canvas pages, drawn by the addon itself).
    present("settings.functions", { "Settings.RegisterCanvasLayoutCategory",
        "Settings.RegisterCanvasLayoutSubcategory", "Settings.RegisterAddOnCategory",
        "Settings.OpenToCategory", "Settings.CreateSliderOptions" })
end

local function checkFrames()
    section("load-on-demand frames")
    for _, name in ipairs({ "ProfessionsFrame", "AuctionHouseFrame", "PlayerSpellsFrame",
        "ClassTalentFrame", "SpellBookFrame", "WorldMapFrame", "BattlefieldMapFrame", "TaxiFrame",
        "FlightMapFrame", "MovieFrame", "EditModeManagerFrame" }) do
        info("frame." .. name, get(name) and "exists" or "not there yet")
    end
    for _, addon in ipairs({ "Blizzard_Professions", "Blizzard_AuctionHouseUI",
        "Blizzard_PlayerSpells", "Blizzard_WorldMap", "Blizzard_FlightMap", "Blizzard_BattlefieldMap",
        "Blizzard_EditMode" }) do
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon)
        local loadable, reason
        if C_AddOns and C_AddOns.GetAddOnInfo then
            local _
            _, _, _, loadable, reason = C_AddOns.GetAddOnInfo(addon)
        end
        info("addon." .. addon, format("loaded %s, loadable %s, reason %s", text(loaded),
            text(loadable), text(reason)))
    end
end

local function checkCVars()
    section("console variables")
    for _, name in ipairs({ "nameplateShowFriendlyPlayers", "nameplateShowFriends",
        "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateShowOnlyNames", "autoDismount",
        "autoDismountFlying", "autoStand", "autoUnshift", "showDungeonEntrancesOnMap",
        "autoLootDefault", "floatingCombatTextCombatDamage" }) do
        local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)
        local default = C_CVar and C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name)
        if value == nil then
            info("cvar." .. name, "not on this client")
        else
            info("cvar." .. name, format("value %s, default %s", text(value), text(default)))
        end
    end
    local list = get("ConsoleGetAllCommands") and ConsoleGetAllCommands()
    if type(list) ~= "table" then
        fail("cvar.list", "ConsoleGetAllCommands gave " .. text(list))
        return
    end
    local cvarType = Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar or 0
    local count = 0
    for _, entry in ipairs(list) do
        if entry.commandType == cvarType then
            count = count + 1
        end
    end
    info("cvar.list", format("%d commands, %d of them CVars", #list, count))
end

local function checkTaxi()
    section("flight masters (open one for the rest)")
    present("taxi.functions", { "TakeTaxiNode", "GetNumRoutes", "TaxiGetNodeSlot",
        "TaxiRequestEarlyLanding", "UnitOnTaxi", "GetTaxiMapID", "TaxiNodeName", "TaxiNodeCost",
        "NumTaxiNodes", "TaxiNodeGetType", "C_TaxiMap.GetAllTaxiNodes",
        "C_TaxiMap.GetTaxiNodesForMap", "C_TaxiMap.ShouldMapShowTaxiNodes" })
    local states = Enum.FlightPathState
    info("taxi.states", states and keys(states) or "Enum.FlightPathState missing")
    info("taxi.onTaxi", "UnitOnTaxi('player') " .. join(call("UnitOnTaxi", "player")))
    -- A field for a flight's length would settle whether the game knows it.
    -- Just after the flight map closes it gives -1 rather than nil.
    local mapID = get("GetTaxiMapID") and GetTaxiMapID()
    if type(mapID) ~= "number" or mapID <= 0 then
        skip("taxi.nodes", "no flight master open: talk to one and run this again")
        return
    end
    local nodes = C_TaxiMap.GetAllTaxiNodes(mapID)
    if type(nodes) ~= "table" or #nodes == 0 then
        fail("taxi.nodes", "GetAllTaxiNodes gave none for map " .. text(mapID))
        return
    end
    info("taxi.node-fields", keys(nodes[1]))
    local byState = {}
    for _, node in ipairs(nodes) do
        local state = text(node.state)
        byState[state] = (byState[state] or 0) + 1
    end
    local parts = {}
    for state, n in pairs(byState) do
        parts[#parts + 1] = state .. "=" .. n
    end
    info("taxi.node-states", format("map %s, %d nodes: %s", text(mapID), #nodes, tconcat(parts, " ")))
    local current
    for _, node in ipairs(nodes) do
        if states and node.state == states.Current then
            current = node
        end
    end
    if current then
        pass("taxi.current", "Enum.FlightPathState.Current marks " .. text(current.name) .. " ("
            .. text(current.nodeID) .. ")")
    else
        fail("taxi.current", "no node is in state Current")
    end
end

local function checkMap()
    section("maps")
    present("map.functions", { "C_Map.GetMapRectOnMap", "C_Map.GetWorldPosFromMapPos",
        "C_Map.GetMapPosFromWorldPos", "C_Map.GetMapArtID", "C_Map.GetBestMapForUnit",
        "C_Map.GetMapArtLayers", "C_EncounterJournal.GetDungeonEntrancesForMap",
        "C_MapExplorationInfo.GetExploredMapTextures", "C_Texture.GetAtlasInfo" })
    present("map.waypoint", { "C_Map.SetUserWaypoint", "C_Map.ClearUserWaypoint",
        "C_Map.CanSetUserWaypointOnMap", "C_Map.GetMapChildrenInfo",
        "UiMapPoint.CreateFromCoordinates", "C_SuperTrack.SetSuperTrackedUserWaypoint",
        "hash_SlashCmdList" })
    present("map.arrow", { "C_Map.GetUserWaypoint", "C_Map.HasUserWaypoint",
        "C_Map.GetPlayerMapPosition", "C_Map.GetMapWorldSize", "GetPlayerFacing" })
    present("map.questarrow", { "C_SuperTrack.GetSuperTrackedQuestID",
        "C_QuestLog.GetNextWaypoint", "C_QuestLog.GetQuestsOnMap" })
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then
        skip("map.here", "the player has no map here")
        return
    end
    local mapInfo = C_Map.GetMapInfo(mapID)
    info("map.here", format("map %s %s, type %s, parent %s, art %s", text(mapID),
        text(mapInfo and mapInfo.name), text(mapInfo and mapInfo.mapType),
        text(mapInfo and mapInfo.parentMapID), join(call("C_Map.GetMapArtID", mapID))))
    -- Climb to the continent for the rect and world position calls.
    local continent, walk = nil, mapInfo
    while walk do
        if ns.WorldMap.IsContinent(walk) then
            continent = walk.mapID
            break
        end
        walk = walk.parentMapID and walk.parentMapID > 0 and C_Map.GetMapInfo(walk.parentMapID) or nil
    end
    if continent then
        local ok, rect = pcall(C_Map.GetMapRectOnMap, mapID, continent)
        info("map.rect", format("GetMapRectOnMap(%s, %s): %s", text(mapID), text(continent),
            ok and type(rect) == "table" and "a rect" or join(ok, rect)))
        local ok2, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0.5, 0.5))
        info("map.worldpos", format("GetWorldPosFromMapPos: %s, continent %s", text(ok2), text(cont))
            .. (ok2 and type(pos) == "table" and pos.GetXY and format(" at %.1f, %.1f", pos:GetXY()) or ""))
    else
        skip("map.rect", "no continent found above map " .. text(mapID))
    end
    for _, id in ipairs({ mapID, continent }) do
        local shows = call("C_TaxiMap.ShouldMapShowTaxiNodes", id)
        local ok, taxi = call("C_TaxiMap.GetTaxiNodesForMap", id)
        local _, entrances = call("C_EncounterJournal.GetDungeonEntrancesForMap", id)
        local _, explored = call("C_MapExplorationInfo.GetExploredMapTextures", id)
        info("map." .. id, format("shows taxi nodes %s; taxi nodes %s; dungeon entrances %s; explored textures %s",
            text(shows), ok and type(taxi) == "table" and #taxi or "none",
            type(entrances) == "table" and #entrances or "none",
            type(explored) == "table" and #explored or "none"))
        if type(entrances) == "table" and entrances[1] then
            info("map." .. id .. ".entrance-fields", keys(entrances[1]))
        end
    end
    -- Whether the zone map and the world map carry the label and provider frames we hook.
    local world = ns.WorldMap.Get()
    if world then
        local found = 0
        for provider in pairs(world.dataProviders or {}) do
            if type(provider) == "table" and provider.EvaluateLabels then
                found = found + 1
            end
            if type(provider) == "table" and provider.Label and provider.Label.EvaluateLabels then
                found = found + 1
            end
        end
        if found > 0 then
            pass("map.labels", found .. " provider(s) with EvaluateLabels on the world map")
        else
            fail("map.labels", "no world map provider has EvaluateLabels (Zone Info's hook won't fire)")
        end
    else
        skip("map.labels", "the world map addon hasn't loaded: open the map first")
    end
    info("map.zonemap", "BattlefieldMapFrame " .. (get("BattlefieldMapFrame") and
        (get("BattlefieldMapFrame.AddDataProvider") and "exists with AddDataProvider" or "exists, no AddDataProvider")
        or "not there yet (open the zone map)"))
    -- Atlases Points of Interest draws.
    local missing, have = {}, {}
    for _, atlas in ipairs({ "Dungeon", "Raid", "TaxiNode_Alliance", "TaxiNode_Horde",
        "TaxiNode_Neutral", "FlightMaster", "FlightMasterFerry", "Vehicle-Air-Horde",
        "Vehicle-TempleofKotmogu-CyanBall", "Vehicle-TempleofKotmogu-GreenBall",
        "poi-graveyard-neutral", "poi-soulspiritghost" }) do
        local found = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        local list = found and have or missing
        list[#list + 1] = atlas
    end
    if #missing == 0 then
        pass("map.atlases", "all found")
    else
        info("map.atlases", "missing: " .. tconcat(missing, ", ") .. "; found: " .. tconcat(have, ", "))
    end
end

local function checkSecrets()
    section("secret values")
    present("secret.functions", { "issecretvalue", "C_CurveUtil.CreateCurve", "UnitHealthPercent",
        "CurveConstants.ScaleTo100", "Enum.LuaCurveType" })
    local ok, curve = call("C_CurveUtil.CreateCurve")
    -- Forever gives a userdata (LuaCurveObject), not a table.
    if not (ok and (type(curve) == "table" or type(curve) == "userdata")) then
        fail("secret.curve", "CreateCurve gave " .. text(curve))
        return
    end
    local built, err = pcall(function()
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, 0.4)
        curve:AddPoint(0.35, 1)
    end)
    if not built then
        fail("secret.curve", "step curve: " .. text(err))
        return
    end
    local ok2, alpha = pcall(UnitHealthPercent, "player", true, curve)
    if not ok2 then
        fail("secret.curve", "UnitHealthPercent with the curve: " .. text(alpha))
        return
    end
    local ok3, err3 = pcall(scratch.SetAlpha, scratch, alpha)
    if ok3 then
        pass("secret.curve", "step curve through UnitHealthPercent into SetAlpha works (value "
            .. text(alpha) .. "), in combat " .. text(InCombatLockdown()))
    else
        fail("secret.curve", "SetAlpha refused the result: " .. text(err3))
    end
    info("secret.state", "C_Secrets " .. (get("C_Secrets") and keys(C_Secrets) or "missing"))
end

local function checkItems()
    section("items and merchants")
    present("items.repair", { "CanMerchantRepair", "GetRepairAllCost", "RepairAllItems",
        "CanGuildBankRepair", "IsInGuild", "GetGuildBankWithdrawMoney" })
    present("items.auction", { "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetNumReplicateItems",
        "C_AuctionHouse.GetReplicateItemInfo", "C_AuctionHouse.GetReplicateItemLink",
        "C_AuctionHouse.IsThrottledMessageSystemReady", "C_Item.GetItemInfo" })
    info("items.guild", "IsInGuild " .. join(call("IsInGuild")) .. "; withdraw money (-1 is no limit; "
        .. "only meaningful at a bank) " .. join(call("GetGuildBankWithdrawMoney")))
    present("items.lockpicking", { "C_SpellBook.IsSpellKnown", "GetProfessions", "GetProfessionInfo" })
    info("items.pick-lock", "Pick Lock (1804) known: " .. join(call("C_SpellBook.IsSpellKnown", 1804)))
    local skills = {}
    for _, index in pairs({ call("GetProfessions") }) do
        if type(index) == "number" then
            local name, _, level, max = GetProfessionInfo(index)
            skills[#skills + 1] = format("%s %s/%s", text(name), text(level), text(max))
        end
    end
    info("items.professions", #skills > 0 and tconcat(skills, "; ") or "none")
    -- Tracking: which spells are on, for the one-at-a-time question.
    present("items.tracking", { "C_Minimap.GetNumTrackingTypes", "C_Minimap.GetTrackingInfo",
        "C_Minimap.SetTracking" })
    local n = get("C_Minimap.GetNumTrackingTypes") and C_Minimap.GetNumTrackingTypes() or 0
    local on = {}
    for i = 1, n do
        local ok, data = pcall(C_Minimap.GetTrackingInfo, i)
        if ok and type(data) == "table" and data.active then
            on[#on + 1] = text(data.name)
        end
    end
    info("items.tracking-on", format("%d types; on: %s; mounted %s", n,
        #on > 0 and tconcat(on, ", ") or "none", join(call("IsMounted"))))
    local unit = UnitExists("target") and "target" or nil
    if unit then
        info("items.creature-type", "UnitCreatureType(target): " .. join(UnitCreatureType(unit)))
    else
        skip("items.creature-type", "target a creature to see whether the type ID comes second")
    end
    local tooltip = get("C_TooltipInfo.GetUnit") and unit and C_TooltipInfo.GetUnit(unit)
    if type(tooltip) == "table" and tooltip.lines then
        info("items.unit-title", "line 2 of the target's tooltip: "
            .. text(tooltip.lines[2] and tooltip.lines[2].leftText))
    end
end

local function checkPlayers()
    section("players, groups and events")
    present("players.functions", { "RepopMe", "CancelDuel", "StaticPopup_Hide", "Dismount",
        "C_ChatInfo.PerformEmote", "StopCinematic", "MovieFrame.FinishMovie", "GetNumTitles", "IsTitleKnown",
        "C_MajorFactions.GetMajorFactionProgressionInfo", "C_RecentAllies.IsRecentAllyByGUID" })
    info("players.ally-color", RECENT_ALLY_FONT_COLOR and join(RECENT_ALLY_FONT_COLOR:GetRGB())
        or "RECENT_ALLY_FONT_COLOR missing")
    -- Recent allies: answers for the player and each group member, without opening the tab. A
    -- member UnitIsUnit can't tell from the player (secret) is left out.
    local guids = { UnitGUID("player") }
    for i = 1, GetNumGroupMembers() do
        local unit = (IsInRaid() and "raid" or "party") .. i
        if UnitExists(unit) and not ns.IsTrueOrSecret(UnitIsUnit(unit, "player")) then
            guids[#guids + 1] = UnitGUID(unit)
        end
    end
    local answers = {}
    for _, guid in ipairs(guids) do
        local ok, value = call("C_RecentAllies.IsRecentAllyByGUID", guid)
        answers[#answers + 1] = ok and text(value) or ("error " .. text(value))
    end
    info("players.recent-allies", "IsRecentAllyByGUID (player, then group): " .. tconcat(answers, ", "))
    local ok, faction = call("C_MajorFactions.GetMajorFactionProgressionInfo", 2800)
    info("players.pvp-rank", ok and type(faction) == "table" and ("renown level " .. text(faction.renownLevel))
        or ("no data: " .. text(faction)))
    local titles, known = get("GetNumTitles") and GetNumTitles() or 0, 0
    for i = 1, titles do
        if IsTitleKnown(i) then
            known = known + 1
        end
    end
    info("players.titles", format("%d titles, %d known", titles, known))
    -- Events: RegisterEvent raises an error for an event the client doesn't have, if it's strict.
    local strict = not pcall(scratch.RegisterEvent, scratch, "FPP_NOT_AN_EVENT")
    if not strict then
        scratch:UnregisterEvent("FPP_NOT_AN_EVENT")
        info("events.strict", "RegisterEvent takes any name, so the results below prove nothing")
    end
    local bad = {}
    for _, event in ipairs({ "DUEL_REQUESTED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
        "KNOWN_TITLES_UPDATE", "CHAT_MSG_COMBAT_FACTION_CHANGE", "CINEMATIC_START",
        "REPLICATE_ITEM_LIST_UPDATE", "MAP_EXPLORATION_UPDATED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED",
        "PLAYER_DEAD", "UI_ERROR_MESSAGE", "MERCHANT_SHOW", "PLAYER_CONTROL_LOST",
        "PLAYER_CONTROL_GAINED" }) do
        if pcall(scratch.RegisterEvent, scratch, event) then
            scratch:UnregisterEvent(event)
        else
            bad[#bad + 1] = event
        end
    end
    if strict then
        if #bad == 0 then
            pass("events.names", "every event probed is known to the client")
        else
            fail("events.names", "unknown: " .. tconcat(bad, ", "))
        end
    end
end

local function checkUI()
    section("interface")
    present("ui.editmode", { "EditModeManagerFrame",
        "NineSliceUtil.ApplyLayout", "EditModeManagerFrame.EnterEditMode",
        "EditModeManagerFrame.ExitEditMode", "EditModeManagerFrame.ClearSelectedSystem",
        "MinimalSliderWithSteppersMixin", "CreateMinimalSliderFormatter" })
    present("ui.fonts", { "SystemFont_NamePlate", "CreateFontFamily", "TooltipDataProcessor.AddTooltipPostCall",
        "Menu.ModifyMenu" })
    local label = scratch:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText("Test")
    local height = label:GetStringHeight()
    info("ui.font-height", "GetStringHeight right after SetText: " .. text(height)
        .. (height == 0 and " (0 is the not-yet-loaded font bug)" or ""))
    info("ui.set-font-height", "FontString:SetFontHeight is " .. (label.SetFontHeight and "there" or "missing"))
    -- These two are protected on Retail; the outcome depends on combat, so say which it was.
    local a, b = pcall(scratch.SetMouseClickEnabled, scratch, false), pcall(scratch.SetMouseMotionEnabled, scratch, false)
    pcall(scratch.SetMouseClickEnabled, scratch, true)
    pcall(scratch.SetMouseMotionEnabled, scratch, true)
    add(a and b and "PASS" or "FAIL", "ui.mouse-enabled", format("SetMouseClickEnabled %s, SetMouseMotionEnabled %s, "
        .. "in combat %s (run this in combat too)", text(a), text(b), text(InCombatLockdown())))
    -- Timers and the C_ tables the addon leans on.
    present("ui.c-tables", { "C_Timer.After", "C_AddOns.IsAddOnLoaded", "C_Container", "C_SpecializationInfo",
        "C_Traits", "C_TooltipInfo.GetUnit", "C_NamePlate.GetNamePlates", "C_DamageMeter" })
end

-- How many entries each module's collected data holds (its defaults that are tables: prices,
-- times, learned flight points), whatever the module, so nothing here knows another module.
local function checkSaved()
    section("this addon's saved data")
    for _, name in ipairs(ns.order) do
        local other = ns.modules[name]
        local keys = {}
        for key, default in pairs(other.defaults or {}) do
            if type(default) == "table" then
                keys[#keys + 1] = key
            end
        end
        sort(keys)
        for _, key in ipairs(keys) do
            local count = 0
            for _ in pairs(other.db[key] or {}) do
                count = count + 1
            end
            info("saved." .. name .. "." .. key, count .. " entries"
                .. (other.perCharacter and other.perCharacter[key] and " for this character" or ""))
        end
    end
end

-- Things only the player can do -----------------------------------------------------------------

local MANUAL = {
    "MANUAL flight: talk to a flight master, run the self test again (it lists taxi.node-fields and states), "
        .. "hover a destination on the flight map, take a flight of at least a minute, and land. The "
        .. "recorder logs the route slots, control loss, UnitOnTaxi times, and what owns the tooltip.",
    "MANUAL early landing: on a flight, run /run TaxiRequestEarlyLanding() and note whether you land early "
        .. "and whether the recorder saw it.",
    "MANUAL learned flight nodes: at a flight master, compare taxi.node-states in the log with which "
        .. "points show learned on the world map (Points of Interest); screenshot both.",
    "MANUAL zone info corners: /fpp set WorldMap corner TOPRIGHT (then TOPLEFT, BOTTOMRIGHT) with the world map open "
        .. "on a zone and on a continent; screenshot each corner, and the tooltip on a dungeon row.",
    "MANUAL tracking mounted: mounted, run /run C_Minimap.SetTracking(1, true) and check the tracking icon and "
        .. "that you didn't dismount; unmounted, turn on Find Herbs then Find Minerals and see that one replaces the other.",
    "MANUAL death: die (or duel-fall), let Auto Release run, and check the recorder saw PLAYER_DEAD; in a "
        .. "battleground, run this test to see IsInInstance say pvp.",
    "MANUAL duel: have someone duel you with Auto Decline on; the recorder logs DUEL_REQUESTED's arguments.",
    "MANUAL repair: at a vendor with Auto Repair on, with and without guild funds; the recorder logs "
        .. "UI_ERROR_MESSAGE lines.",
    "MANUAL cinematic: trigger a cinematic with Skip Cinematics on and its Debug option on.",
    "MANUAL auction: open the Auction House, let Item Tooltips scan auction prices, then post an "
        .. "item; watch that the Sell tab list fills.",
    "MANUAL combat: run this test in combat (a dummy is enough): secret.curve, ui.mouse-enabled, cvar changes.",
    "MANUAL stand and shapeshift: sit, then /cast a spell that needs standing; note whether autoStand "
        .. "stands you, and the cvar.autoStand default logged above.",
}

-- The recorder: a frame that logs what happens after the test ran, until the next /reload. ------

local recorder

local function record(text_)
    add("REC", format("%.1f", GetTime()), text_)
end

local function recordTaxiMap()
    local mapID = GetTaxiMapID and GetTaxiMapID()
    record(format("TAXIMAP_OPENED map %s, FlightMapFrame %s, TaxiFrame %s", text(mapID),
        text(FlightMapFrame and FlightMapFrame:IsShown()), text(TaxiFrame and TaxiFrame:IsShown())))
    local nodes = mapID and C_TaxiMap.GetAllTaxiNodes(mapID) or {}
    local parts = {}
    for i, node in ipairs(nodes) do
        if i <= 60 then
            parts[#parts + 1] = format("%s:%s:%s", text(node.nodeID), text(node.slotIndex), text(node.state))
        end
    end
    record("nodes (id:slot:state) " .. tconcat(parts, " "))
end

local function recordTake(slot)
    local routes = GetNumRoutes and GetNumRoutes(slot)
    local stops = {}
    for i = 1, tonumber(routes) or 0 do
        stops[#stops + 1] = join(TaxiGetNodeSlot(slot, i, true)) .. " -> " .. join(TaxiGetNodeSlot(slot, i, false))
    end
    record(format("TakeTaxiNode slot %s (%s, cost %s), %s routes: %s", text(slot),
        text(TaxiNodeName and TaxiNodeName(slot)), text(TaxiNodeCost and TaxiNodeCost(slot)),
        text(routes), tconcat(stops, " | ")))
end

local tooltipSeen = {}
local function recordTooltip(tooltip)
    if tooltip ~= GameTooltip or not ((FlightMapFrame and FlightMapFrame:IsShown()) or (TaxiFrame and TaxiFrame:IsShown())) then
        return
    end
    local owner = tooltip:GetOwner()
    local data = owner and owner.taxiNodeData
    local id = data and data.nodeID or (owner and owner.GetID and owner:GetID()) or "?"
    if not tooltipSeen[id] then
        tooltipSeen[id] = true
        record(format("tooltip owner node %s: taxiNodeData %s (%s)", text(id), text(data ~= nil),
            type(data) == "table" and keys(data) or "no fields"))
    end
end

local wasOnTaxi, taxiStart = false, nil
local EVENT_ARGS = 4

local function onEvent(_, event, ...)
    if event == "TAXIMAP_OPENED" then
        recordTaxiMap()
    elseif event == "UI_ERROR_MESSAGE" then
        record("UI_ERROR_MESSAGE " .. join(...))
    elseif event == "CHAT_MSG_SYSTEM" or event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        local message = ...
        if event == "CHAT_MSG_COMBAT_FACTION_CHANGE" or (ns.IsText(message)
            and (message:find("standing") or message:find("reputation") or message:find("Friendly")
                or message:find("Honored") or message:find("Revered") or message:find("Exalted"))) then
            record(event .. " " .. text(message))
        end
    else
        local args = {}
        for i = 1, EVENT_ARGS do
            args[i] = text((select(i, ...)))
        end
        record(event .. " " .. tconcat(args, ", ")
            .. format(" | combat %s, instance %s, dead %s", text(InCombatLockdown()),
                join(IsInInstance()), text(UnitIsDeadOrGhost("player"))))
    end
end

local onUpdate = ns.Frames.Throttled(0.5, function()
    local now = UnitOnTaxi("player") and true or false
    if now ~= wasOnTaxi then
        wasOnTaxi = now
        if now then
            taxiStart = GetTime()
            record("UnitOnTaxi became true")
        else
            record(format("UnitOnTaxi became false after %.1f seconds", GetTime() - (taxiStart or GetTime())))
        end
    end
end)

local function onTakeTaxiNode(slot)
    if recorder then
        pcall(recordTake, slot)
    end
end

local function onEarlyLanding()
    record("TaxiRequestEarlyLanding called, UnitOnTaxi " .. text(UnitOnTaxi("player")))
end

local function onTooltipShow(tooltip)
    if recorder then
        pcall(recordTooltip, tooltip)
    end
end

local function startRecorder()
    if recorder then
        return
    end
    recorder = CreateFrame("Frame")
    recorder:SetScript("OnEvent", onEvent)
    recorder:SetScript("OnUpdate", onUpdate)
    for _, event in ipairs({ "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "PLAYER_CONTROL_LOST",
        "PLAYER_CONTROL_GAINED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "DUEL_REQUESTED",
        "CINEMATIC_START", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "KNOWN_TITLES_UPDATE",
        "CHAT_MSG_COMBAT_FACTION_CHANGE", "CHAT_MSG_SYSTEM", "UI_ERROR_MESSAGE", "MERCHANT_SHOW",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
        pcall(recorder.RegisterEvent, recorder, event)
    end
    -- Self Test is always on, so these always run once hooked. Each skips a function this
    -- client doesn't have.
    module:Hook("TakeTaxiNode", onTakeTaxiNode)
    module:Hook("TaxiRequestEarlyLanding", onEarlyLanding)
    module:Hook(GameTooltip, "Show", onTooltipShow)
end

-- Game data: the IDs the addon ships (ns.GameData), and what play has taught it since.
local function checkGameData()
    section("game data")
    local report, singles = ns.GameData.Audit()
    for _, set in ipairs(report) do
        local id = "data." .. set.label
        local learned = format("%d seeded, %d learned%s", set.size, set.learned,
            set.build and (" (build " .. text(set.build) .. ")") or "")
        if not set.kind then
            info(id, learned)
        elseif #set.missing == 0 then
            pass(id, learned .. "; every " .. set.kind .. " ID found")
        else
            local missing = {}
            for i, key in ipairs(set.missing) do
                missing[i] = text(key)
            end
            fail(id, learned .. "; no such " .. set.kind .. ": " .. tconcat(missing, " "))
        end
    end
    for _, entry in ipairs(singles) do
        local id = format("data.%s.%s", entry.kind, text(entry.id))
        if entry.found == nil then
            skip(id, entry.label .. ": couldn't check")
        elseif entry.found then
            pass(id, entry.label)
        else
            fail(id, entry.label .. " isn't in this client")
        end
    end
end

-- Running it ---------------------------------------------------------------------------------

local CHECKS = { checkClient, checkSettings, checkFrames, checkCVars, checkTaxi, checkMap,
    checkSecrets, checkItems, checkPlayers, checkUI, checkSaved, checkGameData }

---Runs every probe and writes the results to the saved log, starting the recorder.
---@return number count how many lines it wrote
function module.Run()
    scratch = scratch or CreateFrame("Frame")
    lines = {}
    ns.db.selfTest = {
        when = date("%Y-%m-%d %H:%M:%S"),
        lines = lines,
    }
    for _, fn in ipairs(CHECKS) do
        check(fn)
    end
    section("manual steps")
    for _, step in ipairs(MANUAL) do
        lines[#lines + 1] = step
    end
    section("recorder (from now until /reload)")
    startRecorder()
    ns.Print(format(L.SELFTEST_DONE, #lines))
    return #lines
end

-- Shown in the Debug module's settings (Settings/Debug.lua).
module.debugActions = {
    {
        name = L.SELFTEST_TITLE,
        button = L.SELFTEST_BUTTON,
        description = L.SELFTEST_BUTTON_DESC,
        fn = module.Run,
        section = L.DEBUG_SECTION_TOOLS,
    },
    {
        name = L.SELFTEST_GAMEDATA,
        button = L.SELFTEST_GAMEDATA_BUTTON,
        description = L.SELFTEST_GAMEDATA_DESC,
        fn = function()
            ns.Confirm("SELFTEST_GAMEDATA", L.SELFTEST_GAMEDATA_CONFIRM, function()
                ns.GameData.ForgetAll()
                ns.Print(L.SELFTEST_GAMEDATA_DONE)
            end)
        end,
        section = L.DEBUG_SECTION_TOOLS,
    },
}

ns.AddCommand("selftest", "", L.SELFTEST_COMMAND, module.Run, "Debug")
