-- Class Colors: players' health bars and names in their class color on the player, target, focus,
-- party, and target-of-target frames, and NPCs' health bars by reaction: red when hostile, yellow
-- when neutral, gray when tapped by someone else. Friendly NPCs, and units whose class or
-- reaction can't be read, keep Blizzard's green. Idea from MiniClassColors; none of its code.
-- With Friends and Who List on, online friends' names in the friends list and names in the who
-- list are in their class color too (the guild roster already does this itself). With Offline
-- Friends on, offline friends' names are in the class Forever++ last saw them as (ns.Players).
--
-- Blizzard's health bars are a green texture with lockColor set, so Blizzard never colors them
-- except party frames, which desaturate the bar for a disconnected member. The bar is
-- desaturated and tinted to show a class color. Every call Blizzard makes to a bar's color or
-- desaturation is remembered and then painted over again, so turning a part off puts back
-- exactly what Blizzard last set.
local _, ns = ...

local _G, setmetatable = _G, setmetatable
local pairs, format, wipe = pairs, string.format, wipe
local C_FriendList, GetPlayerInfoByGUID = C_FriendList, GetPlayerInfoByGUID
local UnitIsPlayer, UnitIsConnected, UnitReaction = UnitIsPlayer, UnitIsConnected, UnitReaction
local UnitIsTapDenied, UnitPlayerControlled, CreateColor = UnitIsTapDenied, UnitPlayerControlled, CreateColor

local L = ns.L
local readable = ns.IsReadable
local classColor = ns.Colors.Class
local classColorOf = ns.Colors.ClassToken

local module = ns.NewModule("ClassColors", L.CLASSCOLORS_DESC, {
    enabled = true,
    healthBars = true,
    npcBars = true,
    nameColor = "default",
    nameBackgrounds = true,
    socialNames = true,
    offlineFriends = true,
    player = true,
    target = true,
    focus = true,
    party = true,
    targetOfTarget = true,
})
module.title = L.CLASSCOLORS_TITLE
module.category = "units"

local PARTS = L.CLASSCOLORS_SECTION_PARTS
local FRAMES = L.CLASSCOLORS_SECTION_FRAMES
module.options = {
    { key = "healthBars", name = L.CLASSCOLORS_BARS, description = L.CLASSCOLORS_BARS_DESC, section = PARTS },
    { key = "npcBars", name = L.CLASSCOLORS_NPC_BARS, description = L.CLASSCOLORS_NPC_BARS_DESC, section = PARTS },
    {
        key = "nameColor", name = L.CLASSCOLORS_NAMES, description = L.CLASSCOLORS_NAMES_DESC, section = PARTS,
        choices = {
            { "default", L.CLASSCOLORS_NAMES_DEFAULT },
            { "white", L.CLASSCOLORS_NAMES_WHITE },
            { "class", L.CLASSCOLORS_NAMES_CLASS },
        },
    },
    { key = "nameBackgrounds", name = L.CLASSCOLORS_NAME_BG, description = L.CLASSCOLORS_NAME_BG_DESC, section = PARTS },
    { key = "socialNames", name = L.CLASSCOLORS_SOCIAL, description = L.CLASSCOLORS_SOCIAL_DESC, section = PARTS,
        added = "0.8.0" },
    { key = "offlineFriends", name = L.CLASSCOLORS_OFFLINE, description = L.CLASSCOLORS_OFFLINE_DESC,
        section = PARTS, requires = "socialNames", added = "1.0.0-beta.1" },
    { key = "player", name = L.CLASSCOLORS_PLAYER, description = L.CLASSCOLORS_PLAYER_DESC, section = FRAMES },
    { key = "target", name = L.CLASSCOLORS_TARGET, description = L.CLASSCOLORS_TARGET_DESC, section = FRAMES },
    { key = "focus", name = L.CLASSCOLORS_FOCUS, description = L.CLASSCOLORS_FOCUS_DESC, section = FRAMES },
    { key = "party", name = L.CLASSCOLORS_PARTY, description = L.CLASSCOLORS_PARTY_DESC, section = FRAMES },
    { key = "targetOfTarget", name = L.CLASSCOLORS_TOT, description = L.CLASSCOLORS_TOT_DESC, section = FRAMES },
}

