-- Flight controls adapted from AnyCat.Dev's Tools V1; physics instances are owned by this controller.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Flight = {Icon = "navigation", Side = "Full"}
local Controller = {}; Controller.__index = Controller
local SMOOTH = {Low = {accel=6,damp=5,rot=7}, Medium = {accel=12,damp=10,rot=14}, High = {accel=22,damp=18,rot=24}}
function Flight.GetDefaults() return {Enabled=false, Speed=50, Mode="Velocity", Smoothness="Medium"} end
local function disconnect(list)
    for _, connection in ipairs(list) do connection:Disconnect() end
    table.clear(list)
end
function Controller:_release()
    for index=#self._objects,1,-1 do pcall(function() self._objects[index]:Destroy() end) end
    table.clear(self._objects)
    local saved=self._saved; self._saved=nil
    if saved then
        pcall(function() if saved.Humanoid.PlatformStand then saved.Humanoid.PlatformStand=saved.PlatformStand end end)
        pcall(function() if not saved.Humanoid.AutoRotate then saved.Humanoid.AutoRotate=saved.AutoRotate end end)
        pcall(function()
            local current=saved.Humanoid:GetState()
            if current==Enum.HumanoidStateType.Physics or current==Enum.HumanoidStateType.PlatformStanding then saved.Humanoid:ChangeState(saved.State) end
        end)
        pcall(function() saved.Root.AssemblyLinearVelocity=Vector3.zero; saved.Root.AssemblyAngularVelocity=Vector3.zero end)
    end
    self._velocity,self._root,self._humanoid,self._linear,self._align=nil,nil,nil,nil,nil
    self._character,self._rotation,self._anchor=nil,nil,nil
end
function Controller:SetEnabled(enabled)
    assert(not self.Destroyed,"Flight has been destroyed.")
    assert(type(enabled)=="boolean","Enabled must be a boolean.")
    if enabled==self.Enabled then return end
    if not enabled then
        self.Enabled,self.Settings.Enabled=false,false
        disconnect(self._connections); self:_release(); return
    end
    local character=self.Player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    assert(root and humanoid and humanoid.Health>0,"Spawn a living character before enabling flight.")
    self.Enabled,self.Settings.Enabled=true,true
    local ok,message=pcall(function()
        self._root,self._humanoid,self._character=root,humanoid,character
        self._saved={Root=root,Humanoid=humanoid,PlatformStand=humanoid.PlatformStand,AutoRotate=humanoid.AutoRotate,State=humanoid:GetState()}
        humanoid.PlatformStand,humanoid.AutoRotate=true,false
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        local function make(class)
            local object=Instance.new(class); table.insert(self._objects,object)
            object.Name="EstyxqFlight" .. class; return object
        end
        local attachment=make("Attachment"); attachment.Parent=root
        local linear=make("LinearVelocity")
        linear.Attachment0=attachment
        linear.RelativeTo=Enum.ActuatorRelativeTo.World
        linear.VelocityConstraintMode=Enum.VelocityConstraintMode.Vector
        linear.ForceLimitsEnabled=false
        linear.VectorVelocity=Vector3.zero
        linear.Parent=root
        local align=make("AlignOrientation")
        align.Attachment0=attachment
        align.Mode=Enum.OrientationAlignmentMode.OneAttachment
        align.MaxTorque,align.MaxAngularVelocity=math.huge,math.huge
        align.RigidityEnabled=false
        align.Responsiveness=SMOOTH[self.Settings.Smoothness].rot
        align.CFrame=root.CFrame.Rotation
        align.Parent=root
        self._linear,self._align,self._velocity,self._rotation,self._anchor=linear,align,Vector3.zero,root.CFrame.Rotation,root.Position
        table.insert(self._connections,RunService.Heartbeat:Connect(function(dt)
            if not self.Enabled then return end
            local updated,updateError=pcall(self._step,self,dt)
            if not updated then self:_stop(tostring(updateError)) end
        end))
        table.insert(self._connections,self.Player.CharacterRemoving:Connect(function(old)
            if old==self._character then self:_stop("Character changed; enable flight again after spawning.") end
        end))
        table.insert(self._connections,self.Player.CharacterAdded:Connect(function(new)
            if new~=self._character then self:_stop("Character changed; enable flight again after spawning.") end
        end))
    end)
    if not ok then self:SetEnabled(false); error(message,0) end
end
function Controller:_stop(message)
    self:SetEnabled(false)
    if self._onStop then
        local callback=self._onStop
        task.defer(function() if not self.Destroyed then callback(message) end end)
    end
