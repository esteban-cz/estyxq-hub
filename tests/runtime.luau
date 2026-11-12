-- Hub and section lifecycle regressions.
-- Verify the mock's control surface against the actual vendored Elements installer.
do
    local source = sources["menu.luau"]
    local start = assert(source:find("local function Elements(self, getParent)", 1, true))
    local finish = assert(source:find("\nend\n", start, true))
    local install = assert(realCompile(source:sub(start, finish + 4) .. "\nreturn Elements"))()
    local native = {}
    install(native, function() error("Installing methods should not create controls") end)
    local tab = uiContainer({}, { Options = {} }, true)
    local card = tab:AddSection({ Title = "API contract" })
    assert(type(tab.AddSection) == "function" and native.AddSection == nil and card.AddSection == nil)
    for name, method in pairs(card) do
        if type(method) == "function" and name:match("^Add") then
            assert(type(native[name]) == "function", "Mock exposes a missing native method: " .. name)
        end
    end
    assert(type(native.AddTitle) == "function" and type(native.AddDivider) == "function")
    card:Destroy()
end
print("PASS: section mock matches the actual NextUI Elements API and rejects nested AddSection")

-- Scope guarantees are independent from Roblox rendering.
do
    local runtime = execute(sources["core/runtime.luau"])
    local order, errors, canceled = {}, 0, false
    local scope = runtime.newScope({OnError=function() errors += 1 end})
    scope.AddCleanup(function() table.insert(order, "first") end)
    scope.AddCleanup(function() error("cleanup failure must not stop the rest") end)
    scope.AddCleanup(function() table.insert(order, "last") end)
    local delayed = scope.Delay(5, function() canceled = true end)
    local spawned = scope.Spawn(function() environment.task.wait(3); canceled = true end)
    local guard = scope.Guard(function() return 1, nil, 3 end)
    local values = table.pack(guard())
    assert(values.n == 3 and values[1] == 1 and values[2] == nil and values[3] == 3)
    local bad = scope.Guard(function() error("callback failure") end)
    bad(); bad()
    assert(errors == 1 and not scope.IsActive() and table.concat(order, ",") == "last,first")
    assert(coroutine.status(delayed) == "dead" and coroutine.status(spawned) == "dead")
    advance(10)
    assert(not canceled)
    local late = false
    scope.AddCleanup(function() late = true end)
    scope.Destroy()
    assert(late)
    print("PASS: scope cleanup order, cleanup errors, callback errors, return values, task cancellation and late cleanup")
end

local sectionFile = "urban-reloaded-[84448037861644]/combat-[Combat]/silent-aim-[Silent Aim].luau"
local healthyFile = "tests/healthy-section.luau"
local dependencyFile = "tests/dependency.luau"
sources[healthyFile] = [[return { Mount=function(context)
    context.State.Events = 0
    context.Connect(game:GetService("RunService").Heartbeat, function() context.State.Events += 1 end)
    context.AddCleanup(function() context.State.Cleaned = true end)
    context.Section:AddParagraph({Title="Healthy section", Content="Still running"})
end }]]
sources[dependencyFile] = [[getgenv().DependencyExecuted = true; return {}]]
local originalCatalog = sources["catalog.luau"]
overrides["catalog.luau"] = "local catalog=assert(loadstring(" .. string.format("%q",originalCatalog) .. "))()\ntable.insert(catalog.Games[1].Tabs[1].Sections,{Title=\"Healthy\",File=\"tests/healthy-section.luau\"})\nreturn catalog"
environment.game.PlaceId, environment.game.GameId = 84448037861644, 10769552054
local function healthy(hub) return hub.State.Game.Combat.Healthy end
local function boundary(hub) return hub.Sections.Combat["Silent Aim"] end
local function fallback(hub)
    for _, card in ipairs(hub.Tabs.Combat.Sections) do
        if card.Options.Title == "Silent Aim" then
            for _, control in ipairs(card.Elements) do
                if control.Options.Title == "Retry section" then return control end
            end
        end
    end
    error("Retry button missing")
end
local function noLeaks()
    flushTasks()
    assert(allConnections() == 0 and drawingCount() == 0 and not virtualHeld)
