-- Spell Ranks: marks the spells on your action bars that have a higher rank you already know, so
-- a rank 1 Fireball left on the bar after leveling stands out. A small warning badge (or a red
-- tint) sits over the button, and spell tooltips say which rank is the best you know. /fpp ranks
-- lists them in chat. Action buttons are protected, so the marks are our own frames over them and
-- we only read which spell is in each slot. The game has no combat log for addons, and none is
-- needed: slots and spells change out of combat, and the marks refresh after a short wait.
local _, ns = ...

local ipairs, pairs, format = ipairs, pairs, string.format
local C_Spell = C_Spell
local Enum, GameTooltip = Enum, GameTooltip

local L = ns.L
local readable = ns.IsReadable
local Frames = ns.Frames
local ActionButtons, Spellbook, ItemButtons = ns.ActionButtons, ns.Spellbook, ns.ItemButtons

local module = ns.NewModule("SpellRanks", L.SPELLRANKS_DESC, {
    enabled = true,
    style = "badge", -- "badge" or "tint"
    corner = "TOPRIGHT", -- where the badge sits on the button
    size = 16, -- the badge's size, in pixels
    padding = 1, -- how far the badge sits in from its corner, in pixels
    tooltip = true, -- say the best known rank in spell tooltips
    chat = true,
})
module.title = L.SPELLRANKS_TITLE
module.category = "character"

-- The badge's corner, size, and padding matter only while the mark is the badge.
local function hasBadge(db)
    return db.style == "badge"
end

module.options = {
    {
        key = "style", name = L.SPELLRANKS_STYLE, description = L.SPELLRANKS_STYLE_DESC,
        choices = {
            { "badge", L.SPELLRANKS_STYLE_BADGE },
            { "tint", L.SPELLRANKS_STYLE_TINT },
        },
    },
    {
        key = "corner", name = L.ICONMARK_CORNER, description = L.SPELLRANKS_CORNER_DESC,
        choices = ItemButtons.CORNERS, shown = hasBadge, added = "1.2.0",
    },
    {
        key = "size", name = L.SPELLRANKS_SIZE, description = L.SPELLRANKS_SIZE_DESC,
        min = 8, max = 32, step = 2, format = L.ICONMARK_PIXELS, shown = hasBadge, added = "1.2.0",
    },
    {
        key = "padding", name = L.ICONMARK_PADDING, description = L.ICONMARK_PADDING_DESC,
        min = 0, max = 10, step = 1, format = L.ICONMARK_PIXELS, shown = hasBadge, added = "1.2.0",
    },
    { key = "tooltip", name = L.SPELLRANKS_TOOLTIP, description = L.SPELLRANKS_TOOLTIP_DESC },
    ns.ChatOption(L.SPELLRANKS_CHAT_DESC),
}

local DELAY = 0.2 -- seconds to wait for a burst of changes to settle

local ALERT_ATLAS = "services-icon-warning" -- Blizzard's yellow warning triangle, when it exists
local ALERT_FILE = "Interface\\DialogFrame\\DialogAlertIcon" -- and its older art

local known -- spell name -> the highest rank known, or nil until scanned
local lowSlots = {} -- { bar, slot, spellID, rank, best } for every marked button, in bar order
local lastCount = 0

-- A spell ID's name and rank don't change between spellbook scans, so they're kept until the next
-- one (dropped wherever `known` is): spellID -> { name, rank }.
local rankOf = {}

-- The spell's name and rank, or nil while the game hasn't loaded its data (it is asked for, and
-- SPELL_DATA_LOAD_RESULT refreshes us).
local function spellRank(spellID)
    local hit = rankOf[spellID]
    if hit then
        return hit[1], hit[2]
    end
    local name, text = C_Spell.GetSpellName(spellID), C_Spell.GetSpellSubtext(spellID)
    if not name or text == nil then
        if C_Spell.RequestLoadSpellData then
            C_Spell.RequestLoadSpellData(spellID)
        end
        return nil
    end
    if not readable(text) then
        return name, nil
    end
    local rank = Spellbook.Rank(spellID)
    rankOf[spellID] = { name, rank }
    return name, rank
end

