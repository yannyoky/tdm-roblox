-- Внешний вид оружия в руках. Два источника:
--   1. Своя модель: положите Model в ServerStorage/WeaponModels/<Id оружия> (например, Rifle).
--      В модели должна быть деталь Handle — за неё персонаж держит оружие. Ствол смотрит в −Z
--      (передняя сторона детали). Если внутри Handle есть Attachment "Grip", рука встанет в него,
--      Attachment "Muzzle" у дула — оттуда пойдут трассер и вспышка.
--      Так подключаются модели из Creator Store или сделанные в Blender.
--   2. Иначе модель собирается из деталей по рецепту ниже: ствол, магазин, рукоять, приклад, прицел.
-- Детали оружия не сталкиваются и не ловят пули.
local ServerStorage = game:GetService("ServerStorage")

local WeaponModels = {}

local METAL = Color3.fromRGB(42, 42, 46)
local DARK = Color3.fromRGB(24, 24, 27)
local STEEL = Color3.fromRGB(150, 150, 158)
local WOOD = Color3.fromRGB(112, 70, 40)
local POLY = Color3.fromRGB(58, 62, 52)
local OLIVE = Color3.fromRGB(70, 80, 55)
local TAPE = Color3.fromRGB(30, 30, 30)
local GLASS = Color3.fromRGB(90, 140, 190)

local M = Enum.Material

-- Деталь рецепта: size, pos (центр относительно Handle), color, material, rot (градусы X, Y, Z), shape.
type Piece = { size: Vector3, pos: Vector3?, color: Color3, mat: Enum.Material?, rot: Vector3?, shape: string? }
type Recipe = { grip: Vector3?, muzzle: Vector3?, parts: { Piece } }

local function v(x, y, z)
	return Vector3.new(x, y, z)
end

-- Цилиндр вдоль оси Z (ствол, бита): у Roblox ось цилиндра — X, поворачиваем на 90° по Y.
local function tube(length: number, d: number, pos: Vector3, color: Color3, mat: Enum.Material?): Piece
	return { size = v(length, d, d), pos = pos, color = color, mat = mat, rot = v(0, 90, 0), shape = "Cylinder" }
end

