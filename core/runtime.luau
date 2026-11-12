-- Shared lifecycle and section boundaries. No game logic belongs in this module.
local Runtime = {}

function Runtime.newScope(options)
    options = options or {}
    local alive, failed = true, false
    local cleanups, threads = {}, {}
    local scope = {}

    function scope.IsActive()
        return alive and (not options.IsActive or options.IsActive())
    end

    local function clean(callback)
        local ok, message = pcall(callback)
        if not ok then
            (options.OnCleanupError or warn)("[estyxq Hub cleanup] " .. tostring(message))
        end
    end

    function scope.AddCleanup(callback)
        assert(type(callback) == "function", "Cleanup must be a function.")
        if scope.IsActive() then table.insert(cleanups, callback) else clean(callback) end
        return callback
    end

    function scope.Destroy()
        if not alive then return end
        alive = false
        local running = coroutine.running()
        for thread in pairs(threads) do
            if thread ~= running and coroutine.status(thread) ~= "dead" then
                clean(function() task.cancel(thread) end)
            end
        end
        table.clear(threads)
        local pending = cleanups
        cleanups = {}
        for index = #pending, 1, -1 do clean(pending[index]) end
    end

    local function fail(message)
        if failed or not scope.IsActive() then return end
        failed = true
        scope.Destroy()
        if options.OnError then options.OnError(tostring(message))
        else warn("[estyxq Hub task] " .. tostring(message)) end
    end

    function scope.Guard(callback)
        assert(type(callback) == "function", "Callback must be a function.")
        return function(...)
            if not scope.IsActive() then return nil end
            local result = table.pack(xpcall(callback, debug.traceback, ...))
            if not result[1] then fail(result[2]); return nil end
            return table.unpack(result, 2, result.n)
        end
    end

    function scope.Connect(signal, callback)
        assert(scope.IsActive(), "This scope has been destroyed.")
        local connection = signal:Connect(scope.Guard(callback))
        scope.AddCleanup(function() connection:Disconnect() end)
        return connection
    end

    local function schedule(dispatch, callback, ...)
        assert(scope.IsActive(), "This scope has been destroyed.")
        local guarded = scope.Guard(callback)
        local thread = coroutine.create(function(...)
            guarded(...)
            threads[coroutine.running()] = nil
        end)
        threads[thread] = true
        dispatch(thread, ...)
        return thread
    end

    function scope.Spawn(callback, ...)
        return schedule(task.spawn, callback, ...)
    end
    function scope.Defer(callback, ...)
        return schedule(task.defer, callback, ...)
    end
    function scope.Delay(seconds, callback, ...)
        return schedule(function(thread, ...) task.delay(seconds, thread, ...) end, callback, ...)
    end
    return scope
end

-- Only section UI additions are wrapped; the native UI stays available to advanced callers.
local function guardUI(container, scope, library)
    return setmetatable({}, {
        __index = function(_, key)
            local value = container[key]
            if type(value) ~= "function" then return value end
            return function(_, ...)
                if not scope.IsActive() then return nil end
                local args = table.pack(...)
                local options = args[1]
                if key:match("^Add") and type(options) == "table" then
                    options = table.clone(options)
                    for name, callback in pairs(options) do
                        if type(callback) == "function" then options[name] = scope.Guard(callback) end
                    end
                    args[1] = options
                end
                local result = value(container, table.unpack(args, 1, args.n))
                local flags = {}
                if type(options) == "table" and options.Flag then
                    table.insert(flags, options.Flag)
                    if options.Keybind ~= nil or options.Bind then table.insert(flags, options.Flag .. "_key") end
                end
                for _, flag in ipairs(flags) do
                    local registered = library and library.Options and library.Options[flag]
                    if registered then
                        scope.AddCleanup(function()
                            if library.Options[flag] == registered then
                                library.Options[flag] = nil
                                if library.Flags then library.Flags[flag] = nil end
                            end
                        end)
                    end
                end
                if type(result) == "table" and (result.AddSection or result.AddToggle or result.AddTab) then
                    return guardUI(result, scope, library)
                end
                return result
            end
        end,
    })
end

function Runtime.newSection(options)
    local section = { Status = "Idle", Attempts = 0 }
    local life = Runtime.newScope({ IsActive = options.IsActive, OnCleanupError = options.OnCleanupError })
    local attempt, card
    local function clearCard()
        if card then local previous = card; card = nil; previous:Destroy() end
    end
    local function render(definition)
        clearCard()
        card = options.CreateCard(definition or {})
        return card
    end

    function section.Retry()
        if not life.IsActive() or section.Status == "Loading" then return false end
        if attempt then attempt.Destroy() end
        section.Attempts += 1
        section.Status, section.Error = "Loading", nil
        render():AddParagraph({ Title = "Loading section", Content = "Getting your tools ready." })
        local current
        current = Runtime.newScope({
            IsActive = function() return life.IsActive() end,
            OnCleanupError = options.OnCleanupError,
            OnError = function(message)
                if not life.IsActive() or attempt ~= current then return end
                section.Status, section.Error = "Error", message
                if options.OnError then options.OnError(message) end
                -- Let a failing control's constructor finish before replacing its card.
                life.Defer(function()
                    if attempt ~= current or section.Status ~= "Error" then return end
                    local fallback = render()
                    fallback:AddParagraph({ Title = "Section unavailable", Content = "This section could not start or stopped after an error. You can try again." })
                    fallback:AddButton({ Title = "Retry section", Callback = life.Guard(section.Retry) })
                end)
            end,
        })
        attempt = current
        current.Spawn(function()
            local definition = options.Load(current.IsActive)
            if not current.IsActive() then return end
            assert(type(definition) == "table" and type(definition.Mount) == "function", "Section modules must return a table with Mount(context).")
            local view = guardUI(render(definition), current, options.Library)
            local context = options.Context(current, view)
            local cleanup = definition.Mount(context)
            if cleanup ~= nil then current.AddCleanup(cleanup) end
            if current.IsActive() then section.Status = "Ready" end
        end)
        return true
    end

    function section.Destroy()
        if section.Status == "Destroyed" then return end
        section.Status = "Destroyed"
        life.Destroy()
        if attempt then attempt.Destroy() end
        clearCard()
    end
    return section
end

return Runtime
