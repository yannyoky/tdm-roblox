-- Боты. Бот — это таблица-«боец» с полями как у игрока, которые нужны матчу:
--   IsBot, Id, Name, DisplayName, UserId (отрицательный), TeamKey, Character
-- MatchService создаёт и удаляет ботов, BotService строит им тела и управляет ими.
--
-- ИИ разделён на два слоя:
--   think (раз в ThinkInterval) — решает, что делать: цель, укрытие, точка захвата, проверка
--     звуков и урона, поиск пути через PathfindingService;
--   step (каждый кадр) — плавно ведёт бота: идёт по точкам пути, сглаживает направление,
--     поворачивает корпус через AlignOrientation, целится и стреляет очередями.
-- Так бот не дёргается: направление и поворот меняются плавно, путь не пересчитывается
-- без нужды, а пока считается новый, бот идёт по старому.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BotsConfig = require(Shared.Config.Bots)
local TeamsConfig = require(Shared.Config.Teams)
local Weapons = require(Shared.Config.Weapons)
local Combat = require(Shared.Config.Combat)
local CrouchPose = require(Shared.CrouchPose)

local WeaponService = require(script.Parent.WeaponService)
local PhysicsSetup = require(script.Parent.PhysicsSetup)
local SkinService = require(script.Parent.SkinService)
local DamageService = require(script.Parent.DamageService)
local GrenadeService = require(script.Parent.GrenadeService)

local BotService = {}

local bots = {} -- список живых объектов-ботов
local byModel = setmetatable({}, { __mode = "k" }) -- [Model] = бот
local nextId = 0
local usedNames = {}

local BASE_SPEED = 16
local UP = Vector3.yAxis
local PATH_PARAMS = {
	AgentRadius = 1.6,
	AgentHeight = 5.5,
	AgentCanJump = true,
	AgentCanClimb = true,
	WaypointSpacing = 5,
	Costs = { Water = 20, Climb = 4 },
}

-- Стандартные анимации R15 (если у модели нет своего Animate).
local DEFAULT_ANIMS = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
	climb = "rbxassetid://507765644",
	toolnone = "rbxassetid://507768375",
}

-- Хуки от MatchService.
local hooks = {
	getEnemies = function(_bot)
		return {}
	end, -- список бойцов-врагов
	getAllies = function(_bot)
		return {}
	end, -- список бойцов своей команды
	isAlive = function(_entity)
		return false
	end,
	getObjective = function(_bot): Vector3?
		return nil
	end,
	onDied = function(_bot, _hum) end,
	teamOf = function(_entity): string?
		return nil
	end,
	idOf = function(_entity): string
		return ""
	end,
}

function BotService.setHooks(newHooks)
	for k, v in newHooks do
		hooks[k] = v
	end
end

