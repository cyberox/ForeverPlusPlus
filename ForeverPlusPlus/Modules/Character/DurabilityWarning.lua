-- Durability Warning: says once when the most worn equipped item drops below the durability the
-- player picks, and once more when an item breaks, so they repair before it does. Each way of
-- saying it is its own option: a chat line naming the item, red text in the middle of the screen
-- where the game says "Inventory is full" (the game's own place for a short warning, so it needs
-- no frame of ours to place in Edit Mode), and a sound from ns.Sounds.
--
-- It warns only when the level gets worse (ns.Durability.ShouldWarn): low, then broken. Repairing,
-- or taking the item off, brings the level back down, and the next drop warns again. Durability
-- events come in bursts (every hit in a fight), so a look waits for them to settle. After logging
-- in, gear that's already low gets one quiet warning (chat only) once the world has loaded; a
-- reload or a loading screen says nothing new.
local _, ns = ...

local format, floor = string.format, math.floor
local GetInventoryItemLink = GetInventoryItemLink

local L = ns.L
local Durability = ns.Durability

local module = ns.NewModule("DurabilityWarning", L.DURABILITYWARNING_DESC, {
    enabled = false,
    threshold = 25, -- percent
    broken = true,
    alert = true,
    sound = "raidwarning", -- a key of ns.Sounds.CHOICES
    chat = true,
})
module.title = L.DURABILITYWARNING_TITLE
module.category = "character"
module.added = "1.5.0"
module.developer = { enabled = true }

module.options = {
    {
        key = "threshold", name = L.DURABILITYWARNING_THRESHOLD,
        description = L.DURABILITYWARNING_THRESHOLD_DESC,
        min = 5, max = 50, step = 5, format = "%d%%",
    },
    { key = "broken", name = L.DURABILITYWARNING_BROKEN, description = L.DURABILITYWARNING_BROKEN_DESC },
    { key = "alert", name = L.DURABILITYWARNING_ALERT, description = L.DURABILITYWARNING_ALERT_DESC },
    {
        key = "sound", name = L.DURABILITYWARNING_SOUND, description = L.DURABILITYWARNING_SOUND_DESC,
        choices = ns.Sounds.CHOICES,
    },
    ns.ChatOption(L.DURABILITYWARNING_CHAT_DESC),
}

local SETTLE = 1 -- seconds of quiet after a durability event before looking
local FIRST_LOOK = 5 -- seconds after loading in (or turning on) before the first look

local last -- the level last seen; nil until the first look after turning on
local reloading -- this login is a /reload, so the first look only notes the level

---The warning level now, with the most worn item's fraction and slot.
local function current()
    local lowest, slot = Durability.Lowest()
    local level = Durability.Level(lowest, module.db.threshold / 100, module.db.broken)
    return level, lowest, slot
end

-- The worn item's link, or nil when it can't be read.
local function itemLink(slot)
    local link = slot and GetInventoryItemLink("player", slot)
    return ns.IsText(link, true) and link or nil
end

---Says the warning for `level` in every way the player turned on; `quiet` (the first look after
---logging in) only in chat, or on screen when chat is off, and without the sound.
local function warn(level, lowest, slot, quiet)
    local db = module.db
    local percent = floor((lowest or 0) * 100)
    local link = itemLink(slot)
    local chat, alert
    if level == "broken" then
        chat = link and format(L.DURABILITYWARNING_BROKEN_ITEM, link) or L.DURABILITYWARNING_BROKEN_GEAR
        alert = L.DURABILITYWARNING_ALERT_BROKEN
    else
        chat = link and format(L.DURABILITYWARNING_LOW_ITEM, link, percent)
            or format(L.DURABILITYWARNING_LOW_GEAR, percent)
        alert = format(L.DURABILITYWARNING_ALERT_LOW, percent)
    end
    module:Print(chat) -- nothing while Chat Messages is off
    if db.alert and not (quiet and db.chat) then
        ns.Frames.ErrorMessage(alert)
    end
    if not quiet then
        ns.Sounds.Play(db.sound)
    end
end

local function look()
    if last == nil then
        return -- the first look hasn't happened yet; it will see this too
    end
    local level, lowest, slot = current()
    if Durability.ShouldWarn(last, level) then
        warn(level, lowest, slot)
    end
    last = level
end

local queueLook = ns.Frames.Coalesce(look, SETTLE, module)
local firstTimer = ns.Frames.Timer(module)

local function firstLook()
    local level, lowest, slot = current()
    if not reloading and Durability.ShouldWarn(nil, level) then
        warn(level, lowest, slot, true)
    end
    last = level
end

-- At login and /reload the world loads after OnEnable: wait for it, so the item links and
-- durability are there and the chat line isn't lost behind the loading screen. Later loading
-- screens change nothing.
local function onEnteringWorld(_, isInitialLogin, isReloadingUi)
    if last == nil then
        reloading = isReloadingUi and not isInitialLogin
        firstTimer:Start(FIRST_LOOK, firstLook)
    end
end

function module:OnEnable()
    last, reloading = nil, false
    self:On("PLAYER_ENTERING_WORLD", onEnteringWorld)
    self:On("UPDATE_INVENTORY_DURABILITY", queueLook)
    self:On("PLAYER_EQUIPMENT_CHANGED", queueLook)
    -- Turned on live, no PLAYER_ENTERING_WORLD follows; at login this run is replaced by its own.
    firstTimer:Start(FIRST_LOOK, firstLook)
end

function module:OnDisable()
    last = nil
end

-- Picking a sound plays it. A new threshold, or Warn When Broken, takes the level as it is now
-- without warning, so changing them doesn't set one off; the next drop past it does.
function module:OnOptionChanged(key)
    if key == "sound" then
        ns.Sounds.Play(self.db.sound)
    elseif (key == "threshold" or key == "broken") and last ~= nil then
        last = current()
    end
end

-- Debug's Test Warning: the low warning as it would come now, in every way turned on.
module.debugActions = {
    {
        name = L.DURABILITYWARNING_TEST, button = L.DURABILITYWARNING_TEST_BUTTON,
        description = L.DURABILITYWARNING_TEST_DESC, section = L.DEBUG_SECTION_PREVIEWS,
        fn = function()
            local _, lowest, slot = current()
            warn("low", lowest or module.db.threshold / 100, slot)
        end,
    },
}
