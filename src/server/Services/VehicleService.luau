-- Автопарк: машины на площадках баз, посадка, урон, взрыв, возврат брошенных машин.
--
-- Для других систем:
--   VehicleService.damage(model, amount, attacker?)  -- урон машине (оружие, гранаты)
--   VehicleService.fromPart(part) -> Model?          -- машина, которой принадлежит деталь
--   VehicleService.isInVehicle(character) -> boolean
--   VehicleService.resetFleet()                      -- все машины заново на площадки (новый раунд/карта)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehiclesConfig = require(Shared.Config.Vehicles)
local VehicleBuilder = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("VehicleBuilder"))
local MapService = require(script.Parent.MapService)

local VehicleService = {}

type PadRecord = {
	pad: BasePart,
	team: string,
	typeId: string,
	vehicle: Model?,
	respawnAt: number?,
	emptySince: number?,
}

local folder: Folder
local pads: { PadRecord } = {}

local function teamOf(player: Player): string?
	return player.Team and player.Team:GetAttribute("Key")
end

local function canUse(player: Player, model: Model): boolean
	if not VehiclesConfig.TeamLocked then
		return true
	end
	return teamOf(player) == model:GetAttribute("Team")
end

local function seatsOf(model: Model): { Seat | VehicleSeat }
	local list = {}
	for _, child in model:GetChildren() do
		if child:IsA("Seat") or child:IsA("VehicleSeat") then
			table.insert(list, child)
		end
	end
	return list
end

local function isEmpty(model: Model): boolean
	for _, seat in seatsOf(model) do
		if seat.Occupant then
			return false
		end
	end
	return true
end

local function humanoidOf(player: Player): Humanoid?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and not char:GetAttribute("InLobby") then
		return hum
	end
	return nil
end

local function eject(seat: Seat | VehicleSeat)
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	local hum = seat.Occupant
	if hum then
		hum.Sit = false
		hum.Jump = true
	end
end

-- Нет водителя: шарниры в «ручник», физику снова считает сервер.
local function parkDrive(model: Model)
	local drive = model:FindFirstChild("Drive")
	if not drive then
		return
	end
	local torque = model:GetAttribute("Torque") or 5000
	for _, c in drive:GetChildren() do
		if c:IsA("HingeConstraint") then
			if c.ActuatorType == Enum.ActuatorType.Motor then
				c.AngularVelocity = 0
				c.MotorMaxTorque = torque * 0.5
			else
				c.TargetAngle = 0
			end
		end
	end
end

local function setOwner(model: Model, player: Player?)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			pcall(function()
				if player then
					part:SetNetworkOwner(player)
				else
					part:SetNetworkOwnershipAuto()
				end
			end)
		end
	end
end

local function explode(model: Model, record: PadRecord?)
	if model:GetAttribute("Destroyed") then
		return
	end
	model:SetAttribute("Destroyed", true)
	model:SetAttribute("Health", 0)
	local root = model.PrimaryPart
	if root then
		local blast = Instance.new("Explosion")
		blast.Position = root.Position
		blast.BlastRadius = 14
		blast.BlastPressure = 0 -- без разлёта деталей, урон считаем сами
		blast.DestroyJointRadiusPercent = 0
		blast.ExplosionType = Enum.ExplosionType.NoCraters
		blast.Parent = workspace
	end
	for _, seat in seatsOf(model) do
		local hum = seat.Occupant
		eject(seat)
		if hum then
			local attacker = model:GetAttribute("LastAttacker")
			if attacker then
				hum:SetAttribute("LastAttacker", attacker)
			end
			hum:TakeDamage(VehiclesConfig.ExplosionDamage)
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			d.Enabled = false
		elseif d:IsA("BasePart") and d.Transparency < 1 then
			d.Color = d.Color:Lerp(Color3.fromRGB(20, 20, 20), 0.8)
			d.Material = Enum.Material.CorrodedMetal
		end
	end
	parkDrive(model)
	if record then
		record.respawnAt = os.clock() + (VehiclesConfig.Types[record.typeId].RespawnTime or 20)
	end
	task.delay(6, function()
		model:Destroy()
	end)
