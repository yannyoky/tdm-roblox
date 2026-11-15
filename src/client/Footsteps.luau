-- Шаги в такт анимации: звук касания играет, когда стопа персонажа опускается на землю
-- (стопа поднялась над землёй и снова встала на неё). Так звук совпадает с тем, что видно,
-- и у игроков, и у ботов. Бег громче, присед тише. Стандартный звук бега Roblox заглушён.
-- У персонажей без отдельных стоп (R6) шаг считается по пройденному расстоянию.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds).Footsteps
local MovementConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.Movement)

local Footsteps = {}

local WALK_SPEED = 16
local SPRINT_SPEED = WALK_SPEED * MovementConfig.Sprint.Multiplier
local MIN_INTERVAL = 0.15 -- не чаще одного шага за это время
local LIFT = 0.2 -- на сколько стопа должна подняться, чтобы считаться в воздухе
local PLANT = 0.08 -- и насколько опуститься к земле, чтобы считаться шагом
local R6_STRIDE = 6.5 -- шаг по расстоянию для персонажей без стоп
local MAX_DISTANCE = Config.Range + 10 -- дальше шаги не считаем

type FootState = { ground: number, lifted: boolean }
type CharState = { feet: { [string]: FootState }, last: number, dist: number, variant: number }

local states: { [Model]: CharState } = setmetatable({}, { __mode = "k" }) :: any

local function tier(char: Model, speed: number)
	if char:GetAttribute("Crouching") then
		return Config.Crouch
	elseif speed > (WALK_SPEED + SPRINT_SPEED) / 2 then
		return Config.Sprint
	end
	return Config.Walk
end

local function playStep(st: CharState, at: BasePart, t)
	local ids = Config.Ids
	-- Следующий вариант звука, но не тот же, что в прошлый раз.
	st.variant = (st.variant + math.random(1, #ids - 1) - 1) % #ids + 1
	local s = Instance.new("Sound")
	s.SoundId = ids[st.variant]
	s.Volume = t.Volume * (0.9 + math.random() * 0.2)
	s.PlaybackSpeed = t.Pitch * (0.94 + math.random() * 0.12)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = Config.Range
	s.Parent = at
	s:Play()
	Debris:AddItem(s, 1.5)
end

local function update(char: Model, dt: number, camPos: Vector3)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end
	-- Стандартный звук бега Roblox выключаем: вместо него наши шаги.
	local running = root:FindFirstChild("Running")
	if running and running:IsA("Sound") and running.Volume ~= 0 then
		running.Volume = 0
	end
	if (root.Position - camPos).Magnitude > MAX_DISTANCE then
		return
	end
	local st = states[char]
	if not st then
		st = { feet = {}, last = 0, dist = 0, variant = 1 }
		states[char] = st
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local moving = speed > 2 and hum.FloorMaterial ~= Enum.Material.Air and hum.SeatPart == nil
	local now = os.clock()
	local t = tier(char, speed)

	local left = char:FindFirstChild("LeftFoot")
	local right = char:FindFirstChild("RightFoot")
	if left and right and left:IsA("BasePart") and right:IsA("BasePart") then
		for _, foot in { left, right } do
			local y = root.CFrame:PointToObjectSpace(foot.Position).Y
			local fs = st.feet[foot.Name]
			if not fs then
				st.feet[foot.Name] = { ground = y, lifted = false }
			else
				-- Нижнее положение стопы: следим за минимумом, медленно отпуская его вверх (присед).
				fs.ground = math.min(y, fs.ground + dt * 0.5)
				if not fs.lifted and y > fs.ground + LIFT then
					fs.lifted = true
				elseif fs.lifted and y < fs.ground + PLANT then
					fs.lifted = false
					if moving and now - st.last > MIN_INTERVAL then
						st.last = now
						playStep(st, foot, t)
					end
				end
			end
		end
		-- Если анимация не двигает стопы (например, её нет), считаем шаги по расстоянию.
		if moving and now - st.last > 0.9 then
			st.dist += speed * dt
			if st.dist > R6_STRIDE then
				st.dist = 0
				st.last = now
				playStep(st, root, t)
			end
		else
			st.dist = 0
		end
	elseif moving then
		st.dist += speed * dt
		if st.dist > R6_STRIDE and now - st.last > MIN_INTERVAL then
			st.dist = 0
			st.last = now
			playStep(st, root, t)
		end
	end
end

function Footsteps.init()
	-- Боты — модели с атрибутом BotId прямо в workspace.
	local bots: { [Model]: true } = {}
	local function track(child: Instance)
		if child:IsA("Model") and child:GetAttribute("BotId") ~= nil then
			bots[child] = true
		end
	end
	workspace.ChildAdded:Connect(track)
	workspace.ChildRemoved:Connect(function(child)
		bots[child :: Model] = nil
	end)
	for _, child in workspace:GetChildren() do
		track(child)
	end

	RunService.Heartbeat:Connect(function(dt)
		local camPos = workspace.CurrentCamera.CFrame.Position
		for _, player in Players:GetPlayers() do
			local char = player.Character
			if char then
				update(char, dt, camPos)
			end
		end
		for bot in bots do
			update(bot, dt, camPos)
		end
	end)
end

return Footsteps
