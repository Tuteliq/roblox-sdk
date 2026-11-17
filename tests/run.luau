--[[
	Test runner: `lune run tests/run` from the repository root.
	Each tests/*.spec.luau returns { [testName] = function() ... end }.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local files = {}
for _, name in fs.readDir("tests") do
	if string.match(name, "%.spec%.luau$") then
		table.insert(files, name)
	end
end
table.sort(files)

local passed, failed = 0, 0
for _, file in files do
	local spec = require("./" .. string.gsub(file, "%.luau$", ""))
	local names = {}
	for name in spec do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local ok, err = pcall(spec[name])
		if ok then
			passed += 1
			print(`  ok    {file} :: {name}`)
		else
			failed += 1
			print(`  FAIL  {file} :: {name}\n        {err}`)
		end
	end
end

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
