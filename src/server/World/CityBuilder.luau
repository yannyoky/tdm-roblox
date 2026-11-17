-- Сборка открытого города (карта с полем City = true в MapsData.json). Вызывается из MapBuilder.build.
--
-- Что строится (настройки — src/shared/Config/City.luau, геометрия сетки — src/shared/CityGrid.luau):
--   * улицы по сетке: 2 полосы в каждую сторону, двойная сплошная, прерывистая между полосами,
--     стоп-линии и «зебры» у каждого перекрёстка;
--   * перекрёстки со светофорами (переключает World/TrafficLights.luau) и пешеходными светофорами,
--     таблички с названиями улиц;
--   * кварталы: тротуар с бордюром, фонари, деревья, урны, гидранты, остановки, киоски;
--   * виды кварталов: высотки, магазины, жилые дворы, заправки, парковки, парки, базы сторон.
--
-- Что получают другие системы (папка Map/City):
--   Intersections/I_<i>_<j>  -- модель перекрёстка: атрибуты I, J, Signalized, NS, EW ("G"|"Y"|"R"),
--                               внутри лампы светофоров (Lamp: Axis, Color) и пешеходные (PedLamp: Axis, Kind)
--   ParkingSpots/<Part>      -- места на парковках (нос машины смотрит по LookVector)
--   SitPoints/<Part>         -- где можно сесть (скамейки), тег "SitPoint"
--   FuelPumps/<Part>         -- колонки на заправках, тег "FuelPump"
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.City)
local CityGrid = require(Shared.CityGrid)
local Props = require(script.Parent.Props)
local Detailer = require(script.Parent.Detailer)

local CityBuilder = {}
local optimize: (Instance) -> ()

local rgb = Color3.fromRGB
local part = Props.part

local N = Config.Blocks
local B = Config.BlockSize
local R = Config.RoadWidth
local SW = Config.SidewalkWidth
local CH = Config.CurbHeight
local IN = B / 2 - SW -- половина внутренней площадки квартала

local DIRS = CityGrid.Dirs
local SIDES = { "N", "S", "E", "W" }
-- Поворот элемента карты (MapBuilder: rot), при котором его сторона N смотрит на сторону квартала.
local SIDE_ROT = { N = 0, W = 90, S = 180, E = -90 }

local C = {
	sidewalk = rgb(162, 160, 154),
	curb = rgb(192, 190, 184),
	plaza = rgb(176, 172, 164),
	lotAsphalt = rgb(62, 64, 66),
	grass = rgb(88, 116, 62),
	path = rgb(188, 182, 170),
	white = rgb(230, 230, 224),
	yellow = rgb(224, 182, 52),
	pole = rgb(48, 51, 54),
	signalOff = rgb(26, 26, 28),
	concrete = rgb(168, 165, 158),
}

local STREETS_V = { "пр. Мира", "ул. Ленина", "ул. Гагарина", "ул. Пушкина", "ул. Кирова", "ул. Садовая", "ул. Лесная", "ул. Речная" }
local STREETS_H = { "ул. Советская", "ул. Набережная", "пр. Победы", "ул. Центральная", "ул. Молодёжная", "ул. Заводская", "ул. Новая", "ул. Школьная" }

local nightDetails: (geo: Instance, rng: Random) -> ()

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end

-- Тонкая разметка на асфальте (земля карты — асфальт на y = 0).
local function marking(parent: Instance, size: Vector2, cf: CFrame, color: Color3)
	part(parent, "Marking", Vector3.new(size.X, 0.04, size.Y), cf * CFrame.new(0, 0.03, 0), color, Enum.Material.SmoothPlastic, false, { CastShadow = false })
end

-- Пандус: низ в center (на земле), поднимается по riseDir на h за len.
local function ramp(parent: Instance, center: Vector3, riseDir: Vector3, w: number, h: number, len: number, color: Color3, mat: Enum.Material)
	local c = center + Vector3.new(0, h / 2, 0)
	local p = Instance.new("WedgePart")
	p.Name = "CurbRamp"
	p.Size = Vector3.new(w, h, len)
	p.CFrame = CFrame.lookAt(c, c - riseDir)
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Место, где можно сесть: невидимая точка на сиденье, лицом по LookVector.
-- Невидимое сиденье (Seat). Само по касанию не сажает (CanTouch = false): садятся по кнопке E,
-- её добавляет World/Seats.luau.
local function sitPoint(ctx, cf: CFrame)
	local p = Instance.new("Seat")
	p.Name = "SitPoint"
	p.Size = Vector3.new(1.6, 0.2, 1.4)
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Parent = ctx.sitPoints
	CollectionService:AddTag(p, "SitPoint")
	return p
end

local function bench(ctx, parent: Instance, cf: CFrame)
	Props.bench(parent, cf)
	sitPoint(ctx, cf * CFrame.new(0, 2.1, 0))
end

local function parkingSpot(ctx, cf: CFrame)
	local p = part(ctx.parking, "Spot", Vector3.new(8, 0.2, 17), cf * CFrame.new(0, CH + 0.1, 0), C.white, Enum.Material.SmoothPlastic, false, { Transparency = 1 })
	return p
end

------------------------------------------------------------------------
-- Улицы: разметка на отрезках между перекрёстками

local function roadSegment(parent: Instance, center: Vector3, along: Vector3)
	local cf = CFrame.lookAt(center, center + along) -- -Z локально = along, +X = вправо от along
	local L = B
	local stopAt = L / 2 - 11.5 -- до сюда тянутся линии (дальше стоп-линия и зебра)
	local lineLen = stopAt * 2
	-- Двойная сплошная.
	for _, x in { -0.55, 0.55 } do
		marking(parent, Vector2.new(0.3, lineLen), cf * CFrame.new(x, 0, 0), C.yellow)
	end
	-- Края проезжей части.
	for _, x in { -(R / 2 - 1.4), R / 2 - 1.4 } do
		marking(parent, Vector2.new(0.35, lineLen), cf * CFrame.new(x, 0, 0), C.white)
	end
	-- Прерывистая между полосами.
	local laneX = Config.Median / 2 + Config.LaneWidth
	for _, x in { -laneX, laneX } do
		local z = -stopAt + 4
		while z + 8 <= stopAt - 2 do
			marking(parent, Vector2.new(0.3, 8), cf * CFrame.new(x, 0, z + 4), C.white)
			z += 20
		end
	end
	-- Стоп-линии: к дальнему концу (-Z) едут полосы справа (+X), к ближнему — слева.
	local half = R / 2 - 1.2 - Config.Median / 2
	marking(parent, Vector2.new(half, 1), cf * CFrame.new(Config.Median / 2 + half / 2, 0, -(L / 2 - 10.5)), C.white)
	marking(parent, Vector2.new(half, 1), cf * CFrame.new(-(Config.Median / 2 + half / 2), 0, L / 2 - 10.5), C.white)
	-- Пешеходные переходы на обоих концах.
	for _, sgn in { -1, 1 } do
		local z = sgn * (L / 2 - 5.5)
		local x = -R / 2 + 3
		while x <= R / 2 - 3 do
			marking(parent, Vector2.new(2.2, 8), cf * CFrame.new(x, 0, z), C.white)
			x += 4.4
		end
	end
