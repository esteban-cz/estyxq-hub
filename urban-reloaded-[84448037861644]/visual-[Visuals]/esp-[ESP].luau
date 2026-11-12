local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local environment = (type(getgenv) == "function" and getgenv()) or shared
local INSTANCE_KEY = "estyxq-hub.UrbanReload.ESP"

local ESP = {
    Version = "3.0.0",
    Icon = "eye",
    Side = "Full"
}
local Controller = {}
Controller.__index = Controller

local DEFAULTS = {
    Enabled = false,
    SkeletonEnabled = true,
    GroundRingEnabled = true,
    HeadRingEnabled = true,
    TeamCheck = true,
    VisibleOnly = false,
    NamesEnabled = true,
    DistanceEnabled = true,
    HealthBarEnabled = true,
    BoxEnabled = false,
    UseDisplayNames = false,
    UseTeamColors = false,
    AutoGroundOffset = true,
    AutoHeadRadius = true,
    MaxDistance = 600,
    Color = Color3.fromRGB(179, 154, 255),
    OutlineEnabled = true,
    DistanceFade = true,
    PulseEnabled = false,
    PulseSpeed = 1.5,
    RingAnimationEnabled = true,
    RingSpeed = 0.2, -- Revolutions per second.
    Thickness = 1.5,
    Opacity = 0.9, -- Drawing uses 1 for fully opaque.
    RefreshRate = 30,
    RingSegments = 24,
    GroundRadius = 2.5,
    GroundOffset = 3, -- Studs below HumanoidRootPart.
    HeadRadius = 0.6,
    TextSize = 13,
    HeadOffset = 0 -- Studs above the center of Head.
}

local NUMBER_LIMITS = {
    MaxDistance = {50, 3000},
    TextSize = {10, 20, true},
    PulseSpeed = {0.1, 10},
    RingSpeed = {0.05, 1.5},
    Thickness = {0.5, 5},
    Opacity = {0, 1},
    RefreshRate = {15, 120, true},
    RingSegments = {12, 64, true},
    GroundRadius = {0.5, 8},
    GroundOffset = {0, 8},
    HeadRadius = {0.2, 3},
    HeadOffset = {-2, 4}
}

