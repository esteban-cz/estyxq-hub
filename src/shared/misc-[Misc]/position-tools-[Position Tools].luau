local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PositionTools = {
    Icon = "gamepad",
    Side = "Full"
}

local function getPosition(player)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root.Position
end

local function formatPosition(position)
    return string.format("%d, %d, %d", math.floor(position.X), math.floor(position.Y), math.floor(position.Z))
end

function PositionTools.Mount(context)
    local player = Players.LocalPlayer
    assert(player, "Position Tools must run on the client.")

    context.Controls.CurrentPosition = context.Section:AddParagraph({
        Title = "Current position",
        Content = "Character unavailable."
    })
    context.Controls.SavedPosition = context.Section:AddParagraph({
        Title = "Saved position",
        Content = "None"
    })
    local state = context.State
    state.HeightOffset = 3

    local function readPosition()
        local position = getPosition(player)
        if not position then
            context.Notify("Position unavailable", "Your character position could not be read.", "Error")
            return nil
        end
        return position
    end

    context.Controls.Save = context.Section:AddButton({
        Title = "Save current position",
        Callback = function()
            local position = readPosition()
            if not position then return end
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            state.SavedCFrame, state.SavedPosition = root.CFrame, position
            context.Controls.SavedPosition:Set("Saved position", formatPosition(position))
            context.Notify("Position saved", formatPosition(position))
        end
    })
    context.Controls.Copy = context.Section:AddButton({
        Title = "Copy current position",
        Callback = function()
            local position = readPosition()
            if not position then return end
            if type(setclipboard) ~= "function" then
                context.Notify("Clipboard unavailable", "This environment does not provide clipboard access.", "Error")
                return
            end
            local text = formatPosition(position)
            local copied, message = pcall(setclipboard, text)
            if not copied then
                context.Notify("Could not copy position", tostring(message), "Error")
                return
            end
            context.Notify("Position copied", text)
        end
    })

    context.Controls.HeightOffset = context.Section:AddSlider({
        Title = "Teleport height offset", Min = 0, Max = 10, Increment = 0.5, Default = state.HeightOffset, Suffix = " studs",
        Callback = function(value) state.HeightOffset = value end
    })
    context.Controls.Teleport = context.Section:AddButton({
        Title = "Teleport to saved position", Callback = function()
            if not state.SavedCFrame then context.Notify("No saved position", "Save a position first.", "Warning"); return end
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not root or not humanoid or humanoid.Health <= 0 then context.Notify("Character unavailable", "Spawn a living character before teleporting.", "Error"); return end
            local moved, message = pcall(function()
                root.CFrame = state.SavedCFrame + Vector3.new(0, state.HeightOffset, 0)
                root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
            end)
            if not moved then context.Notify("Teleport failed", tostring(message), "Error")
            else context.Notify("Position restored", "Returned to your saved position.") end
        end
    })
    context.Controls.Clear = context.Section:AddButton({Title = "Clear saved position", Callback = function()
        state.SavedCFrame, state.SavedPosition = nil, nil
        context.Controls.SavedPosition:Set("Saved position", "None")
    end})
    context.Controls.Reset = context.Section:AddButton({Title = "Reset character", Description = "Respawn your current character.", Hold = 1, Callback = function()
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then context.Notify("Character unavailable", "Your character could not be found.", "Error"); return end
        humanoid.Health = 0
    end})
    context.AddCleanup(function() state.SavedCFrame, state.SavedPosition = nil, nil end)

    local function refreshPosition()
        local position = getPosition(player)
        context.Controls.CurrentPosition:Set("Current position", position and formatPosition(position) or "Character unavailable.")
    end
    refreshPosition()

    local elapsed = 0
    context.Connect(RunService.Heartbeat, function(deltaTime)
        elapsed += deltaTime
        if elapsed < 0.15 then return end
        elapsed %= 0.15
        refreshPosition()
    end)
end

return PositionTools
