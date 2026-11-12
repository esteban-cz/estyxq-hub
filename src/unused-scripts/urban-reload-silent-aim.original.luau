-- [[ Rscripts Risk Notice ]]
-- This script is not verified by rscripts.net. Deal with caution.
--
-- Stay safe:
--   • Never log in on unofficial Roblox sites or lookalike domains.
--   • Real Roblox links use roblox.com (check the .com ending).
--   • Treat fake Roblox login / "claim reward" pages as phishing.
-- [[ End Rscripts Risk Notice ]]

local Players          = game:GetService("Players")
local CoreGui          = game:GetService("CoreGui")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer      = Players.LocalPlayer
local Camera           = workspace.CurrentCamera

local TARGET_GAME_ID = 84448037861644
local TITLE_ICON     = "rbxassetid://81470350553607"
local DISCORD_LINK   = "https://discord.gg/KSATpcU2Cn"
local LOADER_BRAND   = "NEMESIS"

local Config = {
    Silent = {
        Enabled     = false,
        UseFOV      = true,
        MaxDistance = 350,
        TeamCheck   = true,
        WallCheck   = false,
        Part        = "Head",
        HitChance   = 100,
        FOV         = 130,
    },
}

local Theme = {
    Bg      = Color3.fromRGB(10, 10, 12),
    Panel   = Color3.fromRGB(18, 18, 22),
    Row     = Color3.fromRGB(28, 28, 34),
    Accent  = Color3.fromRGB(255, 255, 255),
    Text    = Color3.fromRGB(245, 240, 250),
    TextDim = Color3.fromRGB(150, 140, 165),
    Off     = Color3.fromRGB(45, 40, 50),
    Green   = Color3.fromRGB(80, 220, 120),
    Red     = Color3.fromRGB(255, 80, 80),
    Discord = Color3.fromRGB(88, 101, 242),
}

local function getAimPart(char, partName)
    partName = partName or "Head"
    if partName == "HumanoidRootPart" then
        return char:FindFirstChild("HumanoidRootPart")
    elseif partName == "UpperTorso" then
        return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    end
    return char:FindFirstChild("Head")
end

local function silentVisibilityCheck(part, char)
    if not Config.Silent.WallCheck then return true end
    local filter = { LocalPlayer.Character }
    if char then table.insert(filter, char) end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = filter
    local origin = Camera.CFrame.Position
    local result = workspace:Raycast(origin, part.Position - origin, rp)
    return result == nil
end

local function getSilentTarget()
    if not Config.Silent.Enabled then return nil end
    local chance = Config.Silent.HitChance or 100
    if chance < 100 and math.random(1, 100) > chance then return nil end

    local closest, best = nil, Config.Silent.UseFOV and Config.Silent.FOV or math.huge
    local center = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y * 0.5)
    local camPos = Camera.CFrame.Position
    local maxDist = Config.Silent.MaxDistance or 350

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local skip = false
            if Config.Silent.TeamCheck and plr.Team and plr.Team == LocalPlayer.Team then
                skip = true
            end
            if not skip then
                local char = plr.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local part = getAimPart(char, Config.Silent.Part)
                        if part then
                            local dist3d = (part.Position - camPos).Magnitude
                            if dist3d <= maxDist then
                                local screen, onScreen = Camera:WorldToViewportPoint(part.Position)
                                if onScreen and screen.Z > 0 then
                                    local dist = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                                    if (not Config.Silent.UseFOV or dist <= Config.Silent.FOV) and dist < best then
                                        if silentVisibilityCheck(part, char) then
                                            closest = part
                                            best = dist
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return closest
end

local silentHooked = false
local silentOldNamecall = nil
local function ensureSilentHook()
    if silentHooked then return true end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        return false
    end
    local ok = pcall(function()
        silentOldNamecall = hookmetamethod(Camera, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if (method == "ViewportPointToRay" or method == "ScreenPointToRay")
                and self == Camera and Config.Silent.Enabled then
                local okTarget, target = pcall(getSilentTarget)
                if okTarget and target and target.Parent then
                    local origin = Camera.CFrame.Position
                    local ox = (math.random() - 0.5) * 0.06
                    local oy = (math.random() - 0.5) * 0.05
                    local oz = (math.random() - 0.5) * 0.06
                    local aimPos = target.Position + Vector3.new(ox, oy, oz)
                    return Ray.new(origin, (aimPos - origin).Unit * 1000)
                end
            end
            return silentOldNamecall(self, ...)
        end)
    end)
    if ok then
        silentHooked = true
        return true
    end
    return false
