local SilentAim = {Version="0.2.0", Icon="crosshair", Side="Full"}
local Controller = {}
Controller.__index = Controller
local INSTANCE_KEY, HOOK_KEY = "estyxq-hub.UrbanReload.SilentAim", "estyxq-hub.UrbanReload.SilentAim.Hook"
local NUMBERS = {
    FOV={Default=130, Min=25, Max=1000, Step=5, Title="FOV radius", Suffix="px"},
    MaxDistance={Default=350, Min=25, Max=5000, Step=25, Title="Max distance", Suffix=" studs"},
    HitChance={Default=100, Min=0, Max=100, Step=1, Title="Hit chance", Suffix="%"},
    RefreshRate={Default=30, Min=10, Max=120, Step=5, Title="Target refresh rate", Suffix=" Hz"},
}

function SilentAim.GetDefaults()
    local settings={Enabled=false, UseFOV=true, ShowFOV=true, TeamCheck=true, WallCheck=false,
        Part="Head", FOVColor=Color3.fromRGB(179,154,255)}
    for key, option in pairs(NUMBERS) do settings[key]=option.Default end
    return settings
end

local function environment()
    return (type(getgenv)=="function" and getgenv()) or shared
end

-- Reuse a single pass-through dispatcher. Restoring an older metamethod blindly could
-- remove another script's later hook; unload instead clears this dispatcher's owner.
local function brokerFor(camera)
    local registry=environment()
    local existing=registry[HOOK_KEY]
    if existing then
        assert(existing.Version==1 and type(existing.Original)=="function", "A different Silent Aim hook is already installed; rejoin before updating.")
        return existing
    end
    assert(type(hookmetamethod)=="function" and type(getnamecallmethod)=="function", "This executor does not provide camera metamethod hooks.")
    local broker={Version=1, Busy=false}
    local function dispatch(object, ...)
        local owner=broker.Owner
        if not owner or not owner.Enabled or owner.Destroyed or broker.Busy or object~=workspace.CurrentCamera
            then
            return broker.Original(object, ...)
        end
        local method=getnamecallmethod()
        if (method~="ViewportPointToRay" and method~="ScreenPointToRay") or (type(checkcaller)=="function" and checkcaller()) then
            return broker.Original(object, ...)
        end
        local ray=broker.Original(object, ...)
        broker.Busy=true
        local ok, redirected=pcall(owner._redirect, owner, object, ray)
        broker.Busy=false
        if not ok then owner:_fail(redirected); return ray end
        return redirected or ray
    end
    local wrapper=type(newcclosure)=="function" and newcclosure(dispatch) or dispatch
    broker.Original=hookmetamethod(camera,"__namecall",wrapper)
    assert(type(broker.Original)=="function", "The executor did not return the original camera metamethod.")
    registry[HOOK_KEY]=broker
    return broker
end

function Controller:_aimPart(character)
    local name=self.Settings.Part
    local part=character:FindFirstChild(name)
    if not part and name=="UpperTorso" then part=character:FindFirstChild("Torso") end
    return part and part:IsA("BasePart") and part or nil
end

function Controller:_sameTeam(player)
    local localPlayer=self._players.LocalPlayer
    return self.Settings.TeamCheck and not localPlayer.Neutral and not player.Neutral
        and localPlayer.Team~=nil and player.Team==localPlayer.Team
end

function Controller:_visible(camera, part, character)
    if not self.Settings.WallCheck then return true end
    local parameters=RaycastParams.new()
    parameters.FilterType=Enum.RaycastFilterType.Exclude
    local localCharacter=self._players.LocalPlayer.Character
    parameters.FilterDescendantsInstances=localCharacter and {localCharacter} or {}
    local result=workspace:Raycast(camera.CFrame.Position,part.Position-camera.CFrame.Position,parameters)
    return result==nil or (result.Instance~=nil and result.Instance:IsDescendantOf(character))
end

function Controller:_findTarget(camera)
    local localPlayer=self._players.LocalPlayer
    local own=localPlayer.Character
    local ownHumanoid=own and own:FindFirstChildOfClass("Humanoid")
    if not ownHumanoid or ownHumanoid.Health<=0 then return nil end
    local center=camera.ViewportSize/2
    local closest, best=nil, self.Settings.UseFOV and self.Settings.FOV or math.huge
    for _, player in ipairs(self._players:GetPlayers()) do
        if player~=localPlayer and not self:_sameTeam(player) then
            local character=player.Character
            local humanoid=character and character:FindFirstChildOfClass("Humanoid")
            local part=humanoid and humanoid.Health>0 and self:_aimPart(character)
            if part and part.Parent and (part.Position-camera.CFrame.Position).Magnitude<=self.Settings.MaxDistance then
                local screen, onScreen=camera:WorldToViewportPoint(part.Position)
                if onScreen and screen.Z>0 then
                    local distance=(Vector2.new(screen.X,screen.Y)-center).Magnitude
                    if distance<=best and self:_visible(camera,part,character) then
                        closest={Player=player, Character=character, Part=part, Camera=camera}
                        best=distance
                    end
                end
            end
        end
    end
    return closest