end

------------------------------------------------------------------------
-- Перекрёстки и светофоры

local LAMP_COLORS = { R = rgb(255, 40, 30), Y = rgb(255, 170, 20), G = rgb(40, 255, 110) }

local function signalHead(model: Model, cf: CFrame, axis: string)
	part(model, "SignalHead", Vector3.new(1.5, 4.4, 1.1), cf, C.pole, Enum.Material.Metal, true)
	part(model, "SignalBackplate", Vector3.new(2.6, 5.4, 0.12), cf * CFrame.new(0, 0, 0.62), rgb(20, 20, 22), Enum.Material.SmoothPlastic)
	for i, color in { "R", "Y", "G" } do
		local y = (2 - i) * 1.35
		local lamp = Props.disc(model, "Lamp", cf * CFrame.new(0, y, -0.57), 1.05, 0.12, C.signalOff, Enum.Material.SmoothPlastic)
		lamp:SetAttribute("Axis", axis)
		lamp:SetAttribute("Color", color)
		lamp:SetAttribute("On", LAMP_COLORS[color])
		part(model, "SignalVisor", Vector3.new(1.3, 0.1, 0.7), cf * CFrame.new(0, y + 0.62, -0.9), C.pole, Enum.Material.Metal)
	end
end

local function pedHead(model: Model, cf: CFrame, axis: string)
	part(model, "PedSignal", Vector3.new(1.3, 2.6, 0.9), cf, C.pole, Enum.Material.Metal)
	for i, kind in { "Stop", "Walk" } do
		local lamp = part(model, "PedLamp", Vector3.new(0.95, 0.95, 0.08), cf * CFrame.new(0, (1.5 - i) * 1.15, -0.47), C.signalOff, Enum.Material.SmoothPlastic)
		lamp:SetAttribute("Axis", axis)
		lamp:SetAttribute("Kind", kind)
		lamp:SetAttribute("On", if kind == "Walk" then rgb(235, 245, 255) else rgb(255, 90, 30))
	end
end

local function buildIntersection(parent: Instance, i: number, j: number)
	local c = CityGrid.intersection(i, j)
	local legs = CityGrid.legs(i, j)
	local count = 0
	for _, on in legs do
		if on then
			count += 1
		end
	end
	local model = Instance.new("Model")
	model.Name = string.format("I_%d_%d", i, j)
	local center = part(model, "Center", Vector3.new(R, 0.2, R), CFrame.new(c.X, 0.1, c.Z), C.white, Enum.Material.SmoothPlastic, false, { Transparency = 1 })
	model.PrimaryPart = center
	model:SetAttribute("I", i)
	model:SetAttribute("J", j)
	model:SetAttribute("Signalized", count >= 3)
	if count >= 3 then -- на углах города светофоров нет: там нет и сигнала
		model:SetAttribute("NS", "G")
		model:SetAttribute("EW", "R")
	end
	for _, s in SIDES do
		model:SetAttribute("Leg" .. s, legs[s])
	end

	if count >= 3 then
		local off = R / 2 + 3.5
		for leg, on in legs do
			if not on then
				continue
			end
			local d = -DIRS[leg] -- машины с этой улицы едут к перекрёстку в направлении d
			local right = CityGrid.right(d)
			local axis = CityGrid.axis(d)
			local base = c - d * off + right * off
			Props.post(model, "SignalPole", CFrame.new(base.X, CH, base.Z), 19, 0.9, C.pole, Enum.Material.Metal, true)
			local armY = CH + 17.6
			Props.rod(model, "SignalArm", Vector3.new(base.X, armY, base.Z), Vector3.new(base.X, armY, base.Z) - right * (off - 1), 0.5, C.pole, Enum.Material.Metal)
			for lane = 1, Config.LanesPerDirection do
				local p = c - d * off + right * CityGrid.laneOffset(lane) + Vector3.new(0, CH + 15.3, 0)
				signalHead(model, CFrame.lookAt(p, p - d), axis)
			end
			-- Пешеходный светофор смотрит через улицу (на тех, кто переходит дорогу этой оси).
			local pp = base + Vector3.new(0, CH + 8.5, 0) - right * 0.8
			pedHead(model, CFrame.lookAt(pp, pp - right), axis)
			-- Название поперечной улицы.
			local name = if axis == "NS" then STREETS_H[j + 1] else STREETS_V[i + 1]
			local sp = base + Vector3.new(0, CH + 12.5, 0) - right * 2.6
			local s = Props.sign(model, CFrame.lookAt(sp, sp - d), 4.6, 0.9, name or "", rgb(30, 90, 60), rgb(255, 255, 255), Enum.Font.GothamBold)
			s.Name = "StreetName"
		end
	end
	model.Parent = parent
	return model
end

------------------------------------------------------------------------
-- Кварталы

-- Точка на тротуаре стороны side квартала: u — вдоль стороны (вправо от взгляда наружу), off — от края бордюра внутрь.
local function edgePoint(bc: Vector3, side: string, u: number, off: number): Vector3
	local o = DIRS[side]
	local t = CityGrid.right(o)
	return Vector3.new(bc.X, CH, bc.Z) + o * (B / 2 - off) + t * u
end

-- Въезд с улицы во двор: пандус через бордюр, мебель тротуара здесь не ставится.
local function driveway(ctx, bc: Vector3, side: string, u: number, w: number)
	table.insert(ctx.skips, { bc = bc, side = side, u = u, w = w })
	local o = DIRS[side]
	local p = edgePoint(bc, side, u, 0) + o * 1.5
	ramp(ctx.geo, Vector3.new(p.X, 0, p.Z), -o, w, CH, 3, C.curb, Enum.Material.Concrete)
end

local function skipped(ctx, bc: Vector3, side: string, u: number, r: number): boolean
	for _, s in ctx.skips do
		if s.bc == bc and s.side == side and math.abs(s.u - u) < s.w / 2 + r then
			return true
		end
	end
	return false
end

