-- Городской трафик: только в режиме «Город» (атрибут ReplicatedStorage.CityLife) и только на карте
-- с папкой Map/City. В боевых режимах машин-NPC нет.
--
-- Как едет машина:
--   * по своей полосе (правостороннее движение, 2 полосы в каждую сторону, CityGrid);
--   * у перекрёстка смотрит на светофор своей оси (World/TrafficLights): на красный и на жёлтый,
--     если успевает остановиться, встаёт у стоп-линии;
--   * поворачивает по плавной кривой: направо из правой полосы, налево из левой, заранее
--     перестраиваясь; при левом повороте пропускает встречных;
--   * впереди по ходу проверяется «коридор» (пространственный запрос): машины, игроки, прохожие,
--     машины игроков. Скорость подбирается так, чтобы успеть остановиться перед ними;
--   * если впереди что-то стоит и не уезжает, перестраивается в соседнюю полосу и объезжает.
-- Машину ведёт сервер через AlignPosition/AlignOrientation (VehicleBuilder.buildTraffic), колёса
-- крутятся по скорости. Настройки — Config/City.Traffic.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared.Config.City)
local CityGrid = require(Shared.CityGrid)
local TrafficLights = require(script.Parent.TrafficLights)
local VehicleBuilder = require(script.Parent.VehicleBuilder)

local Traffic = {}

local Cfg = CityConfig.Traffic
local R = CityConfig.RoadWidth
local N = CityGrid.N
local DIRS = CityGrid.Dirs
local STEP = { N = { 0, -1 }, S = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } }
local STOP_MARGIN = 13 -- от края перекрёстка до бампера стоящей машины (зебра и стоп-линия)
local AI_RATE = 0.1

type Piece = {
	kind: string, -- "seg" | "turn"
	len: number,
	-- seg: ось дороги от a0 по d, полосу задаёт lat
	a0: Vector3?,
	d: Vector3?,
	-- turn: кривая Безье p0 → p1 → p2
	p0: Vector3?,
	p1: Vector3?,
	p2: Vector3?,
}

type Car = {
	model: Model,
	chassis: BasePart,
	align: AlignPosition,
	orient: AlignOrientation,
	motors: { HingeConstraint },
	half: number,
	width: number,
	wheelR: number,
	dir: string, -- направление на текущем отрезке
	i: number, -- перекрёсток, к которому едем
	j: number,
	lane: number,
	lat: number,
	latTarget: number,
	plan: string, -- "S" | "L" | "R" на ближайшем перекрёстке
	nextDir: string,
	piece: Piece,
	s: number,
	v: number,
	obstacle: number, -- расстояние от бампера до препятствия
	blocker: Car?, -- машина трафика впереди (если препятствие — она)
	queued: boolean, -- стоит в очереди у светофора (такую машину не объезжают)
	aiAcc: number,
	stuck: number,
	waitedBehind: number,
	cf: CFrame,
}

local cars: { Car } = {}
local byModel: { [Model]: Car } = {}
local folder: Folder? = nil
local running = false
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
local includeAcc = 0

local function dirName(v: Vector3): string
	for name, d in DIRS do
		if d:Dot(v) > 0.9 then
			return name
		end
	end
	return "N"
end

local function legsOf(i: number, j: number)
	return CityGrid.legs(i, j)
end

-- Отрезок улицы от перекрёстка (i, j) по направлению dir до следующего.
local function segmentPiece(i: number, j: number, dir: string): Piece
	local d = DIRS[dir]
	local a = CityGrid.intersection(i, j)
	return { kind = "seg", len = CityConfig.BlockSize, a0 = a + d * (R / 2), d = d }
end

local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t)
end

local function turnPiece(i: number, j: number, fromDir: string, fromLat: number, toDir: string, toLane: number): Piece
	local c = CityGrid.intersection(i, j)
	local d1, d2 = DIRS[fromDir], DIRS[toDir]
	local p0 = c - d1 * (R / 2) + CityGrid.right(d1) * fromLat
	local p2 = c + d2 * (R / 2) + CityGrid.right(d2) * CityGrid.laneOffset(toLane)
	local p1 = if d1:Dot(d2) > 0.9 then (p0 + p2) / 2 else p0 + d1 * (p2 - p0):Dot(d1)
	local len = 0
	local prev = p0
	for k = 1, 10 do
		local p = bezier(p0, p1, p2, k / 10)
		len += (p - prev).Magnitude
		prev = p
	end
	return { kind = "turn", len = len, p0 = p0, p1 = p1, p2 = p2 }