end

function Controller:_removeCircle()
    local circle=self._circle
    self._circle=nil
    if circle then pcall(function() circle.Visible=false; circle:Remove() end) end
end

function Controller:_drawCircle(camera)
    if not camera or not self.Settings.ShowFOV or not self.Settings.UseFOV then self:_removeCircle(); return end
    if self._circleUnavailable then return end
    if not self._circle then
        local circle
        local ok, message=pcall(function()
            assert(Drawing and type(Drawing.new)=="function", "Drawing.Circle is unavailable in this executor.")
            circle=Drawing.new("Circle")
            circle.Filled, circle.NumSides, circle.Thickness, circle.Transparency=false, 64, 1.5, 0.8
        end)
        if not ok then
            if circle then pcall(function() circle:Remove() end) end
            self._circleUnavailable=true
            if self._onWarning then self._onWarning(tostring(message)) end
            return
        end
        self._circle=circle
    end
    self._circle.Position=camera.ViewportSize/2
    self._circle.Radius=self.Settings.FOV
    self._circle.Color=self.Settings.FOVColor
    self._circle.Visible=true
end

function Controller:_step(deltaTime)
    if not self.Enabled then return end
    local camera=workspace.CurrentCamera
    self:_drawCircle(camera)
    if not camera then self._target=nil; return end
    self._accumulator+=deltaTime
    if self._target and self._target.Camera~=camera then self._target=nil end
    if self._accumulator>=1/self.Settings.RefreshRate then
        self._accumulator=0
        self._target=self:_findTarget(camera)
    end
end

function Controller:_redirect(camera, ray)
    if not self.Enabled or self.Destroyed then return nil end
    local target=self._target
    if not target or target.Camera~=camera or target.Player.Character~=target.Character or not target.Part.Parent
        or not target.Part:IsDescendantOf(target.Character) or self:_sameTeam(target.Player) then return nil end
    local humanoid=target.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health<=0 or (target.Part.Position-camera.CFrame.Position).Magnitude>self.Settings.MaxDistance then return nil end
    local chance=self.Settings.HitChance
    if chance<=0 or (chance<100 and math.random(1,100)>chance) then return nil end
    local direction=target.Part.Position-ray.Origin
    if direction.Magnitude<0.0001 or ray.Direction.Magnitude<0.0001 then return nil end
    -- Camera ray methods return unit rays. Preserve their origin/depth and length.
    return Ray.new(ray.Origin,direction.Unit*ray.Direction.Magnitude)
end

function Controller:_fail(message)
    if self.Destroyed then return end
    self:SetEnabled(false)
    local callback=self._onError
    if callback then task.defer(callback,tostring(message)) end
end

function Controller:SetEnabled(value)
    assert(not self.Destroyed,"This Silent Aim controller has been destroyed.")
    assert(type(value)=="boolean","Enabled must be a boolean.")
    if value==self.Enabled then return end
    if not value then
        self.Enabled, self.Settings.Enabled, self._target=false, false, nil
        if self._connection then self._connection:Disconnect(); self._connection=nil end
        self:_removeCircle()
        if self._broker and self._broker.Owner==self then self._broker.Owner=nil end
        return
    end
    local camera=workspace.CurrentCamera
    assert(camera,"The current camera is not ready. Try enabling again after spawning.")
    self._broker=brokerFor(camera)
    self.Enabled, self.Settings.Enabled, self._accumulator=true, true, 0
    self._broker.Owner=self
    local ok, message=pcall(function()
        self._connection=self._runService.RenderStepped:Connect(function(deltaTime)
            local updated, updateError=pcall(self._step,self,deltaTime)
            if not updated then self:_fail(updateError) end
        end)
        self:_step(1/self.Settings.RefreshRate)
    end)
    if not ok then self:SetEnabled(false); error(message,0) end
end

function Controller:UpdateSettings(patch)
    assert(not self.Destroyed,"This Silent Aim controller has been destroyed.")
    local settings=table.clone(self.Settings)
    for key,value in pairs(patch) do
        local default=settings[key]
        assert(default~=nil,"Unknown Silent Aim setting: " .. tostring(key))
        if NUMBERS[key] then
            local option=NUMBERS[key]
            assert(type(value)=="number" and value==value and math.abs(value)<math.huge,key .. " must be finite.")
            value=math.clamp(value,option.Min,option.Max)
        elseif key=="Part" then
            assert(table.find({"Head","UpperTorso","HumanoidRootPart"},value),"Unknown aim part.")
        elseif key=="FOVColor" then assert(typeof(value)=="Color3","FOVColor must be a Color3.")
        else assert(type(value)=="boolean",key .. " must be a boolean.") end
        settings[key]=value
    end
    local enabled=settings.Enabled
    settings.Enabled=self.Enabled
    self.Settings=settings
    self._target=nil
    if patch.ShowFOV==true then self._circleUnavailable=false end
    self:SetEnabled(enabled)
    if self.Enabled then self:_step(1/self.Settings.RefreshRate) end