-- Тротуар, бордюр и площадка квартала. lotMat/lotColor — покрытие внутренней площадки.
local function blockBase(ctx, bc: Vector3, lotMat: Enum.Material, lotColor: Color3, lotTop: number?)
	local g = ctx.geo
	local y = CH / 2
	part(g, "Sidewalk", Vector3.new(B, CH, SW), CFrame.new(bc.X, y, bc.Z - B / 2 + SW / 2), C.sidewalk, Enum.Material.Pavement, true)
	part(g, "Sidewalk", Vector3.new(B, CH, SW), CFrame.new(bc.X, y, bc.Z + B / 2 - SW / 2), C.sidewalk, Enum.Material.Pavement, true)
	part(g, "Sidewalk", Vector3.new(SW, CH, B - 2 * SW), CFrame.new(bc.X - B / 2 + SW / 2, y, bc.Z), C.sidewalk, Enum.Material.Pavement, true)
	part(g, "Sidewalk", Vector3.new(SW, CH, B - 2 * SW), CFrame.new(bc.X + B / 2 - SW / 2, y, bc.Z), C.sidewalk, Enum.Material.Pavement, true)
	local ch = CH + 0.03
	part(g, "Curb", Vector3.new(B, ch, 0.6), CFrame.new(bc.X, ch / 2, bc.Z - B / 2 + 0.3), C.curb, Enum.Material.Concrete, true)
	part(g, "Curb", Vector3.new(B, ch, 0.6), CFrame.new(bc.X, ch / 2, bc.Z + B / 2 - 0.3), C.curb, Enum.Material.Concrete, true)
	part(g, "Curb", Vector3.new(0.6, ch, B - 1.2), CFrame.new(bc.X - B / 2 + 0.3, ch / 2, bc.Z), C.curb, Enum.Material.Concrete, true)
	part(g, "Curb", Vector3.new(0.6, ch, B - 1.2), CFrame.new(bc.X + B / 2 - 0.3, ch / 2, bc.Z), C.curb, Enum.Material.Concrete, true)
	local top = lotTop or CH
	part(g, "Lot", Vector3.new(IN * 2, top, IN * 2), CFrame.new(bc.X, top / 2, bc.Z), lotColor, lotMat, true)
end

-- Мебель тротуаров по всем сторонам квартала: фонари, деревья, урны, гидранты, остановки, киоски, знаки.
local function sidewalkItems(ctx, bc: Vector3, kind: string, rng: Random)
	local parent = ctx.street
	for _, side in SIDES do
		local o = DIRS[side]
		local function at(u: number, off: number): CFrame
			local p = edgePoint(bc, side, u, off)
			return CFrame.lookAt(p, p + o) -- лицом к дороге
		end
		-- Фонари у бордюра, свет над дорогой.
		for _, u in { -60, -20, 20, 60 } do
			if not skipped(ctx, bc, side, u, 1.5) then
				Detailer.streetLamp(parent, at(u, 1.4), -1)
			end
		end
		-- Деревья в лунках между фонарями (кроме деловых кварталов с витринами — там через раз).
		for n, u in { -40, 0, 40 } do
			if (kind ~= "downtown" or n ~= 2) and not skipped(ctx, bc, side, u, 3) then
				Detailer.tree(parent, at(u + rng:NextNumber(-2, 2), 4.2), rng)
			end
		end
		-- Урны у фонарей.
		for _, u in { -17, 23 } do
			if rng:NextNumber() < 0.6 and not skipped(ctx, bc, side, u, 1.5) then
				Props.bin(parent, at(u, 1.6), rng)
			end
		end
		-- Гидрант.
		if rng:NextNumber() < 0.5 and not skipped(ctx, bc, side, -52, 1.5) then
			Props.hydrant(parent, at(-52, 1.2))
		end
		-- Остановка или киоск.
		local roll = rng:NextNumber()
		if roll < 0.22 and not skipped(ctx, bc, side, 30, 7) then
			Props.busStop(parent, at(30, 5), rng)
		elseif roll < 0.4 and (kind == "downtown" or kind == "commercial" or kind == "park") and not skipped(ctx, bc, side, -30, 5) then
			Props.kiosk(parent, at(-30, 8.6), rng)
		end
		-- Знак у угла.
		if rng:NextNumber() < 0.35 and not skipped(ctx, bc, side, 70, 1) then
			Props.roadSign(parent, at(70, 1.2), Props.pick({ "speed", "noparking", "crossing", "mainroad" }, rng), rng)
		end
	end
end

-- Локальная система площадки квартала: -Z смотрит на сторону front.
local function lotFrame(bc: Vector3, front: string): CFrame
	return CFrame.new(bc.X, CH, bc.Z) * yaw(SIDE_ROT[front])
end

-- Сторона квартала, смотрящая к центру города.
local function sideToCenter(bc: Vector3): string
	if math.abs(bc.X) > math.abs(bc.Z) then
		return if bc.X > 0 then "W" else "E"
	end
	return if bc.Z > 0 then "N" else "S"
end

-- Элемент карты (MapBuilder): здание размером wx × wz по осям мира, сторона N элемента смотрит на side.
local function placeFacing(ctx, e, side: string, wx: number, wz: number)
	e.rot = SIDE_ROT[side]
	if side == "E" or side == "W" then
		e.w, e.d = wz, wx
	else
		e.w, e.d = wx, wz
	end
	ctx.place(e)
end

------------------------------------------------------------------------
-- Высотка: подиум с магазинами (обычный дом карты с витриной) и стеклянная башня с поясами этажей.

