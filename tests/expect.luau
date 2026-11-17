local Expect = {}

function Expect.equal(actual, expected, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

function Expect.truthy(value, label: string?)
	if not value then
		error(`{label or "value"}: expected a truthy value, got {tostring(value)}`, 2)
	end
end

function Expect.falsy(value, label: string?)
	if value then
		error(`{label or "value"}: expected a falsy value, got {tostring(value)}`, 2)
	end
end

return Expect
