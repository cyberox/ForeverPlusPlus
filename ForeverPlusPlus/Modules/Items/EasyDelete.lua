-- Easy Delete: types the word into Blizzard's "type DELETE to confirm" box when you destroy a good
-- item, so Yes is one click. The popup, its item link, and its Yes and No buttons stay Blizzard's.
local _, ns = ...

local L = ns.L

local module = ns.NewModule("EasyDelete", L.EASYDELETE_DESC, {
    enabled = false,
})
module.title = L.EASYDELETE_TITLE
module.category = "items"
module.developer = { enabled = true }

-- The popups that want the word typed (Blizzard_StaticPopup_Game/Mainline/GameDialogDefs.lua).
-- Their gamepad versions and the plain DELETE_ITEM popup ask for no word.
local TYPED = {
    DELETE_GOOD_ITEM = true,
    DELETE_GOOD_QUEST_ITEM = true,
}

-- After StaticPopup_Show, once the popup's OnShow has disabled Yes. Setting the text runs the
-- popup's own EditBoxOnTextChanged, which enables Yes when the word matches.
local function onShow(which)
    if not TYPED[which] or not DELETE_ITEM_CONFIRM_STRING then
        return
    end
    local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
    local editBox = dialog and dialog.GetEditBox and dialog:GetEditBox()
    if editBox then
        editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
    end
end

function module:OnEnable()
    self:Hook("StaticPopup_Show", onShow)
end
