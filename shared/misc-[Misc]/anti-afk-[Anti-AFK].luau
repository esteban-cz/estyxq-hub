-- estyxq Hub / universal Misc section and Anti-AFK controller
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local environment = (type(getgenv) == "function" and getgenv()) or shared
local INSTANCE_KEY = "estyxq-hub.AntiAFK"
local AntiAFK = { Version = "1.0.0" }
local Controller = {}
Controller.__index = Controller
local DEFAULTS = { Enabled = false, IdleThreshold = 300, PulseInterval = 60 }

function AntiAFK.GetDefaults()
    return table.clone(DEFAULTS)
end

local function disconnectAll(connections)
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
end

function Controller:_release()
    local cameraFrame = self._heldCamera
    if not cameraFrame then return true end
    local released, message = pcall(function() VirtualUser:Button2Up(Vector2.new(0, 0), cameraFrame) end)
    if released then self._heldCamera = nil end
    return released, message
end

function Controller:_fail(message)
    self:SetEnabled(false)
    if self._onError then task.defer(self._onError, tostring(message))
    else warn("[estyxq Anti-AFK] " .. tostring(message)) end
end

function Controller:Pulse()
    assert(not self.Destroyed, "This Anti-AFK controller has been destroyed.")
    if not self.Enabled or self._heldCamera then return false end
    local camera = workspace.CurrentCamera
    if not camera then return false end
    self._heldCamera = camera.CFrame
    self._releaseAt = os.clock() + 0.1
    local ok, message = pcall(function() VirtualUser:Button2Down(Vector2.new(0, 0), self._heldCamera) end)
    if not ok then self:_fail(message); return false end
    self._lastPulse = os.clock()
    self._releaseAt = self._lastPulse + 0.1
    self.PulseCount += 1
    return true
end

function Controller:_checkIdle()
    local now = os.clock()
    if not self._heldCamera and now - self._lastInput >= self.Settings.IdleThreshold
        and now - self._lastPulse >= self.Settings.PulseInterval then
        self:Pulse()
    end
end

function Controller:SetEnabled(enabled)
    assert(not self.Destroyed, "This Anti-AFK controller has been destroyed.")
    assert(type(enabled) == "boolean", "Enabled must be a boolean.")
    if enabled == self.Enabled then
        if not enabled then self:_release() end
        return
    end
    if enabled then
        local checked, supported = pcall(function()
            return type(VirtualUser.Button2Down) == "function" and type(VirtualUser.Button2Up) == "function"
        end)
        assert(checked and supported, "This environment does not provide VirtualUser keepalive input.")
    end
    self.Enabled, self.Settings.Enabled = enabled, enabled
    if not enabled then
        disconnectAll(self._connections)
        local released, message = self:_release()
        if not released then warn("[estyxq Anti-AFK] Could not release simulated input: " .. tostring(message)) end
        return
    end
    self._lastInput, self._lastPulse, self._accumulator = os.clock(), os.clock(), 0
    local started, message = pcall(function()
        local function activity()
            if not self._heldCamera then self._lastInput = os.clock() end
        end
        table.insert(self._connections, UserInputService.InputBegan:Connect(activity))
        table.insert(self._connections, UserInputService.InputChanged:Connect(activity))
        table.insert(self._connections, LocalPlayer.Idled:Connect(function() self:_checkIdle() end))
        table.insert(self._connections, RunService.Heartbeat:Connect(function(deltaTime)
            if self._heldCamera and os.clock() >= self._releaseAt then
                local released, releaseError = self:_release()
                if not released then self:_fail(releaseError); return end
            end
            self._accumulator += deltaTime
            if self._accumulator >= 1 then
                self._accumulator %= 1
                self:_checkIdle()
            end
        end))
    end)
    if not started then self:SetEnabled(false); error(message, 0) end
end