local function tower(ctx, cx: number, cz: number, wx: number, wz: number, h: number, front: string, rng: Random)
	local cfg = Config.Towers
	local podium = 10
	placeFacing(ctx, { k = "block", x = cx, z = cz, h = podium, shop = rng:NextInteger(1, 16), mat = "Concrete", color = { 150, 146, 140 } }, front, wx, wz)

	local m = Instance.new("Model")
	m.Name = "Tower"
	local glass = cfg.Glass[rng:NextInteger(1, #cfg.Glass)]
	local frame = cfg.Frame[rng:NextInteger(1, #cfg.Frame)]
	local bw, bd = wx - 6, wz - 6
	local bodyH = h - podium
	part(m, "TowerGlass", Vector3.new(bw, bodyH, bd), CFrame.new(cx, podium + bodyH / 2, cz), glass, Enum.Material.SmoothPlastic, true, { Reflectance = 0.22 })
	-- Пояса этажей.
	local fh = cfg.FloorHeight
	local y = podium + fh
	while y < h - 2 do
		part(m, "FloorBand", Vector3.new(bw + 0.5, 0.7, bd + 0.5), CFrame.new(cx, y, cz), frame, Enum.Material.Concrete)
		y += fh
	end
	-- Вертикальные импосты на всех гранях.
	for _, face in { { Vector3.new(0, 0, -1), bw, bd }, { Vector3.new(0, 0, 1), bw, bd }, { Vector3.new(1, 0, 0), bd, bw }, { Vector3.new(-1, 0, 0), bd, bw } } do
		local o, len, depth = face[1], face[2], face[3]
		local t = CityGrid.right(o)
		local n = math.max(2, math.floor(len / 8))
		for k = 1, n - 1 do
			local p = Vector3.new(cx, podium + bodyH / 2, cz) + o * (depth / 2 + 0.15) + t * (-len / 2 + k * len / n)
			part(m, "Mullion", Vector3.new(0.45, bodyH, 0.45), CFrame.new(p), frame, Enum.Material.Metal)
		end
		-- Угловые колонны.
		local corner = Vector3.new(cx, podium + bodyH / 2, cz) + o * (depth / 2) + t * (len / 2)
		part(m, "Corner", Vector3.new(1.2, bodyH, 1.2), CFrame.new(corner), frame, Enum.Material.Concrete)
	end
	-- Крыша: парапет, техэтаж, иногда антенна с красным огнём.
	part(m, "Parapet", Vector3.new(bw + 1, 2.2, bd + 1), CFrame.new(cx, h + 1.1, cz), frame, Enum.Material.Concrete, true)
	part(m, "Roof", Vector3.new(bw - 1, 0.3, bd - 1), CFrame.new(cx, h + 2.25, cz), rgb(80, 80, 82), Enum.Material.Concrete)
	part(m, "Plant", Vector3.new(bw * 0.4, 7, bd * 0.4), CFrame.new(cx + rng:NextNumber(-3, 3), h + 3.5, cz + rng:NextNumber(-3, 3)), rgb(140, 140, 138), Enum.Material.Metal, true)
	if rng:NextNumber() < 0.6 then
		local top = h + 7 + 18
		Props.post(m, "Antenna", CFrame.new(cx, h + 7, cz), 18, 0.5, rgb(170, 170, 172), Enum.Material.Metal)
		local beacon = part(m, "Beacon", Vector3.new(0.9, 0.9, 0.9), CFrame.new(cx, top + 0.4, cz), rgb(255, 30, 20), Enum.Material.Neon, false, { Shape = Enum.PartType.Ball })
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 40, 30)
		light.Range = 12
		light.Brightness = 2
		light.Parent = beacon
	end
	m.Parent = ctx.geo
end

local lots = {}

function lots.downtown(ctx, bc: Vector3, rng: Random)
	blockBase(ctx, bc, Enum.Material.Pavement, C.plaza)
	local cfg = Config.Towers
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local wx, wz = rng:NextInteger(50, 62), rng:NextInteger(50, 62)
			local cx = bc.X + sx * (IN - wx / 2 - 2)
			local cz = bc.Z + sz * (IN - wz / 2 - 2)
			local front = if rng:NextNumber() < 0.5 then (if sx > 0 then "E" else "W") else (if sz > 0 then "S" else "N")
			tower(ctx, cx, cz, wx, wz, rng:NextInteger(cfg.Height[1], cfg.Height[2]), front, rng)
		end
	end
	-- Площадь между башнями: клумбы, деревья, скамейки.
	local parent = ctx.street
	Detailer.bigTree(parent, CFrame.new(bc.X, CH, bc.Z), rng, 0.55)
	for _, p in { Vector3.new(14, 0, 0), Vector3.new(-14, 0, 0), Vector3.new(0, 0, 14), Vector3.new(0, 0, -14) } do
		local cf = CFrame.lookAt(Vector3.new(bc.X, CH, bc.Z) + p, Vector3.new(bc.X, CH, bc.Z) + p * 2)
		bench(ctx, parent, cf)
		Props.planter(parent, cf * CFrame.new(5, 0, 0), rng)
	end
end

function lots.commercial(ctx, bc: Vector3, rng: Random)
	blockBase(ctx, bc, Enum.Material.Concrete, C.concrete)
	local gateSide = SIDES[rng:NextInteger(1, 4)]
	for _, side in SIDES do
		local o = DIRS[side]
		local t = CityGrid.right(o)
		local corner = if side == "N" or side == "S" then 0 else 20
		local u = -IN + corner
		local uMax = IN - corner
		while u < uMax - 12 do
			if side == gateSide and u > -10 and u < 10 then
				u = 10
			end
			local w = math.min(rng:NextInteger(18, 28), uMax - u)
			if side == gateSide and u < -10 and u + w > -10 then
				w = -10 - u
			end
			if w < 10 then
				u += w + 1.5
				continue
			end
			local d = rng:NextInteger(14, 18)
			local center = Vector3.new(bc.X, 0, bc.Z) + o * (IN - d / 2) + t * (u + w / 2)
			local twoFloors = rng:NextNumber() < 0.3
			local wx = if side == "N" or side == "S" then w else d
			local wz = if side == "N" or side == "S" then d else w
			placeFacing(ctx, {
				k = "block",
				x = center.X,
				z = center.Z,
				h = if twoFloors then 17 else rng:NextInteger(9, 10),
				shop = rng:NextInteger(1, 16),
				mat = if rng:NextNumber() < 0.5 then "Brick" else "Concrete",
				access = { "S", "ladder" },
			}, side, wx, wz)
			u += w + 1.5
		end
	end
	driveway(ctx, bc, gateSide, 0, 18)
	-- Двор: служебная парковка и мусорные баки.
	local lf = lotFrame(bc, gateSide)
	for k = -2, 2 do
		local cf = lf * CFrame.new(k * 11, 0, 8)
		marking(ctx.geo, Vector2.new(0.3, 17), cf * CFrame.new(5.5, 0, 0), C.white)
		parkingSpot(ctx, cf * CFrame.new(0, -CH, 0) * yaw(180))
	end
	Props.dumpster(ctx.street, lf * CFrame.new(-30, 0, 36), rng)
	Props.dumpster(ctx.street, lf * CFrame.new(30, 0, 36), rng)
	Props.trashbags(ctx.street, lf * CFrame.new(-22, 0, 37), rng)
end

function lots.residential(ctx, bc: Vector3, rng: Random)
	blockBase(ctx, bc, Enum.Material.Pavement, C.plaza)
	local parent = ctx.street
	-- Газоны во дворе.
	part(ctx.geo, "Lawn", Vector3.new(IN * 2 - 50, 0.1, 50), CFrame.new(bc.X, CH + 0.05, bc.Z), C.grass, Enum.Material.Grass, true)
	-- Панельки вдоль северной и южной сторон, лицом на улицу.
	for _, side in { "N", "S" } do
		local w = rng:NextInteger(104, 128)
		local d = 15
		local center = Vector3.new(bc.X, 0, bc.Z) + DIRS[side] * (IN - d / 2 - 1)
		placeFacing(ctx, { k = "block", x = center.X, z = center.Z, h = rng:NextInteger(3, 4) * 9 - 1, mat = "Concrete", access = { "E", "ladder" } }, side, w, d)
	end
	-- Дом поменьше на восточной или западной стороне.
	local side = if rng:NextNumber() < 0.5 then "E" else "W"
	local center = Vector3.new(bc.X, 0, bc.Z) + DIRS[side] * (IN - 9)
	placeFacing(ctx, { k = "block", x = center.X, z = center.Z, h = 26, mat = "Brick", access = { "W", "ladder" } }, side, 16, 46)
	-- Двор: деревья, скамейки, баскетбольное кольцо, контейнерная площадка, бельё.
	for _ = 1, 7 do
		local p = Vector3.new(bc.X + rng:NextNumber(-48, 48), CH, bc.Z + rng:NextNumber(-20, 20))
		if math.abs(p.X - bc.X) > 12 then
			Detailer.bigTree(parent, CFrame.new(p), rng, rng:NextNumber(0.4, 0.6))
		end
	end
	for _, x in { -26, -12, 12, 26 } do
		bench(ctx, parent, CFrame.lookAt(Vector3.new(bc.X + x, CH, bc.Z + 28), Vector3.new(bc.X + x, CH, bc.Z)))
	end
	Props.hoop(parent, CFrame.lookAt(Vector3.new(bc.X - 2, CH, bc.Z - 30), Vector3.new(bc.X - 2, CH, bc.Z)))
	Props.binArea(parent, CFrame.lookAt(Vector3.new(bc.X + 52, CH, bc.Z - 32), Vector3.new(bc.X + 52, CH, bc.Z)), rng)
	Props.clothesline(parent, Vector3.new(bc.X - 46, CH, bc.Z - 10), Vector3.new(bc.X - 30, CH, bc.Z - 10), rng)
	for _ = 1, 4 do
		Detailer.bush(parent, CFrame.new(bc.X + rng:NextNumber(-55, 55), CH, bc.Z + rng:NextNumber(-22, 22)), rng)
	end
	-- Места для машин жильцов вдоль газона.
	for k = -3, 3 do
		local cf = CFrame.new(bc.X + k * 11, CH, bc.Z - 30) * yaw(if k % 2 == 0 then 0 else 180)
		if math.abs(k) >= 2 then
			parkingSpot(ctx, cf * CFrame.new(0, -CH, 0))
		end
	end
	driveway(ctx, bc, side == "E" and "W" or "E", 0, 16)
end

function lots.gas(ctx, bc: Vector3, rng: Random)
	blockBase(ctx, bc, Enum.Material.Asphalt, C.lotAsphalt)
	local front = sideToCenter(bc)
	local lf = lotFrame(bc, front)
	local g = Instance.new("Model")
	g.Name = "GasStation"
	-- Навес на шести колоннах, подсветка снизу.
	local roofY = 15
	for _, x in { -22, 0, 22 } do
		for _, z in { -32, -12 } do
			part(g, "CanopyPost", Vector3.new(1.4, roofY, 1.4), lf * CFrame.new(x, roofY / 2, z), rgb(225, 225, 222), Enum.Material.Metal, true)
		end
	end
	part(g, "CanopyRoof", Vector3.new(60, 1.6, 32), lf * CFrame.new(0, roofY + 0.8, -22), rgb(232, 232, 228), Enum.Material.Metal, true)
	part(g, "CanopyFascia", Vector3.new(60.4, 1.6, 32.4), lf * CFrame.new(0, roofY + 2.1, -22), rgb(200, 40, 40), Enum.Material.SmoothPlastic)
	local fasciaText = part(g, "CanopyText", Vector3.new(30, 1.4, 0.05), lf * CFrame.new(0, roofY + 2.1, -38.25), rgb(200, 40, 40), Enum.Material.SmoothPlastic, false, { Transparency = 1 })
	Props.label(fasciaText, "ТОПЛИВО  •  КОФЕ  •  24/7", rgb(255, 255, 255), Enum.Font.GothamBlack)
	for _, x in { -18, 0, 18 } do
		for _, z in { -30, -14 } do
			local panel = part(g, "CanopyLight", Vector3.new(4, 0.1, 2), lf * CFrame.new(x, roofY - 0.05, z), rgb(255, 250, 235), Enum.Material.Glass)
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Bottom
			light.Angle = 120
			light.Range = 24
			light.Brightness = 2.5
			light.Color = rgb(245, 245, 255)
			light.Shadows = false
			light.Enabled = false
			light.Parent = panel
			CollectionService:AddTag(panel, "StreetLamp")
		end
	end
	-- Островки с колонками.
	for _, x in { -11, 11 } do
		part(g, "PumpIsland", Vector3.new(4, 0.6, 22), lf * CFrame.new(x, 0.3, -22), C.concrete, Enum.Material.Concrete, true)
		for _, z in { -28, -16 } do
			local base = lf * CFrame.new(x, 0.6, z)
			local pump = part(g, "FuelPump", Vector3.new(2.6, 5.6, 1.6), base * CFrame.new(0, 2.8, 0), rgb(235, 235, 232), Enum.Material.SmoothPlastic, true)
			part(g, "PumpTop", Vector3.new(2.8, 0.9, 1.8), base * CFrame.new(0, 5.9, 0), rgb(200, 40, 40), Enum.Material.SmoothPlastic)
			for _, sgn in { -1, 1 } do
				local screen = part(g, "PumpScreen", Vector3.new(1.8, 1.2, 0.05), base * CFrame.new(0, 4.2, sgn * 0.83), rgb(20, 24, 22), Enum.Material.SmoothPlastic)
				Props.label(screen, "АИ-95\n57.90", rgb(120, 255, 140), Enum.Font.Code, if sgn < 0 then Enum.NormalId.Front else Enum.NormalId.Back)
				Props.rod(g, "PumpHose", (base * CFrame.new(sgn * 1.4, 3.6, 0)).Position, (base * CFrame.new(sgn * 1.6, 1.2, 0)).Position, 0.25, rgb(25, 25, 25), Enum.Material.Rubber)
			end
			CollectionService:AddTag(pump, "FuelPump")
			pump.Parent = ctx.pumps
		end
	end
	-- Магазин при заправке.
	local store = lf * CFrame.new(0, 0, 50)
	local sp = store.Position
	placeFacing(ctx, { k = "block", x = sp.X, z = sp.Z, h = 10, shop = 11, mat = "Concrete", color = { 210, 208, 200 }, access = { "S", "ladder" } }, front, if front == "N" or front == "S" then 52 else 20, if front == "N" or front == "S" then 20 else 52)
	-- Стела с ценами.
	local pylon = lf * CFrame.new(62, 0, -66)
	part(g, "PylonPost", Vector3.new(1.6, 12, 1.6), pylon * CFrame.new(0, 6, 0), rgb(70, 72, 76), Enum.Material.Metal, true)
	local board = part(g, "PylonBoard", Vector3.new(8, 10, 1), pylon * CFrame.new(0, 15, 0), rgb(200, 40, 40), Enum.Material.SmoothPlastic, true)
	Props.label(board, "АЗС\nАИ-92  52.40\nАИ-95  57.90\nДТ  66.10", rgb(255, 255, 255), Enum.Font.GothamBlack, Enum.NormalId.Front)
	Props.label(board, "АЗС\nАИ-92  52.40\nАИ-95  57.90\nДТ  66.10", rgb(255, 255, 255), Enum.Font.GothamBlack, Enum.NormalId.Back)
	Props.bin(g, lf * CFrame.new(-26, 0, -4), rng)
	Props.bin(g, lf * CFrame.new(26, 0, -4), rng)
	-- Места у магазина.
	for k = -2, 2 do
		local cf = lf * CFrame.new(k * 10, -CH, 30) * yaw(180)
		marking(ctx.geo, Vector2.new(0.3, 16), lf * CFrame.new(k * 10 + 5, 0, 30), C.white)
		parkingSpot(ctx, cf)
	end
	g.Parent = ctx.geo
	driveway(ctx, bc, front, -44, 20)
	driveway(ctx, bc, front, 44, 20)
end

function lots.parking(ctx, bc: Vector3, rng: Random)
	blockBase(ctx, bc, Enum.Material.Asphalt, C.lotAsphalt)
	local front = sideToCenter(bc)
	local lf = lotFrame(bc, front)
	-- Ряды мест: одинарный у въезда, двойной посередине, одинарный сзади. Между ними проезды.
	local rows = { { z = -56, nose = 1 }, { z = -11, nose = -1 }, { z = 8, nose = 1 }, { z = 54, nose = -1 } }
	for _, row in rows do
		for k = -7, 6 do
			local x = k * 10 + 5
			if row.z < -40 and math.abs(x) < 14 then
				continue -- проезд с улицы
			end
			marking(ctx.geo, Vector2.new(0.3, 18), lf * CFrame.new(x - 5, 0, row.z), C.white)
			if k == 6 then
				marking(ctx.geo, Vector2.new(0.3, 18), lf * CFrame.new(x + 5, 0, row.z), C.white)
			end
			-- Нос машины к проезду.
			parkingSpot(ctx, lf * CFrame.new(x, -CH, row.z) * yaw(if row.nose > 0 then 180 else 0))
		end
	end
	-- Стрелки движения на проездах.
	for _, z in { -33, 31 } do
		marking(ctx.geo, Vector2.new(1, 8), lf * CFrame.new(-30, 0, z) * yaw(90), C.white)
		marking(ctx.geo, Vector2.new(1, 8), lf * CFrame.new(30, 0, z) * yaw(90), C.white)
	end
	-- Фонари по осевой двойного ряда.
	for _, x in { -48, 0, 48 } do
		local p = lf * CFrame.new(x, 0, -1.5)
		part(ctx.geo, "ParkingCurb", Vector3.new(12, 0.5, 2), p * CFrame.new(0, 0.25, 0), C.concrete, Enum.Material.Concrete, true)
		Detailer.streetLamp(ctx.street, p, 1)
	end
	-- Будка охраны и шлагбаум у въезда.
	local booth = lf * CFrame.new(18, 0, -68)
	part(ctx.geo, "Booth", Vector3.new(5, 8, 5), booth * CFrame.new(0, 4, 0), rgb(220, 218, 210), Enum.Material.SmoothPlastic, true)
	part(ctx.geo, "BoothWindow", Vector3.new(4, 2.5, 0.1), booth * CFrame.new(0, 5, -2.55), rgb(60, 80, 95), Enum.Material.Glass, false, { Reflectance = 0.2 })
	part(ctx.geo, "BoothRoof", Vector3.new(6, 0.4, 6), booth * CFrame.new(0, 8.2, 0), rgb(60, 62, 66), Enum.Material.Metal)
	local s = Props.sign(ctx.geo, lf * CFrame.new(-18, 9, -70), 9, 2, "P  ПАРКОВКА", rgb(30, 80, 170), rgb(255, 255, 255), Enum.Font.GothamBlack, true)
	s.Name = "ParkingSign"
	Props.post(ctx.geo, "SignPole", lf * CFrame.new(-18, 0, -69.6), 8, 0.4, rgb(150, 152, 155), Enum.Material.Metal, true)
	driveway(ctx, bc, front, 0, 24)
end

function lots.park(ctx, bc: Vector3, rng: Random)
	blockBase(ctx, bc, Enum.Material.Grass, C.grass)
	local parent = ctx.street
	local c = Vector3.new(bc.X, CH, bc.Z)
	local layer = 0
	local function path(a: Vector3, b: Vector3, w: number)
		layer += 1
		local mid = (a + b) / 2
		part(ctx.geo, "Path", Vector3.new(w, 0.1, (b - a).Magnitude), CFrame.lookAt(mid, b) * CFrame.new(0, 0.05 + layer * 0.006, 0), C.path, Enum.Material.Pavement, true)
	end
	-- Дорожки: крест от середин сторон, диагонали от углов, кольцо вокруг фонтана.
	for _, side in SIDES do
		path(c + DIRS[side] * IN, c + DIRS[side] * 22, 8)
	end
	for _, d in { Vector3.new(1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) } do
		path(c + d * (IN - 2), c + d.Unit * 24, 6)
	end
	local ringR = 24
	for k = 0, 11 do
		local a1, a2 = k / 12 * math.pi * 2, (k + 1) / 12 * math.pi * 2
		local p1 = c + Vector3.new(math.cos(a1), 0, math.sin(a1)) * ringR
		local p2 = c + Vector3.new(math.cos(a2), 0, math.sin(a2)) * ringR
		path(p1, p2 + (p2 - p1).Unit * 1.5, 7)
	end
	-- Фонтан.
	local f = Instance.new("Model")
	f.Name = "Fountain"
	-- Чаша: дно и кольцевой бортик из сегментов (внутри видно воду).
	Props.post(f, "FountainFloor", CFrame.new(c), 0.6, 25, C.concrete, Enum.Material.Concrete, true)
	for k = 0, 15 do
		local a = (k + 0.5) / 16 * math.pi * 2
		local p = c + Vector3.new(math.cos(a), 0, math.sin(a)) * 12.4
		part(f, "FountainRim", Vector3.new(5.2, 2, 1.3), CFrame.lookAt(p, c) * CFrame.new(0, 1, 0), C.concrete, Enum.Material.Concrete, true)
	end
	Props.post(f, "FountainWater", CFrame.new(c + Vector3.new(0, 0.6, 0)), 0.9, 24, rgb(58, 96, 112), Enum.Material.SmoothPlastic)
	local water = f:FindFirstChild("FountainWater") :: BasePart
	water.Transparency = 0.15
	water.Reflectance = 0.35
	Props.post(f, "FountainColumn", CFrame.new(c), 5.5, 3.5, C.concrete, Enum.Material.Concrete, true)
	Props.post(f, "FountainBowl", CFrame.new(c + Vector3.new(0, 5.5, 0)), 0.9, 10, C.concrete, Enum.Material.Concrete)
	local spout = part(f, "Spout", Vector3.new(0.6, 0.6, 0.6), CFrame.new(c + Vector3.new(0, 7, 0)), C.concrete, Enum.Material.Concrete)
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Color = ColorSequence.new(rgb(210, 230, 245))
	spray.LightEmission = 0.2
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.7) })
	spray.Speed = NumberRange.new(13, 16)
	spray.SpreadAngle = Vector2.new(14, 14)
	spray.Acceleration = Vector3.new(0, -32, 0)
	spray.Lifetime = NumberRange.new(0.9, 1.1)
	spray.Rate = 80
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = spout
	f.Parent = ctx.geo
	-- Скамейки вокруг фонтана лицом к нему.
	for k = 0, 7 do
		local a = (k + 0.5) / 8 * math.pi * 2
		local p = c + Vector3.new(math.cos(a), 0, math.sin(a)) * (ringR + 6)
		bench(ctx, parent, CFrame.lookAt(p, c))
	end
	-- Фонари на кольце.
	-- Фонари за скамейками, между дорожками (дорожки идут по осям и диагоналям).
	for k = 0, 3 do
		local a = (k + 0.25) / 4 * math.pi * 2
		local p = c + Vector3.new(math.cos(a), 0, math.sin(a)) * (ringR + 11)
		Detailer.streetLamp(parent, CFrame.lookAt(p, c), -1)
	end
	-- Входы в парк с середины сторон: на тротуаре напротив ничего не ставим.
	for _, side in SIDES do
		table.insert(ctx.skips, { bc = bc, side = side, u = 0, w = 10 })
	end
	-- Деревья и кусты подальше от дорожек.
	local function nearPath(p: Vector3): boolean
		local rel = p - c
		if rel.Magnitude < ringR + 10 then
			return true
		end
		if math.abs(rel.X) < 7 or math.abs(rel.Z) < 7 then
			return true
		end
		if math.abs(math.abs(rel.X) - math.abs(rel.Z)) < 7 then
			return true
		end
		return false
	end
	local placed = 0
	for _ = 1, 80 do
		if placed >= 20 then
			break
		end
		local p = c + Vector3.new(rng:NextNumber(-IN + 6, IN - 6), 0, rng:NextNumber(-IN + 6, IN - 6))
		if not nearPath(p) then
			if rng:NextNumber() < 0.7 then
				Detailer.bigTree(parent, CFrame.new(p), rng, rng:NextNumber(0.5, 0.8))
			else
				Detailer.bush(parent, CFrame.new(p), rng, rng:NextNumber(1, 1.6))
			end
			placed += 1
		end
	end
	-- Живая изгородь по краю с проходами для дорожек.
	for _, side in SIDES do
		local o = DIRS[side]
		local t = CityGrid.right(o)
		for _, seg in { { -IN + 9, -8 }, { 8, IN - 9 } } do
			local u = (seg[1] + seg[2]) / 2
			local len = seg[2] - seg[1]
			local p = c + o * (IN - 1.5) + t * u
			Props.hedge(parent, CFrame.lookAt(p, p + o) * yaw(0), len, rng)
		end
	end