end

-- Положение и направление на текущем участке.
local function pose(car: Car): (Vector3, Vector3)
	local pc = car.piece
	if pc.kind == "seg" then
		local d = pc.d :: Vector3
		return (pc.a0 :: Vector3) + d * car.s + CityGrid.right(d) * car.lat, d
	end
	local t = math.clamp(car.s / pc.len, 0, 1)
	local p = bezier(pc.p0 :: Vector3, pc.p1 :: Vector3, pc.p2 :: Vector3, t)
	local ahead = bezier(pc.p0 :: Vector3, pc.p1 :: Vector3, pc.p2 :: Vector3, math.min(1, t + 0.02))
	local back = bezier(pc.p0 :: Vector3, pc.p1 :: Vector3, pc.p2 :: Vector3, math.max(0, t - 0.02))
	local tangent = ahead - back
	return p, if tangent.Magnitude > 1e-4 then tangent.Unit else DIRS[car.dir]
end

-- Выбор поворота на перекрёстке (i, j) при движении по dir.
local function choosePlan(i: number, j: number, dir: string): (string, string)
	local legs = legsOf(i, j)
	local d = DIRS[dir]
	local rightDir = dirName(CityGrid.right(d))
	local leftDir = dirName(-CityGrid.right(d))
	local options = {}
	if legs[dir] then
		table.insert(options, { "S", dir, Cfg.TurnChance.Straight })
	end
	if legs[rightDir] then
		table.insert(options, { "R", rightDir, Cfg.TurnChance.Right })
	end
	if legs[leftDir] then
		table.insert(options, { "L", leftDir, Cfg.TurnChance.Left })
	end
	if #options == 0 then
		return "U", CityGrid.Opposite[dir] -- тупика в сетке нет, но на всякий случай
	end
	local total = 0
	for _, o in options do
		total += o[3]
	end
	local r = math.random() * total
	for _, o in options do
		r -= o[3]
		if r <= 0 then
			return o[1], o[2]
		end
	end
	return options[1][1], options[1][2]
end

local function wantLane(car: Car): number
	if car.plan == "R" then
		return CityConfig.LanesPerDirection
	elseif car.plan == "L" then
		return 1
	end
	return car.lane
end

-- Въехали на новый отрезок: следующий перекрёсток и план поворота на нём.
local function enterSegment(car: Car, fromI: number, fromJ: number, dir: string)
	local st = STEP[dir]
	car.dir = dir
	car.i, car.j = fromI + st[1], fromJ + st[2]
	car.piece = segmentPiece(fromI, fromJ, dir)
	car.plan, car.nextDir = choosePlan(car.i, car.j, dir)
end

-- Сигнал для нас на ближайшем перекрёстке: нужно ли вставать у стоп-линии.
local function mustStop(car: Car, distToLine: number): boolean
	local axis = CityGrid.axis(DIRS[car.dir])
	local sig = TrafficLights.get(car.i, car.j, axis)
	if sig == "R" then
		return distToLine > -1
	elseif sig == "Y" then
		return distToLine > car.v * car.v / (2 * Cfg.Decel) + 1
	end
	-- Левый поворот: пропустить встречных, которые едут к этому же перекрёстку.
	if car.plan == "L" and distToLine < 30 then
		local opposite = CityGrid.Opposite[car.dir]
		for _, other in cars do
			if other ~= car and other.dir == opposite and other.i == car.i and other.j == car.j and other.v > 2 then
				local left = other.piece.len - other.s - other.half
				if other.piece.kind == "seg" and left < 55 and other.plan ~= "L" then
					return true
				end
			end
		end
	end
	return false
end