-- Первая деталь каждого рецепта — Handle.
local RECIPES: { [string]: Recipe } = {
	Rifle = {
		muzzle = v(0, 0.08, -1.62),
		grip = v(0, -0.28, 0.32),
		parts = {
			{ size = v(0.3, 0.45, 1.2), color = METAL, mat = M.Metal },
			tube(0.95, 0.11, v(0, 0.08, -1.15), DARK, M.Metal),
			{ size = v(0.28, 0.3, 0.6), pos = v(0, 0, -0.85), color = WOOD, mat = M.Wood },
			{ size = v(0.18, 0.6, 0.26), pos = v(0, -0.47, -0.22), color = DARK, mat = M.Metal, rot = v(18, 0, 0) },
			{ size = v(0.17, 0.45, 0.22), pos = v(0, -0.38, 0.32), color = WOOD, mat = M.Wood, rot = v(-15, 0, 0) },
			{ size = v(0.22, 0.38, 0.9), pos = v(0, -0.08, 1.05), color = WOOD, mat = M.Wood },
			{ size = v(0.05, 0.16, 0.05), pos = v(0, 0.2, -1.5), color = DARK },
			{ size = v(0.12, 0.08, 0.15), pos = v(0, 0.26, -0.1), color = DARK },
		},
	},
	SMG = {
		muzzle = v(0, 0.06, -0.83),
		grip = v(0, -0.26, 0.3),
		parts = {
			{ size = v(0.28, 0.4, 0.9), color = DARK, mat = M.Metal },
			tube(0.4, 0.1, v(0, 0.06, -0.63), METAL, M.Metal),
			{ size = v(0.15, 0.65, 0.22), pos = v(0, -0.5, -0.12), color = METAL, mat = M.Metal },
			{ size = v(0.16, 0.42, 0.2), pos = v(0, -0.36, 0.3), color = DARK, rot = v(-15, 0, 0) },
			{ size = v(0.06, 0.06, 0.6), pos = v(0, 0.1, 0.75), color = METAL, mat = M.Metal },
			{ size = v(0.06, 0.3, 0.06), pos = v(0, -0.03, 1.05), color = METAL, mat = M.Metal },
			{ size = v(0.1, 0.1, 0.25), pos = v(0, 0.25, 0), color = DARK },
		},
	},
	Shotgun = {
		muzzle = v(0, 0.08, -1.7),
		grip = v(0, -0.22, 0.38),
		parts = {
			{ size = v(0.3, 0.4, 0.8), color = METAL, mat = M.Metal },
			tube(1.3, 0.13, v(0, 0.08, -1.05), DARK, M.Metal),
			tube(1.0, 0.12, v(0, -0.08, -0.9), DARK, M.Metal),
			{ size = v(0.24, 0.24, 0.45), pos = v(0, -0.08, -0.85), color = WOOD, mat = M.Wood },
			{ size = v(0.17, 0.42, 0.22), pos = v(0, -0.32, 0.38), color = WOOD, mat = M.Wood, rot = v(-15, 0, 0) },
			{ size = v(0.24, 0.42, 1.0), pos = v(0, -0.12, 0.9), color = WOOD, mat = M.Wood, rot = v(-6, 0, 0) },
		},
	},
	LMG = {
		muzzle = v(0, 0.1, -1.93),
		grip = v(0, -0.33, 0.42),
		parts = {
			{ size = v(0.4, 0.55, 1.4), color = POLY, mat = M.Metal },
			tube(1.25, 0.15, v(0, 0.1, -1.3), DARK, M.Metal),
			{ size = v(0.05, 0.55, 0.05), pos = v(0.12, -0.22, -1.6), color = DARK, rot = v(0, 0, 12) },
			{ size = v(0.05, 0.55, 0.05), pos = v(-0.12, -0.22, -1.6), color = DARK, rot = v(0, 0, -12) },
			{ size = v(0.36, 0.45, 0.5), pos = v(0, -0.48, -0.1), color = OLIVE },
			{ size = v(0.17, 0.45, 0.22), pos = v(0, -0.45, 0.42), color = DARK, rot = v(-15, 0, 0) },
			{ size = v(0.26, 0.45, 0.8), pos = v(0, -0.05, 1.1), color = POLY },
			{ size = v(0.06, 0.1, 0.4), pos = v(0, 0.36, -0.3), color = DARK },
		},
	},
	Sniper = {
		muzzle = v(0, 0.05, -2.13),
		grip = v(0, -0.22, 0.45),
		parts = {
			{ size = v(0.28, 0.4, 1.2), color = OLIVE, mat = M.Metal },
			tube(1.55, 0.1, v(0, 0.05, -1.35), DARK, M.Metal),
			tube(0.9, 0.2, v(0, 0.4, -0.1), DARK, M.Metal),
			{ size = v(0.22, 0.22, 0.04), pos = v(0, 0.4, -0.57), color = GLASS, mat = M.Glass },
			{ size = v(0.08, 0.18, 0.1), pos = v(0, 0.25, -0.35), color = DARK },
			{ size = v(0.08, 0.18, 0.1), pos = v(0, 0.25, 0.15), color = DARK },
			{ size = v(0.16, 0.3, 0.25), pos = v(0, -0.32, 0), color = DARK },
			{ size = v(0.17, 0.42, 0.22), pos = v(0, -0.32, 0.45), color = OLIVE, rot = v(-15, 0, 0) },
			{ size = v(0.24, 0.45, 1.0), pos = v(0, -0.1, 1.1), color = OLIVE },
			{ size = v(0.05, 0.05, 0.22), pos = v(0.18, 0.1, 0.25), color = STEEL, mat = M.Metal },
		},
	},
	Pistol = {
		muzzle = v(0, 0.05, -0.45),
		grip = v(0, -0.3, 0.22),
		parts = {
			{ size = v(0.22, 0.28, 0.9), color = DARK, mat = M.Metal },
			{ size = v(0.2, 0.55, 0.28), pos = v(0, -0.36, 0.22), color = TAPE, rot = v(-12, 0, 0) },
			{ size = v(0.04, 0.12, 0.2), pos = v(0, -0.2, -0.05), color = DARK },
		},
	},
	Revolver = {
		muzzle = v(0, 0.08, -1.02),
		grip = v(0, -0.32, 0.3),
		parts = {
			{ size = v(0.22, 0.32, 0.5), color = STEEL, mat = M.Metal },
			tube(0.36, 0.32, v(0, -0.02, -0.05), STEEL, M.Metal),
			tube(0.8, 0.12, v(0, 0.08, -0.62), STEEL, M.Metal),
			{ size = v(0.2, 0.5, 0.25), pos = v(0, -0.36, 0.32), color = WOOD, mat = M.Wood, rot = v(-20, 0, 0) },
		},
	},
	Knife = {
		parts = {
			{ size = v(0.16, 0.2, 0.5), color = TAPE },
			{ size = v(0.04, 0.22, 0.85), pos = v(0, 0.02, -0.68), color = STEEL, mat = M.Metal },
			{ size = v(0.26, 0.28, 0.06), pos = v(0, 0, -0.26), color = DARK, mat = M.Metal },
		},
	},
	Bat = {
		parts = {
			{ size = v(0.18, 0.18, 0.6), color = TAPE },
			tube(2.2, 0.3, v(0, 0, -1.4), WOOD, M.Wood),
			tube(0.06, 0.24, v(0, 0, 0.32), WOOD, M.Wood),
		},
	},
	Frag = {
		parts = {
			{ size = v(0.5, 0.6, 0.5), color = OLIVE, shape = "Ball" },
			{ size = v(0.18, 0.14, 0.18), pos = v(0, 0.33, 0), color = STEEL, mat = M.Metal },
			{ size = v(0.05, 0.4, 0.1), pos = v(0.22, 0.15, 0), color = STEEL, mat = M.Metal, rot = v(0, 0, -10) },
			{ size = v(0.03, 0.14, 0.14), pos = v(-0.12, 0.38, 0), color = STEEL, mat = M.Metal },
		},
	},
	Smoke = {
		parts = {
			{ size = v(0.9, 0.45, 0.45), color = Color3.fromRGB(150, 150, 150), mat = M.Metal, rot = v(0, 0, 90), shape = "Cylinder" },
			{ size = v(0.12, 0.3, 0.3), pos = v(0, 0.5, 0), color = DARK, rot = v(0, 0, 90), shape = "Cylinder" },
			{ size = v(0.05, 0.45, 0.1), pos = v(0.25, 0.2, 0), color = STEEL, mat = M.Metal },
		},
	},
	Flash = {
		parts = {
			{ size = v(0.85, 0.42, 0.42), color = Color3.fromRGB(70, 90, 140), mat = M.Metal, rot = v(0, 0, 90), shape = "Cylinder" },
			{ size = v(0.12, 0.3, 0.3), pos = v(0, 0.48, 0), color = DARK, rot = v(0, 0, 90), shape = "Cylinder" },
			{ size = v(0.05, 0.42, 0.1), pos = v(0.24, 0.2, 0), color = STEEL, mat = M.Metal },
		},
	},
}

