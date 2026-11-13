-- Anti-Kick hook ownership, partial installation, and reload regressions.
do
    local source=sources["shared/misc-[Misc]/anti-kick-[Anti-Kick].luau"]
    local module=execute(source)
    local beforeNamecall,beforeDirect=hookInstallations,directHookInstallations
    local controller=module.new()
    failKickHook=true
    assert(not pcall(controller.SetEnabled,controller,true) and not controller.Enabled)
    local broker=registry["estyxq-hub.AntiKick.Hooks"]
    assert(broker.NamecallInstalled and not broker.DirectInstalled and broker.Owner==nil)
    assert(hookInstallations==beforeNamecall+1)
    failKickHook=false
    controller:SetEnabled(true)
    assert(hookInstallations==beforeNamecall+1 and directHookInstallations==beforeDirect+1)
    namecallMethod="Kick"
    local forwarded=kickCalls
    assert(activeNamecall(localPlayer,"blocked")==nil and localPlayer:Kick("blocked")==nil)
    assert(kickCalls==forwarded and controller.Blocked==2)
    assert(directKick(enemy,"other player")=="kick forwarded" and kickCalls==forwarded+1)
    controller:SetEnabled(false)
    assert(activeNamecall(localPlayer,"allowed")=="kick forwarded" and localPlayer:Kick("allowed")=="kick forwarded")
    controller:Destroy()
    local previousDispatcher=activeNamecall
    local external=0
    activeNamecall=function(...) external=external+1; return previousDispatcher(...) end
    for _=1,5 do
        local fresh=execute(source).new()
        fresh:SetEnabled(true)
        assert(localPlayer:Kick("blocked")==nil)
        fresh:Destroy(); fresh:Destroy()
        assert(broker.Owner==nil and activeNamecall(localPlayer,"allowed")=="kick forwarded")
    end
    assert(external==5 and hookInstallations==beforeNamecall+1 and directHookInstallations==beforeDirect+1)
    local first,second=module.new(),module.new()
    first:SetEnabled(true); second:SetEnabled(true)
    assert(not first.Enabled and second.Enabled and broker.Owner==second)
    first:Destroy()
    assert(broker.Owner==second)
    second:Destroy()
    namecallMethod="ViewportPointToRay"
    assert(allConnections()==0)
    print("PASS: Anti-Kick reuses hooks across reloads, resumes partial installs, deactivates on cleanup and preserves later hooks")
end
