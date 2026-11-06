-- Small frame helpers modules share: probing for Blizzard art and templates, the box tooltips are
-- drawn in, Escape closing our windows, red text in the error frame, running something once
-- after a burst of calls, a timer that waits for one run at a time, and whether the player is in
-- combat or moving.
local _, ns = ...

local select, ipairs, tinsert, CreateFrame, C_Timer = select, ipairs, table.insert, CreateFrame, C_Timer
local pcall, UIParent, format = pcall, UIParent, string.format
local setmetatable, type, InCombatLockdown = setmetatable, type, InCombatLockdown

local Frames = {}
ns.Frames = Frames

---Whether this client has an atlas. Probe: atlas names change between builds.
---@param name string
---@return boolean
function Frames.HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and true or false
end

---The first atlas in the list this client has, or nil.
---@param ... string atlas names, best first
---@return string?
function Frames.FirstAtlas(...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if Frames.HasAtlas(name) then
            return name
        end
    end
end

---Whether this client has a Blizzard template (Mainline's).
---@param name string
---@return boolean
function Frames.HasTemplate(name)
    return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) and true
        or false
end

---A frame in one of Blizzard's box templates (a tooltip's, a dialog's border), or the older
---tooltip backdrop where this client doesn't have the template.
---@param parent table
---@param template string
---@return table
function Frames.TemplateBox(parent, template)
    local hasTemplate = Frames.HasTemplate(template)
    local box = CreateFrame("Frame", nil, parent, hasTemplate and template or "BackdropTemplate")
    if not hasTemplate and box.SetBackdrop and BACKDROP_TOOLTIP_16_16_5555 then
        box:SetBackdrop(BACKDROP_TOOLTIP_16_16_5555)
        box:SetBackdropColor(0, 0, 0, 0.8)
    end
    return box
end

---A frame in the box Blizzard draws tooltips in, or the older tooltip backdrop where this client
---doesn't have the template.
---@param parent table
---@return table
function Frames.TooltipBox(parent)
    return Frames.TemplateBox(parent, "TooltipBackdropTemplate")
end

---Lets Escape close one of our windows, the way Blizzard's own windows close: its name goes in
---UISpecialFrames, which the game menu key hides first. Blizzard reads the list through
---securecall, so our entry taints nothing, and it skips hidden frames, so Escape still opens the
---game menu while the window is closed. The frame needs a global name.
---@param frame table a named frame
function Frames.CloseOnEscape(frame)
    local name = frame:GetName()
    if not (name and UISpecialFrames) then
        return
    end
    for _, special in ipairs(UISpecialFrames) do
        if special == name then
            return
        end
    end
    tinsert(UISpecialFrames, name)
end

---One of our windows in Blizzard's frame with a portrait (the addon's icon), a sunken box, and a
---strip for buttons at the bottom, as the game's own lists use. Probe: an older template if this
---client doesn't have it. Named, so Escape can close it (Frames.CloseOnEscape).
---@param name string the window's global name
---@param title string
---@return table frame
function Frames.PortraitWindow(name, title)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "ButtonFrameTemplate")
    if not (ok and f) then
        f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    end
    if f.SetPortraitToAsset then
        pcall(f.SetPortraitToAsset, f, ns.icon)
        -- Blizzard's portrait is 62 pixels square. The icon's emblem is about 52 of its 64 pixels
        -- wide, centered 32 across and 30 down; show it 54 pixels wide, so the icon's dark square
        -- border falls outside the circle. Centered at 30.5 across and 29 down (from the round
        -- mask's insets), it sat about a pixel high and a quarter left of the ring in game
        -- (2026-10-15, measured on a screenshot), so it's centered at 30.75 across and 30 down.
        if f.SetPortraitTexCoord then
            local perPixel = 52 / 64 / 54
            local left, top = 32 / 64 - 30.75 * perPixel, 30.25 / 64 - 30 * perPixel
            pcall(f.SetPortraitTexCoord, f, left, left + 62 * perPixel, top, top + 62 * perPixel)
        end
    end
    -- The addon's name in gray before the title, so the window says whose it is.
    local gray = ns.Colors.GRAY
    title = format(ns.L.FRAMES_WINDOW_TITLE, ns.Colors.Code(gray[1], gray[2], gray[3]) .. ns.title
        .. "|r", title)
    if f.SetTitle then
        f:SetTitle(title)
    elseif f.TitleText then
        f.TitleText:SetText(title)
    end
    return f
end

---Blizzard's sunken box behind a list or text, or a plain frame where the template is missing.
---@param parent table
---@return table
function Frames.Inset(parent)
    local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if ok and inset then
        return inset
    end
    return CreateFrame("Frame", nil, parent)
end

---A list row's highlight or selection: Blizzard's Settings list atlas where it exists, a plain
---tint where not.
---@param row table
---@param layer string
---@param atlas string such as "Options_List_Active" or "Options_List_Hover"
---@param r number
---@param g number
---@param b number
---@param a number
---@return table texture
function Frames.RowTexture(row, layer, atlas, r, g, b, a)
    local texture = row:CreateTexture(nil, layer)
    texture:SetAllPoints()
    if Frames.HasAtlas(atlas) then
        texture:SetAtlas(atlas)
    else
        texture:SetColorTexture(r, g, b, a)
    end
    return texture
end

---A frame's anchor points, each { point, relativeTo, relativePoint, x, y }, to put back later
---with Frames.SetPoints (such as a Blizzard frame's own place before a module moves it).
---@param frame table
---@return table[] points empty when it has none
function Frames.GetPoints(frame)
    local points = {}
    for i = 1, frame:GetNumPoints() do
        points[i] = { frame:GetPoint(i) }
    end
    return points
end

---Puts back the anchor points Frames.GetPoints read.
---@param frame table
---@param points table[]
function Frames.SetPoints(frame, points)
    frame:ClearAllPoints()
    for _, p in ipairs(points) do
        frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
end

---Blizzard's red panel button, 22 high. `onClick` is called with no arguments; a button that
---needs `self` sets its own OnClick instead.
---@param parent table
---@param text string? set later when it changes
---@param width number
---@param onClick? function
---@return table button
function Frames.Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    if text then
        button:SetText(text)
    end
    if onClick then
        button:SetScript("OnClick", function() onClick() end)
    end
    return button
end

---Red text in the middle of the screen, the way the game says "Not enough rage".
---@param text string?
function Frames.ErrorMessage(text)
    if not (text and UIErrorsFrame) then
        return
    end
    if UIErrorsFrame.AddExternalErrorMessage then
        UIErrorsFrame:AddExternalErrorMessage(text)
    else
        UIErrorsFrame:AddMessage(text, 1, 0.1, 0.1)
    end
end

-- Puts a timer in `module.timers`, which Core cancels when the module (or part) turns off.
local function own(module, timer)
    if module then
        local timers = module.timers
        if not timers then
            timers = {}
            module.timers = timers
        end
        timers[#timers + 1] = timer
    end
end

---Runs `fn` once, `delay` seconds after the first call (the next frame by default), however often
---it's called before then. For events that come in bursts. Give the module (or part) whose work it
---is: the Profiler page charges the run to it, and a queued run is dropped when it turns off (and
---doesn't happen while it's off). Make one per module at file load, not in OnEnable.
---@param fn function
---@param delay? number
---@param module? table
---@return function queue call to run `fn` soon
---@return function cancel drops a queued run
function Frames.Coalesce(fn, delay, module)
    if module then
        fn = ns.Profiler.Wrap(module, fn, ns.Profiler.SOURCE_DELAYED)
    end
    local timer
    local function run()
        timer = nil
        if module and not module.enabled then
            return
        end
        fn()
    end
    local function queue()
        if not timer then
            timer = C_Timer.NewTimer(delay or 0, run)
        end
    end
    local function cancel()
        if timer then
            timer:Cancel()
            timer = nil
        end
    end
    own(module, { Cancel = cancel })
    return queue, cancel
end

---An OnUpdate script that calls `fn(frame)` at most every `interval` seconds: look a few times a
---second instead of every frame.
---@param interval number seconds
---@param fn fun(frame: table)
---@return fun(frame: table, delta: number)
function Frames.Throttled(interval, fn)
    local elapsed = 0
    return function(frame, delta)
        elapsed = elapsed + delta
        if elapsed >= interval then
            elapsed = 0
            fn(frame)
        end
    end
end

---A hidden frame that calls `fn()` every `interval` seconds while it's shown, charged to `module`
---on the Profiler page. Show it to start watching and hide it to stop.
---@param module table
---@param interval number seconds
---@param fn function
---@return table frame
function Frames.Watcher(module, interval, fn)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    frame:SetScript("OnUpdate", Frames.Throttled(interval, ns.Profiler.Wrap(module, fn)))
    return frame
end

---What the player is busy with, for a window that fades while they play: "combat" in combat,
---"moving" while they move (or fall, or fly), or nil when they stand still. A speed the game
---hides counts as standing still.
---@return string?
function Frames.PlayerActivity()
    if InCombatLockdown() then
        return "combat"
    end
    local speed = GetUnitSpeed and GetUnitSpeed("player")
    if ns.IsNumber(speed) and speed > 0 then
        return "moving"
    end
    if IsFalling and ns.IsTrue(IsFalling()) then
        return "moving"
    end
end

local Timer = {}
Timer.__index = Timer

---Runs `fn` in `seconds`, in place of the run waiting, if any.
---@param seconds number
---@param fn function
function Timer:Start(seconds, fn)
    self:Cancel()
    local handle
    local owner = self.module
    handle = C_Timer.NewTimer(seconds, function()
        if self.handle == handle then
            self.handle = nil
        end
        if owner and not owner.enabled then
            return -- turned off before Core could cancel it
        end
        local profiler = ns.Profiler
        if owner and profiler.recording then
            profiler.CallFrom(owner, profiler.SOURCE_TIMER, fn)
        else
            fn()
        end
    end)
    self.handle = handle
end

---Drops the run waiting, if any.
function Timer:Cancel()
    if self.handle then
        self.handle:Cancel()
        self.handle = nil
    end
end

---Whether a run is waiting.
---@return boolean
function Timer:IsPending()
    return self.handle ~= nil
end

---A timer that waits for one run at a time: `Start(seconds, fn)` replaces the run waiting,
---`Cancel()` drops it, and `IsPending()` says whether one is waiting. `fn` can start it again.
---Give the module (or part) whose work it is: the Profiler page charges it, Core cancels it when
---that turns off, and `fn` doesn't run while it's off. Without one, `Cancel` it in OnDisable.
---Make one per module at file load, not in OnEnable.
---@param module? table
---@return table timer
function Frames.Timer(module)
    local timer = setmetatable({ module = module }, Timer)
    own(module, timer)
    return timer
end
