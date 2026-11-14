-- Отделка карты, чтобы она не выглядела набором кубов. Настройки — Config/Decor.luau.
--
-- 1. Процедурная детализация: рамы и стёкла окон, подоконники, межэтажные пояса, цоколь, карнизы,
--    водостоки, кондиционеры, двери, вентиляция на крышах, рёбра и замки контейнеров, столбы заборов,
--    тротуары с бордюрами, разметка дорог, колонны и парапеты стен баз.
--    Почти все детали без столкновений и без попаданий пуль (CanCollide/CanQuery = false),
--    поэтому геймплей (укрытия, паркур, прострел) остаётся как в обычной ветке.
-- 2. Деревья и кусты из Creator Store (меши в World/DecorAssets.luau), фонари вдоль дорог,
--    уличная мелочь-укрытия (бочки, баки, поддоны, покрышки, скамейки, плиты).
-- 3. Слоты для готовых моделей: положите модель в ServerStorage/DecorModels
--    (Container, Crate — модель или папка с моделями), и она заменит процедурную коробку.
--    Исходная деталь становится невидимой, но остаётся для столкновений и попаданий.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Decor)
local Assets = require(script.Parent.DecorAssets)

local Detailer = {}

local MODELS_FOLDER = "DecorModels"

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

local function lampsOn(_mapId: string): boolean
	return Config.LitWindows == true
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
	local fn = decorators[e.k]
	if not fn then
		return
	end
	local parent = Instance.new("Model")
	parent.Name = "Detail_" .. e.k
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
			-- Соседние куски той же дороги почти параллельны: их не считаем, иначе на стыках дыры.
			if other ~= road and math.abs(other.CFrame.LookVector:Dot(road.CFrame.LookVector)) < 0.95 then
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
		if road.Material ~= Enum.Material.Asphalt then
			continue -- у грунтовок и троп тротуаров и разметки нет
		end
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
-- Деревья и кусты из мешей (DecorAssets).

-- Собирает дерево/куст из записи DecorAssets в точке cf с масштабом k.
local function meshProp(parent: Instance, name: string, parts, cf: CFrame, k: number, leafColor: Color3): Model
	local m = Instance.new("Model")
	m.Name = name
	for _, piece in parts do
		local p = Instance.new("Part")
		p.Name = if piece.leaf then "Leaves" else "Trunk"
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Color = if piece.leaf then leafColor else piece.color
		p.Material = Enum.Material.SmoothPlastic
		local localCf = CFrame.new(table.unpack(piece.cf))
		p.CFrame = cf * CFrame.new(localCf.Position * k) * localCf.Rotation
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = "rbxassetid://" .. piece.mesh
		if piece.tex then
			mesh.TextureId = "rbxassetid://" .. piece.tex
		end
		mesh.Scale = piece.scale * k
		mesh.Parent = p
		p.Parent = m
	end
	m.Parent = parent
	return m
end

------------------------------------------------------------------------
-- Уличная мелочь: твёрдые укрытия из деталей.

local CLUTTER = {}

local function solid(p: BasePart): BasePart
	p.CanCollide, p.CanQuery = true, true
	p.CastShadow = true
	return p
end

