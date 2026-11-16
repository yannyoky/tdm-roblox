-- Погода у игрока: капли дождя вокруг камеры, звук дождя и грома, мокрый блестящий асфальт,
-- вспышки молний. Какая погода — решает сервер (src/server/World/Environment.luau) и пишет
-- в атрибуты ReplicatedStorage: RainIntensity (0..1) и LightningStrike (счётчик вспышек).
-- Настройки — src/shared/Config/City.luau (Weather).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.City).Weather

local Weather = {}

local player = Players.LocalPlayer
local PARK = CFrame.new(0, -5000, 0)
-- Поверхности, которые блестят под дождём.
local WET_NAMES = { Ground = true, Sidewalk = true, Lot = true, Curb = true, Path = true, CurbRamp = true, BaseFloor = true }

local drops: { BasePart } = {}
local dropPos: { Vector3 } = {}
local dropEnd: { number } = {}
local active = 0
local rain = 0
local wetness = 0
local appliedWet = -1
local wetParts: { BasePart } = {}
local wetBase: { [BasePart]: number } = {}
local wetMap: Instance? = nil

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function makeDrops(folder: Instance)
	for i = 1, Config.Drops do
		local p = Instance.new("Part")
		p.Name = "Drop"
		p.Size = Vector3.new(0.06, 2.6, 0.06)
		p.Color = Color3.fromRGB(196, 206, 220)
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = 0.55
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.CFrame = PARK
		p.Parent = folder
		drops[i] = p
		dropPos[i] = PARK.Position
		dropEnd[i] = 0
	end
end

-- Новая капля над случайной точкой вокруг камеры (чаще перед ней), конец — первая поверхность снизу.
local function respawn(i: number, cam: CFrame)
	local r = Config.DropRadius * math.sqrt(math.random())
	local a = math.random() * math.pi * 2
	local look = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
	local center = cam.Position + (if look.Magnitude > 0.01 then look.Unit * Config.DropRadius * 0.35 else Vector3.zero)
	local x, z = center.X + math.cos(a) * r, center.Z + math.sin(a) * r
	local y = cam.Position.Y + 8 + math.random() * 45
	local hit = workspace:Raycast(Vector3.new(x, y, z), Vector3.new(0, -300, 0), params)
	dropPos[i] = Vector3.new(x, y, z)
	dropEnd[i] = if hit then hit.Position.Y else y - 300
end

local function collectWet(map: Instance?)
	-- Вернуть прежний блеск старой карте и собрать поверхности новой.
	for part, base in wetBase do
		if part.Parent then
			part.Reflectance = base
		end
	end
	table.clear(wetParts)
	table.clear(wetBase)
	wetMap = map
	appliedWet = -1
	if not map then
		return
	end
	for _, inst in map:GetDescendants() do
		if inst:IsA("BasePart") and WET_NAMES[inst.Name] then
			table.insert(wetParts, inst)
			wetBase[inst] = inst.Reflectance
		end
	end
end

local flash: ColorCorrectionEffect? = nil

local function lightning()
	if not flash or not flash.Parent then
		local f = Instance.new("ColorCorrectionEffect")
		f.Name = "LightningFlash"
		f.Parent = Lighting
		flash = f
	end
	local f = flash :: ColorCorrectionEffect
	task.spawn(function()
		for _ = 1, math.random(1, 3) do
			f.Brightness = 0.45 + math.random() * 0.3
			f.TintColor = Color3.fromRGB(215, 225, 255)
			TweenService:Create(f, TweenInfo.new(0.18), { Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
			task.wait(0.08 + math.random() * 0.15)
		end
	end)
	if Config.ThunderSound ~= 0 then
		task.delay(0.6 + math.random() * 2.4, function()
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. Config.ThunderSound
			s.Volume = 0.8
			s.PlaybackSpeed = 0.85 + math.random() * 0.3
			s.Parent = SoundService
			s:Play()
			s.Ended:Once(function()
				s:Destroy()
			end)
		end)
	end
end

function Weather.init()
	local folder = Instance.new("Folder")
	folder.Name = "Rain"
	folder.Parent = workspace.CurrentCamera
	makeDrops(folder)

	local rainSound: Sound? = nil
	if Config.RainSound ~= 0 then
		local s = Instance.new("Sound")
		s.Name = "RainLoop"
		s.SoundId = "rbxassetid://" .. Config.RainSound
		s.Looped = true
		s.Volume = 0
		s.Parent = SoundService
		rainSound = s
	end

	local function readRain()
		rain = ReplicatedStorage:GetAttribute("RainIntensity") or 0
	end
	readRain()
	ReplicatedStorage:GetAttributeChangedSignal("RainIntensity"):Connect(readRain)
	ReplicatedStorage:GetAttributeChangedSignal("LightningStrike"):Connect(function()
		if rain > 0.3 then
			lightning()
		end
	end)

	local wetAcc = 0
	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local cam = camera.CFrame
		params.FilterDescendantsInstances = { folder, player.Character :: Instance }

		-- Капли.
		local want = math.floor(Config.Drops * rain + 0.5)
		if want < active then
			for i = want + 1, active do
				drops[i].CFrame = PARK
			end
		end
		if want > active then
			for i = active + 1, want do
				respawn(i, cam)
				-- Разбросать по высоте, чтобы не падали стеной.
				dropPos[i] -= Vector3.new(0, math.random() * 40, 0)
			end
		end
		active = want
		if active > 0 then
			local parts = table.create(active)
			local cfs = table.create(active)
			local fall = Config.DropSpeed * dt
			local wind = Vector3.new(0.12, 0, 0.05) * fall
			for i = 1, active do
				local p = dropPos[i] - Vector3.new(0, fall, 0) + wind
				if p.Y < dropEnd[i] or (p - cam.Position).Magnitude > Config.DropRadius * 1.6 then
					respawn(i, cam)
					p = dropPos[i]
				end
				dropPos[i] = p
				parts[i] = drops[i]
				cfs[i] = CFrame.new(p) * CFrame.Angles(0.06, 0, -0.12)
			end
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- Звук: громче в сильный дождь.
		if rainSound then
			local vol = rain * 0.7
			if vol > 0.01 and not rainSound.IsPlaying then
				rainSound:Play()
			end
			rainSound.Volume += (vol - rainSound.Volume) * math.min(1, dt * 2)
			if vol <= 0.01 and rainSound.Volume < 0.02 and rainSound.IsPlaying then
				rainSound:Stop()
			end
		end

		-- Мокрый асфальт: намокает за ~20 с, сохнет за ~90 с.
		wetAcc += dt
		if wetAcc >= 0.5 then
			local step = wetAcc
			wetAcc = 0
			local map = workspace:FindFirstChild("Map")
			if map ~= wetMap then
				collectWet(map)
			end
			if rain > wetness then
				wetness = math.min(rain, wetness + step / 20)
			else
				wetness = math.max(rain, wetness - step / 90)
			end
			if math.abs(wetness - appliedWet) > 0.04 or (wetness == 0 and appliedWet ~= 0) then
				appliedWet = wetness
				for _, part in wetParts do
					if part.Parent then
						part.Reflectance = (wetBase[part] or 0) + wetness * Config.WetReflectance
					end
				end
			end
		end
	end)
end

return Weather