local function rad(r: Vector3?): CFrame
	if not r then
		return CFrame.new()
	end
	return CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

local function prepare(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
end

local function buildPiece(piece: Piece, name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = piece.size
	p.Color = piece.color
	p.Material = piece.mat or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if piece.shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif piece.shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	end
	prepare(p)
	return p
end

local function weldTo(handle: BasePart, part: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
end

-- Своя модель из ServerStorage/WeaponModels. Возвращает true, если нашлась и подключена.
local function fromStorage(tool: Tool, id: string): boolean
	local folder = ServerStorage:FindFirstChild("WeaponModels")
	local source = folder and folder:FindFirstChild(id)
	if not source then
		return false
	end
	local model = source:Clone()
	local handle = model:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		warn("[WeaponModels] В модели ServerStorage.WeaponModels." .. id .. " нет детали Handle, беру встроенную")
		model:Destroy()
		return false
	end
	-- Скрипты из чужих моделей не запускаем.
	for _, inst in model:GetDescendants() do
		if inst:IsA("LuaSourceContainer") then
			inst:Destroy()
		end
	end
	handle.Name = "Handle"
	handle.Parent = tool
	prepare(handle)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			prepare(inst)
			inst.Parent = tool
			weldTo(handle, inst)
		end
	end
	model:Destroy()
	local grip = handle:FindFirstChild("Grip")
	if grip and grip:IsA("Attachment") then
		tool.Grip = grip.CFrame
	end
	return true
end

-- Собрать модель оружия внутри tool. def — запись из Config/Weapons.
function WeaponModels.build(tool: Tool, id: string, def)
	if fromStorage(tool, id) then
		return
	end
	local recipe = RECIPES[id]
	if not recipe then
		-- Нет рецепта: простой брусок, как раньше.
		local handle = buildPiece({ size = def.HandleSize or v(0.4, 0.8, 2), color = def.Color or DARK }, "Handle")
		handle.Parent = tool
		return
	end
	local handle = buildPiece(recipe.parts[1], "Handle")
	local base = rad(recipe.parts[1].rot)
	handle.CFrame = base
	handle.Parent = tool
	for i = 2, #recipe.parts do
		local piece = recipe.parts[i]
		local part = buildPiece(piece, "Part" .. i)
		part.CFrame = CFrame.new(piece.pos or Vector3.zero) * rad(piece.rot)
		part.Parent = tool
		weldTo(handle, part)
	end
	-- Точка у дула: отсюда рисуются трассер и вспышка выстрела.
	if recipe.muzzle then
		local muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.Position = recipe.muzzle
		muzzle.Parent = handle
	end
	-- Рука на пистолетной рукоятке. У Handle с поворотом (гранаты) учитываем его.
	if recipe.grip then
		tool.Grip = CFrame.new(recipe.grip)
	elseif recipe.parts[1].rot then
		tool.Grip = base:Inverse()
	end
end

return WeaponModels
