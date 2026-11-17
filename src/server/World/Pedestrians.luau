-- Прохожие: только в режиме «Город» (атрибут ReplicatedStorage.CityLife) на карте с папкой Map/City.
-- В TDM, капте и других боевых режимах их нет.
--
-- Каждый прохожий — R15-персонаж с повседневной одеждой (Config/City.Pedestrians.Wear).
-- Где ходят: линия вдоль тротуара каждого квартала, узлы — четыре угла квартала.
--   * На углу выбирает: дойти до соседнего угла (путь строит PathfindingService, обходит киоски,
--     остановки, деревья), перейти улицу по зебре или посидеть на скамейке поблизости.
--   * Перейти улицу: ждёт у бордюра, пока у перехода горит «идите» (World/TrafficLights.walkLeft)
--     и его хватит, чтобы дойти. Где светофора нет — пока рядом нет едущих машин.
--   * Встретил другого прохожего — иногда останавливается поболтать: поворачиваются друг к другу,
--     машут рукой, смеются.
--   * Уступает дорогу: если впереди человек, обходит его сбоку.
--   * Машина едет прямо на него — отскакивает в сторону и пугается.
--   * Слышит выстрел — бежит прочь от стрелка, пока не успокоится.
-- Машины трафика (World/Traffic) видят прохожих и тормозят перед ними.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared.Config.City)
local CityGrid = require(Shared.CityGrid)
local AppearanceApply = require(Shared.AppearanceApply)
local CharacterLook = require(Shared.CharacterLook)
local TrafficLights = require(script.Parent.TrafficLights)

local Pedestrians = {}

local Cfg = CityConfig.Pedestrians
local B = CityConfig.BlockSize
local R = CityConfig.RoadWidth
local CH = CityConfig.CurbHeight
local N = CityGrid.N
local W = Cfg.WalkLine
local THINK = 0.15

local ANIMS = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	sit = "rbxassetid://2506281703",
	wave = "rbxassetid://507770239",
	laugh = "rbxassetid://507770818",
}

type Node = { col: number, row: number, sx: number, sz: number }

type Ped = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	tracks: { [string]: AnimationTrack },
	current: string?,
	speed: number,
	node: Node,
	state: string, -- "idle" | "walk" | "wait" | "cross" | "sit" | "talk" | "panic"
	route: { Vector3 },
	routeAt: number, -- когда в последний раз вызвали MoveTo
	stuckPos: Vector3,
	stuckT: number,
	untilT: number, -- конец сидения, разговора, испуга
	seat: Seat?,
	partner: Ped?,
	lastTalk: number,
	crossing: { i: number, j: number, axis: string, to: Node, from: Vector3, over: Vector3 }?,
	busy: boolean, -- ждёт путь от PathfindingService
	acc: number,
}

local peds: { Ped } = {}
local folder: Folder? = nil
local running = false
local spawning = false
local generation = 0

------------------------------------------------------------------------
-- Геометрия тротуаров.

local function corner(n: Node): Vector3
	local bc = CityGrid.blockCenter(n.col, n.row)
	return Vector3.new(bc.X + n.sx * (B / 2 - W), CH, bc.Z + n.sz * (B / 2 - W))
end

-- Ближайший к точке угол квартала.
local function nearestNode(p: Vector3): Node
	local best: Node = { col = 1, row = 1, sx = 1, sz = 1 }
	local bestD = math.huge
	for col = 1, N do
		for row = 1, N do
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local n = { col = col, row = row, sx = sx, sz = sz }
					local d = (corner(n) - p).Magnitude
					if d < bestD then
						best, bestD = n, d
					end
				end
			end
		end
	end
	return best
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rand(range: { number }): number
	return range[1] + math.random() * (range[2] - range[1])
end

------------------------------------------------------------------------
-- Внешность и анимации.