-- Nameplates are Blizzard's to color, so this module leaves them alone, but players' health bars
-- on them are a flat blue or red unless these CVars are on (NamePlateDriverMixin's
-- UpdateNamePlateOptions reads them into useClassColors, Gethe `forever` branch, checked
-- 2026-11-04), so a player who wants class colors everywhere gets a button for each.
local friendlyBars = ns.CVars.OffNotice(module, "nameplateShowFriendlyClassColor",
    L.CLASSCOLORS_FRIENDLY_BARS_OFF, L.CLASSCOLORS_FRIENDLY_BARS_OFF_DESC)
local enemyBars = ns.CVars.OffNotice(module, "nameplateShowClassColor",
    L.CLASSCOLORS_ENEMY_BARS_OFF, L.CLASSCOLORS_ENEMY_BARS_OFF_DESC)

-- Friendly players' names on Blizzard's nameplates are white unless this CVar is on, so a player
-- who wants class colors everywhere gets a button for it. Not while Player Nameplates is on: it
-- draws its own names in their class color and keeps this off, so Blizzard's hidden ones stay white.
local FRIENDLY_PLATE_NAMES = "nameplateUseClassColorForFriendlyPlayerUnitNames"
local plateNames = ns.CVars.OffNotice(module, FRIENDLY_PLATE_NAMES, L.CLASSCOLORS_PLATE_NAMES_OFF,
    L.CLASSCOLORS_PLATE_NAMES_OFF_DESC)
local plateNamesOff = plateNames.shown
plateNames.shown = function()
    return plateNamesOff() and not ns.FriendlyPlates.DrawsPlayers()
end
module.notice = { friendlyBars, enemyBars, plateNames }

local MAX_PARTY = 4
-- Blizzard's own hostile, neutral, and tapped colors (UnitSelectionColor, Classic's tapped bar).
local HOSTILE, NEUTRAL, TAPPED = CreateColor(1, 0, 0), CreateColor(1, 1, 0), CreateColor(0.5, 0.5, 0.5)
local WHITE = CreateColor(1, 1, 1)
local NEUTRAL_REACTION = 4 -- UnitReaction: 1-3 hostile, 4 neutral, 5-8 friendly
local weak = { __mode = "k" }
local applying = setmetatable({}, weak) -- StatusBar -> true while we set its color ourselves
local painted = setmetatable({}, weak) -- StatusBar or FontString -> true while in our color
local blizzardColor = setmetatable({}, weak) -- StatusBar -> { r, g, b, a } Blizzard last set
local blizzardDesaturated = setmetatable({}, weak) -- StatusBar -> what Blizzard last set
local nameColor = setmetatable({}, weak) -- FontString -> { r, g, b, a } before we colored it
local backgroundFrame = setmetatable({}, weak) -- Texture -> the unit frame it's the background of
local blizzardBackground = setmetatable({}, weak) -- Texture -> { r, g, b, a } Blizzard last set

-- Which of the module's frame settings a Blizzard unit frame falls under, or nil.
local function partOf(frame)
    if not frame then
        return nil
    end
    local target, focus = _G.TargetFrame, _G.FocusFrame
    if frame == _G.PlayerFrame then
        return "player"
    elseif frame == target then
        return "target"
    elseif frame == focus then
        return "focus"
    elseif (target and frame == target.totFrame) or (focus and frame == focus.totFrame) then
        return "targetOfTarget"
    elseif _G.PartyFrame and frame:GetParent() == _G.PartyFrame then
        return "party"
    end
end

-- Whether the module colors this frame at all.
local function frameOn(frame, unit)
    local part = partOf(frame)
    return module.enabled and part and module.db[part] and unit and true or false
end

