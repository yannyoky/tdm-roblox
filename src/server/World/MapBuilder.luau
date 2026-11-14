-- Собирает карту из описания в Config/MapsData.json в папку Workspace.Map.
-- Структура результата совместима с MatchService и режимами:
--   Map/Geometry/...                       -- всё, что видно и по чему ходят
--   Map/Spawns/<Team>, <Team>_Forward, Lobby
--   Map/CapturePoints/<Имя зоны>           -- зоны капта (могут быть повёрнуты)
--   Map/Bases/<Team>                       -- невидимый объём базы (защищённая зона)
--   Map/VehiclePads/<Team>/Pad1..N         -- площадки, где появляются машины
-- Холмы делаются из Terrain, всё остальное — из деталей.
--
-- Расстановка (дороги, зоны, застройка) повторена в tools/map_layout.py для схемы карт:
-- если меняете порядок вызовов генератора случайных чисел здесь, поменяйте и там.
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
local SMOOTH_STEPS = 6 -- точек сглаживания на каждый отрезок дороги

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
local ROAD_STYLE = {
	road = { color = Color3.fromRGB(55, 55, 58), material = Enum.Material.Asphalt },
	dirt = { color = Color3.fromRGB(120, 100, 70), material = Enum.Material.Ground },
	path = { color = Color3.fromRGB(110, 92, 64), material = Enum.Material.Ground },
}

------------------------------------------------------------------------
-- Генератор случайных чисел (MINSTD). Свой, а не Random, чтобы схема карты
-- (tools/map_layout.py) получала ровно ту же расстановку.

local Rng = {}
Rng.__index = Rng

function Rng.new(seed: number)
	local s = math.floor(seed) % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return setmetatable({ s = s }, Rng)
end

function Rng:next(): number
	self.s = (self.s * 48271) % 2147483647
	return self.s
end

function Rng:float(): number
	return (self:next() - 1) / 2147483646
end

function Rng:range(a: number, b: number): number
	return a + self:float() * (b - a)
end

function Rng:int(a: number, b: number): number
	return a + math.floor(self:float() * (b - a + 1))
end

------------------------------------------------------------------------

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

local function color(c: any): Color3?
	if type(c) == "table" then
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	return c
end

-- Поворот вокруг вертикали в градусах.
local function yaw(rot: number?): CFrame
	return CFrame.Angles(0, math.rad(rot or 0), 0)
end

-- То же, что yaw(rot) * Vector3.new(lx, 0, lz), но только X и Z (как rot_xz в схеме).
local function rotXZ(lx: number, lz: number, rot: number): (number, number)
	local t = math.rad(rot)
	local c, s = math.cos(t), math.sin(t)
	return c * lx + s * lz, -s * lx + c * lz
end

local function box(parent: Instance, name: string, size: Vector3, cf: CFrame, col: Color3, mat: Enum.Material): Part
	return make("Part", { Name = name, Size = size, CFrame = cf, Color = col, Material = mat }, parent)
end

-- Пандус: низ на земле в точке center, поднимается в направлении riseDir.
local function wedge(parent: Instance, name: string, center: Vector3, riseDir: Vector3, w: number, h: number, len: number, col: Color3, mat: Enum.Material)
	local look = -riseDir * WEDGE_FLIP
	local cf = CFrame.lookAt(center + Vector3.new(0, h / 2, 0), center + Vector3.new(0, h / 2, 0) + look)
	return make("WedgePart", { Name = name, Size = Vector3.new(w, h, len), CFrame = cf, Color = col, Material = mat }, parent)
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

