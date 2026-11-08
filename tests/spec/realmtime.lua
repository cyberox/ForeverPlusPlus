-- RealmTime: the offset between the realm's clock and the player's, and realm times moved to it.
local T = ...
local eq, same = T.eq, T.same

local realm = { year = 2026, month = 11, monthDay = 7, weekday = 7, hour = 20, minute = 0 }
local here = { year = 2026, month = 11, day = 7, hour = 23, min = 1 }
T.env.C_DateAndTime = {
    GetCurrentCalendarTime = function()
        return realm
    end,
}
T.env.date = function()
    return here
end
local ns = {}
T.load("Lib/RealmTime", ns)
local R = ns.RealmTime

eq(R.Offset(), 180, "realmtime: a minute apart rounds to the zone")
here = { year = 2026, month = 11, day = 8, hour = 1, min = 59 }
eq(R.Offset(), 360, "realmtime: ahead across midnight")
here = { year = 2026, month = 11, day = 7, hour = 14, min = 30 }
eq(R.Offset(), -330, "realmtime: behind by a half hour zone")
here = { year = 2027, month = 1, day = 1, hour = 0, min = 45 }
realm = { year = 2026, month = 12, monthDay = 31, weekday = 5, hour = 19, minute = 0 }
eq(R.Offset(), 345, "realmtime: across the year, a quarter hour zone")
here = { year = 2026, month = 11, day = 7, hour = 20, min = 0 }
realm = { year = 2026, month = 11, monthDay = 7, weekday = 7, hour = 20, minute = 0 }
eq(R.Offset(), 0, "realmtime: the same clock")

T.env.C_DateAndTime = {}
T.load("Lib/RealmTime", ns)
eq(ns.RealmTime.Offset(), nil, "realmtime: no realm clock")

same({ R.Clock(21, 30, 180) }, { 0, 30, 1 }, "realmtime: clock into tomorrow")
same({ R.Clock(1, 15, -120) }, { 23, 15, -1 }, "realmtime: clock into yesterday")
same({ R.Clock(9, 5, 0) }, { 9, 5, 0 }, "realmtime: clock unmoved")

same({ R.Date({ year = 2026, month = 12, monthDay = 31, hour = 22, minute = 0 }, 180) },
    { { year = 2027, month = 1, monthDay = 1, weekday = 6, hour = 1, minute = 0 }, 1 },
    "realmtime: date into the new year, a Friday")
same({ R.Date({ year = 2028, month = 3, monthDay = 1, hour = 2, minute = 0 }, -180) },
    { { year = 2028, month = 2, monthDay = 29, weekday = 3, hour = 23, minute = 0 }, -1 },
    "realmtime: date back to a leap day, a Tuesday")
same({ R.Date({ year = 2026, month = 11, monthDay = 7, hour = 12, minute = 0 }, 0) },
    { { year = 2026, month = 11, monthDay = 7, weekday = 7, hour = 12, minute = 0 }, 0 },
    "realmtime: date unmoved, a Saturday")

here = { year = 2026, month = 11, day = 8, hour = 1, min = 0 }
eq(R.IsToday({ year = 2026, month = 11, monthDay = 8 }), true, "realmtime: today")
eq(R.IsToday({ year = 2026, month = 11, monthDay = 7 }), false, "realmtime: not today")