local BONES = {
    [Enum.HumanoidRigType.R6] = {{"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
                                 {"Torso", "Left Leg"}, {"Torso", "Right Leg"}},
    [Enum.HumanoidRigType.R15] = {{"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"}, {"LowerTorso", "LeftUpperLeg"},
                                  {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
                                  {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"},
                                  {"RightLowerLeg", "RightFoot"}, {"UpperTorso", "LeftUpperArm"},
                                  {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
                                  {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"},
                                  {"RightLowerArm", "RightHand"}}
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
    hideLines(record.BoxOutline)
    hideLines(record.Box)
    hideLines(record.HealthBar)
    if record.Tag then
        record.Tag.Visible = false
    end
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
        self._drawingCount = self._drawingCount - 1
    end
    while #lines < count do
        local ok, line = pcall(Drawing.new, "Line")
        if not ok or not line then
            error("The drawing API could not create an ESP line.", 0)
        end
        table.insert(lines, line) -- Track it before setting properties so errors can still be cleaned up.
        self._drawingCount = self._drawingCount + 1
        line.Visible = false
        line.ZIndex = zIndex or 2
    end
end

function Controller:_clearDrawings(record)
    self:_resizeLines(record.SkeletonOutline, 0)
    self:_resizeLines(record.Skeleton, 0)
    self:_resizeLines(record.GroundRing, 0)
    self:_resizeLines(record.HeadRing, 0)
    self:_resizeLines(record.BoxOutline, 0)
    self:_resizeLines(record.Box, 0)
    self:_resizeLines(record.HealthBar, 0)
    self:_removeTag(record)
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
        Player = player,
        Parts = {},
        Skeleton = {},
        SkeletonOutline = {},
        GroundRing = {},
        HeadRing = {},
        GroundProjection = {},
        HeadProjection = {},
        Connections = {},
        CharacterConnections = {},
        Box = {},
        BoxOutline = {},
        HealthBar = {},
        Visible = false
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
        return false
    end
    line.From = Vector2.new(from.X, from.Y)
    line.To = Vector2.new(to.X, to.Y)
    line.Color = color
    line.Thickness = thickness or self.Settings.Thickness
    line.Transparency = opacity
    line.Visible = true
    return true
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

function Controller:_drawRing(lines, projection, camera, center, radius, opacity, upright)
    local points = circlePoints(self.Settings.RingSegments)
    self:_resizeLines(lines, #points)
    for index, offset in ipairs(points) do
        local point
        if upright then
            point = center + (camera.CFrame.RightVector * offset.X + camera.CFrame.UpVector * offset.Z) * radius
        else
            point = center + offset * radius
        end
        projection[index] = camera:WorldToViewportPoint(point)
    end
    local visible = false
    for index, line in ipairs(lines) do
        local style = self._ringStyles[index]
        visible = self:_drawLine(line, projection[index], projection[index % #points + 1], style.Color,
            opacity * style.Opacity) or visible
    end
    return visible
end

function Controller:_removeTag(record)
    local tag = record.Tag
    record.Tag = nil
    if tag then
        pcall(function()
            tag.Visible = false;
            tag:Remove()
        end)
        self._drawingCount = self._drawingCount - 1
    end
end

function Controller:_tag(record)
    if record.Tag then
        return record.Tag
    end
    if self._textUnavailable then
        return nil
    end
    local tag
    local ok, message = pcall(function()
        tag = Drawing.new("Text")
        assert(tag, "The drawing API returned no text object.")
        record.Tag = tag
        self._drawingCount = self._drawingCount + 1
        tag.Visible, tag.Center, tag.Font, tag.ZIndex = false, true, 2, 3
    end)
    if not ok then
        self:_removeTag(record)
        self._textUnavailable = true
        if self._onWarning then
            local callback = self._onWarning
            task.defer(function()
                if not self.Destroyed then
                    callback("Player labels need Drawing.Text: " .. tostring(message))
                end
            end)
        end
        return nil
    end
    return tag
end

-- Use the model bounds rather than a fixed R6-sized rectangle.
function Controller:_screenBounds(record, camera)
    local frame, size = record.Character:GetBoundingBox()
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                local corner = frame:PointToWorldSpace(Vector3.new(size.X * x / 2, size.Y * y / 2, size.Z * z / 2))
                local screen = camera:WorldToViewportPoint(corner)
                if screen.Z <= 0.05 then
                    return nil
                end
                left, top = math.min(left, screen.X), math.min(top, screen.Y)
                right, bottom = math.max(right, screen.X), math.max(bottom, screen.Y)
            end
        end
    end
    if right < 0 or left > camera.ViewportSize.X or bottom < 0 or top > camera.ViewportSize.Y or right - left < 1 or
        bottom - top < 1 then
        return nil
    end
    return {
        Left = left,
        Top = top,
        Right = right,
        Bottom = bottom
    }
end

function Controller:_drawOverlay(record, bounds, color, opacity, distance)
    if not bounds then
        hideLines(record.BoxOutline);
        hideLines(record.Box);
        hideLines(record.HealthBar)
        if record.Tag then
            record.Tag.Visible = false
        end
        return false
    end
    local settings = self.Settings
    local left, top, right, bottom = bounds.Left, bounds.Top, bounds.Right, bounds.Bottom
    local width, height = right - left, bottom - top
    local visible = false
    self:_resizeLines(record.Box, settings.BoxEnabled and 8 or 0)
    self:_resizeLines(record.BoxOutline, settings.BoxEnabled and settings.OutlineEnabled and 8 or 0, 1)
    if settings.BoxEnabled then
        local w, h = width * 0.25, height * 0.2
        local corners = {{left, top, left + w, top}, {left, top, left, top + h}, {right, top, right - w, top},
                         {right, top, right, top + h}, {left, bottom, left + w, bottom},
                         {left, bottom, left, bottom - h}, {right, bottom, right - w, bottom},
                         {right, bottom, right, bottom - h}}
        for index, corner in ipairs(corners) do
            local from, to = Vector3.new(corner[1], corner[2], 1), Vector3.new(corner[3], corner[4], 1)
            if record.BoxOutline[index] then
                self:_drawLine(record.BoxOutline[index], from, to, OUTLINE_COLOR, opacity, settings.Thickness + 2)
            end
            visible = self:_drawLine(record.Box[index], from, to, color, opacity) or visible
        end
    end
    self:_resizeLines(record.HealthBar, settings.HealthBarEnabled and 2 or 0)
    if settings.HealthBarEnabled then
        local maximum = record.Humanoid.MaxHealth
        local fraction = maximum > 0 and math.clamp(record.Humanoid.Health / maximum, 0, 1) or 0
        local healthColor = Color3.fromRGB(245, 93, 107):Lerp(Color3.fromRGB(103, 224, 172), fraction)
        self:_drawLine(record.HealthBar[1], Vector3.new(left - 6, top - 1, 1), Vector3.new(left - 6, bottom + 1, 1),
            OUTLINE_COLOR, opacity * 0.9, 4)
        visible = self:_drawLine(record.HealthBar[2], Vector3.new(left - 6, bottom, 1),
            Vector3.new(left - 6, bottom - height * fraction, 1), healthColor, opacity, 2) or visible
    end
    if settings.NamesEnabled or settings.DistanceEnabled then
        local tag = self:_tag(record)
        if tag then
            local labels = {}
            if settings.NamesEnabled then
                table.insert(labels, settings.UseDisplayNames and record.Player.DisplayName or record.Player.Name)
            end
            if settings.DistanceEnabled then
                table.insert(labels, tostring(math.floor(distance + 0.5)) .. " studs")
            end
            tag.Text = table.concat(labels, "  |  ")
            tag.Position = Vector2.new((left + right) / 2, top - settings.TextSize - 5)
            tag.Size, tag.Color, tag.Transparency = settings.TextSize, color, opacity
            tag.Outline, tag.OutlineColor, tag.Visible = settings.OutlineEnabled, OUTLINE_COLOR, true
            visible = true
        end
    else
        self:_removeTag(record)
    end
    return visible
end

function Controller:_renderPlayer(player, record, camera, origin)
    local settings, humanoid, root = self.Settings, record.Humanoid, record.Parts.HumanoidRootPart
    local character = record.Character
    if not root or not character or character ~= player.Character or not character.Parent or not humanoid or
        humanoid.Health <= 0 then
        hideRecord(record);
        return
    end
    if settings.TeamCheck and not LocalPlayer.Neutral and not player.Neutral and LocalPlayer.Team ~= nil and
        LocalPlayer.Team == player.Team then
        hideRecord(record);
        return
    end
    local delta = root.Position - origin
    local distanceSquared = delta:Dot(delta)
    local maxSquared = settings.MaxDistance * settings.MaxDistance
    if distanceSquared > maxSquared then
        hideRecord(record);
        return
    end
    local bounds
    if settings.BoxEnabled or settings.HealthBarEnabled or settings.NamesEnabled or settings.DistanceEnabled then
        bounds = self:_screenBounds(record, camera)
    end
    local projected, onScreen = camera:WorldToViewportPoint(root.Position)
    if not bounds and (not onScreen or projected.Z <= 0.05) then
        hideRecord(record);
        return
    end
    if settings.VisibleOnly then
        local head = record.Parts.Head or root
        local hit = workspace:Raycast(camera.CFrame.Position, head.Position - camera.CFrame.Position,
            self._raycastParams)
        if hit and (not hit.Instance or not hit.Instance:IsDescendantOf(character)) then
            hideRecord(record);
            return
        end
    end
    local opacity = settings.Opacity
    if settings.DistanceFade then
        local fadeStart = maxSquared * 0.65 * 0.65
        local fade = math.clamp((distanceSquared - fadeStart) / (maxSquared - fadeStart), 0, 1)
        opacity = opacity * (1 - fade * fade * (3 - 2 * fade))
    end
    if opacity <= 0.001 then
        hideRecord(record);
        return
    end
    local color = settings.Color
    if settings.UseTeamColors and not player.Neutral and player.Team ~= nil then
        color = player.TeamColor.Color
    end
    if settings.PulseEnabled then
        color = color:Lerp(WHITE, (math.sin(self._elapsed * settings.PulseSpeed) + 1) * 0.09)
    end
    if (settings.GroundRingEnabled or settings.HeadRingEnabled) and self._styleColor ~= color then
        self:_updateRingStyles(color)
        self._styleColor = color
    end
    local bones = BONES[humanoid.RigType] or {}
    local visible = false
    if record.Rig ~= humanoid.RigType then
        self:_clearDrawings(record);
        record.Rig = humanoid.RigType
    end
    self:_resizeLines(record.SkeletonOutline, settings.SkeletonEnabled and settings.OutlineEnabled and #bones or 0, 1)
    self:_resizeLines(record.Skeleton, settings.SkeletonEnabled and #bones or 0)
    local projectedParts = {}
    local function project(name)
        local part = record.Parts[name]
        if part and not projectedParts[name] then
            projectedParts[name] = camera:WorldToViewportPoint(part.Position)
        end
        return projectedParts[name]
    end
    for index, line in ipairs(record.Skeleton) do
        local pair = bones[index]
        local from, to = project(pair[1]), project(pair[2])
        if from and to then
            if record.SkeletonOutline[index] then
                self:_drawLine(record.SkeletonOutline[index], from, to, OUTLINE_COLOR, opacity * 0.8,
                    settings.Thickness + 1.8)
            end
            visible = self:_drawLine(line, from, to, color, opacity) or visible
        else
            line.Visible = false
            if record.SkeletonOutline[index] then
                record.SkeletonOutline[index].Visible = false
            end
        end
    end
    if settings.GroundRingEnabled then
        local offset = settings.GroundOffset
        if settings.AutoGroundOffset then
            offset = humanoid.HipHeight + root.Size.Y / 2
            if humanoid.RigType == Enum.HumanoidRigType.R6 then
                local leg = record.Parts["Left Leg"] or record.Parts["Right Leg"]
                if leg then
                    offset = offset + leg.Size.Y
                end
            end
        end
        visible = self:_drawRing(record.GroundRing, record.GroundProjection, camera,
            root.Position - Vector3.new(0, offset, 0), settings.GroundRadius, opacity) or visible
    end
    local head = record.Parts.Head
    if settings.HeadRingEnabled and head then
        local radius = settings.AutoHeadRadius and math.max(head.Size.X, head.Size.Y) * 0.55 or settings.HeadRadius
        visible = self:_drawRing(record.HeadRing, record.HeadProjection, camera,
            head.Position + Vector3.new(0, settings.HeadOffset, 0), radius, opacity, true) or visible
    else
        hideLines(record.HeadRing)
    end
    visible = self:_drawOverlay(record, bounds, color, opacity, math.sqrt(distanceSquared)) or visible
    record.Visible = visible
end

function Controller:_render()
    local camera = workspace.CurrentCamera
    local localCharacter = LocalPlayer.Character
    local root = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or (camera and camera.CFrame.Position)
    if not camera or not origin then
        for _, record in pairs(self._records) do
            hideRecord(record)
        end
        return
    end
    if self.Settings.VisibleOnly then
        if not self._raycastParams then
            self._raycastParams = RaycastParams.new();
            self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude;
            self._raycastParams.IgnoreWater = true
        end
        self._raycastParams.FilterDescendantsInstances = localCharacter and {localCharacter} or {}
    end
    self._styleColor = nil -- Ring animation changes even when the base color does not.
    for player, record in pairs(self._records) do
        self:_renderPlayer(player, record, camera, origin)
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
        table.insert(self._connections, Players.PlayerAdded:Connect(function(player)
            self:_track(player)
        end))
        table.insert(self._connections, Players.PlayerRemoving:Connect(function(player)
            self:_untrack(player)
        end))
        for _, player in ipairs(Players:GetPlayers()) do
            self:_track(player)
        end
        table.insert(self._connections, RunService.RenderStepped:Connect(function(deltaTime)
            self._elapsed = self._elapsed + deltaTime
            self._accumulator = self._accumulator + deltaTime
            local interval = 1 / self.Settings.RefreshRate
            if self._accumulator < interval then
                return
            end
            self._accumulator = self._accumulator % interval
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
    if patch.NamesEnabled == true or patch.DistanceEnabled == true then
        self._textUnavailable = false
    end
    for _, record in pairs(self._records) do
        if not nextSettings.BoxEnabled or not nextSettings.OutlineEnabled then
            self:_resizeLines(record.BoxOutline, 0)
        end
        if not nextSettings.BoxEnabled then
            self:_resizeLines(record.Box, 0)
        end
        if not nextSettings.HealthBarEnabled then
            self:_resizeLines(record.HealthBar, 0)
        end
        if not nextSettings.NamesEnabled and not nextSettings.DistanceEnabled then
            self:_removeTag(record)
        end
        if not nextSettings.SkeletonEnabled or not nextSettings.OutlineEnabled then
            self:_resizeLines(record.SkeletonOutline, 0)
        end
        if not nextSettings.SkeletonEnabled then
            self:_resizeLines(record.Skeleton, 0)
        end
        if not nextSettings.GroundRingEnabled then
            self:_resizeLines(record.GroundRing, 0)
        end
        if not nextSettings.HeadRingEnabled then
            self:_resizeLines(record.HeadRing, 0)
        end
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
        tracked = tracked + 1
        if record.Visible then
            visible = visible + 1
        end
    end
    return {
        Enabled = self.Enabled,
        TrackedPlayers = tracked,
        VisiblePlayers = visible,
        Drawings = self._drawingCount
    }
end

function Controller:Destroy()
    if self.Destroyed then
        return
    end
    self:SetEnabled(false)
    self.Destroyed = true
    self._onError, self._onWarning = nil, nil
    if environment[INSTANCE_KEY] == self then
        environment[INSTANCE_KEY] = nil
    end
end

function ESP.new(settings, onError, onWarning)
    assert(LocalPlayer, "ESP must run on the client.")
    local previous = environment[INSTANCE_KEY]
    if previous then
        previous:Destroy()
    end
    local self = setmetatable({
        Settings = ESP.GetDefaults(),
        Enabled = false,
        Destroyed = false,
        _records = {},
        _connections = {},
        _drawingCount = 0,
        _ringStyles = {},
        _elapsed = 0,
        _accumulator = 0,
        _onError = onError,
        _onWarning = onWarning
    }, Controller)
    local configured, configureError = pcall(self.UpdateSettings, self, settings or {})
    if not configured then
        self:Destroy()
        error(configureError, 0)
    end
    environment[INSTANCE_KEY] = self
    return self
end

local PRESETS = {
    Balanced = {
        SkeletonEnabled = true,
        GroundRingEnabled = true,
        HeadRingEnabled = true,
        NamesEnabled = true,
        DistanceEnabled = true,
        HealthBarEnabled = true,
        BoxEnabled = false,
        OutlineEnabled = true,
        PulseEnabled = false,
        RingAnimationEnabled = true,
        RefreshRate = 30,
        RingSegments = 24
    },
    Minimal = {
        SkeletonEnabled = true,
        GroundRingEnabled = false,
        HeadRingEnabled = false,
        NamesEnabled = false,
        DistanceEnabled = true,
        HealthBarEnabled = false,
        BoxEnabled = false,
        OutlineEnabled = true,
        PulseEnabled = false,
        RingAnimationEnabled = false,
        RefreshRate = 30,
        RingSegments = 16
    },
    Detailed = {
        SkeletonEnabled = true,
        GroundRingEnabled = true,
        HeadRingEnabled = true,
        NamesEnabled = true,
        DistanceEnabled = true,
        HealthBarEnabled = true,
        BoxEnabled = true,
        OutlineEnabled = true,
        PulseEnabled = false,
        RingAnimationEnabled = true,
        RefreshRate = 60,
        RingSegments = 32
    }
}

function ESP.Mount(context)
    local state, controls = context.State, context.Controls
    for key, value in pairs(ESP.GetDefaults()) do
        state[key] = value
    end
    local updating = false
    local status = context.Section:AddParagraph({
        Title = "ESP is off",
        Content = "Skeletons, upright head rings, and player information."
    })
    local function refresh()
        status:Set(state.Enabled and "ESP is on" or "ESP is off",
            state.Enabled and ("Updates at " .. state.RefreshRate .. " Hz / Range " .. state.MaxDistance ..
                " studs. Minimize the hub to keep your view clear.") or
                "Enable when ready. Closing, retrying, or reloading releases all ESP drawings.")
    end
    local controller = ESP.new(state, function(message)
        if not context.IsActive() then
            return
        end
        state.Enabled = false
        if controls.Enabled then
            controls.Enabled:Set(false)
        end
        context.Notify("ESP stopped", tostring(message), "Error")
        refresh()
    end, function(message)
        if context.IsActive() then
            context.Notify("ESP labels unavailable", message, "Warning")
        end
    end)
    context.AddCleanup(function()
        state.Enabled = false;
        controller:Destroy()
    end)
    local function apply(patch)
        controller:UpdateSettings(patch)
        for key, value in pairs(controller:GetSettings()) do
            state[key] = value
        end
        refresh()
    end
    local function syncControls()
        updating = true
        for key, value in pairs(state) do
            if controls[key] then
                controls[key]:Set(value)
            end
        end
        updating = false
    end
    controls.Enabled = context.Section:AddToggle({
        Title = "Enable ESP",
        Style = "Switch",
        Default = false,
        Callback = function(value)
            if updating then
                return
            end
            local ok, message = pcall(controller.SetEnabled, controller, value)
            state.Enabled = controller.Enabled
            if not ok then
                if controls.Enabled then
                    controls.Enabled:Set(false)
                end
                context.Notify("ESP unavailable", tostring(message), "Error")
            end
            refresh()
        end
    })
    controls.Preset = context.Section:AddDropdown({
        Title = "Visual preset",
        Values = {"Balanced", "Minimal", "Detailed"},
        Default = "Balanced",
        Callback = function(value)
            if updating then
                return
            end
            apply(assert(PRESETS[value], "Unknown ESP preset."))
            syncControls()
        end
    })
    -- Inline control pages are part of Elements; section cards do not expose AddSection.
    local pages = context.Section:AddTabs({})
    local visibility, style = pages:AddTab("Visibility"), pages:AddTab("Style")
    local rings, performance = pages:AddTab("Rings"), pages:AddTab("Performance")
    local function toggle(parent, key, title, description)
        controls[key] = parent:AddToggle({
            Title = title,
            Description = description,
            Style = "Switch",
            Default = state[key],
            Callback = function(value)
                if not updating then
                    apply({
                        [key] = value
                    })
                end
            end
        })
    end
    local function slider(parent, key, title, step, suffix, description)
        local limits = NUMBER_LIMITS[key]
        controls[key] = parent:AddSlider({
            Title = title,
            Description = description,
            Min = limits[1],
            Max = limits[2],
            Increment = step,
            Default = state[key],
            Suffix = suffix,
            Callback = function(value)
                if not updating then
                    apply({
                        [key] = value
                    })
                end
            end
        })
    end
    toggle(visibility, "TeamCheck", "Hide teammates", "Neutral players remain visible.")
    toggle(visibility, "VisibleOnly", "Visible players only", "Hide players behind geometry.")
    toggle(visibility, "SkeletonEnabled", "Skeletons")
    toggle(visibility, "BoxEnabled", "Corner boxes")
    toggle(visibility, "HealthBarEnabled", "Health bars")
    toggle(visibility, "NamesEnabled", "Player names")
    toggle(visibility, "DistanceEnabled", "Distance labels")
    toggle(visibility, "UseDisplayNames", "Use display names")
    slider(visibility, "MaxDistance", "Max distance", 50, " studs")
    controls.Color = style:AddColorPicker({
        Title = "ESP color",
        Default = state.Color,
        Callback = function(value)
            if not updating then
                apply({
                    Color = value
                })
            end
        end
    })
    toggle(style, "UseTeamColors", "Use team colors")
    toggle(style, "OutlineEnabled", "Dark outlines")
    toggle(style, "DistanceFade", "Fade near range limit")
    toggle(style, "PulseEnabled", "Color pulse")
    slider(style, "Thickness", "Line thickness", 0.1, "px")
    slider(style, "Opacity", "Opacity", 0.05, "")
    slider(style, "TextSize", "Label size", 1, "px")
    slider(style, "PulseSpeed", "Pulse speed", 0.1, "")
    toggle(rings, "GroundRingEnabled", "Ground ring")
    toggle(rings, "HeadRingEnabled", "Upright head ring", "Faces your camera and surrounds the head.")
    toggle(rings, "AutoGroundOffset", "Match the character's feet")
    toggle(rings, "AutoHeadRadius", "Match the head size")
    toggle(rings, "RingAnimationEnabled", "Animated ring highlight")
    slider(rings, "GroundRadius", "Ground radius", 0.1, " studs")
    slider(rings, "GroundOffset", "Manual feet offset", 0.1, " studs", "Used when matching the character's feet is off.")
    slider(rings, "HeadRadius", "Manual head radius", 0.05, " studs", "Used when matching the head size is off.")
    slider(rings, "HeadOffset", "Head height offset", 0.1, " studs")
    slider(rings, "RingSpeed", "Highlight speed", 0.05, " rev/s")
    slider(performance, "RefreshRate", "Update rate", 5, " Hz")
    slider(performance, "RingSegments", "Ring detail", 4, " segments")
    performance:AddLabel("Higher update rates and ring detail draw more often. The Balanced preset starts at 30 Hz.")
    controls.Reset = performance:AddButton({
        Title = "Reset visual settings",
        Callback = function()
            local defaults = ESP.GetDefaults()
            defaults.Enabled = controller.Enabled
            apply(defaults)
            syncControls()
            updating = true
            controls.Preset:Set("Balanced")
            updating = false
        end
    })
    refresh()
end

return ESP
