-- Loot Rolls: the group loot rolls (Need, Greed, Pass) where the player puts them in Edit Mode,
-- stacking up, down, left, or right with the gap they pick, and showing the seconds left to roll
-- and how many in the group picked each roll.
--
-- Blizzard stacks the roll frames (GroupLootFrame1 to 4) up from GroupLootContainer's bottom, 100
-- apart (GroupLootContainer_Update, Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua, `forever`
-- branch). Right after it does, each roll frame is anchored to our own Edit Mode frame instead.
-- The container stays where Blizzard keeps it above the action bars (a managed frame Blizzard lays
-- out itself), so none of Blizzard's layout is touched, and the roll frames aren't protected, so
-- this works in combat too. The Edit Mode preview draws example rolls of our own from the same art:
-- Blizzard's roll template drops a frame without a real roll from the container when it shows.
local _, ns = ...

local ipairs, pairs, format, floor, type, setmetatable, pcall =
    ipairs, pairs, string.format, math.floor, type, setmetatable, pcall
local CreateFrame, UIParent = CreateFrame, UIParent

local L = ns.L
local readable = ns.IsReadable
local EditMode, ItemButtons = ns.EditMode, ns.ItemButtons

local module = ns.NewModule("LootRolls", L.LOOTROLLS_DESC, {
    enabled = false,
    x = 0, -- the first roll's offset from the center of the screen (Edit Mode)
    y = -170,
    scale = 100, -- percent
    grow = "up", -- a key of STEPS: which way more rolls stack
    spacing = 4, -- pixels between rolls
    preview = 1, -- example rolls shown in Edit Mode
    timer = true,
    counts = true,
})
module.title = L.LOOTROLLS_TITLE
module.category = "interface"
module.developer = { enabled = true }
module.added = "1.4.0"

module.options = {
    {
        key = "grow", name = L.LOOTROLLS_GROW, description = L.LOOTROLLS_GROW_DESC, editMode = true,
        choices = {
            { "up", L.LOOTROLLS_GROW_UP },
            { "down", L.LOOTROLLS_GROW_DOWN },
            { "left", L.LOOTROLLS_GROW_LEFT },
            { "right", L.LOOTROLLS_GROW_RIGHT },
        },
    },
    {
        key = "spacing", name = L.LOOTROLLS_SPACING, description = L.LOOTROLLS_SPACING_DESC, editMode = true,
        min = 0, max = 30, step = 2, format = L.ICONMARK_PIXELS,
    },
    {
        key = "preview", name = L.LOOTROLLS_PREVIEW, description = L.LOOTROLLS_PREVIEW_DESC, editMode = true,
        min = 1, max = 4, step = 1, format = "%d",
    },
    { key = "timer", name = L.LOOTROLLS_TIMER, description = L.LOOTROLLS_TIMER_DESC },
    { key = "counts", name = L.LOOTROLLS_COUNTS, description = L.LOOTROLLS_COUNTS_DESC },
}

local ROLLS = _G.NUM_GROUP_LOOT_FRAMES or 4
local ROLL_WIDTH, ROLL_HEIGHT = 277, 67 -- GroupLootFrameBaseTemplate's size
-- Which way each next roll goes from the one before.
local STEPS = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

local weak = { __mode = "k" }
local anchor -- our Edit Mode frame: where the first roll sits, one roll's size
local ownScale = setmetatable({}, weak) -- roll frame -> its scale before ours

local function rollFrame(i)
    return _G["GroupLootFrame" .. i]
end

local function gamepad()
    return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end

-- Places a roll (or an example of one) `k` rolls on from the first, at our scale.
local function put(frame, k)
    if ownScale[frame] == nil then
        ownScale[frame] = frame:GetScale()
    end
    frame:SetScale(module.db.scale / 100)
    local step = STEPS[module.db.grow] or STEPS.up
    local gap = module.db.spacing
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", anchor, "CENTER", step[1] * k * (ROLL_WIDTH + gap), step[2] * k * (ROLL_HEIGHT + gap))
end

-- After Blizzard stacks the rolls: each one against our frame, in Blizzard's order, with no gaps
-- left by a roll that ended.
local function placeRolls()
    local container = GroupLootContainer
    if not (module.enabled and anchor and container and container.rollFrames) or gamepad() then
        return
    end
    local k = 0
    for i = 1, container.maxIndex or 0 do
        local frame = container.rollFrames[i]
        if frame then
            put(frame, k)
            k = k + 1
        end
    end