end
local function checkOtherSections(hub)
    assert(not hub.Tabs.ESP and hub.Tabs.Misc and hub.Tabs.Settings)
    assert(hub.Sections.Combat.Healthy.Status == "Ready" and not healthy(hub).Cleaned)
    local before = healthy(hub).Events
    advance(0.2)
    assert(healthy(hub).Events == before + 1)
end

-- Fetch, compile, module evaluation, shape validation and Mount each have a boundary.
for _, failure in ipairs({"download", "syntax", "evaluation", "shape", "mount"}) do
    downloadFailures[sectionFile] = failure == "download"
    overrides[sectionFile] = ({
        syntax="local = invalid", evaluation='error("module evaluation failed")',
        shape="return {}", mount='return { Mount=function(context) context.AddCleanup(function() getgenv().PartialMountCleaned = true end); error("mount failed") end }',
    })[failure]
    local hub = execute(loaderSource)
    local failed = boundary(hub)
    assert(failed.Status == "Error" and type(failed.Error) == "string")
    assert(not hub.Window.Destroyed and registry["estyxq-hub.Menu"] ~= nil)
    checkOtherSections(hub)
    fallback(hub)
    if failure == "mount" then assert(registry.PartialMountCleaned) end
    downloadFailures[sectionFile], overrides[sectionFile] = nil, nil
    fallback(hub).Options.Callback()
    flushTasks()
    assert(failed.Status == "Ready" and failed.Attempts == 2 and failed.Error == nil, failed.Error)
    assert(#hub.Tabs.Combat.Sections == 2, "Retry must replace its card")
    assert(not pcall(fallback, hub), "A successful retry must remove the error card")
    hub.Destroy()
    noLeaks()
end
print("PASS: isolated section download/compile/evaluation/Mount failures, retry controls, fresh loads and stable cards")

overrides[sectionFile] = [[return { Mount=function(context)
    context.State.Events = 0
    context.State.Active = context.IsActive
    context.AddCleanup(function() context.State.Cleaned = true end)
    context.Connect(game:GetService("RunService").Heartbeat, function()
        if context.State.FailEvent then error("event callback failed") end
        context.State.Events += 1
    end)
    context.Delay(30, function() context.State.Delayed = true end)
    context.Spawn(function() task.wait(20); context.State.Spawned = true end)
    context.Controls.Enabled = context.Section:AddToggle({Title="Break feature", Flag="test-owned-flag", Default=false,
        Callback=function(value) if value then error("control callback failed") end end})
    context.Controls.Action = context.Section:AddButton({Title="Break action", Callback=function() error("action callback failed") end})
    return function() context.State.ReturnedCleanup = true end
end }]]
do
    local hub = execute(loaderSource)
    assert(hub.Config.ScriptName == "Urban Reload" and hub.Config.ScriptVersion == gameVersion)
    assert(hub.Config.Subtitle == "Urban Reload tools." and not hub.Tabs.Playground)
    local state = hub.State.Game.Combat["Silent Aim"]
    local control = hub.Controls.Game.Combat["Silent Aim"].Enabled
    control:Set(true)
    flushTasks()
    assert(boundary(hub).Status == "Error" and state.Cleaned and state.ReturnedCleanup and not state.Active())
    assert(hub.Library.Options["test-owned-flag"] == nil)
    checkOtherSections(hub)
    local events = state.Events
    control:Set(true) -- Saved handles from a failed attempt must be harmless.
    advance(31)
    assert(state.Events == events and not state.Delayed and not state.Spawned)
    fallback(hub).Options.Callback(); flushTasks()
    local fresh = hub.State.Game.Combat["Silent Aim"]
    assert(fresh ~= state and boundary(hub).Status == "Ready")
    fresh.FailEvent = true
    advance(0.2)
    assert(boundary(hub).Status == "Error" and fresh.Cleaned)
    checkOtherSections(hub)
    fallback(hub).Options.Callback(); flushTasks()
    hub.Controls.Game.Combat["Silent Aim"].Action.Options.Callback()
    flushTasks()
    assert(boundary(hub).Status == "Error")
    hub.Destroy(); noLeaks()
end
print("PASS: guarded toggle/button/event callbacks, local cleanup, flag removal, canceled work and fresh retry state")

-- An owned background task failure also stops only its section.
overrides[sectionFile] = [[return { Mount=function(context)
    context.AddCleanup(function() context.State.Cleaned = true end)
    context.Delay(1, function() error("delayed failure") end)
end }]]
do
    local hub = execute(loaderSource)
    assert(boundary(hub).Status == "Ready")
    advance(1)
    assert(boundary(hub).Status == "Error" and hub.State.Game.Combat["Silent Aim"].Cleaned)
    checkOtherSections(hub)
    hub.Destroy(); noLeaks()
end

-- A section download yields independently while shared controls and the other section mount.
overrides[sectionFile] = nil
pauses[sectionFile] = true
do
    local hub = execute(loaderSource)
    assert(boundary(hub).Status == "Loading")
    assert(not boundary(hub).Retry(), "Ignore duplicate retries during a pending attempt")
    checkOtherSections(hub)
    hub.Controls.Shared.Misc["Anti-AFK"].Enabled:Set(true)
    local previousAFK=registry["estyxq-hub.AntiAFK"]
    assert(previousAFK.Enabled)
    local pending = httpPending[sectionFile]
    local nextHub = execute(loaderSource)
    assert(coroutine.status(pending) == "dead" and hub.Window.Destroyed)
    assert(boundary(nextHub).Status == "Ready" and registry["estyxq-hub.Menu"] ~= nil)
    assert(previousAFK.Destroyed)
    nextHub.Destroy(); noLeaks()
end

-- Even if an executor cannot cancel its HTTP coroutine, a retired attempt must not evaluate it.
ignoreCancellation = true
pauses[sectionFile] = true
do
    overrides[sectionFile] = 'getgenv().StaleSectionEvaluated = true; return {Mount=function() end}'
    local hub = execute(loaderSource)
    local pending = httpPending[sectionFile]
    hub.Destroy()
    resume(pending)
    assert(not registry.StaleSectionEvaluated and boundary(hub).Status == "Destroyed")
    noLeaks()
end
-- The same ownership check applies to a nested context.LoadModule request.
overrides[sectionFile] = [[return {Mount=function(context)
    context.Spawn(function() context.LoadModule("tests/dependency.luau") end)
end}]]
pauses[dependencyFile] = true
do
    local hub = execute(loaderSource)
    local pending = httpPending[dependencyFile]
    hub.Destroy()
    resume(pending)
    assert(not registry.DependencyExecuted)
    noLeaks()
end
ignoreCancellation = false
overrides[sectionFile] = nil
print("PASS: independent downloads, duplicate retry prevention, reload cancellation and stale source evaluation guards")


-- Default-value callbacks may run while a native control is still being constructed.
overrides[sectionFile] = [[return {Mount=function(context)
    context.AddCleanup(function() context.State.Cleaned = true end)
    context.Section:AddToggle({Title="Immediate failure", Default=true, Flag="immediate-flag", Callback=function() error("default failed") end})
    return function() context.State.LateReturnCleaned = true end
end}]]
do
    local hub = execute(loaderSource)
    local state = hub.State.Game.Combat["Silent Aim"]
    assert(boundary(hub).Status == "Error" and state.Cleaned and state.LateReturnCleaned)
    assert(hub.Library.Options["immediate-flag"] == nil)
    fallback(hub)
    checkOtherSections(hub)
    hub.Destroy(); noLeaks()
end
print("PASS: constructor callbacks fail safely and late returned cleanup runs immediately")

-- Exercise the actual added NextUI section destructor rather than only its test double.
do
    local _, body = assert(sources["menu.luau"]:match("([ \t]*)function sec:Destroy%(%)\n(.-)\n%1end"))
    local destroy = assert(realCompile("return function(self, tab, card, collapseKey, NextUI)\n" .. body .. "\nend"))()
    local removed = false
    local card = {Destroy=function() removed=true end}
    local other = {}
    local option = {}
    local library = {Options={collapse=option}, Flags={collapse=true}, _Prune=function() end}
    local tab = {_sections={{frame=card},{frame=other}}}
    destroy({_collapseOption=option},tab,card,"collapse",library)
    assert(removed and #tab._sections == 1 and tab._sections[1].frame == other)
    assert(library.Options.collapse == nil and library.Flags.collapse == nil)
    library.Options.collapse = other
    destroy({_collapseOption=option},tab,card,"collapse",library)
    assert(library.Options.collapse == other, "Destroying an old card must preserve newer flag ownership")
end
print("PASS: actual NextUI card destructor removes search registration and preserves newer option ownership")


-- The actual Elements connection helper releases native control input listeners on card destruction.
do
    local helper = assert(sources["menu.luau"]:match("local function Elements%(self, getParent%)\n(.-)\n[ \t]*local function hgt"))
    local connect = assert(realCompile("return function(getParent)\n" .. helper .. "\nreturn connect\nend"))()
    local owner = {Destroying=signal()}
    local event = signal()
    local calls = 0
    local connection = connect(function() return owner end)(event, function() calls += 1 end)
    event:Fire()
    owner.Destroying:Fire()
    event:Fire()
    assert(calls == 1 and not connection.Connected)
    -- Destroying an Instance disconnects its own Destroying listeners in Roblox.
    for _, owned in ipairs(owner.Destroying.Connections) do owned:Disconnect() end
    noLeaks()
end
print("PASS: actual native control listeners disconnect when their container is destroyed")

-- Entry-point routing and shared UI behavior still use actual application source.
do
    local hub = execute(loaderSource)
    local encoded = false
    for _, url in ipairs(requests) do if url:find("silent-aim-%5BSilent%20Aim%5D.luau",1,true) then encoded=true end end
    assert(encoded and consoleMessages[#consoleMessages]:find("Loaded Urban Reload v" .. gameVersion .. " successfully",1,true))
    hub.Window:Close()
    assert(hub.Pill.Visible and not hub.Window.Visible)
    hub.Pill.Activated:Fire()
    assert(hub.Window.Visible and not hub.Pill.Visible)
    hub.Controls.Theme:Set("Aqua")
    assert(hub.Pill.BackgroundColor3 == hub.Library.Theme.Card)
    hub.Destroy(); noLeaks()
    environment.game.PlaceId = 999999999
    hub = execute(loaderSource)
    assert(hub.Tabs.Combat, "Experience ID should include another place in the same game")
    hub.Destroy()
    environment.game.GameId = 123456
    hub = execute(loaderSource)
    assert(hub.Config.ScriptName == "Universal" and hub.Tabs.Misc and not hub.Tabs.Playground and not hub.Tabs.Combat and not hub.Tabs.ESP)
    local owner = registry["estyxq-hub.Menu"]
    downloadFailures["main.luau"] = true
    assert(not pcall(execute,loaderSource) and registry["estyxq-hub.Menu"] == owner and not hub.Window.Destroyed)
    downloadFailures["main.luau"] = nil
    hub.Destroy(); noLeaks()
    overrides["catalog.luau"] = [[return {SchemaVersion=1, SharedTabs={}, Games={
        {Id="experience",Name="Experience",Version="1",Subtitle="All places",GameIds={123456},PlaceIds={},Tabs={}},
        {Id="place",Name="Place",Version="2",Subtitle="One place",GameIds={},PlaceIds={999999999},Tabs={}},
    }}]]
    hub = execute(loaderSource)
    assert(hub.Config.ScriptName == "Place" and hub.Config.ScriptVersion == "2")
    hub.Destroy(); noLeaks()
end
print("PASS: game routing/precedence, URL encoding, success log, reopen pill, theme changes and failed loader preservation")

-- Critical source failures preserve the currently working UI until the replacement is prepared.
do
    overrides["catalog.luau"] = nil
    environment.game.PlaceId, environment.game.GameId = 0, 0
    local hub = execute(loaderSource)
    local owner = registry["estyxq-hub.Menu"]
    for _, file in ipairs({"main.luau", "menu.luau", "core/runtime.luau"}) do
        downloadFailures[file] = true
        assert(not pcall(execute,loaderSource))
        assert(registry["estyxq-hub.Menu"] == owner and not hub.Window.Destroyed)
        downloadFailures[file] = nil
        overrides[file] = "local = invalid"
        assert(not pcall(execute,loaderSource))
        assert(registry["estyxq-hub.Menu"] == owner and not hub.Window.Destroyed)
        overrides[file] = nil
    end
    pauses["menu.luau"] = true
    local pending = coroutine.create(function() return execute(loaderSource) end)
    assert(resume(pending) == "HTTP menu.luau")
    assert(registry["estyxq-hub.Menu"] == owner and not hub.Window.Destroyed)
    local newest = execute(loaderSource)
    local newestOwner = registry["estyxq-hub.Menu"]
    resume(pending)
    assert(registry["estyxq-hub.Menu"] == newestOwner and not newest.Window.Destroyed)
    newest.Destroy(); noLeaks()
end
print("PASS: staged framework fetch/compile failures preserve the existing hub; concurrent startups keep the newest owner")


do
    local hub = execute(loaderSource)
    local owner = registry["estyxq-hub.Menu"]
    pauses["core/runtime.luau"] = true
    local pending = coroutine.create(function() return execute(loaderSource) end)
    assert(resume(pending) == "HTTP core/runtime.luau")
    downloadFailures["catalog.luau"] = true
    assert(not pcall(execute,loaderSource))
    downloadFailures["catalog.luau"] = nil
    resume(pending)
    assert(registry["estyxq-hub.Menu"] == owner and not hub.Window.Destroyed)
    assert(registry["estyxq-hub.Menu.Starting"] == nil)
    hub.Destroy(); noLeaks()
end
print("PASS: a superseded loader cannot replace the working hub after a newer startup fails")



-- Exercise the real section UI with both controllers active, including reload and retry.
do
    overrides["catalog.luau"], overrides[sectionFile] = nil, nil
    environment.game.PlaceId, environment.game.GameId = 84448037861644,10769552054
    local hub=execute(loaderSource)
    assert(hub.Sections.Combat["Silent Aim"].Status=="Ready" and hub.Sections.Misc["Anti-AFK"].Status=="Ready")
    local combat=hub.Controls.Game.Combat["Silent Aim"]
    local misc=hub.Controls.Shared.Misc["Anti-AFK"]
    combat.Enabled:Set(true)
    misc.Enabled:Set(true)
    local silent,afk=registry["estyxq-hub.UrbanReload.SilentAim"],registry["estyxq-hub.AntiAFK"]
    assert(silent.Enabled and afk.Enabled and drawingCount()==1)
    combat.FOV:Set(240)
    combat.Part:Set("HumanoidRootPart")
    assert(silent.Settings.FOV==240 and silent._circle.Radius==240 and silent.Settings.Part=="HumanoidRootPart")
    combat.ShowFOV:Set(false)
    assert(drawingCount()==0 and silent.Enabled)
    combat.ShowFOV:Set(true)
    assert(drawingCount()==1)
    misc.Test.Options.Callback()
    assert(virtualHeld)
    hub.Window:Close()
    assert(silent.Enabled and afk.Enabled and hub.Pill.Visible)
    local installed=hookInstallations
    local fresh=execute(loaderSource)
    assert(hub.Window.Destroyed and silent.Destroyed and afk.Destroyed and not virtualHeld)
    assert(drawingCount()==0 and hookInstallations==installed)
    assert(not fresh.State.Game.Combat["Silent Aim"].Enabled and not fresh.State.Shared.Misc["Anti-AFK"].Enabled)
    local old=registry["estyxq-hub.UrbanReload.SilentAim"]
    fresh.Sections.Combat["Silent Aim"].Retry()
    assert(old.Destroyed and fresh.Sections.Combat["Silent Aim"].Status=="Ready")
    fresh.Destroy(); noLeaks()
    environment.game.PlaceId,environment.game.GameId=0,0
end
print("PASS: real Combat and shared Misc controls, live settings, optional circle, minimize, reload and retry cleanup")


-- Urban Reload Visuals uses the actual section and controller with guarded inline page controls.
do
    environment.game.PlaceId, environment.game.GameId = 84448037861644, 10769552054
    overrides["catalog.luau"], overrides[sectionFile] = nil, nil
    local hub = execute(loaderSource)
    local boundary = hub.Sections.Visuals.ESP
    assert(boundary.Status == "Ready", boundary.Error)
    assert(hub.Tabs.Visuals and hub.Tabs.Combat and hub.Tabs.Misc and not hub.Tabs.ESP)
    local controls = hub.Controls.Game.Visuals.ESP
    local state = hub.State.Game.Visuals.ESP
    assert(not state.Enabled and registry["estyxq-hub.UrbanReload.ESP"] and drawingCount() == 0)
    controls.Enabled:Set(true)
    RunService.RenderStepped:Fire(0.04)
    local controller = registry["estyxq-hub.UrbanReload.ESP"]
    assert(controller.Enabled and controller:GetStats().VisiblePlayers == 1 and drawingCount() > 0)
    controls.Preset:Set("Minimal")
    RunService.RenderStepped:Fire(0.04)
    assert(not state.HeadRingEnabled and not state.GroundRingEnabled and not state.NamesEnabled and not state.HealthBarEnabled)
    assert(controls.HeadRingEnabled:Get() == false and controller.Settings.RefreshRate == 30)
    controls.Preset:Set("Detailed")
    RunService.RenderStepped:Fire(0.04)
    assert(state.BoxEnabled and state.HeadRingEnabled and controller.Settings.RingSegments == 32)
    controls.Color:Set(color(1,0.5,0.2))
    controls.HeadOffset:Set(0.5)
    controls.MaxDistance:Set(400)
    assert(state.Color.R == 1 and controller.Settings.HeadOffset == 0.5 and controller.Settings.MaxDistance == 400)
    controls.Reset.Options.Callback()
    RunService.RenderStepped:Fire(0.04)
    assert(controller.Enabled and state.Enabled and state.MaxDistance == 600 and state.RefreshRate == 30 and not state.BoxEnabled)
    assert(controls.Preset:Get() == "Balanced")
    hub.Controls.Game.Combat["Silent Aim"].Enabled:Set(true)
    hub.Controls.Shared.Misc["Anti-AFK"].Enabled:Set(true)
    local aim, afk = registry["estyxq-hub.UrbanReload.SilentAim"], registry["estyxq-hub.AntiAFK"]
    hub.Window:Close()
    assert(controller.Enabled and aim.Enabled and afk.Enabled and hub.Pill.Visible)
    local fresh = execute(loaderSource)
    assert(controller.Destroyed and aim.Destroyed and afk.Destroyed and drawingCount() == 0)
    assert(fresh.Sections.Visuals.ESP.Status == "Ready" and not fresh.State.Game.Visuals.ESP.Enabled)
    local old = registry["estyxq-hub.UrbanReload.ESP"]
    fresh.Sections.Visuals.ESP.Retry()
    assert(old.Destroyed and fresh.Sections.Visuals.ESP.Status == "Ready")
    -- Callbacks added inside the inline pages must still be scoped to the section.
    local broken = registry["estyxq-hub.UrbanReload.ESP"]
    broken.UpdateSettings = function() error("inline page setting failure") end
    fresh.Controls.Game.Visuals.ESP.Color:Set(color(0,1,1))
    flushTasks()
    assert(fresh.Sections.Visuals.ESP.Status == "Error" and broken.Destroyed)
    assert(fresh.Sections.Combat["Silent Aim"].Status == "Ready" and fresh.Sections.Misc["Anti-AFK"].Status == "Ready")
    fresh.Destroy(); noLeaks()
    environment.game.PlaceId, environment.game.GameId = 0, 0
end
print("PASS: Visuals ESP controls, presets/reset, guarded inline pages, concurrent features and retry/reload cleanup")

-- Run the actual local entry point against executor-style workspace files.
do
    local remoteRequests = #requests
    local reads = {}
    environment.readfile = function(filename)
        assert(filename:sub(1,15) == "estyxq-hub/src/")
        local file=filename:sub(16)
        table.insert(reads,file)
        if file=="menu.luau" then return "MOCK_NEXTUI" end
        return assert(sources[file], "Local source missing: " .. file)
    end
    local hub=execute(sources["dev-loader.luau"])
    assert(hub.Tabs.Misc and not hub.Tabs.Combat)
    assert(#requests==remoteRequests and table.find(reads,"catalog.luau") and table.find(reads,"shared/misc-[Misc]/anti-afk-[Anti-AFK].luau"))
    hub.Controls.Shared.Misc["Anti-AFK"].Enabled:Set(true)
    assert(registry["estyxq-hub.AntiAFK"].Enabled)
    hub.Destroy(); noLeaks()
    environment.readfile=nil
    assert(not pcall(execute,sources["dev-loader.luau"]), "Unsupported local IO should fail clearly")
end
print("PASS: local development loader reads active project files and does not fetch hub source from GitHub")

print("All runtime checks passed (Roblox/NextUI test doubles; live executor verification remains separate).")
