-- Noclip adapted from AnyCat.Dev's Tools V1. Original collision values are restored per character.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Noclip={Icon="ghost",Side="Full"}
local Controller={}; Controller.__index=Controller
local function disconnect(list)
    for _,connection in ipairs(list) do connection:Disconnect() end
    table.clear(list)
end
function Controller:_restore(part)
    local original=self._parts[part]
    if original==nil then return end
    self._parts[part]=nil
    pcall(function() if part.CanCollide==false then part.CanCollide=original end end)
end
function Controller:_releaseCharacter()
    disconnect(self._characterConnections)
    for part in pairs(self._parts) do self:_restore(part) end
    self._character=nil
end
function Controller:_attach(character)
    self:_releaseCharacter()
    self._character=character
    if not character then return end
    local function track(part)
        if part:IsA("BasePart") and self._parts[part]==nil then self._parts[part]=part.CanCollide end
    end
    table.insert(self._characterConnections,character.DescendantAdded:Connect(function(part)
        if self.Enabled and self._character==character then track(part) end
    end))
    table.insert(self._characterConnections,character.DescendantRemoving:Connect(function(part) self:_restore(part) end))
    for _,part in ipairs(character:GetDescendants()) do track(part) end
end
function Controller:_step()
    if self.Player.Character~=self._character then self:_attach(self.Player.Character) end
    for part in pairs(self._parts) do
        if part.Parent then part.CanCollide=false else self:_restore(part) end
    end
end
function Controller:SetEnabled(enabled)
    assert(not self.Destroyed,"Noclip has been destroyed.")
    assert(type(enabled)=="boolean","Enabled must be a boolean.")
    if enabled==self.Enabled then return end
    self.Enabled=enabled
    if not enabled then disconnect(self._connections); self:_releaseCharacter(); return end
    local ok,message=pcall(function()
        self:_attach(self.Player.Character)
        self:_step()
        table.insert(self._connections,RunService.Stepped:Connect(function()
            if not self.Enabled then return end
            local updated,updateError=pcall(self._step,self)
            if not updated then
                self:SetEnabled(false)
                local callback=self._onError
                if callback then task.defer(function() if not self.Destroyed then callback(tostring(updateError)) end end) end
            end
        end))
        table.insert(self._connections,self.Player.CharacterRemoving:Connect(function(character)
            if character==self._character then self:_releaseCharacter() end
        end))
    end)
    if not ok then self:SetEnabled(false); error(message,0) end
end
function Controller:Destroy()
    if self.Destroyed then return end
    self:SetEnabled(false); self.Destroyed=true; self._onError=nil
end
function Noclip.new(onError)
    assert(Players.LocalPlayer,"Noclip must run on the client.")
    return setmetatable({Player=Players.LocalPlayer,Enabled=false,Destroyed=false,_parts={},_connections={},_characterConnections={},_onError=onError},Controller)
end
function Noclip.Mount(context)
    local state,controls=context.State,context.Controls
    state.Enabled=false
    local controller=Noclip.new(function(message)
        if not context.IsActive() then return end
        state.Enabled=false; controls.Enabled:Set(false)
        context.Notify("Noclip stopped",message,"Error")
    end)
    context.AddCleanup(function() state.Enabled=false; controller:Destroy() end)
    context.Section:AddParagraph({Title="Noclip",Content="Restores original collision settings when disabled. Follows your character after respawning."})
    controls.Enabled=context.Section:AddToggle({Title="Enable noclip",Style="Switch",Default=false,Callback=function(value)
        local ok,message=pcall(controller.SetEnabled,controller,value)
        state.Enabled=controller.Enabled
        if not ok then if controls.Enabled then controls.Enabled:Set(false) end; context.Notify("Noclip unavailable",tostring(message),"Error") end
    end})
end
return Noclip