end

-- Turning off: each roll back where Blizzard stacks it, at its own scale.
local function giveBack()
    for frame, scale in pairs(ownScale) do
        if frame.IsForbidden == nil or not frame:IsForbidden() then
            frame:SetScale(scale)
        end
    end
    local container = GroupLootContainer
    if not (container and container.rollFrames) or gamepad() then
        return
    end
    for i = 1, container.maxIndex or 0 do
        local frame = container.rollFrames[i]
        if frame and ownScale[frame] then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", container, "BOTTOM", 0, (container.reservedSize or 100) * (i - 0.5))
        end
    end
end

-- Time left ------------------------------------------------------------------------------------------

local timers = setmetatable({}, weak) -- a timer bar -> our seconds beside it

local function timerText(bar)
    local text = timers[bar]
    if not text then
        -- Above the bar's right end, under the item's name: Greed's button is past the bar's end.
        text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 1)
        timers[bar] = text
    end
    return text
end

local function showSeconds(bar, seconds)
    local text = timerText(bar)
    if not (module.enabled and module.db.timer and seconds) then
        text:Hide()
        return
    end
    if text.seconds ~= seconds then
        text.seconds = seconds
        text:SetFormattedText(L.LOOTROLLS_TIMER_TEXT, seconds)
    end
    text:Show()
end

-- After Blizzard's own OnUpdate for a roll, which runs every frame while it shows.
local function onRollUpdate(frame)
    local bar, rollID = frame.Timer, frame.rollID
    if not bar then
        return
    end
    local left = rollID and GetLootRollTimeLeft and GetLootRollTimeLeft(rollID)
    showSeconds(bar, readable(left) and left and floor(left / 1000 + 0.5) or nil)
end

-- Roll counts ----------------------------------------------------------------------------------------

local tallies = setmetatable({}, weak) -- a roll's buttons' holder -> { need, greed, pass } texts

local function buttonsOf(frame)
    local holder = frame.LootButtonContainer or frame
    return holder, holder.NeedButton, holder.GreedButton, holder.PassButton
end

-- Each count at its button's corner, on the buttons' holder: a cosmetic roll shows Transmog where
-- Greed is, and its count goes there.
local function countTexts(frame)
    local holder, need, greed, pass = buttonsOf(frame)
    local texts = tallies[holder]
    if not texts and need and greed and pass then
        texts = {}
        for i, button in ipairs({ need, greed, pass }) do
            local text = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
            texts[i] = text
        end
        tallies[holder] = texts
    end
    return texts
end

local function showCounts(frame, need, greed, pass)
    local texts = countTexts(frame)
    if not texts then
        return
    end
    local on = module.enabled and module.db.counts
    for i, count in ipairs({ need or 0, greed or 0, pass or 0 }) do
        texts[i]:SetText(count)
        texts[i]:SetShown(on and count > 0 or false)
    end
end

-- How many picked each, from a drop in the loot history: Need (main or off spec), Greed (or
-- Transmog), and Pass (EncounterLootDropRollState, LootHistoryDocumentation.lua).
local function tally(drop)
    local states = Enum and Enum.EncounterLootDropRollState or {}
    local need, greed, pass = 0, 0, 0
    for _, roll in ipairs(drop.rollInfos or {}) do
        local state = roll.state
        if not readable(state) then
            return nil
        end
        if state == (states.NeedMainSpec or 0) or state == (states.NeedOffSpec or 1) then
            need = need + 1
        elseif state == (states.Greed or 3) or state == (states.Transmog or 2) then
            greed = greed + 1
        elseif state == (states.Pass or 5) then
            pass = pass + 1
        end
    end
    return need, greed, pass
end

-- The roll showing this item, matched by its link.
local function rollFor(link)
    for i = 1, ROLLS do
        local frame = rollFrame(i)
        local rollID = frame and frame:IsShown() and frame.rollID
        local own = rollID and GetLootRollItemLink and GetLootRollItemLink(rollID)
        if readable(own) and own == link then
            return frame
        end
    end
end

