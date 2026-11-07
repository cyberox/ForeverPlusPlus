-- AddOns List: a plainer AddOns list on the character screen and the game menu. Blizzard's list
-- sorts addons under category headers; this builds the same kind of rows without the headers,
-- with addons you have enabled first and the disabled ones after, each group in name order. It
-- changes only which rows the list's scroll box shows, so the rows, the checkboxes, and the
-- Enable All / Disable All buttons are still Blizzard's. Turning it off gives Blizzard's own list
-- back at once. Its AddOn Sets option adds a Sets dropdown beside Disable All, to save which
-- addons are on under a name and turn that list back on later.
local addonName, ns = ...

local _G, ipairs, pairs, next, type, pcall, sort, lower, find, format =
    _G, ipairs, pairs, next, type, pcall, table.sort, string.lower, string.find, string.format
local C_AddOns, UnitGUID, CreateFrame, CreateTreeDataProvider, geterrorhandler =
    C_AddOns, UnitGUID, CreateFrame, CreateTreeDataProvider, geterrorhandler

local L = ns.L

local module = ns.NewModule("AddOnsList", L.ADDONSLIST_DESC, {
    enabled = true,
    enabledFirst = true, -- enabled addons above the disabled ones
    ungroup = false, -- disabled addons leave their group and sit with the other disabled ones
    notes = true, -- the search box also looks in an addon's notes
    showSets = false, -- the Sets dropdown beside Disable All
    chat = true, -- say so in chat when a set is saved, or has addons that aren't installed
    -- Saved sets, account-wide: { [set name] = { [addon name] = true } }. By addon name, since an
    -- addon's index changes when addons are added or removed.
    sets = {},
})
module.title = L.ADDONSLIST_TITLE
module.category = "system"

-- What it says in chat is only about sets, so its checkbox sits under AddOn Sets.
local chat = ns.ChatOption(L.ADDONSLIST_CHAT_DESC)
chat.requires = "showSets"
chat.added = "1.2.0"

module.options = {
    { key = "enabledFirst", name = L.ADDONSLIST_ENABLEDFIRST, description = L.ADDONSLIST_ENABLEDFIRST_DESC },
    { key = "ungroup", name = L.ADDONSLIST_UNGROUP, description = L.ADDONSLIST_UNGROUP_DESC },
    { key = "notes", name = L.ADDONSLIST_NOTES, description = L.ADDONSLIST_NOTES_DESC },
    { key = "showSets", name = L.ADDONSLIST_SETS, description = L.ADDONSLIST_SETS_DESC, added = "0.9.0" },
    chat,
}

-- Blizzard_AddOnList makes AddonList with a ScrollBox of tree rows (each row's data is
-- `{ addonIndex = n }`) and a SearchBox, and runs AddonList_Update to fill it. Read from the
-- Mainline UI this client is built on; the row shape is Unverified here, so every piece is probed.
local ADDON = "Blizzard_AddOnList"

local busy = false

local function plain(text)
    return lower(ns.Text.Plain(text or ""))
end

local function addList()
    local list = _G.AddonList
    if type(list) == "table" and list.ScrollBox and list.SearchBox and list.ScrollBox.SetDataProvider then
        return list
    end
end

