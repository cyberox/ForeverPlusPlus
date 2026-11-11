-- The player's spellbook by spell name, with every rank of each spell they know. Forever keeps
-- Classic's ranks: each rank is its own spell ID, and its subtext ("Rank 3") is what /cast needs to
-- pick one. Nothing is cached; read again after SPELLS_CHANGED, and after SPELL_DATA_LOAD_RESULT
-- when a read came back incomplete.
local _, ns = ...

local pairs, tonumber, sort, strmatch = pairs, tonumber, table.sort, string.match
local C_Spell, C_SpellBook, Enum = C_Spell, C_SpellBook, Enum

local Spellbook = {}
ns.Spellbook = Spellbook

local readable = ns.IsReadable

---Whether this client can read the spellbook this way.
---@return boolean
function Spellbook.Available()
    return C_Spell and C_Spell.GetSpellSubtext and C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and true or false
end

---Whether the player knows a spell, as the game answers. False on a client without the spell book
---call (the plain IsSpellKnown is only a deprecated wrapper of it).
---@param spellID number
---@return boolean
function Spellbook.IsKnown(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID)
    end
    return false
end

---The spell's rank number from its subtext, or nil for a spell without ranks.
---@param spellID number
---@return number?
function Spellbook.Rank(spellID)
    local text = C_Spell.GetSpellSubtext(spellID)
    local rank = ns.IsText(text) and strmatch(text, "%d+")
    return rank and tonumber(rank)
end

-- The spell's name and subtext, or nil while the game hasn't loaded its data (it is asked for).
local function nameAndSubtext(spellID)
    local name = C_Spell.GetSpellName(spellID)
    local subtext = C_Spell.GetSpellSubtext(spellID)
    if not name or subtext == nil then
        if C_Spell.RequestLoadSpellData then
            C_Spell.RequestLoadSpellData(spellID)
        end
        return nil
    end
    return name, subtext
end

---Every spell the player knows, by name: a list of `{ id, rank, subtext }` from the lowest rank to
---the highest (rank 0 for a spell without ranks). Passive spells and the other spec's are left
---out. The second result is false while some spell data was still loading. Probe: the skill line
---fields are Mainline's; on Forever they are **Unverified** (docs/forever-api.md).
---@return table<string, table[]> ranks
---@return boolean complete
function Spellbook.Ranks()
    local ranks, complete = {}, true
    if not Spellbook.Available() then
        return ranks, false
    end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not (info.offSpecID and info.offSpecID ~= 0) then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                local id = item and readable(item.spellID) and item.spellID
                if id and not item.isPassive then
                    local name, subtext = nameAndSubtext(id)
                    if not name then
                        complete = false
                    elseif readable(name) then
                        local list = ranks[name] or {}
                        ranks[name] = list
                        list[#list + 1] = { id = id, rank = Spellbook.Rank(id) or 0,
                            subtext = ns.IsText(subtext) and subtext or "" }
                    end
                end
            end
        end
    end
    for _, list in pairs(ranks) do
        sort(list, function(a, b)
            return a.rank < b.rank
        end)
    end
    return ranks, complete
end

---The level a spell is learned at, or nil when this client doesn't say. Probe: Mainline's
---C_Spell.GetSpellLevelLearned; on Forever it is **Unverified**.
---@param spellID number
---@return number?
function Spellbook.LevelLearned(spellID)
    local get = C_Spell and C_Spell.GetSpellLevelLearned
    local level = get and get(spellID)
    return readable(level) and tonumber(level) or nil
end
