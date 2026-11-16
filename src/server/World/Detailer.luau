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
local Props = require(script.Parent.Props)

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

-- ServerStorage/DecorModels, а если её нет — ServerStorage/RealisticModels (так назывался слот раньше).
local function modelsFolder(): Instance?
	return ServerStorage:FindFirstChild(MODELS_FOLDER) or ServerStorage:FindFirstChild("RealisticModels")
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
-- Витрина магазина

local SHOPS = {
	{ "ПРОДУКТЫ", Color3.fromRGB(40, 120, 60) },
	{ "АПТЕКА", Color3.fromRGB(40, 150, 90) },
	{ "ШАУРМА", Color3.fromRGB(200, 110, 30) },
	{ "ЛОМБАРД", Color3.fromRGB(160, 130, 40) },
	{ "ШИНОМОНТАЖ", Color3.fromRGB(40, 40, 45) },
	{ "ЦВЕТЫ", Color3.fromRGB(190, 60, 110) },
	{ "ХОЗТОВАРЫ", Color3.fromRGB(150, 80, 40) },
	{ "РЕМОНТ ТЕЛЕФОНОВ", Color3.fromRGB(40, 80, 160) },
	{ "БАР «ПОДВАЛ»", Color3.fromRGB(110, 30, 35) },
	{ "ПАРИКМАХЕРСКАЯ", Color3.fromRGB(120, 60, 140) },
	{ "МАГАЗИН 24 ЧАСА", Color3.fromRGB(200, 40, 40) },
	{ "ОПТИКА", Color3.fromRGB(30, 110, 150) },
	{ "СТОЛОВАЯ", Color3.fromRGB(170, 100, 50) },
	{ "АВТОЗАПЧАСТИ", Color3.fromRGB(60, 60, 70) },
	{ "ПЕКАРНЯ", Color3.fromRGB(180, 130, 60) },
	{ "МИКРОЗАЙМЫ", Color3.fromRGB(230, 170, 20) },
}