-- The NPC's reaction color, or nil for friendly NPCs and ones we can't read.
local function reactionColor(unit)
    local controlled = UnitPlayerControlled(unit)
    local tapped = UnitIsTapDenied(unit)
    if readable(controlled) and not controlled and readable(tapped) and tapped then
        return TAPPED
    end
    -- The unit's reaction to the player, as Blizzard's tooltip reads it. The player's reaction to
    -- the unit can differ: a hostile mob of a faction the player is neutral with reads neutral.
    local reaction = UnitReaction(unit, "player")
    if not (readable(reaction) and reaction) then
        return nil
    elseif reaction < NEUTRAL_REACTION then
        return HOSTILE
    elseif reaction == NEUTRAL_REACTION then
        return NEUTRAL
    end
end

-- The color for `unit`'s health bar or name (`setting` healthBars or names) on `frame`, else
-- nil for Blizzard's. Players get their class color; NPCs' bars get their reaction color with
-- npcBars on. Disconnected players keep Blizzard's gray.
local function wanted(frame, unit, setting)
    if not frameOn(frame, unit) then
        return nil
    end
    local player = UnitIsPlayer(unit)
    if not readable(player) then
        return nil
    elseif not player then
        return setting == "healthBars" and module.db.npcBars and reactionColor(unit) or nil
    elseif setting ~= "names" and not module.db[setting] then
        return nil
    end
    local connected = UnitIsConnected(unit)
    if readable(connected) and not connected then
        return nil
    end
    return classColor(unit)
end

local function restoreBar(bar)
    local color = blizzardColor[bar]
    local desaturated = blizzardDesaturated[bar]
    applying[bar] = true
    bar:SetStatusBarDesaturated(desaturated or false)
    if color then
        bar:SetStatusBarColor(color[1], color[2], color[3], color[4])
    else
        bar:SetStatusBarColor(1, 1, 1) -- lockColor bars: Blizzard never tints them
    end
    applying[bar] = nil
    painted[bar] = nil
end

-- Not painted, so what the bar shows is Blizzard's. Kept now because the hooks that remember it
-- don't run while the module is off, so what they last saw may be out of date.
local function keepBlizzardBar(bar)
    local r, g, b, a = bar:GetStatusBarColor()
    if readable(r) then
        blizzardColor[bar] = { r, g, b, a }
    end
    if bar.IsStatusBarDesaturated then
        local desaturated = bar:IsStatusBarDesaturated()
        if readable(desaturated) then
            blizzardDesaturated[bar] = desaturated
        end
    end
end

local function paintBar(bar)
    local color = wanted(bar.unitFrame, bar.unit, "healthBars")
    if not color then
        if painted[bar] then
            restoreBar(bar)
        end
        return
    end
    if not painted[bar] then
        keepBlizzardBar(bar)
    end
    applying[bar] = true
    bar:SetStatusBarDesaturated(true)
    bar:SetStatusBarColor(color:GetRGB())
    applying[bar] = nil
    painted[bar] = true
end

-- Remember what Blizzard sets, then paint over it again.
local function onBarColor(bar, r, g, b, a)
    if applying[bar] then
        return
    end
    blizzardColor[bar] = { r, g, b, a }
    paintBar(bar)
end

local function onBarDesaturated(bar, desaturated)
    if applying[bar] then
        return
    end
    blizzardDesaturated[bar] = desaturated
    paintBar(bar)
end

local function hookBar(bar)
    module:Hook(bar, "SetStatusBarColor", onBarColor)
    module:Hook(bar, "SetStatusBarDesaturated", onBarDesaturated)
end

-- Puts a font string in `color`, or back in the color it had before we first colored it.
local function colorText(text, color)
    if color then
        if not nameColor[text] then
            nameColor[text] = { text:GetTextColor() }
        end
        text:SetTextColor(color:GetRGB())
        painted[text] = true
    elseif painted[text] then
        local old = nameColor[text]
        text:SetTextColor(old[1], old[2], old[3], old[4])
        painted[text] = nil
    end