end

function VehicleService.fromPart(part: Instance): Model?
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("IsVehicle") then
			return node
		end
		node = node.Parent
	end
	return nil
end

function VehicleService.isInVehicle(character: Model): boolean
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	return seat ~= nil and VehicleService.fromPart(seat) ~= nil
end

function VehicleService.damage(model: Model, amount: number, attacker: Player?)
	if model:GetAttribute("Destroyed") or amount <= 0 then
		return
	end
	if attacker and teamOf(attacker) == model:GetAttribute("Team") then
		return -- по своим машинам урона нет
	end
	if attacker then
		model:SetAttribute("LastAttacker", attacker.UserId)
	end
	local hp = (model:GetAttribute("Health") or 0) - amount
	model:SetAttribute("Health", math.max(0, hp))
	if hp <= 0 then
		local record
		for _, r in pads do
			if r.vehicle == model then
				record = r
			end
		end
		explode(model, record)
	end
end

-- Наезд: сбитый на скорости противник получает урон.
local function setupRam(model: Model)
	local root = model.PrimaryPart :: BasePart
	local recent: { [Humanoid]: number } = {}
	local function onTouched(hit: BasePart)
		local speed = root.AssemblyLinearVelocity.Magnitude
		if speed < VehiclesConfig.RamMinSpeed then
			return
		end
		local char = hit.Parent
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or hum.SeatPart then
			return
		end
		local now = os.clock()
		if recent[hum] and now - recent[hum] < 1 then
			return
		end
		local victim = Players:GetPlayerFromCharacter(char)
		local victimTeam = if victim then teamOf(victim) else char:GetAttribute("Team")
		if victimTeam == model:GetAttribute("Team") then
			return
		end
		recent[hum] = now
		local driverSeat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
		local driverHum = driverSeat and driverSeat.Occupant
		local driver = driverHum and Players:GetPlayerFromCharacter(driverHum.Parent)
		if driver then
			hum:SetAttribute("LastAttacker", driver.UserId)
			hum:SetAttribute("LastWeapon", nil)
		end
		hum:TakeDamage(VehiclesConfig.RamDamage * math.clamp(speed / 60, 0.6, 1.6))
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and (part.Name == "Chassis" or part.Name == "Hood" or part.Name == "Bumper") then
			part.Touched:Connect(onTouched)
		end
	end
end

local function prompt(parent: Instance, action: string, object: string, key: Enum.KeyCode, offset: Vector2?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key
	p.HoldDuration = 0
	p.MaxActivationDistance = 11
	p.RequiresLineOfSight = false
	if offset then
		p.UIOffset = offset
	end
	p.Parent = parent
	return p
end

local function setupVehicle(model: Model, record: PadRecord?)
	local driverSeat = model:FindFirstChild("DriverSeat") :: VehicleSeat
	local chassis = model.PrimaryPart :: BasePart
	local name = model.Name

	-- Посадка по кнопке: E — за руль, F — пассажиром.
	prompt(driverSeat, "За руль", name, Enum.KeyCode.E).Triggered:Connect(function(player)
		local hum = humanoidOf(player)
		if not hum or hum.SeatPart or not canUse(player, model) or model:GetAttribute("Destroyed") then
			return
		end
		if driverSeat.Occupant == nil then
			driverSeat:Sit(hum)
		end
	end)
	prompt(chassis, "Пассажиром", name, Enum.KeyCode.F, Vector2.new(0, 80)).Triggered:Connect(function(player)
		local hum = humanoidOf(player)
		if not hum or hum.SeatPart or not canUse(player, model) or model:GetAttribute("Destroyed") then
			return
		end
		for _, seat in seatsOf(model) do
			if seat ~= driverSeat and seat.Occupant == nil then
				seat:Sit(hum)
				return
			end
		end
	end)
	local flip = prompt(chassis, "Перевернуть", name, Enum.KeyCode.G, Vector2.new(0, 160))
	flip.HoldDuration = 1
	flip.Enabled = false
	flip.Triggered:Connect(function(player)
		if not canUse(player, model) or model:GetAttribute("Destroyed") then
			return
		end
		local pos = chassis.Position
		local look = chassis.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.1 then
			flat = Vector3.new(0, 0, -1)
		end
		model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 4, 0), pos + Vector3.new(0, 4, 0) + flat.Unit))
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
	end)

	-- Чужие не садятся даже касанием; водитель получает физику машины себе.
	for _, seat in seatsOf(model) do
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local hum = seat.Occupant
			local player = hum and Players:GetPlayerFromCharacter(hum.Parent)
			if hum and (not player or not canUse(player, model) or model:GetAttribute("Destroyed")) then
				task.defer(eject, seat)
				return
			end
			if seat == driverSeat then
				if player then
					model:SetAttribute("Driver", player.UserId)
					setOwner(model, player)
				else
					model:SetAttribute("Driver", nil)
					parkDrive(model)
					task.defer(setOwner, model, nil)
				end
			end
			if record then
				record.emptySince = if isEmpty(model) then os.clock() else nil
			end
		end)
	end

	setupRam(model)
