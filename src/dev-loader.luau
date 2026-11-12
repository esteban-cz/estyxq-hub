-- Copy the project to your executor's workspace/estyxq-hub folder first.
-- Change ROOT if you use another folder name. The normal GitHub entry point is src/loader.luau.
local ROOT = "estyxq-hub/src/"
assert(type(readfile) == "function", "Local development requires an executor with readfile support.")
local function readSource(filename)
    return readfile(ROOT .. filename)
end
local chunk, message = loadstring(readSource("loader.luau"), "estyxq-hub/local-loader")
assert(chunk, message)
return chunk({ ReadSource = readSource })