-- Every spell in your spellbook's highest rank by name (Spellbook.Ranks leaves out passives and
-- the other spec's spells, which can't be put on the bar).
local function scan()
    local best = {}
    local ranks, complete = Spellbook.Ranks()
    for name, list in pairs(ranks) do
        best[name] = list[#list].rank
    end
    return best, complete
end

-- The spell a button's slot holds, or nil for an empty slot or an item, or a macro with no spell.
local function slotSpell(button)
    local kind, id, subType = ActionButtons.Content(button)
    if not (kind and id) then
        return nil
    end
    if kind == "macro" then
        -- A macro that shows a spell gives that spell's ID, not the macro's index (Mainline).
        return readable(subType) and subType == "spell" and id or nil
    end
    return kind == "spell" and id or nil
end

-- A mark is made out of combat only (Lib/ActionButtons.lua).
local marks = ActionButtons.Marks(function(frame)
    frame.tint = frame:CreateTexture(nil, "OVERLAY")
    frame.tint:SetPoint("TOPLEFT", 2, -2)
    frame.tint:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.tint:SetColorTexture(1, 0.1, 0.1, 0.4)
    frame.badge = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    if Frames.HasAtlas(ALERT_ATLAS) then
        frame.badge:SetAtlas(ALERT_ATLAS)
    else
        frame.badge:SetTexture(ALERT_FILE)
    end
end)

local function mark(button, on)
    local frame = on and marks.Get(button) or marks.Find(button)
    if not frame then
        return
    end
    frame:SetShown(on)
    local db = module.db
    local tint = db.style == "tint"
    frame.tint:SetShown(tint)
    frame.badge:SetShown(not tint)
    -- Inside the button's corner: past its edge, the next button over draws on top of it.
    frame.badge:SetSize(db.size, db.size)
    ItemButtons.PlaceInCorner(frame.badge, frame, db.corner, db.padding)
end

-- The spellbook scan's own row on the Profiler page. Profiler.Call keeps one result, so the
-- scan's two come back as a pair.
local Profiler = ns.Profiler
local PART_SCAN = Profiler.Part(module, L.SPELLRANKS_PART_SCAN)
local scanned = {}

local function scanBoth()
    scanned[1], scanned[2] = scan()
    return scanned
end

local function refresh()
    if not module.enabled then
        return
    end
    if not known then
        local result = Profiler.Call(PART_SCAN, scanBoth)
        local complete
        known, complete = result[1], result[2]
        -- Usable as it is; when data was still loading, SPELL_DATA_LOAD_RESULT scans again.
        module.incomplete = not complete
    end
    lowSlots = {}
    ActionButtons.Each(function(button, bar, slotNumber)
        local low = false
        local spellID = slotSpell(button)
        if spellID then
            local name, rank = spellRank(spellID)
            local best = name and rank and known[name]
            if best and rank < best then
                low = true
                lowSlots[#lowSlots + 1] = { bar = bar, slot = slotNumber,
                    spellID = spellID, rank = rank, best = best }
            end
        end
        mark(button, low)
    end)
    -- Say it once when a level or a new spell adds marks, not on every bar change.
    if #lowSlots > lastCount and module.announce then
        module:Print(format(L.SPELLRANKS_FOUND, #lowSlots))
    end
    lastCount = #lowSlots
    module.announce = false
end

local schedule = Frames.Coalesce(refresh, DELAY, module)

local function queue()
    if module.enabled then
        schedule()
    end
end

local function onSpellsChanged()
    known, rankOf = nil, {}
    queue()
end

-- Only a new spell or a level is worth a chat line; SPELLS_CHANGED also fires at every login.
local function onLearned()
    module.announce = true
    onSpellsChanged()
end

local function onLoaded()
    if module.incomplete then
        known, rankOf = nil, {}
    end
    queue()
end

-- Adds "Higher Rank Known: Rank 7" to a spell's tooltip when a higher rank than this one is
-- known, shaped like our item tooltip lines (white label, value at the right edge) so it doesn't
-- read as part of the gold spell description.
local function onTooltip(tooltip, data)
    if not (module.db.tooltip and known and tooltip == GameTooltip
        and data and readable(data.id) and data.id) then
        return
    end
    local name, rank = spellRank(data.id)
    local best = name and rank and known[name]
    if best and rank < best then
        tooltip:AddDoubleLine(L.SPELLRANKS_BEST, format(L.SPELLRANKS_BEST_RANK, best), 1, 1, 1, 1, 1, 1)
    end
end

function module:OnEnable()
    if not Spellbook.Available() then
        return
    end
    self:On("SPELLS_CHANGED", onSpellsChanged)
    self:On("LEARNED_SPELL_IN_SKILL_LINE", onLearned)
    self:On("PLAYER_LEVEL_UP", onLearned)
    self:On("ACTIONBAR_SLOT_CHANGED", queue)
    self:On("ACTIONBAR_PAGE_CHANGED", queue)
    self:On("UPDATE_BONUS_ACTIONBAR", queue)
    self:On("UPDATE_SHAPESHIFT_FORM", queue)
    self:On("PLAYER_REGEN_ENABLED", queue) -- buttons created late, when we were in combat
    self:On("SPELL_DATA_LOAD_RESULT", onLoaded)
    self:TooltipPostCall(Enum.TooltipDataType and Enum.TooltipDataType.Spell, onTooltip)
    known, rankOf = nil, {}
    lastCount = 0
    queue()
end

function module:OnDisable()
    marks.HideAll()
    known, lowSlots, rankOf = nil, {}, {}
end

function module:OnOptionChanged(key)
    if (key == "style" or key == "corner" or key == "size" or key == "padding") and self.enabled then
        queue()
    end
end

ns.AddCommand("ranks", "", L.SPELLRANKS_COMMAND, function()
    if not module.enabled then
        ns.Print(L.SPELLRANKS_OFF)
        return
    end
    if #lowSlots == 0 then
        ns.Print(L.SPELLRANKS_NONE)
        return
    end
    for _, entry in ipairs(lowSlots) do
        local link = C_Spell.GetSpellLink(entry.spellID) or C_Spell.GetSpellName(entry.spellID)
        ns.Print(format(L.SPELLRANKS_LINE, entry.bar, entry.slot, link, entry.rank, entry.best))
    end
end, "SpellRanks")
