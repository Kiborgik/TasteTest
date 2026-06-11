--[[
  VerifyRelease — compares a downloaded release artifact against a local
  build, module by module and byte by byte.

  Usage: lune run Tools/VerifyRelease.luau <path-to-released.rbxm>
  Run from the repo root after Tools/BuildRbxm.luau has produced the
  local TasteTest.rbxm.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local releasedPath = process.args[1]
assert(releasedPath, "pass the path to the downloaded rbxm as the first argument")

local released = roblox.deserializeModel(fs.readFile(releasedPath))[1]
local localBuild = roblox.deserializeModel(fs.readFile("TasteTest.rbxm"))[1]

local function collect(inst, prefix, out)
    for _, child in inst:GetChildren() do
        if child.ClassName == "ModuleScript" then
            out[prefix .. child.Name] = child.Source
        else
            collect(child, prefix .. child.Name .. "/", out)
        end
    end
    return out
end

local releasedSources = collect(released, "", {})
local localSources = collect(localBuild, "", {})

local count = 0
for name, source in releasedSources do
    assert(localSources[name] == source, "mismatch: " .. name)
    count += 1
end
for name in localSources do
    assert(releasedSources[name] ~= nil, "missing in release: " .. name)
end

print(("released artifact verified: %d modules identical to the local build"):format(count))
