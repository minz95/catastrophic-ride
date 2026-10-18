--!nocheck
-- dump.luau — canonical text dump of a built instance tree, for diffs.
local Mock = require("./mock")

local Dump = {}

local function r(n)
	return string.format("%.3f", n + 0)
end

local function v3(v)
	return r(v.X) .. "," .. r(v.Y) .. "," .. r(v.Z)
end

function Dump.tree(root)
	local lines = {}
	for _, d in ipairs(root:GetDescendants()) do
		local p = Mock.props(d)
		local line = { d.ClassName, d:GetFullName() }
		if d:IsA("BasePart") then
			local cf = p.CFrame
			local comps = { cf:GetComponents() }
			local rot = {}
			for i = 4, 12 do
				table.insert(rot, r(comps[i]))
			end
			table.insert(line, "size=" .. v3(p.Size))
			table.insert(line, "pos=" .. v3(cf.Position))
			table.insert(line, "rot=" .. table.concat(rot, ","))
			table.insert(line, "cc=" .. tostring(p.CanCollide))
			table.insert(line, "t=" .. r(p.Transparency))
			table.insert(line, "mat=" .. tostring(p.Material))
			table.insert(line, "col=" .. tostring(p.Color))
			if p.CustomPhysicalProperties then
				table.insert(line, "phys=" .. tostring(p.CustomPhysicalProperties))
			end
		end
		local tags = d:GetTags()
		if #tags > 0 then
			table.insert(line, "tags=" .. table.concat(tags, "|"))
		end
		for k, v in pairs(d:GetAttributes()) do
			table.insert(line, "@" .. k .. "=" .. tostring(v))
		end
		table.insert(lines, table.concat(line, " "))
	end
	return lines
end

return Dump
