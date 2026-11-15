-- A yes/no confirmation in Blizzard's own popup, for anything that throws data away, such as a
-- module's Reset button in Settings, and a popup that asks for a line of text or shows one to copy.
-- While the controller interface is on, each is a frame of our own instead (see below).
local _, ns = ...

local StaticPopupDialogs, StaticPopup_Show, YES, NO = StaticPopupDialogs, StaticPopup_Show, YES, NO
local CANCEL, ACCEPT, CLOSE, strtrim, error = CANCEL, ACCEPT, CLOSE, strtrim, error
local CreateFrame, UIParent, ipairs, format, max = CreateFrame, UIParent, ipairs, string.format, math.max

-- A popup of our own -------------------------------------------------------------------------------
-- With the controller interface on, one of Blizzard's popups shown by an addon runs the
-- controller's focus manager tainted, as a menu does (StaticPopupGamepad's HandlePopupShow; see
-- Lib/Menus.lua), and the game then blocks its own actions and blames us. So then the question is
-- asked in a frame of our own: the text, an optional text box, and up to four buttons. The mouse
-- works it, a controller's A is its first button and B closes it, and Enter and Escape work in
-- the text box.
local WIDTH, PAD, BUTTON_WIDTH, BUTTON_GAP = 340, 18, 110, 8 -- the least the popup and a button are
local BUTTON_PAD = 28 -- room around a button's text
local own -- the frame, made the first time it's needed

local function ownPopup()
    if own then
        return own
    end
    local template = ns.Frames.HasTemplate("TooltipBackdropTemplate") and "TooltipBackdropTemplate" or nil
    own = CreateFrame("Frame", nil, UIParent, template)
    own:SetFrameStrata("FULLSCREEN_DIALOG")
    own:SetFrameLevel(200)
    own:SetWidth(WIDTH)
    own:SetPoint("TOP", UIParent, "TOP", 0, -135) -- where Blizzard's first popup sits
    own:EnableMouse(true)
    own:Hide()
    if not template then
        local back = own:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    end
    own.text = own:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    own.text:SetPoint("TOP", 0, -PAD)
    own.text:SetWidth(WIDTH - PAD * 2)
    own.box = CreateFrame("EditBox", nil, own, ns.Frames.HasTemplate("InputBoxTemplate") and "InputBoxTemplate" or nil)
    own.box:SetSize(WIDTH - PAD * 3, 22)
    own.box:SetAutoFocus(false)
    own.box:SetFontObject("ChatFontNormal")
    own.box:SetScript("OnEscapePressed", function()
        own:Hide()
    end)
    own.box:SetScript("OnEnterPressed", function()
        own.press(1)
    end)
    own.buttons = {}
    for i = 1, 4 do
        own.buttons[i] = ns.Frames.Button(own, nil, BUTTON_WIDTH, function()
            own.press(i)
        end)
    end
    if own.EnableGamePadButton then
        -- The D-pad moves between the buttons, A presses the one it's on, and B closes.
        own:SetScript("OnGamePadButtonDown", function(_, button)
            if button == "PAD1" then
                own.press(own.focus)
            elseif button == "PAD2" then
                own:Hide()
            elseif button == "PADDLEFT" or button == "PADDRIGHT" then
                own.buttons[own.focus]:UnlockHighlight()
                own.focus = (own.focus - 1 + (button == "PADDRIGHT" and 1 or -1)) % own.count + 1
                own.buttons[own.focus]:LockHighlight()
            end
        end)
        own:SetScript("OnShow", function(self)
            self:EnableGamePadButton(true)
        end)
        own:SetScript("OnHide", function(self)
            self:EnableGamePadButton(false)
        end)
    end
    return own
end