end
function Controller:_step(dt)
    if self.Player.Character~=self._character or not self._root.Parent or self._humanoid.Health<=0 then
        self:_stop("Flight stopped because your character is unavailable."); return
    end
    if (self._root.Position-self._anchor).Magnitude>1 and self._velocity.Magnitude<0.1 then self._anchor=self._root.Position end
    local camera=workspace.CurrentCamera
    local move=Vector3.zero
    local focused=UIS:GetFocusedTextBox()~=nil
    if camera and not focused then
        if UIS:IsKeyDown(Enum.KeyCode.W) then move=move+camera.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then move=move-camera.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then move=move+camera.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then move=move-camera.CFrame.RightVector end
        if move.Magnitude<0.001 then move=self._humanoid.MoveDirection end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then move=move+Vector3.yAxis end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move=move-Vector3.yAxis end
    end
    if move.Magnitude>1 then move=move.Unit end
    local smooth=SMOOTH[self.Settings.Smoothness]
    local rate=move.Magnitude>0 and smooth.accel or smooth.damp
    local alpha=1-math.exp(-rate*math.clamp(dt,0,0.25))
    self._velocity=self._velocity:Lerp(move*self.Settings.Speed,alpha)
    if focused or not camera then self._velocity=Vector3.zero end
    if self._velocity.Magnitude<0.05 and move.Magnitude==0 then self._velocity=Vector3.zero end
    self._linear.VectorVelocity=self._velocity
    self._align.Responsiveness=smooth.rot
    if camera then
        self._rotation=self._rotation:Lerp(camera.CFrame.Rotation,1-math.exp(-smooth.rot*math.clamp(dt,0,0.25)))
        self._align.CFrame=self._rotation
    end
    if self.Settings.Mode=="Hybrid" and move.Magnitude==0 and self._velocity.Magnitude<0.1 then
        self._root.CFrame=CFrame.new(self._anchor)*self._root.CFrame.Rotation
    else self._anchor=self._root.Position end
end
function Controller:UpdateSettings(patch)
    assert(not self.Destroyed,"Flight has been destroyed.")
    local nextSettings=table.clone(self.Settings)
    for key,value in pairs(patch) do
        assert(nextSettings[key]~=nil,"Unknown flight setting: " .. tostring(key))
        if key=="Speed" then
            assert(type(value)=="number" and value==value and math.abs(value)<math.huge,"Speed must be finite.")
            value=math.clamp(value,10,300)
        elseif key=="Mode" then assert(value=="Velocity" or value=="Hybrid","Unknown flight mode.")
        elseif key=="Smoothness" then assert(SMOOTH[value],"Unknown flight smoothing.")
        else assert(type(value)=="boolean","Enabled must be a boolean.") end
        nextSettings[key]=value
    end
    local enabled=nextSettings.Enabled; nextSettings.Enabled=self.Enabled; self.Settings=nextSettings
    self:SetEnabled(enabled)
end
function Controller:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false); self.Destroyed=true; self._onStop=nil
end
function Flight.new(settings,onStop)
    local self=setmetatable({Player=Players.LocalPlayer,Settings=Flight.GetDefaults(),Enabled=false,Destroyed=false,_connections={},_objects={},_onStop=onStop},Controller)
    assert(self.Player,"Flight must run on the client.")
    local ok,message=pcall(self.UpdateSettings,self,settings or {})
    if not ok then self:Destroy(); error(message,0) end
    return self
end
function Flight.Mount(context)
    local state,controls=context.State,context.Controls
    for key,value in pairs(Flight.GetDefaults()) do state[key]=value end
    local controller=Flight.new(state,function(message)
        if not context.IsActive() then return end
        state.Enabled=false; if controls.Enabled then controls.Enabled:Set(false) end
        context.Notify("Flight stopped",message,"Info")
    end)
    context.AddCleanup(function() state.Enabled=false; controller:Destroy() end)
    context.Section:AddParagraph({Title="Flight",Content="WASD to move, Space up, Ctrl down. Typing pauses movement. Flight turns off when your character changes."})
    controls.Enabled=context.Section:AddToggle({Title="Enable flight",Style="Switch",Default=false,Callback=function(value)
        local ok,message=pcall(controller.SetEnabled,controller,value)
        state.Enabled=controller.Enabled
        if not ok then if controls.Enabled then controls.Enabled:Set(false) end; context.Notify("Flight unavailable",tostring(message),"Error") end
    end})
    controls.Speed=context.Section:AddSlider({Title="Speed",Min=10,Max=300,Increment=10,Default=state.Speed,Callback=function(value) controller:UpdateSettings({Speed=value}); state.Speed=controller.Settings.Speed end})
    for _,option in ipairs({{Key="Mode",Title="Flight mode",Values={"Velocity","Hybrid"}},{Key="Smoothness",Title="Smoothing",Values={"Low","Medium","High"}}}) do
        controls[option.Key]=context.Section:AddDropdown({Title=option.Title,Values=option.Values,Default=state[option.Key],Callback=function(value) controller:UpdateSettings({[option.Key]=value}); state[option.Key]=value end})
    end
end
return Flight
