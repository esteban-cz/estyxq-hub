-- estyxq Hub / reusable skeleton and ring ESP
-- Execute this file before menu.luau, or load its returned module from a raw GitHub URL.
-- Standalone use: local module = loadstring(game:HttpGet(yourURL))(); local esp = module.new({ Enabled = true })

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local environment = (type(getgenv) == "function" and getgenv()) or shared
local MODULE_KEY = "estyxq-hub.ESPModule"
local INSTANCE_KEY = "estyxq-hub.ESP"

local ESP = { Version = "2.1.0" }
local Controller = {}
Controller.__index = Controller

local DEFAULTS = {
    Enabled = false,
    SkeletonEnabled = true,
    GroundRingEnabled = true,
    HeadRingEnabled = true,
    TeamCheck = true,
    MaxDistance = 3000,
    Color = Color3.fromRGB(179, 154, 255),
    OutlineEnabled = true,
    DistanceFade = true,
    PulseEnabled = true,
    PulseSpeed = 1.5,
    RingAnimationEnabled = true,
    RingSpeed = 0.2, -- Revolutions per second.
    Thickness = 1.5,
    Opacity = 0.9, -- Drawing uses 1 for fully opaque.
    RefreshRate = 60,
    RingSegments = 40,
    GroundRadius = 2.5,
    GroundOffset = 3, -- Studs below HumanoidRootPart.
    HeadRadius = 0.6,
    HeadOffset = 0, -- Studs above the center of Head.
}

local NUMBER_LIMITS = {
    MaxDistance = { 50, 10000 },
    PulseSpeed = { 0.1, 10 },
    RingSpeed = { 0.05, 1.5 },
    Thickness = { 0.5, 5 },
    Opacity = { 0, 1 },
    RefreshRate = { 15, 120, true },
    RingSegments = { 12, 64, true },
    GroundRadius = { 0.5, 8 },
    GroundOffset = { 0, 8 },
    HeadRadius = { 0.2, 3 },
    HeadOffset = { -2, 4 },
}