function Controller:UpdateSettings(patch)
    assert(not self.Destroyed, "This Anti-AFK controller has been destroyed.")
    local settings = table.clone(self.Settings)
    for key, value in pairs(patch) do
        assert(DEFAULTS[key] ~= nil, "Unknown Anti-AFK setting: " .. tostring(key))
        if key == "Enabled" then
            assert(type(value) == "boolean", "Enabled must be a boolean.")
        else
            assert(type(value) == "number" and value == value and math.abs(value) < math.huge, key .. " must be finite.")
            value = math.round(math.clamp(value, key == "IdleThreshold" and 60 or 15, key == "IdleThreshold" and 900 or 300))
        end
        settings[key] = value
    end
    local enabled = settings.Enabled
    settings.Enabled = self.Enabled
    self.Settings = settings
    self:SetEnabled(enabled)
end

function Controller:GetSettings() return table.clone(self.Settings) end

function Controller:GetStatus()
    return { Enabled = self.Enabled, IdleSeconds = math.floor(os.clock() - self._lastInput), Pulses = self.PulseCount }
end

function Controller:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false)
    self.Destroyed = true
    self._onError = nil
    if environment[INSTANCE_KEY] == self then environment[INSTANCE_KEY] = nil end
end

function AntiAFK.new(settings, onError)
    assert(LocalPlayer, "Anti-AFK must run on the client.")
    local previous = environment[INSTANCE_KEY]
    if previous then previous:Destroy() end
    local self = setmetatable({
        Settings = AntiAFK.GetDefaults(), Enabled = false, Destroyed = false, PulseCount = 0,
        _connections = {}, _lastInput = os.clock(), _lastPulse = os.clock(), _accumulator = 0, _onError = onError,
    }, Controller)
    local configured, message = pcall(self.UpdateSettings, self, settings or {})
    if not configured then self:Destroy(); error(message, 0) end
    environment[INSTANCE_KEY] = self
    return self
end



AntiAFK.Icon, AntiAFK.Side = "clock", "Full"
function AntiAFK.Mount(context)
    local state, controls = context.State, context.Controls
    for key, value in pairs(AntiAFK.GetDefaults()) do state[key] = value end
    local status = context.Section:AddParagraph({Title="Anti-AFK is off", Content="Only sends keepalive input after you have been idle."})
    local function refresh()
        status:Set(state.Enabled and "Anti-AFK is on" or "Anti-AFK is off", "Idle threshold: " .. state.IdleThreshold .. "s / Keepalive interval: " .. state.PulseInterval .. "s")
    end
    local controller = AntiAFK.new(state, function(message)
        if not context.IsActive() then return end
        state.Enabled = false
        if controls.Enabled then controls.Enabled:Set(false) end
        context.Notify("Anti-AFK stopped", tostring(message), "Error")
        refresh()
    end)
    context.AddCleanup(function() state.Enabled = false; controller:Destroy() end)
    controls.Enabled = context.Section:AddToggle({Title="Enable Anti-AFK", Style="Switch", Default=state.Enabled,
        Callback=function(value)
            local ok, message = pcall(controller.SetEnabled, controller, value)
            state.Enabled = controller.Enabled
            if not ok then
                if controls.Enabled then controls.Enabled:Set(false) end
                context.Notify("Anti-AFK unavailable", tostring(message), "Error")
            end
            refresh()
        end})
    for _, option in ipairs({
        {Key="IdleThreshold", Title="Idle threshold", Min=60, Max=900, Increment=30},
        {Key="PulseInterval", Title="Keepalive interval", Min=15, Max=300, Increment=15},
    }) do
        controls[option.Key] = context.Section:AddSlider({Title=option.Title, Min=option.Min, Max=option.Max, Increment=option.Increment, Suffix="s", Default=state[option.Key],
            Callback=function(value) controller:UpdateSettings({[option.Key]=value}); state[option.Key]=controller.Settings[option.Key]; refresh() end})
    end
    controls.Test = context.Section:AddButton({Title="Test keepalive", Description="Enable Anti-AFK first, then send one input pulse.", Callback=function()
        if not controller.Enabled then context.Notify("Anti-AFK is off", "Enable Anti-AFK before testing."); return end
        if controller:Pulse() then context.Notify("Keepalive sent", "The input will release automatically.") end
    end})
    refresh()
end
return AntiAFK