local function pickWear(list: { string }): string
	return list[math.random(1, #list)]
end

local function buildModel(): Model?
	local wear = Cfg.Wear
	local outfit = {
		Top = pickWear(wear.Top),
		Bottom = pickWear(wear.Bottom),
		Shoes = pickWear(wear.Shoes),
		Hat = if math.random() < wear.HatChance then pickWear(wear.Hat) else "none",
	}
	local look = AppearanceApply.randomLook()
	local desc = AppearanceApply.describe(look, "Bandits", outfit, nil)
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
	if not ok then
		warn("[Pedestrians] Внешность не загрузилась:", model)
		ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		if not ok then
			return nil
		end
	end
	return model
end

local function loadTracks(model: Model, hum: Humanoid): { [string]: AnimationTrack }
	local ids = table.clone(ANIMS)
	for name, animId in CharacterLook.botAnimations() do
		if name == "idle" or name == "walk" or name == "run" then
			ids[name] = animId
		end
	end
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy() -- LocalScript у NPC не работает: анимации играет сервер
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local tracks = {}
	for name, id in ids do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, anim)
		if ok and track then
			local gesture = name == "wave" or name == "laugh"
			track.Looped = not gesture
			track.Priority = if gesture then Enum.AnimationPriority.Action else Enum.AnimationPriority.Core
			tracks[name] = track
		end
	end
	return tracks
end

local function animate(p: Ped)
	local speed = flat(p.root.AssemblyLinearVelocity).Magnitude
	local want = if p.hum.Sit then "sit" elseif speed > 11 then "run" elseif speed > 0.8 then "walk" else "idle"
	if want ~= p.current then
		local old = p.current and p.tracks[p.current]
		if old then
			old:Stop(0.25)
		end
		local new = p.tracks[want]
		if new then
			new:Play(0.25)
		end
		p.current = want
	end
	local track = p.tracks[want]
	if track and want == "walk" then
		-- Шаг анимации ходьбы рассчитан примерно на 7 студ/с: так ноги не «скользят».
		track:AdjustSpeed(math.clamp(speed / 7, 0.6, 1.4))
	elseif track and want == "run" then
		track:AdjustSpeed(math.clamp(speed / 18, 0.6, 1.3))
	end
end

local function gesture(p: Ped, name: string)
	local t = p.tracks[name]
	if t then
		t:Play(0.2)
	end
end

------------------------------------------------------------------------
-- Движение.

local function stand(p: Ped)
	table.clear(p.route)
	p.hum:MoveTo(p.root.Position)
end

local function setRoute(p: Ped, points: { Vector3 })
	p.route = points
	p.routeAt = 0
	p.stuckT = 0
	p.stuckPos = p.root.Position
end

-- Путь по тротуару через PathfindingService (в отдельном потоке). Не нашёлся — идём напрямую.
local agentParams = {
	AgentRadius = 1.5,
	AgentHeight = 5.5,
	AgentCanJump = false,
	WaypointSpacing = 8,
	Costs = { Water = 20 },
}
local function pathTo(p: Ped, target: Vector3, after: { Vector3 }?, onReady: (() -> ())?)
	p.busy = true
	local gen = generation
	task.spawn(function()
		local path = PathfindingService:CreatePath(agentParams)
		local ok = pcall(path.ComputeAsync, path, p.root.Position, target)
		if gen ~= generation or not p.model.Parent then
			return
		end
		p.busy = false
		local points = {}
		if ok and path.Status == Enum.PathStatus.Success then
			local wps = path:GetWaypoints()
			for k = 2, #wps do
				table.insert(points, wps[k].Position)
			end
		end
		if #points == 0 then
			points = { target }
		end
		for _, extra in after or {} do
			table.insert(points, extra)
		end
		setRoute(p, points)
		if onReady then
			onReady()
		end
	end)
end

-- Обход людей впереди: цель сдвигается вбок.
local function avoid(p: Ped, target: Vector3): Vector3
	local pos = p.root.Position
	local to = flat(target - pos)
	if to.Magnitude < 0.5 then
		return target
	end
	local fwd = to.Unit
	local right = Vector3.new(-fwd.Z, 0, fwd.X)
	local function check(other: BasePart)
		local rel = flat(other.Position - pos)
		local ahead = rel:Dot(fwd)
		local side = rel:Dot(right)
		if ahead > 0.5 and ahead < 5 and math.abs(side) < 2.4 then
			return if side > 0 then -1 else 1
		end
		return 0
	end
	local shift = 0
	for _, o in peds do
		if o ~= p and o.root.Parent then
			shift += check(o.root)
		end
	end
	for _, pl in Players:GetPlayers() do
		local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			shift += check(r)
		end
	end
	if shift == 0 then
		return target
	end
	return pos + fwd * 4 + right * math.sign(shift) * 2.6
end

------------------------------------------------------------------------
-- Решения на углу.

local function freeSeatNear(pos: Vector3, radius: number): Seat?
	local map = workspace:FindFirstChild("Map")
	local city = map and map:FindFirstChild("City")
	local seats = city and city:FindFirstChild("SitPoints")
	if not seats then
		return nil
	end
	local options = {}
	for _, s in seats:GetChildren() do
		if s:IsA("Seat") and s.Occupant == nil and not s:GetAttribute("Reserved") and (s.Position - pos).Magnitude < radius then
			table.insert(options, s)
		end
	end
	if #options == 0 then
		return nil
	end
	return options[math.random(1, #options)]
end

local function walkAlong(p: Ped)
	local n = p.node
	local nextNode: Node = if math.random() < 0.5
		then { col = n.col, row = n.row, sx = -n.sx, sz = n.sz }
		else { col = n.col, row = n.row, sx = n.sx, sz = -n.sz }
	p.state = "walk"
	p.node = nextNode
	pathTo(p, corner(nextNode))
end

-- Переход через улицу: по X (к соседнему кварталу по столбцу) или по Z.
local function startCross(p: Ped): boolean
	local n = p.node
	local options = {}
	if n.col + n.sx >= 1 and n.col + n.sx <= N then
		table.insert(options, "X")
	end
	if n.row + n.sz >= 1 and n.row + n.sz <= N then
		table.insert(options, "Z")
	end
	if #options == 0 then
		return false
	end
	local which = options[math.random(1, #options)]
	local i = if n.sx > 0 then n.col else n.col - 1
	local j = if n.sz > 0 then n.row else n.row - 1
	local c = corner(n)
	local to: Node, dir: Vector3, axis: string
	if which == "X" then
		to = { col = n.col + n.sx, row = n.row, sx = -n.sx, sz = n.sz }
		dir = Vector3.new(n.sx, 0, 0)
		axis = "NS" -- переходим улицу, идущую с севера на юг
	else
		to = { col = n.col, row = n.row + n.sz, sx = n.sx, sz = -n.sz }
		dir = Vector3.new(0, 0, n.sz)
		axis = "EW"
	end
	local curb = c + dir * (W - 1.5) -- у края тротуара
	local over = corner(to) - dir * (W - 1.5)
	p.crossing = { i = i, j = j, axis = axis, to = to, from = curb, over = over }
	p.state = "wait"
	setRoute(p, { curb })
	return true
end

local function carsNear(pos: Vector3, radius: number): boolean
	for _, name in { "Traffic", "Vehicles" } do
		local f = workspace:FindFirstChild(name)
		if f then
			for _, m in f:GetChildren() do
				local root = m:IsA("Model") and m.PrimaryPart
				if root and (root.Position - pos).Magnitude < radius and root.AssemblyLinearVelocity.Magnitude > 3 then
					return true
				end
			end
		end
	end
	return false
end

local function canGo(p: Ped): boolean
	local c = p.crossing
	if not c then
		return false
	end
	local left = TrafficLights.walkLeft(c.i, c.j, c.axis)
	if left == nil then
		-- Нерегулируемый угол: смотрим на машины.
		return not carsNear((c.from + c.over) / 2, 40)
	end
	return left >= Cfg.CrossMinWalk
end

local function sitDown(p: Ped): boolean
	local seat = freeSeatNear(p.root.Position, 70)
	if not seat then
		return false
	end
	seat:SetAttribute("Reserved", true)
	p.seat = seat
	p.state = "sit"
	p.untilT = math.huge
	local front = seat.CFrame * CFrame.new(0, 0, -2.2)
	pathTo(p, front.Position)
	return true
end

local function releaseSeat(p: Ped)
	local seat = p.seat
	if not seat then
		return
	end
	p.seat = nil
	seat:SetAttribute("Reserved", nil)
	if p.hum.SeatPart == seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		p.hum.Sit = false
		p.hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function decide(p: Ped)
	local r = math.random()
	local ch = Cfg.Choice
	local total = ch.Walk + ch.Cross + ch.Sit
	r *= total
	if r < ch.Sit and sitDown(p) then
		return
	end
	if r < ch.Sit + ch.Cross and startCross(p) then
		return
	end
	walkAlong(p)
end

local function backToSidewalk(p: Ped)
	p.node = nearestNode(p.root.Position)
	p.state = "walk"
	pathTo(p, corner(p.node))
end

------------------------------------------------------------------------
-- Реакции.

local function panic(p: Ped, from: Vector3, seconds: number)
	if p.state == "talk" and p.partner then
		local other = p.partner
		p.partner = nil
		if other.partner == p then
			other.partner = nil
			other.state = "idle"
			other.hum.AutoRotate = true
		end
	end
	p.hum.AutoRotate = true
	releaseSeat(p)
	p.crossing = nil
	p.state = "panic"
	p.untilT = os.clock() + seconds
	p.hum.WalkSpeed = Cfg.RunSpeed
	-- Бежим к самому дальнему от опасности углу поблизости (по тротуару).
	local pos = p.root.Position
	local best, bestScore = nil, -math.huge
	for col = math.max(1, p.node.col - 1), math.min(N, p.node.col + 1) do
		for row = math.max(1, p.node.row - 1), math.min(N, p.node.row + 1) do
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local n = { col = col, row = row, sx = sx, sz = sz }
					local c = corner(n)
					local away = (c - from).Magnitude
					local trip = (c - pos).Magnitude
					if trip < 200 then
						local score = away - trip * 0.4
						if score > bestScore then
							best, bestScore = n, score
						end
					end
				end
			end
		end
	end
	if best then
		p.node = best
		pathTo(p, corner(best))
	end
end

-- Машина едет прямо на прохожего: отскок вбок.
local function dodgeCars(p: Ped): boolean
	local pos = p.root.Position
	for _, name in { "Traffic", "Vehicles" } do
		local f = workspace:FindFirstChild(name)
		if not f then
			continue
		end
		for _, m in f:GetChildren() do
			local root = m:IsA("Model") and m.PrimaryPart
			if not root then
				continue
			end
			local v = flat(root.AssemblyLinearVelocity)
			local speed = v.Magnitude
			if speed < 8 then
				continue
			end
			local rel = flat(pos - root.Position)
			local dir = v.Unit
			local ahead = rel:Dot(dir)
			local side = rel:Dot(Vector3.new(-dir.Z, 0, dir.X))
			local halfW = (m:GetAttribute("Width") or 7) / 2 + 1.5
			if ahead > 0 and ahead < Cfg.DodgeDistance + speed * 0.4 and math.abs(side) < halfW then
				local away = Vector3.new(-dir.Z, 0, dir.X) * (if side >= 0 then 1 else -1)
				releaseSeat(p)
				p.crossing = nil
				p.state = "panic"
				p.untilT = os.clock() + 4
				p.hum.WalkSpeed = Cfg.RunSpeed
				p.hum.Jump = true
				setRoute(p, { pos + away * (halfW + 4) })
				return true
			end
		end
	end
	return false
end

local function tryTalk(p: Ped, now: number)
	if now - p.lastTalk < Cfg.TalkCooldown then
		return
	end
	for _, o in peds do
		if o ~= p and o.state == "walk" and not o.busy and now - o.lastTalk >= Cfg.TalkCooldown then
			local d = (o.root.Position - p.root.Position).Magnitude
			if d < 7 then
				p.lastTalk, o.lastTalk = now, now -- решаем один раз за встречу
				if math.random() < Cfg.TalkChance then
					local t = now + rand(Cfg.TalkTime)
					for _, x in { p, o } do
						x.state = "talk"
						x.partner = if x == p then o else p
						x.untilT = t
						x.hum.AutoRotate = false
						stand(x)
					end
					gesture(p, "wave")
					task.delay(0.6, gesture, o, "wave")
					task.delay(rand({ 2, 4 }), gesture, o, "laugh")
				end
				return
			end
		end
	end
end

local function face(p: Ped, at: Vector3)
	local pos = p.root.Position
	local look = flat(at - pos)
	if look.Magnitude > 0.1 then
		local target = CFrame.lookAt(pos, pos + look)
		p.root.CFrame = p.root.CFrame:Lerp(target, 0.25)
	end
end

------------------------------------------------------------------------
-- Цикл одного прохожего.

local function step(p: Ped, now: number, dt: number)
	if p.busy then
		return
	end
	local hum = p.hum
	if p.state ~= "panic" and p.state ~= "sit" and dodgeCars(p) then
		return
	end

	-- Идём по маршруту.
	if #p.route > 0 then
		local target = p.route[1]
		local d = flat(target - p.root.Position).Magnitude
		if d < (if #p.route == 1 then 1.6 else 3) then
			table.remove(p.route, 1)
			p.routeAt = 0
		else
			if now - p.routeAt > 1 then
				p.routeAt = now
				hum:MoveTo(avoid(p, target))
			end
			-- Застрял: подпрыгнуть, потом пропустить точку, потом начать с ближайшего угла.
			if (p.root.Position - p.stuckPos).Magnitude > 1.5 then
				p.stuckPos = p.root.Position
				p.stuckT = 0
			else
				p.stuckT += dt
				if p.stuckT > 3 and p.stuckT - dt <= 3 then
					hum.Jump = true
				elseif p.stuckT > 7 then
					table.remove(p.route, 1)
					p.stuckT = 0
				end
			end
		end
		if p.state == "walk" then
			tryTalk(p, now)
		end
		if p.state ~= "cross" or #p.route > 0 then
			return
		end
	end

	-- Маршрут пройден: что дальше.
	local state = p.state
	if state == "walk" or state == "idle" then
		if p.state == "walk" and math.random() < 0.15 then
			-- Иногда просто постоять на углу.
			p.state = "idle"
			p.untilT = now + rand({ 1.5, 5 })
			stand(p)
		elseif now >= p.untilT then
			decide(p)
		end
	elseif state == "wait" then
		if p.crossing then
			face(p, p.crossing.over)
			if canGo(p) then
				p.state = "cross"
				setRoute(p, { p.crossing.over, corner(p.crossing.to) })
			end
		else
			p.state = "idle"
		end
	elseif state == "cross" then
		if p.crossing then
			p.node = p.crossing.to
			p.crossing = nil
		end
		p.state = "walk"
	elseif state == "sit" then
		local seat = p.seat
		if not seat or not seat.Parent then
			releaseSeat(p)
			backToSidewalk(p)
		elseif hum.SeatPart ~= seat then
			if seat.Occupant and seat.Occupant ~= hum then
				-- Пока шли, сел кто-то другой.
				releaseSeat(p)
				backToSidewalk(p)
			elseif (seat.Position - p.root.Position).Magnitude < 6 then
				seat:Sit(hum)
				p.untilT = now + rand(Cfg.SitTime)
			else
				setRoute(p, { seat.Position })
			end
		elseif now >= p.untilT then
			releaseSeat(p)
			backToSidewalk(p)
		end
	elseif state == "talk" then
		local o = p.partner
		if o and o.partner == p and o.root.Parent then
			face(p, o.root.Position)
		end
		if now >= p.untilT or not o then
			p.partner = nil
			hum.AutoRotate = true
			p.state = "walk"
			p.untilT = 0
			decide(p)
		end
	elseif state == "panic" then
		if now >= p.untilT then
			hum.WalkSpeed = p.speed
			backToSidewalk(p)
		end
	end
end

------------------------------------------------------------------------
-- Появление и удаление.

local function playersNear(pos: Vector3, r: number): boolean
	for _, pl in Players:GetPlayers() do
		local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - pos).Magnitude < r then
			return true
		end
	end
	return false
end

local function spawnPed()
	local gen = generation
	local node: Node? = nil
	for _ = 1, 20 do
		local n = { col = math.random(1, N), row = math.random(1, N), sx = if math.random() < 0.5 then -1 else 1, sz = if math.random() < 0.5 then -1 else 1 }
		local lot = CityGrid.lot(n.col, n.row)
		if string.sub(lot, 1, 5) ~= "base:" and not playersNear(corner(n), Cfg.SpawnAwayFromPlayers) then
			node = n
			break
		end
	end
	if not node then
		return
	end
	local model = buildModel()
	if not model then
		return
	end
	if gen ~= generation or not folder then
		model:Destroy()
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	if not hum or not root then
		model:Destroy()
		return
	end
	model.Name = "Pedestrian"
	model:SetAttribute("Pedestrian", true)
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	local speed = rand(Cfg.WalkSpeed)
	hum.WalkSpeed = speed
	local pos = corner(node) + Vector3.new(math.random() * 4 - 2, 0, math.random() * 4 - 2)
	model:PivotTo(CFrame.new(pos + Vector3.new(0, hum.HipHeight + root.Size.Y / 2 + 0.2, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local p: Ped = {
		model = model,
		hum = hum,
		root = root,
		tracks = loadTracks(model, hum),
		current = nil,
		speed = speed,
		node = node,
		state = "idle",
		route = {},
		routeAt = 0,
		stuckPos = root.Position,
		stuckT = 0,
		untilT = os.clock() + math.random() * 3,
		seat = nil,
		partner = nil,
		lastTalk = os.clock() - math.random() * Cfg.TalkCooldown,
		crossing = nil,
		busy = false,
		acc = math.random() * THINK,
	}
	table.insert(peds, p)
end

local function removePed(index: number)
	local p = peds[index]
	table.remove(peds, index)
	releaseSeat(p)
	if p.partner and p.partner.partner == p then
		p.partner.partner = nil
	end
	if p.model.Parent then
		p.model:Destroy()
	end
end

local function clearAll()
	generation += 1
	for i = #peds, 1, -1 do
		removePed(i)
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
	f.Name = "Pedestrians"
	f.Parent = workspace
	folder = f
end

-- Выстрел: прохожие в радиусе слышимости разбегаются.
function Pedestrians.heardShot(origin: Vector3)
	if not running then
		return
	end
	for _, p in peds do
		local d = (p.root.Position - origin).Magnitude
		if d < Cfg.PanicRadius and p.root.Parent then
			if p.state ~= "panic" then
				task.delay(d / 200 + math.random() * 0.4, function()
					if p.model.Parent then
						panic(p, origin, Cfg.PanicTime + math.random() * 4)
					end
				end)
			else
				p.untilT = math.max(p.untilT, os.clock() + Cfg.PanicTime)
			end
		end
	end
end

function Pedestrians.init(mapChanged: RBXScriptSignal)
	ReplicatedStorage:GetAttributeChangedSignal("CityLife"):Connect(startStop)
	mapChanged:Connect(function()
		running = false
		clearAll()
		startStop()
	end)
	startStop()

	RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		dt = math.min(dt, 0.1)
		if #peds < Cfg.Count and not spawning then
			spawning = true
			task.spawn(function()
				pcall(spawnPed)
				task.wait(0.4)
				spawning = false
			end)
		end
		local now = os.clock()
		for index = #peds, 1, -1 do
			local p = peds[index]
			if not p.model.Parent or not p.root.Parent or p.hum.Health <= 0 or p.root.Position.Y < -50 then
				removePed(index)
				continue
			end
			p.acc += dt
			if p.acc >= THINK then
				local stepDt = p.acc
				p.acc = 0
				step(p, now, stepDt)
				animate(p)
			end
		end
	end)
end

return Pedestrians