end

-- База стороны в квартале: ворота смотрят на улицу Config.BaseGate.
local function baseLot(ctx, bc: Vector3, teamKey: string, rng: Random)
	blockBase(ctx, bc, Enum.Material.Pavement, C.plaza, CH - 0.1)
	local gate = Config.BaseGate[teamKey] or sideToCenter(bc)
	local dir = DIRS[gate]
	local pos = Vector3.new(bc.X, 0, bc.Z) + dir * (IN - 42 - 3)
	ctx.buildBase(teamKey, pos, dir)
	driveway(ctx, bc, gate, 0, 46)
	-- Деревья за стенами базы.
	for _ = 1, 6 do
		local p = Vector3.new(bc.X, CH, bc.Z) - dir * (IN - 6) + CityGrid.right(dir) * rng:NextNumber(-IN + 8, IN - 8)
		Detailer.bigTree(ctx.street, CFrame.new(p), rng, rng:NextNumber(0.45, 0.6))
	end
end

------------------------------------------------------------------------
-- Зелёная полоса за внешней улицей до края карты

local function outskirts(ctx, rng: Random)
	local H = CityGrid.Half
	local M = Config.Margin
	local S = CityGrid.Size
	local g = ctx.geo
	for _, s in {
		{ Vector3.new(S, CH, M), Vector3.new(0, CH / 2, -H - M / 2) },
		{ Vector3.new(S, CH, M), Vector3.new(0, CH / 2, H + M / 2) },
		{ Vector3.new(M, CH, CityGrid.Total), Vector3.new(-H - M / 2, CH / 2, 0) },
		{ Vector3.new(M, CH, CityGrid.Total), Vector3.new(H + M / 2, CH / 2, 0) },
	} do
		part(g, "Verge", s[1], CFrame.new(s[2]), C.grass, Enum.Material.Grass, true)
	end
	-- Бетонный забор у края и деревья вдоль улицы.
	local wallOff = H + M - 3
	for _, s in {
		{ Vector3.new(S - 6, 9, 1.4), Vector3.new(0, 4.5, -wallOff) },
		{ Vector3.new(S - 6, 9, 1.4), Vector3.new(0, 4.5, wallOff) },
		{ Vector3.new(1.4, 9, S - 6), Vector3.new(-wallOff, 4.5, 0) },
		{ Vector3.new(1.4, 9, S - 6), Vector3.new(wallOff, 4.5, 0) },
	} do
		part(g, "OuterWall", s[1], CFrame.new(s[2]), rgb(150, 146, 138), Enum.Material.Concrete, true)
	end
	for _, side in SIDES do
		local o = DIRS[side]
		local t = CityGrid.right(o)
		local u = -H + 10
		while u < H - 10 do
			local p = o * (H + 10 + rng:NextNumber(0, M - 26)) + t * u + Vector3.new(0, CH, 0)
			Detailer.bigTree(ctx.street, CFrame.new(p), rng, rng:NextNumber(0.5, 0.75))
			u += rng:NextNumber(22, 34)
		end
		-- Фонари вдоль внешней улицы.
		u = -H + 30
		while u < H - 30 do
			local p = o * (H + 1.5) + t * u + Vector3.new(0, CH, 0)
			Detailer.streetLamp(ctx.street, CFrame.lookAt(p, p - o), -1)
			u += 60
		end
	end
