-- Камера главного меню: медленный пролёт над текущей картой, как в меню GTA.
-- Планы сменяются через затемнение: облёт центра сверху, проезд вдоль улицы на малой высоте,
-- подъём над зоной захвата или базой. Высота подбирается лучами вниз, чтобы не влететь в дома.
-- После «Играть» камера через затемнение переходит в штаб и плавно подлетает за спину игрока.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MapsConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.Maps)

local player = Players.LocalPlayer

local MenuCamera = {}

local SHOT_TIME = 9 -- секунд на один план
local FADE_TIME = 0.7
local FOV = 60

local running = false
local token = 0
local fade: Frame? = nil
local savedFov = 70

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function camera(): Camera
	return workspace.CurrentCamera
end

local function getFade(): Frame
	if fade and fade.Parent then
		return fade
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MenuCameraFade"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5 -- под окнами меню (у них 10), но над HUD
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	fade = f
	return f
end

local function fadeTo(alpha: number, time: number)
	local f = getFade()
	local tween = TweenService:Create(f, TweenInfo.new(time, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 - alpha })
	tween:Play()
	tween.Completed:Wait()
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Высота крыш и земли под точкой (по карте; штабы и персонажи не мешают).
local function groundAt(x: number, z: number): number
	local map = workspace:FindFirstChild("Map")
	if not map then
		return 0
	end
	params.FilterDescendantsInstances = {}
	local hit = workspace:Raycast(Vector3.new(x, 350, z), Vector3.new(0, -500, 0), params)
	if hit and hit.Instance:IsDescendantOf(map) then
		return hit.Position.Y
	end
	return if hit and hit.Position.Y < 300 then hit.Position.Y else 0
end

-- Наивысшая точка под отрезком a→b (несколько проб).
local function clearance(a: Vector3, b: Vector3): number
	local top = -math.huge
	for i = 0, 6 do
		local p = a:Lerp(b, i / 6)
		top = math.max(top, groundAt(p.X, p.Z))
	end
	return top
end

type Shot = { from: CFrame, to: CFrame }

-- Интересные точки карты: зоны захвата и базы.
local function pointsOfInterest(map: Instance): { Vector3 }
	local list = {}
	for _, folderName in { "CapturePoints", "Bases" } do
		local f = map:FindFirstChild(folderName)
		if f then
			for _, item in f:GetChildren() do
				if item:IsA("BasePart") then
					table.insert(list, item.Position)
				elseif item:IsA("Model") then
					table.insert(list, item:GetPivot().Position)
				end
			end
		end
	end
	return list
end

local function makeShot(rng: Random, kind: number): Shot
	local map = workspace:FindFirstChild("Map")
	local mapId = map and map:GetAttribute("MapId")
	local cfg = mapId and MapsConfig.List[mapId]
	local half = (if cfg and cfg.Size then cfg.Size else 1000) * 0.5
	local center = Vector3.zero

	if kind == 1 then
		-- Облёт центра карты сверху.
		local r = half * rng:NextNumber(0.45, 0.6)
		local a0 = rng:NextNumber(0, math.pi * 2)
		local a1 = a0 + math.rad(rng:NextNumber(18, 26)) * (if rng:NextNumber() < 0.5 then -1 else 1)
		local p0 = center + Vector3.new(math.cos(a0) * r, 0, math.sin(a0) * r)
		local p1 = center + Vector3.new(math.cos(a1) * r, 0, math.sin(a1) * r)
		local y = clearance(p0, p1) + rng:NextNumber(70, 100)
		local look = center + Vector3.new(0, 0, 0)
		return {
			from = CFrame.lookAt(Vector3.new(p0.X, y, p0.Z), look),
			to = CFrame.lookAt(Vector3.new(p1.X, y, p1.Z), look),
		}
	elseif kind == 2 then
		-- Пролёт на малой высоте вдоль прямой через город.
		local start = Vector3.new(rng:NextNumber(-half, half) * 0.5, 0, rng:NextNumber(-half, half) * 0.5)
		local dir = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0).LookVector
		local finish = start + dir * rng:NextNumber(110, 150)
		local y = clearance(start - dir * 20, finish + dir * 60) + rng:NextNumber(16, 26)
		local p0, p1 = Vector3.new(start.X, y, start.Z), Vector3.new(finish.X, y, finish.Z)
		local down = Vector3.new(0, -0.32, 0)
		return {
			from = CFrame.lookAt(p0, p0 + dir + down),
			to = CFrame.lookAt(p1, p1 + dir + down),
		}
	else
		-- Подъём над интересной точкой (зона капта, база), камера смотрит на неё.
		local pois = if map then pointsOfInterest(map) else {}
		local target = if #pois > 0 then pois[rng:NextInteger(1, #pois)] else center
		target = Vector3.new(target.X, groundAt(target.X, target.Z), target.Z)
		local a = rng:NextNumber(0, math.pi * 2)
		local off = Vector3.new(math.cos(a), 0, math.sin(a))
		local p0 = target + off * 70
		local p1 = target + off * 95
		local base = clearance(p0, target)
		local y0 = math.max(base + 14, target.Y + 14)
		local y1 = math.max(clearance(p1, target) + 60, target.Y + 70)
		return {
			from = CFrame.lookAt(Vector3.new(p0.X, y0, p0.Z), target),
			to = CFrame.lookAt(Vector3.new(p1.X, y1, p1.Z), target),
		}
	end
