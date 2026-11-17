-- ModelScale.lua
-- Scales a model's parts (sizes, positions round `pivot`, special meshes,
-- attachments) by `s`. Used for still copies shown smaller: a worn Legend
-- Ride (LegendShop), the lobby's pedestals (Maps/LobbyHub).

local ModelScale = {}

function ModelScale.scale(model, s, pivot)
	pivot = pivot or model:GetPivot()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size = d.Size * s
			d.CFrame = pivot * (CFrame.new(rel.Position * s) * (rel - rel.Position))
		elseif d:IsA("SpecialMesh") then
			d.Scale = d.Scale * s
			d.Offset = d.Offset * s
		elseif d:IsA("Attachment") then
			d.Position = d.Position * s
		end
	end
	return model
end

--- Moves `model` so its bounding box stands on `floorY`, centred on `at`
-- (X, Z), turned to `rot` (a CFrame's rotation).
function ModelScale.standOn(model, at, floorY, rot)
	model:PivotTo(CFrame.new(model:GetPivot().Position) * (rot or CFrame.new()))
	local cf, size = model:GetBoundingBox()
	local move = Vector3.new(at.X - cf.Position.X, floorY - (cf.Position.Y - size.Y / 2), at.Z - cf.Position.Z)
	model:PivotTo(CFrame.new(move) * model:GetPivot())
	return model
end

return ModelScale
