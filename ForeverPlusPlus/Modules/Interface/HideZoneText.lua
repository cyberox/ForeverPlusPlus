-- Hide Zone Text: the names that fade in at the top middle of the screen on entering a zone or a
-- place in it, and the line under them saying whose territory it is, out of sight. The zone's name
-- is still on the minimap.
--
-- Blizzard's two frames (ZoneTextFrame, SubZoneTextFrame; Blizzard_FrameXML/Mainline/ZoneText.lua,
-- build 70938) fade by setting their own alpha every frame, so that isn't ours to set, and they
-- read each other's IsShown to pick what to say, so hiding one changes the other. The words
-- themselves are four font strings whose alpha nothing else sets: those are faded, and Blizzard's
-- frames go on as before, showing nothing.
local _, ns = ...

local ipairs, pairs = ipairs, pairs

local L = ns.L

local module = ns.NewModule("HideZoneText", L.HIDEZONETEXT_DESC, {
    enabled = false,
    zone = true,
    subzone = true,
    pvp = true,
})
module.title = L.HIDEZONETEXT_TITLE
module.category = "interface"
module.added = "1.7.1"

module.options = {
    { key = "zone", name = L.HIDEZONETEXT_ZONE, description = L.HIDEZONETEXT_ZONE_DESC },
    { key = "subzone", name = L.HIDEZONETEXT_SUBZONE, description = L.HIDEZONETEXT_SUBZONE_DESC },
    { key = "pvp", name = L.HIDEZONETEXT_PVP, description = L.HIDEZONETEXT_PVP_DESC },
}

-- Each option's font strings, by their global names.
local PARTS = {
    zone = { "ZoneTextString" },
    subzone = { "SubZoneTextString" },
    pvp = { "PVPInfoTextString", "PVPArenaTextString" },
}

local function apply()
    for key, names in pairs(PARTS) do
        local hide = module.enabled and module.db[key]
        for _, name in ipairs(names) do
            local text = _G[name]
            if text and text.SetAlpha then
                text:SetAlpha(hide and 0 or 1)
            end
        end
    end
end

module.OnEnable = apply
module.OnDisable = apply
module.OnOptionChanged = apply
