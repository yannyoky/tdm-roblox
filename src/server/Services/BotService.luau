-- Боты. Бот — это таблица-«боец» с полями как у игрока, которые нужны матчу:
--   IsBot, Id, Name, DisplayName, UserId (отрицательный), TeamKey, Character
-- MatchService создаёт и удаляет ботов, BotService строит им тела и управляет ими.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BotsConfig = require(Shared.Config.Bots)
local TeamsConfig = require(Shared.Config.Teams)
local Weapons = require(Shared.Config.Weapons)

local WeaponService = require(script.Parent.WeaponService)
local PhysicsSetup = require(script.Parent.PhysicsSetup)

local BotService = {}

local bots = {} -- список живых объектов-ботов
local byModel = setmetatable({}, { __mode = "k" }) -- [Model] = бот
local nextId = 0
local usedNames = {}

-- Хуки от MatchService.
local hooks = {
	getEnemies = function(_bot)
		return {}
	end, -- список бойцов-врагов
	isAlive = function(_entity)
		return false
	end,
	getObjective = function(_bot): Vector3?
		return nil
	end,
	onDied = function(_bot, _hum) end,
}

function BotService.setHooks(newHooks)
	for k, v in newHooks do
		hooks[k] = v
	end
end

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
		-- состояние ИИ
		target = nil,
		seenFor = 0,
		path = nil :: { PathWaypoint }?,
		pathIndex = 1,
		pathGoal = nil :: Vector3?,
		pathTime = 0,
		computing = false,
		lastPos = nil :: Vector3?,
		stuckTime = 0,
		strafeDir = 1,
		strafeTime = 0,
	}
	table.insert(bots, bot)
	return bot
end

function BotService.despawn(bot)
	if bot.Character then
		byModel[bot.Character] = nil
		bot.Character:Destroy()
		bot.Character = nil
	end
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
	model.Name = bot.DisplayName
	model:SetAttribute("BotId", bot.Id)
	model:SetAttribute("TeamKey", bot.TeamKey)
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayName = bot.DisplayName
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	return model
end

-- Появление бота в точке spawnCFrame.
function BotService.spawn(bot, spawnCFrame: CFrame, protection: number)
	BotService.despawn(bot)
	local model = buildCharacter(bot)
	PhysicsSetup.prepareCharacter(model)
	model:PivotTo(spawnCFrame)
	model.Parent = workspace
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root:SetNetworkOwner(nil) -- физику бота считает сервер
	bot.Character = model
	byModel[model] = bot
	bot.target, bot.seenFor, bot.path, bot.pathGoal = nil, 0, nil, nil

	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local tool = WeaponService.makeTool(bot.WeaponId)
	if tool then
		tool.Parent = model
		hum:EquipTool(tool)
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
		hooks.onDied(bot, hum)
	end)
end

local function charParts(entity)
	local char = entity.Character
	if not char then
		return nil, nil, nil
	end
	return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function canSee(bot, head: BasePart, target): Vector3?
	local tchar = target.Character
	local tpart = tchar and (tchar:FindFirstChild("UpperTorso") or tchar:FindFirstChild("HumanoidRootPart"))
	if not tpart then
		return nil
	end
	local offset = tpart.Position - head.Position
	if offset.Magnitude > BotsConfig.ViewDistance then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.Character }
	local result = workspace:Raycast(head.Position, offset, params)
	if result and result.Instance:IsDescendantOf(tchar) then
		return tpart.Position
	end
	return nil
end

local function findTarget(bot, head: BasePart)
	local best, bestDist = nil, math.huge
	for _, enemy in hooks.getEnemies(bot) do
		if hooks.isAlive(enemy) then
			local pos = canSee(bot, head, enemy)
			if pos then
				local d = (pos - head.Position).Magnitude
				if d < bestDist then
					best, bestDist = enemy, d
				end
			end
		end
	end
	return best
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

local function computePath(bot, from: Vector3, goal: Vector3)
	if bot.computing then
		return
	end
	bot.computing = true
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(path.ComputeAsync, path, from, goal)
		bot.computing = false
		if ok and path.Status == Enum.PathStatus.Success then
			bot.path = path:GetWaypoints()
			bot.pathIndex = 2
		else
			bot.path = nil
		end
		bot.pathGoal = goal
		bot.pathTime = os.clock()
	end)