-- Коридор впереди по ходу: ближайшее препятствие (студы от бампера).
local function scanAhead(car: Car, cf: CFrame, lateral: number?): (number, BasePart?)
	local look = math.clamp(8 + car.v * 1.5, 12, 60)
	local center = cf * CFrame.new(lateral or 0, 3, -(car.half + look / 2 + 0.5))
	local hits = workspace:GetPartBoundsInBox(center, Vector3.new(car.width * 0.85, 5, look), overlap)
	local best = math.huge
	local bestPart: BasePart? = nil
	local front = cf * CFrame.new(0, 0, -car.half)
	for _, h in hits do
		if h:IsDescendantOf(car.model) then
			continue
		end
		local rel = front:PointToObjectSpace(h.Position)
		local d = -rel.Z - math.max(h.Size.X, h.Size.Z) / 2
		if d < best then
			best = math.max(0, d)
			bestPart = h
		end
	end
	return best, bestPart
end

-- Свободна ли соседняя полоса рядом и чуть впереди (для перестроения).
local function laneFree(car: Car, cf: CFrame, lateral: number): boolean
	local box = cf * CFrame.new(lateral, 3, -6)
	local hits = workspace:GetPartBoundsInBox(box, Vector3.new(car.width * 0.9, 5, car.half * 2 + 26), overlap)
	for _, h in hits do
		if not h:IsDescendantOf(car.model) then
			return false
		end
	end
	return true
end

local function refreshInclude()
	local list: { Instance } = {}
	if folder then
		table.insert(list, folder)
	end
	local vehicles = workspace:FindFirstChild("Vehicles")
	if vehicles then
		table.insert(list, vehicles)
	end
	local peds = workspace:FindFirstChild("Pedestrians")
	if peds then
		table.insert(list, peds)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	overlap.FilterDescendantsInstances = list
end

local function placeModel(car: Car, pos: Vector3, fwd: Vector3)
	local flat = Vector3.new(fwd.X, 0, fwd.Z)
	if flat.Magnitude < 1e-3 then
		flat = DIRS[car.dir]
	end
	local cf = CFrame.lookAt(Vector3.new(pos.X, 0, pos.Z), Vector3.new(pos.X, 0, pos.Z) + flat.Unit)
	car.cf = cf
	car.align.Position = (cf * CFrame.new(0, car.wheelR, 0)).Position
	car.orient.CFrame = cf.Rotation
end

local function playersNear(pos: Vector3, r: number): boolean
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - pos).Magnitude < r then
			return true
		end
	end
	return false
end