function CLUTTER.barrels(parent: Instance, cf: CFrame, rng: Random)
	local colors = { Color3.fromRGB(40, 70, 130), Color3.fromRGB(150, 40, 35), Color3.fromRGB(60, 90, 50), Color3.fromRGB(70, 70, 72) }
	local n = rng:NextInteger(1, 3)
	for i = 1, n do
		local col = colors[rng:NextInteger(1, #colors)]
		local c = cf * CFrame.new((i - 2) * 2.3 + rng:NextNumber(-0.2, 0.2), 1.75, rng:NextNumber(-0.4, 0.4))
		solid(trim(parent, "Barrel", Vector3.new(3.5, 2.2, 2.2), c * CFrame.Angles(0, 0, math.pi / 2), col, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder }))
		for _, y in { -0.9, 0.9 } do
			trim(parent, "BarrelRing", Vector3.new(0.18, 2.3, 2.3), c * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2), col:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		end
	end
end

function CLUTTER.dumpster(parent: Instance, cf: CFrame, rng: Random)
	local col = if rng:NextNumber() < 0.5 then Color3.fromRGB(45, 95, 60) else Color3.fromRGB(60, 70, 95)
	solid(trim(parent, "Dumpster", Vector3.new(6, 3.6, 3.6), cf * CFrame.new(0, 2.1, 0), col, Enum.Material.Metal))
	trim(parent, "DumpsterLid", Vector3.new(6.2, 0.25, 3.8), cf * CFrame.new(0, 4.0, 0.1) * CFrame.Angles(math.rad(-6), 0, 0), col:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Plastic)
	for _, sx in { -2.5, 2.5 } do
		for _, sz in { -1.4, 1.4 } do
			trim(parent, "Wheel", Vector3.new(0.4, 0.6, 0.6), cf * CFrame.new(sx, 0.3, sz) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(25, 25, 25), Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
		end
	end
end

function CLUTTER.pallets(parent: Instance, cf: CFrame, rng: Random)
	local n = rng:NextInteger(2, 6)
	local wood = Color3.fromRGB(170, 135, 90)
	for i = 0, n - 1 do
		local c = cf * CFrame.new(rng:NextNumber(-0.2, 0.2), 0.3 + i * 0.6, rng:NextNumber(-0.2, 0.2)) * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0)
		solid(trim(parent, "Pallet", Vector3.new(4, 0.25, 4), c * CFrame.new(0, 0.17, 0), wood, Enum.Material.WoodPlanks))
		for _, z in { -1.7, 0, 1.7 } do
			trim(parent, "PalletBlock", Vector3.new(4, 0.35, 0.5), c * CFrame.new(0, -0.13, z), wood:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.WoodPlanks)
		end
	end
end

function CLUTTER.tires(parent: Instance, cf: CFrame, rng: Random)
	local n = rng:NextInteger(2, 4)
	for i = 0, n - 1 do
		local c = cf * CFrame.new(rng:NextNumber(-0.3, 0.3), 0.45 + i * 0.85, rng:NextNumber(-0.3, 0.3))
		solid(trim(parent, "Tire", Vector3.new(0.85, 2.8, 2.8), c * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(28, 28, 30), Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder }))
		trim(parent, "TireHole", Vector3.new(0.9, 1.3, 1.3), c * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(12, 12, 12), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	end
end

function CLUTTER.bench(parent: Instance, cf: CFrame, _rng: Random)
	local wood = Color3.fromRGB(150, 105, 65)
	local metal = Color3.fromRGB(45, 45, 48)
	for _, x in { -2.4, 2.4 } do
		solid(trim(parent, "BenchLeg", Vector3.new(0.3, 1.8, 1.6), cf * CFrame.new(x, 0.9, 0), metal, Enum.Material.Metal))
	end
	for i, z in { -0.5, 0, 0.5 } do
		local p = trim(parent, "BenchSeat", Vector3.new(5.6, 0.18, 0.42), cf * CFrame.new(0, 1.85, z), wood, Enum.Material.WoodPlanks)
		if i == 2 then
			solid(p)
		end
	end
	trim(parent, "BenchBack", Vector3.new(5.6, 1, 0.18), cf * CFrame.new(0, 2.6, 0.8) * CFrame.Angles(math.rad(-12), 0, 0), wood, Enum.Material.WoodPlanks)
end

function CLUTTER.slabs(parent: Instance, cf: CFrame, rng: Random)
	local n = rng:NextInteger(2, 4)
	for i = 0, n - 1 do
		local c = cf * CFrame.new(rng:NextNumber(-0.4, 0.4), 0.35 + i * 0.7, rng:NextNumber(-0.4, 0.4)) * CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0)
		solid(trim(parent, "Slab", Vector3.new(9, 0.7, 4), c, Color3.fromRGB(165, 162, 155), Enum.Material.Concrete))
	end
end

