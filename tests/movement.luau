-- Movement controllers run against deterministic physics/input doubles.
do
    local Enum=environment.Enum
    local flightModule=execute(sources["shared/movement-[Movement]/fly-[Flight].luau"])
    local noclipModule=execute(sources["shared/movement-[Movement]/noclip-[Noclip].luau"])
    local jumpModule=execute(sources["shared/movement-[Movement]/jump-[Jump].luau"])
    local function livePhysics()
        local count=0
        for _,object in ipairs(physicsInstances) do if not object.Destroyed then count=count+1 end end
        return count
    end
    local function body()
        local character=localPlayer.Character
        return character:FindFirstChild("HumanoidRootPart"),character:FindFirstChildOfClass("Humanoid")
    end
    local function respawn()
        local previous=localPlayer.Character
        localPlayer.CharacterRemoving:Fire(previous)
        localPlayer.Character=character(6)
        localPlayer.CharacterAdded:Fire(localPlayer.Character)
    end
    local root,hum=body()
    hum.Health,hum.PlatformStand,hum.AutoRotate=100,false,false
    hum:ChangeState(Enum.HumanoidStateType.Running)
    assert(livePhysics()==0 and allConnections()==0)
    local stopped=0
    local fly=flightModule.new(nil,function() stopped=stopped+1 end)
    fly:SetEnabled(true)
    assert(livePhysics()==3 and hum.PlatformStand and not hum.AutoRotate)
    assert(fly._linear.RelativeTo==Enum.ActuatorRelativeTo.World and fly._linear.ForceLimitsEnabled==false)
    assert(fly._align.Mode==Enum.OrientationAlignmentMode.OneAttachment)
    UserInputService.Keys[Enum.KeyCode.W]=true
    UserInputService.Keys[Enum.KeyCode.D]=true
    UserInputService.Keys[Enum.KeyCode.Space]=true
    advance(0.1)
    assert(fly._linear.VectorVelocity.Magnitude>0 and fly._linear.VectorVelocity.Magnitude<=50.0001)
    UserInputService.Focused={}
    advance(0.1)
    assert(fly._linear.VectorVelocity.Magnitude==0,"Typing must pause flight")
    UserInputService.Focused=nil
    table.clear(UserInputService.Keys)
    fly:UpdateSettings({Mode="Hybrid",Speed=100,Smoothness="High"})
    root.Position=vec(50,25,30)
    advance(0.1)
    assert(root.Position.X==50 and root.Position.Y==25,"Hybrid flight must respect an external teleport")
    fly:SetEnabled(false)
    assert(not hum.PlatformStand and hum.AutoRotate==false and hum:GetState()==Enum.HumanoidStateType.Running)
    assert(livePhysics()==0 and root.AssemblyLinearVelocity.Magnitude==0 and allConnections()==0)
    hum.AutoRotate=true
    failInstanceClass="AlignOrientation"
    assert(not pcall(fly.SetEnabled,fly,true))
    assert(not fly.Enabled and not hum.PlatformStand and hum.AutoRotate and livePhysics()==0 and allConnections()==0)
    failInstanceClass=nil
    fly:SetEnabled(true)
    respawn(); flushTasks()
    assert(not fly.Enabled and stopped==1 and livePhysics()==0)
    fly:Destroy()
    assert(not pcall(flightModule.new,{Speed=math.huge}))
    local without=localPlayer.Character; localPlayer.Character=nil
    local empty=flightModule.new()
    assert(not pcall(empty.SetEnabled,empty,true))
    empty:Destroy(); localPlayer.Character=without

    root,hum=body()
    local head=localPlayer.Character:FindFirstChild("Head")
    head.CanCollide=false
    local clip=noclipModule.new()
    clip:SetEnabled(true)
    assert(not root.CanCollide and not head.CanCollide)
    local accessoryPart=part("AccessoryHandle")
    local accessory={Name="Accessory",IsA=function() return false end,GetDescendants=function() return {accessoryPart} end}
    accessoryPart.Parent=accessory
    localPlayer.Character:Add(accessory)
    RunService.Stepped:Fire(testTime,0.02)
    assert(not accessoryPart.CanCollide)
    localPlayer.Character.DescendantRemoving:Fire(accessoryPart)
    accessoryPart.Parent=nil
    assert(accessoryPart.CanCollide,"Detached parts must regain their original collision")
    clip:SetEnabled(false)
    assert(root.CanCollide and not head.CanCollide and allConnections()==0)
    clip:SetEnabled(true)
    local oldRoot=root
    respawn()
    root,hum=body()
    RunService.Stepped:Fire(testTime,0.02)
    assert(oldRoot.CanCollide and not root.CanCollide and clip.Enabled)
    clip:Destroy()
    assert(root.CanCollide and allConnections()==0)

    local jump=jumpModule.new({Mode="Multi",ExtraJumps=2})
    jump:SetEnabled(true)
    hum:ChangeState(Enum.HumanoidStateType.Running)
    assert(jump:RequestJump() and jump.Remaining==2)
    assert(jump:RequestJump() and jump.Remaining==1)
    assert(jump:RequestJump() and jump.Remaining==0)
    assert(not jump:RequestJump())
    hum:ChangeState(Enum.HumanoidStateType.Landed)
    advance(0.05)
    assert(jump.Remaining==2)
    local input={KeyCode=Enum.KeyCode.Space,UserInputType="Keyboard"}
    UserInputService.InputBegan:Fire(input,false)
    local remaining=jump.Remaining
    advance(0.2); UserInputService.JumpRequest:Fire()
    assert(jump.Remaining==remaining,"A held keyboard request must not consume extra jumps")
    UserInputService.InputEnded:Fire(input)
    UserInputService.InputBegan:Fire(input,false)
    assert(jump.Remaining==remaining-1)
    UserInputService.InputEnded:Fire(input)
    jump:UpdateSettings({Mode="Hold",Power=60})
    UserInputService.InputBegan:Fire(input,false)
    root.AssemblyLinearVelocity=vec(3,-20,4)
    advance(0.05)
    assert(root.AssemblyLinearVelocity.Y==60 and root.AssemblyLinearVelocity.X==3 and root.AssemblyLinearVelocity.Z==4)
    UserInputService.Focused={}
    root.AssemblyLinearVelocity=vec(3,-20,4)
    advance(0.05)
    assert(root.AssemblyLinearVelocity.Y==-20)
    UserInputService.Focused=nil
    UserInputService.InputEnded:Fire(input)
    advance(0.05)
    assert(root.AssemblyLinearVelocity.Y==-20)
    hum.PlatformStand=true
    assert(not jump:RequestJump(),"Jump modifiers must pause while flight controls the humanoid")
    hum.PlatformStand=false
    respawn()
    advance(0.05)
    assert(jump.Remaining==2 and not jump._held)
    jump:SetEnabled(false)
    root,hum=body()
    root.AssemblyLinearVelocity=vec(0,-5,0)
    UserInputService.InputBegan:Fire(input,false); UserInputService.JumpRequest:Fire(); advance(0.05)
    assert(root.AssemblyLinearVelocity.Y==-5 and allConnections()==0)
    jump:Destroy()
    assert(not pcall(jumpModule.new,{Power=0/0}))
    assert(not pcall(jumpModule.new,{Mode="Invalid"}))
    root.Position=vec(0,0,0)
    root.AssemblyLinearVelocity=vec(0,0,0)
    assert(livePhysics()==0 and allConnections()==0)
    print("PASS: flight constraints/typing/teleports/rollback/respawn, collision restoration/dynamic parts, jump modes/limits/hold and cleanup")
end
