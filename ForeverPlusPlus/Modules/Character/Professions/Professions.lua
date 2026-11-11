-- Professions: what Forever++ adds to the professions window, in one module with a part for each,
-- in its own file: Recipe Colors (the recipe list colored by the chance of a skill-up), Skill-Ups
-- Left (how long each recipe keeps giving skill-ups), and Crafting Costs (what a recipe costs and
-- makes, from auction and merchant prices). Each part has its own checkbox heading its section in
-- Settings, works without the others, and shares only `module.internal` with them.
local _, ns = ...

local type, ipairs = type, ipairs
local C_TradeSkillUI = C_TradeSkillUI

local L = ns.L

local module = ns.NewModule("Professions", L.PROFESSIONS_DESC, {
    enabled = true,
})
module.title = L.PROFESSIONS_TITLE
module.category = "character"
module.added = "1.5.0"

-- Up to 1.4.0, Recipe Colors was a module of its own and Crafting Costs (with the merchant prices
-- it learns) was an option of Item Tooltips' Auction Prices. Each now is a part here, on or off as
-- the player saw it: Crafting Costs showed nothing while Item Tooltips or its Auction Prices was
-- off, so it starts off then; and Skill-Ups Left, new in 1.5.0 and Recipe Colors' until then,
-- follows Recipe Colors. The module is on while any part is. Every profile is moved alike (1.4.0
-- had only Default; profiles came in 1.5.0 too, so others are already in the new layout and only
-- the leftovers are cleared).
ns.Migrate(7, function(db)
    for _, root in ipairs(ns.Store.Roots(db)) do
        local settings = type(root.settings) == "table" and root.settings
        local colors = settings and type(settings.RecipeColors) == "table" and settings.RecipeColors
        local tooltips = settings and type(settings.ItemTooltips) == "table" and settings.ItemTooltips
        if colors or (tooltips and (tooltips.crafting ~= nil or tooltips.enabled == false
            or tooltips.auction == false)) then
            local new = type(settings.Professions) == "table" and settings.Professions or {}
            settings.Professions = new
            if colors then
                ns.MoveSettings(colors, new, { recipeColors = "enabled", "highlight", "gray" })
                if colors.enabled == false then
                    new.skillUps = false
                end
            end
            if tooltips then
                local shown = tooltips.enabled ~= false and tooltips.auction ~= false
                if not shown then
                    new.crafting = false
                elseif tooltips.crafting ~= nil then
                    new.crafting = tooltips.crafting
                end
            end
            local any = false
            for _, key in ipairs({ "recipeColors", "skillUps", "crafting" }) do
                any = any or new[key] ~= false
            end
            if not any then
                new.enabled = false
            end
        end
        if settings then
            settings.RecipeColors = nil
            if tooltips then
                tooltips.crafting, tooltips.craftingRows = nil, nil
            end
        end
        -- The Minimap Button's quick toggles kept by module name, in each profile.
        local data = type(root.data) == "table" and root.data
        local minimap = data and type(data.MinimapButton) == "table" and data.MinimapButton
        local picks = minimap and type(minimap.quickToggles) == "table" and minimap.quickToggles
        if picks then
            if picks.RecipeColors ~= nil and picks.Professions == nil then
                picks.Professions = picks.RecipeColors
            end
            picks.RecipeColors = nil
        end
    end
    -- What merchants charge, learned for the account (Default's data holds account data).
    local data = type(db.data) == "table" and db.data
    local tooltips = data and type(data.ItemTooltips) == "table" and data.ItemTooltips
    if tooltips and type(tooltips.vendor) == "table" then
        local new = type(data.Professions) == "table" and data.Professions or {}
        data.Professions = new
        if type(new.vendor) ~= "table" then
            new.vendor = tooltips.vendor
        end
        tooltips.vendor = nil
    end
    -- The version Recipe Colors was last seen in, for its NEW marks.
    local seen = type(db.seenModules) == "table" and db.seenModules
    if seen and seen.RecipeColors ~= nil then
        if seen.Professions == nil then
            seen.Professions = seen.RecipeColors
        end
        seen.RecipeColors = nil
    end
end)

local internal = {}
module.internal = internal

-- Guild, NPC, and runeforging lists have no skill-ups, so neither colors nor counts. Probe: each
-- call is Mainline's.
function internal.ListHasSkillUps()
    local T = C_TradeSkillUI
    if not T then
        return false
    end
    if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then
        return false
    end
    if T.IsNPCCrafting and T.IsNPCCrafting() then
        return false
    end
    if T.IsRuneforging and T.IsRuneforging() then
        return false
    end
    return true
end

-- Crafting Costs prices what it can from auction prices, which only Item Tooltips' Auction Prices
-- (or Auctionator through it) gives. Without them it counts merchant prices alone.
module.notice = {
    text = L.PROFESSIONS_NO_PRICES,
    description = L.PROFESSIONS_NO_PRICES_DESC,
    shown = function()
        return ns.PartOn(module, "crafting") and not ns.Prices.Available()
    end,
}