end

local function paintName(frame)
    local text = frame.name
    if not text then
        return
    end
    local color
    local choice = module.db.nameColor
    if choice == "white" then
        color = frameOn(frame, frame.unit) and WHITE or nil
    elseif choice == "class" then
        color = wanted(frame, frame.unit, "names")
    end
    colorText(text, color)
end

-- The bar behind a target or focus name that Blizzard tints by faction. The field name differs
-- between builds, so probe both; frames without one (player, party) return nil.
local function backgroundOf(frame)
    if frame.nameBackground then
        return frame.nameBackground
    end
    local content = frame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    return main and main.ReputationColor
end

local function restoreBackground(texture)
    local color = blizzardBackground[texture]
    applying[texture] = true
    if color then
        texture:SetVertexColor(color[1], color[2], color[3], color[4])
    end
    applying[texture] = nil
    painted[texture] = nil
end

local function paintBackground(texture, frame)
    local color = wanted(frame, frame.unit, "nameBackgrounds")
    if not color then
        if painted[texture] then
            restoreBackground(texture)
        end
        return
    end
    -- Blizzard may have colored it before our hook, or while the module was off and the hook did
    -- nothing, so keep what it shows now to put back.
    if not painted[texture] then
        local r, g, b, a = texture:GetVertexColor()
        if ns.IsReadable(r) then
            blizzardBackground[texture] = { r, g, b, a }
        end
    end
    applying[texture] = true
    texture:SetVertexColor(color:GetRGB())
    applying[texture] = nil
    painted[texture] = true
end

local function onBackgroundColor(texture, r, g, b, a)
    if applying[texture] then
        return
    end
    blizzardBackground[texture] = { r, g, b, a }
    paintBackground(texture, backgroundFrame[texture])
end

local function hookBackground(texture, frame)
    backgroundFrame[texture] = frame
    module:Hook(texture, "SetVertexColor", onBackgroundColor)
end

local function update(frame)
    if not partOf(frame) then
        return
    end
    local bar = frame.healthbar
    if bar then
        hookBar(bar)
        paintBar(bar)
    end
    paintName(frame)
    local texture = backgroundOf(frame)
    if texture then
        hookBackground(texture, frame)
        paintBackground(texture, frame)
    end
end

-- Blizzard calls UnitFrame_Update whenever a frame's unit changes (a new target, the party
-- roster, the target's target), so the colors follow it.
local function updateAll()
    local target, focus, party = _G.TargetFrame, _G.FocusFrame, _G.PartyFrame
    update(_G.PlayerFrame)
    update(target)
    update(focus)
    update(target and target.totFrame)
    update(focus and focus.totFrame)
    for i = 1, MAX_PARTY do
        update(party and party["MemberFrame" .. i])
    end
