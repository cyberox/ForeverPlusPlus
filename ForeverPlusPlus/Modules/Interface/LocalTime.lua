-- Local Time: the calendar's times, and the few other times of day the game gives in realm time,
-- shown in the player's own time while the clock's Local Time box is on (timeMgrUseLocalTime).
-- Blizzard formats each from the realm's hour and minute (GameTime_GetFormattedTime), so that box
-- only ever changed the minimap clock.
--
-- Nothing of Blizzard's is replaced: each place is hooked after it draws, and the time it wrote is
-- written again in the player's time. Turned off, or with the box off, the same code writes the
-- realm's time back. Events stay on the realm's day in the month grid, since moving them would
-- mean redrawing Blizzard's grid; a time that falls on another day for the player says so (+1).
-- The create event window still picks realm time (changing what it sends would taint it), with
-- the player's time under it. Read from Blizzard's Forever UI source at build 70862.
local _, ns = ...

local ipairs, format, date, time, type = ipairs, format, date, time, type
local C_Calendar, C_DateAndTime = C_Calendar, C_DateAndTime

local L = ns.L
local RealmTime = ns.RealmTime

local CVAR = "timeMgrUseLocalTime"

local module = ns.NewModule("LocalTime", L.LOCALTIME_DESC, {
    enabled = true, -- does nothing until the player turns the clock's Local Time on
    localTime = false,
})
module.title = L.LOCALTIME_TITLE
module.category = "interface"
module.added = "1.3.0"

module.options = {
    { key = "localTime", name = L.LOCALTIME_CLOCK, description = L.LOCALTIME_CLOCK_DESC, cvar = CVAR },
}

-- How the grid shows a day that moved, always there.
module.notice = {
    text = L.LOCALTIME_NOTICE,
    description = L.LOCALTIME_NOTICE_DESC,
}

-- Blizzard_Calendar's own limits (locals there): event buttons in a day, and how many of them
-- leave room for AM and PM.
local MAX_EVENTS = 4
local MAX_BIG_EVENTS = 2
local NO_TIME = { HOLIDAY = true, RAID_LOCKOUT = true, RAID_RESET = true }

-- Minutes to move realm times by: 0 while the module or the clock's Local Time is off, or when
-- the two clocks agree.
local function offset()
    if not (module.enabled and ns.CVars.IsOn(CVAR)) then
        return 0
    end
    return RealmTime.Offset() or 0
end

-- A realm hour and minute as the calendar writes it, moved by `off`, with +1 or -1 when that's
-- another day.
local function clock(hour, minute, ampm, off)
    local h, m, days = RealmTime.Clock(hour, minute, off)
    local text = GameTime_GetFormattedTime(h, m, ampm)
    if days > 0 then
        return format(L.LOCALTIME_NEXT_DAY, text)
    elseif days < 0 then
        return format(L.LOCALTIME_PREVIOUS_DAY, text)
    end
    return text
end

local function eventTime(event)
    return event.sequenceType == "END" and event.endTime or event.startTime
end

local function fullDate(t)
    return format(FULLDATE, CALENDAR_WEEKDAY_NAMES[t.weekday], CALENDAR_FULLDATE_MONTH_NAMES[t.month],
        t.monthDay, t.year, t.month)
end

-- Tooltip lines Blizzard wrote that are in `map` (its text -> ours), on one side, written again.
-- Events at the same realm time show the same time for the player, so the text alone says which.
local function rewriteTooltip(side, map)
    local tooltip = GameTooltip
    local changed = false
    for i = 1, tooltip:NumLines() do
        local line = _G["GameTooltipText" .. side .. i]
        local text = line and line:IsShown() and line:GetText()
        local ours = text and map[text]
        if ours and ours ~= text then
            line:SetText(ours)
            changed = true
        end
    end
    if changed then
        tooltip:Show() -- to fit the new widths
    end
end

-- The calendar ------------------------------------------------------------------------------

-- One day of the month grid: the time beside each event that has one.
local function drawDay(index, day, monthOffset, off)
    local dayButton = _G["CalendarDayButton" .. index]
    if not (dayButton and day and monthOffset) then
        return
    end
    local name = dayButton:GetName()
    local ampm = (dayButton.numViewableEvents or 0) <= MAX_BIG_EVENTS
    for i = 1, MAX_EVENTS do
        local button = _G[name .. "EventButton" .. i]
        local eventIndex = button and button:IsShown() and button.eventIndex
        local event = eventIndex and C_Calendar.GetDayEvent(monthOffset, day, eventIndex)
        local text = event and _G[button:GetName() .. "Text2"]
        local t = text and not NO_TIME[event.calendarType] and eventTime(event)
        if t then
            text:SetText(clock(t.hour, t.minute, ampm, off))
        end
    end
