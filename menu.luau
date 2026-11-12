-- estyxq Hub / NextUI menu
-- Set ScriptBaseURL to the raw GitHub folder containing menu.luau and esp.luau.
-- Execute menu.luau to open the hub; ESP is fetched only when it is enabled.
local CONFIG = {
    Title = "estyxq Hub",
    Subtitle = "Your scripts. One home.",
    Folder = "estyxqHub",
    InstanceKey = "estyxqHub.Menu",
    ScriptName = "Universal",
    ScriptVersion = "1.0.0",
    MenuVersion = "2.0.0",
    LibraryURL = "https://diser.me/nextui/source.lua",

    ScriptBaseURL = "https://raw.githubusercontent.com/esteban-cz/estyxqHub/main/",
    Theme = "Amethyst",
    Transparent = true,
    Anonymous = false,
    Stars = true,
    ToggleKey = Enum.KeyCode.RightShift,
}

local environment = (type(getgenv) == "function" and getgenv()) or shared
local libraryEnvironment = (type(getgenv) == "function" and getgenv()) or _G
local previousSession = environment[CONFIG.InstanceKey]
local session = { Stopped = false, Starting = true, Connections = {} }
environment[CONFIG.InstanceKey] = session

local function isCurrentSession()
    return not session.Stopped and environment[CONFIG.InstanceKey] == session
end

function session:DestroyESP()
    local esp = self.ESP
    self.ESP = nil
    if esp then esp:Destroy() end
end

local function retireSession()
    session.Stopped = true
    session:DestroyESP()
    for _, connection in ipairs(session.Connections) do connection:Disconnect() end
    table.clear(session.Connections)
    if environment[CONFIG.InstanceKey] == session then environment[CONFIG.InstanceKey] = nil end
end

function session:Destroy()
    retireSession()
    if self.Starting and not self.Window then return end
    local library = self.Library
    self.Library = nil
    if library then library:Destroy() end
end

if type(previousSession) == "table" and type(previousSession.Destroy) == "function" then
    local cleaned, message = pcall(previousSession.Destroy, previousSession)
    if not cleaned then
        session:Destroy()
        error("Could not replace the previous hub: " .. tostring(message), 0)
    end
end