-- shop — номер вывески (1..#SHOPS, по кругу). Витрина по сторонам от двери (дверь в центре).
local function shopFront(parent: Instance, face: CFrame, len: number, h: number, shop: number, _rng: Random)
	local info = SHOPS[(shop - 1) % #SHOPS + 1]
	local col = info[2]
	local glassTop = math.min(5.6, h - 3)
	for _, sgn in { -1, 1 } do
		local u0, u1 = 2.6, len / 2 - 1
		if u1 - u0 > 1.5 then
			local u = sgn * (u0 + u1) / 2
			local w = u1 - u0
			trim(parent, "ShopFrame", Vector3.new(w + 0.4, glassTop - 0.6, 0.16), face * CFrame.new(u, 0.8 + (glassTop - 0.8) / 2, -0.08), FRAME, Enum.Material.SmoothPlastic)
			trim(parent, "ShopWindow", Vector3.new(w, glassTop - 1, 0.1), face * CFrame.new(u, 0.8 + (glassTop - 0.8) / 2, -0.17), GLASS:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.Glass, { Reflectance = 0.2 })
			local n = math.max(1, math.floor(w / 4))
			for i = 1, n - 1 do
				trim(parent, "ShopMullion", Vector3.new(0.18, glassTop - 1, 0.1), face * CFrame.new(u - w / 2 + i * w / n, 0.8 + (glassTop - 0.8) / 2, -0.25), FRAME, Enum.Material.SmoothPlastic)
			end
		end
	end
	-- Вывеска и навес.
	local signW = math.min(len - 2, 18)
	local signY = glassTop + 1.3
	local board = trim(parent, "ShopSign", Vector3.new(signW, 1.8, 0.3), face * CFrame.new(0, signY, -0.2), col, Enum.Material.SmoothPlastic)
	local text = trim(parent, "ShopSignText", Vector3.new(signW - 0.6, 1.4, 0.05), face * CFrame.new(0, signY, -0.38), col, Enum.Material.SmoothPlastic, { Transparency = 1 })
	Props.label(text, info[1], Color3.fromRGB(255, 255, 255), Enum.Font.GothamBlack)
	board.CastShadow = false
	trim(parent, "Awning", Vector3.new(len - 1.5, 0.2, 2.6), face * CFrame.new(0, glassTop + 0.15, -1.2) * CFrame.Angles(math.rad(-14), 0, 0), col:Lerp(Color3.new(1, 1, 1), 0.25), Enum.Material.Fabric)
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

		-- Магазин: на улицу смотрит витрина с вывеской вместо окон первого этажа.
		local isShopFront = e.shop and side == "N"
		if isShopFront then
			shopFront(parent, face, len, h, e.shop, rng)
		end

		-- Окна по этажам.
		local skipAll = (side == accessSide and accessKind == "stairs") or isShopFront
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
			if not small and not e.shop then
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

-- Дерево или куст: реалистичная модель из ServerStorage/DecorModels (или RealisticModels),
-- папки Trees и Bushes, если они есть; иначе меш из DecorAssets.
-- k — тот же масштаб, что у меша: высота дерева ~ 35 * k студов, куста ~ 4.5 * k.
local function plant(parent: Instance, kind: string, parts, cf: CFrame, k: number, leafColor: Color3, rng: Random): Model
	local slot = if kind == "Bush" then "Bushes" else "Trees"
	local template = pickModel(slot, rng)
	if template then
		local height = if kind == "Bush" then 4.5 * k else 35 * k
		local m = placeModel(template, cf, parent, Vector3.new(0, height, 0), false)
		m.Name = kind
		return m
	end
	return meshProp(parent, kind, parts, cf, k, leafColor)
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

CLUTTER.trashbags = Props.trashbags
CLUTTER.couch = Props.couch
CLUTTER.wreck = Props.wreck
CLUTTER.binarea = Props.binArea
CLUTTER.planter = Props.planter

local CLUTTER_KINDS = {
	"barrels", "barrels", "dumpster", "dumpster", "pallets", "pallets", "tires", "bench", "slabs", "pipes",
	"trashbags", "trashbags", "trashbags", "couch", "wreck", "binarea", "planter",
}
-- Большим вещам нужно больше места.
local CLUTTER_CLEARANCE = { wreck = 9, binarea = 8, slabs = 6, pipes = 6 }

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

-- Куда отделку не ставим: базы команд (с запасом вокруг стен, чтобы не загородить ворота)
-- и точки появления. Возвращает проверку (позиция, радиус) -> true, если место запретное.
local function keepOut(geo: Instance): (Vector3, number) -> boolean
	local map = geo.Parent
	local volumes: { BasePart } = {}
	local spawnPoints: { Vector3 } = {}
	local bases = map and map:FindFirstChild("Bases")
	if bases then
		for _, b in bases:GetChildren() do
			if b:IsA("BasePart") then
				table.insert(volumes, b)
			end
		end
	end
	local spawns = map and map:FindFirstChild("Spawns")
	if spawns then
		for _, f in spawns:GetChildren() do
			for _, sp in f:GetChildren() do
				if sp:IsA("BasePart") then
					table.insert(spawnPoints, sp.Position)
				end
			end
		end
	end
	return function(pos: Vector3, r: number): boolean
		for _, v in volumes do
			local p = v.CFrame:PointToObjectSpace(pos)
			if math.abs(p.X) < v.Size.X / 2 + r + 8 and math.abs(p.Z) < v.Size.Z / 2 + r + 8 then
				return true
			end
		end
		for _, sp in spawnPoints do
			if Vector3.new(sp.X - pos.X, 0, sp.Z - pos.Z).Magnitude < r + 5 then
				return true
			end
		end
		return false
	end
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

	-- Место свободно: не на дороге, не на базе и рядом нет деталей карты (кроме земли).
	local forbidden = keepOut(geo)
	local function freeSpot(clearance: number, roadMargin: number): Vector3?
		for _ = 1, 25 do
			local pos = Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half, half))
			if not nearRoad(roads, pos, roadMargin) and not forbidden(pos, clearance) then
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
				local m = plant(out, kind, list[rng:NextInteger(1, #list)], cf, k, leafColor, rng)
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
		local kind = CLUTTER_KINDS[rng:NextInteger(1, #CLUTTER_KINDS)]
		local pos = freeSpot(CLUTTER_CLEARANCE[kind] or 4, 3)
		if pos then
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
	local forbidden = keepOut(geo)
	local side = 1
	local acc = 0 -- сколько прошли от прошлого фонаря: куски дороги идут подряд
	for _, road in roads do
		if road.Name == "Road" and road.Material == Enum.Material.Asphalt then
			local len = road.Size.Z
			local z = -len / 2 + (cfg.Spacing - acc)
			while z <= len / 2 do
				local x = side * (road.Size.X / 2 + walk - 0.8)
				local pos = road.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
				local blocked = forbidden(pos, 1)
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

------------------------------------------------------------------------
-- Улицы: урны, знаки, столбы с проводами, деревья, остановки, киоски, щиты, изгороди, переходы.

-- Точка попадает на другую дорогу с запасом r? Куски той же дороги (атрибут RoadId) проверяются
-- без запаса и без круглых стыков: иначе соседние куски «закрывали» бы всё вдоль улицы.
local function onOtherRoad(roads: { BasePart }, road: BasePart?, pos: Vector3, r: number): boolean
	local id = road and road:GetAttribute("RoadId")
	for _, other in roads do
		if other ~= road then
			local same = id ~= nil and other:GetAttribute("RoadId") == id
			if same then
				if other.Name == "Road" then
					local p = other.CFrame:PointToObjectSpace(pos)
					if math.abs(p.X) < other.Size.X / 2 and math.abs(p.Z) < other.Size.Z / 2 then
						return true
					end
				end
			elseif other.Name == "RoadJoint" then
				local d = Vector3.new(pos.X - other.Position.X, 0, pos.Z - other.Position.Z).Magnitude
				if d < other.Size.Y / 2 + r then
					return true
				end
			else
				local p = other.CFrame:PointToObjectSpace(pos)
				if math.abs(p.X) < other.Size.X / 2 + r and math.abs(p.Z) < other.Size.Z / 2 + r then
					return true
				end
			end
		end
	end
	return false
end

local IGNORE_HITS = { Ground = true, Sidewalk = true, Curb = true, Boundary = true, Patch = true }

-- В коробке нет твёрдых деталей карты (кроме земли и тротуара)?
local function boxFree(cf: CFrame, size: Vector3, overlap: OverlapParams): boolean
	for _, h in workspace:GetPartBoundsInBox(cf, size, overlap) do
		if h.CanCollide and not IGNORE_HITS[h.Name] then
			return false
		end
	end
	return true
end

-- Дерево у тротуара: меш дуба поменьше, приствольная лунка, невидимый твёрдый ствол.
local function streetTree(parent: Instance, cf: CFrame, rng: Random)
	local k = rng:NextNumber(0.38, 0.52)
	local leafColor = Config.LeafColors[rng:NextInteger(1, #Config.LeafColors)]
	local m = plant(parent, "Oak", Assets.Oak[rng:NextInteger(1, #Assets.Oak)], cf * yaw(rng:NextNumber(0, 360)), k, leafColor, rng)
	m.Name = "StreetTree"
	local trunkH = 12 * k / 0.7
	local trunk = Instance.new("Part")
	trunk.Name = "TreeCollider"
	trunk.Anchored = true
	trunk.Transparency = 1
	trunk.Size = Vector3.new(1.4, trunkH, 1.4)
	trunk.CFrame = cf * CFrame.new(0, trunkH / 2, 0)
	trunk.Parent = m
	trim(m, "TreePit", Vector3.new(3.4, 0.08, 3.4), cf * CFrame.new(0, 0.04, 0), Color3.fromRGB(78, 62, 46), Enum.Material.Ground, { CastShadow = false })
	trim(m, "TreePitEdge", Vector3.new(3.8, 0.12, 3.8), cf * CFrame.new(0, 0.03, 0), Color3.fromRGB(150, 148, 142), Enum.Material.Concrete, { CastShadow = false })
end

-- Виды уличных вещей. off — отступ от края дороги (тротуар шириной walk), size — габарит
-- для проверки места (X вдоль дороги), oneSide — только по одной стороне.
local STREET_ITEMS = {
	{ key = "Crosswalks", phase = 0.5 },
	{ key = "BusStops", phase = 0.3, off = function(walk) return walk + 2.8 end, size = Vector3.new(11.5, 9, 5) },
	{ key = "Kiosks", phase = 0.7, off = function(walk) return walk + 3.4 end, size = Vector3.new(8, 8, 6) },
	{ key = "Billboards", phase = 0.1, off = function(walk) return walk + 6 end, size = Vector3.new(23, 21, 2.4), y0 = 0 },
	{ key = "Poles", phase = 0.15, off = function(walk) return walk + 0.9 end, size = Vector3.new(1.6, 19, 1.6), oneSide = true },
	{ key = "Trees", phase = 0.4, off = function(walk) return walk + 2.4 end, size = Vector3.new(4, 10, 4) },
	{ key = "Hedges", phase = 0.85, off = function(walk) return walk + 1.3 end, size = Vector3.new(8.4, 3, 2.2) },
	{ key = "Bins", phase = 0.6, off = function(walk) return walk - 0.9 end, size = Vector3.new(1.8, 3, 1.8) },
	{ key = "Hydrants", phase = 0.25, off = function(_walk) return 1 end, size = Vector3.new(1.4, 3, 1.4) },
	{ key = "Signs", phase = 0.9, off = function(_walk) return 0.6 end, size = Vector3.new(1.2, 9, 1.2) },
}

function Detailer.street(geo: Instance, mapId: string)
	local cfg = Config.Street and (Config.Street[mapId] or Config.Street.Default)
	if not cfg then
		return
	end
	local roads = roadParts(geo)
	local walk = if Config.Sidewalks and Config.Sidewalks.Enabled then Config.Sidewalks.Width else 0
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { geo }
	local rng = Random.new(#mapId * 541 + 7)
	local forbidden = keepOut(geo)
	local out = Instance.new("Model")
	out.Name = "Detail_Street"
	out.Parent = geo

	local acc, side = {}, {}
	for _, item in STREET_ITEMS do
		local spacing = cfg[item.key] or 0
		acc[item.key] = spacing * (1 - item.phase)
		side[item.key] = 1
	end
	local lastPole: Vector3? = nil

	for _, road in roads do
		if road.Name ~= "Road" or road.Material ~= Enum.Material.Asphalt then
			continue
		end
		local len = road.Size.Z
		local hw = road.Size.X / 2
		local look, right = road.CFrame.LookVector, road.CFrame.RightVector
		for _, item in STREET_ITEMS do
			local spacing = cfg[item.key] or 0
			if spacing <= 0 then
				continue
			end
			local z = -len / 2 + (spacing - acc[item.key])
			while z <= len / 2 do
				local placed = false
				if item.key == "Crosswalks" then
					-- «Зебра» поперёк дороги и знаки по обе стороны. Не у перекрёстка.
					local center = road.CFrame:PointToWorldSpace(Vector3.new(0, 0, z))
					if z > -len / 2 + 3 and z < len / 2 - 3 and not onOtherRoad(roads, road, center, hw + 10) and not forbidden(center, hw + 4) then
						local m = Instance.new("Model")
						m.Name = "Crosswalk"
						local x = -hw + 1.2
						while x <= hw - 1.2 do
							trim(m, "Zebra", Vector3.new(1.2, 0.02, 5), road.CFrame * CFrame.new(x, road.Size.Y / 2 + 0.015, z), Color3.fromRGB(232, 230, 222), Enum.Material.SmoothPlastic, { CastShadow = false })
							x += 2.4
						end
						for _, s in { -1, 1 } do
							local p = road.CFrame:PointToWorldSpace(Vector3.new(s * (hw + 0.6), 0, z + s * 3.5))
							local cf = CFrame.lookAt(Vector3.new(p.X, 0, p.Z), Vector3.new(p.X, 0, p.Z) - look * s)
							if boxFree(cf * CFrame.new(0, 4.5, 0), Vector3.new(1.2, 9, 1.2), overlap) then
								Props.roadSign(m, cf, "crossing", rng)
							end
						end
						m.Parent = out
						placed = true
					end
				else
					local s = side[item.key]
					local x = s * (hw + item.off(walk))
					local pos = road.CFrame:PointToWorldSpace(Vector3.new(x, 0, z))
					pos = Vector3.new(pos.X, 0, pos.Z)
					local halfAlong = item.size.X / 2
					local r = math.max(item.size.Z / 2, 0.5)
					local ends = { pos, pos + look * halfAlong, pos - look * halfAlong }
					local ok = not forbidden(pos, math.max(halfAlong, r))
					for _, p in ends do
						if onOtherRoad(roads, road, p, r) then
							ok = false
							break
						end
					end
					-- Лицом к дороге: -Z смотрит на ось дороги, X идёт вдоль неё.
					local cf = CFrame.lookAt(pos, pos - right * s)
					if ok and boxFree(cf * CFrame.new(0, item.size.Y / 2 + 0.3, 0), item.size, overlap) then
						local m = Instance.new("Model")
						m.Name = "Street_" .. item.key
						if item.key == "BusStops" then
							Props.busStop(m, cf, rng)
						elseif item.key == "Kiosks" then
							Props.kiosk(m, cf, rng)
						elseif item.key == "Billboards" then
							Props.billboard(m, cf * yaw(rng:NextNumber(-12, 12)), rng)
						elseif item.key == "Poles" then
							local a, b = Props.powerPole(m, cf)
							if lastPole and (lastPole - pos).Magnitude < spacing * 1.6 then
								Props.wire(m, lastPole + (a - pos), a)
								Props.wire(m, lastPole + (b - pos), b)
							end
							lastPole = pos
						elseif item.key == "Trees" then
							streetTree(m, cf, rng)
						elseif item.key == "Hedges" then
							Props.hedge(m, cf, 8, rng)
						elseif item.key == "Bins" then
							Props.bin(m, cf, rng)
						elseif item.key == "Hydrants" then
							Props.hydrant(m, cf)
						elseif item.key == "Signs" then
							-- Знак смотрит навстречу движению по своей стороне.
							Props.roadSign(m, CFrame.lookAt(pos, pos + look * s), Props.pick(Props.SIGN_KINDS, rng), rng)
						end
						m.Parent = out
						placed = true
					end
				end
				if placed then
					if not item.oneSide then
						side[item.key] = -side[item.key]
					end
					z += spacing
				else
					z += math.max(4, spacing * 0.15) -- место занято: пробуем чуть дальше
				end
			end
			-- Сколько уже прошли к следующей вещи: продолжаем на следующем куске дороги.
			acc[item.key] = math.clamp(spacing - (z - len / 2), 0, spacing)
		end
	end
end

------------------------------------------------------------------------
-- Дворы: контейнерные площадки и мусор у задних стен, адресные таблички, граффити.

function Detailer.yards(geo: Instance, mapId: string)
	local cfg = Config.Yards and (Config.Yards[mapId] or Config.Yards.Default)
	if not cfg then
		return
	end
	local roads = roadParts(geo)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { geo }
	local forbidden = keepOut(geo)
	local out = Instance.new("Model")
	out.Name = "Detail_Yards"
	out.Parent = geo

	-- Дома: глухие здания (Building) и оболочки (по полу Floor, стены на 1 шире).
	local houses = {}
	for _, p in geo:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name == "Building" then
				table.insert(houses, { base = p.CFrame * CFrame.new(0, -p.Size.Y / 2, 0), w = p.Size.X, d = p.Size.Z, h = p.Size.Y, shell = false })
			elseif p.Name == "Floor" then
				table.insert(houses, { base = p.CFrame * CFrame.new(0, -0.1, 0), w = p.Size.X + 2, d = p.Size.Z + 2, h = 9, shell = true })
			end
		end
	end

	for _, house in houses do
		local w, d, h = house.w, house.d, house.h
		if w < 9 or d < 9 then
			continue -- сараи и будки
		end
		local pos = house.base.Position
		local rng = Random.new(math.floor(pos.X * 31 + pos.Z * 17) % 2 ^ 30)

		-- Мусор у задней (S) или боковой стены.
		if rng:NextNumber() < (cfg.Trash or 0) then
			local sideName = if rng:NextNumber() < 0.65 then "S" else Props.pick({ "E", "W" }, rng)
			local face, len = faceFrame(house.base, sideName, w, d, 0)
			local big = len >= 18 and rng:NextNumber() < 0.6
			local along = if big then 13 else 6
			if len > along + 2 then
				local u = rng:NextNumber(-len / 2 + along / 2 + 1, len / 2 - along / 2 - 1)
				local depth = if big then 6 else 3.6
				local cf = face * CFrame.new(u, 0, -depth / 2 - 0.8)
				cf = CFrame.new(cf.Position.X, 0, cf.Position.Z) * cf.Rotation
				local p = cf.Position
				if not forbidden(p, along / 2) and not onOtherRoad(roads, nil, p, depth / 2 + 1) and boxFree(cf * CFrame.new(0, 2.3, 0), Vector3.new(along, 4, depth), overlap) then
					local m = Instance.new("Model")
					m.Name = "Yard_Trash"
					if big then
						Props.binArea(m, cf, rng)
					else
						Props.dumpster(m, cf * CFrame.new(-1, 0, 0), rng)
						if rng:NextNumber() < 0.7 then
							Props.trashbags(m, cf * CFrame.new(3.6, 0, -0.3), rng)
						end
					end
					m.Parent = out
				end
			end
		end

		-- Табличка с адресом на углу уличного фасада.
		if not house.shell and h >= 9 and rng:NextNumber() < (cfg.Address or 0) then
			local face, len = faceFrame(house.base, "N", w, d, 0)
			Props.addressPlate(out, face * CFrame.new(len / 2 - 2.6, math.min(8.3, h - 2), -0.25), rng)
		end

		-- Граффити внизу стены (не по центру, где обычно дверь).
		if rng:NextNumber() < (cfg.Graffiti or 0) then
			local sideName = Props.pick({ "N", "S", "E", "W" }, rng)
			local face, len = faceFrame(house.base, sideName, w, d, 0)
			local gw = math.min(len - 8, rng:NextNumber(5, 9))
			if gw >= 4 then
				local half = len / 2 - gw / 2 - 0.5
				local minU = gw / 2 + 3.5
				if half > minU then
					local u = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(minU, half)
					Props.graffiti(out, face * CFrame.new(u, 1.9, -0.33), gw, 2.9, rng)
				end
			end
		end
	end
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

------------------------------------------------------------------------
-- Для города (World/CityBuilder.luau): те же деревья, кусты и фонари, что и на картах.

-- Дерево у тротуара (с лункой и твёрдым стволом).
function Detailer.tree(parent: Instance, cf: CFrame, rng: Random)
	streetTree(parent, cf, rng)
end

-- Большое дерево в парке или во дворе: k ~ 0.5..0.8 (высота ~ 35 * k).
function Detailer.bigTree(parent: Instance, cf: CFrame, rng: Random, k: number)
	local leafColor = Config.LeafColors[rng:NextInteger(1, #Config.LeafColors)]
	local m = plant(parent, "Oak", Assets.Oak[rng:NextInteger(1, #Assets.Oak)], cf * yaw(rng:NextNumber(0, 360)), k, leafColor, rng)
	local trunkH = 12 * k / 0.7
	local trunk = Instance.new("Part")
	trunk.Name = "TreeCollider"
	trunk.Anchored = true
	trunk.Transparency = 1
	trunk.Size = Vector3.new(1.6, trunkH, 1.6)
	trunk.CFrame = cf * CFrame.new(0, trunkH / 2, 0)
	trunk.Parent = m
	return m
end

-- Куст (сквозь него можно пройти).
function Detailer.bush(parent: Instance, cf: CFrame, rng: Random, k: number?)
	local leafColor = Config.LeafColors[rng:NextInteger(1, #Config.LeafColors)]
	return plant(parent, "Bush", Assets.Bush[rng:NextInteger(1, #Assets.Bush)], cf * yaw(rng:NextNumber(0, 360)), k or rng:NextNumber(0.8, 1.2), leafColor, rng)
end

-- Фонарь: base — точка на земле, свет вылетает по armDir (1 = +Z локально, -1 = -Z).
function Detailer.streetLamp(parent: Instance, base: CFrame, armDir: number)
	return streetLamp(parent, base, armDir)
end

return Detailer
