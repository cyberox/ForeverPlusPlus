-- Realm time and the player's own: how far apart the two clocks are, and a realm time (a
-- CalendarTime, or an hour and minute) moved to the player's clock. The calendar and the other
-- places that show a time of day get the realm's (C_Calendar, C_DateAndTime), whatever the clock's
-- Local Time box says. Plain arithmetic on the dates, so no daylight saving guess gets in.
local _, ns = ...

local floor, date = math.floor, date
local C_DateAndTime = C_DateAndTime

local RealmTime = {}
ns.RealmTime = RealmTime

local DAY = 24 * 60 -- minutes
local STEP = 15 -- every time zone is a whole number of quarter hours from UTC

-- Days from 1970-01-01 to a date (Howard Hinnant's days_from_civil), for any year after 0.
local function days(year, month, day)
    if month <= 2 then
        year = year - 1
    end
    local era = floor(year / 400)
    local yoe = year - era * 400
    local mp = (month + 9) % 12
    local doy = floor((153 * mp + 2) / 5) + day - 1
    local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- The date `n` days after 1970-01-01 (civil_from_days), with its weekday, 1 for Sunday as the
-- calendar counts them.
local function civil(n)
    local z = n + 719468
    local era = floor(z / 146097)
    local doe = z - era * 146097
    local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
    local mp = floor((5 * doy + 2) / 153)
    local day = doy - floor((153 * mp + 2) / 5) + 1
    local month = mp < 10 and mp + 3 or mp - 9
    local year = yoe + era * 400 + (month <= 2 and 1 or 0)
    return year, month, day, (n + 4) % 7 + 1 -- 1970-01-01 was a Thursday
end

---Minutes the player's clock is ahead of the realm's (negative when behind), in quarter hours.
---Both clocks only give the minute, read a moment apart, so the raw difference can be a minute off;
---every time zone is a whole number of quarter hours, which rounding to one takes out. Nil when
---the client can't tell the realm's time.
---@return number? minutes
function RealmTime.Offset()
    local realm = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
        and C_DateAndTime.GetCurrentCalendarTime()
    if not (realm and realm.year and realm.hour) then
        return nil
    end
    local here = date("*t")
    local diff = (days(here.year, here.month, here.day) - days(realm.year, realm.month, realm.monthDay))
        * DAY + (here.hour - realm.hour) * 60 + (here.min - realm.minute)
    return floor(diff / STEP + 0.5) * STEP
end

---A realm hour and minute on the player's clock, and how many days that moves it (1 when it's
---tomorrow there, -1 yesterday).
---@param hour number
---@param minute number
---@param offset number minutes, from RealmTime.Offset
---@return number hour
---@return number minute
---@return number days
function RealmTime.Clock(hour, minute, offset)
    local total = hour * 60 + minute + offset
    local shift = floor(total / DAY)
    total = total - shift * DAY
    return floor(total / 60), total % 60, shift
end

---A realm CalendarTime (year, month, monthDay, hour, minute) on the player's clock, as a new
---CalendarTime with its weekday, and how many days that moved it.
---@param t table
---@param offset number minutes, from RealmTime.Offset
---@return table time
---@return number days
function RealmTime.Date(t, offset)
    local hour, minute, shift = RealmTime.Clock(t.hour or 0, t.minute or 0, offset)
    local year, month, day, weekday = civil(days(t.year, t.month, t.monthDay) + shift)
    return { year = year, month = month, monthDay = day, weekday = weekday, hour = hour,
        minute = minute }, shift
end

---Whether a CalendarTime falls on the player's today.
---@param t table
---@return boolean
function RealmTime.IsToday(t)
    local here = date("*t")
    return t.year == here.year and t.month == here.month and t.monthDay == here.day
end