---The character the list asks about. On Forever the list passes a character's GUID to
---GetAddOnEnableState, not its name: a name gets "enabled" for every addon (probed 2026-09-30).
---It is the dropdown's pick: nil for All, a GUID for one character. When the pick can't be read,
---the player. The pick is the third value of CollectSelectionData, a list of menu descriptions
---(GetSelectionData's first is always nil there).
---@param list table|nil
---@return string|nil
local function selectedCharacter(list)
    local dropdown = list and list.Dropdown
    if dropdown and dropdown.CollectSelectionData then
        local ok, _, _, selections = pcall(dropdown.CollectSelectionData, dropdown)
        local selected = ok and type(selections) == "table" and selections[1]
        if selected and selected.GetData then
            local data = selected:GetData()
            if type(data) == "string" and find(data, "^Player%-") then
                return data
            end
            return nil
        end
    end
    return UnitGUID("player")
end

---Everything the list needs to know about one addon, read once per rebuild.
local function readAddOn(index, character)
    local name, title, notes = C_AddOns.GetAddOnInfo(index)
    local group = C_AddOns.GetAddOnMetadata(index, "Group")
    local state = C_AddOns.GetAddOnEnableState(index, character)
    local _, reason = C_AddOns.IsAddOnLoadable(index, character)
    local none = Enum and Enum.AddOnEnableState and Enum.AddOnEnableState.None or 0
    return {
        index = index,
        name = name,
        group = group,
        key = plain(title ~= "" and title or name),
        text = plain(title or name),
        notes = plain(notes),
        -- A dependency that's switched off counts as disabled, like its own checkbox would.
        disabled = state <= none or reason == "DEP_DISABLED",
    }
end

local function byKey(a, b)
    if a.key ~= b.key then
        return a.key < b.key
    end
    return a.index < b.index
end

local function matches(info, filter, withNotes)
    if filter == "" then
        return true
    end
    if find(info.text, filter, 1, true) or find(plain(info.name), filter, 1, true) then
        return true
    end
    if info.group and find(plain(info.group), filter, 1, true) then
        return true
    end
    return withNotes and find(info.notes, filter, 1, true) ~= nil
end

-- Builds the tree: a row for each group's parent with its addons under it, enabled groups first
-- when asked, no category rows.
local function build(list)
    local db = module.db
    local character = selectedCharacter(list)
    local filter = plain(list.SearchBox:GetText())

    local infos, byName = {}, {}
    for index = 1, C_AddOns.GetNumAddOns() do
        local info = readAddOn(index, character)
        infos[#infos + 1] = info
        byName[info.name] = info
    end

    -- A group is its parent's name in the "Group" metadata; an addon whose parent isn't installed
    -- stands alone.
    local roots, children = {}, {}
    for _, info in ipairs(infos) do
        local parent = info.group and info.group ~= info.name and byName[info.group]
        if parent and not (db.ungroup and info.disabled) then
            children[parent] = children[parent] or {}
            children[parent][#children[parent] + 1] = info
        else
            roots[#roots + 1] = info
        end
    end

    local shown, hidden = {}, {}
    for _, root in ipairs(roots) do
        local kids = children[root]
        local rootMatch = matches(root, filter, db.notes)
        local keep
        if kids then
            keep = {}
            for _, kid in ipairs(kids) do
                if rootMatch or matches(kid, filter, db.notes) then
                    keep[#keep + 1] = kid
                end
            end
            sort(keep, byKey)
        end
        if rootMatch or (keep and #keep > 0) then
            root.keep = keep
            local bucket = db.enabledFirst and root.disabled and hidden or shown
            bucket[#bucket + 1] = root
        end
    end
    sort(shown, byKey)
    sort(hidden, byKey)

    local provider = CreateTreeDataProvider()
    local function insert(root)
        local node = provider:Insert({ addonIndex = root.index })
        if root.keep then
            for _, kid in ipairs(root.keep) do
                node:Insert({ addonIndex = kid.index })
            end
        end
    end
    for _, root in ipairs(shown) do
        insert(root)
    end
    for _, root in ipairs(hidden) do
        insert(root)
    end
    return provider
end

local function rebuild()
    local list = addList()
    if busy or not list or not list:IsShown() or not (C_AddOns and CreateTreeDataProvider) then
        return
    end
    busy = true
    local ok, provider = pcall(build, list)
    if ok then
        list.ScrollBox:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    else
        -- Leave Blizzard's list as it is rather than show half of ours, and report the error.
        geterrorhandler()(provider)
    end
    busy = false
end

-- AddOn sets ---------------------------------------------------------------------------------------

local setsDropdown

local function isOn(index, character)
    local none = Enum and Enum.AddOnEnableState and Enum.AddOnEnableState.None or 0
    return C_AddOns.GetAddOnEnableState(index, character) > none
end

-- Blizzard redraws the checkboxes, and turns Okay into Reload UI when anything changed.
local function refreshList()
    if type(_G.AddonList_Update) == "function" then
        _G.AddonList_Update()
    end
end

---Saves the addons on for the character the list shows (all characters for All) as `name`,
---replacing a set of that name.
local function saveSet(name)
    local character = selectedCharacter(addList())
    local set = {}
    for index = 1, C_AddOns.GetNumAddOns() do
        if isOn(index, character) then
            set[(C_AddOns.GetAddOnInfo(index))] = true
        end
    end
    module.db.sets[name] = set
    module:Print(format(L.ADDONSLIST_SETS_SAVED, name))
end

---Turns on the set's addons and turns off the rest, for the character the list shows, like
---checking the boxes by hand: nothing changes until Okay, and Cancel undoes it. Forever++ stays on,
---so the sets are still there next time.
local function applySet(name)
    local set = module.db.sets[name]
    if not set then
        return
    end
    local character = selectedCharacter(addList())
    local installed = {}
    for index = 1, C_AddOns.GetNumAddOns() do
        local addon = C_AddOns.GetAddOnInfo(index)
        installed[addon] = true
        if set[addon] or addon == addonName then
            C_AddOns.EnableAddOn(index, character)
        else
            C_AddOns.DisableAddOn(index, character)
        end
    end
    local missing = 0
    for addon in pairs(set) do
        if not installed[addon] then
            missing = missing + 1
        end
    end
    refreshList()
    if missing > 0 then
        module:Print(format(L.ADDONSLIST_SETS_MISSING, name, missing))
    end
end

local function promptSave()
    ns.PromptName("ADDONSLIST_SETS_SAVE", L.ADDONSLIST_SETS_SAVE_PROMPT, "", function(name)
        if module.db.sets[name] then
            ns.Confirm("ADDONSLIST_SETS_REPLACE", L.ADDONSLIST_SETS_REPLACE_CONFIRM, function()
                saveSet(name)
            end, name)
        else
            saveSet(name)
        end
    end)
end

local function deleteSet(name)
    ns.Confirm("ADDONSLIST_SETS_DELETE", L.ADDONSLIST_SETS_DELETE_CONFIRM, function()
        module.db.sets[name] = nil
    end, name)
end

local function setNames()
    local names = {}
    for name in pairs(module.db.sets) do
        names[#names + 1] = name
    end
    sort(names, function(a, b)
        return lower(a) < lower(b)
    end)
    return names
end

-- Click a set to apply it; save and delete under a divider.
local function setupSetsMenu(_, root)
    local names = setNames()
    if #names == 0 then
        root:CreateTitle(L.ADDONSLIST_SETS_NONE)
    end
    for _, name in ipairs(names) do
        root:CreateButton(name, applySet, name)
    end
    root:CreateDivider()
    root:CreateButton(L.ADDONSLIST_SETS_SAVE, promptSave)
    if next(module.db.sets) then
        local delete = root:CreateButton(L.ADDONSLIST_SETS_DELETE)
        for _, name in ipairs(names) do
            delete:CreateButton(name, deleteSet, name)
        end
    end
end

-- Shows the Sets dropdown while the module and its option are on, made the first time.
local function updateSets()
    local list = addList()
    local want = module.enabled and module.db.showSets and list
    if want and not setsDropdown and WowStyle1DropdownMixin and list.DisableAllButton then
        -- Probe: WowStyle1DropdownTemplate is Mainline's menu dropdown, the one the list's own
        -- character dropdown uses. It fits in the gap between Disable All and Okay.
        setsDropdown = CreateFrame("DropdownButton", nil, list, "WowStyle1DropdownTemplate")
        setsDropdown:SetWidth(130)
        setsDropdown:SetPoint("LEFT", list.DisableAllButton, "RIGHT", 8, 0)
        setsDropdown:SetDefaultText(L.ADDONSLIST_SETS_BUTTON)
        setsDropdown:SetupMenu(setupSetsMenu)
    end
    if setsDropdown then
        setsDropdown:SetShown(want and true or false)
    end
end

local function start()
    local list = addList()
    if not list then
        return
    end
    module:Hook("AddonList_Update", rebuild)
    module:HookScript(list.SearchBox, "OnTextChanged", rebuild)
    module:HookScript(list, "OnShow", rebuild)
    updateSets()
    rebuild()
end

function module:OnEnable()
    ns.AddOns.WhenLoaded(ADDON, start)
end

function module:OnDisable()
    ns.AddOns.Cancel(ADDON, start)
    updateSets()
    -- Blizzard's own update puts its categories back.
    if addList() then
        refreshList()
    end
end

function module:OnOptionChanged(key)
    if not self.enabled then
        return
    end
    if key == "showSets" then
        updateSets()
    else
        rebuild()
    end
end