end

local function spawnAt(record: PadRecord)
	local pad = record.pad
	local look = pad.CFrame.LookVector
	local ground = CFrame.lookAt(Vector3.new(pad.Position.X, pad.Position.Y - 0.1, pad.Position.Z), Vector3.new(pad.Position.X, pad.Position.Y - 0.1, pad.Position.Z) + Vector3.new(look.X, 0, look.Z))
	local model = VehicleBuilder.build(record.typeId, ground, record.team)
	setupVehicle(model, record)
	model.Parent = folder
	record.vehicle = model
	record.respawnAt = nil
	record.emptySince = os.clock()
end

function VehicleService.resetFleet()
	folder:ClearAllChildren()
	table.clear(pads)
	local map = workspace:FindFirstChild("Map")
	local padsFolder = map and map:FindFirstChild("VehiclePads")
	if not padsFolder then
		return
	end
	for _, teamFolder in padsFolder:GetChildren() do
		for _, pad in teamFolder:GetChildren() do
			local typeId = pad:GetAttribute("VehicleType")
			if pad:IsA("BasePart") and typeId and VehiclesConfig.Types[typeId] then
				local record: PadRecord = { pad = pad, team = pad:GetAttribute("Team") or teamFolder.Name, typeId = typeId }
				table.insert(pads, record)
				spawnAt(record)
			end
		end
	end
end

-- Раз в секунду: респаун потерянных машин, возврат брошенных, кнопка «перевернуть».
local function tick()
	local now = os.clock()
	for _, record in pads do
		local model = record.vehicle
		if model and model.Parent == nil then
			record.vehicle = nil
			model = nil
			record.respawnAt = record.respawnAt or now
		end
		if not model then
			if record.respawnAt and now >= record.respawnAt then
				spawnAt(record)
			end
			continue
		end
		if model:GetAttribute("Destroyed") then
			continue
		end
		local root = model.PrimaryPart
		if not root then
			continue
		end
		-- Упала с карты.
		if root.Position.Y < -50 then
			model:Destroy()
			record.vehicle = nil
			record.respawnAt = now + 3
			continue
		end
		-- Брошена вдали от площадки.
		local farFromPad = (root.Position - record.pad.Position).Magnitude > 40
		if record.emptySince and farFromPad and now - record.emptySince > VehiclesConfig.AbandonTime then
			model:Destroy()
			record.vehicle = nil
			record.respawnAt = now + 1
			continue
		end
		local flip: ProximityPrompt? = nil
		for _, p in root:GetChildren() do
			if p:IsA("ProximityPrompt") and p.ActionText == "Перевернуть" then
				flip = p
			end
		end
		if flip then
			flip.Enabled = root.CFrame.UpVector.Y < 0.4 and root.AssemblyLinearVelocity.Magnitude < 8
		end
	end
end

function VehicleService.init()
	folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = workspace

	MapService.Changed:Connect(function()
		VehicleService.resetFleet()
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 1 then
			acc = 0
			tick()
		end
	end)
end

return VehicleService
