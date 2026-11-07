-- Hide Quest Tooltips: takes the quest lines (the quest's name, "- Item 0/8", and who else on it)
-- off unit and object tooltips, by skipping those lines as the game builds the tooltip.
local _, ns = ...

local ipairs = ipairs

local L = ns.L

local module = ns.NewModule("HideQuestTooltips", L.HIDEQUESTTOOLTIPS_DESC, { enabled = false, objects = true })
module.title = L.HIDEQUESTTOOLTIPS_TITLE
module.category = "quests"
module.added = "1.2.0"
module.options = {
    { key = "objects", name = L.HIDEQUESTTOOLTIPS_OBJECTS, description = L.HIDEQUESTTOOLTIPS_OBJECTS_DESC },
}

local registered

function module:OnEnable()
    local Processor, Lines, Kinds = TooltipDataProcessor, Enum and Enum.TooltipDataLineType, Enum and Enum.TooltipDataType
    -- A pre-call can't be removed, so add them once; they do nothing while the module is off.
    if registered or not (Processor and Processor.AddLinePreCall and Lines and Kinds) then
        return
    end
    registered = true
    local function skip(tooltip)
        local info = tooltip.processingInfo
        local kind = info and info.tooltipData and info.tooltipData.type
        return module.enabled and (kind == Kinds.Unit or (kind == Kinds.Object and module.db.objects))
    end
    for _, name in ipairs({ "QuestObjective", "QuestTitle", "QuestPlayer" }) do
        if Lines[name] then
            Processor.AddLinePreCall(Lines[name], skip)
        end
    end
end
