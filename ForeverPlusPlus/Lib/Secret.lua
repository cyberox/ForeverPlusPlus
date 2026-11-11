-- Helpers for secret values: Forever inherits Midnight's rules, so unit data can come back secret
-- (mostly in combat and instances) and must not be tested or compared in Lua.
local _, ns = ...

local type, pcall = type, pcall
local issecretvalue, C_CurveUtil, UnitHealthPercent, Enum = issecretvalue, C_CurveUtil, UnitHealthPercent, Enum
local C_Secrets, C_UnitAuras = C_Secrets, C_UnitAuras

---Whether a value can be tested, compared, or used in Lua. Secret values can't; treat them as
---unknown and pass them only to widget setters.
---@secret-guard value accessible
---@param value any
---@return boolean
function ns.IsReadable(value)
    return not (issecretvalue and issecretvalue(value))
end

---Whether a value is a string Lua can read: not secret, and with `nonEmpty`, not "" either. The
---check text from the game (names, tooltip lines, chat) needs before it's matched or compared.
---@secret-guard value accessible
---@param value any
---@param nonEmpty? boolean
---@return boolean
function ns.IsText(value, nonEmpty)
    if issecretvalue and issecretvalue(value) or type(value) ~= "string" then
        return false
    end
    return not nonEmpty or value ~= ""
end

---Whether a value is a readable number: false for a secret or anything else.
---@secret-guard value accessible
---@param value any
---@return boolean
function ns.IsNumber(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
end

---Whether a flag from the game is known to be true: false when it's false, nil, or secret. For a
---check that should do nothing unless it's sure.
---@param value any
---@return boolean
function ns.IsTrue(value)
    return not (issecretvalue and issecretvalue(value)) and not not value
end

---Whether a flag from the game may be true: true when it's true or secret. For a check that
---should hold back unless it's sure the flag is off.
---@param value any
---@return boolean
function ns.IsTrueOrSecret(value)
    return issecretvalue and issecretvalue(value) or not not value
end

---Whether auras can be read now. While the client makes them secret (in combat, mostly),
---reading one from addon code throws instead of giving back a secret value, so check this first.
---@return boolean
function ns.AurasReadable()
    local secret = C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
    return not ns.IsTrueOrSecret(secret)
end

---Calls `fn(aura)` for each of the unit's auras that `filter` ("HELPFUL") picks, in order. A read
---that throws ends the scan. Check ns.AurasReadable first, and each field with ns.IsReadable, as
---a field can still be secret. False when this client can't list auras.
---@param unit string
---@param filter string
---@param fn fun(aura: table)
---@return boolean
function ns.EachAura(unit, filter, fn)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then
        return false
    end
    for i = 1, 40 do
        local ok, aura = pcall(get, unit, i, filter)
        if not (ok and aura) then
            break
        end
        fn(aura)
    end
    return true
end

---A curve for `UnitHealthPercent(unit, true, curve)` that gives `hurt` below full health and
---`full` at full health. Use the result as an alpha (or other widget value): the client does the
---math, so it works while health is secret. Nil on a client without curves.
---@param hurt number
---@param full number
---@return table?
function ns.HealthStepCurve(hurt, full)
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and UnitHealthPercent) then
        return nil
    end
    local curve = C_CurveUtil.CreateCurve()
    if Enum.LuaCurveType and Enum.LuaCurveType.Step and curve.SetType then
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, hurt)
        curve:AddPoint(1, full)
    else
        -- A steep ramp just below full, for clients without step curves.
        curve:AddPoint(0, hurt)
        curve:AddPoint(0.99, hurt)
        curve:AddPoint(1, full)
    end
    return curve
end