end

pcall(function()
    local function nuke(parent)
        for _, g in ipairs(parent:GetChildren()) do
            if g.Name == "SilentAimOpenSourceMini" or g.Name == "NemesisLoader" then
                g:Destroy()
            end
        end
    end
    nuke(CoreGui)
    if gethui then pcall(function() nuke(gethui()) end) end
end)

local function parentGui(g)
    local ok = pcall(function()
        if gethui then g.Parent = gethui() else g.Parent = CoreGui end
    end)
    if not ok then g.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end

local function toInt(v)
    if type(v) == "number" then return math.floor(v) end
    if type(v) == "string" then
        local n = tonumber(v)
        if n then return math.floor(n) end
    end
    local ok, n = pcall(function() return tonumber(tostring(v)) end)
    if ok and n then return math.floor(n) end
    return nil
end

local rawGameId  = game.GameId
local rawPlaceId = game.PlaceId
local gameIdNum  = toInt(rawGameId)
local placeIdNum = toInt(rawPlaceId)
local targetNum  = toInt(TARGET_GAME_ID)

print("[NEMESIS] GameId  =", tostring(rawGameId), "->", tostring(gameIdNum))
print("[NEMESIS] PlaceId =", tostring(rawPlaceId), "->", tostring(placeIdNum))
print("[NEMESIS] Target  =", tostring(TARGET_GAME_ID), "->", tostring(targetNum))

local function matchesTarget()
    if gameIdNum and targetNum and gameIdNum == targetNum then return true end
    if placeIdNum and targetNum and placeIdNum == targetNum then return true end
    local gs = tostring(rawGameId):gsub("%D", "")
    local ps = tostring(rawPlaceId):gsub("%D", "")
    local ts = tostring(TARGET_GAME_ID):gsub("%D", "")
    if gs == ts or ps == ts then return true end
    return false
end

