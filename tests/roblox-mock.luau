-- Roblox/NextUI test doubles. Production source is injected by tools/test-runtime.mjs.
local realCompile = loadstring
local registry, signals, drawings, notifications = {}, {}, {}, {}
local failDrawingAt, createdDrawings, failTextDrawing = nil, 0, false
local function signal()
    local event = { Connections = {} }
    table.insert(signals, event)
    function event:Connect(callback)
        local connection = { Connected = true, Callback = callback }
        function connection:Disconnect() self.Connected = false end
        table.insert(self.Connections, connection)
        return connection
    end
    function event:Fire(...)
        for _, connection in ipairs(table.clone(self.Connections)) do
            if connection.Connected then connection.Callback(...) end
        end
    end
    return event
end
local function connectionCount()
    local count = 0
    for _, event in ipairs(signals) do
        for _, connection in ipairs(event.Connections) do if connection.Connected and not event.IsUI then count += 1 end end
    end
    return count
end
local vectorMeta = {}
vectorMeta.__index = function(self,key)
    if key == "Magnitude" then return math.sqrt(self.X*self.X+self.Y*self.Y+self.Z*self.Z) end
    if key == "Unit" then return self*(1/self.Magnitude) end
    return vectorMeta[key]
end
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vectorMeta) end
function vectorMeta:Dot(other) return self.X * other.X + self.Y * other.Y + self.Z * other.Z end
function vectorMeta.__add(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
function vectorMeta.__sub(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
function vectorMeta.__div(a,b) return vec(a.X/b,a.Y/b,a.Z/b) end
function vectorMeta.__mul(a, b) return vec(a.X * b, a.Y * b, a.Z * b) end
function vectorMeta:Lerp(other,t) return self+(other-self)*t end
local frameMeta={}
local function frame(position,right,up,look)
    return setmetatable({Position=position or vec(0,0,0),RightVector=right or vec(1,0,0),UpVector=up or vec(0,1,0),LookVector=look or vec(0,0,1),Kind="CFrame"},frameMeta)
end
frameMeta.__index=function(self,key)
    if key=="Rotation" then return frame(vec(0,0,0),self.RightVector,self.UpVector,self.LookVector) end
    return frameMeta[key]
end
function frameMeta:PointToWorldSpace(point) return self.Position+self.RightVector*point.X+self.UpVector*point.Y+self.LookVector*point.Z end
function frameMeta:Lerp(other,t) return frame(self.Position:Lerp(other.Position,t),self.RightVector:Lerp(other.RightVector,t),self.UpVector:Lerp(other.UpVector,t),self.LookVector:Lerp(other.LookVector,t)) end
frameMeta.__add=function(a,b) return frame(a.Position+b,a.RightVector,a.UpVector,a.LookVector) end
frameMeta.__mul=function(a,b) return frame(a:PointToWorldSpace(b.Position),b.RightVector,b.UpVector,b.LookVector) end
local colorMeta = {}
colorMeta.__index = colorMeta
local function color(r, g, b) return setmetatable({ R = r, G = g, B = b, Kind = "Color3" }, colorMeta) end
function colorMeta:Lerp(other, t) return color(self.R + (other.R - self.R) * t, self.G + (other.G - self.G) * t, self.B + (other.B - self.B) * t) end
local function descendant(self,ancestor)
    local parent=self.Parent
    while type(parent)=="table" do if parent==ancestor then return true end; parent=parent.Parent end
    return false
end
local function part(name,position)
    local object={Name=name,Size=vec(2,2,1),CanCollide=true,AssemblyLinearVelocity=vec(0,0,0),AssemblyAngularVelocity=vec(0,0,0),_frame=frame(position or vec(0,0,20)),IsA=function(_,class) return class=="BasePart" end,IsDescendantOf=descendant}
    return setmetatable(object,{
        __index=function(self,key) if key=="Position" then return self._frame.Position elseif key=="CFrame" then return self._frame end end,
        __newindex=function(self,key,value)
            if key=="Position" then self._frame=frame(value,self._frame.RightVector,self._frame.UpVector,self._frame.LookVector)
            elseif key=="CFrame" then self._frame=value else rawset(self,key,value) end
        end,
    })
end
local function humanoid(rig)
    local object={Name="Humanoid",RigType=rig,Health=100,MaxHealth=100,HipHeight=rig==6 and 0 or 2,PlatformStand=false,AutoRotate=true,MoveDirection=vec(0,0,0),FloorMaterial="Ground",_state="Running",IsA=function(_,class) return class=="Humanoid" end}
    function object:GetState() return self._state end
    function object:ChangeState(state)
        self._state=state
        if state=="Jumping" or state=="Freefall" then self.FloorMaterial="Air" end
        if state=="Landed" or state=="Running" then self.FloorMaterial="Ground" end
    end
    return object
end
local function character(rig, withHumanoid)
    local model = { Parent = true, Children = {}, ChildAdded = signal(), ChildRemoved = signal(), DescendantAdded=signal(), DescendantRemoving=signal() }
    function model:FindFirstChildOfClass(class)
        for _, child in ipairs(self.Children) do if child:IsA(class) then return child end end
    end
    function model:GetBoundingBox()
        local lo, hi = vec(math.huge,math.huge,math.huge), vec(-math.huge,-math.huge,-math.huge)
        for _, child in ipairs(self.Children) do
            if child:IsA("BasePart") then
                local half=child.Size/2
                lo=vec(math.min(lo.X,child.Position.X-half.X),math.min(lo.Y,child.Position.Y-half.Y),math.min(lo.Z,child.Position.Z-half.Z))
                hi=vec(math.max(hi.X,child.Position.X+half.X),math.max(hi.Y,child.Position.Y+half.Y),math.max(hi.Z,child.Position.Z+half.Z))
            end
        end
        local center=(lo+hi)/2
        return {Position=center, PointToWorldSpace=function(_,offset) return center+offset end},hi-lo
    end
    function model:GetDescendants()
        local all={}
        for _,child in ipairs(self.Children) do
            table.insert(all,child)
            if child.GetDescendants then for _,part in ipairs(child:GetDescendants()) do table.insert(all,part) end end
        end
        return all
    end
    function model:GetChildren() return table.clone(self.Children) end
    function model:FindFirstChild(name)
        for _, child in ipairs(self.Children) do if child.Name == name then return child end end
    end
    function model:Add(child) child.Parent=self; table.insert(self.Children,child); self.ChildAdded:Fire(child); self.DescendantAdded:Fire(child); if child.GetDescendants then for _,part in ipairs(child:GetDescendants()) do self.DescendantAdded:Fire(part) end end end
    function model:Remove(name)
        for index, child in ipairs(self.Children) do
            if child.Name == name then self.DescendantRemoving:Fire(child); table.remove(self.Children, index); child.Parent = nil; self.ChildRemoved:Fire(child); return child end
        end
    end
    local names = rig == 6 and { "HumanoidRootPart", "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
        or { "HumanoidRootPart", "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
    for _, name in ipairs(names) do model:Add(part(name)) end
    if withHumanoid ~= false then model:Add(humanoid(rig)) end
    return model
end
local function player(name, team, rig)
    return { Name = name, DisplayName = name .. " display", Team = team, TeamColor = {Color=color(0.2,0.8,1)}, Neutral = false, Character = character(rig), CharacterAdded = signal(), CharacterRemoving = signal() }
end
local localPlayer = player("Local", "Blue", 6)
localPlayer.Character:FindFirstChild("HumanoidRootPart").Position = vec(0, 0, 0)
local enemy = player("Enemy", "Red", 6)
local teammate = player("Teammate", "Blue", 15)
local Players = { LocalPlayer = localPlayer, List = { localPlayer, enemy, teammate }, PlayerAdded = signal(), PlayerRemoving = signal() }
function Players:GetPlayers() return table.clone(self.List) end
localPlayer.Idled = signal()
local RunService = { RenderStepped = signal(), Heartbeat = signal(), Stepped=signal() }
local function camera()
    local object = { CFrame = frame(vec(0,0,0)), ProjectionInputs={}, ViewportSize=vec(800,600,0), Calls = 0 }
    function object:WorldToViewportPoint(position)
        self.Calls += 1
        table.insert(self.ProjectionInputs,position)
        local projected = vec(400 + position.X * 10, 300 - position.Y * 10, position.Z)
        return projected, projected.X >= 0 and projected.X <= 800 and projected.Y >= 0 and projected.Y <= 600 and projected.Z > 0
    end
    return object
end
local world = { CurrentCamera = camera() }
function world:Raycast(origin,direction,parameters)
    self.LastRaycast={Origin=origin,Direction=direction,Parameters=parameters}
    return self.RaycastResult
end
local DrawingAPI = { new = function(kind)
    assert(kind == "Line" or kind == "Circle" or kind == "Text")
    if kind == "Text" and failTextDrawing then error("Drawing.Text unsupported") end
    createdDrawings += 1
    if failDrawingAt and createdDrawings >= failDrawingAt then error("simulated allocation failure") end
    local drawing = { Kind=kind, Visible = false, Removed = false }
    function drawing:Remove() assert(not self.Removed); self.Removed = true; self.Visible = false end
    table.insert(drawings, drawing)
    return drawing
end }
local function drawingCount(onlyVisible)
    local count = 0
    for _, drawing in ipairs(drawings) do
        if not drawing.Removed and (not onlyVisible or drawing.Visible) then count += 1 end
    end
    return count
end
local function uiSignal()
    local event = signal()
    event.IsUI = true
    return event
end
local UserInputService = { InputBegan=uiSignal(), InputChanged=uiSignal(), InputEnded=uiSignal(), JumpRequest=uiSignal(),Keys={},TouchEnabled=false,KeyboardEnabled=true }
function UserInputService:GetFocusedTextBox() return self.Focused end
function UserInputService:IsKeyDown(key) return self.Keys[key]==true end
local physicsInstances,failInstanceClass={},nil
local function uiInstance(class)
    if class==failInstanceClass then error("simulated instance allocation failure") end
    local object = { ClassName = class, InputBegan = uiSignal(), Activated = uiSignal(), MouseEnter = uiSignal(), MouseLeave = uiSignal() }
    if class=="Attachment" or class=="LinearVelocity" or class=="AlignOrientation" then table.insert(physicsInstances,object) end
    function object:IsA(name) return self.ClassName == name end
    function object:Destroy() self.Destroyed = true; self.Parent = nil end
    return object
end
local function dim(scale, offset) return { Scale = scale, Offset = offset } end
local function dim2(xs, xo, ys, yo) return { X = dim(xs, xo), Y = dim(ys, yo) } end
local function uiContainer(options, library, isTab)
    local container = { Options = options, Elements = {}, Sections = {}, Frame = {} }
    function container:Destroy()
        self.Destroyed = true
        if self.Parent then
            local index = table.find(self.Parent.Sections, self)
            if index then table.remove(self.Parent.Sections, index) end
        end
    end
    function container:Select() self.Selected = true end
    -- CreateWindow tabs own section cards; their card handles only expose Elements.
    if isTab then
        function container:AddSection(sectionOptions)
            local section = uiContainer(sectionOptions, library, false)
            section.Parent = self
            table.insert(self.Sections, section)
            return section
        end
    end
    function container:AddTabs(options)
        local tabs = {Pages={}, _list={}}
        function tabs:AddTab(name)
            local page=uiContainer({Title=name},library,false)
            self.Pages[name]=page
            table.insert(self._list,page)
            return page
        end
        function tabs:Select(name) self.Selected=name end
        function tabs:Get() return self.Selected end
        for _,name in ipairs(options.Tabs or options) do tabs:AddTab(name) end
        return tabs
    end
    function container:AddTitle(text)
        local element = { Kind = "Title", Options = { Title = text } }
        function element:Set(value) self.Options.Title = value end
        table.insert(self.Elements, element)
        return element
    end
    function container:AddDivider()
        table.insert(self.Elements, { Kind = "Divider", Options = {} })
    end
    container.AddLabel = container.AddTitle
    function container:AddParagraph(elementOptions)
        local element = { Options = elementOptions }
        function element:Set(title, content)
            self.Options.Title = title or self.Options.Title
            self.Options.Content = content or self.Options.Content
        end
        table.insert(self.Elements, element)
        return element
    end
    for _, kind in ipairs({ "Button", "Toggle", "Slider", "Dropdown", "ColorPicker", "Keybind" }) do
        container["Add" .. kind] = function(self, elementOptions)
            assert(elementOptions.Desc == nil and elementOptions.Value == nil, "Legacy WindUI options")
            if kind == "Slider" then assert(elementOptions.Min and elementOptions.Max and elementOptions.Increment) end
            local element = { Options = elementOptions, Value = elementOptions.Default }
            function element:Get() return self.Value end
            function element:Set(value)
                self.Value = value
                if kind == "Keybind" then
                    if elementOptions.MenuKey then library:SetMenuKey(value) end
                    if elementOptions.ChangedCallback then elementOptions.ChangedCallback(value) end
                elseif elementOptions.Callback then elementOptions.Callback(value) end
            end
            if elementOptions.Flag then library.Options[elementOptions.Flag] = element end
            if kind ~= "Button" and kind ~= "Keybind" then element:Set(elementOptions.Default) end
            table.insert(self.Elements, element)
            return element
        end
    end
    return container
end
local function nextUI()
    if registry.NextUI then registry.NextUI:Destroy() end
    local library = { Version = "1.3.5", Options = {}, ThemeOrder = { "Amethyst", "Aqua", "Rose" } }
    library.Theme = { Card = color(0.1,0.1,0.1), Hover = color(0.2,0.2,0.2), Text = color(1,1,1), Accent = color(0.7,0.5,1) }
    function library:SetTheme(name)
        self.ThemeName = name
        self.Theme.Accent = name == "Aqua" and color(0,1,1) or color(0.7,0.5,1)
        local option = self.Options.theme
        if option and option:Get() ~= name then option:Set(name) end
    end
    function library:SetGlass(value)
        self.Glass = value
        local option = self.Options.glass
        if option and option:Get() ~= value then option:Set(value) end
    end
    function library:SetMenuKey(key) self.MenuKey = key end
    function library:Notify(options) table.insert(notifications, options); return options end
    function library:Destroy()
        self.NativeDestroyed = true
        if self.Gui then self.Gui:Destroy() end
        registry.NextUI = nil
    end
    function library:CreateWindow(options)
        assert(options.Title and options.SubTitle and options.Size and options.Intro == true)
        assert(options.Author == nil and options.OpenButton == nil and options.Transparent == nil, "Legacy window options")
        local gui = uiInstance("ScreenGui")
        gui.AbsoluteSize = { X = 1000, Y = 720 }
        gui.Parent = true
        local profile = { Visible = true }
        local avatar = uiInstance("ImageLabel")
        avatar.Image, avatar.Parent = "rbxthumb://type=AvatarHeadShot&id=123", profile
        function gui:GetDescendants() return { avatar } end
        local window = { Options = options, Tabs = {}, Categories = {}, Gui = gui, Visible = false, _intro = true, Profile = profile }
        function window:Toggle(value)
            if self._intro then self._queued = value; return end
            if value == nil then value = not self.Visible end
            self.Visible = value
        end
        function window:AddCategory(name) table.insert(self.Categories, name) end
        function window:AddTab(title, icon)
            local tab = uiContainer({ Title = title, Icon = icon }, library, true)
            table.insert(self.Tabs, tab)
            return tab
        end
        function window:SetStars(value) self.Stars = value end
        self.Gui = gui
        self:SetTheme(options.Theme)
        self:SetGlass(options.Glass)
        self.Window = window
        return window
    end
    registry.NextUI = library
    return library
end
local testTime, virtualDowns, virtualUps, virtualHeld, failDown, failUpCount = 0, 0, 0, false, false, 0
local consoleMessages, cleanupWarnings = {}, {}
local VirtualUser = {
    Button2Down = function()
        virtualDowns += 1; virtualHeld = true
        if failDown then error("simulated input failure") end
    end,
    Button2Up = function()
        virtualUps += 1
        if failUpCount > 0 then failUpCount -= 1; error("simulated release failure") end
        virtualHeld = false
    end,
}

-- A deterministic scheduler: spawned tasks run to their first yield, deferred tasks wait for flush.
local queued, httpPending, requests = {}, {}, {}
local overrides, downloadFailures, pauses = {}, {}, {}
local ignoreCancellation = false
local function resume(thread, ...)
    local ok, message = coroutine.resume(thread, ...)
    assert(ok, tostring(message))
    return message
end
local function asThread(callback) return type(callback) == "thread" and callback or coroutine.create(callback) end
local function enqueue(at, callback, ...)
    local thread = asThread(callback)
    table.insert(queued, {At=at, Thread=thread, Args=table.pack(...)})
    return thread
end
local fakeTask = {
    spawn = function(callback, ...) local thread = asThread(callback); resume(thread, ...); return thread end,
    defer = function(callback, ...) return enqueue(testTime, callback, ...) end,
    delay = function(seconds, callback, ...) return enqueue(testTime + seconds, callback, ...) end,
    cancel = function(thread)
        if not ignoreCancellation then coroutine.close(thread) end
    end,
    wait = function(seconds)
        enqueue(testTime + (seconds or 0), coroutine.running())
        return coroutine.yield("task wait")
    end,
}
local function flushTasks()
    local iterations = 0
    while true do
        local nextIndex
        for index, item in ipairs(queued) do if item.At <= testTime then nextIndex = index; break end end
        if not nextIndex then break end
        iterations += 1
        assert(iterations < 1000, "Scheduler did not settle")
        local item = table.remove(queued, nextIndex)
        if coroutine.status(item.Thread) ~= "dead" then resume(item.Thread, table.unpack(item.Args,1,item.Args.n)) end
    end
end
local function advance(seconds)
    testTime += seconds
    flushTasks()
    RunService.Heartbeat:Fire(seconds)
    flushTasks()
end
local function allConnections()
    local count = 0
    for _, event in ipairs(signals) do
        for _, connection in ipairs(event.Connections) do if connection.Connected then count += 1 end end
    end
    return count
end
local function fileFromURL(url)
    url = url:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex,16)) end)
    for file in pairs(sources) do
        if url:sub(-#file - 1) == "/" .. file then return file end
    end
    error("Unexpected URL: " .. url)
end
local namecallMethod, executorCaller, hookInstallations = "ViewportPointToRay", false, 0
local kickCalls,directHookInstallations,failKickHook=0,0,false
local function originalKick() kickCalls=kickCalls+1; return "kick forwarded" end
local directKick=originalKick
function localPlayer:Kick(...) return directKick(self,...) end
local function originalNamecall(object, ...)
    if string.lower(namecallMethod)=="kick" then return originalKick(object,...) end
    return {Origin=object.RayOrigin or object.CFrame.Position, Direction=vec(0,0,1), Original=true}
end
local activeNamecall=originalNamecall
local readonly=true
local rawMeta=setmetatable({}, {__index=function(_,key) if key=="__namecall" then return activeNamecall end end, __newindex=function(_,key,value) assert(key=="__namecall"); activeNamecall=value end})
local function cameraRay(object,method,...)
    namecallMethod=method
    return activeNamecall(object,...)
end
local environment
local function compileSource(source, name)
    local chunk, message = realCompile(source, name)
    if chunk then setfenv(chunk, environment) end
    return chunk, message
end
environment = setmetatable({
    getgenv = function() return registry end, shared = registry, workspace = world, Drawing = DrawingAPI, Instance = { new = uiInstance },
    Enum = { Material={Air="Air",Ground="Ground"}, HumanoidStateType={Running="Running",Jumping="Jumping",Freefall="Freefall",Landed="Landed",Physics="Physics",PlatformStanding="PlatformStanding"}, ActuatorRelativeTo={World="World"}, VelocityConstraintMode={Vector="Vector"}, OrientationAlignmentMode={OneAttachment="OneAttachment"}, RaycastFilterType={Exclude="Exclude"}, HumanoidRigType = { R6 = 6, R15 = 15 }, KeyCode = { W="W",A="A",S="S",D="D",Space="Space",LeftControl="Control",ButtonA="ButtonA",RightShift = { Name = "RightShift", Kind = "EnumItem" } }, UserInputType = { MouseButton1 = "Mouse1", Touch = "Touch", MouseMovement = "Move" }, Font = { BuilderSansBold = "Bold" } },
    Vector3 = { new=vec, zero=vec(0,0,0), yAxis=vec(0,1,0) },
    CFrame={new=function(x,y,z) return frame(type(x)=="table" and x or vec(x or 0,y or 0,z or 0)) end,identity=frame()}, Vector2 = { new = function(x,y) return vec(x,y,0) end },
    Ray = {new=function(origin,direction) return {Origin=origin,Direction=direction} end}, RaycastParams={new=function() return {} end},
    hookmetamethod=function(_,method,callback)
        assert(method=="__namecall"); hookInstallations+=1; local previous=activeNamecall; activeNamecall=callback; return previous
    end,
    hookfunction=function(target,replacement)
        assert(target==localPlayer.Kick)
        if failKickHook then error("simulated hookfunction failure") end
        directHookInstallations=directHookInstallations+1; local previous=directKick; directKick=replacement; return previous
    end,
    getrawmetatable=function() return rawMeta end, isreadonly=function() return readonly end, setreadonly=function(_,value) readonly=value end,
    getnamecallmethod=function() return namecallMethod end, checkcaller=function() return executorCaller end, newcclosure=function(callback) return callback end,
    Color3 = { new = color, fromRGB = function(r,g,b) return color(r/255,g/255,b/255) end,
        fromHex = function(hex) return color(tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255) end },
    typeof = function(value) return type(value) == "table" and value.Kind or type(value) end,
    ColorSequence = { new = function(...) return { ... } end }, UDim = { new = function(...) return { ... } end },
    UDim2 = { new = dim2, fromOffset = function(x,y) return dim2(0,x,0,y) end },
    task = fakeTask,
    os = { clock = function() return testTime end },
    print = function(message) table.insert(consoleMessages, message) end,
    warn = function(message) table.insert(cleanupWarnings, message) end,
    game = { PlaceId=0, GameId=0, GetService = function(_, name) return ({ Players = Players, RunService = RunService, UserInputService = UserInputService, VirtualUser = VirtualUser })[name] end,
        HttpGet = function(_, url)
            table.insert(requests,url)
            local file = fileFromURL(url)
            if pauses[file] then
                pauses[file] = nil
                httpPending[file] = coroutine.running()
                coroutine.yield("HTTP " .. file)
            end
            if downloadFailures[file] then error("simulated download failure: " .. file) end
            if overrides[file] then return overrides[file] end
            if file == "menu.luau" then return "MOCK_NEXTUI" end
            return sources[file]
        end },
    loadstring = function(source,name)
        if source == "MOCK_NEXTUI" then return nextUI end
        return compileSource(source,name)
    end,
}, { __index = getfenv() })
local function execute(source, ...)
    local result = assert(compileSource(source))(...)
    if result and result.Window then result.Window._intro = nil; result.Window:Toggle(true) end
    flushTasks()
    return result
end
local afkSource = sources["shared/misc-[Misc]/anti-afk-[Anti-AFK].luau"]
local silentSource = sources["urban-reloaded-[84448037861644]/combat-[Combat]/silent-aim-[Silent Aim].luau"]
local loaderSource, mainSource = sources["loader.luau"], sources["main.luau"]

local espSource = sources["urban-reloaded-[84448037861644]/visual-[Visuals]/esp-[ESP].luau"]
local gameVersion = execute(sources["catalog.luau"]).Games[1].Version