-- Asks in our own popup. `buttons` is a list of `{ text, fn }` in the order they show, a `fn` of
-- false for one that only closes; `edit`, when given, is `{ initial, long }` and each `fn` gets
-- the box's text.
local function ask(text, buttons, edit)
    local popup = ownPopup()
    -- Every button as wide as the longest one's text needs, and the popup as wide as they need.
    local count = #buttons
    local width = BUTTON_WIDTH
    for i, spec in ipairs(buttons) do
        local button = popup.buttons[i]
        button:SetText(spec.text)
        width = max(width, (button:GetTextWidth() or 0) + BUTTON_PAD)
    end
    local popupWidth = max(WIDTH, (width + BUTTON_GAP) * count - BUTTON_GAP + PAD * 2)
    popup:SetWidth(popupWidth)
    popup.text:SetWidth(popupWidth - PAD * 2)
    popup.text:SetText(text)
    local y = PAD + popup.text:GetStringHeight() + 12
    local box = popup.box
    box:SetShown(edit ~= nil)
    if edit then
        box:ClearAllPoints()
        box:SetPoint("TOP", 0, -y)
        box:SetMaxLetters(edit.long and 0 or 2000)
        box:SetText(edit.initial or "")
        y = y + 22 + 12
    end
    local left = -((width + BUTTON_GAP) * count - BUTTON_GAP) / 2
    for i, button in ipairs(popup.buttons) do
        local spec = buttons[i]
        button:SetShown(spec ~= nil)
        button:UnlockHighlight()
        if spec then
            button:SetWidth(width)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", popup, "TOP", left + (i - 1) * (width + BUTTON_GAP), -y)
        end
    end
    popup.press = function(index)
        local spec = buttons[index]
        local typed = edit and box:GetText() or nil
        popup:Hide()
        if spec and spec.fn then
            spec.fn(typed)
        end
    end
    popup.count, popup.focus = count, 1
    -- Only a controller needs to see which button A presses.
    if popup.EnableGamePadButton then
        popup.buttons[1]:LockHighlight()
    end
    popup:SetHeight(y + 22 + PAD)
    popup:Show()
    if edit then
        box:HighlightText()
        box:SetFocus()
    end
end

local function gamepad()
    return ns.Menus.GamepadUI()
end

-- Shows our popup for `key`, made from `build()` the first time the key is used, so a key always
-- has the same buttons. Its text is this call's, since callers format names into it. `textArg`
-- fills a %s in its text.
local function show(key, text, build, data, textArg)
    local which = "FOREVERPLUSPLUS_" .. key
    if not StaticPopupDialogs[which] then
        local dialog = build()
        dialog.timeout = 0
        dialog.whileDead = true
        dialog.hideOnEscape = true
        dialog.preferredIndex = 3 -- clear of the popups the game's own UI uses
        StaticPopupDialogs[which] = dialog
    end
    StaticPopupDialogs[which].text = text
    StaticPopup_Show(which, textArg, nil, data)
end

---Asks the player to confirm, then calls `onAccept`. The same `key` always asks the same question:
---the popup is made the first time it's used. `textArg` fills a %s in `text`, such as a name.
---@param key string a name for this question, such as "AUCTIONPRICES_RESET"
---@param text string the question
---@param onAccept function
---@param textArg? string
function ns.Confirm(key, text, onAccept, textArg)
    if gamepad() then
        ask(textArg and format(text, textArg) or text, { { text = YES, fn = onAccept }, { text = NO, fn = false } })
        return
    end
    -- Probe: StaticPopup is Blizzard's confirmation dialog; without it, just do it.
    if not (StaticPopupDialogs and StaticPopup_Show) then
        onAccept()
        return
    end
    show(key, text, function()
        return {
            text = text,
            button1 = YES,
            button2 = NO,
            -- This call's function, not the first one's, since the popup is made only once.
            OnAccept = function(_, data)
                data.onAccept()
            end,
        }
    end, { onAccept = onAccept }, textArg)
end

local choices = {} -- key -> { onFirst, onSecond, onThird } of the latest ns.ConfirmChoice for it

