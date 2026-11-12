-- Urban Reload ESP rendering and lifecycle regressions.
do
    local module = execute(espSource)
    assert(type(module.Mount) == "function" and type(module.new) == "function")
    assert(connectionCount() == 0 and drawingCount() == 0 and registry["estyxq-hub.ESPModule"] == nil)
    assert(module.GetDefaults().RefreshRate == 30 and module.GetDefaults().MaxDistance == 600)
    enemy.Character, teammate.Character = character(6), character(15)
    localPlayer.Neutral, teammate.Neutral = false, false
    local cam = world.CurrentCamera
    local function frame() RunService.RenderStepped:Fire(0.04); flushTasks() end
    local function lineSettings(extra)
        local settings = {Enabled=true, NamesEnabled=false, DistanceEnabled=false, HealthBarEnabled=false,
            BoxEnabled=false, GroundRingEnabled=false, HeadRingEnabled=false, DistanceFade=false, PulseEnabled=false}
        for key,value in pairs(extra or {}) do settings[key]=value end
        return settings
    end
    local esp = module.new(lineSettings())
    frame()
    assert(esp:GetStats().TrackedPlayers == 2 and esp:GetStats().VisiblePlayers == 1)
    assert(esp:GetStats().Drawings == 10 and drawingCount(true) == 10)
    teammate.Neutral = true
    frame()
    assert(esp:GetStats().VisiblePlayers == 2)
    teammate.Neutral = false
    frame()
    assert(esp:GetStats().VisiblePlayers == 1)
    esp:SetEnabled(false); esp:SetEnabled(true)
    for index=1,10 do
        local previous = enemy.Character
        enemy.CharacterRemoving:Fire(previous)
        enemy.Character = character(index % 2 == 0 and 6 or 15)
        enemy.CharacterAdded:Fire(enemy.Character)
        frame()
        assert(esp:GetStats().Drawings == (index % 2 == 0 and 10 or 28), "Respawn leaked drawings")
    end
    esp._accumulator = 0
    local before = cam.Calls
    RunService.RenderStepped:Fire(0.001)
    assert(cam.Calls == before, "Update rate must throttle projection work")
    frame()
    assert(cam.Calls - before <= 8, "Skeleton joints should share projected endpoints")
    esp:Destroy()
    assert(connectionCount() == 0 and drawingCount() == 0)

    esp = module.new(lineSettings({GroundRingEnabled=true, HeadRingEnabled=true, RingSegments=12,
        SkeletonEnabled=false, RingAnimationEnabled=false, AutoGroundOffset=false, GroundOffset=3, AutoHeadRadius=false, HeadRadius=0.8}))
    frame()
    local record = esp._records[enemy]
    assert(#record.GroundRing == 12 and #record.HeadRing == 12)
    local minY,maxY,minZ,maxZ = math.huge,-math.huge,math.huge,-math.huge
    for _,point in ipairs(record.HeadProjection) do
        minY,maxY=math.min(minY,point.Y),math.max(maxY,point.Y)
        minZ,maxZ=math.min(minZ,point.Z),math.max(maxZ,point.Z)
    end
    assert(maxY-minY>10 and math.abs(maxZ-minZ)<0.00001, "Head ring must stand upright, not lie in the ground plane")
    for _,point in ipairs(record.GroundProjection) do assert(math.abs(point.Y-330)<0.00001) end
    cam.CFrame.RightVector = vec(0.8,0,0.6)
    frame()
    local points = cam.ProjectionInputs
    local center = enemy.Character:FindFirstChild("Head").Position
    for index=#points-11,#points do
        local offset=points[index]-center
        assert(math.abs(-0.6*offset.X+0.8*offset.Z)<0.00001, "Head ring must follow camera orientation")
    end
    cam.CFrame.RightVector = vec(1,0,0)
    esp:UpdateSettings({AutoHeadRadius=true, AutoGroundOffset=true})
    frame()
    assert(math.abs(record.HeadProjection[1].X-411)<0.0001)
    local head = enemy.Character:Remove("Head")
    frame()
    for _,line in ipairs(record.HeadRing) do assert(not line.Visible) end
    enemy.Character:Add(head)
    local oldCamera = world.CurrentCamera
    world.CurrentCamera = nil
    frame()
    assert(drawingCount(true) == 0)
    world.CurrentCamera = camera()
    cam = world.CurrentCamera
    frame()
    assert(esp:GetStats().VisiblePlayers == 1)
    esp:UpdateSettings({MaxDistance=100})
    local targetRoot=enemy.Character:FindFirstChild("HumanoidRootPart")
    targetRoot.Position=vec(0,0,200)
    frame()
    assert(drawingCount(true) == 0, "Distance filtering must cover both rings")
    targetRoot.Position=vec(0,0,20)
    esp:Destroy()

    esp=module.new({Enabled=true, BoxEnabled=true, DistanceFade=false})
    frame()
    record=esp._records[enemy]
    assert(record.Tag and record.Tag.Visible and record.Tag.Text:find("Enemy",1,true) and record.Tag.Text:find("20 studs",1,true))
    assert(#record.Box==8 and #record.BoxOutline==8 and #record.HealthBar==2)
    local humanoid=enemy.Character:FindFirstChildOfClass("Humanoid")
    humanoid.Health=25
    frame()
    local full=record.HealthBar[1].To.Y-record.HealthBar[1].From.Y-2
    local filled=record.HealthBar[2].From.Y-record.HealthBar[2].To.Y
    assert(math.abs(filled-full*0.25)<0.0001, "Health bar must scale with actual MaxHealth")
    esp:UpdateSettings({UseDisplayNames=true,UseTeamColors=true})
    frame()
    assert(record.Tag.Text:find("Enemy display",1,true) and record.Tag.Color==enemy.TeamColor.Color)
    esp:UpdateSettings({VisibleOnly=true})
    world.RaycastResult={Instance=part("Wall")}
    frame()
    assert(drawingCount(true)==0)
    world.RaycastResult={Instance=enemy.Character:FindFirstChild("Torso")}
    frame()
    assert(record.Visible and world.LastRaycast.Parameters.FilterDescendantsInstances[1]==localPlayer.Character)
    world.RaycastResult=nil
    esp:UpdateSettings({VisibleOnly=false,MaxDistance=100,DistanceFade=true})
    targetRoot.Position=vec(0,0,90)
    frame()
    assert(record.Tag.Transparency>0 and record.Tag.Transparency<esp.Settings.Opacity)
    humanoid.Health=0
    frame()
    assert(not record.Visible and drawingCount(true)==0)
    humanoid.Health=100
    targetRoot.Position=vec(0,0,20)
    esp:UpdateSettings({NamesEnabled=false,DistanceEnabled=false,BoxEnabled=false,HealthBarEnabled=false})
    assert(record.Tag==nil and #record.Box==0 and #record.BoxOutline==0 and #record.HealthBar==0)
    local extra=player("Extra","Green",6)
    table.insert(Players.List,extra); Players.PlayerAdded:Fire(extra)
    frame()
    assert(esp:GetStats().TrackedPlayers==3)
    table.remove(Players.List,table.find(Players.List,extra)); Players.PlayerRemoving:Fire(extra)
    assert(esp:GetStats().TrackedPlayers==2 and esp._records[extra]==nil)
    assert(not pcall(esp.UpdateSettings,esp,{MaxDistance=0/0}))
    assert(not pcall(esp.UpdateSettings,esp,{Thickness=math.huge}))
    esp:UpdateSettings({RingSegments=500,Opacity=-10})
    assert(esp.Settings.RingSegments==64 and esp.Settings.Opacity==0)
    esp:Destroy()
    assert(drawingCount()==0 and connectionCount()==0)

    local errors,warnings=0,0
    failTextDrawing=true
    esp=module.new({Enabled=true},function() errors=errors+1 end,function() warnings=warnings+1 end)
    frame()
    assert(esp.Enabled and warnings==1 and errors==0 and esp._records[enemy].Tag==nil and drawingCount(true)>0)
    frame()
    assert(warnings==1,"Unsupported text should warn only once")
    failTextDrawing=false
    esp:UpdateSettings({NamesEnabled=true})
    frame()
    assert(esp._records[enemy].Tag and esp._records[enemy].Tag.Visible)
    esp:Destroy()
    failDrawingAt=createdDrawings+4
    esp=module.new({Enabled=true},function() errors=errors+1 end)
    frame()
    assert(not esp.Enabled and errors==1 and drawingCount()==0 and connectionCount()==0)
    esp:Destroy()
    failDrawingAt=nil
    environment.Drawing=nil
    assert(not pcall(module.new,{Enabled=true}))
    environment.Drawing=DrawingAPI
    assert(connectionCount()==0 and drawingCount()==0)
    esp=module.new({Enabled=true})
    frame()
    local latest=module.new({Enabled=true})
    assert(esp.Destroyed and registry["estyxq-hub.UrbanReload.ESP"]==latest)
    esp:Destroy()
    assert(registry["estyxq-hub.UrbanReload.ESP"]==latest)
    latest:Destroy()
    assert(drawingCount()==0 and connectionCount()==0)
    print("PASS: ESP R6/R15 respawns, upright camera-facing head rings, ground rings, labels/boxes/health, range/occlusion, throttling and cleanup")
    print("PASS: ESP unsupported Drawing/Text, allocation failures, validated settings and singleton replacement")
end