end

local function drawGrid(off)
    local i = 1
    local dayButton = _G.CalendarDayButton1
    while dayButton do
        drawDay(i, dayButton.day, dayButton.monthOffset, off)
        i = i + 1
        dayButton = _G["CalendarDayButton" .. i]
    end
end

-- The list a day with too many events opens.
local function drawPickerButton(button, off)
    local dayButton = CalendarEventPickerFrame and CalendarEventPickerFrame.dayButton
    local event = dayButton and dayButton.day and button.eventIndex
        and C_Calendar.GetDayEvent(dayButton.monthOffset, dayButton.day, button.eventIndex)
    local t = event and button.Time and not NO_TIME[event.calendarType] and eventTime(event)
    if t then
        button.Time:SetText(clock(t.hour, t.minute, true, off))
    end
end

local function drawPicker(off)
    local frame = CalendarEventPickerFrame
    local box = frame and frame:IsShown() and frame.ScrollBox
    if box and box.ForEachFrame then
        box:ForEachFrame(function(button)
            drawPickerButton(button, off)
        end)
    end
end

-- A player's event: its date and time.
local function drawViewEvent(off)
    if not (CalendarViewEventFrame and CalendarViewEventFrame:IsShown()) then
        return
    end
    local info = C_Calendar.GetEventInfo()
    local t = info and info.title and info.time
    if not (t and t.year) then
        return
    end
    local here = RealmTime.Date(t, off)
    CalendarViewEventDateLabel:SetText(fullDate(here))
    CalendarViewEventTimeLabel:SetText(GameTime_GetFormattedTime(here.hour, here.minute, true))
end

-- A holiday: when it begins and ends.
local function drawHoliday(off)
    local frame = CalendarViewHolidayFrame
    if not (frame and frame:IsShown() and frame.ScrollingFont) then
        return
    end
    local index = C_Calendar.GetEventIndex()
    local info = index and C_Calendar.GetHolidayInfo(index.offsetMonths, index.monthDay, index.eventIndex)
    if not (info and info.startTime and info.endTime) then
        return
    end
    local from, to = RealmTime.Date(info.startTime, off), RealmTime.Date(info.endTime, off)
    frame.ScrollingFont:SetText(format(CALENDAR_HOLIDAYFRAME_BEGINSENDS, info.description,
        FormatShortDate(from.monthDay, from.month), GameTime_GetFormattedTime(from.hour, from.minute, true),
        FormatShortDate(to.monthDay, to.month), GameTime_GetFormattedTime(to.hour, to.minute, true)))
end

-- A raid lockout or reset: the time it happens.
local function drawRaid(off)
    local frame = CalendarViewRaidFrame
    if not (frame and frame:IsShown() and frame.ScrollingFont) then
        return
    end
    local index = C_Calendar.GetEventIndex()
    local info = index and C_Calendar.GetRaidInfo(index.offsetMonths, index.monthDay, index.eventIndex)
    local text = info and (info.calendarType == "RAID_LOCKOUT" and CALENDAR_RAID_LOCKOUT_DESCRIPTION
        or info.calendarType == "RAID_RESET" and CALENDAR_RAID_RESET_DESCRIPTION)
    if not (text and info.time) then
        return
    end
    local name = GetDungeonNameWithDifficulty(info.name, info.difficultyName)
    frame.ScrollingFont:SetText(format(text, name, clock(info.time.hour, info.time.minute, true, off)))
end

-- Ours, under the create event window's date: the time picked, in the player's time.
local yourTime

local function drawCreate(off)
    local frame = CalendarCreateEventFrame
    local hour, minute = frame and frame.selectedHour, frame and frame.selectedMinute
    if off == 0 or not (hour and minute and frame:IsShown() and CalendarCreateEventDateLabel) then
        if yourTime then
            yourTime:Hide()
        end
        return
    end
    if not CalendarFrame.militaryTime then
        hour = GameTime_ComputeMilitaryTime(hour, frame.selectedAM)
    end
    if not yourTime then
        yourTime = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        yourTime:SetPoint("TOPLEFT", CalendarCreateEventDateLabel, "BOTTOMLEFT", 0, -2)
    end
    yourTime:SetText(format(L.LOCALTIME_YOUR_TIME, clock(hour, minute, true, off)))
    yourTime:Show()
