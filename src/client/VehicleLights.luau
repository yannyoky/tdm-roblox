-- Свет машин у каждого игрока: фары, габариты, стоп-сигналы, задний ход.
--   * Фары и габариты горят ночью и в ливень (атрибут ReplicatedStorage.Night, ставит World/Environment),
--     только у машины с водителем.
--   * Стоп-сигналы: у своей машины — по педали тормоза; у чужих — по замедлению (скорость машины
--     приходит по сети, так что торможение видно всем без лишних сообщений).
--   * Белые фонари — при движении назад.
-- Детали фонарей добавляет World/VehicleBuilder.luau (Headlight, HeadlightGlow, TailLight, ReverseLight).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VehicleLights = {}

local player = Players.LocalPlayer
local MAX_DISTANCE = 350

type Lamps = {
	model: Model,
	head: { BasePart },
	glow: { BasePart },
	tail: { BasePart },
	reverse: { BasePart },
	prevSpeed: number,
	decel: number,
	state: string,
}

local cars: { [Model]: Lamps } = {}

local function collect(model: Model): Lamps
	local l: Lamps = { model = model, head = {}, glow = {}, tail = {}, reverse = {}, prevSpeed = 0, decel = 0, state = "" }
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name == "Headlight" then
				table.insert(l.head, p)
			elseif p.Name == "HeadlightGlow" then
				table.insert(l.glow, p)
			elseif p.Name == "TailLight" then
				table.insert(l.tail, p)
			elseif p.Name == "ReverseLight" then
				table.insert(l.reverse, p)
			end
		end
	end
	return l
end

local function setLight(parts: { BasePart }, transparency: number, lightOn: boolean)
	for _, p in parts do
		p.Transparency = transparency
		local light = p:FindFirstChildWhichIsA("Light")
		if light then
			light.Enabled = lightOn
		end
	end
end

local function apply(l: Lamps, heads: boolean, brake: boolean, reverse: boolean)
	local key = (if heads then "H" else "-") .. (if brake then "B" else "-") .. (if reverse then "R" else "-")
	if key == l.state then
		return
	end
	l.state = key
	setLight(l.head, 1, heads)
	setLight(l.glow, if heads then 0.05 else 1, false)
	-- Габарит тусклый, стоп яркий (с подсветкой асфальта).
	setLight(l.tail, if brake then 0 elseif heads then 0.45 else 1, brake)
	setLight(l.reverse, if reverse then 0 else 1, reverse)
end

local function update(l: Lamps, dt: number, camPos: Vector3, night: boolean)
	local model = l.model
	local root = model.PrimaryPart
	local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
	if not root or not seat or model:GetAttribute("Destroyed") then
		apply(l, false, false, false)
		return
	end
	if (root.Position - camPos).Magnitude > MAX_DISTANCE then
		return
	end
	local driver = seat.Occupant
	local forward = root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector)
	local a = (forward - l.prevSpeed) / dt
	l.prevSpeed = forward
	-- Замедление (знак к скорости), сглаженное.
	local slowing = if forward > 0 then -a else a
	l.decel += (slowing - l.decel) * math.min(1, dt * 10)

	local brake, reverse = false, false
	if driver then
		if driver.Parent == player.Character then
			-- Своя машина: тормоз — педаль против хода или ручник (Shift).
			local throttle = seat.ThrottleFloat
			brake = (throttle < -0.05 and forward > 1.5) or (throttle > 0.05 and forward < -1.5)
			reverse = throttle < -0.05 and forward <= 1.5
		else
			brake = l.decel > 12 and math.abs(forward) > 1
			reverse = forward < -1.5
		end
	end
	apply(l, night and driver ~= nil, brake, reverse and not brake)
end

function VehicleLights.init()
	local function add(model: Instance)
		if model:IsA("Model") and model:GetAttribute("IsVehicle") and not cars[model] then
			cars[model] = collect(model)
		end
	end
	local function watchFolder(folder: Instance)
		folder.ChildAdded:Connect(function(child)
			task.wait() -- детали машины приходят вместе с моделью, но дадим кадр
			add(child)
		end)
		folder.ChildRemoved:Connect(function(child)
			cars[child :: Model] = nil
		end)
		for _, child in folder:GetChildren() do
			add(child)
		end
	end
	local folder = workspace:FindFirstChild("Vehicles")
	if folder then
		watchFolder(folder)
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Vehicles" and child:IsA("Folder") then
			watchFolder(child)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		dt = math.max(dt, 1 / 240)
		local camPos = workspace.CurrentCamera.CFrame.Position
		local night = ReplicatedStorage:GetAttribute("Night") == true
		for model, l in cars do
			if model.Parent then
				-- При StreamingEnabled детали могли прийти позже: пересобираем, если фонарей нет.
				if #l.tail == 0 and #l.head == 0 and model:FindFirstChild("TailLight") then
					cars[model] = collect(model)
					l = cars[model]
				end
				update(l, dt, camPos, night)
			else
				cars[model] = nil
			end
		end
	end)
end

return VehicleLights
