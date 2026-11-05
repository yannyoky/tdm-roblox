-- Собирает карту из описания в Config/Maps в папку Workspace.Map.
-- Структура результата совместима с MatchService и режимами:
--   Map/Geometry/...                       -- всё, что видно и по чему ходят
--   Map/Spawns/<Team>, <Team>_Forward, Lobby
--   Map/CapturePoints/<Имя зоны>           -- плоские детали зон капта
--   Map/Bases/<Team>                       -- невидимый объём базы (защищённая зона)
--   Map/VehiclePads/<Team>/Pad1..N         -- площадки, где появляются машины
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TeamsConfig = require(Shared.Config.Teams)
local MapsConfig = require(Shared.Config.Maps)
local VehiclesConfig = require(Shared.Config.Vehicles)

local MapBuilder = {}

-- Если пандусы в Studio окажутся развёрнуты не той стороной, поменяйте знак.
local WEDGE_FLIP = 1

local BASE_W, BASE_D = 110, 84 -- размер базы (ширина вдоль фронта, глубина)
local BASE_WALL_H = 12
local GATE_W = 44

local SIDES = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

local PALETTE = {
	Color3.fromRGB(150, 140, 125),
	Color3.fromRGB(125, 128, 132),
	Color3.fromRGB(160, 120, 95),
	Color3.fromRGB(110, 115, 105),
	Color3.fromRGB(175, 165, 150),
}
local CONTAINER_COLORS = {
	Color3.fromRGB(160, 50, 40),
	Color3.fromRGB(40, 90, 150),
	Color3.fromRGB(50, 120, 70),
	Color3.fromRGB(190, 140, 40),
	Color3.fromRGB(110, 110, 110),
}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.TopSurface = Enum.SurfaceType.Smooth
		inst.BottomSurface = Enum.SurfaceType.Smooth
	end
	inst.Parent = parent
	return inst
end

local function folder(parent: Instance, name: string): Folder
	return make("Folder", { Name = name }, parent)
end

local function material(name: any, default: Enum.Material): Enum.Material
	if typeof(name) == "EnumItem" then
		return name
	elseif type(name) == "string" then
		return (Enum.Material :: any)[name]
	end
	return default
end

-- Поворот вокруг вертикали в градусах.
local function yaw(rot: number?): CFrame
	return CFrame.Angles(0, math.rad(rot or 0), 0)
end