end

local function drawWindows(off)
    drawViewEvent(off)
    drawHoliday(off)
    drawRaid(off)
    drawCreate(off)
end

local function drawCalendar(off)
    if CalendarFrame and CalendarFrame:IsShown() then
        drawGrid(off)
        drawPicker(off)
        drawWindows(off)
    end
end

-- Hooks: each draws only while there's something to move. The view windows keep their update
-- function from load, before these hooks, so their redraws are caught where they're shown too.
local function afterDayEvents(index, day, monthOffset)
    local off = offset()
    if off ~= 0 then
        drawDay(index, day, monthOffset, off)
    end
end

local function afterPickerButton(button)
    local off = offset()
    if off ~= 0 then
        drawPickerButton(button, off)
    end
end

local function afterWindows()
    local off = offset()
    if off ~= 0 then
        drawWindows(off)
    end
end

-- The day's tooltip: each event's time at the right.
local function afterDayEnter(dayButton)
    local off = offset()
    if off == 0 or GameTooltip:GetOwner() ~= dayButton or not dayButton.day then
        return
    end
    local map = {}
    for i = 1, C_Calendar.GetNumDayEvents(dayButton.monthOffset, dayButton.day) do
        local event = C_Calendar.GetDayEvent(dayButton.monthOffset, dayButton.day, i)
        local t = event and event.sequenceType ~= "ONGOING" and eventTime(event)
        if t then
            map[GameTime_GetFormattedTime(t.hour, t.minute, true)] = clock(t.hour, t.minute, true, off)
        end
    end
    rewriteTooltip("Right", map)
end

-- An invite's tooltip: the date and time they answered.
local function afterInviteEnter(button)
    local off = offset()
    if off == 0 or GameTooltip:GetOwner() ~= button or not button.inviteIndex then
        return
    end
    local t = C_Calendar.EventGetInviteResponseTime(button.inviteIndex)
    if not (t and t.weekday ~= 0 and t.year) then
        return
    end
    local here = RealmTime.Date(t, off)
    rewriteTooltip("Left", {
        [fullDate(t)] = fullDate(here),
        [GameTime_GetFormattedTime(t.hour, t.minute, true)] = GameTime_GetFormattedTime(here.hour, here.minute, true),
    })
end

local function hookCalendar()
    module:Hook("CalendarFrame_UpdateDayEvents", afterDayEvents)
    module:Hook("CalendarEventPickerFrame_InitButton", afterPickerButton)
    module:Hook("CalendarDayButton_OnEnter", afterDayEnter)
    module:Hook("CalendarEventInviteListButton_OnEnter", afterInviteEnter)
    for _, name in ipairs({ "CalendarFrame_ShowEventFrame", "CalendarFrame_UpdateTimeFormat",
        "CalendarViewEventFrame_Update", "CalendarViewHolidayFrame_Update", "CalendarViewRaidFrame_Update",
        "CalendarCreateEventFrame_Update", "CalendarCreateEvent_SetEventTime",
        "CalendarCreateEvent_UpdateEventTime", "CalendarCreateEvent_UpdateTimeFormat" }) do
        module:Hook(name, afterWindows)
    end
    for _, frame in ipairs({ CalendarViewEventFrame, CalendarViewHolidayFrame, CalendarViewRaidFrame,
        CalendarCreateEventFrame }) do
        module:HookScript(frame, "OnShow", afterWindows)
    end
    drawCalendar(offset())
end

-- Communities --------------------------------------------------------------------------------

