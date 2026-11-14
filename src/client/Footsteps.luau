-- Шаги: темп и громкость зависят от скорости. Бег громче и чаще, присед тише и реже.
-- У игроков подменяется и подстраивается стандартный звук Roblox (HumanoidRootPart.Running),
-- ботам свой звук шагов добавляем сами, иначе они ходят бесшумно.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds).Footsteps
local MovementConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.Movement)

local Footsteps = {}

local WALK_SPEED = 16
local SPRINT_SPEED = WALK_SPEED * MovementConfig.Sprint.Multiplier

local bots: { [Model]: Sound } = {}

local function tier(char: Model, speed: number)
	if char:GetAttribute("Crouching") then
		return Config.Crouch
	elseif speed > (WALK_SPEED + SPRINT_SPEED) / 2 then
		return Config.Sprint
	end
	return Config.Walk
end

local function update(char: Model, sound: Sound, own: boolean)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local t = tier(char, speed)
	-- Темп шагов растёт со скоростью внутри своего режима.
	sound.PlaybackSpeed = t.Speed * math.clamp(speed / (if t == Config.Sprint then SPRINT_SPEED else WALK_SPEED), 0.7, 1.15)
	sound.Volume = t.Volume
	if own then
		-- Ботам включаем и выключаем звук сами (у игроков это делает Roblox).
		local onGround = hum.FloorMaterial ~= Enum.Material.Air and hum.Health > 0
		local moving = speed > 1 and onGround
		if moving and not sound.IsPlaying then
			sound:Play()
		elseif not moving and sound.IsPlaying then
			sound:Stop()
		end
	end
end

local function addBot(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("BotId") == nil or bots[model] then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not root or not model.Parent then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "BotSteps"
	s.SoundId = Config.Id
	s.Looped = true
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 5
	s.RollOffMaxDistance = Config.Range
	s.Parent = root
	bots[model] = s
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			bots[model] = nil
		end
	end)
end

function Footsteps.init()
	workspace.ChildAdded:Connect(function(child)
		task.spawn(addBot, child)
	end)
	for _, child in workspace:GetChildren() do
		task.spawn(addBot, child)
	end

	RunService.Heartbeat:Connect(function()
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local running = root and root:FindFirstChild("Running")
			if running and running:IsA("Sound") then
				-- Стандартный пластиковый звук Roblox меняем на свой.
				if running.SoundId ~= Config.Id then
					running.SoundId = Config.Id
				end
				update(char :: Model, running, false)
			end
		end
		for model, sound in bots do
			update(model, sound, true)
		end
	end)
end

return Footsteps
