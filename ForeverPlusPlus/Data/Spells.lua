-- Hand-kept spell IDs more than one file depends on, each written once: `ns.Data.Spell("FISHING")`
-- gives the ID and has Self Test check the client still has it. Each is Classic's first rank
-- unless said; a spell's other ranks share its name, so code that needs them matches by name.
-- A spell only one file uses stays in that file, through ns.GameData.Spell.
local _, ns = ...

ns.Data = ns.Data or {}

ns.Data.spells = {
    -- Gathering. Forever's Mining arrives as 2576 (Journeyman), which shares the name.
    MINING = { 2575, "Mining" },
    HERB_GATHERING = { 2366, "Herb Gathering" },
    OPENING = { 3365, "Opening" },
    PICK_LOCK = { 1804, "Pick Lock" },
    FISHING = { 7620, "Fishing" },
    -- Minimap tracking.
    FIND_HERBS = { 2383, "Find Herbs" },
    FIND_MINERALS = { 2580, "Find Minerals" },
    -- The Dwarf racial. Classic's ID, unverified on Forever.
    FIND_TREASURE = { 2481, "Find Treasure" },
}

---A shared spell's ID, registered for Self Test. Call it as a file loads, after Lib/GameData.lua.
---@param key string a key of `ns.Data.spells`
---@return number
function ns.Data.Spell(key)
    local spell = ns.Data.spells[key]
    return ns.GameData.Spell(spell[1], spell[2])
end
