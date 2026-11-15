-- Chat Arrow Keys: while you type in chat, Up and Down bring back what you sent before and Left
-- and Right move through the text, without holding Alt.
--
-- The chat box reads the arrow keys only with Alt held, so they keep moving your character while
-- it's open (its "alt arrow key mode"). This turns that off, which gives it Left and Right.
--
-- On Forever since build 70938 that isn't enough for Up and Down: the client brings back a sent
-- line only on Alt+Up, whatever the mode. So we keep what each box sent (every line the game adds
-- to its own history) and put it in the box ourselves. Each box's own mode is kept to put back.
local _, ns = ...

local ipairs, setmetatable, remove = ipairs, setmetatable, table.remove
local IsAltKeyDown = IsAltKeyDown

local L = ns.L
local Chat = ns.Chat

local module = ns.NewModule("ChatArrowKeys", L.CHATARROWKEYS_DESC, {
    enabled = true,
})
module.title = L.CHATARROWKEYS_TITLE
module.category = "chat"
module.added = "1.5.0"

local LINES = 32 -- as many as the game keeps (the template's historyLines)

local modes = setmetatable({}, { __mode = "k" }) -- edit box -> its mode before ours
local sent = setmetatable({}, { __mode = "k" }) -- edit box -> what it sent, oldest first
local place = setmetatable({}, { __mode = "k" }) -- edit box -> how far back Up has gone

local function editBoxOf(frame)
    return frame.editBox or _G[(frame:GetName() or "") .. "EditBox"]
end

-- Whether a list of names or emotes is open under the box: the arrows are its own then.
local function listOpen(box)
    -- Blizzard's, and the one the Lib-EditBox-AutoComplete library gives other addons.
    local theirs = _G["EditBoxAutoCompleteBox"]
    if AutoCompleteBox and AutoCompleteBox.parent == box and AutoCompleteBox:IsShown() then
        return true
    end
    return theirs ~= nil and theirs.parent == box and theirs:IsShown() and true or false
end

local function onHistoryLine(box, text)
    if not ns.IsText(text) or text == "" then
        return
    end
    local lines = sent[box]
    if not lines then
        lines = {}
        sent[box] = lines
    end
    if lines[#lines] ~= text then
        lines[#lines + 1] = text
        if #lines > LINES then
            remove(lines, 1)
        end
    end
    place[box] = nil
end

local function onArrow(box, key)
    local lines = sent[box]
    -- With Alt held the game brings the line back itself.
    if not lines or IsAltKeyDown() or listOpen(box) then
        return
    end
    local back = place[box] or 0
    if key == "UP" then
        back = back + 1
    elseif key == "DOWN" then
        back = back - 1
    else
        return
    end
    if back < 0 or back > #lines then
        return
    end
    place[box] = back
    box:SetText(back == 0 and "" or lines[#lines + 1 - back])
end

local function onFocusGained(box)
    -- An autocomplete list (Blizzard's, or another addon's) puts back the mode it found when it
    -- closes, which can be the one from before ours. So set it again each time the box is typed in.
    box:SetAltArrowKeyMode(false)
    place[box] = nil
end

local function apply(frame)
    local box = editBoxOf(frame)
    if not (box and box.SetAltArrowKeyMode and box.GetAltArrowKeyMode) then
        return
    end
    if module.enabled then
        if modes[box] == nil then
            modes[box] = box:GetAltArrowKeyMode() and true or false
            module:Hook(box, "AddHistoryLine", onHistoryLine)
            module:HookScript(box, "OnArrowPressed", onArrow)
            module:HookScript(box, "OnEditFocusGained", onFocusGained)
        end
        box:SetAltArrowKeyMode(false)
    elseif modes[box] ~= nil then
        box:SetAltArrowKeyMode(modes[box])
        modes[box] = nil
    end
end

function module:IsAvailable()
    local box = ChatFrame1 and editBoxOf(ChatFrame1)
    return box ~= nil and box.SetAltArrowKeyMode ~= nil
end

function module:OnEnable()
    -- Every window's chat box, and one added later.
    Chat.EachWindow(self, apply)
end

function module:OnDisable()
    for _, frame in ipairs(Chat.Frames()) do
        apply(frame)
    end
end