local function countDrop(drop)
    local link = drop and drop.itemHyperlink
    local frame = readable(link) and link and rollFor(link)
    if frame then
        showCounts(frame, tally(drop))
    end
end

local function onDrop(_, encounterID, lootListKey)
    if C_LootHistory and C_LootHistory.GetSortedInfoForDrop then
        countDrop(C_LootHistory.GetSortedInfoForDrop(encounterID, lootListKey))
    end
end
module:OnWhile("counts", { LOOT_HISTORY_UPDATE_DROP = onDrop })

-- A roll that just showed: what the loot history already knows of its item.
local function countFromHistory(frame)
    showCounts(frame, 0, 0, 0)
    if not (module.enabled and module.db.counts and C_LootHistory and C_LootHistory.GetAllEncounterInfos) then
        return
    end
    for _, encounter in ipairs(C_LootHistory.GetAllEncounterInfos() or {}) do
        for _, drop in ipairs(C_LootHistory.GetSortedDropsForEncounter(encounter.encounterID) or {}) do
            if rollFor(drop.itemHyperlink) == frame then
                showCounts(frame, tally(drop))
                return
            end
        end
    end
end

local function onRollShow(frame)
    countFromHistory(frame)
end

-- Preview --------------------------------------------------------------------------------------------

-- Example items for the preview, from the game (ids from the original game's loot, kept in Forever).
local EXAMPLES = {
    { id = ns.GameData.Item(19019, "Thunderfury, Blessed Blade of the Windseeker"), quality = 5 },
    { id = ns.GameData.Item(18832, "Brutality Blade"), quality = 4 },
    { id = ns.GameData.Item(12640, "Lionheart Helm"), quality = 4 },
    { id = ns.GameData.Item(11684, "Ironfoe"), quality = 4 },
}
local LOOT_TOAST = "Interface\\LootFrame\\LootToast"
local examples = {} -- our example roll frames, made when first shown

local function qualityBorder(quality)
    if ColorManager and ColorManager.GetAtlasDataForLootBorderItemQuality then
        local atlas = ColorManager.GetAtlasDataForLootBorderItemQuality(quality)
        if atlas then
            return atlas
        end
    end
    return quality >= 5 and "loottoast-itemborder-orange" or "loottoast-itemborder-purple"
end

-- One example roll, laid out as GroupLootFrameBaseTemplate and MKBGroupLootFrameTemplate lay
-- theirs, from their art, but a frame of our own with no roll behind it.
local function newExample()
    local ok, frame = pcall(CreateFrame, "Frame", nil, UIParent, "DefaultDialogPanelTemplate")
    if not ok or not frame then
        frame = CreateFrame("Frame", nil, UIParent)
    end
    frame:SetSize(ROLL_WIDTH, ROLL_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(LOOT_TOAST)
    background:SetTexCoord(0.28222656, 0.55273438, 0.30859375, 0.57031250)
    background:SetAllPoints()
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetTexture(LOOT_TOAST)
    border:SetTexCoord(0.00097656, 0.28027344, 0.43750000, 0.73437500)
    border:SetSize(286, 76)
    border:SetPoint("CENTER")
    frame.Name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.Name:SetSize(125, 30)
    frame.Name:SetJustifyH("LEFT")
    frame.Name:SetPoint("TOPLEFT", 60, -15)
    frame.IconFrame = CreateFrame("Frame", nil, frame)
    frame.IconFrame:SetSize(34, 34)
    frame.IconFrame:SetPoint("TOPLEFT", 10, -11)
    frame.Icon = frame.IconFrame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetAllPoints()
    frame.IconBorder = frame.IconFrame:CreateTexture(nil, "OVERLAY")
    frame.IconBorder:SetSize(42, 42)
    frame.IconBorder:SetPoint("CENTER", 0, -2)
    frame.Timer = CreateFrame("StatusBar", nil, frame)
    frame.Timer:SetSize(190, 8)
    frame.Timer:SetPoint("BOTTOMLEFT", 3, 2)
    frame.Timer:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    frame.Timer:SetStatusBarColor(1, 1, 0)
    frame.Timer:SetMinMaxValues(0, 60)
    frame.Timer:SetValue(42)
    local barBackground = frame.Timer:CreateTexture(nil, "BACKGROUND")
    barBackground:SetColorTexture(0, 0, 0)
    barBackground:SetAllPoints()
    -- The buttons, as pictures: Need, Pass beside it, Greed under it.
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetPoint("LEFT", frame.Name, "RIGHT", 3, 0)
    holder:SetPoint("TOP")
    holder:SetPoint("BOTTOMRIGHT")
    frame.LootButtonContainer = holder
    local function button(atlas)
        local b = CreateFrame("Frame", nil, holder)
        b:SetSize(32, 32)
        local art = b:CreateTexture(nil, "ARTWORK")
        art:SetAllPoints()
        art:SetAtlas(atlas)
        return b
    end
    holder.NeedButton = button("lootroll-toast-icon-need-up")
    holder.NeedButton:SetPoint("TOPLEFT", 14, -7)
    holder.PassButton = button("lootroll-toast-icon-pass-up")
    holder.PassButton:SetPoint("LEFT", holder.NeedButton, "RIGHT", 6, 2)
    holder.GreedButton = button("lootroll-toast-icon-greed-up")
    holder.GreedButton:SetPoint("TOP", holder.NeedButton, "BOTTOM", 0, 5)
    return frame
end

local function fillExample(frame, example)
    local id = example.id
    local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) or example.quality
    if not readable(quality) or not quality then
        quality = example.quality
    end
    frame.Icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or 134400)
    frame.IconBorder:SetAtlas(qualityBorder(quality))
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    frame.Name:SetText(readable(name) and name or "")
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then
        frame.Name:SetTextColor(color.r, color.g, color.b)
    end
    local link = format("item:%d", id)
    showSeconds(frame.Timer, 42)
    showCounts(frame, 2, 1, 1)
    -- The marks Upgrade Arrows, Appearance Icons, and the others put on a real roll's icon.
    ItemButtons.MarkExampleRoll(frame.Icon, link)