local BONES = {
    [Enum.HumanoidRigType.R6] = {
        { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
        { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
    },
    [Enum.HumanoidRigType.R15] = {
        { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
        { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
        { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
        { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
        { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    },
}

local OUTLINE_COLOR = Color3.fromRGB(12, 10, 20)
local WHITE = Color3.new(1, 1, 1)
local circleCache = {}
local function circlePoints(segments)
    if not circleCache[segments] then
        local points = table.create(segments)
        for index = 1, segments do
            local angle = (index - 1) / segments * math.pi * 2
            points[index] = Vector3.new(math.cos(angle), 0, math.sin(angle))
        end
        circleCache[segments] = points
    end
    return circleCache[segments]
end

local function disconnectAll(connections)
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
end

local function hideLines(lines)
    for _, line in ipairs(lines) do
        line.Visible = false
    end
end

local function hideRecord(record)
    hideLines(record.SkeletonOutline)
    hideLines(record.Skeleton)
    hideLines(record.GroundRing)
    hideLines(record.HeadRing)
    record.Visible = false
end

function ESP.GetDefaults()
    return table.clone(DEFAULTS)
end

function ESP.IsSupported()
    return Drawing ~= nil and type(Drawing.new) == "function"
end

function Controller:_resizeLines(lines, count, zIndex)
    while #lines > count do
        local line = table.remove(lines)
        pcall(function()
            line.Visible = false
            line:Remove()
        end)
        self._drawingCount -= 1
    end
    while #lines < count do
        local ok, line = pcall(Drawing.new, "Line")
        if not ok or not line then
            error("The drawing API could not create an ESP line.", 0)
        end
        table.insert(lines, line) -- Track it before setting properties so errors can still be cleaned up.
        self._drawingCount += 1
        line.Visible = false
        line.ZIndex = zIndex or 2
    end
end

function Controller:_clearDrawings(record)
    self:_resizeLines(record.SkeletonOutline, 0)
    self:_resizeLines(record.Skeleton, 0)
    self:_resizeLines(record.GroundRing, 0)
    self:_resizeLines(record.HeadRing, 0)
    table.clear(record.GroundProjection)
    table.clear(record.HeadProjection)
    record.Visible = false
end

function Controller:_detachCharacter(record)
    disconnectAll(record.CharacterConnections)
    self:_clearDrawings(record)
    record.Character, record.Humanoid, record.Rig = nil, nil, nil
    table.clear(record.Parts)
end

function Controller:_attachCharacter(record, character)
    self:_detachCharacter(record)
    record.Character = character

    local function addChild(child)
        if child:IsA("BasePart") then
            record.Parts[child.Name] = child
        elseif child:IsA("Humanoid") then
            record.Humanoid = child
        end
    end
    table.insert(record.CharacterConnections, character.ChildAdded:Connect(addChild))
    table.insert(record.CharacterConnections, character.ChildRemoved:Connect(function(child)
        if record.Parts[child.Name] == child then
            record.Parts[child.Name] = nil
        end
        if record.Humanoid == child then
            record.Humanoid = nil
        end
    end))
    for _, child in ipairs(character:GetChildren()) do
        addChild(child)
    end
end

function Controller:_track(player)
    if player == LocalPlayer or self._records[player] or not self.Enabled then
        return
    end
    local record = {
        Player = player, Parts = {}, Skeleton = {}, SkeletonOutline = {}, GroundRing = {}, HeadRing = {},
        GroundProjection = {}, HeadProjection = {}, Connections = {}, CharacterConnections = {},
        Visible = false,
    }
    self._records[player] = record
    table.insert(record.Connections, player.CharacterAdded:Connect(function(character)
        self:_attachCharacter(record, character)
    end))
    table.insert(record.Connections, player.CharacterRemoving:Connect(function(character)
        if record.Character == character then
            self:_detachCharacter(record)
        end
    end))
    if player.Character then
        self:_attachCharacter(record, player.Character)
    end
end

function Controller:_untrack(player)
    local record = self._records[player]
    if record then
        disconnectAll(record.Connections)
        self:_detachCharacter(record)
        self._records[player] = nil
    end
end

function Controller:_drawLine(line, from, to, color, opacity, thickness)
    opacity = opacity or self.Settings.Opacity
    if from.Z <= 0.05 or to.Z <= 0.05 or opacity <= 0.001 then
        line.Visible = false
        return
    end
    line.From = Vector2.new(from.X, from.Y)
    line.To = Vector2.new(to.X, to.Y)
    line.Color = color
    line.Thickness = thickness or self.Settings.Thickness
    line.Transparency = opacity
    line.Visible = true
end

function Controller:_updateRingStyles(color)
    local settings = self.Settings
    local phase = (self._elapsed * settings.RingSpeed) % 1
    local highlightColor = color:Lerp(WHITE, 0.4)
    for index = 1, settings.RingSegments do
        local style = self._ringStyles[index]
        if not style then
            style = {}
            self._ringStyles[index] = style
        end
        local highlight = 0
        if settings.RingAnimationEnabled then
            local separation = math.abs((index - 1) / settings.RingSegments - phase)
            separation = math.min(separation, 1 - separation)
            highlight = math.max(0, 1 - separation / 0.22)
            highlight = highlight * highlight * (3 - 2 * highlight)
        end
        style.Color = color:Lerp(highlightColor, highlight)
        style.Opacity = settings.RingAnimationEnabled and (0.55 + 0.45 * highlight) or 1
    end
end

function Controller:_drawRing(lines, projection, camera, center, radius, opacity)
    local points = circlePoints(self.Settings.RingSegments)
    self:_resizeLines(lines, #points)
    for index, offset in ipairs(points) do
        projection[index] = camera:WorldToViewportPoint(center + offset * radius)
    end
    for index, line in ipairs(lines) do
        local style = self._ringStyles[index]
        self:_drawLine(line, projection[index], projection[index % #points + 1], style.Color, opacity * style.Opacity)
    end
end

function Controller:_render()
    local camera = workspace.CurrentCamera -- Cameras can be replaced by a game or while spectating.
    local settings = self.Settings
    local localCharacter = LocalPlayer.Character
    local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
    local origin = localRoot and localRoot.Position or (camera and camera.CFrame.Position)
    local color = settings.Color
    if settings.PulseEnabled then
        local phase = (math.sin(self._elapsed * settings.PulseSpeed) + 1) * 0.5
        color = self._pulseLow:Lerp(self._pulseHigh, phase):Lerp(settings.Color, 0.35)
    end
    -- All players share the same ring styling; calculate the moving highlight only once per update.
    if settings.GroundRingEnabled or settings.HeadRingEnabled then
        self:_updateRingStyles(color)
    end
    local maxDistanceSquared = settings.MaxDistance * settings.MaxDistance

    for player, record in pairs(self._records) do
        local opacity = settings.Opacity
        local humanoid = record.Humanoid
        local root = record.Parts.HumanoidRootPart
        local eligible = camera and origin and root and record.Character == player.Character
            and record.Character.Parent and humanoid and humanoid.Health > 0
        if eligible and settings.TeamCheck and not LocalPlayer.Neutral and not player.Neutral
            and LocalPlayer.Team ~= nil and LocalPlayer.Team == player.Team then
            eligible = false
        end
        if eligible then
            local delta = root.Position - origin
            local distanceSquared = delta:Dot(delta)
            local _, onScreen = camera:WorldToViewportPoint(root.Position)
            eligible = distanceSquared <= maxDistanceSquared and onScreen
            if eligible and settings.DistanceFade then
                -- Fade through the final 35% of the range, with a smooth transition at both ends.
                local fadeStart = maxDistanceSquared * 0.65 * 0.65
                local fade = math.clamp((distanceSquared - fadeStart) / (maxDistanceSquared - fadeStart), 0, 1)
                opacity *= 1 - fade * fade * (3 - 2 * fade)
            end
        end
        local bones = humanoid and BONES[humanoid.RigType]
        if not eligible or not bones then
            hideRecord(record)
            continue
        end
        if record.Rig ~= humanoid.RigType then
            self:_clearDrawings(record)
            record.Rig = humanoid.RigType
        end
        record.Visible = true
        self:_resizeLines(record.SkeletonOutline,
            settings.SkeletonEnabled and settings.OutlineEnabled and #bones or 0, 1)
        self:_resizeLines(record.Skeleton, settings.SkeletonEnabled and #bones or 0)
        for index, line in ipairs(record.Skeleton) do
            local pair = bones[index]
            local partA, partB = record.Parts[pair[1]], record.Parts[pair[2]]
            if partA and partB then
                local endpoint = partB.Position
                if record.Rig == Enum.HumanoidRigType.R6 and (pair[2] == "Left Arm" or pair[2] == "Right Arm") then
                    endpoint += Vector3.new(0, 0.5, 0)
                end
                local from = camera:WorldToViewportPoint(partA.Position)
                local to = camera:WorldToViewportPoint(endpoint)
                local outline = record.SkeletonOutline[index]
                if outline then
                    self:_drawLine(outline, from, to, OUTLINE_COLOR, opacity * 0.75, settings.Thickness + 1.8)
                end
                self:_drawLine(line, from, to, color, opacity)
            else
                line.Visible = false
                if record.SkeletonOutline[index] then record.SkeletonOutline[index].Visible = false end
            end
        end
        if settings.GroundRingEnabled then
            self:_drawRing(record.GroundRing, record.GroundProjection, camera,
                root.Position - Vector3.new(0, settings.GroundOffset, 0), settings.GroundRadius, opacity)
        end
        local head = record.Parts.Head
        if settings.HeadRingEnabled and head then
            self:_drawRing(record.HeadRing, record.HeadProjection, camera,
                head.Position + Vector3.new(0, settings.HeadOffset, 0), settings.HeadRadius, opacity)
        else
            hideLines(record.HeadRing)
        end
    end
end

function Controller:SetEnabled(enabled)
    assert(not self.Destroyed, "This ESP controller has been destroyed.")
    assert(type(enabled) == "boolean", "Enabled must be a boolean.")
    if enabled == self.Enabled then
        return
    end
    if enabled then
        assert(ESP.IsSupported(), "ESP needs an environment with the Drawing API.")
    end
    self.Enabled, self.Settings.Enabled = enabled, enabled
    self._accumulator = 0
    if not enabled then
        disconnectAll(self._connections)
        for player in pairs(self._records) do
            self:_untrack(player)
        end
        return
    end
    local started, startError = pcall(function()
        table.insert(self._connections, Players.PlayerAdded:Connect(function(player) self:_track(player) end))
        table.insert(self._connections, Players.PlayerRemoving:Connect(function(player) self:_untrack(player) end))
        for _, player in ipairs(Players:GetPlayers()) do
            self:_track(player)
        end
        table.insert(self._connections, RunService.RenderStepped:Connect(function(deltaTime)
            self._elapsed += deltaTime
            self._accumulator += deltaTime
            local interval = 1 / self.Settings.RefreshRate
            if self._accumulator < interval then
                return
            end
            self._accumulator %= interval
            local rendered, renderError = pcall(self._render, self)
            if not rendered then
                self:SetEnabled(false)
                if self._onError then
                    task.defer(self._onError, tostring(renderError))
                else
                    warn("[estyxq ESP] " .. tostring(renderError))
                end
            end
        end))
    end)
    if not started then
        self:SetEnabled(false)
        error(startError, 0)
    end
end

function Controller:UpdateSettings(patch)
    assert(not self.Destroyed, "This ESP controller has been destroyed.")
    local nextSettings = table.clone(self.Settings)
    for key, value in pairs(patch) do
        local default = DEFAULTS[key]
        assert(default ~= nil, "Unknown ESP setting: " .. tostring(key))
        if NUMBER_LIMITS[key] then
            local limits = NUMBER_LIMITS[key]
            assert(type(value) == "number" and value == value and math.abs(value) < math.huge, key .. " must be finite.")
            value = math.clamp(value, limits[1], limits[2])
            if limits[3] then
                value = math.round(value)
            end
        elseif key == "Color" then
            assert(typeof(value) == "Color3", "Color must be a Color3.")
        else
            assert(type(value) == "boolean", key .. " must be a boolean.")
        end
        nextSettings[key] = value
    end
    local shouldEnable = nextSettings.Enabled
    nextSettings.Enabled = self.Enabled
    self.Settings = nextSettings
    self._pulseLow = nextSettings.Color:Lerp(Color3.new(0, 0, 0), 0.12)
    self._pulseHigh = nextSettings.Color:Lerp(WHITE, 0.18)
    for _, record in pairs(self._records) do
        if not nextSettings.SkeletonEnabled or not nextSettings.OutlineEnabled then
            self:_resizeLines(record.SkeletonOutline, 0)
        end
        if not nextSettings.SkeletonEnabled then self:_resizeLines(record.Skeleton, 0) end
        if not nextSettings.GroundRingEnabled then self:_resizeLines(record.GroundRing, 0) end
        if not nextSettings.HeadRingEnabled then self:_resizeLines(record.HeadRing, 0) end
        hideRecord(record)
    end
    self:SetEnabled(shouldEnable)
end

function Controller:GetSettings()
    return table.clone(self.Settings)
end

function Controller:GetStats()
    local tracked, visible = 0, 0
    for _, record in pairs(self._records) do
        tracked += 1
        if record.Visible then visible += 1 end
    end
    return { Enabled = self.Enabled, TrackedPlayers = tracked, VisiblePlayers = visible, Drawings = self._drawingCount }
end

function Controller:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false)
    self.Destroyed = true
    self._onError = nil
    if environment[INSTANCE_KEY] == self then
        environment[INSTANCE_KEY] = nil
    end
end

function ESP.new(settings, onError)
    assert(LocalPlayer, "ESP must run on the client.")
    local previous = environment[INSTANCE_KEY]
    if previous then previous:Destroy() end
    local self = setmetatable({
        Settings = ESP.GetDefaults(), Enabled = false, Destroyed = false,
        _records = {}, _connections = {}, _drawingCount = 0, _ringStyles = {},
        _elapsed = 0, _accumulator = 0, _onError = onError,
    }, Controller)
    local configured, configureError = pcall(self.UpdateSettings, self, settings or {})
    if not configured then
        self:Destroy()
        error(configureError, 0)
    end
    environment[INSTANCE_KEY] = self
    return self
end

environment[MODULE_KEY] = ESP
return ESP