end

function Controller:GetSettings() return table.clone(self.Settings) end
function Controller:GetStatus()
    return {Enabled=self.Enabled, Target=self._target and self._target.Player.Name or nil,
        CircleVisible=self._circle~=nil and self._circle.Visible==true}
end
function Controller:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false)
    self.Destroyed=true
    self._onError, self._onWarning=nil, nil
    if environment()[INSTANCE_KEY]==self then environment()[INSTANCE_KEY]=nil end
end

function SilentAim.new(settings,onError,onWarning)
    local players=game:GetService("Players")
    assert(players.LocalPlayer,"Silent Aim must run on the client.")
    local previous=environment()[INSTANCE_KEY]
    if previous then previous:Destroy() end
    local controller=setmetatable({Settings=SilentAim.GetDefaults(), Enabled=false, Destroyed=false,
        _players=players, _runService=game:GetService("RunService"), _accumulator=0,
        _onError=onError, _onWarning=onWarning},Controller)
    local ok,message=pcall(controller.UpdateSettings,controller,settings or {})
    if not ok then controller:Destroy(); error(message,0) end
    environment()[INSTANCE_KEY]=controller
    return controller
end

function SilentAim.Mount(context)
    local state, controls=context.State, context.Controls
    for key,value in pairs(SilentAim.GetDefaults()) do state[key]=value end
    local status=context.Section:AddParagraph({Title="Silent Aim is off", Content="Camera-ray mode. Ready for in-game compatibility testing."})
    local function refresh()
        status:Set(state.Enabled and "Silent Aim is on" or "Silent Aim is off", state.Enabled
            and (state.Part .. " / " .. state.HitChance .. "% chance / " .. state.MaxDistance .. " studs")
            or "Enable when ready. Closing or reloading the hub stops targeting.")
    end
    local controller=SilentAim.new(state,function(message)
        if not context.IsActive() then return end
        state.Enabled=false
        if controls.Enabled then controls.Enabled:Set(false) end
        context.Notify("Silent Aim stopped",tostring(message),"Error")
        refresh()
    end,function(message)
        if context.IsActive() then context.Notify("FOV circle unavailable",message,"Warning") end
    end)
    context.AddCleanup(function() state.Enabled=false; controller:Destroy() end)
    controls.Enabled=context.Section:AddToggle({Title="Enable Silent Aim", Style="Switch", Default=false, Callback=function(value)
        local ok,message=pcall(controller.SetEnabled,controller,value)
        state.Enabled=controller.Enabled
        if not ok then
            if controls.Enabled then controls.Enabled:Set(false) end
            context.Notify("Silent Aim unavailable",tostring(message),"Error")
        end
        refresh()
    end})
    -- CreateWindow section cards expose controls, titles, and dividers, not nested AddSection.
    local section=context.Section
    local function toggle(key,title)
        controls[key]=section:AddToggle({Title=title, Style="Switch", Default=state[key], Callback=function(value)
            controller:UpdateSettings({[key]=value}); state[key]=value; refresh()
        end})
    end
    local function slider(key)
        local option=NUMBERS[key]
        controls[key]=section:AddSlider({Title=option.Title,Min=option.Min,Max=option.Max,Increment=option.Step,Default=state[key],Suffix=option.Suffix,Callback=function(value)
            controller:UpdateSettings({[key]=value}); state[key]=controller.Settings[key]; refresh()
        end})
    end
    section:AddDivider()
    section:AddTitle("Targeting")
    toggle("TeamCheck","Team check")
    toggle("WallCheck","Wall check")
    toggle("UseFOV","Limit targets to FOV")
    controls.Part=section:AddDropdown({Title="Aim part",Values={"Head","UpperTorso","HumanoidRootPart"},Default=state.Part,Callback=function(value)
        controller:UpdateSettings({Part=value}); state.Part=value; refresh()
    end})
    for _,key in ipairs({"MaxDistance","HitChance","RefreshRate"}) do slider(key) end
    section:AddDivider()
    section:AddTitle("FOV circle")
    slider("FOV")
    toggle("ShowFOV","Show FOV circle")
    controls.FOVColor=section:AddColorPicker({Title="Circle color",Default=state.FOVColor,Callback=function(value)
        controller:UpdateSettings({FOVColor=value}); state.FOVColor=value
    end})
    refresh()
end
return SilentAim