local function buildGUI()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "SilentAimOpenSourceMini"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.DisplayOrder = 999
    parentGui(ScreenGui)

    local MAIN_W, MAIN_H = 210, 172

    local Main = Instance.new("Frame")
    Main.Size = UDim2.new(0, MAIN_W, 0, MAIN_H)
    Main.Position = UDim2.new(0.5, -MAIN_W / 2, 0.5, -MAIN_H / 2)
    Main.BackgroundColor3 = Theme.Bg
    Main.BorderSizePixel = 0
    Main.ClipsDescendants = true
    Main.Active = true
    Main.Parent = ScreenGui
    Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

    local MainStroke = Instance.new("UIStroke", Main)
    MainStroke.Color = Theme.Accent
    MainStroke.Thickness = 1.2
    MainStroke.Transparency = 0.25

    local Glow = Instance.new("ImageLabel")
    Glow.Size = UDim2.new(1.25, 0, 1.25, 0)
    Glow.Position = UDim2.new(-0.125, 0, -0.125, 0)
    Glow.BackgroundTransparency = 1
    Glow.Image = "rbxassetid://5028857084"
    Glow.ImageColor3 = Theme.Accent
    Glow.ImageTransparency = 0.85
    Glow.ZIndex = 0
    Glow.Parent = Main
    Instance.new("UICorner", Glow).CornerRadius = UDim.new(0, 20)

    local Header = Instance.new("Frame")
    Header.Size = UDim2.new(1, -16, 0, 44)
    Header.Position = UDim2.new(0, 8, 0, 8)
    Header.BackgroundTransparency = 1
    Header.ZIndex = 2
    Header.Parent = Main

    local Icon = Instance.new("ImageLabel")
    Icon.Size = UDim2.new(0, 42, 0, 42)
    Icon.Position = UDim2.new(0, 0, 0.5, -21)
    Icon.BackgroundTransparency = 1
    Icon.Image = TITLE_ICON
    Icon.ScaleType = Enum.ScaleType.Fit
    Icon.ZIndex = 3
    Icon.Parent = Header

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -48, 1, 0)
    Title.Position = UDim2.new(0, 48, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Font = Enum.Font.GothamBlack
    Title.TextSize = 12
    Title.TextColor3 = Theme.Text
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Text = "SILENT AIM OPEN SOURCE"
    Title.ZIndex = 3
    Title.Parent = Header

    local Divider = Instance.new("Frame")
    Divider.Size = UDim2.new(1, -20, 0, 1)
    Divider.Position = UDim2.new(0, 10, 0, 58)
    Divider.BackgroundColor3 = Theme.Row
    Divider.BorderSizePixel = 0
    Divider.ZIndex = 2
    Divider.Parent = Main

    local Status = Instance.new("TextLabel")
    Status.Size = UDim2.new(1, -20, 0, 14)
    Status.Position = UDim2.new(0, 10, 0, 64)
    Status.BackgroundTransparency = 1
    Status.Font = Enum.Font.GothamMedium
    Status.TextSize = 10
    Status.TextColor3 = Theme.TextDim
    Status.TextXAlignment = Enum.TextXAlignment.Left
    Status.Text = "Status: OFF"
    Status.ZIndex = 2
    Status.Parent = Main

    local ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Size = UDim2.new(1, -20, 0, 36)
    ToggleBtn.Position = UDim2.new(0, 10, 0, 84)
    ToggleBtn.BackgroundColor3 = Theme.Row
    ToggleBtn.BorderSizePixel = 0
    ToggleBtn.AutoButtonColor = false
    ToggleBtn.Font = Enum.Font.GothamBold
    ToggleBtn.TextSize = 12
    ToggleBtn.TextColor3 = Theme.Text
    ToggleBtn.Text = "ACTIVER SILENT AIM"
    ToggleBtn.ZIndex = 3
    ToggleBtn.Parent = Main
    Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 8)

    local ToggleStroke = Instance.new("UIStroke", ToggleBtn)
    ToggleStroke.Color = Theme.Off
    ToggleStroke.Thickness = 1.2
    ToggleStroke.Transparency = 0.2

    local DiscordBtn = Instance.new("TextButton")
    DiscordBtn.Size = UDim2.new(1, -20, 0, 32)
    DiscordBtn.Position = UDim2.new(0, 10, 0, 130)
    DiscordBtn.BackgroundColor3 = Theme.Panel
    DiscordBtn.BorderSizePixel = 0
    DiscordBtn.AutoButtonColor = false
    DiscordBtn.Font = Enum.Font.GothamBold
    DiscordBtn.TextSize = 11
    DiscordBtn.TextColor3 = Theme.Text
    DiscordBtn.Text = DISCORD_LINK
    DiscordBtn.ZIndex = 3
    DiscordBtn.Parent = Main
    Instance.new("UICorner", DiscordBtn).CornerRadius = UDim.new(0, 8)

    local DiscordStroke = Instance.new("UIStroke", DiscordBtn)
    DiscordStroke.Color = Theme.Discord
    DiscordStroke.Thickness = 1.2
    DiscordStroke.Transparency = 0.25

    local function paintToggle()
        if Config.Silent.Enabled then
            ToggleBtn.Text = "SILENT AIM ACTIF"
            ToggleBtn.BackgroundColor3 = Theme.Accent
            ToggleBtn.TextColor3 = Color3.fromRGB(10, 10, 12)
            ToggleStroke.Color = Theme.Accent
            ToggleStroke.Transparency = 0.05
            Status.Text = "Status: ON"
            Status.TextColor3 = Theme.Green
        else
            ToggleBtn.Text = "ACTIVER SILENT AIM"
            ToggleBtn.BackgroundColor3 = Theme.Row
            ToggleBtn.TextColor3 = Theme.Text
            ToggleStroke.Color = Theme.Off
            ToggleStroke.Transparency = 0.2
            Status.Text = "Status: OFF"
            Status.TextColor3 = Theme.TextDim
        end
    end
    paintToggle()

    ToggleBtn.MouseButton1Click:Connect(function()
        Config.Silent.Enabled = not Config.Silent.Enabled
        if Config.Silent.Enabled then ensureSilentHook() end
        paintToggle()
    end)

    DiscordBtn.MouseButton1Click:Connect(function()
        pcall(function()
            if setclipboard then setclipboard(DISCORD_LINK) end
        end)
        DiscordBtn.Text = "Discord copied"
        DiscordBtn.TextColor3 = Theme.Green
        DiscordStroke.Color = Theme.Green
        task.delay(1.6, function()
            if DiscordBtn and DiscordBtn.Parent then
                DiscordBtn.Text = DISCORD_LINK
                DiscordBtn.TextColor3 = Theme.Text
                DiscordStroke.Color = Theme.Discord
            end
        end)
    end)

    local dragging, startInputPos, startFramePos
    local function beginDrag(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging = true
        startInputPos = input.Position
        startFramePos = Main.Position
    end
    local function updateDrag(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - startInputPos
        Main.Position = UDim2.new(
            startFramePos.X.Scale, startFramePos.X.Offset + delta.X,
            startFramePos.Y.Scale, startFramePos.Y.Offset + delta.Y
        )
    end
    local function endDrag(input)
        if input.UserInputState == Enum.UserInputState.End then dragging = false end
    end
    Header.InputBegan:Connect(beginDrag)
    Header.InputChanged:Connect(updateDrag)
    Header.InputEnded:Connect(endDrag)
    UserInputService.InputChanged:Connect(updateDrag)
    UserInputService.InputEnded:Connect(endDrag)
end

local function showLoader(onDone)
    local loadGui = Instance.new("ScreenGui")
    loadGui.Name = "NemesisLoader"
    loadGui.ResetOnSpawn = false
    loadGui.IgnoreGuiInset = true
    loadGui.DisplayOrder = 9999
    parentGui(loadGui)

    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.35
    overlay.BorderSizePixel = 0
    overlay.Parent = loadGui

    local box = Instance.new("Frame")
    box.Size = UDim2.new(0, 280, 0, 120)
    box.Position = UDim2.new(0.5, -140, 0.5, -60)
    box.BackgroundColor3 = Theme.Bg
    box.BorderSizePixel = 0
    box.Parent = loadGui
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)

    local boxStroke = Instance.new("UIStroke", box)
    boxStroke.Color = Theme.Row
    boxStroke.Thickness = 1
    boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local logo = Instance.new("ImageLabel")
    logo.Size = UDim2.new(0, 44, 0, 44)
    logo.Position = UDim2.new(0, 16, 0, 16)
    logo.BackgroundTransparency = 1
    logo.Image = TITLE_ICON
    logo.ScaleType = Enum.ScaleType.Fit
    logo.Parent = box

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -80, 0, 20)
    title.Position = UDim2.new(0, 68, 0, 18)
    title.BackgroundTransparency = 1
    title.Text = LOADER_BRAND
    title.TextColor3 = Theme.Text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = box

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -80, 0, 16)
    subtitle.Position = UDim2.new(0, 68, 0, 38)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "Initializing..."
    subtitle.TextColor3 = Theme.TextDim
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextSize = 11
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = box

    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(1, -32, 0, 4)
    barBg.Position = UDim2.new(0, 16, 1, -22)
    barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    barBg.BorderSizePixel = 0
    barBg.Parent = box
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new(0, 0, 1, 0)
    barFill.BackgroundColor3 = Theme.Accent
    barFill.BorderSizePixel = 0
    barFill.Parent = barBg
    Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

    local pctLabel = Instance.new("TextLabel")
    pctLabel.Size = UDim2.new(0, 40, 0, 14)
    pctLabel.Position = UDim2.new(1, -50, 1, -40)
    pctLabel.BackgroundTransparency = 1
    pctLabel.Text = "0%"
    pctLabel.TextColor3 = Theme.Accent
    pctLabel.Font = Enum.Font.GothamBold
    pctLabel.TextSize = 10
    pctLabel.TextXAlignment = Enum.TextXAlignment.Right
    pctLabel.Parent = box

    box.Position = UDim2.new(0.5, -140, 0.5, -40)
    box.BackgroundTransparency = 1
    TweenService:Create(box, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, -140, 0.5, -60),
        BackgroundTransparency = 0,
    }):Play()

    local progress = 0
    local steps = {
        { delay = 0.15, text = "Loading modules..." },
        { delay = 0.20, text = "Injecting..." },
        { delay = 0.25, text = "Preparing UI..." },
        { delay = 0.30, text = "Injected" },
    }

    task.spawn(function()
        for _, s in ipairs(steps) do
            task.wait(s.delay)
            subtitle.Text = s.text
        end
        while progress < 100 do
            task.wait(0.02)
            progress = math.min(progress + 2, 100)
            barFill.Size = UDim2.new(progress / 100, 0, 1, 0)
            pctLabel.Text = math.floor(progress) .. "%"
        end
        task.wait(0.2)
        TweenService:Create(box, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, -140, 0.5, -40),
            BackgroundTransparency = 1,
        }):Play()
        task.wait(0.35)
        loadGui:Destroy()
        if onDone then onDone() end
    end)