end

local function navigate(bot, hum: Humanoid, root: BasePart, goal: Vector3)
	local needNew = not bot.pathGoal
		or (bot.pathGoal - goal).Magnitude > 10
		or os.clock() - bot.pathTime > 4
	if needNew then
		computePath(bot, root.Position, goal)
	end
	local path = bot.path
	if path and bot.pathIndex <= #path then
		local wp = path[bot.pathIndex]
		if (Vector3.new(wp.Position.X, root.Position.Y, wp.Position.Z) - root.Position).Magnitude < 4 then
			bot.pathIndex += 1
		end
		if wp.Action == Enum.PathWaypointAction.Jump then
			hum.Jump = true
		end
		hum:MoveTo(wp.Position)
	else
		hum:MoveTo(goal)
	end
end

local function think(bot, dt: number)
	local char, hum, root = charParts(bot)
	if not char or not hum or hum.Health <= 0 or not root then
		return
	end
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local tool = char:FindFirstChildOfClass("Tool")
	local def = Weapons.List[bot.WeaponId]

	-- Застревание: подпрыгнуть и пересчитать путь.
	if bot.lastPos and (root.Position - bot.lastPos).Magnitude < 0.3 and hum.MoveDirection.Magnitude > 0 then
		bot.stuckTime += dt
		if bot.stuckTime > 1.2 then
			hum.Jump = true
			bot.pathGoal = nil
			bot.stuckTime = 0
		end
	else
		bot.stuckTime = 0
	end
	bot.lastPos = root.Position

	-- Перезарядка.
	if tool and def and def.MagSize and (tool:GetAttribute("Ammo") or 0) <= 0 then
		WeaponService.reload(char, bot.WeaponId)
	end

	-- Цель: держим текущую, пока её видно, иначе ищем новую.
	local targetPos = bot.target and hooks.isAlive(bot.target) and canSee(bot, head, bot.target)
	if not targetPos then
		bot.target = findTarget(bot, head)
		bot.seenFor = 0
		targetPos = bot.target and canSee(bot, head, bot.target)
	end

	if bot.target and targetPos then
		bot.seenFor += dt
		hum.AutoRotate = false
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPos.X, root.Position.Y, targetPos.Z))

		-- Движение в бою: стрейф в стороны, отход, если враг слишком близко.
		bot.strafeTime -= dt
		if bot.strafeTime <= 0 then
			bot.strafeDir = -bot.strafeDir
			bot.strafeTime = 0.8 + math.random() * 1.2
		end
		local toTarget = targetPos - root.Position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		local side = if flat.Magnitude > 0.1 then flat.Unit:Cross(Vector3.yAxis) * bot.strafeDir else Vector3.zero
		local range = if def then def.Range else 100
		local forward = if flat.Magnitude > range * 0.6 then flat.Unit elseif flat.Magnitude < 12 then -flat.Unit else Vector3.zero
		hum:Move(side + forward)

		if bot.seenFor >= BotsConfig.ReactionTime and tool then
			local e = BotsConfig.AimError
			local aim = targetPos + Vector3.new((math.random() - 0.5) * e, (math.random() - 0.3) * e, (math.random() - 0.5) * e)
			WeaponService.fire(bot, char, bot.WeaponId, head.Position, aim - head.Position)
		end
		return
	end

	-- Врагов не видно: идём к цели режима или к ближайшему врагу.
	hum.AutoRotate = true
	local goal = hooks.getObjective(bot) or nearestEnemyPosition(bot, root.Position)
	if goal then
		navigate(bot, hum, root, goal)
	else
		hum:Move(Vector3.zero)
	end
end

function BotService.start()
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(BotsConfig.ThinkInterval)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, bot in table.clone(bots) do
				local ok, err = pcall(think, bot, dt)
				if not ok then
					warn("[BotService] Ошибка ИИ бота ", bot.Name, ": ", err)
				end
			end
		end
	end)
end

return BotService
