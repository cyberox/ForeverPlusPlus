-- Console Variables' Popular group: CVars players look for, by section, each with a plain name
-- and help of our own (the game's help is often empty or written for its developers). Only ones
-- the game's Options don't have, or limit (Options stops Max Camera Distance at 2.0), and only
-- ones whose effect on Forever is known.
--
-- Picked 2026-11-05 from what comes up again and again: Advanced Interface Options' panels and its
-- described CVars (github.com/Stanzilla/AdvancedInterfaceOptions), Leatrix Plus's CVar options,
-- community lists of useful CVars, warcraft.wiki.gg, and settings players on Forever had changed
-- by hand. Every name was checked against Forever 1.60.1 (70532)'s CVar dump
-- (github.com/Ketho/BlizzardInterfaceResources, branch forever), which is where the defaults
-- below come from; 12.0 renamed or dropped some names older lists still use (nameplateMotion is
-- gone, the combat text ones are now _v2).
--
-- Left out on purpose:
-- - Ones Forever's Options set (Blizzard_SettingsDefinitions_*, `forever` UI source): camera turn
--   and tilt speed, follow style, water collision, damage numbers, Classic combat text, and the
--   sound ones. Options is where players look for those first.
-- - Ones only Forever has, whose effect nobody has written down (showTaxiNodeLearnedIcon,
--   canUseQuestItemWithLeftClick), and ones whose effect here is a guess (TargetNearestUseNew,
--   chatClassColorOverride's "Classic" value, ffxNether for spells Classic barely has). A
--   setting that may do nothing would only confuse.
-- - Ones a module of ours already sets (Quest Levels, Spell Ranks, XP Bar Text, Coordinates), so
--   the two don't fight.
--
-- A CVar a later build drops is skipped when the page is built, so a stale name costs nothing.
-- Each item: { CVar name, plain name, what it does and what its values mean }.
local _, ns = ...

local L = ns.L
local internal = ns.modules.ConsoleVariables.internal

internal.POPULAR = {
    {
        header = L.CONSOLEVARIABLES_POP_CAMERA,
        { "cameraDistanceMaxZoomFactor", L.CONSOLEVARIABLES_POP_ZOOM, L.CONSOLEVARIABLES_POP_ZOOM_DESC },
        { "cameraZoomSpeed", L.CONSOLEVARIABLES_POP_ZOOM_SPEED, L.CONSOLEVARIABLES_POP_ZOOM_SPEED_DESC },
        { "cameraIndirectVisibility", L.CONSOLEVARIABLES_POP_COLLISION, L.CONSOLEVARIABLES_POP_COLLISION_DESC },
    },
    {
        header = L.CONSOLEVARIABLES_POP_EFFECTS,
        { "ffxGlow", L.CONSOLEVARIABLES_POP_GLOW, L.CONSOLEVARIABLES_POP_GLOW_DESC },
        { "ffxDeath", L.CONSOLEVARIABLES_POP_DEATH, L.CONSOLEVARIABLES_POP_DEATH_DESC },
    },
    {
        header = L.CONSOLEVARIABLES_POP_NAMEPLATES,
        { "nameplateMaxDistance", L.CONSOLEVARIABLES_POP_PLATE_RANGE, L.CONSOLEVARIABLES_POP_PLATE_RANGE_DESC },
        { "nameplateOverlapV", L.CONSOLEVARIABLES_POP_PLATE_SPACING, L.CONSOLEVARIABLES_POP_PLATE_SPACING_DESC },
        { "nameplateMinAlpha", L.CONSOLEVARIABLES_POP_PLATE_FAR, L.CONSOLEVARIABLES_POP_PLATE_FAR_DESC },
        { "nameplateOccludedAlphaMult", L.CONSOLEVARIABLES_POP_PLATE_HIDDEN,
            L.CONSOLEVARIABLES_POP_PLATE_HIDDEN_DESC },
        { "nameplateSelectedScale", L.CONSOLEVARIABLES_POP_PLATE_TARGET, L.CONSOLEVARIABLES_POP_PLATE_TARGET_DESC },
        -- Asked for by a player; the game doesn't seem to save it (docs/forever-api.md), so it wants a lock.
        { "nameplateSimplifiedScale", L.CONSOLEVARIABLES_POP_PLATE_SIMPLIFIED,
            L.CONSOLEVARIABLES_POP_PLATE_SIMPLIFIED_DESC },
        { "nameplateShowEnemyTotems", L.CONSOLEVARIABLES_POP_PLATE_TOTEMS, L.CONSOLEVARIABLES_POP_PLATE_TOTEMS_DESC },
        { "nameplateShowEnemyPets", L.CONSOLEVARIABLES_POP_PLATE_PETS, L.CONSOLEVARIABLES_POP_PLATE_PETS_DESC },
    },
    {
        header = L.CONSOLEVARIABLES_POP_MAP,
        { "rotateMinimap", L.CONSOLEVARIABLES_POP_ROTATE, L.CONSOLEVARIABLES_POP_ROTATE_DESC },
        { "mapFade", L.CONSOLEVARIABLES_POP_MAP_FADE, L.CONSOLEVARIABLES_POP_MAP_FADE_DESC },
    },
    {
        header = L.CONSOLEVARIABLES_POP_CHAT,
        { "chatMouseScroll", L.CONSOLEVARIABLES_POP_CHAT_SCROLL, L.CONSOLEVARIABLES_POP_CHAT_SCROLL_DESC },
        { "showLootSpam", L.CONSOLEVARIABLES_POP_LOOT_SPAM, L.CONSOLEVARIABLES_POP_LOOT_SPAM_DESC },
    },
    {
        header = L.CONSOLEVARIABLES_POP_COMBAT,
        { "SpellQueueWindow", L.CONSOLEVARIABLES_POP_QUEUE, L.CONSOLEVARIABLES_POP_QUEUE_DESC },
        { "stopAutoAttackOnTargetChange", L.CONSOLEVARIABLES_POP_STOP_ATTACK,
            L.CONSOLEVARIABLES_POP_STOP_ATTACK_DESC },
        { "comboPointLocation", L.CONSOLEVARIABLES_POP_COMBO, L.CONSOLEVARIABLES_POP_COMBO_DESC },
        { "WorldTextScale_v2", L.CONSOLEVARIABLES_POP_TEXT_SIZE, L.CONSOLEVARIABLES_POP_TEXT_SIZE_DESC },
    },
    {
        header = L.CONSOLEVARIABLES_POP_INTERFACE,
        { "scriptErrors", L.CONSOLEVARIABLES_POP_ERRORS, L.CONSOLEVARIABLES_POP_ERRORS_DESC },
        { "alwaysCompareItems", L.CONSOLEVARIABLES_POP_COMPARE, L.CONSOLEVARIABLES_POP_COMPARE_DESC },
        { "AutoPushSpellToActionBar", L.CONSOLEVARIABLES_POP_PUSH_SPELLS, L.CONSOLEVARIABLES_POP_PUSH_SPELLS_DESC },
        { "autoLootRate", L.CONSOLEVARIABLES_POP_LOOT_RATE, L.CONSOLEVARIABLES_POP_LOOT_RATE_DESC },
    },
    {
        header = L.CONSOLEVARIABLES_POP_GRAPHICS,
        { "farclip", L.CONSOLEVARIABLES_POP_FARCLIP, L.CONSOLEVARIABLES_POP_FARCLIP_DESC },
        { "horizonClip", L.CONSOLEVARIABLES_POP_FOG_END, L.CONSOLEVARIABLES_POP_FOG_END_DESC },
        { "horizonStart", L.CONSOLEVARIABLES_POP_FOG_START, L.CONSOLEVARIABLES_POP_FOG_START_DESC },
        { "groundEffectDensity", L.CONSOLEVARIABLES_POP_GRASS, L.CONSOLEVARIABLES_POP_GRASS_DESC },
        { "groundEffectDist", L.CONSOLEVARIABLES_POP_GRASS_DIST, L.CONSOLEVARIABLES_POP_GRASS_DIST_DESC },
        { "weatherDensity", L.CONSOLEVARIABLES_POP_WEATHER, L.CONSOLEVARIABLES_POP_WEATHER_DESC },
    },
    {
        header = L.CONSOLEVARIABLES_POP_SCREENSHOTS,
        { "screenshotQuality", L.CONSOLEVARIABLES_POP_SHOT_QUALITY, L.CONSOLEVARIABLES_POP_SHOT_QUALITY_DESC },
        { "screenshotFormat", L.CONSOLEVARIABLES_POP_SHOT_FORMAT, L.CONSOLEVARIABLES_POP_SHOT_FORMAT_DESC },
    },
    {
        header = L.CONSOLEVARIABLES_POP_MOUSE,
        { "rawMouseEnable", L.CONSOLEVARIABLES_POP_RAW_MOUSE, L.CONSOLEVARIABLES_POP_RAW_MOUSE_DESC },
    },
}
