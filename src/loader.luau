local launchOptions = ... or {}
assert(type(launchOptions) == "table", "Loader options must be a table.")
assert(launchOptions.ReadSource == nil or type(launchOptions.ReadSource) == "function", "ReadSource must be a function.")
local CONFIG = {
    ScriptBaseURL = "https://raw.githubusercontent.com/esteban-cz/estyxq-hub/main/src/",
    MainFile = "main.luau",
    LibraryFile = "menu.luau",
    CatalogFile = "catalog.luau" -- Generated locally with npm run build.
}

local environment = (type(getgenv) == "function" and getgenv()) or shared
local LOAD_KEY = "estyxq-hub.Loader"
local run = {}
environment[LOAD_KEY] = run
local function isCurrentRun()
    return environment[LOAD_KEY] == run
end

local function encodePath(filename)
    return (filename:gsub("[^%w%-%._~/]", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local loaded, result = pcall(function()
    local base = CONFIG.ScriptBaseURL:match("^%s*(.-)%s*$"):gsub("/+$", "")
    assert(base ~= "", "Set ScriptBaseURL in loader.luau to your raw GitHub folder URL.")
    local function url(filename)
        return base .. "/" .. encodePath(filename)
    end
    local function compileFile(filename)
        local source
        if launchOptions.ReadSource then
            source = launchOptions.ReadSource(filename, url(filename))
        else
            source = game:HttpGet(url(filename))
        end
        if not isCurrentRun() then
            return nil
        end
        local chunk, message = loadstring(source, "estyxq-hub/" .. filename)
        if not chunk then
            error("Could not compile " .. filename .. ": " .. tostring(message), 0)
        end
        return chunk
    end

    local selected
    local catalog = {
        SharedTabs = {},
        Games = {}
    }
    if CONFIG.CatalogFile ~= "" then
        local catalogChunk = compileFile(CONFIG.CatalogFile)
        if not isCurrentRun() then
            return nil
        end
        catalog = catalogChunk()
        assert(type(catalog) == "table" and catalog.SchemaVersion == 1 and type(catalog.Games) == "table" and
                   type(catalog.SharedTabs) == "table", "Invalid catalog.luau. Rebuild it with npm run build.")
        -- A place-specific entry wins over an experience-wide entry.
        for _, field in ipairs({"PlaceIds", "GameIds"}) do
            local id = tonumber(field == "PlaceIds" and game.PlaceId or game.GameId) or 0
            if id > 0 then
                for _, entry in ipairs(catalog.Games) do
                    assert(type(entry) == "table", "Invalid game catalog entry.")
                    if table.find(entry[field] or {}, id) then
                        selected = entry;
                        break
                    end
                end
            end
            if selected then
                break
            end
        end
    end
    if not isCurrentRun() then
        return nil
    end

    -- Section files are loaded by their own boundaries after the shared hub is ready.
    local mainChunk = compileFile(CONFIG.MainFile)
    if not isCurrentRun() then
        return nil
    end
    local hub = mainChunk({
        ScriptBaseURL = base .. "/",
        LibraryURL = url(CONFIG.LibraryFile),
        SharedTabs = catalog.SharedTabs,
        GameModule = selected,
        IsCurrentLoad = isCurrentRun,
        ReadSource = launchOptions.ReadSource
    })
    if not isCurrentRun() then
        return hub
    end
    assert(type(hub) == "table" and type(hub.Destroy) == "function" and type(hub.Config) == "table",
        "main.luau did not return a hub. Upload the updated main.luau alongside this loader.")
    return hub
end)

local wasCurrent = isCurrentRun()
if wasCurrent then
    environment[LOAD_KEY] = nil
end
if not wasCurrent then
    if loaded and type(result) == "table" and type(result.Destroy) == "function" then
        result.Destroy()
    end
    return nil
end
if not loaded then
    error("[estyxq Hub loader] " .. tostring(result), 0)
end
print(string.format("[estyxq Hub loader] Loaded %s v%s successfully.", result.Config.ScriptName,
    result.Config.ScriptVersion))
return result