local function spawnCar(): Car?
	if not folder then
		return nil
	end
	for _ = 1, 30 do
		local dirs = { "N", "S", "E", "W" }
		local dir = dirs[math.random(1, 4)]
		local st = STEP[dir]
		-- Отрезок, у которого есть следующий перекрёсток.
		local i, j = math.random(0, N), math.random(0, N)
		local ni, nj = i + st[1], j + st[2]
		if ni < 0 or ni > N or nj < 0 or nj > N then
			continue
		end
		local lane = math.random(1, CityConfig.LanesPerDirection)
		local piece = segmentPiece(i, j, dir)
		local s = math.random(25, math.floor(piece.len - 50))
		local d = DIRS[dir]
		local pos = (piece.a0 :: Vector3) + d * s + CityGrid.right(d) * CityGrid.laneOffset(lane)
		if playersNear(pos, Cfg.SpawnAwayFromPlayers) then
			continue
		end
		local clear = true
		for _, other in cars do
			if (other.cf.Position - pos).Magnitude < 24 then
				clear = false
				break
			end
		end
		if not clear then
			continue
		end
		local typeId = Cfg.Types[math.random(1, #Cfg.Types)]
		local groundCf = CFrame.lookAt(pos, pos + d)
		local ok, model = pcall(VehicleBuilder.buildTraffic, typeId, groundCf, Cfg.Mass)
		if not ok then
			warn("[Traffic] Не удалось собрать машину:", model)
			return nil
		end
		local chassis = model.PrimaryPart :: BasePart
		local motors = {}
		for _, m in (model:FindFirstChild("Drive") :: Folder):GetChildren() do
			if m:IsA("HingeConstraint") then
				table.insert(motors, m)
			end
		end
		local car: Car = {
			model = model,
			chassis = chassis,
			align = chassis:FindFirstChild("Follow") :: AlignPosition,
			orient = chassis:FindFirstChild("Face") :: AlignOrientation,
			motors = motors,
			half = (model:GetAttribute("Length") or 18) / 2,
			width = model:GetAttribute("Width") or 7,
			wheelR = model:GetAttribute("WheelRadius") or 1.3,
			dir = dir,
			i = ni,
			j = nj,
			lane = lane,
			lat = CityGrid.laneOffset(lane),
			latTarget = CityGrid.laneOffset(lane),
			plan = "S",
			nextDir = dir,
			piece = piece,
			s = s,
			v = Cfg.Speed * 0.5,
			obstacle = math.huge,
			blocker = nil,
			queued = false,
			aiAcc = math.random() * AI_RATE,
			stuck = 0,
			waitedBehind = 0,
			cf = groundCf,
		}
		car.plan, car.nextDir = choosePlan(ni, nj, dir)
		model.Parent = folder
		byModel[model] = car
		pcall(function()
			chassis:SetNetworkOwner(nil)
		end)
		placeModel(car, pos, d)
		return car
	end
	return nil
end

local function removeCar(index: number)
	local car = cars[index]
	table.remove(cars, index)
	byModel[car.model] = nil
	if car.model.Parent then
		car.model:Destroy()
	end
end

-- Решения 10 раз в секунду: препятствия, перестроение, «застрял».
local function think(car: Car, step: number)
	local cf = car.cf
	local hit: BasePart?
	car.obstacle, hit = scanAhead(car, cf)
	car.blocker = nil
	if hit and folder and hit:IsDescendantOf(folder) then
		local m = hit:FindFirstAncestorOfClass("Model")
		car.blocker = m and byModel[m]
	end
	if car.piece.kind ~= "seg" then
		car.queued = false
		return
	end
	local distToEnd = car.piece.len - car.s - car.half
	-- В очереди: стоим у стоп-линии или за машиной, которая сама в очереди.
	local stopped = car.v < 1.5
	car.queued = stopped
		and ((distToEnd - STOP_MARGIN < 4 and mustStop(car, distToEnd - STOP_MARGIN)) or (car.blocker ~= nil and (car.blocker :: Car).queued))
	-- Перестроиться под поворот заранее.
	local want = wantLane(car)
	if want ~= car.lane and distToEnd > 25 then
		local lat = CityGrid.laneOffset(want)
		if laneFree(car, cf, lat - car.lat) then
			car.lane = want
			car.latTarget = lat
		end
	end
	-- Объезд: впереди что-то стоит, а мы не у светофора.
	local atLine = distToEnd - STOP_MARGIN < 4
	if car.obstacle < 18 and car.v < 1.5 and not atLine and not car.queued then
		car.waitedBehind += step
	else
		car.waitedBehind = 0
	end
	if car.waitedBehind > 2.5 and distToEnd > 35 then
		local other = if car.lane == 1 then 2 else 1
		local lat = CityGrid.laneOffset(other)
		if laneFree(car, cf, lat - car.lat) and scanAhead(car, cf, lat - car.lat) > 22 then
			car.lane = other
			car.latTarget = lat
			car.waitedBehind = 0
			-- Новый план, раз полоса другая (левая полоса не поворачивает направо и наоборот).
			if (car.plan == "R" and other == 1) or (car.plan == "L" and other ~= 1) then
				car.plan, car.nextDir = "S", car.dir
				local legs = legsOf(car.i, car.j)
				if not legs[car.dir] then
					car.plan, car.nextDir = choosePlan(car.i, car.j, car.dir)
				end
			end
		end
	end
end

local function advance(car: Car, dt: number)
	local pc = car.piece
	-- Целевая скорость.
	local target = if pc.kind == "seg" then Cfg.Speed elseif car.plan == "S" then Cfg.Speed else Cfg.TurnSpeed
	if pc.kind == "seg" then
		local distToEnd = pc.len - car.s - car.half
		local distToLine = distToEnd - STOP_MARGIN
		if mustStop(car, distToLine) then
			target = math.min(target, math.sqrt(2 * Cfg.Decel * math.max(0, distToLine - 0.5)))
		end
		if car.plan ~= "S" then
			target = math.min(target, math.sqrt(Cfg.TurnSpeed ^ 2 + 2 * Cfg.Decel * 0.6 * math.max(0, distToEnd)))
		end
	end
	if car.obstacle < math.huge then
		target = math.min(target, math.sqrt(2 * Cfg.Decel * math.max(0, car.obstacle - 3)))
		if car.obstacle < 3 then
			target = 0
		end
	end
	if target > car.v then
		car.v = math.min(target, car.v + Cfg.Accel * dt)
	else
		car.v = math.max(target, car.v - Cfg.Decel * 1.5 * dt)
	end

	-- Перестроение: плавно вбок.
	local latVel = 0
	if pc.kind == "seg" and car.lat ~= car.latTarget then
		local stepLat = math.clamp(car.latTarget - car.lat, -Cfg.LaneChangeSpeed * dt, Cfg.LaneChangeSpeed * dt)
		car.lat += stepLat
		latVel = stepLat / dt
	end

	car.s += car.v * dt
	while car.s > car.piece.len do
		car.s -= car.piece.len
		if car.piece.kind == "seg" then
			-- Въезжаем на перекрёсток.
			local toLane = if car.plan == "R" then CityConfig.LanesPerDirection elseif car.plan == "L" then 1 else car.lane
			car.piece = turnPiece(car.i, car.j, car.dir, car.lat, car.nextDir, toLane)
			car.lane = toLane
		else
			-- Съехали с перекрёстка на следующую улицу.
			enterSegment(car, car.i, car.j, car.nextDir)
			car.lat = CityGrid.laneOffset(car.lane)
			car.latTarget = car.lat
		end
	end

	local pos, fwd = pose(car)
	if latVel ~= 0 and car.v > 1 then
		fwd = (fwd * car.v + CityGrid.right(fwd) * latVel).Unit
	end
	placeModel(car, pos, fwd)
	-- Колёса: ω = v / r (знак — «вперёд» для оси X).
	local w = -car.v / car.wheelR
	for _, m in car.motors do
		m.AngularVelocity = w
	end
end

local function clearAll()
	for i = #cars, 1, -1 do
		removeCar(i)
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
end

local function shouldRun(): boolean
	local map = workspace:FindFirstChild("Map")
	return ReplicatedStorage:GetAttribute("CityLife") == true and map ~= nil and map:FindFirstChild("City") ~= nil
end

local function startStop()
	local want = shouldRun()
	if want == running then
		return
	end
	running = want
	if not want then
		clearAll()
		return
	end
	local f = Instance.new("Folder")
	f.Name = "Traffic"
	f.Parent = workspace
	folder = f
	refreshInclude()
end

function Traffic.init(mapChanged: RBXScriptSignal)
	ReplicatedStorage:GetAttributeChangedSignal("CityLife"):Connect(startStop)
	mapChanged:Connect(function()
		running = false
		clearAll()
		startStop()
	end)
	startStop()

	local spawnAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		dt = math.min(dt, 0.1)
		includeAcc += dt
		if includeAcc > 1 then
			includeAcc = 0
			refreshInclude()
		end
		-- Досоздаём машины понемногу (не все в одном кадре).
		spawnAcc += dt
		if spawnAcc > 0.3 and #cars < Cfg.Cars then
			spawnAcc = 0
			local car = spawnCar()
			if car then
				table.insert(cars, car)
			end
		end
		for index = #cars, 1, -1 do
			local car = cars[index]
			if not car.model.Parent or not car.chassis.Parent then
				table.remove(cars, index)
				byModel[car.model] = nil
				continue
			end
			car.aiAcc += dt
			if car.aiAcc >= AI_RATE then
				local step = car.aiAcc
				car.aiAcc = 0
				think(car, step)
				-- Застряла (сбили с полосы, упёрлась) или далеко от своей цели — убрать и создать заново.
				if car.v < 0.5 then
					car.stuck += step
				else
					car.stuck = 0
				end
				local off = (car.chassis.Position - car.align.Position).Magnitude
				local tilted = car.chassis.CFrame.UpVector.Y < 0.5
				if (car.stuck > 30 or off > 25 or tilted) and not playersNear(car.chassis.Position, 40) then
					removeCar(index)
					continue
				end
			end
			advance(car, dt)
		end
	end)
end

return Traffic