end

-- Попросить сервер прислать детали вокруг точки (при StreamingEnabled).
local function stream(position: Vector3)
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(position, 2)
		end)
	end)
end

-- Запустить пролёт (если ещё не идёт).
function MenuCamera.start()
	if running then
		return
	end
	running = true
	token += 1
	local my = token
	local cam = camera()
	savedFov = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = FOV
	getFade().BackgroundTransparency = 0

	task.spawn(function()
		local rng = Random.new()
		local kind = rng:NextInteger(1, 3)
		while running and my == token do
			local shot = makeShot(rng, kind)
			stream(shot.from.Position)
			kind = kind % 3 + 1
			local t0 = os.clock()
			local conn = RunService.RenderStepped:Connect(function()
				if my ~= token then
					return
				end
				local t = (os.clock() - t0) / SHOT_TIME
				-- Почти равномерно, с мягким началом и концом.
				local k = 0.15 * smooth(t) + 0.85 * t
				cam = camera()
				cam.CameraType = Enum.CameraType.Scriptable
				cam.CFrame = shot.from:Lerp(shot.to, math.clamp(k, 0, 1))
			end)
			fadeTo(0, FADE_TIME)
			local wait = SHOT_TIME - FADE_TIME * 2
			local waited = 0
			while waited < wait and my == token do
				waited += task.wait(0.1)
			end
			if my ~= token then
				conn:Disconnect()
				return
			end
			fadeTo(1, FADE_TIME)
			conn:Disconnect()
		end
	end)
end

-- Вернуть обычную камеру. С toCharacter — через затемнение подлететь за спину персонажа.
function MenuCamera.stop(toCharacter: boolean?)
	if not running then
		return
	end
	running = false
	token += 1
	local my = token
	task.spawn(function()
		fadeTo(1, 0.4)
		local cam = camera()
		local char = player.Character or player.CharacterAdded:Wait()
		local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		local hum = char:FindFirstChildOfClass("Humanoid")
		if toCharacter and root and my == token then
			-- Из-под потолка штаба к точке за спиной игрока.
			local behind = root.CFrame * CFrame.new(0, 3, 11)
			local high = root.CFrame * CFrame.new(4, 9, 22)
			local look = root.Position + Vector3.new(0, 1.5, 0)
			local from = CFrame.lookAt(high.Position, look)
			local to = CFrame.lookAt(behind.Position, look)
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = from
			cam.FieldOfView = savedFov
			local t0 = os.clock()
			local conn = RunService.RenderStepped:Connect(function()
				local t = smooth((os.clock() - t0) / 1.4)
				cam.CFrame = from:Lerp(to, t)
			end)
			fadeTo(0, 0.5)
			task.wait(0.9)
			conn:Disconnect()
		end
		if my ~= token then
			return
		end
		cam.FieldOfView = savedFov
		if hum then
			cam.CameraSubject = hum
		end
		cam.CameraType = Enum.CameraType.Custom
		fadeTo(0, 0.2)
	end)
end

function MenuCamera.isRunning(): boolean
	return running
end

return MenuCamera
