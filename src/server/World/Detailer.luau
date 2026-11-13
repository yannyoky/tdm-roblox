-- Отделка карты, чтобы она не выглядела набором кубов (ветка графики).
--
-- 1. Процедурная детализация: рамы и стёкла окон, подоконники, межэтажные пояса, цоколь, карнизы,
--    водостоки, кондиционеры, двери, вентиляция на крышах, рёбра и замки контейнеров, столбы заборов,
--    тротуары с бордюрами, разметка дорог.
--    Почти все детали без столкновений и без попаданий пуль (CanCollide/CanQuery = false),
--    поэтому геймплей (укрытия, паркур, прострел) остаётся как в обычной ветке.
-- 2. Слоты для готовых моделей: положите модель в ServerStorage/RealisticModels (см. docs/GRAPHICS.md),
--    и она заменит процедурную коробку. Исходная деталь становится невидимой, но остаётся
--    для столкновений и попаданий.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Graphics)

local Detailer = {}

local MODELS_FOLDER = "RealisticModels"

local SIDES = { "N", "S", "E", "W" }

local FRAME = Color3.fromRGB(205, 203, 196)
local GLASS = Color3.fromRGB(52, 62, 72)
local GLASS_LIT = Color3.fromRGB(255, 196, 120)
local TRIM = Color3.fromRGB(120, 118, 112)
local DARK_METAL = Color3.fromRGB(55, 57, 60)

local function yaw(rot: number?): CFrame
	return CFrame.Angles(0, math.rad(rot or 0), 0)
end

