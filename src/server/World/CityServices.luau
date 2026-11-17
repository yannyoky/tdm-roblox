-- Городские сервисы на карте с городом (Map/City). Настройки — Config/City.Services.
--   * Заправки (любой режим): машина с водителем стоит у колонки — её чинят (VehicleService.repair).
--     Пока идёт ремонт, у машины атрибут Repairing (подсказка в HUD машины).
--   * Киоски (только «Город», CityLife): подсказка «Магазин» открывает меню покупок у игрока
--     (клиент: src/client/CityInteract.luau, по атрибуту OpenMenu у подсказки).
--   * Парковки (только «Город»): «Вызвать машину» на свободном месте — личная машина своей стороны
--     (VehicleService.spawnPersonal). Одна на игрока, прежняя пропадает.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared.Config.City)
local VehicleService = require(script.Parent.VehicleService)

local CityServices = {}

local Cfg = CityConfig.Services
local REPAIR_TICK = 0.25

local pumps: { BasePart } = {}
local prompts: { ProximityPrompt } = {}
local lastCall: { [Player]: number } = {}
local overlap = OverlapParams.new()

local function cityOf(map: Instance?): Instance?
	return map and map:FindFirstChild("City")
end

local function clearPrompts()
	for _, p in prompts do
		local holder = p.Parent
		p:Destroy()
		if holder and holder:IsA("Attachment") and holder:GetAttribute("CityPrompt") then
			holder:Destroy()
		end
	end
	table.clear(prompts)
end

local function addPrompt(parent: Instance, action: string, object: string, key: Enum.KeyCode, distance: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	p.Parent = parent
	table.insert(prompts, p)
	return p
end

-- Свободно ли место: нет машин.
local function spotFree(spot: BasePart): boolean
	local vehicles = workspace:FindFirstChild("Vehicles")
	local list: { Instance } = {}
	if vehicles then
		table.insert(list, vehicles)
	end
	local traffic = workspace:FindFirstChild("Traffic")
	if traffic then
		table.insert(list, traffic)
	end
	-- Людей не считаем: вызывающий сам стоит у места, машина появится рядом с ним.
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = list
	local hits = workspace:GetPartBoundsInBox(spot.CFrame * CFrame.new(0, 3, 0), Vector3.new(7.5, 5, 16), overlap)
	return #hits == 0
end

local function callCar(player: Player, spot: BasePart)
	local now = os.clock()
	if now - (lastCall[player] or -math.huge) < Cfg.CarCallCooldown then
		return
	end
	local team = player.Team and player.Team:GetAttribute("Key")
	local typeId = team and Cfg.CarCall[team]
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not typeId or not hum or hum.Health <= 0 or hum.SeatPart then
		return
	end
	if not spotFree(spot) then
		return
	end
	lastCall[player] = now
	local look = spot.CFrame.LookVector
	local pos = Vector3.new(spot.Position.X, spot.Position.Y - 0.1, spot.Position.Z)
	VehicleService.spawnPersonal(player, typeId, CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z)))
end

local function setupLife(map: Instance?)
	clearPrompts()
	local city = cityOf(map)
	if not city or ReplicatedStorage:GetAttribute("CityLife") ~= true then
		return
	end
	-- Киоски.
	if Cfg.KioskPrompt then
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Kiosk" then
				local p = addPrompt(d, "Магазин", "Киоск", Enum.KeyCode.E, 8)
				p:SetAttribute("OpenMenu", "Shop")
			end
		end
	end
	-- Парковки.
	local spots = city:FindFirstChild("ParkingSpots")
	if spots then
		for _, spot in spots:GetChildren() do
			if spot:IsA("BasePart") then
				-- Места — невидимые плашки с CanQuery = false (пули сквозь них), а на такой детали
				-- подсказка не показывается. Поэтому точка подсказки — в Terrain, на высоте груди.
				local at = Instance.new("Attachment")
				at.Name = "ParkingPrompt"
				at:SetAttribute("CityPrompt", true)
				at.Position = spot.Position + Vector3.new(0, 3, 0) -- Terrain стоит в начале координат
				at.Parent = workspace.Terrain
				local p = addPrompt(at, "Вызвать машину", "Парковка", Enum.KeyCode.G, 10)
				p.HoldDuration = 0.6
				p.Triggered:Connect(function(player)
					callCar(player, spot)
				end)
			end
		end
	end
end

local function collectPumps(map: Instance?)
	table.clear(pumps)
	local city = cityOf(map)
	local folder = city and city:FindFirstChild("FuelPumps")
	if folder then
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(pumps, p)
			end
		end
	end
end

local function repairTick(dt: number)
	if #pumps == 0 then
		return
	end
	local vehicles = workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return
	end
	for _, model in vehicles:GetChildren() do
		local root = model:IsA("Model") and model.PrimaryPart
		if not root then
			continue
		end
		local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
		local repairing = false
		if seat and seat.Occupant and root.AssemblyLinearVelocity.Magnitude < Cfg.RepairMaxSpeed then
			for _, pump in pumps do
				local d = root.Position - pump.Position
				if Vector3.new(d.X, 0, d.Z).Magnitude < Cfg.RepairRadius then
					repairing = VehicleService.repair(model, Cfg.RepairPerSecond * dt)
					break
				end
			end
		end
		if (model:GetAttribute("Repairing") == true) ~= repairing then
			model:SetAttribute("Repairing", if repairing then true else nil)
		end
	end
end

function CityServices.init(mapChanged: RBXScriptSignal)
	mapChanged:Connect(function(map)
		collectPumps(map)
		setupLife(map)
	end)
	ReplicatedStorage:GetAttributeChangedSignal("CityLife"):Connect(function()
		setupLife(workspace:FindFirstChild("Map"))
	end)
	local map = workspace:FindFirstChild("Map")
	collectPumps(map)
	setupLife(map)
	Players.PlayerRemoving:Connect(function(player)
		lastCall[player] = nil
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= REPAIR_TICK then
			repairTick(acc)
			acc = 0
		end
	end)
end

return CityServices
