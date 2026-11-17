-- Waylaid Crates: help filling Waylaid Crates, in two parts: what each bundle a crate takes costs
-- at auction, in its tooltip (Costs.lua), and a Waylaid Crates entry in the auction house's
-- categories listing what the crates in the bags still need (Category.lua). Each part is turned
-- on and off by its own dropdown (module:NewPart with `choices`). This file reads the bundles from
-- a crate's tooltip for both. Prices and item names come from Item Tooltips' Auction Prices
-- through ns.Prices.
local _, ns = ...

local ipairs, type, tonumber, setmetatable = ipairs, type, tonumber, setmetatable
local _G = _G

local L = ns.L

-- The parts add their dropdowns and defaults: `costs` (Costs.lua) and `list` (Category.lua).
local module = ns.NewModule("WaylaidCrates", L.WAYLAIDCRATES_DESC, { enabled = true })
module.title = L.WAYLAIDCRATES_TITLE
module.category = "items"
module.added = "0.9.0"

-- Before 0.9.0, Bundle Costs was Item Tooltips' Waylaid Crate Costs option.
ns.Migrate(1, function(db)
    local saved = db.modules or {}
    local old = saved.ItemTooltips
    if not (old and old.crates ~= nil) then
        return
    end
    local db = saved.WaylaidCrates or {}
    saved.WaylaidCrates = db
    ns.MoveSettings(old, db, { costs = "crates" })
    old.crates = nil
end)

module.internal = {}
local internal = module.internal

-- Bundles ----------------------------------------------------------------------------------------
-- A Waylaid Crate's Use line lists the bundles that fill it, one per line ("- 6 Bolt of Woolen
-- Cloth"), in the Use line's own text or in lines of their own after it.

local USE = _G.ITEM_SPELL_TRIGGER_ONUSE or "Use:" -- Blizzard's "Use:", in the player's language

-- Each line of a text, for gmatch on the text with "\n" added. The crate's text breaks lines
-- with "\r\n", and a "\r" left on a line we draw shows as an empty line after it.
internal.LINES = "(.-)\r?\n"

local LINES = internal.LINES

---A tooltip line's text without color codes, or nil when it can't be read.
---@param line table
---@return string|nil
function internal.PlainText(line)
    local text = line.leftText
    if type(text) == "string" and ns.IsReadable(text) then
        return ns.Text.Plain(text)
    end
end

---A bundle in the list ("- 6 Bolt of Woolen Cloth"): its count and item name, or nil.
---@param part string
---@return number|nil count
---@return string|nil name
function internal.BundleOf(part)
    local count, name = part:match("^%s*%-%s*(%d+)%s+(.-)%s*$")
    if count and name ~= "" then
        return tonumber(count), name
    end
end

---Whether any of the text's lines is a bundle.
---@param text string
---@return boolean
function internal.HasBundle(text)
    for part in (text .. "\n"):gmatch(LINES) do
        if internal.BundleOf(part) then
            return true
        end
    end
    return false
end

---Whether `lineData` is the Use line or one of the bundle lines right after it.
---@param data table tooltip data
---@param lineData table one of its lines
---@return boolean
function internal.InList(data, lineData)
    local found, chain = false, false
    for _, line in ipairs(data.lines or {}) do
        local text = internal.PlainText(line) or ""
        if not found and text:find(USE, 1, true) == 1 then
            found, chain = true, true
        elseif found then
            chain = chain and internal.HasBundle(text)
        end
        if line == lineData then
            return found and chain
        end
    end
    return false
end

---The bundles an item's tooltip lists after its Use line: { { count, name } }, empty for an item
---that isn't a crate.
---@param data table tooltip data, as C_TooltipInfo gives it
---@return table
function internal.Bundles(data)
    local bundles, found = {}, false
    for _, line in ipairs(data.lines or {}) do
        local text = internal.PlainText(line) or ""
        if not found then
            found = text:find(USE, 1, true) == 1
        elseif not internal.HasBundle(text) then
            break
        end
        if found then
            for part in (text .. "\n"):gmatch(LINES) do
                local count, name = internal.BundleOf(part)
                if count then
                    bundles[#bundles + 1] = { count, name }
                end
            end
        end
    end
    return bundles
end

local crates = {} -- item link (or itemID) -> true once its tooltip listed bundles
local byData = setmetatable({}, { __mode = "k" }) -- tooltip data -> whether it lists bundles

---Whether the item in this tooltip data is a crate, looked at once per tooltip: line callbacks
---ask before every line of every item tooltip. Only "yes" is remembered for the item. A crate
---the game hasn't loaded yet (one never owned, in the auction house) is drawn first without its
---Use text, so "no" holds only for that tooltip's data, and the redraw once it loads looks again.
---@param data table tooltip data
---@return boolean
function internal.IsCrate(data)
    local key = ns.IsText(data.hyperlink, true) and data.hyperlink or ns.ItemTooltip.ItemID(data)
    if key and crates[key] then
        return true
    end
    local known = byData[data]
    if known == nil then
        known = #internal.Bundles(data) > 0
        byData[data] = known
        if known and key then
            crates[key] = true
        end
    end
    return known
end
