-- Jump modes adapted from AnyCat.Dev's Tools V1; listeners only exist while enabled.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Jump={Icon="arrow-up",Side="Full"}
local Controller={}; Controller.__index=Controller
function Jump.GetDefaults() return {Enabled=false,Mode="Always",ExtraJumps=3,Power=50} end
function Controller:_body()
    local character=self.Player.Character
    if character~=self._character then
        self._character=character; self.Remaining=self.Settings.ExtraJumps; self._held=false
    end
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health<=0 or humanoid.PlatformStand then return nil end
    return humanoid,root
end
function Controller:_boost(hold)
    if UIS:GetFocusedTextBox() then return false end
    local humanoid,root=self:_body()
    if not humanoid then return false end
    local velocity=root.AssemblyLinearVelocity
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    root.AssemblyLinearVelocity=Vector3.new(velocity.X,hold and self.Settings.Power or math.max(velocity.Y,self.Settings.Power),velocity.Z)
    return true
end
function Controller:RequestJump()
    if not self.Enabled or UIS:GetFocusedTextBox() then return false end
    local humanoid=self:_body()
    if not humanoid then return false end
    local state=humanoid:GetState()
    local airborne=humanoid.FloorMaterial==Enum.Material.Air or state==Enum.HumanoidStateType.Jumping or state==Enum.HumanoidStateType.Freefall
    if self.Settings.Mode=="Multi" and airborne then
        if self.Remaining<=0 then return false end
        if self:_boost(false) then self.Remaining=self.Remaining-1; return true end
        return false
    end
    return self:_boost(self.Settings.Mode=="Hold")
end
function Controller:_step()
    local humanoid=self:_body()
    if not humanoid then return end
    if humanoid.FloorMaterial~=Enum.Material.Air and humanoid:GetState()~=Enum.HumanoidStateType.Jumping then self.Remaining=self.Settings.ExtraJumps end
    if self.Settings.Mode=="Hold" and self._held then self:_boost(true) end
end
function Controller:SetEnabled(enabled)
    assert(not self.Destroyed,"Jump controls have been destroyed.")
    assert(type(enabled)=="boolean","Enabled must be a boolean.")
    if enabled==self.Enabled then return end
    self.Enabled,self.Settings.Enabled=enabled,enabled
    self._held=false; self.Remaining=self.Settings.ExtraJumps
    if not enabled then
        for _,connection in ipairs(self._connections) do connection:Disconnect() end
        table.clear(self._connections); self._character=nil; return
    end
    self._character=self.Player.Character
    local function guarded(callback)
        return function(...)
            if not self.Enabled then return end
            local ok,message=pcall(callback,...)
            if not ok then
                self:SetEnabled(false)
                local report=self._onError
                if report then task.defer(function() if not self.Destroyed then report(tostring(message)) end end) end
            end
        end
    end
    local ok,message=pcall(function()
        table.insert(self._connections,UIS.InputBegan:Connect(guarded(function(input,processed)
            if processed or UIS:GetFocusedTextBox() then return end
            if input.KeyCode==Enum.KeyCode.Space or input.KeyCode==Enum.KeyCode.ButtonA then
                self:_body()
                self._held=true; self._lastRequest=os.clock(); self:RequestJump()
            end
        end)))
        table.insert(self._connections,UIS.InputEnded:Connect(guarded(function(input)
            if input.KeyCode==Enum.KeyCode.Space or input.KeyCode==Enum.KeyCode.ButtonA or input.UserInputType==Enum.UserInputType.Touch then self._held=false end
        end)))
        table.insert(self._connections,UIS.JumpRequest:Connect(guarded(function()
            if self._held or os.clock()-self._lastRequest<0.12 then return end
            self._lastRequest=os.clock()
            self:RequestJump()
            if UIS.TouchEnabled then self._held=true end
        end)))
        table.insert(self._connections,RunService.Heartbeat:Connect(guarded(function() self:_step() end)))
    end)
    if not ok then self:SetEnabled(false); error(message,0) end
end
function Controller:UpdateSettings(patch)
    assert(not self.Destroyed,"Jump controls have been destroyed.")
    local settings=table.clone(self.Settings)
    for key,value in pairs(patch) do
        assert(settings[key]~=nil,"Unknown jump setting: " .. tostring(key))
        if key=="Mode" then assert(table.find({"Always","Multi","Hold"},value),"Unknown jump mode.")
        elseif key=="Enabled" then assert(type(value)=="boolean","Enabled must be a boolean.")
        else
            assert(type(value)=="number" and value==value and math.abs(value)<math.huge,key .. " must be finite.")
            value=math.clamp(value,key=="ExtraJumps" and 1 or 10,key=="ExtraJumps" and 10 or 150)
            if key=="ExtraJumps" then value=math.round(value) end
        end
        settings[key]=value
    end
    local enabled=settings.Enabled; settings.Enabled=self.Enabled; self.Settings=settings
    self.Remaining=settings.ExtraJumps; self._held=false
    self:SetEnabled(enabled)
end
function Controller:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false); self.Destroyed=true; self._onError=nil
end
function Jump.new(settings,onError)
    assert(Players.LocalPlayer,"Jump controls must run on the client.")
    local self=setmetatable({Player=Players.LocalPlayer,Settings=Jump.GetDefaults(),Enabled=false,Destroyed=false,_connections={},_lastRequest=-math.huge,_onError=onError},Controller)
    local ok,message=pcall(self.UpdateSettings,self,settings or {})
    if not ok then self:Destroy(); error(message,0) end
    return self
end
function Jump.Mount(context)
    local state,controls=context.State,context.Controls
    for key,value in pairs(Jump.GetDefaults()) do state[key]=value end
    local controller=Jump.new(state,function(message)
        if not context.IsActive() then return end
        state.Enabled=false; controls.Enabled:Set(false)
        context.Notify("Jump controls stopped",message,"Error")
    end)
    context.AddCleanup(function() state.Enabled=false; controller:Destroy() end)
    context.Section:AddParagraph({Title="Jump modes",Content="Always: unlimited jump presses. Multi: a limited number of extra jumps. Hold: keep rising while jump is held. Pauses during flight or typing."})
    controls.Enabled=context.Section:AddToggle({Title="Enable jump modifiers",Style="Switch",Default=false,Callback=function(value)
        local ok,message=pcall(controller.SetEnabled,controller,value)
        state.Enabled=controller.Enabled
        if not ok then if controls.Enabled then controls.Enabled:Set(false) end; context.Notify("Jump controls unavailable",tostring(message),"Error") end
    end})
    controls.Mode=context.Section:AddDropdown({Title="Jump mode",Values={"Always","Multi","Hold"},Default=state.Mode,Callback=function(value) controller:UpdateSettings({Mode=value}); state.Mode=value end})
    controls.ExtraJumps=context.Section:AddSlider({Title="Extra jumps",Description="Used in Multi mode.",Min=1,Max=10,Increment=1,Default=state.ExtraJumps,Callback=function(value) controller:UpdateSettings({ExtraJumps=value}); state.ExtraJumps=controller.Settings.ExtraJumps end})
    controls.Power=context.Section:AddSlider({Title="Upward speed",Min=10,Max=150,Increment=5,Default=state.Power,Callback=function(value) controller:UpdateSettings({Power=value}); state.Power=controller.Settings.Power end})
end
return Jump
