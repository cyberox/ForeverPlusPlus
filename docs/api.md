# Forever++ API for addon authors

Forever++ shares what it knows with other addons through one global, `ForeverPlusPlusAPI`. The code is [`ForeverPlusPlus/API.lua`](../ForeverPlusPlus/API.lua).

```lua
local FPP = ForeverPlusPlusAPI and ForeverPlusPlusAPI.v1
if FPP then
    local copper, seenAt = FPP.GetAuctionPrice(itemLink)
end
```

Add `## OptionalDeps: ForeverPlusPlus` to your TOC so Forever++ loads first. Then `ForeverPlusPlusAPI` is there when your files run. Saved data (players seen, which modules are on) loads at `PLAYER_LOGIN`, so read it after `IsReady()` returns true or after the `READY` callback.

## Promises

- **`v1` never breaks.** Functions and return values may be added to it, but nothing is renamed or removed and no meaning changes. A breaking change would ship as `v2`, next to `v1`.
- **Read only.** You get copies and plain values, never Forever++'s own tables. Changing one has no effect. Assigning into `ForeverPlusPlusAPI` or `v1` raises an error.
- **Calls can't break your addon.** An error inside Forever++ goes to the error handler (BugSack shows it) and the call returns `nil`. Bad input, like a table where an item belongs, also returns `nil`.
- **`nil` means unknown.** Much of this data comes from modules the player can turn off, or from what Forever++ has seen in play. Always handle `nil`.

Wherever a function takes `item`, it accepts an item ID (`4305`), an item link, an `"item:4305"` string, or an item name. A name is found in the client's item cache first, then among the items with an auction price.

Colors come back as `r, g, b` (0 to 1) plus a hex string `"ffrrggbb"`, the same form as a class color's `colorStr`.

## General

| Function | Returns |
| --- | --- |
| `GetVersion()` | The API version (`1`) and Forever++'s version, such as `"1.0.0"`. |
| `IsReady()` | Whether saved data has loaded (after `PLAYER_LOGIN`). |
| `IsModuleEnabled(name)` | Whether a module is on, by its internal name (`"ItemTooltips"`, `"ClassColors"`), or `nil` for a name Forever++ doesn't have. Use it to skip something Forever++ is already showing. |
| `GetModules()` | A list of `{ name, title, category, enabled }` for every module this client gets. |

## Auction prices

Prices come from Item Tooltips' Auction Prices: Forever++'s own scans of the auction house, or Auctionator's prices when the player picks Use Auctionator's Prices. While that part is off, there are no prices.

| Function | Returns |
| --- | --- |
| `HasAuctionPrices()` | Whether there are prices to give. |
| `GetAuctionPriceSource()` | `"ForeverPlusPlus"`, `"Auctionator"`, or `nil` without prices. |
| `GetAuctionPrice(item)` | The lowest buyout for one of the item in copper, and the `time()` it was seen (`nil` when unknown). `nil` when there's no price. |

## Disenchanting

These follow Classic's disenchanting rules, by quality, item level, and weapon or armor. Forever's results may differ.

| Function | Returns |
| --- | --- |
| `GetDisenchantResults(item)` | What disenchanting gives, most likely first: a list of `{ itemID, chance (0 to 1), min, max }`. `nil` when the item can't be disenchanted, or the client hasn't loaded it yet (ask again after `GET_ITEM_INFO_RECEIVED`). |
| `GetDisenchantValue(item)` | The average value in copper at the auction prices, and how many results had no price (the total leaves those out). `nil` without prices or results. |

## Players seen

Forever++ saves the class, level, race, and guild of the other players it sees, for the whole account: your group, your guild roster, friends, `/who` results, units you target or mouse over, nameplates, and chat. It learns while a module that uses this data is on (Chat Levels, Class Colors' Offline Friends, Whisper Window). What's already saved can be read either way. Players not seen for 60 days are dropped.

| Function | Returns |
| --- | --- |
| `GetPlayerInfo(name, guid)` | `{ class, className, level, race, guild, lastSeen }`. `class` is the token (`"MAGE"`), `className` and `race` are localized, and `lastSeen` is a `time()`. Any field can be `nil`. Returns `nil` for someone never seen. `name` may include a surname (`"Bob-Surname"`). `guid` is optional and tells apart players with the same name on different realms. |
| `GetPlayerClassColor(name, guid)` | Their class color, from the class last seen. |

Levels are the last ones seen, so they can be behind. Check `lastSeen`.

## Colors

| Function | Returns |
| --- | --- |
| `GetClassColor(classToken)` | A class's color (`"MAGE"`). |
| `GetLevelColor(low, high)` | A level or level range against the player's level, colored like a quest: red or orange above you, yellow while you're in it, green or gray once you've outleveled it. Leave out `high` for a single level. |

## Dungeons and raids

| Function | Returns |
| --- | --- |
| `GetInstances()` | Every dungeon and raid, lowest level first: a list of `{ key, instanceID, name, englishName, minLevel, maxLevel, isRaid }`. `name` is in the player's language. The levels follow the dungeon finder once it has listed them, and Forever's own dungeons are included. |
| `GetInstanceInfo(instance)` | One of them, by instance ID or by name (in the player's language or English), or `nil`. |

## Gathering

| Function | Returns |
| --- | --- |
| `GetGatheringNode(name)` | A herb or vein by the name the world shows: `{ skillLine (182 Herbalism, 186 Mining), skill, itemID }`. A field is `nil` until it's known. |
| `GetItemGatheringSkill(item)` | The skill line and skill of the lowest herb or vein that gives an item. |
| `GetSkinningSkill(level)` | The Skinning skill needed for a creature of that level. |

## Callbacks

```lua
FPP.RegisterCallback("PRICES_UPDATED", function(event)
    -- redraw your prices
end, myAddon)
FPP.UnregisterCallback("PRICES_UPDATED", myAddon)
```

`RegisterCallback(event, fn, owner)` calls `fn(event, ...)` each time the event happens. Each owner holds one function per event. Pass your addon's table as `owner`, or leave it out and the function is its own owner. An error in your callback goes to the error handler and doesn't stop the other callbacks. An unknown event name is reported the same way.

| Event | When |
| --- | --- |
| `READY` | Saved data has loaded. Fires once, after `PLAYER_LOGIN`. |
| `PRICES_UPDATED` | Auction prices changed: new prices were seen while browsing or scanning, they were reset, or their source changed (Auction Prices turned on or off, or the switch to or from Auctionator). Fires at most once a second. |