function CLUTTER.pipes(parent: Instance, cf: CFrame, rng: Random)
	local col = Color3.fromRGB(120, 105, 90)
	for i, x in { -1.6, 0, 1.6 } do
		if i < 3 or rng:NextNumber() < 0.5 then
			solid(trim(parent, "BigPipe", Vector3.new(10, 1.5, 1.5), cf * CFrame.new(x, 0.75, 0) * CFrame.Angles(0, math.pi / 2, 0), col, Enum.Material.CorrodedMetal, { Shape = Enum.PartType.Cylinder }))
		end
	end
	solid(trim(parent, "BigPipe", Vector3.new(10, 1.5, 1.5), cf * CFrame.new(-0.8, 2.05, 0) * CFrame.Angles(0, math.pi / 2, 0), col, Enum.Material.CorrodedMetal, { Shape = Enum.PartType.Cylinder }))
end

local CLUTTER_KINDS = { "barrels", "barrels", "dumpster", "pallets", "pallets", "tires", "bench", "slabs", "pipes" }

------------------------------------------------------------------------
-- Расстановка: деревья, кусты, мелочь. Места выбираются вне дорог и построек.

local function roadParts(geo: Instance): { BasePart }
	local roads: { BasePart } = {}
	for _, part in geo:GetChildren() do
		if part:IsA("BasePart") and (part.Name == "Road" or part.Name == "RoadJoint") then
			table.insert(roads, part)
		end
	end
	return roads
end

local function nearRoad(roads: { BasePart }, pos: Vector3, margin: number): boolean
	for _, road in roads do
		if road.Name == "RoadJoint" then
			-- Круглая заплатка на стыке (цилиндр, радиус = половина ширины дороги).
			local d = Vector3.new(pos.X - road.Position.X, 0, pos.Z - road.Position.Z).Magnitude
			if d < road.Size.Y / 2 + margin then
				return true
			end
		else
			local p = road.CFrame:PointToObjectSpace(pos)
			if math.abs(p.X) < road.Size.X / 2 + margin and math.abs(p.Z) < road.Size.Z / 2 + margin then
				return true
			end
		end
	end
	return false
end