---Asks the player to pick one of two (or three) things or cancel, laid out like Blizzard's own
---Defaults popup (`first` | Cancel | `second`, then `third` when given), then calls that choice's
---function. Like ns.Confirm, the popup for a `key` is made the first time it's used, so a key
---always has a third choice or never does.
---@param key string a name for this question
---@param text string the question
---@param first string the left button
---@param onFirst function
---@param second string the button right of Cancel
---@param onSecond function
---@param third? string the right button
---@param onThird? function
function ns.ConfirmChoice(key, text, first, onFirst, second, onSecond, third, onThird)
    if gamepad() then
        local buttons = {
            { text = first, fn = onFirst }, { text = CANCEL, fn = false }, { text = second, fn = onSecond },
        }
        if third then
            buttons[4] = { text = third, fn = onThird }
        end
        ask(text, buttons)
        return
    end
    -- Probe: as ns.Confirm. Without the popup, do nothing: there's no way to know which.
    if not (StaticPopupDialogs and StaticPopup_Show) then
        return
    end
    choices[key] = { onFirst, onSecond, onThird }
    -- The buttons are this call's too, for a choice whose buttons name something ("Copy of Raid").
    local made = StaticPopupDialogs["FOREVERPLUSPLUS_" .. key]
    if made then
        made.button1, made.button3, made.button4 = first, second, third
    end
    show(key, text, function()
        local dialog = {
            text = text,
            button1 = first,
            button2 = CANCEL,
            button3 = second,
            button4 = third,
            -- The latest call's functions, not the first one's, since the popup is made once.
            OnAccept = function()
                choices[key][1]()
            end,
            OnAlt = function()
                choices[key][2]()
            end,
        }
        if third then
            -- A fourth button calls OnCancel unless callbacks go by the button's index, which
            -- then calls OnButton3 and OnButton4 in place of OnAlt (Blizzard_StaticPopup's
            -- StaticPopup_OnClick, Gethe `forever` branch). Cancel and Escape still call nothing.
            dialog.selectCallbackByIndex = true
            dialog.OnButton3 = dialog.OnAlt
            dialog.OnButton4 = function()
                choices[key][3]()
            end
        end
        return dialog
    end)
end

---ns.ConfirmChoice from a list of buttons, { text, fn } each, in order: the first left of Cancel,
---the rest right of it. It holds two or three; the same `key` always gets as many.
---@param key string
---@param text string
---@param buttons { text: string, fn: function }[]
function ns.ConfirmButtons(key, text, buttons)
    local first, second, third = buttons[1], buttons[2], buttons[3]
    if not (first and second) then
        error("Forever++: ConfirmButtons needs two or three buttons", 2)
    end
    ns.ConfirmChoice(key, text, first.text, first.fn, second.text, second.fn,
        third and third.text, third and third.fn)
end

-- The popup's text box. Probe: GetEditBox is Mainline's; older popups had a field.
local function editBoxOf(dialog)
    return dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
end

---Asks for a line of text in Blizzard's popup, with `initial` filled in and selected, then calls
---`onAccept(text)`. Without `onAccept`, it shows `initial` to copy, with only a Close button. A
---`key` always has the same buttons, so use one key per kind of question.
---@param key string a name for this question
---@param text string the question
---@param initial? string
---@param onAccept? fun(text: string)
---@param long? boolean no limit on the text's length, for a string as long as a node export
function ns.Prompt(key, text, initial, onAccept, long)
    if gamepad() then
        local buttons = onAccept and { { text = ACCEPT, fn = onAccept }, { text = CANCEL, fn = false } }
            or { { text = CLOSE, fn = false } }
        ask(text, buttons, { initial = initial, long = long })
        return
    end
    if not (StaticPopupDialogs and StaticPopup_Show) then
        return
    end
    show(key, text, function()
        return {
            text = text,
            button1 = onAccept and ACCEPT or CLOSE,
            button2 = onAccept and CANCEL or nil,
            hasEditBox = true,
            -- Room for a pasted string, past the default limit; 0 is none at all.
            maxLetters = long and 0 or 2000,
            OnShow = function(dialog, data)
                local box = editBoxOf(dialog)
                if box then
                    box:SetText(data.initial or "")
                    box:HighlightText()
                    box:SetFocus()
                end
            end,
            OnAccept = function(dialog, data)
                local box = editBoxOf(dialog)
                if data.onAccept and box then
                    data.onAccept(box:GetText())
                end
            end,
            EditBoxOnEnterPressed = function(box, data)
                if data.onAccept then
                    data.onAccept(box:GetText())
                end
                box:GetParent():Hide()
            end,
            EditBoxOnEscapePressed = function(box)
                box:GetParent():Hide()
            end,
        }
    end, { initial = initial, onAccept = onAccept })
end

---ns.Prompt for a name: calls `onName(name)` with the text trimmed, and not at all when it's blank.
---@param key string a name for this question
---@param text string the question
---@param initial? string
---@param onName fun(name: string)
function ns.PromptName(key, text, initial, onName)
    ns.Prompt(key, text, initial, function(input)
        local name = strtrim(input or "")
        if name ~= "" then
            onName(name)
        end
    end)
end