end

local function showUnsupported()
    local gui = Instance.new("ScreenGui")
    gui.Name = "NemesisLoader"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9999
    parentGui(gui)

    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.35
    overlay.BorderSizePixel = 0
    overlay.Parent = gui

    local box = Instance.new("Frame")
    box.Size = UDim2.new(0, 300, 0, 140)
    box.Position = UDim2.new(0.5, -150, 0.5, -70)
    box.BackgroundColor3 = Theme.Bg
    box.BorderSizePixel = 0
    box.Parent = gui
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)

    local boxStroke = Instance.new("UIStroke", box)
    boxStroke.Color = Theme.Row
    boxStroke.Thickness = 1
    boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local logo = Instance.new("ImageLabel")
    logo.Size = UDim2.new(0, 44, 0, 44)
    logo.Position = UDim2.new(0, 16, 0, 16)
    logo.BackgroundTransparency = 1
    logo.Image = TITLE_ICON
    logo.ScaleType = Enum.ScaleType.Fit
    logo.Parent = box

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -80, 0, 20)
    title.Position = UDim2.new(0, 68, 0, 18)
    title.BackgroundTransparency = 1
    title.Text = LOADER_BRAND .. " don't load"
    title.TextColor3 = Theme.Red
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = box

    local reason = Instance.new("TextLabel")
    reason.Size = UDim2.new(1, -80, 0, 16)
    reason.Position = UDim2.new(0, 68, 0, 42)
    reason.BackgroundTransparency = 1
    reason.Text = "Reason: Not supported game"
    reason.TextColor3 = Theme.TextDim
    reason.Font = Enum.Font.Gotham
    reason.TextSize = 11
    reason.TextXAlignment = Enum.TextXAlignment.Left
    reason.Parent = box

    local debugLbl = Instance.new("TextLabel")
    debugLbl.Size = UDim2.new(1, -32, 0, 16)
    debugLbl.Position = UDim2.new(0, 16, 0, 82)
    debugLbl.BackgroundTransparency = 1
    debugLbl.Text = "PlaceId: " .. tostring(rawPlaceId)
    debugLbl.TextColor3 = Theme.TextDim
    debugLbl.Font = Enum.Font.Code
    debugLbl.TextSize = 10
    debugLbl.TextXAlignment = Enum.TextXAlignment.Left
    debugLbl.Parent = box

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(1, -32, 0, 30)
    closeBtn.Position = UDim2.new(0, 16, 1, -44)
    closeBtn.BackgroundColor3 = Theme.Row
    closeBtn.BorderSizePixel = 0
    closeBtn.AutoButtonColor = false
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    closeBtn.TextColor3 = Theme.Text
    closeBtn.Text = "Close"
    closeBtn.Parent = box
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
    local closeStroke = Instance.new("UIStroke", closeBtn)
    closeStroke.Color = Theme.Red
    closeStroke.Thickness = 1.2
    closeStroke.Transparency = 0.3

    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy()
    end)
end

if not matchesTarget() then
    showUnsupported()
    return
end

showLoader(function()
    buildGUI()
    pcall(ensureSilentHook)
end)