function builders.block(geo: Instance, e, style: Random)
	local base = CFrame.new(e.x, 0, e.z) * yaw(e.rot)
	local col = color(e.color) or PALETTE[style:NextInteger(1, #PALETTE)]
	local mat = material(e.mat, Enum.Material.Concrete)
	box(geo, "Building", Vector3.new(e.w, e.h, e.d), base * CFrame.new(0, e.h / 2, 0), col, mat)

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
		wedge(geo, "Stairs", center, base:VectorToWorldSpace(tangent), 5, e.h, len, col, mat)
	else
		-- Лестница у края стены, чтобы не загораживать центр.
		local offset = dir * (half + 1) + tangent * math.max(0, faceLen / 2 - 3)
		ladder(geo, base * CFrame.new(offset), e.h)
	end
end

-- Стена с проёмами. openings: { { u = центр вдоль стены, w, bottom, top } }.
local function wallWithOpenings(geo: Instance, cf: CFrame, length: number, height: number, thick: number, openings, col: Color3, mat: Enum.Material)
	table.sort(openings, function(a, b)
		return a.u < b.u
	end)
	local cursor = -length / 2
	local function piece(u0: number, u1: number, y0: number, y1: number)
		if u1 - u0 < 0.05 or y1 - y0 < 0.05 then
			return
		end
		local size = Vector3.new(u1 - u0, y1 - y0, thick)
		box(geo, "Wall", size, cf * CFrame.new((u0 + u1) / 2, (y0 + y1) / 2, 0), col, mat)
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

function builders.shell(geo: Instance, e, style: Random)
	local base = CFrame.new(e.x, 0, e.z) * yaw(e.rot)
	local col = color(e.color) or PALETTE[style:NextInteger(1, #PALETTE)]
	local mat = material(e.mat, Enum.Material.Brick)
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
		wallWithOpenings(geo, wall.cf, wall.len, h, t, openings, col, mat)
	end

	-- Пол и крыша с люком в углу.
	box(geo, "Floor", Vector3.new(w - 2 * t, 0.2, d - 2 * t), base * CFrame.new(0, 0.1, 0), Color3.fromRGB(95, 90, 85), Enum.Material.WoodPlanks)
	local roofY = h + 0.5
	if e.hatch ~= false then
		local hs = 4 -- размер люка
		local hx, hz = w / 2 - t - 3 - hs / 2, d / 2 - t - 3 - hs / 2
		local x0, x1 = hx - hs / 2, hx + hs / 2
		local z0, z1 = hz - hs / 2, hz + hs / 2
		local function roof(ax: number, bx: number, az: number, bz: number)
			if bx - ax > 0.05 and bz - az > 0.05 then
				box(geo, "Roof", Vector3.new(bx - ax, 1, bz - az), base * CFrame.new((ax + bx) / 2, roofY, (az + bz) / 2), col, Enum.Material.Concrete)
			end
		end
		roof(-w / 2, x0, -d / 2, d / 2)
		roof(x1, w / 2, -d / 2, d / 2)
		roof(x0, x1, -d / 2, z0)
		roof(x0, x1, z1, d / 2)
		-- лестница под люком, вплотную к стене
		ladder(geo, base * CFrame.new(hx, 0, hz + hs / 2 - 1), h + 1)
	else
		box(geo, "Roof", Vector3.new(w, 1, d), base * CFrame.new(0, roofY, 0), col, Enum.Material.Concrete)
	end
end

function builders.container(geo: Instance, e, style: Random)
	local base = CFrame.new(e.x, 0, e.z) * yaw(e.rot)
	for level = 1, e.stack or 1 do
		local col = CONTAINER_COLORS[style:NextInteger(1, #CONTAINER_COLORS)]
		box(geo, "Container", Vector3.new(8, 8.5, 20), base * CFrame.new(0, 8.5 * (level - 0.5), 0), col, Enum.Material.CorrodedMetal)
	end
end

function builders.crate(geo: Instance, e, style: Random)
	local s = e.s or 4
	local cf = CFrame.new(e.x, s / 2, e.z) * yaw(style:NextNumber(-20, 20))
	box(geo, "Crate", Vector3.new(s, s, s), cf, Color3.fromRGB(140, 105, 65), Enum.Material.WoodPlanks)
end

-- Ломаная из стенок: забор или стена по точкам pts = { {x, z}, ... }.
local function polyline(geo: Instance, name: string, e, thick: number, col: Color3, mat: Enum.Material)
	local h = e.h
	for i = 1, #e.pts - 1 do
		local a = Vector3.new(e.pts[i][1], 0, e.pts[i][2])
		local b = Vector3.new(e.pts[i + 1][1], 0, e.pts[i + 1][2])
		local len = (b - a).Magnitude
		if len > 0.1 then
			local mid = (a + b) / 2 + Vector3.new(0, h / 2, 0)
			-- +thick по длине, чтобы углы смыкались без щелей
			box(geo, name, Vector3.new(thick, h, len + thick), CFrame.lookAt(mid, mid + (b - a)), col, mat)
		end
	end
end

function builders.fence(geo: Instance, e)
	e.h = e.h or 4
	polyline(geo, "Fence", e, 0.5, Color3.fromRGB(120, 95, 70), Enum.Material.WoodPlanks)
end

function builders.wall(geo: Instance, e)
	e.h = e.h or 7
	polyline(geo, "Wall", e, 1.5, Color3.fromRGB(150, 145, 140), Enum.Material.Concrete)
end

function builders.ramp(geo: Instance, e)
	local dir = yaw(e.rot).LookVector
	wedge(geo, "Ramp", Vector3.new(e.x, 0, e.z), dir, e.w, e.h, e.len, Color3.fromRGB(120, 120, 115), Enum.Material.DiamondPlate)
end

function builders.beam(geo: Instance, e)
	local cf = CFrame.new(e.x, e.y + e.h / 2, e.z) * yaw(e.rot)
	box(geo, "Beam", Vector3.new(e.w, e.h, e.d), cf, Color3.fromRGB(200, 160, 40), Enum.Material.Metal)
end

local function buildElement(geo: Instance, e, style: Random)
	local fn = builders[e.k]
	if fn then
		fn(geo, e, style)
	else
		warn("[MapBuilder] Неизвестный элемент карты: " .. tostring(e.k))
	end
end

------------------------------------------------------------------------
-- Дороги: сглаживание ломаной сплайном Катмулла — Рома

local function catmull(p0, p1, p2, p3, t: number)
	local t2, t3 = t * t, t * t * t
	local out = {}
	for i = 1, 2 do
		out[i] = 0.5 * (2 * p1[i] + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2 + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3)
	end
	return out
end

local function smooth(pts)
	if #pts < 3 then
		return pts
	end
	local out = { pts[1] }
	local n = #pts
	for i = 1, n - 1 do
		local p0 = pts[math.max(i - 1, 1)]
		local p1, p2 = pts[i], pts[i + 1]
		local p3 = pts[math.min(i + 2, n)]
		for k = 1, SMOOTH_STEPS do
			table.insert(out, catmull(p0, p1, p2, p3, k / SMOOTH_STEPS))
		end
	end
	return out
end

local function buildRoad(geo: Instance, pts, w: number, kind: string)
	local style = ROAD_STYLE[kind] or ROAD_STYLE.road
	local y = if kind == "path" then 0.07 else 0.06
	local function piece(name: string, size: Vector3, cf: CFrame, shape: Enum.PartType?)
		local p = make("Part", {
			Name = name,
			Size = size,
			CFrame = cf,
			Color = style.color,
			Material = style.material,
			CanCollide = false, -- ездим по земле, дорога только рисунок
			CanQuery = false,
		}, geo)
		if shape then
			p.Shape = shape
		end
	end
	for i = 1, #pts - 1 do
		local a = Vector3.new(pts[i][1], y, pts[i][2])
		local b = Vector3.new(pts[i + 1][1], y, pts[i + 1][2])
		local len = (b - a).Magnitude
		if len > 0.05 then
			piece("Road", Vector3.new(w, 0.1, len), CFrame.lookAt((a + b) / 2, b))
		end
		-- круглая «заплатка» на стыке, чтобы на поворотах не было зубцов
		if i > 1 then
			piece("RoadJoint", Vector3.new(0.1, w, w), CFrame.new(a) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
		end
	end
end

------------------------------------------------------------------------
-- Холмы из Terrain: профиль (1 + cos) / 2, пологие края, по ним можно въехать

local function buildHill(hill, mat: Enum.Material)
	local terrain = workspace.Terrain
	local steps = math.max(3, math.ceil(hill.h / 1.5))
	for i = 0, steps - 1 do
		local y0, y1 = i * hill.h / steps, (i + 1) * hill.h / steps
		local f = y0 / hill.h
		local radius = hill.r * math.acos(2 * f - 1) / math.pi
		if radius > 1 then
			terrain:FillCylinder(CFrame.new(hill.x, (y0 + y1) / 2, hill.z), y1 - y0, radius, mat)
		end
	end
end

------------------------------------------------------------------------
-- Занятые места: круги (здания, зоны, базы, холмы) и отрезки (дороги)

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

function Occupancy:addSegment(a, b, r: number)
	table.insert(self.segments, { a = Vector2.new(a[1], a[2]), b = Vector2.new(b[1], b[2]), r = r })
end

-- Здание у дороги проверяем по «глубине» (r * 0.55), а не по описанному кругу,
-- иначе дома не встанут вдоль улиц.
function Occupancy:free(x: number, z: number, r: number): boolean
	local p = Vector2.new(x, z)
	for _, c in self.circles do
		if (c.p - p).Magnitude < c.r + r then
			return false
		end
	end
	for _, s in self.segments do
		if distToSegment(p, s.a, s.b) < s.r + r * 0.55 then
			return false
		end
	end
	return true
end

------------------------------------------------------------------------
-- Генераторы застройки: (rng, x, z, rot) -> элементы, радиус занятого места.
-- Порядок вызовов rng должен совпадать с tools/map_layout.py.

local fillers = {}

function fillers.block(rng, x: number, z: number, rot: number)
	local w, d = rng:int(14, 28), rng:int(12, 24)
	local h = rng:int(9, 22)
	local side = ({ "N", "S", "E", "W" })[rng:int(1, 4)]
	local kind = if rng:float() < 0.4 then "stairs" else "ladder"
	return { { k = "block", x = x, z = z, w = w, d = d, h = h, rot = rot, access = { side, kind } } }, math.max(w, d) / 2 + 5
end

function fillers.panel(rng, x: number, z: number, rot: number)
	local w, d = rng:int(36, 56), rng:int(12, 15)
	local h = rng:int(16, 24)
	local side = if rng:float() < 0.5 then "E" else "W"
	return { { k = "block", x = x, z = z, w = w, d = d, h = h, rot = rot, access = { side, "ladder" }, mat = "Concrete" } }, w / 2 + 5
end

function fillers.shell(rng, x: number, z: number, rot: number)
	local w, d = rng:int(16, 28), rng:int(14, 22)
	local h = rng:int(9, 12)
	local sides = { "N", "S", "E", "W" }
	local doors = { sides[rng:int(1, 4)] }
	if rng:float() < 0.6 then
		local second = sides[rng:int(1, 4)]
		if second ~= doors[1] then
			table.insert(doors, second)
		end
	end
	return { { k = "shell", x = x, z = z, w = w, d = d, h = h, rot = rot, doors = doors } }, math.max(w, d) / 2 + 5
end

function fillers.containers(rng, x: number, z: number, rot: number)
	local items = {}
	local n = rng:int(1, 3)
	for i = 1, n do
		local lx, lz = (i - (n + 1) / 2) * 9, rng:range(-3, 3)
		local ox, oz = rotXZ(lx, lz, rot)
		local stack = if rng:float() < 0.35 then 2 else 1
		table.insert(items, { k = "container", x = x + ox, z = z + oz, rot = rot, stack = stack })
	end
	return items, 16
end

function fillers.crates(rng, x: number, z: number, _rot: number)
	local items = {}
	for _ = 1, rng:int(2, 5) do
		table.insert(items, { k = "crate", x = x + rng:range(-6, 6), z = z + rng:range(-6, 6), s = rng:int(3, 4) })
	end
	return items, 9
end

function fillers.shed(rng, x: number, z: number, rot: number)
	return { { k = "block", x = x, z = z, w = 7, d = 7, h = rng:int(5, 7), rot = rot, mat = "WoodPlanks" } }, 7
end

-- Ряд гаражей высотой 5–6: можно подтянуться и бегать по крышам.
function fillers.garages(rng, x: number, z: number, rot: number)
	local n = rng:int(4, 8)
	local w = n * 6
	return { { k = "block", x = x, z = z, w = w, d = 8, h = rng:int(5, 6), rot = rot, mat = "CorrodedMetal" } }, w / 2 + 4
end

-- Дачный участок: забор с калиткой, домик с люком на крышу, иногда сарай.
function fillers.dacha(rng, x: number, z: number, rot: number)
	local W, D = rng:int(26, 34), rng:int(22, 30)
	local gate = rng:range(-W / 2 + 4, W / 2 - 8)
	local hx = rng:range(-3, 3)
	local function p(lx: number, lz: number)
		local ox, oz = rotXZ(lx, lz, rot)
		return { x + ox, z + oz }
	end
	local x0, x1, z0, z1 = -W / 2, W / 2, -D / 2, D / 2
	local house = p(hx, -D / 6)
	local items = {
		{ k = "fence", pts = { p(gate + 5, z1), p(x1, z1), p(x1, z0), p(x0, z0), p(x0, z1), p(gate, z1) } },
		{ k = "shell", x = house[1], z = house[2], w = 12, d = 10, h = 8, rot = rot, doors = { "S" }, mat = "WoodPlanks" },
	}
	if rng:float() < 0.5 then
		local shed = p(x1 - 5, z1 - 6)
		table.insert(items, { k = "block", x = shed[1], z = shed[2], w = 5, d = 5, h = 5, rot = rot, mat = "WoodPlanks" })
	end
	return items, math.max(W, D) / 2 + 5
end

-- Постройки зоны заданы относительно её центра и поворота.
local function zoneLocal(zone, e)
	local zr = zone.rot or 0
	local out = table.clone(e)
	if e.pts then
		out.pts = {}
		for _, pt in e.pts do
			local ox, oz = rotXZ(pt[1], pt[2], zr)
			table.insert(out.pts, { zone.x + ox, zone.z + oz })
		end
	else
		local ox, oz = rotXZ(e.x, e.z, zr)
		out.x, out.z = zone.x + ox, zone.z + oz
		out.rot = (e.rot or 0) + zr
	end
	return out
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


------------------------------------------------------------------------

function MapBuilder.build(mapId: string): Folder
	local cfg = MapsConfig.List[mapId]
	assert(cfg, "Нет карты " .. tostring(mapId))
	local filler = cfg.Filler
	local style = Random.new(filler and filler.Seed or 1) -- только цвета, на расстановку не влияет

	workspace.Terrain:Clear()

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
	box(geo, "Ground", Vector3.new(S, 4, S), CFrame.new(0, -2, 0), color(cfg.Ground.Color) :: Color3, material(cfg.Ground.Material, Enum.Material.Grass))
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

	-- Дороги, грунтовки и тропы.
	local roads = {}
	for _, road in cfg.Roads or {} do
		local pts = smooth(road.pts)
		local kind = road.kind or "road"
		table.insert(roads, { pts = pts, w = road.w })
		buildRoad(geo, pts, road.w, kind)
		for i = 1, #pts - 1 do
			occ:addSegment(pts[i], pts[i + 1], road.w / 2 + 2)
		end
	end

	-- Базы и передовые точки (порядок команд фиксирован, как в схеме).
	for _, teamKey in TeamsConfig.Order do
		local baseCfg = cfg.Bases[teamKey]
		if baseCfg then
			buildBase(map, geo, teamKey, baseCfg, center)
			occ:addCircle(baseCfg.x, baseCfg.z, math.max(BASE_W, BASE_D) / 2 + 20)
			local len = math.sqrt(baseCfg.x ^ 2 + baseCfg.z ^ 2)
			local ux, uz = -baseCfg.x / len, -baseCfg.z / len
			local sx, sz = -uz, ux
			local fx, fz = baseCfg.x * 0.55, baseCfg.z * 0.55
			-- Сдвигаем передовую точку с дороги вбок, если нужно.
			for _, shift in { 0, 30, -30, 55, -55 } do
				local cx, cz = fx + sx * shift, fz + sz * shift
				if occ:free(cx, cz, 14) then
					fx, fz = cx, cz
					break
				end
			end
			buildForward(map, geo, teamKey, Vector3.new(fx, 0, fz), center)
			occ:addCircle(fx, fz, 26)
		end
	end

	-- Холмы.
	local hillMat = material(cfg.HillMaterial, Enum.Material.Grass)
	for _, hill in cfg.Hills or {} do
		buildHill(hill, hillMat)
		occ:addCircle(hill.x, hill.z, hill.r * 0.85)
	end

	-- Зоны каптов и их постройки (заданы относительно центра зоны).
	local points = map:FindFirstChild("CapturePoints") :: Folder
	for _, zone in cfg.Zones do
		local zoneCf = CFrame.new(zone.x, 0.5, zone.z) * yaw(zone.rot)
		local zonePart = make("Part", {
			Name = zone.Name,
			Size = Vector3.new(zone.w, 1, zone.d),
			CFrame = zoneCf,
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
			buildElement(geo, zoneLocal(zone, e), style)
		end
		occ:addCircle(zone.x, zone.z, math.max(zone.w, zone.d) / 2 + 8)
	end

	for _, e in cfg.Extras or {} do
		buildElement(geo, table.clone(e), style)
		occ:addCircle(e.x, e.z, 16)
	end

	-- Застройка: часть домов встаёт вдоль дорог (повёрнута к улице), часть — вразброс
	-- под любым углом. Между ними остаются дворы и переулки.
	if filler then
		local rng = Rng.new(filler.Seed)
		local a = filler.Area
		local placed, tries = 0, 0
		while placed < filler.Count and tries < filler.Count * 50 do
			tries += 1
			local kind = filler.Kinds[rng:int(1, #filler.Kinds)]
			local gen = fillers[kind]
			local seed = rng:int(1, 2 ^ 30)
			local _, radius = gen(Rng.new(seed), 0, 0, 0)
			local x, z, rot
			if #roads > 0 and rng:float() < (filler.StreetShare or 0) then
				local road = roads[rng:int(1, #roads)]
				local pts = road.pts
				local i = rng:int(1, #pts - 1)
				local p1, p2 = pts[i], pts[i + 1]
				local t = rng:float()
				local px, pz = p1[1] + (p2[1] - p1[1]) * t, p1[2] + (p2[2] - p1[2]) * t
				local len = math.sqrt((p2[1] - p1[1]) ^ 2 + (p2[2] - p1[2]) ^ 2)
				if len == 0 then
					len = 1
				end
				local tx, tz = (p2[1] - p1[1]) / len, (p2[2] - p1[2]) / len
				local side = if rng:float() < 0.5 then -1 else 1
				local nx, nz = -tz * side, tx * side
				local dist = road.w / 2 + 3 + radius * 0.55 + rng:float() * 5
				x, z = px + nx * dist, pz + nz * dist
				rot = math.deg(math.atan2(-tz, tx)) + (if side < 0 then 180 else 0)
			else
				x, z = rng:range(a[1], a[3]), rng:range(a[2], a[4])
				rot = rng:range(0, 360)
			end
			if x >= a[1] and x <= a[3] and z >= a[2] and z <= a[4] and occ:free(x, z, radius) then
				local items = gen(Rng.new(seed), x, z, rot)
				for _, e in items do
					buildElement(geo, e, style)
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