end

------------------------------------------------------------------------
-- Ночь: окна, которые загораются (тег NightWindow, включает World/Environment), и яркие фонари.

local function nightWindow(p: BasePart)
	CollectionService:AddTag(p, "NightWindow")
end

nightDetails = function(geo: Instance, rng: Random)
	local dn = Config.DayNight
	for _, inst in geo:GetDescendants() do
		if inst:IsA("BasePart") then
			if inst.Name == "WindowGlass" and inst.Material ~= Enum.Material.Neon and rng:NextNumber() < dn.LitWindows then
				nightWindow(inst)
			elseif CollectionService:HasTag(inst, "StreetLamp") then
				local light = inst:FindFirstChildOfClass("SpotLight")
				if light then
					light.Range = dn.LampRange
					light.Brightness = dn.LampBrightness
					light.Angle = 150
				end
			end
		end
	end
	-- Высотки: полосы светящихся окон на части этажей.
	for _, tower in geo:GetChildren() do
		local glass = tower:IsA("Model") and tower.Name == "Tower" and tower:FindFirstChild("TowerGlass") :: BasePart?
		if not glass then
			continue
		end
		local size = glass.Size
		local fh = Config.Towers.FloorHeight
		local floors = math.floor(size.Y / fh)
		for f = 0, floors - 1 do
			for _, face in { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) } do
				if rng:NextNumber() < dn.LitWindows * 1.4 then
					local len = if face.X == 0 then size.X else size.Z
					local depth = if face.X == 0 then size.Z else size.X
					local w = rng:NextNumber(6, math.max(7, len * 0.5))
					local u = rng:NextNumber(-len / 2 + w / 2 + 1, len / 2 - w / 2 - 1)
					local y = glass.Position.Y - size.Y / 2 + f * fh + fh / 2 + 0.3
					local t = CityGrid.right(face)
					local p = Vector3.new(glass.Position.X, y, glass.Position.Z) + face * (depth / 2 + 0.06) + t * u
					local panel = part(tower, "LitWindows", Vector3.new(if face.X == 0 then w else 0.1, fh - 3, if face.X == 0 then 0.1 else w), CFrame.new(p), glass.Color, Enum.Material.SmoothPlastic, false, { Transparency = 1, CastShadow = false })
					nightWindow(panel)
				end
			end
		end
	end