end
-- UNIT_FACTION comes for every unit the client tracks, nameplates too, often several at once; one
-- pass a frame later covers a burst. (No unit filter: the target's target gets no event of its own.)
local updateSoon, cancelUpdate = ns.Frames.Coalesce(updateAll, nil, module)

-- The friends list and the who list. Their rows are scroll box buttons, so we listen for the
-- scroll box's OnInitializedFrame, which it sends for addons after Blizzard's own initializer has
-- filled a row, and recolor the row then.

local FRIENDS_ADDON, WHO_ADDON = "Blizzard_FriendsFrame", "Blizzard_GroupFinder_VanillaStyle"
local lists = {} -- scroll box -> its paint function, while the module is on
local friendPainted = setmetatable({}, weak) -- friend button -> true while its name is colored

local function socialOn()
    return module.enabled and module.db.socialNames
end

local function offlineOn()
    return socialOn() and module.db.offlineFriends
end

-- The player cache learns only while some module uses it, so it's ours only while offline
-- friends are colored.
local function syncPlayers()
    if offlineOn() then
        ns.Players.Use(module)
    else
        ns.Players.Release(module)
    end
end

-- A friend's class token: from their GUID when the client knows it, else from the localized
-- class name the friend info carries.
local function friendClass(info)
    if info.guid and GetPlayerInfoByGUID then
        local _, class = GetPlayerInfoByGUID(info.guid)
        if readable(class) and class then
            return class
        end
    end
    return ns.Players.ClassToken(info.className)
end

-- Blizzard draws an online WoW friend as "Name, Level 60 Warrior" in one flat color, and an
-- offline one as just the name in gray, so we write the same line with only the name in its class
-- color. Without `color` it's Blizzard's line.
local function friendText(info, color)
    local name = color and ns.Colors.Text(color, info.name) or info.name
    if not info.connected then
        return name
    end
    return name .. ", " .. format(_G.FRIENDS_LEVEL_TEMPLATE, info.level, info.className)
end

-- An offline friend's class isn't sent, so it's the one they had when last seen.
local function offlineClass(info)
    local seen = ns.Players.Get(info.guid, info.name)
    return seen and seen.class
end

local function paintFriend(_, button, elementData)
    local info
    if elementData and elementData.buttonType == _G.FRIENDS_BUTTON_TYPE_WOW and button.name then
        info = C_FriendList.GetFriendInfoByIndex(elementData.id)
    end
    if not (info and info.name) then
        friendPainted[button] = nil -- a different kind of row now, which Blizzard has redrawn
        return
    end
    local color
    if info.connected then
        color = socialOn() and classColorOf(friendClass(info))
    else
        color = offlineOn() and classColorOf(offlineClass(info))
    end
    if color then
        button.name:SetText(friendText(info, color))
        friendPainted[button] = true
    elseif friendPainted[button] then
        button.name:SetText(friendText(info))
        friendPainted[button] = nil
    end
end

-- The who list colors only the Class column; this colors the name too.
local function paintWho(_, button, elementData)
    local info = elementData and elementData.info
    if button.Name then
        colorText(button.Name, socialOn() and info and classColorOf(info.filename) or nil)
    end
end

local function repaint(scrollBox, paint)
    scrollBox:ForEachFrame(function(frame, elementData)
        paint(module, frame, elementData)
    end)
end

local function watchList(scrollBox, paint)
    if not scrollBox or lists[scrollBox] then
        return
    end
    lists[scrollBox] = paint
    scrollBox:RegisterCallback(_G.ScrollBoxListMixin.Event.OnInitializedFrame, paint, module)
    repaint(scrollBox, paint)
end

local function watchFriends()
    local frame = _G.FriendsListFrame
    watchList(frame and frame.ScrollBox, paintFriend)
end

local function watchWho()
    local frame = _G.LFGWhoListFrame
    watchList(frame and frame.ScrollBox, paintWho)
end

local function repaintLists()
    for scrollBox, paint in pairs(lists) do
        repaint(scrollBox, paint)
    end
end

function module:OnEnable()
    self:Hook("UnitFrame_Update", update)
    -- A reaction or tap can change without a new unit (a mob turns hostile, someone tags it).
    self:On("UNIT_FACTION", updateSoon)
    updateAll()
    if _G.ScrollBoxListMixin then
        ns.AddOns.WhenLoaded(FRIENDS_ADDON, watchFriends)
        ns.AddOns.WhenLoaded(WHO_ADDON, watchWho)
    end
    syncPlayers()
end

-- module.enabled is already false here, so every painted bar and name goes back to Blizzard's.
function module:OnDisable()
    cancelUpdate()
    updateAll()
    ns.AddOns.Cancel(FRIENDS_ADDON, watchFriends)
    ns.AddOns.Cancel(WHO_ADDON, watchWho)
    repaintLists()
    for scrollBox in pairs(lists) do
        scrollBox:UnregisterCallback(_G.ScrollBoxListMixin.Event.OnInitializedFrame, module)
    end
    wipe(lists)
    ns.Players.Release(module)
end

function module:OnOptionChanged()
    syncPlayers()
    updateAll()
    repaintLists()
end