local function box(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	return make("Part", { Name = name, Size = size, CFrame = cf, Color = color, Material = mat }, parent)
end

-- Пандус: низ на земле в точке center, поднимается в направлении riseDir.
local function wedge(parent: Instance, name: string, center: Vector3, riseDir: Vector3, w: number, h: number, len: number, color: Color3, mat: Enum.Material)
	local look = -riseDir * WEDGE_FLIP
	local cf = CFrame.lookAt(center + Vector3.new(0, h / 2, 0), center + Vector3.new(0, h / 2, 0) + look)
	return make("WedgePart", { Name = name, Size = Vector3.new(w, h, len), CFrame = cf, Color = color, Material = mat }, parent)
end

-- Лестница (TrussPart): по ней Roblox даёт лазать сам, на всех платформах.
local function ladder(parent: Instance, base: CFrame, height: number)
	local h = math.max(2, math.ceil(height / 2) * 2)
	return make("TrussPart", {
		Name = "Ladder",
		Size = Vector3.new(2, h, 2),
		CFrame = base * CFrame.new(0, h / 2, 0),
		Color = Color3.fromRGB(70, 70, 75),
		Material = Enum.Material.Metal,
	}, parent)
end

------------------------------------------------------------------------
-- Элементы карты

local builders = {}

function builders.block(geo: Instance, e, rng: Random)
	local base = CFrame.new(e.x, 0, e.z) * yaw(e.rot)
	local color = e.color or PALETTE[rng:NextInteger(1, #PALETTE)]
	local mat = material(e.material, Enum.Material.Concrete)
	box(geo, "Building", Vector3.new(e.w, e.h, e.d), base * CFrame.new(0, e.h / 2, 0), color, mat)

	local access = e.access
	if not access then
		return
	end
	local side, kind = access[1], access[2]
	local dir = SIDES[side]
	local half = if side == "N" or side == "S" then e.d / 2 else e.w / 2
	local faceLen = if side == "N" or side == "S" then e.w else e.d
	local tangent = Vector3.new(-dir.Z, 0, dir.X)

	if kind == "stairs" and faceLen >= e.h * 1.6 + 2 then
		local len = math.min(faceLen - 2, e.h * 2.2)
		local center = base:PointToWorldSpace(dir * (half + 2.5))
		wedge(geo, "Stairs", center, base:VectorToWorldSpace(tangent), 5, e.h, len, color, mat)
	else
		-- Лестница у правого края стены, чтобы не загораживать центр.
		local offset = dir * (half + 1) + tangent * math.max(0, faceLen / 2 - 3)
		ladder(geo, base * CFrame.new(offset), e.h)
	end
end

-- Стена с проёмами. openings: { { u = центр вдоль стены, w, bottom, top } }.
local function wallWithOpenings(geo: Instance, cf: CFrame, length: number, height: number, thick: number, openings, color: Color3, mat: Enum.Material)
	table.sort(openings, function(a, b)
		return a.u < b.u
	end)
	local cursor = -length / 2
	local function piece(u0: number, u1: number, y0: number, y1: number)
		if u1 - u0 < 0.05 or y1 - y0 < 0.05 then
			return
		end
		local size = Vector3.new(u1 - u0, y1 - y0, thick)
		box(geo, "Wall", size, cf * CFrame.new((u0 + u1) / 2, (y0 + y1) / 2, 0), color, mat)
	end
	for _, o in openings do
		local u0, u1 = o.u - o.w / 2, o.u + o.w / 2
		piece(cursor, u0, 0, height)
		piece(u0, u1, 0, o.bottom)
		piece(u0, u1, o.top, height)
		cursor = u1
	end
	piece(cursor, length / 2, 0, height)
end

function builders.shell(geo: Instance, e, rng: Random)
	local base = CFrame.new(e.x, 0, e.z) * yaw(e.rot)
	local color = e.color or PALETTE[rng:NextInteger(1, #PALETTE)]
	local mat = material(e.material, Enum.Material.Brick)
	local w, d, h = e.w, e.d, e.h
	local t = 1
	local doors = {}
	for _, s in e.doors or {} do
		doors[s] = true
	end

	-- Стены: N/S во всю ширину, E/W между ними.
	local walls = {
		N = { cf = base * CFrame.new(0, 0, -d / 2 + t / 2), len = w },
		S = { cf = base * CFrame.new(0, 0, d / 2 - t / 2) * yaw(180), len = w },
		E = { cf = base * CFrame.new(w / 2 - t / 2, 0, 0) * yaw(-90), len = d - 2 * t },
		W = { cf = base * CFrame.new(-w / 2 + t / 2, 0, 0) * yaw(90), len = d - 2 * t },
	}
	for side, wall in walls do
		local openings = {}
		if doors[side] then
			table.insert(openings, { u = 0, w = 6, bottom = 0, top = math.min(8.5, h - 1.5) })
		end
		-- Окна для стрельбы изнутри, каждые ~10 студов.
		if h >= 8 then
			local n = math.floor(wall.len / 10)
			for i = 1, n do
				local u = -wall.len / 2 + (i - 0.5) * (wall.len / n)
				if not doors[side] or math.abs(u) > 6 then
					table.insert(openings, { u = u, w = 3, bottom = 3.5, top = 6.5 })
				end
			end
		end
		wallWithOpenings(geo, wall.cf, wall.len, h, t, openings, color, mat)
	end

	-- Пол и крыша с люком в углу.
	box(geo, "Floor", Vector3.new(w - 2 * t, 0.2, d - 2 * t), base * CFrame.new(0, 0.1, 0), Color3.fromRGB(95, 90, 85), Enum.Material.WoodPlanks)
	local roofY = h + 0.5
	if e.hatch then
		local hs = 4 -- размер люка
		local hx, hz = w / 2 - t - 3 - hs / 2, d / 2 - t - 3 - hs / 2
		-- крыша из 4 частей вокруг люка
		local x0, x1 = hx - hs / 2, hx + hs / 2
		local z0, z1 = hz - hs / 2, hz + hs / 2
		local function roof(ax: number, bx: number, az: number, bz: number)
			if bx - ax > 0.05 and bz - az > 0.05 then
				box(geo, "Roof", Vector3.new(bx - ax, 1, bz - az), base * CFrame.new((ax + bx) / 2, roofY, (az + bz) / 2), color, Enum.Material.Concrete)
			end
		end
		roof(-w / 2, x0, -d / 2, d / 2)
		roof(x1, w / 2, -d / 2, d / 2)
		roof(x0, x1, -d / 2, z0)
		roof(x0, x1, z1, d / 2)
		-- лестница под люком, вплотную к стене
		ladder(geo, base * CFrame.new(hx, 0, hz + hs / 2 - 1), h + 1)
	else
		box(geo, "Roof", Vector3.new(w, 1, d), base * CFrame.new(0, roofY, 0), color, Enum.Material.Concrete)
	end
end

function builders.container(geo: Instance, e, rng: Random)
	local base = CFrame.new(e.x, 0, e.z) * yaw(e.rot)
	for level = 1, e.stack or 1 do
		local color = CONTAINER_COLORS[rng:NextInteger(1, #CONTAINER_COLORS)]
		box(geo, "Container", Vector3.new(8, 8.5, 20), base * CFrame.new(0, 8.5 * (level - 0.5), 0), color, Enum.Material.CorrodedMetal)
	end
end

function builders.crate(geo: Instance, e, rng: Random)
	local s = e.s or 4
	local cf = CFrame.new(e.x, s / 2, e.z) * yaw(rng:NextNumber(-20, 20))
	box(geo, "Crate", Vector3.new(s, s, s), cf, Color3.fromRGB(140, 105, 65), Enum.Material.WoodPlanks)
end

local function linear(geo: Instance, name: string, e, thick: number, color: Color3, mat: Enum.Material)
	local a, b = Vector3.new(e.x1, 0, e.z1), Vector3.new(e.x2, 0, e.z2)
	local len = (b - a).Magnitude
	if len < 0.1 then
		return
	end
	local mid = (a + b) / 2 + Vector3.new(0, e.h / 2, 0)
	local cf = CFrame.lookAt(mid, mid + (b - a))
	box(geo, name, Vector3.new(thick, e.h, len), cf, color, mat)
end

function builders.fence(geo: Instance, e)
	linear(geo, "Fence", e, 0.5, Color3.fromRGB(120, 95, 70), Enum.Material.WoodPlanks)
end

function builders.wall(geo: Instance, e)
	linear(geo, "Wall", e, 1.5, Color3.fromRGB(150, 145, 140), Enum.Material.Concrete)
end

function builders.road(geo: Instance, e)
	local a, b = Vector3.new(e.x1, 0, e.z1), Vector3.new(e.x2, 0, e.z2)
	local mid = (a + b) / 2 + Vector3.new(0, 0.06, 0)
	local cf = CFrame.lookAt(mid, mid + (b - a))
	make("Part", {
		Name = "Road",
		Size = Vector3.new(e.w, 0.1, (b - a).Magnitude + e.w),
		CFrame = cf,
		Color = Color3.fromRGB(55, 55, 58),
		Material = Enum.Material.Asphalt,
		CanCollide = false, -- ездим по земле, дорога только рисунок
		CanQuery = false,
	}, geo)
end

function builders.ramp(geo: Instance, e)
	local dir = yaw(e.rot).LookVector
	wedge(geo, "Ramp", Vector3.new(e.x, 0, e.z), dir, e.w, e.h, e.len, Color3.fromRGB(120, 120, 115), Enum.Material.DiamondPlate)
end

function builders.beam(geo: Instance, e)
	local cf = CFrame.new(e.x, e.y + e.h / 2, e.z) * yaw(e.rot)
	box(geo, "Beam", Vector3.new(e.w, e.h, e.d), cf, Color3.fromRGB(200, 160, 40), Enum.Material.Metal)
end

local function buildElement(geo: Instance, e, rng: Random)
	local fn = builders[e.kind]
	if fn then
		fn(geo, e, rng)
	else
		warn("[MapBuilder] Неизвестный элемент карты: " .. tostring(e.kind))
	end
end

------------------------------------------------------------------------
-- Случайная застройка между дорогами и зонами (детерминированная по Seed)

local function distToSegment(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (p - (a + ab * t)).Magnitude
end

local Occupancy = {}
Occupancy.__index = Occupancy

function Occupancy.new()
	return setmetatable({ circles = {}, segments = {} }, Occupancy)
end

function Occupancy:addCircle(x: number, z: number, r: number)
	table.insert(self.circles, { p = Vector2.new(x, z), r = r })
end

function Occupancy:addSegment(x1: number, z1: number, x2: number, z2: number, halfW: number)
	table.insert(self.segments, { a = Vector2.new(x1, z1), b = Vector2.new(x2, z2), r = halfW })
end

function Occupancy:free(x: number, z: number, r: number): boolean
	local p = Vector2.new(x, z)
	for _, c in self.circles do
		if (c.p - p).Magnitude < c.r + r then
			return false
		end
	end
	for _, s in self.segments do
		if distToSegment(p, s.a, s.b) < s.r + r then
			return false
		end
	end
	return true
end

-- Те же описания элементов, что в Config/Maps.
local function Block(x, z, w, d, h, access, extra)
	local t = { kind = "block", x = x, z = z, w = w, d = d, h = h, access = access }
	for k, v in extra or {} do
		t[k] = v
	end
	return t
end

local function Shell(x, z, w, d, h, doors, extra)
	local t = { kind = "shell", x = x, z = z, w = w, d = d, h = h, doors = doors, hatch = true }
	for k, v in extra or {} do
		t[k] = v
	end
	return t
end

local function Container(x, z, rot, stack)
	return { kind = "container", x = x, z = z, rot = rot, stack = stack }
end

local function Crate(x, z, s)
	return { kind = "crate", x = x, z = z, s = s }
end

local function Fence(x1, z1, x2, z2)
	return { kind = "fence", x1 = x1, z1 = z1, x2 = x2, z2 = z2, h = 4 }
end

-- Генераторы «кварталов»: возвращают список элементов и радиус занимаемого места.
local fillers = {}

function fillers.block(rng: Random, x: number, z: number)
	local w, d = rng:NextInteger(14, 28), rng:NextInteger(12, 24)
	local h = rng:NextInteger(9, 22)
	local sides = { "N", "S", "E", "W" }
	local access = { sides[rng:NextInteger(1, 4)], if rng:NextNumber() < 0.4 then "stairs" else "ladder" }
	return { Block(x, z, w, d, h, access, { rot = rng:NextInteger(0, 3) * 90 }) }, math.max(w, d) / 2 + 6
end

function fillers.panel(rng: Random, x: number, z: number)
	local w, d = rng:NextInteger(40, 60), rng:NextInteger(12, 15)
	local h = rng:NextInteger(16, 24)
	local access = { if rng:NextNumber() < 0.5 then "E" else "W", "ladder" }
	local items = { Block(x, z, w, d, h, access, { rot = rng:NextInteger(0, 1) * 90, material = "Concrete" }) }
	return items, w / 2 + 6
end

function fillers.shell(rng: Random, x: number, z: number)
	local w, d = rng:NextInteger(18, 30), rng:NextInteger(14, 22)
	local h = rng:NextInteger(9, 12)
	local all = { "N", "S", "E", "W" }
	local doors = { all[rng:NextInteger(1, 4)] }
	if rng:NextNumber() < 0.6 then
		local second = all[rng:NextInteger(1, 4)]
		if second ~= doors[1] then
			table.insert(doors, second)
		end
	end
	return { Shell(x, z, w, d, h, doors, { rot = rng:NextInteger(0, 3) * 90 }) }, math.max(w, d) / 2 + 6
end

function fillers.containers(rng: Random, x: number, z: number)
	local items = {}
	local rot = rng:NextInteger(0, 1) * 90
	local base = CFrame.new(x, 0, z) * yaw(rot)
	local n = rng:NextInteger(1, 3)
	for i = 1, n do
		local p = base * Vector3.new((i - (n + 1) / 2) * 9, 0, rng:NextNumber(-3, 3))
		table.insert(items, Container(p.X, p.Z, rot, if rng:NextNumber() < 0.35 then 2 else 1))
	end
	return items, 16
end

function fillers.crates(rng: Random, x: number, z: number)
	local items = {}
	for _ = 1, rng:NextInteger(2, 5) do
		table.insert(items, Crate(x + rng:NextNumber(-6, 6), z + rng:NextNumber(-6, 6), rng:NextInteger(3, 4)))
	end
	return items, 9
end

function fillers.shed(rng: Random, x: number, z: number)
	return { Block(x, z, 7, 7, rng:NextInteger(5, 7), nil, { material = "WoodPlanks", rot = rng:NextInteger(0, 3) * 45 }) }, 7
end

-- Дачный участок: забор с калиткой, домик с люком на крышу, иногда сарай.
function fillers.dacha(rng: Random, x: number, z: number)
	local W, D = rng:NextInteger(26, 34), rng:NextInteger(22, 30)
	local x0, x1, z0, z1 = x - W / 2, x + W / 2, z - D / 2, z + D / 2
	local gate = rng:NextNumber(x0 + 4, x1 - 8)
	local items = {
		Fence(x0, z0, x1, z0),
		Fence(x0, z0, x0, z1),
		Fence(x1, z0, x1, z1),
		Fence(x0, z1, gate, z1),
		Fence(gate + 5, z1, x1, z1),
		Shell(x + rng:NextNumber(-3, 3), z - D / 6, 12, 10, 8, { "S" }, { material = "WoodPlanks" }),
	}
	if rng:NextNumber() < 0.5 then
		table.insert(items, Block(x1 - 5, z1 - 6, 5, 5, 5, nil, { material = "WoodPlanks" }))
	end
	return items, math.max(W, D) / 2 + 5
end

------------------------------------------------------------------------
-- База команды

local function buildBase(map: Folder, geo: Instance, teamKey: string, cfg, center: Vector3)
	local info = TeamsConfig.List[teamKey]
	local pos = Vector3.new(cfg.x, 0, cfg.z)
	local toCenter = Vector3.new(center.X - pos.X, 0, center.Z - pos.Z)
	-- Локальная система базы: -Z смотрит в сторону центра карты (там ворота).
	local cf = CFrame.lookAt(pos, pos + toCenter.Unit)
	local baseGeo = folder(geo, "Base_" .. teamKey)
	local wallColor = info.Color:Lerp(Color3.fromRGB(90, 90, 90), 0.6)

	box(baseGeo, "BaseFloor", Vector3.new(BASE_W, 0.4, BASE_D), cf * CFrame.new(0, 0.2, 0), Color3.fromRGB(70, 72, 75), Enum.Material.Concrete)
	-- Стены с трёх сторон и ворота спереди.
	local H = BASE_WALL_H
	box(baseGeo, "BaseWall", Vector3.new(BASE_W, H, 2), cf * CFrame.new(0, H / 2, BASE_D / 2), wallColor, Enum.Material.Concrete)
	box(baseGeo, "BaseWall", Vector3.new(2, H, BASE_D), cf * CFrame.new(-BASE_W / 2, H / 2, 0), wallColor, Enum.Material.Concrete)
	box(baseGeo, "BaseWall", Vector3.new(2, H, BASE_D), cf * CFrame.new(BASE_W / 2, H / 2, 0), wallColor, Enum.Material.Concrete)
	local side = (BASE_W - GATE_W) / 2
	box(baseGeo, "BaseWall", Vector3.new(side, H, 2), cf * CFrame.new(-BASE_W / 2 + side / 2, H / 2, -BASE_D / 2), wallColor, Enum.Material.Concrete)
	box(baseGeo, "BaseWall", Vector3.new(side, H, 2), cf * CFrame.new(BASE_W / 2 - side / 2, H / 2, -BASE_D / 2), wallColor, Enum.Material.Concrete)
	-- Флаг команды.
	box(baseGeo, "FlagPole", Vector3.new(0.6, 24, 0.6), cf * CFrame.new(0, 12, BASE_D / 2 - 6), Color3.fromRGB(200, 200, 200), Enum.Material.Metal)
	box(baseGeo, "Flag", Vector3.new(0.2, 5, 8), cf * CFrame.new(0, 21, BASE_D / 2 - 10) * yaw(90), info.Color, Enum.Material.Fabric)

	-- Невидимый объём базы: внутри свои защищены, чужие получают урон.
	local volume = make("Part", {
		Name = teamKey,
		Size = Vector3.new(BASE_W, 40, BASE_D),
		CFrame = cf * CFrame.new(0, 20, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, map:FindFirstChild("Bases"))
	volume:SetAttribute("Team", teamKey)

	-- Точки появления в задней половине базы, лицом к воротам.
	local spawns = folder(map:FindFirstChild("Spawns") :: Instance, teamKey)
	local i = 0
	for row = 0, 1 do
		for col = -3, 3 do
			i += 1
			make("Part", {
				Name = "Spawn" .. i,
				Size = Vector3.new(5, 0.2, 5),
				CFrame = cf * CFrame.new(col * 12, 0.5, BASE_D / 2 - 12 - row * 12),
				Color = info.Color,
				Material = Enum.Material.Neon,
				Transparency = 0.7,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			}, spawns)
		end
	end

	-- Площадки машин в передней половине, носом к воротам.
	local pads = folder(map:FindFirstChild("VehiclePads") :: Instance, teamKey)
	local fleet = VehiclesConfig.Fleet[teamKey] or {}
	local list = {}
	for _, entry in fleet do
		for _ = 1, entry.Count do
			table.insert(list, entry.Type)
		end
	end
	local spacing = math.min(14, (BASE_W - 10) / math.max(1, #list))
	for n, vehicleType in list do
		local x = (n - (#list + 1) / 2) * spacing
		local pad = make("Part", {
			Name = "Pad" .. n,
			Size = Vector3.new(9, 0.2, 17),
			CFrame = cf * CFrame.new(x, 0.45, -BASE_D / 2 + 22),
			Color = Color3.fromRGB(230, 200, 60),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.5,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, pads)
		pad:SetAttribute("VehicleType", vehicleType)
		pad:SetAttribute("Team", teamKey)
	end

	return cf
end

-- Передовая точка: небольшая позиция из мешков с песком на полпути к центру.
local function buildForward(map: Folder, geo: Instance, teamKey: string, pos: Vector3, center: Vector3)
	local info = TeamsConfig.List[teamKey]
	local cf = CFrame.lookAt(pos, Vector3.new(center.X, 0, center.Z))
	local spawns = folder(map:FindFirstChild("Spawns") :: Instance, teamKey .. "_Forward")
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2
		make("Part", {
			Name = "Spawn" .. i,
			Size = Vector3.new(4, 0.2, 4),
			CFrame = cf * CFrame.new(math.cos(angle) * 9, 0.3, math.sin(angle) * 9),
			Color = info.Color,
			Material = Enum.Material.Neon,
			Transparency = 0.8,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, spawns)
	end
	for _, offset in { Vector3.new(-8, 0, -16), Vector3.new(8, 0, -16), Vector3.new(0, 0, -19) } do
		box(geo, "Sandbags", Vector3.new(8, 3, 2), cf * CFrame.new(offset + Vector3.new(0, 1.5, 0)), Color3.fromRGB(150, 135, 100), Enum.Material.Sand)
	end
end

------------------------------------------------------------------------
-- Лобби (общее для всех карт)

function MapBuilder.ensureLobby(): Model
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		return existing
	end
	local lobby = make("Model", { Name = "Lobby" }, nil)
	local p = MapsConfig.Lobby.Position
	local gray = Color3.fromRGB(70, 70, 80)
	box(lobby, "LobbyFloor", Vector3.new(48, 2, 48), CFrame.new(p - Vector3.new(0, 1, 0)), gray, Enum.Material.Concrete)
	box(lobby, "LobbyRail", Vector3.new(48, 6, 1), CFrame.new(p + Vector3.new(0, 3, 24)), gray, Enum.Material.Concrete)
	box(lobby, "LobbyRail", Vector3.new(48, 6, 1), CFrame.new(p + Vector3.new(0, 3, -24)), gray, Enum.Material.Concrete)
	box(lobby, "LobbyRail", Vector3.new(1, 6, 48), CFrame.new(p + Vector3.new(24, 3, 0)), gray, Enum.Material.Concrete)
	box(lobby, "LobbyRail", Vector3.new(1, 6, 48), CFrame.new(p + Vector3.new(-24, 3, 0)), gray, Enum.Material.Concrete)
	lobby.Parent = workspace
	return lobby
end

------------------------------------------------------------------------

function MapBuilder.build(mapId: string): Folder
	local cfg = MapsConfig.List[mapId]
	assert(cfg, "Нет карты " .. tostring(mapId))
	local rng = Random.new(cfg.Filler and cfg.Filler.Seed or 1)

	local map = Instance.new("Folder")
	map.Name = "Map"
	map:SetAttribute("MapId", mapId)
	map:SetAttribute("MapName", cfg.Name)
	local geo = folder(map, "Geometry")
	folder(map, "Spawns")
	folder(map, "CapturePoints")
	folder(map, "Bases")
	folder(map, "VehiclePads")

	-- Земля и невидимые границы.
	local S = cfg.Size
	box(geo, "Ground", Vector3.new(S, 4, S), CFrame.new(0, -2, 0), cfg.Ground.Color, cfg.Ground.Material)
	for _, b in {
		{ Vector3.new(S, 300, 2), Vector3.new(0, 150, S / 2) },
		{ Vector3.new(S, 300, 2), Vector3.new(0, 150, -S / 2) },
		{ Vector3.new(2, 300, S), Vector3.new(S / 2, 150, 0) },
		{ Vector3.new(2, 300, S), Vector3.new(-S / 2, 150, 0) },
	} do
		make("Part", { Name = "Boundary", Size = b[1], CFrame = CFrame.new(b[2]), Transparency = 1, CanQuery = false }, geo)
	end

	local occ = Occupancy.new()
	local center = Vector3.zero

	-- Дороги.
	for _, road in cfg.Roads or {} do
		builders.road(geo, road)
		occ:addSegment(road.x1, road.z1, road.x2, road.z2, road.w / 2 + 3)
	end

	-- Базы и передовые точки.
	for teamKey, baseCfg in cfg.Bases do
		buildBase(map, geo, teamKey, baseCfg, center)
		occ:addCircle(baseCfg.x, baseCfg.z, math.max(BASE_W, BASE_D) / 2 + 20)
		local basePos = Vector3.new(baseCfg.x, 0, baseCfg.z)
		local fwd = basePos:Lerp(center, 0.45)
		-- Сдвигаем передовую точку с дороги вбок, если нужно.
		local side = Vector3.new(-(center - basePos).Unit.Z, 0, (center - basePos).Unit.X)
		for _, shift in { 0, 30, -30, 55, -55 } do
			local candidate = fwd + side * shift
			if occ:free(candidate.X, candidate.Z, 14) then
				fwd = candidate
				break
			end
		end
		buildForward(map, geo, teamKey, fwd, center)
		occ:addCircle(fwd.X, fwd.Z, 26)
	end

	-- Зоны каптов и их постройки.
	local points = map:FindFirstChild("CapturePoints") :: Folder
	for _, zone in cfg.Zones do
		local zonePart = make("Part", {
			Name = zone.Name,
			Size = Vector3.new(zone.w, 1, zone.d),
			CFrame = CFrame.new(zone.x, 0.5, zone.z),
			Color = Color3.fromRGB(240, 240, 240),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.75,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, points)
		CollectionService:AddTag(zonePart, "CaptureZone")
		box(geo, "ZonePole", Vector3.new(0.6, 18, 0.6), CFrame.new(zone.x, 9, zone.z), Color3.fromRGB(220, 220, 220), Enum.Material.Metal)
		for _, e in zone.Props or {} do
			buildElement(geo, e, rng)
		end
		occ:addCircle(zone.x, zone.z, math.max(zone.w, zone.d) / 2 + 8)
	end

	for _, e in cfg.Extras or {} do
		buildElement(geo, e, rng)
		occ:addCircle(e.x or 0, e.z or 0, 16)
	end

	-- Случайная застройка.
	local filler = cfg.Filler
	if filler then
		local a = filler.Area
		local placed, tries = 0, 0
		while placed < filler.Count and tries < filler.Count * 40 do
			tries += 1
			local kind = filler.Kinds[rng:NextInteger(1, #filler.Kinds)]
			local x, z = rng:NextNumber(a[1], a[3]), rng:NextNumber(a[2], a[4])
			-- Сначала прикидываем размер, потом проверяем место.
			local probe = Random.new(rng:NextInteger(1, 2 ^ 30))
			local items, radius = fillers[kind](probe, x, z)
			if occ:free(x, z, radius) then
				for _, e in items do
					buildElement(geo, e, rng)
				end
				occ:addCircle(x, z, radius)
				placed += 1
			end
		end
	end

	-- Точки лобби (сама площадка общая, см. ensureLobby).
	local lobbySpawns = folder(map:FindFirstChild("Spawns") :: Instance, "Lobby")
	local lp = MapsConfig.Lobby.Position
	for i, offset in { Vector3.new(-10, 0, -10), Vector3.new(10, 0, -10), Vector3.new(-10, 0, 10), Vector3.new(10, 0, 10) } do
		make("Part", {
			Name = "Spawn" .. i,
			Size = Vector3.new(5, 0.2, 5),
			CFrame = CFrame.new(lp + offset + Vector3.new(0, 0.1, 0)),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, lobbySpawns)
	end

	return map
end

return MapBuilder