-- The guild's calendar button: the next few events, "Today 9:00 PM" or "Friday 9:00 PM".
local function afterCommunitiesCalendar(button)
    local off = offset()
    if off == 0 or GameTooltip:GetOwner() ~= button or type(button.GetCommunitiesFrame) ~= "function" then
        return
    end
    local club = button:GetCommunitiesFrame():GetSelectedClubInfo()
    local now = C_DateAndTime.GetCurrentCalendarTime()
    if not (club and now) then
        return
    end
    local map = {}
    local events = C_Calendar.GetClubCalendarEvents(club.clubId, now, C_DateAndTime.AdjustTimeByDays(now, 4))
    for _, event in ipairs(events or {}) do
        local t = event.startTime
        if t and t.year then
            local here = RealmTime.Date(t, off)
            local realmDay = now.weekday == t.weekday and COMMUNITIES_CALENDAR_TODAY or CALENDAR_WEEKDAY_NAMES[t.weekday]
            local day = RealmTime.IsToday(here) and COMMUNITIES_CALENDAR_TODAY or CALENDAR_WEEKDAY_NAMES[here.weekday]
            map[format(COMMUNITIES_CALENDAR_EVENT_FORMAT, realmDay, GameTime_GetFormattedTime(t.hour, t.minute, true))]
                = format(COMMUNITIES_CALENDAR_EVENT_FORMAT, day, GameTime_GetFormattedTime(here.hour, here.minute, true))
        end
    end
    rewriteTooltip("Left", map)
end

-- A guild event in Guild News, written as Blizzard does: today, a weekday this week, or a date.
local SIX_DAYS = 6 * 24 * 60 * 60

local function afterGuildNewsEvent(button, eventID)
    local off = offset()
    local info = off ~= 0 and button.text and C_Calendar.GetGuildEventInfo(eventID)
    if not (info and info.year) then
        return
    end
    local here = RealmTime.Date({ year = info.year, month = info.month, monthDay = info.monthDay,
        hour = info.hour, minute = info.minute }, off)
    local day
    if RealmTime.IsToday(here) then
        day = NORMAL_FONT_COLOR_CODE .. GUILD_EVENT_TODAY .. FONT_COLOR_CODE_CLOSE
    elseif time({ year = here.year, month = here.month, day = here.monthDay }) - time() < SIX_DAYS then
        day = CALENDAR_WEEKDAY_NAMES[here.weekday]
    else
        day = format(GUILD_NEWS_DATE, CALENDAR_WEEKDAY_NAMES[here.weekday], here.monthDay, here.month)
    end
    button.text:SetFormattedText(GUILD_EVENT_FORMAT, day, GameTime_GetFormattedTime(here.hour, here.minute, true),
        info.title)
end

local function hookCommunities()
    local frame = CommunitiesFrame
    module:HookScript(frame and frame.CommunitiesCalendarButton, "OnEnter", afterCommunitiesCalendar)
    module:Hook("CommunitiesGuildNewsButton_SetEvent", afterGuildNewsEvent)
end

-- Mail ---------------------------------------------------------------------------------------

-- A sale's invoice: when the money arrives. Taken to be realm time like the calendar's, since
-- Blizzard formats it the same way. Unverified in game.
local function drawMail(off)
    local line = OpenMailInvoiceMoneyDelay
    if not (line and line:IsShown() and InboxFrame and InboxFrame.openMailID) then
        return
    end
    local kind, _, _, _, _, _, _, _, hour, minute = GetInboxInvoiceInfo(InboxFrame.openMailID)
    if kind == "seller_temp_invoice" and hour and minute then
        line:SetFormattedText(AUCTION_INVOICE_FUNDS_DELAY, clock(hour, minute, true, off))
    end
end

local function afterMail()
    local off = offset()
    if off ~= 0 then
        drawMail(off)
    end
end

-- On and off ---------------------------------------------------------------------------------

-- Everything shown now, drawn again: in the player's time, or the realm's after turning off.
local function redraw()
    local off = offset()
    drawCalendar(off)
    if OpenMailFrame and OpenMailFrame:IsShown() then
        drawMail(off)
    end
end

local function onCVarUpdate(_, name)
    if type(name) == "string" and name:lower() == "timemgruselocaltime" then
        redraw()
    end
end

function module:OnEnable()
    ns.AddOns.WhenLoaded("Blizzard_Calendar", hookCalendar)
    ns.AddOns.WhenLoaded("Blizzard_Communities", hookCommunities)
    if OpenMailFrame then
        self:Hook(OpenMailFrame, "Update", afterMail)
    end
    self:On("CVAR_UPDATE", onCVarUpdate)
    redraw()
end

function module:OnDisable()
    ns.AddOns.Cancel("Blizzard_Calendar", hookCalendar)
    ns.AddOns.Cancel("Blizzard_Communities", hookCommunities)
    redraw()
end

function module:OnOptionChanged()
    redraw()
end