end

local editing = false -- Edit Mode is open

-- The example rolls while Edit Mode is open: as many as Preview Rolls says, where rolls will go.
local function showPreview()
    local count = (module.enabled and editing) and module.db.preview or 0
    for k = 1, #EXAMPLES do
        local frame = examples[k]
        if k <= count then
            if not frame then
                frame = newExample()
                examples[k] = frame
            end
            fillExample(frame, EXAMPLES[k])
            put(frame, k - 1)
            frame:Show()
        elseif frame then
            frame:Hide()
        end
    end
end

local function onEditMode(active)
    editing = active
    showPreview()
end

-- Turning on and off ---------------------------------------------------------------------------------

local function apply()
    if not anchor then
        return
    end
    anchor:SetScale(module.db.scale / 100)
    EditMode.Place(anchor, module.db.x, module.db.y)
    placeRolls()
    showPreview()
end

-- What's on the rolls showing now, after an option changed.
local function refreshRolls()
    for i = 1, ROLLS do
        local frame = rollFrame(i)
        if frame and frame:IsShown() then
            onRollShow(frame)
        end
    end
    for bar, text in pairs(timers) do
        if not (module.enabled and module.db.timer) then
            text:Hide()
        elseif bar:IsVisible() then
            text:Show()
        end
    end
end

function module:OnEnable()
    if not anchor then
        anchor = CreateFrame("Frame", nil, UIParent)
        anchor:SetSize(ROLL_WIDTH, ROLL_HEIGHT)
        anchor:SetFrameStrata("DIALOG")
    end
    anchor:Show()
    EditMode.RegisterModule(self, anchor, L.LOOTROLLS_TITLE, apply, onEditMode)
    self:Hook("GroupLootContainer_Update", placeRolls)
    for i = 1, ROLLS do
        -- The frames' scripts were set when they loaded, so their own functions can't be hooked by
        -- name: their scripts are.
        self:HookScript(rollFrame(i), "OnShow", onRollShow)
        self:HookScript(rollFrame(i), "OnUpdate", onRollUpdate)
    end
    apply()
    refreshRolls()
end

function module:OnDisable()
    if anchor then
        EditMode.Unregister(anchor)
        anchor:Hide()
    end
    showPreview()
    giveBack()
    refreshRolls()
    for _, texts in pairs(tallies) do
        for _, text in ipairs(texts) do
            text:Hide()
        end
    end
end

function module:OnOptionChanged()
    apply()
    refreshRolls()
end
