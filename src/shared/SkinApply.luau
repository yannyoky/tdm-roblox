-- Надевает скин на модель персонажа (R15 или R6). Используется сервером при появлении
-- и клиентом для предпросмотра в меню скинов.
-- Детали снаряжения не ловят пули (CanQuery = false), поэтому хитбоксы не меняются.
local Skins = require(script.Parent.Config.Skins)

local SkinApply = {}

-- Типы аксессуаров-одежды, которые снимаются под форму. Берём по имени через pcall,
-- чтобы скрипт не падал, если какого-то типа нет в текущей версии Roblox.
local CLOTHING_TYPES = {}
for _, name in { "TShirt", "Shirt", "Pants", "Jacket", "Sweater", "Shorts", "LeftShoe", "RightShoe", "DressSkirt", "Back", "Waist", "Shoulder", "Front" } do
	local ok, item = pcall(function()
		return (Enum.AccessoryType :: any)[name]
	end)
	if ok and item then
		CLOTHING_TYPES[item] = true
	end
end
local HEAD_GEAR = { Helmet = true, Cap = true, Beanie = true, Balaclava = true }

local SHIRT_PARTS = { "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "Torso", "Left Arm", "Right Arm" }
local PANTS_PARTS = { "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg", "Left Leg", "Right Leg" }
local SHOE_PARTS = { "LeftFoot", "RightFoot" }

local function gearPart(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = "Gear_" .. name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function attach(model: Model, part: BasePart, body: BasePart, offset: CFrame)
	part.CFrame = body.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
end

local function sphereMesh(part: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
end

local function cylinder(part: Part)
	part.Shape = Enum.PartType.Cylinder
end

-- Одна деталь снаряжения.
local function buildGear(model: Model, kind: string, color: Color3, skinColor: Color3)
	local head = model:FindFirstChild("Head") :: BasePart?
	local torso = (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")) :: BasePart?
	if not head or not torso then
		return
	end
	-- У R6 голова 2×1×1 с мешем, реальный размер головы ближе к 1.2.
	local h = if model:FindFirstChild("UpperTorso") then head.Size else Vector3.new(1.2, 1.2, 1.2)
	local t = torso.Size

	if kind == "Helmet" then
		local p = gearPart(kind, Vector3.new(h.X * 1.25, h.Y * 0.85, h.Z * 1.3), color, Enum.Material.SmoothPlastic)
		sphereMesh(p)
		attach(model, p, head, CFrame.new(0, h.Y * 0.28, 0.02))
	elseif kind == "Beanie" then
		local p = gearPart(kind, Vector3.new(h.X * 1.12, h.Y * 0.75, h.Z * 1.15), color)
		sphereMesh(p)
		attach(model, p, head, CFrame.new(0, h.Y * 0.3, 0))
	elseif kind == "Cap" then
		local top = gearPart(kind, Vector3.new(h.Y * 0.35, h.X * 1.1, h.X * 1.1), color)
		cylinder(top)
		attach(model, top, head, CFrame.new(0, h.Y * 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local brim = gearPart(kind .. "Brim", Vector3.new(h.X * 0.9, 0.08, h.Z * 0.5), color)
		attach(model, brim, head, CFrame.new(0, h.Y * 0.32, -h.Z * 0.7))
	elseif kind == "Bandana" then
		local p = gearPart(kind, Vector3.new(h.X * 1.06, h.Y * 0.42, h.Z * 1.06), color)
		attach(model, p, head, CFrame.new(0, -h.Y * 0.22, 0))
	elseif kind == "Balaclava" then
		local p = gearPart(kind, h * 1.07, color)
		attach(model, p, head, CFrame.new())
		local eyes = gearPart(kind .. "Eyes", Vector3.new(h.X * 0.75, h.Y * 0.16, 0.04), skinColor, Enum.Material.SmoothPlastic)
		attach(model, eyes, head, CFrame.new(0, h.Y * 0.1, -h.Z * 0.54))
	elseif kind == "Visor" then
		local p = gearPart(kind, Vector3.new(h.X * 0.9, h.Y * 0.16, 0.06), color, Enum.Material.Glass)
		p.Reflectance = 0.3
		attach(model, p, head, CFrame.new(0, h.Y * 0.1, -h.Z * 0.53))
	elseif kind == "Vest" then
		local p = gearPart(kind, Vector3.new(t.X * 1.1, t.Y * 0.85, t.Z * 1.35), color)
		attach(model, p, torso, CFrame.new(0, t.Y * 0.05, 0))
	elseif kind == "Chain" then
		local p = gearPart(kind, Vector3.new(t.X * 0.45, 0.08, 0.05), color, Enum.Material.Metal)
		attach(model, p, torso, CFrame.new(0, t.Y * 0.3, -t.Z * 0.5 - 0.03))
		local pendant = gearPart(kind .. "Pendant", Vector3.new(0.18, 0.22, 0.05), color, Enum.Material.Metal)
		attach(model, pendant, torso, CFrame.new(0, t.Y * 0.18, -t.Z * 0.5 - 0.03))
	elseif kind == "Backpack" then
		local p = gearPart(kind, Vector3.new(t.X * 0.7, t.Y * 0.85, 0.6), color)
		attach(model, p, torso, CFrame.new(0, 0, t.Z * 0.5 + 0.3))
	end
end

-- Снять прошлый скин и надеть новый. skinId может быть nil: тогда только снимается старый.
function SkinApply.apply(model: Model, skinId: string?)
	for _, inst in model:GetChildren() do
		if inst:IsA("BasePart") and string.sub(inst.Name, 1, 5) == "Gear_" then
			inst:Destroy()
		end
	end
	local def = skinId and Skins.List[skinId]
	if not def then
		return
	end

	local hasHeadGear = false
	for _, g in def.Gear do
		if HEAD_GEAR[g.Kind] then
			hasHeadGear = true
		end
	end

	for _, inst in model:GetChildren() do
		if inst:IsA("Shirt") or inst:IsA("Pants") or inst:IsA("ShirtGraphic") or inst:IsA("BodyColors") then
			inst:Destroy()
		elseif inst:IsA("Accessory") then
			local layered = inst:FindFirstChildWhichIsA("WrapLayer", true) ~= nil
			local kind = inst.AccessoryType
			if layered or CLOTHING_TYPES[kind] or (hasHeadGear and (kind == Enum.AccessoryType.Hat or kind == Enum.AccessoryType.Face)) then
				inst:Destroy()
			end
		end
	end

	local head = model:FindFirstChild("Head") :: BasePart?
	local skinColor = if head then head.Color else Color3.fromRGB(234, 184, 146)
	local function paint(names: { string }, color: Color3)
		for _, name in names do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.Color = color
				part.Material = Enum.Material.Fabric
			end
		end
	end
	paint(SHIRT_PARTS, def.Shirt)
	paint(PANTS_PARTS, def.Pants)
	paint(SHOE_PARTS, def.Shoes or def.Pants)

	for _, g in def.Gear do
		buildGear(model, g.Kind, g.Color, skinColor)
	end
	model:SetAttribute("Skin", def.Id)
end

return SkinApply