end

------------------------------------------------------------------------

-- ctx (даёт MapBuilder):
--   map, geo       -- папки карты
--   place(e)       -- построить элемент карты (block/shell/...) с отделкой
--   buildBase(teamKey, pos: Vector3, gateDir: Vector3)
------------------------------------------------------------------------
-- Оптимизация после сборки (этап 6). Днём узкое место — тени солнца: их отбрасывали ~12 500
-- деталей, большая часть — мелочь, чья тень не видна (рамы и стёкла окон, подоконники, плафоны
-- фонарей, козырьки светофоров, карнизы). Им тени выключаем; тени зданий, деревьев, столбов
-- и крупных предметов остаются. Касания (Touched) у карты никто не слушает — выключаем всем.
local NO_SHADOW = {
	WindowSill = true,
	WindowFrame = true,
	WindowMullion = true,
	WindowGlass = true,
	TowerWindows = true,
	LitWindows = true,
	FloorBand = true,
	Cornice = true,
	Plinth = true,
	Pipe = true,
	LampGlass = true,
	LampHead = true,
	LampArm = true,
	LampBase = true,
	Lamp = true,
	PedLamp = true,
	SignalVisor = true,
	Marking = true,
}

optimize = function(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanTouch = false
			if d.CastShadow then
				local s = d.Size
				-- Деталь-носитель меша (деревья, кусты) крошечная, а видимая форма большая — её не трогаем.
				local thin = math.min(s.X, s.Y, s.Z) < 0.35
					and math.max(s.X, s.Y, s.Z) < 16
					and d:FindFirstChildOfClass("SpecialMesh") == nil
				if NO_SHADOW[d.Name] or thin or d.Transparency >= 0.95 or d.Material == Enum.Material.Neon then
					d.CastShadow = false
				end
			end
		end
	end
end

function CityBuilder.build(ctx)
	local rng = Random.new(Config.Seed)
	local city = folder(ctx.map, "City")
	ctx.city = city
	ctx.parking = folder(city, "ParkingSpots")
	ctx.sitPoints = folder(city, "SitPoints")
	ctx.pumps = folder(city, "FuelPumps")
	ctx.skips = {}
	local street = Instance.new("Model")
	street.Name = "Detail_Street"
	ctx.street = street
	local markings = Instance.new("Model")
	markings.Name = "Detail_RoadMarkings"

	-- Разметка улиц между перекрёстками.
	for i = 0, N do
		for j = 1, N do
			local zMid = (CityGrid.line(j - 1) + CityGrid.line(j)) / 2
			roadSegment(markings, Vector3.new(CityGrid.line(i), 0, zMid), Vector3.new(0, 0, 1))
			local xMid = zMid
			roadSegment(markings, Vector3.new(xMid, 0, CityGrid.line(i)), Vector3.new(1, 0, 0))
		end
	end

	-- Кварталы.
	for row = 1, N do
		for col = 1, N do
			local kind = CityGrid.lot(col, row)
			local bc = CityGrid.blockCenter(col, row)
			local blockRng = Random.new(Config.Seed * 1000 + row * 31 + col)
			local teamKey = kind:match("^base:(.+)$")
			if teamKey then
				baseLot(ctx, bc, teamKey, blockRng)
			else
				local fn = lots[kind] or lots.residential
				fn(ctx, bc, blockRng)
			end
			sidewalkItems(ctx, bc, kind, blockRng)
		end
	end

	-- Перекрёстки и светофоры (после кварталов: столбы встают на углы тротуаров).
	local intersections = folder(city, "Intersections")
	for i = 0, N do
		for j = 0, N do
			buildIntersection(intersections, i, j)
		end
	end

	outskirts(ctx, rng)
	markings.Parent = ctx.geo
	street.Parent = ctx.geo
	nightDetails(ctx.geo, rng)
	optimize(ctx.map)
	return city
end

return CityBuilder
