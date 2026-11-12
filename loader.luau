-- estyxq Hub / main entry point
-- Change the repository URL here; main.luau receives the library and feature URLs.
local CONFIG = {
    ScriptBaseURL = "https://raw.githubusercontent.com/esteban-cz/estyxqHub/main/",
    MainFile = "main.luau",
    LibraryFile = "menu.luau",
    ESPFile = "esp.luau",
}

local environment = (type(getgenv) == "function" and getgenv()) or shared
local LOAD_KEY = "estyxqHub.Loader"
local run = {}
environment[LOAD_KEY] = run

local function isCurrentRun()
    return environment[LOAD_KEY] == run
end

local loaded, result = pcall(function()
    local base = CONFIG.ScriptBaseURL:match("^%s*(.-)%s*$"):gsub("/+$", "")
    assert(base ~= "", "Set ScriptBaseURL in loader.luau to your raw GitHub folder URL.")
    local mainURL = base .. "/" .. CONFIG.MainFile
    local source = game:HttpGet(mainURL)
    if not isCurrentRun() then return nil end
    local mainChunk, compileError = loadstring(source, "estyxqHub/main")
    if not mainChunk then error("Could not compile main.luau: " .. tostring(compileError), 0) end
    local hub = mainChunk({
        ScriptBaseURL = base .. "/",
        LibraryURL = base .. "/" .. CONFIG.LibraryFile,
        ESPSourceURL = base .. "/" .. CONFIG.ESPFile,
    })
    if not isCurrentRun() then return hub end
    assert(type(hub) == "table" and type(hub.Destroy) == "function",
        "main.luau did not return a hub. Upload the updated main.luau alongside this loader.")
    return hub
end)

local wasCurrent = isCurrentRun()
if wasCurrent then environment[LOAD_KEY] = nil end
if not wasCurrent then
    -- A hub that finished after a newer loader must retire only its own session.
    if loaded and type(result) == "table" and type(result.Destroy) == "function" then result.Destroy() end
    return nil
end
if not loaded then error("[estyxq Hub loader] " .. tostring(result), 0) end
return result
