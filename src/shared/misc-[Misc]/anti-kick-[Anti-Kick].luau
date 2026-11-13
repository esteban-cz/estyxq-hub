-- Client kick-call interception. One shared dispatcher pair survives retries/reloads.
local AntiKick = {Icon = "shield", Side = "Full", DefaultEnabled = true}
local Controller = {}
Controller.__index = Controller
local KEY = "estyxq-hub.AntiKick.Hooks"

local function getBroker(player)
    local environment = (type(getgenv) == "function" and getgenv()) or shared
    local broker = environment[KEY]
    if broker then assert(broker.Version == 1, "Rejoin before changing the Anti-Kick hook version.")
    else broker = {Version = 1}; environment[KEY] = broker end
    if broker.NamecallInstalled and broker.DirectInstalled then return broker end
    assert(type(getnamecallmethod) == "function" and type(hookfunction) == "function", "This executor does not support the required kick hooks.")
    assert(type(player.Kick) == "function", "The local player has no Kick method.")
    local wrap = type(newcclosure) == "function" and newcclosure or function(callback) return callback end
    local methodName = getnamecallmethod
    if not broker.NamecallInstalled then
        local dispatch = wrap(function(object, ...)
            local owner = broker.Owner
            if owner and owner.Enabled and object == owner.Player and string.lower(methodName()) == "kick" then
                owner.Blocked = owner.Blocked + 1
                return
            end
            return broker.OriginalNamecall(object, ...)
        end)
        if type(hookmetamethod) == "function" then
            broker.OriginalNamecall = hookmetamethod(game, "__namecall", dispatch)
        else
            assert(type(getrawmetatable) == "function" and type(setreadonly) == "function", "This executor does not support metatable hooks.")
            local meta = getrawmetatable(game)
            local wasReadonly = true
            if type(isreadonly) == "function" then wasReadonly = isreadonly(meta) end
            broker.OriginalNamecall = meta.__namecall
            setreadonly(meta, false)
            local installed, message = pcall(function() meta.__namecall = dispatch end)
            local locked, lockError = pcall(setreadonly, meta, wasReadonly)
            if installed then broker.NamecallInstalled = true end
            if not installed then error(message, 0) end
            if not locked then error(lockError, 0) end
        end
        assert(type(broker.OriginalNamecall) == "function", "The executor did not return the original namecall.")
        broker.NamecallInstalled = true
    end
    if not broker.DirectInstalled then
        broker.OriginalKick = hookfunction(player.Kick, wrap(function(object, ...)
            local owner = broker.Owner
            if owner and owner.Enabled and object == owner.Player then
                owner.Blocked = owner.Blocked + 1
                return
            end
            return broker.OriginalKick(object, ...)
        end))
        assert(type(broker.OriginalKick) == "function", "The executor did not return the original Kick function.")
        broker.DirectInstalled = true
    end
    return broker
end

function Controller:SetEnabled(enabled)
    assert(not self.Destroyed, "Anti-Kick has been destroyed.")
    assert(type(enabled) == "boolean", "Enabled must be a boolean.")
    if enabled == self.Enabled then return end
    if enabled then
        local broker = getBroker(self.Player)
        if broker.Owner and broker.Owner ~= self then broker.Owner:SetEnabled(false) end
        self.Broker, self.Enabled = broker, true
        broker.Owner = self
    else
        self.Enabled = false
        if self.Broker and self.Broker.Owner == self then self.Broker.Owner = nil end
    end
end
function Controller:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false)
    self.Destroyed = true
end
function AntiKick.new()
    local player = game:GetService("Players").LocalPlayer
    assert(player, "Anti-Kick must run on the client.")
    return setmetatable({Player = player, Enabled = false, Blocked = 0, Destroyed = false}, Controller)
end
function AntiKick.Mount(context)
    local controller = AntiKick.new()
    context.State.Enabled = false
    context.AddCleanup(function() context.State.Enabled = false; controller:Destroy() end)
    local status = context.Section:AddParagraph({Title = "Anti-Kick is off", Content = "Intercepts local Kick calls while enabled. Server disconnections are unaffected."})
    local function enable(value)
        local ok, message = pcall(controller.SetEnabled, controller, value)
        context.State.Enabled = controller.Enabled
        status:Set(controller.Enabled and "Anti-Kick is on" or "Anti-Kick is off")
        if not ok then
            if context.Controls.Enabled then context.Controls.Enabled:Set(false) end
            context.Notify("Anti-Kick unavailable", tostring(message), "Error")
        end
    end
    context.Controls.Enabled = context.Section:AddToggle({Title = "Enable Anti-Kick", Style = "Switch", Default = false, Callback = enable})
    if AntiKick.DefaultEnabled then context.Controls.Enabled:Set(true) end
end
return AntiKick
