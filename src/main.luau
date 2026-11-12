local launchOptions = ...
local CONFIG = {
    Title = "estyxq Hub",
    Subtitle = "Your scripts. One home.",
    Folder = "estyxq-hub",
    InstanceKey = "estyxq-hub.Menu",
    ScriptName = "Universal",
    ScriptVersion = "1.0.0",
    MenuVersion = "2.2.0",
    LibraryURL = "", -- Optional override. Defaults to ScriptBaseURL .. "menu.luau".

    ScriptBaseURL = "https://raw.githubusercontent.com/esteban-cz/estyxq-hub/main/src/",
    Theme = "Amethyst",
    Transparent = true,
    Anonymous = false,
    Stars = true,
    ToggleKey = Enum.KeyCode.RightShift
}

-- Arguments are local to this execution; concurrent loaders cannot overwrite each other's URLs.
if launchOptions ~= nil then
    assert(type(launchOptions) == "table", "Hub launch options must be a table.")
    for _, key in ipairs({"ScriptBaseURL", "LibraryURL"}) do
        if launchOptions[key] ~= nil then
            assert(type(launchOptions[key]) == "string", key .. " must be a string.")
            CONFIG[key] = launchOptions[key]
        end
    end
end

local sharedTabs = launchOptions and launchOptions.SharedTabs or {}
assert(type(sharedTabs) == "table", "SharedTabs must be a table.")
local readSource = launchOptions and launchOptions.ReadSource
assert(readSource == nil or type(readSource) == "function", "ReadSource must be a function.")
local function fetchSource(filename, url)
    if readSource then
        return readSource(filename, url)
    end
    return game:HttpGet(url)
end
local gameModule = launchOptions and launchOptions.GameModule
if gameModule then
    assert(type(gameModule) == "table" and type(gameModule.Tabs) == "table", "Invalid game module.")
    for _, field in ipairs({"Id", "Name", "Version", "Subtitle"}) do
        assert(type(gameModule[field]) == "string" and gameModule[field] ~= "", "Game module needs " .. field .. ".")
    end
    assert(gameModule.Id:match("^[%w_-]+$"), "Game Id must use letters, numbers, underscores, or hyphens.")
    CONFIG.ScriptName, CONFIG.ScriptVersion, CONFIG.Subtitle = gameModule.Name, gameModule.Version, gameModule.Subtitle
    CONFIG.Folder = CONFIG.Folder .. "-" .. gameModule.Id
end

local function sourceURL(filename, override)
    local url = (override or ""):match("^%s*(.-)%s*$")
    if url ~= "" then
        return url
    end
    local base = (CONFIG.ScriptBaseURL or ""):match("^%s*(.-)%s*$")
    if base ~= "" then
        local path = filename:gsub("[^%w%-%._~/]", function(char)
            return string.format("%%%02X", string.byte(char))
        end)
        return base:gsub("/+$", "") .. "/" .. path
    end
    return nil
end

local environment = (type(getgenv) == "function" and getgenv()) or shared
local libraryEnvironment = (type(getgenv) == "function" and getgenv()) or _G
-- Download and compile required framework files before retiring a working hub.
local loadGuard = launchOptions and launchOptions.IsCurrentLoad
assert(loadGuard == nil or type(loadGuard) == "function", "IsCurrentLoad must be a function.")
local START_KEY = CONFIG.InstanceKey .. ".Starting"
local startup = {}
environment[START_KEY] = startup
local function ownsStartup()
    return environment[START_KEY] == startup and (not loadGuard or loadGuard())
end
local function prepare(filename, override)
    local url = sourceURL(filename, override)
    assert(url, "Configure a source URL for " .. filename .. ".")
    local source = fetchSource(filename, url)
    if not ownsStartup() then
        return nil
    end
    local chunk, message = loadstring(source, "estyxq-hub/" .. filename)
    assert(chunk, message)
    return chunk
end
local prepared, libraryChunk, Runtime = pcall(function()
    local ui = prepare("menu.luau", CONFIG.LibraryURL)
    if not ownsStartup() then
        return nil
    end
    local runtimeChunk = prepare("core/runtime.luau")
    if not ownsStartup() then
        return nil
    end
    local runtime = runtimeChunk()
    assert(type(runtime) == "table" and type(runtime.newSection) == "function", "Invalid hub runtime module.")
    return ui, runtime
end)
local wasPreparedOwner = ownsStartup()
if environment[START_KEY] == startup then
    environment[START_KEY] = nil
end
if not wasPreparedOwner then
    return nil
end
if not prepared then
    error(libraryChunk, 0)
end

