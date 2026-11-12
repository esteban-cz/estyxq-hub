local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local AntiKick = {
    Icon = "shield",
    Side = "Full"
}

function AntiKick.Mount(context)
    assert(LocalPlayer, "Anti-Kick must run on the client.")

    local enabled = false
    context.State.Enabled = false
    context.AddCleanup(function()
        enabled = false
        context.State.Enabled = false
    end)

    local meta = getrawmetatable(game)
    local oldNamecall = meta.__namecall
    setreadonly(meta, false)
    local installed, installError = pcall(function()
        meta.__namecall = newcclosure(function(self, ...)
            if enabled and self == LocalPlayer and string.lower(getnamecallmethod()) == "kick" then
                print("Prevented Kick At " .. tostring(os.time()))
                return
            end
            return oldNamecall(self, ...)
        end)
    end)
    local locked, lockError = pcall(setreadonly, meta, true)
    if not installed then
        error(installError, 0)
    end
    if not locked then
        error(lockError, 0)
    end

    local oldKick
    oldKick = hookfunction(LocalPlayer.Kick, newcclosure(function(self, ...)
        if enabled then
            print("Prevented Kick At " .. tostring(os.time()))
            return
        end
        return oldKick(self, ...)
    end))

    local status = context.Section:AddParagraph({
        Title = "Anti-Kick is on",
        Content = "Client-side Kick calls are blocked while enabled."
    })
    local function refresh()
        local title = enabled and "Anti-Kick is on" or "Anti-Kick is off"
        status:Set(title, "Client-side Kick calls are blocked while enabled.")
    end
    context.Controls.Enabled = context.Section:AddToggle({
        Title = "Enable Anti-Kick",
        Style = "Switch",
        Default = true,
        Callback = function(value)
            enabled = value
            context.State.Enabled = value
            refresh()
        end
    })
    enabled = true
    context.State.Enabled = true
    refresh()
end

return AntiKick
