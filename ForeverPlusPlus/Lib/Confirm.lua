-- A yes/no confirmation in Blizzard's own popup, for anything that throws data away, such as a
-- module's Reset button in Settings, and a popup that asks for a line of text or shows one to copy.
local _, ns = ...

local StaticPopupDialogs, StaticPopup_Show, YES, NO = StaticPopupDialogs, StaticPopup_Show, YES, NO
local CANCEL, ACCEPT, CLOSE, strtrim, error = CANCEL, ACCEPT, CLOSE, strtrim, error

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