function Detailer.scatter(geo: Instance, mapId: string)
	local counts = Config.Scatter[mapId] or Config.Scatter.Default
	if not counts then
		return
	end
	local mapSize = 1000
	local ok, MapsConfig = pcall(require, ReplicatedStorage.Shared.Config.Maps)
	if ok and MapsConfig.List[mapId] then
		mapSize = MapsConfig.List[mapId].Size
	end
	local rng = Random.new(#mapId * 977 + 13)
	local roads = roadParts(geo)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { geo }

	local out = Instance.new("Model")
	out.Name = "Detail_Scatter"
	out.Parent = geo
	local half = mapSize / 2 - 25
	-- Высота земли: на холмах (Terrain) ставим на склон.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { workspace.Terrain }
	local function groundAt(pos: Vector3): number
		local hit = workspace:Raycast(pos + Vector3.new(0, 80, 0), Vector3.new(0, -100, 0), rayParams)
		return if hit then hit.Position.Y else 0
	end

	-- Место свободно: не на дороге и рядом нет деталей карты (кроме земли).
	local function freeSpot(clearance: number, roadMargin: number): Vector3?
		for _ = 1, 25 do
			local pos = Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half, half))
			if not nearRoad(roads, pos, roadMargin) then
				local hits = workspace:GetPartBoundsInBox(CFrame.new(pos + Vector3.new(0, 7, 0)), Vector3.new(clearance * 2, 12, clearance * 2), overlap)
				local blocked = false
				for _, h in hits do
					if h.Name ~= "Ground" and h.Name ~= "Boundary" and h.Name ~= "Patch" then
						blocked = true
						break
					end
				end
				if not blocked then
					return Vector3.new(pos.X, groundAt(pos), pos.Z)
				end
			end
		end
		return nil
	end

	-- Пятна на земле: несколько плоских дисков внахлёст дают неровную форму.
	local patches = Config.Patches[mapId] or Config.Patches.Default
	local ground = geo:FindFirstChild("Ground") :: BasePart?
	local groundColor = if ground then ground.Color else Color3.fromRGB(100, 100, 100)
	local PATCH = {
		Grass = { mat = Enum.Material.Grass, color = function()
			return Color3.fromRGB(86, 112, 62):Lerp(Color3.fromRGB(110, 120, 70), rng:NextNumber())
		end },
		Dirt = { mat = Enum.Material.Ground, color = function()
			return Color3.fromRGB(112, 92, 68):Lerp(Color3.fromRGB(130, 112, 86), rng:NextNumber())
		end },
		Stain = { mat = Enum.Material.SmoothPlastic, color = function()
			return groundColor:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0.25, 0.45))
		end },
		Light = { mat = if ground then ground.Material else Enum.Material.Concrete, color = function()
			return groundColor:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0.08, 0.18))
		end },
	}
	local patchOut = Instance.new("Model")
	patchOut.Name = "Patches"
	for kind, count in patches do
		local spec = PATCH[kind]
		for _ = 1, count do
			local pos = Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half, half))
			local r = rng:NextNumber(5, if kind == "Stain" then 9 else 16)
			-- Пятно не должно заходить на дорогу: иначе на асфальте мерцает.
			if spec and not nearRoad(roads, pos, r * 1.7 + 1) then
				local col = spec.color()
				for j = 1, rng:NextInteger(2, 4) do
					local off = if j == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-r, r), 0, rng:NextNumber(-r, r)) * 0.7
					local rr = r * rng:NextNumber(0.5, 1)
					local disk = trim(patchOut, "Patch", Vector3.new(0.04, rr * 2, rr * 2), CFrame.new(pos + off + Vector3.new(0, 0.02 + j * 0.003, 0)) * CFrame.Angles(0, 0, math.pi / 2), col, spec.mat, { Shape = Enum.PartType.Cylinder })
					disk.CastShadow = false
				end
			end
		end
	end
	patchOut.Parent = out

	for _, kind in { "Oak", "Spruce", "Bush" } do
		local list = Assets[kind]
		for _ = 1, counts[kind] or 0 do
			local isTree = kind ~= "Bush"
			local pos = freeSpot(if isTree then 5 else 2.5, if isTree then 6 else 2)
			if pos then
				local k = if isTree then rng:NextNumber(Config.TreeScale[1], Config.TreeScale[2]) else rng:NextNumber(0.7, 1.15)
				local leafColor = Config.LeafColors[rng:NextInteger(1, #Config.LeafColors)]
				local cf = CFrame.new(pos) * yaw(rng:NextNumber(0, 360))
				local m = meshProp(out, kind, list[rng:NextInteger(1, #list)], cf, k, leafColor)
				if isTree then
					-- Невидимый ствол: сквозь дерево не пройти, пуля в нём застревает.
					local trunkH = 12 * k / 0.7
					local trunk = Instance.new("Part")
					trunk.Name = "TreeCollider"
					trunk.Anchored = true
					trunk.Transparency = 1
					trunk.Size = Vector3.new(1.8 * k / 0.7, trunkH, 1.8 * k / 0.7)
					trunk.CFrame = CFrame.new(pos + Vector3.new(0, trunkH / 2, 0))
					trunk.Material = Enum.Material.Wood
					trunk.Parent = m
				end
			end
		end
	end

	for _ = 1, counts.Clutter or 0 do
		local pos = freeSpot(4, 3)
		if pos then
			local kind = CLUTTER_KINDS[rng:NextInteger(1, #CLUTTER_KINDS)]
			local m = Instance.new("Model")
			m.Name = "Clutter_" .. kind
			CLUTTER[kind](m, CFrame.new(pos) * yaw(rng:NextNumber(0, 360)), rng)
			m.Parent = out
		end
	end
end

------------------------------------------------------------------------
-- Фонари вдоль асфальтовых дорог.

local function streetLamp(parent: Instance, base: CFrame, armDir: number)
	local metal = Color3.fromRGB(70, 74, 78)
	local post = trim(parent, "LampPost", Vector3.new(14, 0.6, 0.6), base * CFrame.new(0, 7, 0) * CFrame.Angles(0, 0, math.pi / 2), metal, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	post.CanCollide, post.CanQuery = true, true
	trim(parent, "LampBase", Vector3.new(1.2, 1, 1.2), base * CFrame.new(0, 0.5, 0), metal, Enum.Material.Metal)
	trim(parent, "LampArm", Vector3.new(0.3, 0.3, 3.2), base * CFrame.new(0, 13.8, armDir * 1.5), metal, Enum.Material.Metal)
	trim(parent, "LampHead", Vector3.new(1.1, 0.45, 1.8), base * CFrame.new(0, 13.6, armDir * 3), metal, Enum.Material.Metal)
	local glass = trim(parent, "LampGlass", Vector3.new(0.9, 0.1, 1.5), base * CFrame.new(0, 13.35, armDir * 3), Color3.fromRGB(255, 228, 170), Enum.Material.Glass)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 120
	light.Range = 32
	light.Brightness = 2.2
	light.Color = Color3.fromRGB(255, 214, 160)
	light.Shadows = false
	light.Enabled = false
	light.Parent = glass
	game:GetService("CollectionService"):AddTag(glass, "StreetLamp")
	return glass
end

function Detailer.lamps(geo: Instance)
	local cfg = Config.Lamps
	if not cfg or not cfg.Enabled then
		return
	end
	local roads = roadParts(geo)
	local out = Instance.new("Model")
	out.Name = "Detail_Lamps"
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { geo }
	local walk = if Config.Sidewalks and Config.Sidewalks.Enabled then Config.Sidewalks.Width else 0
	local side = 1
	local acc = 0 -- сколько прошли от прошлого фонаря: куски дороги идут подряд
	for _, road in roads do
		if road.Name == "Road" and road.Material == Enum.Material.Asphalt then
			local len = road.Size.Z
			local z = -len / 2 + (cfg.Spacing - acc)
			while z <= len / 2 do
				local x = side * (road.Size.X / 2 + walk - 0.8)
				local pos = road.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
				local blocked = false
				-- Не на перекрёстке: точка не должна попадать на другие (непараллельные) дороги.
				for _, other in roads do
					if other ~= road and other.Name == "Road" and math.abs(other.CFrame.LookVector:Dot(road.CFrame.LookVector)) < 0.95 then
						local p = other.CFrame:PointToObjectSpace(pos)
						if math.abs(p.X) < other.Size.X / 2 + 2 and math.abs(p.Z) < other.Size.Z / 2 + 2 then
							blocked = true
							break
						end
					end
				end
				if not blocked then
					local hits = workspace:GetPartBoundsInBox(CFrame.new(pos.X, 7, pos.Z), Vector3.new(1.5, 10, 1.5), overlap)
					for _, h in hits do
						if h.CanCollide and h.Name ~= "Ground" and h.Name ~= "Sidewalk" and h.Name ~= "Curb" then
							blocked = true
							break
						end
					end
				end
				if not blocked then
					streetLamp(out, CFrame.new(pos.X, 0, pos.Z) * road.CFrame.Rotation * CFrame.Angles(0, math.pi / 2, 0), -side)
					side = -side
				end
				z += cfg.Spacing
			end
			acc = (acc + len) % cfg.Spacing
		end
	end
	out.Parent = geo
end

-- Ночью фонари горят, днём — нет. Вызывается после настройки света.
function Detailer.updateLamps(clockTime: number)
	local cfg = Config.Lamps
	local night = clockTime >= cfg.NightFrom or clockTime <= cfg.NightTo
	for _, glass in game:GetService("CollectionService"):GetTagged("StreetLamp") do
		local light = glass:FindFirstChildOfClass("SpotLight")
		if light then
			light.Enabled = night
		end
		glass.Material = if night then Enum.Material.Neon else Enum.Material.Glass
	end
end

return Detailer
