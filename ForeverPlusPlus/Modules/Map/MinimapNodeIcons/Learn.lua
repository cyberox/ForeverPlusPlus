-- Minimap Node Icons' learning: the icon of a node gathered, from Lib/Gathering.lua. The library
-- teaches Lib/Professions.lua the item a herb or vein gives, for every module; what's left here
-- is a node whose item link couldn't be read, which keeps the loot's icon, and forgetting that the
-- minimap showed a name without one.
local _, ns = ...

local Node = ns.Professions.Node

local module = ns.modules.MinimapNodeIcons
local internal = module.internal

function internal.onGather(gather)
    local name, item = gather.name, gather.items[1]
    if not (name and item) or (gather.kind ~= "herb" and gather.kind ~= "ore") then
        return
    end
    local node = Node(name)
    if not item.id and item.icon and not (node and node[3]) then
        module.db.learned[name] = item.icon
    end
    internal.seen[name] = nil
end