local previousSession = environment[CONFIG.InstanceKey]
local session = {
    Stopped = false,
    Starting = true,
    Connections = {},
    Cleanups = {}
}
environment[CONFIG.InstanceKey] = session

local function isCurrentSession()
    return not session.Stopped and environment[CONFIG.InstanceKey] == session
end

local function retireSession()
    session.Stopped = true
    local cleanups = session.Cleanups
    session.Cleanups = {}
    for index = #cleanups, 1, -1 do
        local cleaned, message = pcall(cleanups[index])
        if not cleaned then
            warn("[estyxq Hub cleanup] " .. tostring(message))
        end
    end
    for _, connection in ipairs(session.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(session.Connections)
    if environment[CONFIG.InstanceKey] == session then
        environment[CONFIG.InstanceKey] = nil
    end
end

function session:Destroy()
    retireSession()
    if self.Starting and not self.Window then
        return
    end
    local library = self.Library
    self.Library = nil
    if library then
        library:Destroy()
    end
end

if type(previousSession) == "table" and type(previousSession.Destroy) == "function" then
    local cleaned, message = pcall(previousSession.Destroy, previousSession)
    if not cleaned then
        session:Destroy()
        error("Could not replace the previous hub: " .. tostring(message), 0)
    end
end

local function createMenu()
    local NextUI = libraryChunk()
    assert(type(NextUI) == "table" and type(NextUI.CreateWindow) == "function", "NextUI did not load correctly.")
    session.Library = NextUI

    -- NextUI's X button and reload guard both call this method.
    local nativeDestroy = NextUI.Destroy
    function NextUI:Destroy()
        if self.Destroyed then
            return
        end
        self.Destroyed = true
        if session.Window then
            session.Window.Destroyed = true
        end
        retireSession()
        session.Library = nil
        local activeLibrary = libraryEnvironment.NextUI
        local destroyed, message = pcall(nativeDestroy, self)
        -- A retired session must not clear a newer library's global registration.
        if activeLibrary and activeLibrary ~= self then
            libraryEnvironment.NextUI = activeLibrary
        end
        if not destroyed then
            error(message, 0)
        end
    end
    if not isCurrentSession() then
        return nil
    end

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
        ThemePicker = false, -- The theme picker is built into the Settings tab.
        ToggleKey = CONFIG.ToggleKey,
        MobileButton = false, -- The named reopen pill below handles both desktop and touch.
        Intro = true
    })
    session.Window = Window
    if not isCurrentSession() then
        return nil
    end

    function Window:Open()
        self:Toggle(true)
    end
    function Window:Close()
        self:Toggle(false)
    end
    function Window:Destroy()
        NextUI:Destroy()
    end

    local Menu = {
        Config = CONFIG,
        Library = NextUI,
        NextUI = NextUI,
        Window = Window,
        Tabs = {},
        Sections = {},
        Controls = {
            Game = {},
            Shared = {}
        },
        Game = gameModule,
        State = {
            Theme = CONFIG.Theme,
            Transparent = CONFIG.Transparent,
            Anonymous = CONFIG.Anonymous,
            Stars = CONFIG.Stars,
            ToggleKey = CONFIG.ToggleKey,
            Game = {},
            Shared = {}
        }
    }
    function Menu.Destroy()
        session:Destroy()
    end
    function Menu.Notify(title, content, kind)
        if not isCurrentSession() then
            return nil
        end
        return NextUI:Notify({
            Title = title,
            Content = content,
            Type = kind or "Info",
            Duration = 4
        })
    end

    function Menu.AddCleanup(callback)
        assert(type(callback) == "function", "Cleanup must be a function.")
        if isCurrentSession() then
            table.insert(session.Cleanups, callback)
        else
            local cleaned, message = pcall(callback)
            if not cleaned then
                warn("[estyxq Hub cleanup] " .. tostring(message))
            end
        end
    end

    function Menu.IsActive()
        return isCurrentSession()
    end

    function Menu.LoadModule(filename, override, isActive)
        assert(isCurrentSession(), "This hub session has been unloaded.")
        local url = sourceURL(filename, override)
        assert(url, "Configure a source URL for " .. filename .. ".")
        local function active()
            return isCurrentSession() and (not isActive or isActive())
        end
        if not active() then
            return nil
        end
        local moduleSource = fetchSource(filename, url)
        if not active() then
            return nil
        end
        local moduleChunk, message = loadstring(moduleSource, "estyxq-hub/" .. filename)
        if not moduleChunk then
            error(message, 0)
        end
        local module = moduleChunk()
        if not active() then
            return nil
        end
        return module
    end

    local function connect(signal, callback)
        assert(isCurrentSession(), "This hub session has been unloaded.")
        local connection = signal:Connect(function(...)
            if isCurrentSession() then
                callback(...)
            end
        end)
        table.insert(session.Connections, connection)
        return connection
    end
    Menu.Connect = connect

    local featureSections = {}

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
        if self.Destroyed then
            return
        end
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
        if not press or not (input == press or input.UserInputType == Enum.UserInputType.MouseMovement) then
            return
        end
        local delta = input.Position - pressPosition
        if not dragged and delta.Magnitude <= 8 then
            return
        end
        dragged = true
        local viewport = Window.Gui.AbsoluteSize
        local x = startPosition.X.Scale * viewport.X + startPosition.X.Offset + delta.X
        local y = startPosition.Y.Scale * viewport.Y + startPosition.Y.Offset + delta.Y
        pill.Position = UDim2.fromOffset(math.clamp(x, 82, math.max(82, viewport.X - 82)),
            math.clamp(y, 8, math.max(8, viewport.Y - 44)))
    end)
    connect(UIS.InputEnded, function(input)
        if input == press then
            press = nil
        end
    end)
    connect(pill.Activated, function()
        if not dragged then
            Window:Toggle(true)
        end
    end)
    connect(pill.MouseEnter, function()
        pill.BackgroundColor3 = NextUI.Theme.Hover
    end)
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
        if profile then
            profile.Visible = not value
        end
    end
    setAnonymous(CONFIG.Anonymous)

    local function addTabs(tabs, category, area)
        if #tabs == 0 then
            return
        end
        Window:AddCategory(category)
        for _, tab in ipairs(tabs) do
            assert(not Menu.Tabs[tab.Title] and not table.find({"Overview", "Settings"}, tab.Title),
                "Duplicate tab title: " .. tab.Title)
            local page = Window:AddTab(tab.Title, tab.Icon or "layout")
            Menu.Tabs[tab.Title] = page
            if area == "Game" then
                Menu.GameTab = Menu.GameTab or page
            end
            Menu.State[area][tab.Title], Menu.Controls[area][tab.Title], Menu.Sections[tab.Title] = {}, {}, {}
            for index, section in ipairs(tab.Sections) do
                local boundary = Runtime.newSection({
                    IsActive = Menu.IsActive,
                    Library = NextUI,
                    Load = function(isActive)
                        return Menu.LoadModule(section.File, nil, isActive)
                    end,
                    OnError = function(message)
                        warn("[estyxq Hub / " .. tab.Title .. " / " .. section.Title .. "] " .. message)
                    end,
                    CreateCard = function(definition)
                        local card = page:AddSection({
                            Title = section.Title,
                            Icon = definition.Icon or "sliders-horizontal",
                            Side = definition.Side or (index % 2 == 1 and "Left" or "Right"),
                            Collapsible = definition.Collapsible,
                            Collapsed = definition.Collapsed
                        })
                        card.Frame.LayoutOrder = index
                        return card
                    end,
                    Context = function(scope, card)
                        local state, controls = {}, {}
                        Menu.State[area][tab.Title][section.Title], Menu.Controls[area][tab.Title][section.Title] =
                            state, controls
                        return {
                            Hub = Menu,
                            Library = NextUI,
                            Window = Window,
                            Tab = page,
                            Section = card,
                            State = state,
                            Controls = controls,
                            Game = gameModule,
                            Area = area,
                            Source = section.File,
                            GameState = Menu.State.Game,
                            SharedState = Menu.State.Shared,
                            PlaceId = game.PlaceId,
                            GameId = game.GameId,
                            Scope = scope,
                            Connect = scope.Connect,
                            AddCleanup = scope.AddCleanup,
                            IsActive = scope.IsActive,
                            Guard = scope.Guard,
                            Spawn = scope.Spawn,
                            Defer = scope.Defer,
                            Delay = scope.Delay,
                            LoadModule = function(filename, override)
                                return Menu.LoadModule(filename, override, scope.IsActive)
                            end,
                            Notify = function(...)
                                if scope.IsActive() then
                                    return Menu.Notify(...)
                                end
                            end
                        }
                    end
                })
                Menu.Sections[tab.Title][section.Title] = boundary
                Menu.AddCleanup(boundary.Destroy)
                table.insert(featureSections, boundary)
            end
        end
    end
    Window:AddCategory("Workspace")
    Menu.Tabs.Overview = Window:AddTab("Overview", "home")
    if gameModule then
        addTabs(gameModule.Tabs, gameModule.Name, "Game")
    end
    addTabs(sharedTabs, "Universal", "Shared")
    Window:AddCategory("Preferences")
    Menu.Tabs.Settings = Window:AddTab("Settings", "settings-2")
    local Overview, Settings = Menu.Tabs.Overview, Menu.Tabs.Settings

    local welcome = Overview:AddSection({
        Title = "Welcome home",
        Icon = "home",
        Side = "Full"
    })
    welcome:AddTitle(CONFIG.Title)
    welcome:AddLabel(CONFIG.Subtitle)
    welcome:AddParagraph({
        Title = CONFIG.ScriptName,
        Content = "Version " .. CONFIG.ScriptVersion .. " / All your tools, one familiar space."
    })
    local actions = Overview:AddSection({
        Title = "Start here",
        Icon = "compass",
        Side = "Left"
    })
    if Menu.GameTab then
        actions:AddButton({
            Title = "Open game tools",
            Description = CONFIG.ScriptName,
            Callback = function()
                Menu.GameTab:Select()
            end
        })

    end
    if Menu.Tabs.Misc then
        actions:AddButton({
            Title = "Open Misc",
            Callback = function()
                Menu.Tabs.Misc:Select()
            end
        })
    end
    actions:AddButton({
        Title = "Make it yours",
        Callback = function()
            Settings:Select()
        end
    })
    local essentials = Overview:AddSection({
        Title = "Within reach",
        Icon = "keyboard",
        Side = "Right"
    })
    local shortcut = essentials:AddParagraph({
        Title = "Menu shortcut",
        Content = "Press " .. CONFIG.ToggleKey.Name .. " to show or hide the hub."
    })
    essentials:AddParagraph({
        Title = "Small when you need it",
        Content = "Minimize to the estyxq Hub pill. Drag it anywhere, then tap to return."
    })
    essentials:AddParagraph({
        Title = "Your tools stay with you",
        Content = "Minimizing keeps enabled features active. Closing or reloading cleans them up."
    })

    local themeCard = Settings:AddSection({
        Title = "Appearance",
        Icon = "palette",
        Side = "Left"
    })
    Menu.Controls.Theme = themeCard:AddDropdown({
        Title = "Color theme",
        Values = table.clone(NextUI.ThemeOrder),
        Default = CONFIG.Theme,
        Flag = "theme",
        Callback = function(value)
            NextUI:SetTheme(value)
        end
    })
    Menu.Controls.Transparency = themeCard:AddToggle({
        Title = "Glass background",
        Style = "Switch",
        Default = CONFIG.Transparent,
        Flag = "glass",
        Callback = function(value)
            NextUI:SetGlass(value);
            Menu.State.Transparent = value
        end
    })
    Menu.Controls.Stars = themeCard:AddToggle({
        Title = "Background stars",
        Style = "Switch",
        Default = CONFIG.Stars,
        Callback = function(value)
            Window:SetStars(value);
            Menu.State.Stars = value
        end
    })
    local preferences = Settings:AddSection({
        Title = "Your space",
        Icon = "user",
        Side = "Right"
    })
    Menu.Controls.Anonymous = preferences:AddToggle({
        Title = "Hide profile",
        Description = "Hide your name and avatar in the sidebar.",
        Style = "Switch",
        Default = CONFIG.Anonymous,
        Callback = setAnonymous
    })
    Menu.Controls.ToggleKey = preferences:AddKeybind({
        Title = "Menu shortcut",
        Default = CONFIG.ToggleKey,
        MenuKey = true,
        ChangedCallback = function(key)
            Menu.State.ToggleKey = key
            local label = typeof(key) == "EnumItem" and key.Name or tostring(key)
            shortcut:Set("Menu shortcut", "Press " .. label .. " to show or hide the hub.")
        end
    })
    local about = Settings:AddSection({
        Title = "About",
        Icon = "info",
        Side = "Full"
    })
    about:AddParagraph({
        Title = CONFIG.Title .. " / " .. CONFIG.ScriptName,
        Content = string.format("Script v%s  /  Menu v%s  /  NextUI v%s", CONFIG.ScriptVersion, CONFIG.MenuVersion,
            tostring(NextUI.Version))
    })
    about:AddButton({
        Title = "Unload hub",
        Description = "Close the menu and stop its features.",
        Hold = 1,
        Callback = Menu.Destroy
    })

    Overview:Select()
    -- Build the common controls first; section network requests may yield independently.
    for _, boundary in ipairs(featureSections) do
        boundary.Retry()
    end
    return Menu
end

local created, menuOrError = pcall(createMenu)
session.Starting = false
local wasCurrent = isCurrentSession()
if not created or not wasCurrent then
    session:Destroy()
    if not created and wasCurrent then
        error(menuOrError, 0)
    end
    return nil
end
return menuOrError