------------------------------------------------------------------------
-- Мелкие помощники

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rand(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function unitOr(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > 1e-3 then v.Unit else fallback
end

local function charParts(entity)
	local char = entity.Character
	if not char then
		return nil, nil, nil
	end
	return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

-- Лучи «по миру»: сквозь всех бойцов (их список обновляется каждый такт think).
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.IgnoreWater = true

local function refreshWorldParams()
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, bot in bots do
		if bot.Character then
			table.insert(list, bot.Character)
		end
	end
	worldParams.FilterDescendantsInstances = list
end

-- Свободна ли линия по земле от точки from (корень бота) до точки на земле to:
-- проверяем на высоте колен и пояса, чтобы не срезать углы сквозь ящики и стены.
local function clearWalk(from: Vector3, to: Vector3): boolean
	local feet = from.Y - 3
	for _, h in { 1.7, 3.6 } do
		local a = Vector3.new(from.X, feet + h, from.Z)
		local b = Vector3.new(to.X, to.Y + h, to.Z)
		local dir = b - a
		if dir.Magnitude > 0.1 and workspace:Spherecast(a, 0.9, dir, worldParams) then
			return false
		end
	end
	return true
end

-- Можно ли сделать пару шагов в направлении dir: нет стены и есть земля.
local function canStep(root: BasePart, dir: Vector3, dist: number?): boolean
	local d = dist or 4
	if dir.Magnitude < 0.1 then
		return true
	end
	local unit = dir.Unit
	if workspace:Raycast(root.Position - Vector3.new(0, 1.3, 0), unit * d, worldParams) then
		return false
	end
	local ahead = root.Position + unit * d
	return workspace:Raycast(ahead, Vector3.new(0, -9, 0), worldParams) ~= nil
end

------------------------------------------------------------------------
-- Создание и появление

local function pickName(): string
	for _ = 1, 20 do
		local name = BotsConfig.Names[math.random(#BotsConfig.Names)]
		if not usedNames[name] then
			usedNames[name] = true
			return name
		end
	end
	return "Боец " .. nextId
end

local function resetState(bot)
	bot.target = nil
	bot.visible = false
	bot.lastSeenPos = nil
	bot.lastSeenTime = -math.huge
	bot.lastLostTarget = nil
	bot.reactAt = 0
	bot.engagedAt = 0
	bot.aimPoint = nil
	bot.aimOffset = Vector3.zero
	bot.aimOffsetTime = 0
	bot.aimHead = false
	bot.burstLeft = 0
	bot.nextShot = 0

	bot.waypoints = nil
	bot.wpIndex = 1
	bot.pathGoal = nil
	bot.pathTime = -math.huge
	bot.pathFails = 0
	bot.computing = false
	bot.jumpedWp = 0
	bot.lastPathDir = nil
	bot.navGoal = nil
	bot.arrive = 3
	bot.directDir = nil

	bot.moveMode = "stop" -- "stop" | "path" | "dir"
	bot.moveDir = Vector3.zero
	bot.smoothMove = Vector3.zero
	bot.sep = Vector3.zero
	bot.face = nil
	bot.speedMode = "walk" -- "walk" | "sprint" | "crouch"
	bot.stamina = BotsConfig.SprintStamina
	bot.crouched = false
	bot.crouchDrop = 0
	bot.tired = false

	bot.alertPos = nil
	bot.alertTime = -math.huge
	bot.lastHealth = nil
	bot.hurtAt = -math.huge

	bot.coverPos = nil
	bot.coverUntil = 0
	bot.coverCooldown = 0
	bot.holdLook = nil
	bot.holdLookTime = 0

	bot.strafeDir = if math.random() < 0.5 then -1 else 1
	bot.strafeTime = 0
	bot.stuckTime = 0
	bot.unstickUntil = 0
	bot.unstickDir = Vector3.zero
	bot.reviveTime = 0
	bot.flank = (math.random() * 2 - 1) * BotsConfig.FlankOffset
end

function BotService.create(teamKey: string)
	nextId += 1
	local name = pickName()
	local bot = {
		IsBot = true,
		Id = nextId,
		Name = name,
		DisplayName = "[Бот] " .. name,
		UserId = -nextId,
		TeamKey = teamKey,
		Character = nil :: Model?,
		WeaponId = BotsConfig.PrimaryWeapons[math.random(#BotsConfig.PrimaryWeapons)],
	}
	resetState(bot)
	table.insert(bots, bot)
	return bot
end

function BotService.despawn(bot)
	if bot.Character then
		byModel[bot.Character] = nil
		bot.Character:Destroy()
		bot.Character = nil
	end
	if bot.pathObj then
		bot.pathObj:Destroy()
		bot.pathObj = nil
	end
	bot.hum, bot.root, bot.head, bot.align, bot.anim, bot.tool = nil, nil, nil, nil, nil, nil
end

function BotService.remove(bot)
	BotService.despawn(bot)
	usedNames[bot.Name] = nil
	local index = table.find(bots, bot)
	if index then
		table.remove(bots, index)
	end
end

function BotService.all()
	return bots
end

function BotService.fromCharacter(model: Model)
	return byModel[model]
end

local function buildCharacter(bot): Model
	local color = TeamsConfig.List[bot.TeamKey].Color
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = Color3.fromRGB(234, 184, 146)
	desc.LeftArmColor = desc.HeadColor
	desc.RightArmColor = desc.HeadColor
	desc.TorsoColor = color
	desc.LeftLegColor = color:Lerp(Color3.new(0, 0, 0), 0.5)
	desc.RightLegColor = desc.LeftLegColor
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	SkinService.applyToBot(model, bot.TeamKey)
	model.Name = bot.DisplayName
	model:SetAttribute("BotId", bot.Id)
	model:SetAttribute("TeamKey", bot.TeamKey)
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayName = bot.DisplayName
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	return model
end

-- Анимации на сервере: у NPC LocalScript Animate не работает, поэтому без этого боты
-- «скользят» по земле статуями. Треки, запущенные сервером, видят все игроки.
local function setupAnimations(bot, model: Model, hum: Humanoid)
	local ids = table.clone(DEFAULT_ANIMS)
	local animate = model:FindFirstChild("Animate")
	if animate and animate.ClassName == "Script" then
		return -- серверный Animate работает сам
	end
	if animate then
		for name in ids do
			local holder = animate:FindFirstChild(name)
			local anim = holder and holder:FindFirstChildOfClass("Animation")
			if anim and anim.AnimationId ~= "" then
				ids[name] = anim.AnimationId
			end
		end
		animate:Destroy()
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
			track.Looped = name ~= "jump"
			track.Priority = if name == "toolnone" then Enum.AnimationPriority.Action else Enum.AnimationPriority.Core
			tracks[name] = track
		end
	end
	bot.anim = { tracks = tracks, current = nil }
end

local function updateAnimation(bot, hum: Humanoid, root: BasePart, downed: boolean)
	local a = bot.anim
	if not a then
		return
	end
	local tracks = a.tracks
	local holdTool = not downed and bot.Character and bot.Character:FindFirstChildOfClass("Tool") ~= nil
	local toolTrack = tracks.toolnone
	if toolTrack then
		if holdTool and not toolTrack.IsPlaying then
			toolTrack:Play(0.2)
		elseif not holdTool and toolTrack.IsPlaying then
			toolTrack:Stop(0.2)
		end
	end

	local state = hum:GetState()
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	local want
	if downed then
		want = nil
	elseif state == Enum.HumanoidStateType.Climbing then
		want = "climb"
	elseif state == Enum.HumanoidStateType.Jumping then
		want = "jump"
	elseif state == Enum.HumanoidStateType.Freefall then
		want = "fall"
	elseif speed > 1 then
		want = if speed > BASE_SPEED * 1.2 then "run" else "walk"
	else
		want = "idle"
	end
	if want ~= a.current then
		local old = a.current and tracks[a.current]
		if old then
			old:Stop(0.2)
		end
		local new = want and tracks[want]
		if new then
			new:Play(if want == "jump" then 0.1 else 0.2)
		end
		a.current = want
	end
	local track = want and tracks[want]
	if track then
		if want == "walk" then
			track:AdjustSpeed(math.clamp(speed / 14.5, 0.3, 1.6))
		elseif want == "run" then
			track:AdjustSpeed(math.clamp(speed / 24, 0.6, 1.4))
		elseif want == "climb" then
			track:AdjustSpeed(math.clamp(math.abs(root.AssemblyLinearVelocity.Y) / 6, 0, 1.5))
		end
	end
end

-- Появление бота в точке spawnCFrame.
function BotService.spawn(bot, spawnCFrame: CFrame, protection: number)
	BotService.despawn(bot)
	resetState(bot)
	local model = buildCharacter(bot)
	PhysicsSetup.prepareCharacter(model)
	model:PivotTo(spawnCFrame)
	model.Parent = workspace
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root:SetNetworkOwner(nil) -- физику бота считает сервер
	bot.Character = model
	byModel[model] = bot

	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.WalkSpeed = BASE_SPEED
	bot.hum, bot.root, bot.head = hum, root, model:FindFirstChild("Head")

	-- Поворот корпуса: плавно, через физику, а не телепортом CFrame.
	local att = Instance.new("Attachment")
	att.Name = "BotFacing"
	att.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "BotFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.Responsiveness = BotsConfig.TurnResponsiveness
	align.MaxTorque = math.huge
	align.MaxAngularVelocity = math.rad(720)
	align.CFrame = root.CFrame.Rotation
	align.Enabled = false
	align.Parent = root
	bot.align = align

	-- Свой объект пути на каждого бота; если путь перегородили (машина, дверь), пересчитываем.
	bot.pathObj = PathfindingService:CreatePath(PATH_PARAMS)
	bot.pathObj.Blocked:Connect(function(index)
		if index >= bot.wpIndex then
			bot.pathGoal = nil
		end
	end)

	setupAnimations(bot, model, hum)

	local tool = WeaponService.makeTool(bot.WeaponId)
	if tool then
		tool.Parent = model
		hum:EquipTool(tool)
		bot.tool = tool
	end
	if protection > 0 then
		local shield = Instance.new("ForceField")
		shield.Parent = model
		task.delay(protection, function()
			if shield.Parent then
				shield:Destroy()
			end
		end)
	end
	hum.Died:Connect(function()
		if bot.pathObj then
			bot.pathObj:Destroy()
			bot.pathObj = nil
		end
		hooks.onDied(bot, hum)
	end)
end

------------------------------------------------------------------------
-- Зрение

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude

-- Видна ли часть тела цели: сначала корпус, потом голова (враг за низким укрытием).
-- Возвращает точку, куда целиться, и была ли это голова.
local function canSee(bot, head: BasePart, target, ignoreFov: boolean?): (Vector3?, boolean)
	-- Ослеплён светошумовой.
	if (bot.Character:GetAttribute("BlindUntil") or 0) > os.clock() then
		return nil, false
	end
	local tchar = target.Character
	if not tchar then
		return nil, false
	end
	local torso = tchar:FindFirstChild("UpperTorso") or tchar:FindFirstChild("HumanoidRootPart")
	if not torso then
		return nil, false
	end
	local offset = torso.Position - head.Position
	local dist = offset.Magnitude
	if dist > BotsConfig.ViewDistance then
		return nil, false
	end
	-- Угол обзора: за спиной замечает только вплотную.
	if not ignoreFov and dist > BotsConfig.BackSenseDistance and bot.root then
		local look = flat(bot.root.CFrame.LookVector)
		local cosHalf = math.cos(math.rad(BotsConfig.FieldOfView / 2))
		if look.Magnitude > 0.1 and look.Unit:Dot(unitOr(flat(offset), look.Unit)) < cosHalf then
			return nil, false
		end
	end
	sightParams.FilterDescendantsInstances = { bot.Character }
	for _, partName in { "UpperTorso", "Head" } do
		local part = tchar:FindFirstChild(partName) or (partName == "UpperTorso" and torso)
		if part then
			if not GrenadeService.blocksSight(head.Position, part.Position) then
				local result = workspace:Raycast(head.Position, part.Position - head.Position, sightParams)
				if result and result.Instance:IsDescendantOf(tchar) then
					return part.Position, partName == "Head"
				end
			end
		end
	end
	return nil, false
end

local function findTarget(bot, head: BasePart)
	local best, bestPos, bestHead, bestScore = nil, nil, false, math.huge
	for _, enemy in hooks.getEnemies(bot) do
		if hooks.isAlive(enemy) then
			-- Врага, о котором бот знает (видел или слышал), он замечает и за спиной.
			local known = bot.alertPos and enemy.Character and enemy.Character.PrimaryPart
				and (enemy.Character.PrimaryPart.Position - bot.alertPos).Magnitude < 20
			local pos, isHead = canSee(bot, head, enemy, known)
			if pos then
				local score = (pos - head.Position).Magnitude
				if enemy == bot.target then
					score *= 0.7 -- не бросаем текущую цель ради чуть более близкой
				end
				if score < bestScore then
					best, bestPos, bestHead, bestScore = enemy, pos, isHead, score
				end
			end
		end
	end
	return best, bestPos, bestHead
end

local function nearestEnemyPosition(bot, from: Vector3): Vector3?
	local best, bestDist = nil, math.huge
	for _, enemy in hooks.getEnemies(bot) do
		local _, _, root = charParts(enemy)
		if root and hooks.isAlive(enemy) then
			local d = (root.Position - from).Magnitude
			if d < bestDist then
				best, bestDist = root.Position, d
			end
		end
	end
	return best
end

local function alert(bot, position: Vector3)
	bot.alertPos = position
	bot.alertTime = os.clock()
end

------------------------------------------------------------------------
-- Навигация

local function nearestAheadIndex(wps, pos: Vector3): number
	local bestI, bestD = 1, math.huge
	for i, wp in wps do
		local d = (wp.Position - pos).Magnitude
		if d < bestD then
			bestI, bestD = i, d
		end
	end
	return math.min(bestI + 1, #wps)
end

local function requestPath(bot, root: BasePart, goal: Vector3)
	if bot.computing or not bot.pathObj then
		return
	end
	bot.computing = true
	local char = bot.Character
	local path = bot.pathObj
	local from = root.Position
	task.spawn(function()
		local wps = nil
		-- Если точно в цель не пройти (внутри ящика, на крыше), пробуем точки рядом.
		local tries = { Vector3.zero, Vector3.new(5, 0, 0), Vector3.new(-5, 0, 0), Vector3.new(0, 0, 5), Vector3.new(0, 0, -5) }
		for _, shift in tries do
			local ok = pcall(path.ComputeAsync, path, from, goal + shift)
			if bot.Character ~= char or bot.pathObj ~= path then
				bot.computing = false
				return
			end
			if ok then
				local status = path.Status
				if status == Enum.PathStatus.Success or status.Name == "ClosestNoPath" then
					local list = path:GetWaypoints()
					if #list >= 2 then
						wps = list
						break
					end
				end
			end
		end
		bot.computing = false
		local pos = root.Position
		if wps then
			bot.waypoints = wps
			bot.wpIndex = nearestAheadIndex(wps, pos)
			bot.jumpedWp = 0
			bot.pathFails = 0
		else
			bot.waypoints = nil
			bot.pathFails += 1
		end
		bot.pathGoal = goal
		bot.pathTime = os.clock()
	end)
end

-- Обходим препятствие «усами»: ищем свободное направление, близкое к нужному.
local function steerAround(root: BasePart, dir: Vector3): Vector3
	if canStep(root, dir, 5) then
		return dir
	end
	for _, angle in { 30, -30, 60, -60, 90, -90, 125, -125 } do
		local d = CFrame.fromAxisAngle(UP, math.rad(angle)):VectorToWorldSpace(dir)
		if canStep(root, d, 5) then
			return d
		end
	end
	return dir
end

-- Идти к goal по пути. arrive — на каком расстоянии считать, что пришли.
local function navigate(bot, root: BasePart, goal: Vector3, arrive: number)
	bot.moveMode = "path"
	bot.navGoal = goal
	bot.arrive = arrive
	local now = os.clock()
	local dist = flat(goal - root.Position).Magnitude
	if dist <= arrive then
		return
	end
	local age = now - bot.pathTime
	local need = false
	if not bot.pathGoal then
		need = true
	else
		local moved = (bot.pathGoal - goal).Magnitude
		local tolerance = math.clamp(dist * 0.25, 4, 25)
		if moved > tolerance and age > 0.6 then
			need = true -- цель заметно сместилась
		elseif not bot.waypoints and age > math.min(1 + bot.pathFails, 4) then
			need = true -- прошлый поиск не удался, пробуем ещё
		elseif bot.waypoints and bot.wpIndex > #bot.waypoints and dist > arrive + 3 and age > 0.5 then
			need = true -- путь кончился, а до цели далеко
		elseif age > 10 then
			need = true
		end
	end
	if need then
		requestPath(bot, root, goal)
	end

	-- Срезаем углы: если до следующей точки пути можно дойти по прямой, идём сразу к ней.
	local wps = bot.waypoints
	if wps then
		for _ = 1, 3 do
			local i = bot.wpIndex
			if i >= #wps then
				break
			end
			local cur, nxt = wps[i], wps[i + 1]
			if cur.Action ~= Enum.PathWaypointAction.Walk or nxt.Action ~= Enum.PathWaypointAction.Walk then
				break
			end
			if math.abs(nxt.Position.Y - cur.Position.Y) > 1.5 or not clearWalk(root.Position, nxt.Position) then
				break
			end
			bot.wpIndex = i + 1
		end
		bot.directDir = nil
	else
		-- Пути нет: напрямую, обходя препятствия.
		bot.directDir = steerAround(root, unitOr(flat(goal - root.Position), flat(root.CFrame.LookVector)))
	end
end

-- Каждый кадр: куда шагать, чтобы идти по пути.
local function followPath(bot, hum: Humanoid, root: BasePart): Vector3
	local goal = bot.navGoal
	if not goal then
		return Vector3.zero
	end
	local pos = root.Position
	local toGoal = flat(goal - pos)
	if toGoal.Magnitude <= bot.arrive then
		return Vector3.zero
	end
	local wps = bot.waypoints
	if wps then
		local i = bot.wpIndex
		while i <= #wps do
			local wp = wps[i]
			local off = wp.Position - pos
			local h = flat(off).Magnitude
			local passed = false
			if i < #wps and h < 5 then
				local seg = flat(wps[i + 1].Position - wp.Position)
				passed = seg.Magnitude > 0.01 and seg:Dot(flat(pos - wp.Position)) > 0
			end
			if (h < 2 and math.abs(off.Y + 3) < 4) or passed then
				i += 1
			else
				break
			end
		end
		bot.wpIndex = i
		if i <= #wps then
			local wp = wps[i]
			if wp.Action == Enum.PathWaypointAction.Jump and bot.jumpedWp ~= i then
				bot.jumpedWp = i
				hum.Jump = true
			end
			local d = flat(wp.Position - pos)
			if d.Magnitude < 0.6 then
				return bot.lastPathDir or Vector3.zero -- лезем по лестнице вверх
			end
			bot.lastPathDir = d.Unit
			return d.Unit
		end
	end
	-- Путь ещё считается, не найден или пройден: напрямую.
	local dir = bot.directDir or unitOr(toGoal, Vector3.zero)
	return dir
end

------------------------------------------------------------------------
-- Укрытия

-- Ищем точку рядом, где между нами и угрозой окажется препятствие
-- (с учётом приседа: низкий ящик тоже годится).
local function findCover(bot, root: BasePart, threat: Vector3): Vector3?
	local origin = root.Position
	local feet = origin.Y - 3
	local best, bestScore = nil, math.huge
	local toThreat = unitOr(flat(threat - origin), flat(root.CFrame.LookVector))
	local radius = BotsConfig.CoverSearchRadius
	for i = 0, 15 do
		local angle = i * (math.pi / 8) + math.random() * 0.2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local hit = workspace:Raycast(Vector3.new(origin.X, feet + 1.5, origin.Z), dir * radius, worldParams)
		if hit and math.abs(hit.Normal.Y) < 0.5 then
			local spot = hit.Position - dir * 1.8
			spot = Vector3.new(spot.X, feet, spot.Z)
			-- Встаём с той стороны препятствия, что дальше от угрозы.
			local blocker = workspace:Raycast(threat, (spot + Vector3.new(0, 2.2, 0)) - threat, worldParams)
			if blocker and (blocker.Position - spot).Magnitude < 7 then
				local ground = workspace:Raycast(spot + Vector3.new(0, 3, 0), Vector3.new(0, -8, 0), worldParams)
				if ground then
					local d = (spot - origin).Magnitude
					local score = d
					-- Не бежим навстречу врагу ради укрытия.
					if dir:Dot(toThreat) > 0.3 then
						score += 25
					end
					if score < bestScore then
						best, bestScore = ground.Position, score
					end
				end
			end
		end
	end
	return best
end

------------------------------------------------------------------------
-- Поза и скорость

local function setCrouch(bot, hum: Humanoid, on: boolean)
	local char = bot.Character
	if not char or bot.crouched == on or not CrouchPose.supported(char) then
		return
	end
	bot.crouched = on
	if on then
		bot.crouchDrop = CrouchPose.drop(char)
		hum.HipHeight -= bot.crouchDrop
	else
		hum.HipHeight += bot.crouchDrop
		bot.crouchDrop = 0
	end
	CrouchPose.set(char, on)
end

local function applySpeed(bot, hum: Humanoid, dt: number)
	local mode = bot.speedMode
	local sprinting = false
	if mode == "sprint" then
		-- Как у игроков: бег ограничен выносливостью.
		if bot.stamina > 0 and not bot.tired then
			sprinting = true
			bot.stamina -= dt
			if bot.stamina <= 0 then
				bot.tired = true
			end
		end
	end
	if not sprinting then
		bot.stamina = math.min(BotsConfig.SprintStamina, bot.stamina + dt * 0.8)
		if bot.tired and bot.stamina > BotsConfig.SprintStamina * 0.4 then
			bot.tired = false
		end
	end
	setCrouch(bot, hum, mode == "crouch")
	hum.WalkSpeed = if sprinting
		then BASE_SPEED * BotsConfig.SprintMultiplier
		elseif mode == "crouch" then BotsConfig.CrouchSpeed
		else BASE_SPEED
end

------------------------------------------------------------------------
-- Решения (think)

local function reactionDelay(dist: number): number
	return BotsConfig.ReactionTime + math.random() * BotsConfig.ReactionRandom + dist * BotsConfig.ReactionPerStud
end

local function preferredRange(def): number
	local range = if def then def.Range else 100
	return math.clamp(range * 0.22, 12, 70)
end

local function updateSeparation(bot, root: BasePart)
	local push = Vector3.zero
	for _, ally in hooks.getAllies(bot) do
		if ally ~= bot then
			local _, _, aroot = charParts(ally)
			if aroot then
				local off = flat(root.Position - aroot.Position)
				local d = off.Magnitude
				if d < 5 then
					push += unitOr(off, Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit) * (5 - d) / 5
				end
			end
		end
	end
	bot.sep = push
end

local function checkStuck(bot, hum: Humanoid, root: BasePart, dt: number, now: number)
	local wantsMove = bot.smoothMove.Magnitude > 0.5 and now > bot.unstickUntil
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	if wantsMove and speed < 1.5 and hum:GetState() ~= Enum.HumanoidStateType.Climbing then
		bot.stuckTime += dt
		if bot.stuckTime > 0.7 and bot.stuckTime - dt <= 0.7 then
			hum.Jump = true -- может, низкое препятствие
		elseif bot.stuckTime > 1.5 then
			-- Отойти в сторону и пересчитать путь.
			bot.stuckTime = 0
			local side = flat(root.CFrame.RightVector) * (if math.random() < 0.5 then 1 else -1)
			bot.unstickDir = unitOr(side - flat(root.CFrame.LookVector) * 0.5, side)
			bot.unstickUntil = now + 0.6
			bot.pathGoal = nil
		end
	else
		bot.stuckTime = 0
	end
end

local function findAttacker(bot, hum: Humanoid)
	local id = hum:GetAttribute("LastAttacker")
	if not id then
		return nil
	end
	for _, enemy in hooks.getEnemies(bot) do
		if hooks.idOf(enemy) == id then
			return enemy
		end
	end
	return nil
end

-- Бой: стрейф, держим дистанцию оружия, отходим в укрытие.
local function combatMove(bot, hum: Humanoid, root: BasePart, def, targetPos: Vector3, healthFrac: number, reloading: boolean, now: number, dt: number)
	local toTarget = flat(targetPos - root.Position)
	local dist = toTarget.Magnitude
	local dirT = unitOr(toTarget, flat(root.CFrame.LookVector))

	-- Укрытие: мало здоровья, перезарядка или только что попали.
	if not bot.coverPos and now > bot.coverCooldown then
		local justHit = now - bot.hurtAt < 0.2 and math.random() < 0.35
		if reloading or healthFrac < BotsConfig.CoverHealth or justHit then
			local spot = findCover(bot, root, targetPos)
			bot.coverCooldown = now + (if spot then BotsConfig.CoverCooldown else 2)
			if spot then
				bot.coverPos = spot
				bot.coverUntil = now + rand(BotsConfig.CoverTime[1], BotsConfig.CoverTime[2])
			end
		end
	end
	if bot.coverPos then
		if now > bot.coverUntil and not reloading then
			bot.coverPos = nil
		else
			navigate(bot, root, bot.coverPos, 1.2)
			local arrived = flat(bot.coverPos - root.Position).Magnitude < 2
			bot.speedMode = if arrived then "crouch" else "walk"
			return
		end
	end

	-- Стрейф: меняем сторону или останавливаемся через случайные промежутки.
	bot.strafeTime -= dt
	if bot.strafeTime <= 0 then
		local r = math.random()
		if bot.strafeDir ~= 0 and r < 0.25 then
			bot.strafeDir = 0 -- постоять и прицелиться
			bot.strafeTime = rand(0.4, 0.9)
		else
			bot.strafeDir = if r < 0.6 then -(if bot.strafeDir == 0 then 1 else bot.strafeDir) else (if math.random() < 0.5 then 1 else -1)
			bot.strafeTime = rand(0.6, 1.6)
		end
	end
	local side = dirT:Cross(UP) * bot.strafeDir
	if bot.strafeDir ~= 0 and not canStep(root, side) then
		bot.strafeDir = -bot.strafeDir
		side = -side
		if not canStep(root, side) then
			side = Vector3.zero
		end
	end

	local pref = preferredRange(def)
	local forward = Vector3.zero
	if reloading then
		forward = -dirT -- перезаряжаемся без укрытия: пятимся
	elseif dist > pref * 1.4 then
		forward = dirT
	elseif dist < pref * 0.5 then
		forward = -dirT
	end
	if forward.Magnitude > 0 and not canStep(root, forward) then
		if forward:Dot(dirT) > 0 then
			-- Сближаемся, а напрямую не пройти: обходим по навигации.
			navigate(bot, root, targetPos, pref * 0.8)
			bot.speedMode = "walk"
			return
		end
		forward = Vector3.zero
	end
	local move = side * 0.8 + forward
	bot.moveMode = "dir"
	bot.moveDir = if move.Magnitude > 1 then move.Unit else move
	-- Стоит на месте на дистанции — присаживается, чтобы стать меньше.
	bot.speedMode = if move.Magnitude < 0.1 and dist > 30 then "crouch" else "walk"
end

local function think(bot, dt: number)
	local char, hum, root = charParts(bot)
	if not char or not hum or hum.Health <= 0 or not root then
		return
	end
	local head = bot.head
	if not head or not head.Parent then
		return
	end
	local now = os.clock()
	if DamageService.isDowned(char) then
		bot.moveMode = "stop"
		bot.face = nil
		bot.visible = false
		if bot.crouched then
			setCrouch(bot, hum, false)
		end
		return
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		-- После «ранен — подняли» оружие убирается из рук: берём его снова.
		tool = if bot.tool and bot.tool.Parent ~= nil then bot.tool else WeaponService.makeTool(bot.WeaponId)
		if tool then
			pcall(function()
				tool.Parent = char
				hum:EquipTool(tool)
			end)
			bot.tool = tool
		end
	end
	local def = Weapons.List[bot.WeaponId]
	local ammo = tool and tool:GetAttribute("Ammo") or 0
	local reloading = tool ~= nil and tool:GetAttribute("Reloading") == true
	local healthFrac = hum.Health / math.max(1, hum.MaxHealth)

	updateSeparation(bot, root)
	checkStuck(bot, hum, root, dt, now)

	-- Попали: узнаём, кто стрелял, и разворачиваемся туда.
	if bot.lastHealth and hum.Health < bot.lastHealth - 0.5 then
		bot.hurtAt = now
		local attacker = findAttacker(bot, hum)
		local aroot = attacker and attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
		if aroot and not bot.visible then
			alert(bot, aroot.Position)
		end
	end
	bot.lastHealth = hum.Health

	-- Перезарядка: пустой магазин или полупустой, пока врагов не видно.
	if tool and def and def.MagSize and not reloading then
		if ammo <= 0 or (ammo < def.MagSize * 0.4 and not bot.visible and now - bot.lastSeenTime > 1.5) then
			WeaponService.reload(char, bot.WeaponId)
			reloading = tool:GetAttribute("Reloading") == true
		end
	end

	-- Цель: держим текущую, пока её видно, иначе ищем новую.
	local target, targetPos, isHead = nil, nil, false
	if bot.target and hooks.isAlive(bot.target) then
		targetPos, isHead = canSee(bot, head, bot.target, true)
		target = targetPos and bot.target
	end
	if not targetPos then
		target, targetPos, isHead = findTarget(bot, head)
	end
	if target and targetPos then
		if not bot.visible or target ~= bot.target then
			-- Только что увидел: нужна реакция. Тот же враг, мелькнувший снова, — быстрее.
			local again = target == bot.lastLostTarget and now - bot.lastSeenTime < 1.5
			local dist = (targetPos - head.Position).Magnitude
			bot.reactAt = now + (if again then BotsConfig.ReacquireTime else reactionDelay(dist))
			if not again then
				bot.engagedAt = bot.reactAt
				bot.aimPoint = nil
			end
			bot.aimHead = math.random() < BotsConfig.HeadshotChance
		end
		bot.target = target
		bot.visible = true
		bot.visibleHead = isHead
		bot.lastSeenPos = targetPos
		bot.lastSeenTime = now
		bot.alertPos = nil
	else
		if bot.visible and bot.lastSeenPos then
			-- Потеряли из виду: запоминаем, где был, и идём проверить.
			bot.lastLostTarget = bot.target
			alert(bot, bot.lastSeenPos)
		end
		bot.visible = false
		if bot.target and not hooks.isAlive(bot.target) then
			bot.target = nil
		end
	end

	if bot.visible and targetPos then
		bot.face = targetPos
		-- Наклон рук с оружием на клиентах (WeaponPose).
		local aimDir = targetPos - head.Position
		if aimDir.Magnitude > 0.1 then
			char:SetAttribute("AimPitch", math.floor(math.deg(math.asin(math.clamp(aimDir.Unit.Y, -1, 1))) + 0.5))
		end
		combatMove(bot, hum, root, def, targetPos, healthFrac, reloading, now, dt)
		applySpeed(bot, hum, dt)
		return
	end

	-- Врагов не видно.
	bot.face = nil

	-- Досиживаем в укрытии (перезарядка, лечение), смотрим туда, где был враг.
	if bot.coverPos then
		if now > bot.coverUntil and not reloading then
			bot.coverPos = nil
		else
			navigate(bot, root, bot.coverPos, 1.2)
			bot.face = bot.lastSeenPos
			bot.speedMode = if flat(bot.coverPos - root.Position).Magnitude < 2 then "crouch" else "walk"
			applySpeed(bot, hum, dt)
			return
		end
	end

	-- Поднимаем раненого союзника рядом.
	local downedAlly, allyDist = nil, 40
	for _, ally in hooks.getAllies(bot) do
		local achar = ally.Character
		local aroot = achar and achar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if ally ~= bot and aroot and DamageService.isDowned(achar) then
			local d = (aroot.Position - root.Position).Magnitude
			if d < allyDist then
				downedAlly, allyDist = ally, d
			end
		end
	end
	if downedAlly then
		local achar = downedAlly.Character
		local aroot = achar:FindFirstChild("HumanoidRootPart") :: BasePart
		if allyDist < 5 then
			bot.moveMode = "stop"
			bot.speedMode = "crouch"
			bot.face = aroot.Position
			bot.reviveTime += dt
			if bot.reviveTime >= Combat.Downed.ReviveTime then
				bot.reviveTime = 0
				local ahum = achar:FindFirstChildOfClass("Humanoid")
				if ahum then
					DamageService.revive(ahum, bot)
				end
			end
		else
			bot.reviveTime = 0
			navigate(bot, root, aroot.Position, 3.5)
			bot.speedMode = if allyDist > 15 then "sprint" else "walk"
		end
		applySpeed(bot, hum, dt)
		return
	end
	bot.reviveTime = 0

	-- Слышал выстрелы, получил урон или потерял врага: идём проверить, глядя в ту сторону.
	if bot.alertPos and now - bot.alertTime < BotsConfig.MemoryTime then
		local d = flat(bot.alertPos - root.Position).Magnitude
		if d < 6 then
			bot.alertPos = nil
		else
			navigate(bot, root, bot.alertPos, 5)
			bot.face = bot.alertPos + Vector3.new(0, 2, 0)
			bot.speedMode = "walk"
			applySpeed(bot, hum, dt)
			return
		end
	else
		bot.alertPos = nil
	end

	-- Цель режима (точка захвата) или охота на ближайшего врага.
	local goal = hooks.getObjective(bot)
	if goal then
		local d = flat(goal - root.Position).Magnitude
		if d <= 4 then
			-- На точке: держим её, присев, и смотрим, откуда придут враги.
			bot.moveMode = "stop"
			bot.speedMode = "crouch"
			if now > bot.holdLookTime then
				local enemy = nearestEnemyPosition(bot, root.Position)
				local look = if enemy then flat(enemy - root.Position) else Vector3.zero
				local base = unitOr(look, flat(root.CFrame.LookVector))
				local yaw = math.rad(rand(-50, 50))
				bot.holdLook = CFrame.fromAxisAngle(UP, yaw):VectorToWorldSpace(base)
				bot.holdLookTime = now + rand(1.5, 3.5)
			end
			bot.face = root.Position + bot.holdLook * 20
		else
			navigate(bot, root, goal, 3)
			bot.speedMode = if d > 35 then "sprint" else "walk"
		end
	else
		local enemyPos = nearestEnemyPosition(bot, root.Position)
		if enemyPos then
			-- Каждый бот заходит со своей стороны, а вблизи идёт прямо на врага.
			local toEnemy = flat(enemyPos - root.Position)
			local d = toEnemy.Magnitude
			local side = unitOr(toEnemy, Vector3.xAxis):Cross(UP)
			local flank = bot.flank * math.clamp((d - 40) / 80, 0, 1)
			navigate(bot, root, enemyPos + side * flank, 8)
			bot.speedMode = if d > 70 then "sprint" else "walk"
		else
			bot.moveMode = "stop"
			bot.speedMode = "walk"
		end
	end
	applySpeed(bot, hum, dt)
end

------------------------------------------------------------------------
-- Каждый кадр (step): поворот, плавное движение, прицел и стрельба

local function shootStep(bot, char: Model, head: BasePart, root: BasePart, dt: number, now: number)
	local target = bot.target
	local tchar = target and target.Character
	if not tchar then
		return
	end
	local part = (bot.aimHead or bot.visibleHead) and tchar:FindFirstChild("Head")
		or tchar:FindFirstChild("UpperTorso")
		or tchar:FindFirstChild("HumanoidRootPart")
	if not part then
		return
	end
	-- Прицел догоняет цель с запаздыванием и чуть упреждает движение.
	local trueAim = part.Position + part.AssemblyLinearVelocity * 0.08
	bot.aimPoint = if bot.aimPoint then bot.aimPoint:Lerp(trueAim, 1 - math.exp(-dt * BotsConfig.AimTracking)) else trueAim
	if now < bot.reactAt then
		return
	end
	local tool = char:FindFirstChildOfClass("Tool")
	local def = Weapons.List[bot.WeaponId]
	if not tool or not def or tool:GetAttribute("Reloading") then
		return
	end
	if def.MagSize and (tool:GetAttribute("Ammo") or 0) <= 0 then
		return
	end
	-- Стреляем, только когда корпус почти довернулся до цели.
	local toAim = flat(bot.aimPoint - root.Position)
	if toAim.Magnitude > 0.5 and flat(root.CFrame.LookVector):Dot(toAim.Unit) < 0.9 then
		return
	end
	if now < bot.nextShot then
		return
	end

	-- Разброс: в начале перестрелки больше, потом сходится; на бегу и по бегущим — хуже.
	local settle = math.exp(-(now - bot.engagedAt) / BotsConfig.AimSettleTime)
	local spread = BotsConfig.AimError * (1 + BotsConfig.AimErrorStart * math.max(0, settle))
	spread *= 1 + flat(part.AssemblyLinearVelocity).Magnitude / 32 + flat(root.AssemblyLinearVelocity).Magnitude / 40
	if now > bot.aimOffsetTime then
		bot.aimOffset = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.8, math.random() - 0.5) * spread
		bot.aimOffsetTime = now + 0.12
	end
	local aim = bot.aimPoint + bot.aimOffset
	local fired = WeaponService.fire(bot, char, bot.WeaponId, head.Position, aim - head.Position)
	local interval = 1 / def.FireRate
	if not fired then
		bot.nextShot = now + 0.05
		return
	end
	if def.Automatic then
		if bot.burstLeft <= 0 then
			bot.burstLeft = math.random(BotsConfig.BurstShots[1], BotsConfig.BurstShots[2])
		end
		bot.burstLeft -= 1
		if bot.burstLeft <= 0 then
			bot.nextShot = now + interval + rand(BotsConfig.BurstPause[1], BotsConfig.BurstPause[2])
		else
			bot.nextShot = now + interval
		end
	else
		bot.nextShot = now + interval + rand(BotsConfig.SemiExtraDelay[1], BotsConfig.SemiExtraDelay[2])
	end
end

local function step(bot, dt: number, now: number)
	local char, hum, root, head = bot.Character, bot.hum, bot.root, bot.head
	if not char or not hum or not root or not root.Parent or hum.Health <= 0 then
		return
	end
	local downed = DamageService.isDowned(char)

	-- Поворот корпуса к цели (в бою, при проверке звука, на точке) или по ходу движения.
	local align = bot.align
	if align then
		local faceDir = bot.face and not downed and flat(bot.face - root.Position)
		if faceDir and faceDir.Magnitude > 0.5 then
			align.CFrame = CFrame.lookAt(Vector3.zero, faceDir.Unit)
			if not align.Enabled then
				align.Enabled = true
				hum.AutoRotate = false
			end
		elseif align.Enabled then
			align.Enabled = false
			hum.AutoRotate = true
		end
	end

	-- Движение: желаемое направление сглаживается, поэтому нет рывков.
	local desired = Vector3.zero
	if not downed then
		if now < bot.unstickUntil then
			desired = bot.unstickDir
		elseif bot.moveMode == "path" then
			desired = followPath(bot, hum, root)
		elseif bot.moveMode == "dir" then
			desired = bot.moveDir
		end
		desired += bot.sep * (if desired.Magnitude > 0.1 then 0.6 else 0.35)
		if desired.Magnitude > 1 then
			desired = desired.Unit
		end
	end
	bot.smoothMove = bot.smoothMove:Lerp(desired, 1 - math.exp(-dt * BotsConfig.Steering))
	if bot.smoothMove.Magnitude > 0.08 then
		hum:Move(bot.smoothMove)
	else
		hum:Move(Vector3.zero)
	end

	if bot.visible and not downed and head then
		shootStep(bot, char, head, root, dt, now)
	end
	updateAnimation(bot, hum, root, downed)
end

-- Выстрел любого бойца: враги поблизости слышат его и идут проверить.
local function onShot(shooter, origin: Vector3)
	local team = hooks.teamOf(shooter)
	if not team then
		return
	end
	for _, bot in bots do
		if bot.TeamKey ~= team and bot.root and not bot.visible then
			local d = (bot.root.Position - origin).Magnitude
			if d < BotsConfig.HearDistance then
				-- Чем дальше, тем неточнее бот понимает, откуда стреляли.
				local err = d * 0.12
				alert(bot, origin + Vector3.new(rand(-err, err), 0, rand(-err, err)))
			end
		end
	end
end

function BotService.start()
	WeaponService.onShot = onShot

	-- Решения — несколько раз в секунду.
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(BotsConfig.ThinkInterval)
			local now = os.clock()
			local dt = now - last
			last = now
			if #bots > 0 then
				refreshWorldParams()
			end
			for _, bot in table.clone(bots) do
				local ok, err = pcall(think, bot, dt)
				if not ok then
					warn("[BotService] Ошибка ИИ бота ", bot.Name, ": ", err)
				end
			end
		end
	end)

	-- Движение и прицел — каждый кадр.
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, bot in bots do
			local ok, err = pcall(step, bot, dt, now)
			if not ok and not bot.stepWarned then
				bot.stepWarned = true
				warn("[BotService] Ошибка движения бота ", bot.Name, ": ", err)
			end
		end
	end)
end

return BotService
