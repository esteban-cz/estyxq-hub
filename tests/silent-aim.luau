-- Headless tests for the actual Urban Reload section/controller.
do
    local section=execute(silentSource)
    assert(type(section.Mount)=="function" and type(section.new)=="function")
    assert(hookInstallations==0 and connectionCount()==0 and drawingCount()==0)
    local install=environment.hookmetamethod
    environment.hookmetamethod=nil
    local unsupported=section.new()
    assert(not pcall(unsupported.SetEnabled,unsupported,true) and not unsupported.Enabled)
    unsupported:Destroy()
    environment.hookmetamethod=install
    local errors,warnings=0,0
    local controller=section.new(nil,function() errors+=1 end,function() warnings+=1 end)
    local firstCamera=world.CurrentCamera
    world.CurrentCamera=nil
    assert(not pcall(controller.SetEnabled,controller,true) and not controller.Enabled)
    world.CurrentCamera=firstCamera
    enemy.Character:FindFirstChild("Head").Position=vec(3,1,20)
    controller:SetEnabled(true)
    assert(controller.Enabled and hookInstallations==1 and drawingCount()==1)
    assert(controller:GetStatus().Target=="Enemy" and controller:GetStatus().CircleVisible)
    local circle=controller._circle
    assert(circle.Radius==130 and circle.Position.X==400 and circle.Position.Y==300)
    local ray=cameraRay(firstCamera,"ViewportPointToRay",400,300,0)
    assert(not ray.Original and math.abs(ray.Direction.Magnitude-1)<0.000001)
    assert(ray.Direction.X>0 and ray.Direction.Y>0)
    firstCamera.RayOrigin=vec(1,2,3)
    ray=cameraRay(firstCamera,"ScreenPointToRay",400,300,5)
    assert(ray.Origin==firstCamera.RayOrigin and ray.Direction.Y<0)
    assert(math.abs(ray.Direction.Magnitude-1)<0.000001)
    firstCamera.RayOrigin=nil
    executorCaller=true
    assert(cameraRay(firstCamera,"ViewportPointToRay",400,300).Original)
    executorCaller=false
    assert(cameraRay(firstCamera,"WorldToViewportPoint",400,300).Original)
    local calls=firstCamera.Calls
    for _=1,20 do cameraRay(firstCamera,"ViewportPointToRay",400,300) end
    assert(firstCamera.Calls==calls,"Ray calls must reuse the target cache")

    controller:UpdateSettings({HitChance=0})
    assert(cameraRay(firstCamera,"ViewportPointToRay",400,300).Original)
    controller:UpdateSettings({HitChance=100,FOV=25})
    assert(controller:GetStatus().Target==nil)
    controller:UpdateSettings({UseFOV=false})
    assert(controller:GetStatus().Target=="Enemy" and drawingCount()==0)
    controller:UpdateSettings({UseFOV=true,FOV=130,ShowFOV=false})
    assert(drawingCount()==0)
    controller:UpdateSettings({ShowFOV=true,FOVColor=color(0,1,1)})
    assert(drawingCount()==1 and controller._circle.Color.G==1)

    localPlayer.Neutral=true
    RunService.RenderStepped:Fire(0.04)
    assert(controller:GetStatus().Target=="Teammate","Neutral players must not be excluded as teammates")
    localPlayer.Neutral=false
    controller:UpdateSettings({WallCheck=true})
    world.RaycastResult={Instance=part("Wall")}
    RunService.RenderStepped:Fire(0.04)
    assert(controller:GetStatus().Target==nil)
    world.RaycastResult={Instance=enemy.Character:FindFirstChild("Torso")}
    RunService.RenderStepped:Fire(0.04)
    assert(controller:GetStatus().Target=="Enemy")
    assert(world.LastRaycast.Parameters.FilterDescendantsInstances[1]==localPlayer.Character)
    world.RaycastResult=nil
    controller:UpdateSettings({WallCheck=false,Part="UpperTorso"})
    assert(controller._target.Part.Name=="Torso","R6 torso fallback is required")
    enemy.Character=character(15)
    RunService.RenderStepped:Fire(0.04)
    assert(controller._target.Part.Name=="UpperTorso" and controller._target.Character==enemy.Character)
    local head=enemy.Character:FindFirstChild("Head")
    controller:UpdateSettings({Part="Head"})
    enemy.Character:FindFirstChildOfClass("Humanoid").Health=0
    assert(cameraRay(firstCamera,"ViewportPointToRay",400,300).Original)
    enemy.Character:FindFirstChildOfClass("Humanoid").Health=100
    head.Position=vec(0,0,1000)
    RunService.RenderStepped:Fire(0.04)
    assert(controller:GetStatus().Target==nil)
    head.Position=vec(0,0,20)
    local replacementCamera=camera()
    world.CurrentCamera=replacementCamera
    assert(cameraRay(firstCamera,"ViewportPointToRay",400,300).Original)
    assert(cameraRay(replacementCamera,"ViewportPointToRay",400,300).Original,"Wait for target refresh after camera replacement")
    RunService.RenderStepped:Fire(0.04)
    assert(not cameraRay(replacementCamera,"ViewportPointToRay",400,300).Original and hookInstallations==1)
    world.CurrentCamera=nil
    RunService.RenderStepped:Fire(0.04)
    assert(controller:GetStatus().Target==nil and drawingCount()==0)
    world.CurrentCamera=replacementCamera
    RunService.RenderStepped:Fire(0.04)
    assert(controller:GetStatus().Target=="Enemy" and drawingCount()==1)

    assert(not pcall(controller.UpdateSettings,controller,{FOV=0/0}))
    assert(not pcall(controller.UpdateSettings,controller,{MaxDistance=math.huge}))
    assert(not pcall(controller.UpdateSettings,controller,{Part="Invalid"}))
    controller:UpdateSettings({FOV=50000,RefreshRate=1})
    assert(controller.Settings.FOV==1000 and controller.Settings.RefreshRate==10)
    controller:SetEnabled(false)
    assert(connectionCount()==0 and drawingCount()==0 and registry["estyxq-hub.UrbanReload.SilentAim.Hook"].Owner==nil)
    assert(cameraRay(replacementCamera,"ViewportPointToRay",400,300).Original)
    controller:Destroy()

    -- Missing/failed Drawing support only affects the optional circle.
    environment.Drawing=nil
    controller=section.new({Enabled=true},nil,function() warnings+=1 end)
    assert(controller.Enabled and controller:GetStatus().Target=="Enemy" and drawingCount()==0)
    local warningCount=warnings
    RunService.RenderStepped:Fire(0.04)
    assert(warnings==warningCount)
    environment.Drawing=DrawingAPI
    controller:UpdateSettings({ShowFOV=true})
    assert(drawingCount()==1)
    controller:Destroy()
    failDrawingAt=createdDrawings+1
    controller=section.new({Enabled=true},nil,function() warnings+=1 end)
    assert(controller.Enabled and drawingCount()==0)
    controller:Destroy()
    failDrawingAt=nil

    -- A failed hook callback stops targeting and reports once without breaking camera calls.
    controller=section.new({Enabled=true},function() errors+=1 end)
    controller._redirect=function() error("simulated interception failure") end
    assert(cameraRay(replacementCamera,"ViewportPointToRay",400,300).Original)
    flushTasks()
    assert(not controller.Enabled and errors==1 and drawingCount()==0 and connectionCount()==0)
    controller:Destroy()

    local ownDispatcher=activeNamecall
    local otherCalls=0
    activeNamecall=function(...) otherCalls+=1; return ownDispatcher(...) end
    local installed=hookInstallations
    for _=1,4 do
        local fresh=execute(silentSource).new({Enabled=true})
        assert(hookInstallations==installed and fresh.Enabled)
        fresh:Destroy(); fresh:Destroy()
        assert(cameraRay(replacementCamera,"ViewportPointToRay",400,300).Original)
    end
    assert(otherCalls==4 and connectionCount()==0 and drawingCount()==0)
    assert(registry["estyxq-hub.UrbanReload.SilentAim"]==nil)
    print("PASS: Silent Aim selection, FOV/circle, team/wall checks, R6/R15 respawns, camera changes, ray length/depth, unsupported APIs and cleanup")
    print("PASS: reloads reuse one inert dispatcher and preserve another script's later hook")
end