-- Деталь отделки: без столкновений, без попаданий, мелочь не отбрасывает тень.
local function trim(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if size.X < 1 or size.Y < 1 or size.Z < 1 then
		p.CastShadow = size.X * size.Y * size.Z > 3
	end
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Вертикальная труба (Cylinder лежит по оси X, поворачиваем).
local function pipe(parent: Instance, cf: CFrame, height: number, radius: number, color: Color3)
	return trim(parent, "Pipe", Vector3.new(height, radius * 2, radius * 2), cf * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
end

-- Фасад со стороны side: локальная система, где X идёт вдоль стены, -Z смотрит наружу, z = 0 — поверхность.
local function faceFrame(base: CFrame, side: string, w: number, d: number, inset: number): (CFrame, number)
	if side == "N" then
		return base * CFrame.new(0, 0, -d / 2 + inset), w
	elseif side == "S" then
		return base * CFrame.new(0, 0, d / 2 - inset) * yaw(180), w
	elseif side == "E" then
		return base * CFrame.new(w / 2 - inset, 0, 0) * yaw(-90), d
	else
		return base * CFrame.new(-w / 2 + inset, 0, 0) * yaw(90), d
	end
end

local function rngFor(e): Random
	return Random.new(math.floor((e.x or 0) * 73 + (e.z or 0) * 131 + (e.h or 0) * 7) % 2 ^ 30)
end

local function lampsOn(mapId: string): boolean
	local mood = Config.Moods[mapId] or Config.Moods.Default
	return mood.LampsOn == true
end

------------------------------------------------------------------------
-- Готовые модели

local function modelsFolder(): Instance?
	return ServerStorage:FindFirstChild(MODELS_FOLDER)
end

-- Случайная модель из слота: либо модель с таким именем, либо папка с несколькими моделями.
local function pickModel(slot: string, rng: Random): Model?
	local folder = modelsFolder()
	local item = folder and folder:FindFirstChild(slot)
	if not item then
		return nil
	end
	if item:IsA("Model") then
		return item
	end
	local list = {}
	for _, child in item:GetChildren() do
		if child:IsA("Model") then
			table.insert(list, child)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

-- Ставит копию модели низом в точку cf. Скрипты из бесплатных моделей удаляются.
-- target: Y — нужная высота; если X и Z больше нуля, модель ещё и вписывается в эту коробку.
-- solid = true оставляет модели столкновения и попадания (бочки, баки как укрытие).
local function placeModel(template: Model, cf: CFrame, parent: Instance, target: Vector3?, solid: boolean?): Model
	local m = template:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	if target then
		local size = m:GetExtentsSize()
		local k = target.Y / math.max(size.Y, 0.01)
		if target.X > 0 and target.Z > 0 then
			-- Вписываем в коробку, не вылезая за её стороны.
			k = math.min(k, target.X / math.max(size.X, 0.01), target.Z / math.max(size.Z, 0.01))
		end
		pcall(function()
			m:ScaleTo(m:GetScale() * k)
		end)
	end
	local bbCf, bbSize = m:GetBoundingBox()
	local pivotFromBox = bbCf:ToObjectSpace(m:GetPivot())
	m:PivotTo(cf * CFrame.new(0, bbSize.Y / 2, 0) * pivotFromBox)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			if not solid then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		elseif d:IsA("Light") then
			d:SetAttribute("LampOn", d.Enabled)
			game:GetService("CollectionService"):AddTag(d, "RealismLight")
		end
	end
	m.Parent = parent
	return m
end

-- Заменяет деталь моделью: деталь остаётся невидимой для столкновений и попаданий.
local function replaceWithModel(part: BasePart, slot: string, rng: Random, parent: Instance): boolean
	local template = pickModel(slot, rng)
	if not template then
		return false
	end
	local bottom = part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0)
	-- Модели обычно смотрят вдоль своей оси Z; коробки контейнеров длинные по Z, так что совпадает.
	placeModel(template, bottom, parent, part.Size)
	part.Transparency = 1
	part:SetAttribute("ReplacedBy", slot)
	return true
end

Detailer.pickModel = pickModel
Detailer.placeModel = placeModel

------------------------------------------------------------------------
-- Окна

local function window(parent: Instance, face: CFrame, u: number, y0: number, ww: number, wh: number, lit: boolean)
	local c = face * CFrame.new(u, y0 + wh / 2, 0)
	trim(parent, "WindowFrame", Vector3.new(ww + 0.5, wh + 0.5, 0.16), c * CFrame.new(0, 0, -0.08), FRAME, Enum.Material.SmoothPlastic)
	trim(parent, "WindowGlass", Vector3.new(ww, wh, 0.1), c * CFrame.new(0, 0, -0.14), if lit then GLASS_LIT else GLASS, if lit then Enum.Material.Neon else Enum.Material.Glass, {
		Reflectance = if lit then 0 else 0.12,
	})
	trim(parent, "WindowMullion", Vector3.new(0.16, wh, 0.08), c * CFrame.new(0, 0, -0.22), FRAME, Enum.Material.SmoothPlastic)
	trim(parent, "WindowSill", Vector3.new(ww + 0.9, 0.25, 0.55), face * CFrame.new(u, y0 - 0.2, -0.27), TRIM, Enum.Material.Concrete)
end

-- Рамка вокруг настоящего проёма (окно, через которое стреляют, или дверь).
local function openingFrame(parent: Instance, face: CFrame, u: number, w: number, bottom: number, top: number, isDoor: boolean)
	local h = top - bottom
	local t = 0.3
	trim(parent, "OpeningFrame", Vector3.new(w + 2 * t, t, 0.2), face * CFrame.new(u, top + t / 2, -0.1), FRAME, Enum.Material.SmoothPlastic)
	trim(parent, "OpeningFrame", Vector3.new(t, h, 0.2), face * CFrame.new(u - w / 2 - t / 2, bottom + h / 2, -0.1), FRAME, Enum.Material.SmoothPlastic)
	trim(parent, "OpeningFrame", Vector3.new(t, h, 0.2), face * CFrame.new(u + w / 2 + t / 2, bottom + h / 2, -0.1), FRAME, Enum.Material.SmoothPlastic)
	if not isDoor then
		trim(parent, "WindowSill", Vector3.new(w + 0.9, 0.25, 0.55), face * CFrame.new(u, bottom - 0.12, -0.27), TRIM, Enum.Material.Concrete)
	end
end

------------------------------------------------------------------------
-- Общие элементы фасада

local function facadeBands(parent: Instance, face: CFrame, len: number, h: number, floorH: number, color: Color3)
	local darker = color:Lerp(Color3.new(0, 0, 0), 0.35)
	local lighter = color:Lerp(Color3.new(1, 1, 1), 0.2)
	-- Цоколь.
	trim(parent, "Plinth", Vector3.new(len + 0.3, 1.4, 0.3), face * CFrame.new(0, 0.7, -0.15), darker, Enum.Material.Concrete)
	-- Межэтажные пояса.
	local y = floorH
	while y < h - 2 do
		trim(parent, "FloorBand", Vector3.new(len + 0.2, 0.4, 0.22), face * CFrame.new(0, y, -0.11), lighter, Enum.Material.Concrete)
		y += floorH
	end
	-- Карниз.
	trim(parent, "Cornice", Vector3.new(len + 0.9, 0.7, 0.6), face * CFrame.new(0, h - 0.35, -0.3), lighter, Enum.Material.Concrete)
end

local function acUnit(parent: Instance, cf: CFrame)
	local body = trim(parent, "AirConditioner", Vector3.new(2, 1.4, 1), cf, Color3.fromRGB(225, 225, 220), Enum.Material.SmoothPlastic)
	trim(parent, "AirConditionerGrill", Vector3.new(1.2, 1.1, 0.05), cf * CFrame.new(0.3, 0, -0.52), Color3.fromRGB(90, 90, 92), Enum.Material.DiamondPlate)
	return body
end

-- Мелочь на крыше: вентиляция, кондиционеры. Эти детали твёрдые (на крыше бегают и прячутся).
local function roofProps(parent: Instance, base: CFrame, w: number, d: number, roofY: number, rng: Random, avoid: Vector3?)
	if w < 10 or d < 10 then
		return
	end
	for _ = 1, rng:NextInteger(1, 3) do
		local x = rng:NextNumber(-w / 2 + 4, w / 2 - 4)
		local z = rng:NextNumber(-d / 2 + 4, d / 2 - 4)
		if not avoid or (Vector3.new(x, 0, z) - avoid).Magnitude > 7 then
			local kind = rng:NextInteger(1, 3)
			local cf = base * CFrame.new(x, roofY, z) * yaw(rng:NextInteger(0, 3) * 90)
			if kind == 1 then
				local p = trim(parent, "RoofVent", Vector3.new(2.2, 1.6, 2.2), cf * CFrame.new(0, 0.8, 0), Color3.fromRGB(150, 152, 155), Enum.Material.Metal)
				p.CanCollide, p.CanQuery = true, true
				pipe(parent, cf * CFrame.new(0, 2.1, 0), 1, 0.45, Color3.fromRGB(140, 142, 145))
			elseif kind == 2 then
				local p = trim(parent, "RoofAC", Vector3.new(3.5, 2, 2.5), cf * CFrame.new(0, 1, 0), Color3.fromRGB(200, 200, 196), Enum.Material.Metal)
				p.CanCollide, p.CanQuery = true, true
				trim(parent, "RoofACFan", Vector3.new(1.8, 0.1, 1.8), cf * CFrame.new(0, 2.05, 0), Color3.fromRGB(60, 60, 62), Enum.Material.DiamondPlate)
			else
				pipe(parent, cf * CFrame.new(0, 1.5, 0), 3, 0.3, Color3.fromRGB(120, 122, 125))
			end
		end
	end
end

------------------------------------------------------------------------
-- Элементы

local decorators = {}

function decorators.block(parent: Instance, e, mapId: string, created: { Instance })
	local rng = rngFor(e)
	local building = created[1]
	if not building or not building:IsA("BasePart") then
		return
	end
	local w, d, h = e.w, e.d, e.h
	local base = CFrame.new(e.x, 0, e.z) * yaw(e.rot)
	local color = building.Color
	local small = h < 8 or w < 9 or d < 9 -- сарай, будка
	local lit = lampsOn(mapId)
	local accessSide = e.access and e.access[1]
	local accessKind = e.access and e.access[2]
	local floorH = if h >= 13 then 9 else h

	-- Дверь на стороне без лестницы.
	local doorSide: string? = nil
	for _, s in SIDES do
		if s ~= accessSide then
			doorSide = s
			break
		end
	end

	for _, side in SIDES do
		local face, len = faceFrame(base, side, w, d, 0)
		if not small then
			facadeBands(parent, face, len, h, floorH, color)
		end

		-- Окна по этажам.
		local skipAll = side == accessSide and accessKind == "stairs"
		local n = math.floor((len - 3) / 7)
		if not skipAll and n >= 1 and h >= 7 then
			local floors = math.max(1, math.floor(h / floorH))
			for f = 0, floors - 1 do
				local y0 = f * floorH + (if floorH >= 9 then 3.2 else 2.5)
				local wh = math.min(4.5, floorH - 4)
				if y0 + wh < h - 1 and wh >= 2 then
					for i = 1, n do
						local u = -len / 2 + (i - 0.5) * (len / n)
						local blocked = (side == accessSide and u > len / 2 - 5) -- лестница
							or (side == doorSide and f == 0 and math.abs(u) < 3.5) -- дверь
						if not blocked then
							window(parent, face, u, y0, 3, wh, lit and rng:NextNumber() < 0.3)
						end
					end
					-- Кондиционер между окнами.
					if n >= 2 and f >= 1 and rng:NextNumber() < 0.5 then
						local i = rng:NextInteger(1, n - 1)
						local u = -len / 2 + i * (len / n)
						acUnit(parent, face * CFrame.new(u, y0 + 1, -0.55))
					end
				end
			end
		end

		-- Водосток в углу.
		if not small and (side == "N" or side == "S") then
			pipe(parent, face * CFrame.new(len / 2 - 0.5, h / 2, -0.4), h, 0.25, Color3.fromRGB(110, 112, 115))
		end
	end

	-- Дверь.
	if doorSide then
		local face = faceFrame(base, doorSide, w, d, 0)
		local dh = math.min(7, h - 1.5)
		if dh >= 4 then
			trim(parent, "DoorFrame", Vector3.new(4.4, dh + 0.4, 0.16), face * CFrame.new(0, dh / 2 + 0.2, -0.08), FRAME, Enum.Material.SmoothPlastic)
			trim(parent, "Door", Vector3.new(3.6, dh, 0.14), face * CFrame.new(0, dh / 2, -0.15), DARK_METAL, Enum.Material.Metal)
			trim(parent, "DoorHandle", Vector3.new(0.4, 0.15, 0.2), face * CFrame.new(1.2, 3.5, -0.3), Color3.fromRGB(180, 180, 175), Enum.Material.Metal)
			if not small then
				-- Козырёк над входом.
				trim(parent, "DoorCanopy", Vector3.new(5.5, 0.3, 2), face * CFrame.new(0, dh + 1, -1), TRIM, Enum.Material.Concrete)
			end
		end
	end

	if not small then
		roofProps(parent, base, w, d, h, rng, nil)
	end
end

-- Проёмы оболочки считаются так же, как в MapBuilder.builders.shell.
function decorators.shell(parent: Instance, e, mapId: string, created: { Instance })
	local rng = rngFor(e)
	local w, d, h = e.w, e.d, e.h
	local t = 1
	local base = CFrame.new(e.x, 0, e.z) * yaw(e.rot)
	local color = Color3.fromRGB(150, 140, 125)
	for _, inst in created do
		if inst:IsA("BasePart") and inst.Name == "Wall" then
			color = inst.Color
			break
		end
	end
	local doors = {}
	for _, s in e.doors or {} do
		doors[s] = true
	end
	for _, side in SIDES do
		local face, _ = faceFrame(base, side, w, d, 0)
		local len = if side == "N" or side == "S" then w else d - 2 * t
		-- Без межэтажных поясов (этаж один), карниз по краю крыши.
		facadeBands(parent, face, if side == "N" or side == "S" then w else d, h + 1, h + 10, color)
		if doors[side] then
			openingFrame(parent, face, 0, 6, 0, math.min(8.5, h - 1.5), true)
		end
		if h >= 8 then
			local n = math.floor(len / 10)
			for i = 1, n do
				local u = -len / 2 + (i - 0.5) * (len / n)
				if not doors[side] or math.abs(u) > 6 then
					openingFrame(parent, face, u, 3, 3.5, 6.5, false)
				end
			end
		end
		if side == "N" then
			pipe(parent, face * CFrame.new(w / 2 - 0.5, h / 2, -0.4), h, 0.25, Color3.fromRGB(110, 112, 115))
		end
	end
	-- Люк в углу (см. MapBuilder): туда ничего не ставим.
	local hatch = Vector3.new(w / 2 - t - 5, 0, d / 2 - t - 5)
	roofProps(parent, base, w, d, h + 1, rng, hatch)
end

function decorators.container(parent: Instance, e, _mapId: string, created: { Instance })
	local rng = rngFor(e)
	for _, part in created do
		if part:IsA("BasePart") and part.Name == "Container" then
			if not replaceWithModel(part, "Container", rng, parent) then
				local cf, size = part.CFrame, part.Size
				local rib = part.Color:Lerp(Color3.new(0, 0, 0), 0.15)
				local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
				-- Рёбра по длинным бортам.
				for z = -hz + 1.5, hz - 1.5, 2 do
					for _, sx in { -1, 1 } do
						trim(parent, "Rib", Vector3.new(0.18, size.Y - 0.8, 0.6), cf * CFrame.new(sx * (hx + 0.09), 0, z), rib, Enum.Material.CorrodedMetal)
					end
				end
				-- Угловые стойки и верхние балки.
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						trim(parent, "CornerPost", Vector3.new(0.5, size.Y, 0.5), cf * CFrame.new(sx * (hx - 0.15), 0, sz * (hz - 0.15)), rib, Enum.Material.Metal)
					end
					trim(parent, "TopRail", Vector3.new(0.4, 0.4, size.Z), cf * CFrame.new(sx * (hx - 0.1), hy - 0.2, 0), rib, Enum.Material.Metal)
				end
				-- Двери в торце: шов и запорные штанги.
				trim(parent, "DoorSeam", Vector3.new(0.12, size.Y - 0.6, 0.1), cf * CFrame.new(0, 0, hz + 0.05), rib, Enum.Material.Metal)
				for _, x in { -2.8, -1, 1, 2.8 } do
					trim(parent, "LockRod", Vector3.new(0.14, size.Y - 0.8, 0.14), cf * CFrame.new(x, 0, hz + 0.12), Color3.fromRGB(150, 150, 150), Enum.Material.Metal)
				end
			end
		end
	end
end

function decorators.crate(parent: Instance, e, _mapId: string, created: { Instance })
	local rng = rngFor(e)
	for _, part in created do
		if part:IsA("BasePart") and part.Name == "Crate" then
			if not replaceWithModel(part, "Crate", rng, parent) then
				local s = part.Size
				local band = part.Color:Lerp(Color3.new(0, 0, 0), 0.3)
				for _, y in { -s.Y / 2 + 0.3, s.Y / 2 - 0.3 } do
					trim(parent, "CrateBand", Vector3.new(s.X + 0.1, 0.35, s.Z + 0.1), part.CFrame * CFrame.new(0, y, 0), band, Enum.Material.WoodPlanks)
				end
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						trim(parent, "CrateEdge", Vector3.new(0.35, s.Y, 0.35), part.CFrame * CFrame.new(sx * s.X / 2, 0, sz * s.Z / 2), band, Enum.Material.WoodPlanks)
					end
				end
			end
		end
	end
end

local function linearDetail(parent: Instance, e, created: { Instance }, postEvery: number, postSize: Vector3, capSize: Vector2?, color: Color3?, mat: Enum.Material)
	local part = created[1]
	if not part or not part:IsA("BasePart") then
		return
	end
	local cf, size = part.CFrame, part.Size
	local col = color or part.Color:Lerp(Color3.new(0, 0, 0), 0.25)
	local len = size.Z
	local n = math.max(1, math.floor(len / postEvery))
	for i = 0, n do
		local z = -len / 2 + i * (len / n)
		trim(parent, "Post", postSize, cf * CFrame.new(0, (postSize.Y - size.Y) / 2, z), col, mat)
	end
	if capSize then
		trim(parent, "Cap", Vector3.new(capSize.X, capSize.Y, len), cf * CFrame.new(0, size.Y / 2 + capSize.Y / 2, 0), col:Lerp(Color3.new(1, 1, 1), 0.2), mat)
	end
end

function decorators.fence(parent: Instance, e, _mapId: string, created: { Instance })
	linearDetail(parent, e, created, 6, Vector3.new(0.8, e.h + 0.4, 0.8), Vector2.new(0.7, 0.25), nil, Enum.Material.WoodPlanks)
end

function decorators.wall(parent: Instance, e, _mapId: string, created: { Instance })
	linearDetail(parent, e, created, 12, Vector3.new(2.1, e.h + 0.3, 1.4), Vector2.new(2, 0.35), nil, Enum.Material.Concrete)
end

-- Вызывается из MapBuilder после каждого элемента.
function Detailer.element(geo: Instance, e, mapId: string, created: { Instance })
	local fn = decorators[e.kind]
	if not fn then
		return
	end
	local parent = Instance.new("Model")
	parent.Name = "Detail_" .. e.kind
	fn(parent, e, mapId, created)
	if #parent:GetChildren() > 0 then
		parent.Parent = geo
	else
		parent:Destroy()
	end
end

------------------------------------------------------------------------
-- Дороги: тротуары, бордюры, разметка. Вызывается после сборки карты.

-- Отрезки вдоль дороги (в её локальной Z), свободные от других дорог.
local function freeRuns(road: BasePart, x: number, roads: { BasePart }, margin: number): { { number } }
	local halfLen = road.Size.Z / 2
	local runs = {}
	local start: number? = nil
	local step = 1
	local z = -halfLen
	while z <= halfLen do
		local pos = road.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
		local blocked = false
		for _, other in roads do
			if other ~= road then
				local p = other.CFrame:PointToObjectSpace(pos)
				if math.abs(p.X) < other.Size.X / 2 + margin and math.abs(p.Z) < other.Size.Z / 2 + margin then
					blocked = true
					break
				end
			end
		end
		if not blocked and not start then
			start = z
		elseif blocked and start then
			table.insert(runs, { start, z - step })
			start = nil
		end
		z += step
	end
	if start then
		table.insert(runs, { start, halfLen })
	end
	return runs
end

function Detailer.roads(geo: Instance)
	local cfg = Config.Sidewalks
	local roads: { BasePart } = {}
	for _, part in geo:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Road" then
			table.insert(roads, part)
		end
	end
	local out = Instance.new("Model")
	out.Name = "Detail_Roads"
	for _, road in roads do
		local halfW = road.Size.X / 2
		-- Тротуары с бордюром по обе стороны.
		if cfg.Enabled then
			for _, side in { -1, 1 } do
				local x = side * (halfW + cfg.Width / 2)
				for _, run in freeRuns(road, x, roads, cfg.Width + 0.5) do
					local len = run[2] - run[1]
					if len > 3 then
						local zc = (run[1] + run[2]) / 2
						local walk = trim(out, "Sidewalk", Vector3.new(cfg.Width, cfg.Height, len), road.CFrame * CFrame.new(x, cfg.Height / 2 - road.Size.Y / 2, zc), cfg.Color, Enum.Material.Pavement)
						-- Тротуар твёрдый: по нему ходят, машина переезжает бордюр.
						walk.CanCollide, walk.CanQuery = true, true
						trim(out, "Curb", Vector3.new(0.4, cfg.Height + 0.05, len), road.CFrame * CFrame.new(side * (halfW + 0.2), (cfg.Height + 0.05) / 2 - road.Size.Y / 2, zc), cfg.CurbColor, Enum.Material.Concrete)
					end
				end
			end
		end
		-- Разметка: прерывистая линия по центру.
		if Config.RoadMarkings then
			for _, run in freeRuns(road, 0, roads, 1) do
				local z = run[1] + 2
				while z + 4 <= run[2] - 2 do
					trim(out, "Marking", Vector3.new(0.35, 0.02, 4), road.CFrame * CFrame.new(0, road.Size.Y / 2 + 0.01, z + 2), Color3.fromRGB(225, 222, 210), Enum.Material.SmoothPlastic, { CastShadow = false })
					z += 10
				end
			end
		end
	end
	out.Parent = geo
end

------------------------------------------------------------------------
-- Стены баз: колонны и бетонный парапет.

function Detailer.bases(geo: Instance)
	for _, baseGeo in geo:GetChildren() do
		if baseGeo:IsA("Folder") and baseGeo.Name:sub(1, 5) == "Base_" then
			local out = Instance.new("Model")
			out.Name = "Detail_Base"
			for _, wall in baseGeo:GetChildren() do
				if wall:IsA("BasePart") and wall.Name == "BaseWall" then
					local size = wall.Size
					local long = if size.X > size.Z then "X" else "Z"
					local len = if long == "X" then size.X else size.Z
					local thick = if long == "X" then size.Z else size.X
					local col = wall.Color:Lerp(Color3.new(1, 1, 1), 0.15)
					local capSize = if long == "X" then Vector3.new(len, 0.6, thick + 0.6) else Vector3.new(thick + 0.6, 0.6, len)
					trim(out, "WallCap", capSize, wall.CFrame * CFrame.new(0, size.Y / 2 + 0.3, 0), col, Enum.Material.Concrete)
					local n = math.max(1, math.floor(len / 14))
					for i = 0, n do
						local o = -len / 2 + i * (len / n)
						local offset = if long == "X" then Vector3.new(o, 0, 0) else Vector3.new(0, 0, o)
						local pillar = if long == "X" then Vector3.new(1.4, size.Y + 0.2, thick + 0.8) else Vector3.new(thick + 0.8, size.Y + 0.2, 1.4)
						trim(out, "WallPillar", pillar, wall.CFrame * CFrame.new(offset + Vector3.new(0, 0.1, 0)), col, Enum.Material.Concrete)
					end
				end
			end
			out.Parent = baseGeo
		end
	end
end

------------------------------------------------------------------------
-- Деревья, кусты и мусор из слотов моделей (если они есть).

function Detailer.scatter(geo: Instance, mapId: string)
	local folder = modelsFolder()
	local counts = Config.Scatter[mapId] or Config.Scatter.Default
	if not folder or not counts then
		return
	end
	local mapSize = 1000
	local ok, MapsConfig = pcall(require, ReplicatedStorage.Shared.Config.Maps)
	if ok and MapsConfig.List[mapId] then
		mapSize = MapsConfig.List[mapId].Size
	end
	local rng = Random.new(#mapId * 977)
	local roads: { BasePart } = {}
	for _, part in geo:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Road" then
			table.insert(roads, part)
		end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { geo }

	local out = Instance.new("Model")
	out.Name = "Detail_Scatter"
	out.Parent = geo
	for slot, count in counts do
		if folder:FindFirstChild(slot) then
			local spec = Config.ScatterSlots[slot]
			local placed, tries = 0, 0
			while placed < count and tries < count * 20 do
				tries += 1
				local half = mapSize / 2 - 20
				local pos = Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half, half))
				local onRoad = false
				for _, road in roads do
					local p = road.CFrame:PointToObjectSpace(pos)
					if math.abs(p.X) < road.Size.X / 2 + 5 and math.abs(p.Z) < road.Size.Z / 2 + 5 then
						onRoad = true
						break
					end
				end
				if not onRoad then
					local r = spec.Clearance
					local hits = workspace:GetPartBoundsInBox(CFrame.new(pos + Vector3.new(0, 6, 0)), Vector3.new(r * 2, 10, r * 2), overlap)
					local template = pickModel(slot, rng)
					if #hits == 0 and template then
						local height = rng:NextNumber(spec.Height[1], spec.Height[2])
						placeModel(template, CFrame.new(pos) * yaw(rng:NextNumber(0, 360)), out, Vector3.new(0, height, 0), spec.Solid)
						if spec.Collider then
							-- Невидимый ствол: в дерево нельзя пройти насквозь, пуля в нём застревает.
							local trunk = Instance.new("Part")
							trunk.Name = "TreeCollider"
							trunk.Anchored = true
							trunk.Transparency = 1
							trunk.Size = Vector3.new(spec.Collider, height * 0.6, spec.Collider)
							trunk.CFrame = CFrame.new(pos + Vector3.new(0, height * 0.3, 0))
							trunk.Parent = out
						end
						placed += 1
					end
				end
			end
		end
	end
end

return Detailer