local function createMenu()
    local source = game:HttpGet(CONFIG.LibraryURL)
    if not isCurrentSession() then return nil end
    local chunk, compileError = loadstring(source)
    if not chunk then error(compileError, 0) end
    local NextUI = chunk()
    assert(type(NextUI) == "table" and type(NextUI.CreateWindow) == "function", "NextUI did not load correctly.")
    session.Library = NextUI

    -- NextUI's X button and reload guard both call this method.
    local nativeDestroy = NextUI.Destroy
    function NextUI:Destroy()
        if self.Destroyed then return end
        self.Destroyed = true
        if session.Window then session.Window.Destroyed = true end
        retireSession()
        session.Library = nil
        local activeLibrary = libraryEnvironment.NextUI
        local destroyed, message = pcall(nativeDestroy, self)
        -- A retired session must not clear a newer library's global registration.
        if activeLibrary and activeLibrary ~= self then libraryEnvironment.NextUI = activeLibrary end
        if not destroyed then error(message, 0) end
    end
    if not isCurrentSession() then return nil end

    NextUI.TitleCase = false
    NextUI.TextScale = 1.05
    NextUI.TipLength = 30
    NextUI.ButtonTipLength = 30
    NextUI.ConfigFolder = CONFIG.Folder

    local Window = NextUI:CreateWindow({
        Title = CONFIG.Title,
        SubTitle = CONFIG.Subtitle .. "  /  v" .. CONFIG.ScriptVersion,
        Size = Vector2.new(880, 620),
        MinSize = Vector2.new(650, 460),
        TabWidth = 185,
        Theme = CONFIG.Theme,
        Glass = CONFIG.Transparent,
        Stars = CONFIG.Stars,
        StarCount = 2,
        Resizable = true,
        Search = true,
        SearchWidth = 160,
        Collapsible = true,
        Profile = true,
        ThemePicker = true,
        ToggleKey = CONFIG.ToggleKey,
        MobileButton = false, -- The named reopen pill below handles both desktop and touch.
    })
    session.Window = Window
    if not isCurrentSession() then return nil end

    function Window:Open() self:Toggle(true) end
    function Window:Close() self:Toggle(false) end
    function Window:Destroy() NextUI:Destroy() end

    local Menu = {
        Config = CONFIG, Library = NextUI, NextUI = NextUI, Window = Window,
        Tabs = {}, Controls = {},
        State = {
            Theme = CONFIG.Theme, Transparent = CONFIG.Transparent, Anonymous = CONFIG.Anonymous,
            Stars = CONFIG.Stars, ToggleKey = CONFIG.ToggleKey,
            Demo = { Enabled = false, Intensity = 50, Preset = "Balanced" },
            ESP = {
                Enabled = false, SkeletonEnabled = true, GroundRingEnabled = true, HeadRingEnabled = true,
                TeamCheck = true, MaxDistance = 3000, Color = Color3.fromRGB(179, 154, 255),
                OutlineEnabled = true, DistanceFade = true, PulseEnabled = true, PulseSpeed = 1.5,
                RingAnimationEnabled = true, RingSpeed = 0.2, Thickness = 1.5, Opacity = 0.9,
                RefreshRate = 60, RingSegments = 40, GroundRadius = 2.5, GroundOffset = 3,
                HeadRadius = 0.6, HeadOffset = 0,
            },
        },
    }
    function Menu.Destroy() session:Destroy() end
    function Menu.Notify(title, content, kind)
        if not isCurrentSession() then return nil end
        return NextUI:Notify({ Title = title, Content = content, Type = kind or "Info", Duration = 4 })
    end

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(session.Connections, connection)
        return connection
    end

    -- This pill belongs to NextUI's GUI, so unloading also removes it.
    local pill = Instance.new("TextButton")
    pill.Name = "EstyxqReopen"
    pill.AnchorPoint = Vector2.new(0.5, 0)
    pill.Position = UDim2.new(0.5, 0, 0, 22)
    pill.Size = UDim2.fromOffset(164, 36)
    pill.Text = CONFIG.Title
    pill.Font = Enum.Font.BuilderSansBold
    pill.TextSize = 14
    pill.AutoButtonColor = false
    pill.BorderSizePixel = 0
    pill.Visible = false
    pill.ZIndex = 100
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = pill
    local stroke = Instance.new("UIStroke")
    stroke.Thickness, stroke.Transparency = 1, 0.25
    stroke.Parent = pill
    pill.Parent = Window.Gui
    Menu.Pill = pill

    local function paintPill()
        pill.BackgroundColor3 = NextUI.Theme.Card
        pill.TextColor3 = NextUI.Theme.Text
        stroke.Color = NextUI.Theme.Accent
    end
    paintPill()
    local nativeTheme = NextUI.SetTheme
    function NextUI:SetTheme(name, instant)
        local result = nativeTheme(self, name, instant)
        Menu.State.Theme = self.ThemeName
        paintPill()
        return result
    end
    local nativeToggle = Window.Toggle
    function Window:Toggle(state)
        if self.Destroyed then return end
        nativeToggle(self, state)
        pill.Visible = not self.Visible and not self._intro
    end

    local UIS = game:GetService("UserInputService")
    local press, pressPosition, startPosition, dragged
    connect(pill.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            press, pressPosition, startPosition, dragged = input, input.Position, pill.Position, false
        end
    end)
    connect(UIS.InputChanged, function(input)
        if not press or not (input == press or input.UserInputType == Enum.UserInputType.MouseMovement) then return end
        local delta = input.Position - pressPosition
        if not dragged and delta.Magnitude <= 8 then return end
        dragged = true
        local viewport = Window.Gui.AbsoluteSize
        local x = startPosition.X.Scale * viewport.X + startPosition.X.Offset + delta.X
        local y = startPosition.Y.Scale * viewport.Y + startPosition.Y.Offset + delta.Y
        pill.Position = UDim2.fromOffset(
            math.clamp(x, 82, math.max(82, viewport.X - 82)),
            math.clamp(y, 8, math.max(8, viewport.Y - 44))
        )
    end)
    connect(UIS.InputEnded, function(input)
        if input == press then press = nil end
    end)
    connect(pill.Activated, function()
        if not dragged then Window:Toggle(true) end
    end)
    connect(pill.MouseEnter, function() pill.BackgroundColor3 = NextUI.Theme.Hover end)
    connect(pill.MouseLeave, paintPill)

    -- NextUI's native profile has no runtime visibility method. Hide its complete footer,
    -- including avatar and hover labels, when the privacy switch is enabled.
    local profile
    for _, object in ipairs(Window.Gui:GetDescendants()) do
        if object:IsA("ImageLabel") and object.Image:find("rbxthumb://type=AvatarHeadShot", 1, true) == 1 then
            profile = object.Parent
            break
        end
    end
    local function setAnonymous(value)
        Menu.State.Anonymous = value
        if profile then profile.Visible = not value end
    end
    setAnonymous(CONFIG.Anonymous)

    Window:AddCategory("Workspace")
    Menu.Tabs.Overview = Window:AddTab("Overview", "home")
    Menu.Tabs.Playground = Window:AddTab("Playground", "sliders-horizontal")
    Menu.Tabs.ESP = Window:AddTab("ESP", "eye")
    Window:AddCategory("Preferences")
    Menu.Tabs.Settings = Window:AddTab("Settings", "settings-2")
    local Overview, Playground, ESPTab, Settings = Menu.Tabs.Overview, Menu.Tabs.Playground, Menu.Tabs.ESP, Menu.Tabs.Settings

    local welcome = Overview:AddSection({ Title = "Welcome home", Icon = "home", Side = "Full" })
    welcome:AddTitle(CONFIG.Title)
    welcome:AddLabel(CONFIG.Subtitle)
    welcome:AddParagraph({ Title = CONFIG.ScriptName, Content = "Version " .. CONFIG.ScriptVersion .. " / All your tools, one familiar space." })
    local actions = Overview:AddSection({ Title = "Start here", Icon = "compass", Side = "Left" })
    actions:AddButton({ Title = "Open ESP", Description = "Skeletons, rings, and visual controls.", Callback = function() ESPTab:Select() end })
    actions:AddButton({ Title = "Explore the playground", Description = "Try the sample controls.", Callback = function() Playground:Select() end })
    actions:AddButton({ Title = "Make it yours", Callback = function() Settings:Select() end })
    local essentials = Overview:AddSection({ Title = "Within reach", Icon = "keyboard", Side = "Right" })
    local shortcut = essentials:AddParagraph({ Title = "Menu shortcut", Content = "Press " .. CONFIG.ToggleKey.Name .. " to show or hide the hub." })
    essentials:AddParagraph({ Title = "Small when you need it", Content = "Minimize to the estyxq Hub pill. Drag it anywhere, then tap to return." })
    essentials:AddParagraph({ Title = "ESP stays with you", Content = "Minimizing keeps ESP active. Closing or reloading the hub cleans it up." })

    local samples = Playground:AddSection({ Title = "Sample feature", Icon = "sliders-horizontal", Side = "Left" })
    local previewCard = Playground:AddSection({ Title = "Live preview", Icon = "activity", Side = "Right" })
    local preview
    local function demoSummary()
        local demo = Menu.State.Demo
        return string.format("%s / %s / Intensity %d%%", demo.Enabled and "Enabled" or "Disabled", demo.Preset, demo.Intensity)
    end
    local function refreshPreview() if preview then preview:Set("Current settings", demoSummary()) end end
    Menu.Controls.DemoEnabled = samples:AddToggle({ Title = "Enable sample feature", Description = "A starting point for your own on / off feature.", Style = "Switch", Default = false,
        Callback = function(value) Menu.State.Demo.Enabled = value; refreshPreview() end })
    Menu.Controls.DemoIntensity = samples:AddSlider({ Title = "Intensity", Min = 0, Max = 100, Default = 50, Increment = 1, Suffix = "%",
        Callback = function(value) Menu.State.Demo.Intensity = value; refreshPreview() end })
    Menu.Controls.DemoPreset = samples:AddDropdown({ Title = "Preset", Values = { "Balanced", "Focused", "Relaxed" }, Default = "Balanced",
        Callback = function(value) Menu.State.Demo.Preset = value; refreshPreview() end })
    preview = previewCard:AddParagraph({ Title = "Current settings", Content = demoSummary() })
    Menu.Controls.DemoPreview = preview
    previewCard:AddLabel("These samples only change the preview.")
    previewCard:AddButton({ Title = "Preview notification", Callback = function() Menu.Notify("A little update", demoSummary()) end })

    local espMain = ESPTab:AddSection({ Title = "Universal ESP", Icon = "eye", Side = "Full" })
    local espStatus = espMain:AddParagraph({ Title = "ESP is off", Content = "Skeletons and rings for R6 and R15 characters." })
    Menu.Controls.ESP = {}
    local espLoading = false
    local function refreshESPStatus()
        espStatus:Set(Menu.State.ESP.Enabled and "ESP is on" or "ESP is off", Menu.State.ESP.Enabled
            and "Changes apply immediately. Minimize the hub to keep your view clear."
            or "Skeletons and rings for R6 and R15 characters.")
    end
    local function reportESPError(message)
        if not isCurrentSession() then return end
        Menu.State.ESP.Enabled = false
        if session.ESP and not session.ESP.Destroyed then session.ESP:SetEnabled(false) end
        if Menu.Controls.ESP.Enabled then Menu.Controls.ESP.Enabled:Set(false) end
        refreshESPStatus()
        Menu.Notify("ESP unavailable", tostring(message), "Error")
    end
    local function espSourceURL()
        if CONFIG.ESPSourceURL ~= "" then return CONFIG.ESPSourceURL end
        if CONFIG.ScriptBaseURL ~= "" then return CONFIG.ScriptBaseURL:gsub("/+$", "") .. "/esp.luau" end
        return nil
    end
    local function ensureESP()
        if session.ESP and not session.ESP.Destroyed then return session.ESP end
        local module = environment["estyxqHub.ESPModule"]
        local compatible = type(module) == "table" and type(module.new) == "function"
            and type(module.GetDefaults) == "function" and module.GetDefaults().OutlineEnabled ~= nil
        local url = espSourceURL()
        if url then
            local espSource = game:HttpGet(url)
            if not isCurrentSession() then return nil end
            local espChunk, message = loadstring(espSource)
            if not espChunk then error(message, 0) end
            module = espChunk()
        elseif not compatible then
            error("Run the updated ESP script first, or configure its source URL.", 0)
        end
        if not isCurrentSession() then return nil end
        assert(type(module) == "table" and type(module.new) == "function", "The ESP source did not return an ESP module.")
        local options = table.clone(Menu.State.ESP)
        options.Enabled = false
        local controller
        controller = module.new(options, function(message)
            if session.ESP == controller then reportESPError(message) end
        end)
        if not isCurrentSession() then controller:Destroy(); return nil end
        session.ESP, Menu.ESP = controller, controller
        return controller
    end
    local function updateESPSetting(key, value)
        Menu.State.ESP[key] = value
        if session.ESP and not session.ESP.Destroyed then
            local applied, message = pcall(session.ESP.UpdateSettings, session.ESP, { [key] = value })
            if not applied then reportESPError(message) end
        end
    end
    Menu.Controls.ESP.Enabled = espMain:AddToggle({ Title = "Enable ESP", Description = "Show skeletons and rings for other players.", Style = "Switch", Default = false,
        Callback = function(enabled)
            Menu.State.ESP.Enabled = enabled
            if not enabled then
                if session.ESP and not session.ESP.Destroyed then session.ESP:SetEnabled(false) end
                refreshESPStatus()
                return
            end
            if espLoading then return end
            espLoading = true
            espStatus:Set("Loading ESP...", "Getting your visual tools ready.")
            local started, message = pcall(function()
                local controller = ensureESP()
                if controller then controller:UpdateSettings(Menu.State.ESP) end
            end)
            espLoading = false
            if not isCurrentSession() then return end
            if not started then reportESPError(message) else refreshESPStatus() end
        end })
    local function espToggle(parent, key, title, description)
        Menu.Controls.ESP[key] = parent:AddToggle({ Title = title, Description = description, Default = Menu.State.ESP[key], Style = "Switch", Flag = "esp_" .. key,
            Callback = function(value) updateESPSetting(key, value) end })
    end
    local function espSlider(parent, key, title, minimum, maximum, step, description, suffix)
        Menu.Controls.ESP[key] = parent:AddSlider({ Title = title, Description = description, Min = minimum, Max = maximum, Default = Menu.State.ESP[key], Increment = step, Suffix = suffix, Flag = "esp_" .. key,
            Callback = function(value) updateESPSetting(key, value) end })
    end
    local visibility = ESPTab:AddSection({ Title = "Visibility", Icon = "eye", Side = "Left", Collapsible = true })
    espToggle(visibility, "SkeletonEnabled", "Skeletons")
    espToggle(visibility, "GroundRingEnabled", "Ground rings")
    espToggle(visibility, "HeadRingEnabled", "Head rings")
    espToggle(visibility, "TeamCheck", "Hide teammates", "Neutral players remain visible.")
    espToggle(visibility, "DistanceFade", "Fade distant players")
    espSlider(visibility, "MaxDistance", "Maximum distance", 50, 10000, 50, nil, " studs")
    local appearance = ESPTab:AddSection({ Title = "Appearance", Icon = "palette", Side = "Right", Collapsible = true })
    Menu.Controls.ESP.Color = appearance:AddColorPicker({ Title = "ESP color", Default = Menu.State.ESP.Color, Flag = "esp_Color",
        Callback = function(value) updateESPSetting("Color", value) end })
    espToggle(appearance, "OutlineEnabled", "Skeleton outline")
    espToggle(appearance, "PulseEnabled", "Pulse color")
    espSlider(appearance, "PulseSpeed", "Pulse speed", 0.1, 10, 0.1)
    espSlider(appearance, "Thickness", "Line thickness", 0.5, 5, 0.1)
    espSlider(appearance, "Opacity", "Opacity", 0, 1, 0.05)
    local rings = ESPTab:AddSection({ Title = "Rings", Icon = "circle", Side = "Left", Collapsible = true, Collapsed = true })
    espToggle(rings, "RingAnimationEnabled", "Moving highlight")
    espSlider(rings, "RingSpeed", "Highlight speed", 0.05, 1.5, 0.05)
    espSlider(rings, "GroundRadius", "Ground radius", 0.5, 8, 0.1, nil, " studs")
    espSlider(rings, "GroundOffset", "Ground depth", 0, 8, 0.1, nil, " studs")
    espSlider(rings, "HeadRadius", "Head radius", 0.2, 3, 0.1, nil, " studs")
    espSlider(rings, "HeadOffset", "Head height", -2, 4, 0.1, nil, " studs")
    local performance = ESPTab:AddSection({ Title = "Performance", Icon = "gauge", Side = "Right", Collapsible = true, Collapsed = true })
    espSlider(performance, "RefreshRate", "Refresh rate", 15, 120, 1, nil, " Hz")
    espSlider(performance, "RingSegments", "Ring detail", 12, 64, 1, "Fewer segments reduce drawing work.")

    local themeCard = Settings:AddSection({ Title = "Appearance", Icon = "palette", Side = "Left" })
    Menu.Controls.Theme = themeCard:AddDropdown({ Title = "Color theme", Values = table.clone(NextUI.ThemeOrder), Default = CONFIG.Theme, Flag = "theme",
        Callback = function(value) NextUI:SetTheme(value) end })
    Menu.Controls.Transparency = themeCard:AddToggle({ Title = "Glass background", Style = "Switch", Default = CONFIG.Transparent, Flag = "glass",
        Callback = function(value) NextUI:SetGlass(value); Menu.State.Transparent = value end })
    Menu.Controls.Stars = themeCard:AddToggle({ Title = "Background stars", Style = "Switch", Default = CONFIG.Stars,
        Callback = function(value) Window:SetStars(value); Menu.State.Stars = value end })
    local preferences = Settings:AddSection({ Title = "Your space", Icon = "user", Side = "Right" })
    Menu.Controls.Anonymous = preferences:AddToggle({ Title = "Hide profile", Description = "Hide your name and avatar in the sidebar.", Style = "Switch", Default = CONFIG.Anonymous, Callback = setAnonymous })
    Menu.Controls.ToggleKey = preferences:AddKeybind({ Title = "Menu shortcut", Default = CONFIG.ToggleKey, MenuKey = true,
        ChangedCallback = function(key)
            Menu.State.ToggleKey = key
            local label = typeof(key) == "EnumItem" and key.Name or tostring(key)
            shortcut:Set("Menu shortcut", "Press " .. label .. " to show or hide the hub.")
        end })
    local about = Settings:AddSection({ Title = "About", Icon = "info", Side = "Full" })
    about:AddParagraph({ Title = CONFIG.Title .. " / " .. CONFIG.ScriptName,
        Content = string.format("Script v%s  /  Menu v%s  /  NextUI v%s", CONFIG.ScriptVersion, CONFIG.MenuVersion, tostring(NextUI.Version)) })
    about:AddButton({ Title = "Unload hub", Description = "Close the menu and stop its ESP.", Hold = 1, Callback = Menu.Destroy })

    Overview:Select()
    return Menu
end

local created, menuOrError = pcall(createMenu)
session.Starting = false
local wasCurrent = isCurrentSession()
if not created or not wasCurrent then
    session:Destroy()
    if not created and wasCurrent then error(menuOrError, 0) end
    return nil
end
return menuOrError
