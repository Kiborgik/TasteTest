--[[
  BuildRbxm — packages the framework into TasteTest.rbxm for releases.

  Usage: lune run Tools/BuildRbxm.luau   (from the repo root; fs paths are
  cwd-relative in Lune, unlike requires)

  Produces a Folder named TasteTest containing one ModuleScript per .luau
  file at the repo root, plus a Tests folder with the spec suite. The output
  is verified by deserializing it again and comparing every Source byte for
  byte, so a packaging regression fails CI instead of shipping.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

local OUTPUT = "TasteTest.rbxm"

local function moduleFromFile(path, name)
    local mod = Instance.new("ModuleScript")
    mod.Name = name
    -- Normalize CRLF so a build from a Windows working tree is byte-identical
    -- to a CI build from a fresh LF checkout (.gitattributes pins LF).
    mod.Source = fs.readFile(path):gsub("\r\n", "\n")
    return mod
end

local function addModulesFromDir(dir, parent)
    local count = 0
    for _, fileName in fs.readDir(dir) do
        if fileName:sub(-5) == ".luau" then
            local path = dir == "." and fileName or (dir .. "/" .. fileName)
            moduleFromFile(path, fileName:sub(1, -6)).Parent = parent
            count += 1
        end
    end
    return count
end

local root = Instance.new("Folder")
root.Name = "TasteTest"
local coreCount = addModulesFromDir(".", root)

local tests = Instance.new("Folder")
tests.Name = "Tests"
tests.Parent = root
local testCount = addModulesFromDir("Tests", tests)

fs.writeFile(OUTPUT, roblox.serializeModel({ root }))

-- Round-trip verification: read the file back and compare structure + bytes.
local readBack = roblox.deserializeModel(fs.readFile(OUTPUT))
assert(#readBack == 1 and readBack[1].Name == "TasteTest", "round-trip: root folder missing")
local function collectSources(instance, prefix, out)
    for _, child in instance:GetChildren() do
        if child.ClassName == "ModuleScript" then
            out[prefix .. child.Name] = child.Source
        else
            collectSources(child, prefix .. child.Name .. "/", out)
        end
    end
    return out
end
local packed = collectSources(root, "", {})
local unpacked = collectSources(readBack[1], "", {})
local verified = 0
for name, source in packed do
    assert(unpacked[name] ~= nil, "round-trip: missing module " .. name)
    assert(unpacked[name] == source, "round-trip: source mismatch in " .. name)
    verified += 1
end
for name in unpacked do
    assert(packed[name] ~= nil, "round-trip: unexpected module " .. name)
end

print(("%s: %d core + %d test modules, %d sources verified"):format(OUTPUT, coreCount, testCount, verified))
if coreCount < 5 then
    print("expected at least 5 core modules; did this run from the repo root?")
    process.exit(1)
end
