-- Собирает машину из описания в Config/Vehicles.
-- Устройство: тяжёлое шасси (PrimaryPart) + приваренный лёгкий кузов + 4 колеса на шарнирах.
--   Задние колёса: HingeConstraint-мотор прямо на шасси.
--   Передние: поворотный кулак (HingeConstraint-сервопривод, ось вверх) + мотор колеса.
-- Шарниры лежат в папке Drive (Motor_FL/FR/RL/RR, Steer_FL/FR); ими управляет клиент водителя
-- (src/client/VehicleController.luau), потому что физику машины считает его компьютер.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehiclesConfig = require(Shared.Config.Vehicles)
local TeamsConfig = require(Shared.Config.Teams)

local VehicleBuilder = {}

local WHEEL_WIDTH = 1.2
local DARK = Color3.fromRGB(28, 28, 30)

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function attachment(parent: BasePart, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end

-- Кабина «каркасом» (стойки и крыша, без стёкол): из машины можно стрелять, и её видно насквозь.
local STYLES = {
	sedan = { cabin = { -2.6, 3.6 }, roofY = 4.9, hood = 0.26, trunk = true },
	suv = { cabin = { -3.2, 4.6 }, roofY = 5.4, hood = 0.22, trunk = true },
	pickup = { cabin = { -4.4, -0.6 }, roofY = 5.0, hood = 0.22, bed = true },
	van = { cabin = { -5.2, 7.0 }, roofY = 5.7, hood = 0.13 },
	armored = { cabin = { -5.6, 7.6 }, roofY = 5.9, hood = 0.14, armor = true },
}

function VehicleBuilder.build(typeId: string, groundCf: CFrame, teamKey: string): Model
	local cfg = VehiclesConfig.Types[typeId]
	assert(cfg, "Нет машины " .. tostring(typeId))
	local style = STYLES[cfg.Style] or STYLES.sedan
	local W, L, R = cfg.Width, cfg.Length, cfg.WheelRadius

	local model = Instance.new("Model")
	model.Name = cfg.Name
	model:SetAttribute("IsVehicle", true)
	model:SetAttribute("VehicleType", typeId)
	model:SetAttribute("Team", teamKey)
	model:SetAttribute("MaxHealth", cfg.Health)
	model:SetAttribute("Health", cfg.Health)
	model:SetAttribute("MaxSpeed", cfg.MaxSpeed)
	model:SetAttribute("ReverseSpeed", cfg.ReverseSpeed)
	model:SetAttribute("Torque", cfg.Torque)
	model:SetAttribute("SteerAngle", cfg.SteerAngle)
	model:SetAttribute("WheelRadius", R)
	model:SetAttribute("DriveSign", VehiclesConfig.DriveSign)
	model:SetAttribute("SteerSign", VehiclesConfig.SteerSign)

	-- Центр шасси поднят так, чтобы колёса чуть касались земли.
	local rootCf = groundCf * CFrame.new(0, R + 0.3 + 0.3, 0)
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(W, 1, L)
	chassis.CFrame = rootCf
	chassis.Color = cfg.Accent
	chassis.Material = Enum.Material.Metal
	chassis.CustomPhysicalProperties = PhysicalProperties.new(3, 0.3, 0, 1, 1)
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.Parent = model
	model.PrimaryPart = chassis

	local function body(name: string, size: Vector3, offset: Vector3, color: Color3, mat: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = rootCf * CFrame.new(offset)
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		weld(chassis, p)
		return p
	end

	local top = 0.5 -- верх шасси
	local sideH = if style.armor then 2.2 else 1.3
	local c0, c1 = style.cabin[1], math.min(style.cabin[2], L / 2 - 0.3)
	local cabinLen, cabinZ = c1 - c0, (c0 + c1) / 2

	-- Капот.
	local hoodLen = math.max(1.5, L * style.hood)
	body("Hood", Vector3.new(W, 1.3, hoodLen), Vector3.new(0, top + 0.65, -L / 2 + hoodLen / 2), cfg.Body)
	body("Bumper", Vector3.new(W + 0.2, 0.6, 0.5), Vector3.new(0, top - 0.1, -L / 2 - 0.1), DARK)
	body("Bumper", Vector3.new(W + 0.2, 0.6, 0.5), Vector3.new(0, top - 0.1, L / 2 + 0.1), DARK)
	-- Фары.
	body("Headlight", Vector3.new(1, 0.5, 0.2), Vector3.new(-W / 2 + 0.8, top + 0.9, -L / 2 - 0.05), Color3.fromRGB(255, 250, 220), Enum.Material.Neon)
	body("Headlight", Vector3.new(1, 0.5, 0.2), Vector3.new(W / 2 - 0.8, top + 0.9, -L / 2 - 0.05), Color3.fromRGB(255, 250, 220), Enum.Material.Neon)

	-- Борта кабины (низкие, через верх можно стрелять).
	body("Door", Vector3.new(0.3, sideH, cabinLen), Vector3.new(-W / 2 + 0.15, top + sideH / 2, cabinZ), cfg.Body)
	body("Door", Vector3.new(0.3, sideH, cabinLen), Vector3.new(W / 2 - 0.15, top + sideH / 2, cabinZ), cfg.Body)
	-- Стойки и крыша.
	local pillarH = style.roofY - (top + sideH)
	for _, x in { -W / 2 + 0.2, W / 2 - 0.2 } do
		for _, z in { c0 + 0.2, c1 - 0.2 } do
			body("Pillar", Vector3.new(0.35, pillarH, 0.35), Vector3.new(x, top + sideH + pillarH / 2, z), DARK)
		end
	end
	body("Roof", Vector3.new(W, 0.3, cabinLen), Vector3.new(0, style.roofY + 0.15, cabinZ), cfg.Body)

	if style.trunk then
		local trunkLen = L / 2 - c1
		if trunkLen > 0.5 then
			body("Trunk", Vector3.new(W, 1.3, trunkLen), Vector3.new(0, top + 0.65, c1 + trunkLen / 2), cfg.Body)
		end
	end
	if style.bed then
		local bedLen = L / 2 - c1
		body("BedSide", Vector3.new(0.3, 1.6, bedLen), Vector3.new(-W / 2 + 0.15, top + 0.8, c1 + bedLen / 2), cfg.Body)
		body("BedSide", Vector3.new(0.3, 1.6, bedLen), Vector3.new(W / 2 - 0.15, top + 0.8, c1 + bedLen / 2), cfg.Body)
		body("Tailgate", Vector3.new(W, 1.6, 0.3), Vector3.new(0, top + 0.8, L / 2 - 0.15), cfg.Body)
	end
	if style.armor then
		-- Броневые щитки на бампере.
		body("Plate", Vector3.new(W, 1.6, 0.4), Vector3.new(0, top + 1.6, -L / 2 + hoodLen + 0.2), cfg.Accent, Enum.Material.DiamondPlate)
	end

	-- Полоса цвета команды на крыше и мигалка у силовиков.
	local teamColor = TeamsConfig.List[teamKey] and TeamsConfig.List[teamKey].Color or cfg.Accent
	body("TeamStripe", Vector3.new(W * 0.5, 0.1, cabinLen * 0.8), Vector3.new(0, style.roofY + 0.35, cabinZ), teamColor, Enum.Material.Neon)
	if cfg.LightBar then
		local red = body("LightBar", Vector3.new(W * 0.3, 0.4, 0.8), Vector3.new(-W * 0.16, style.roofY + 0.5, c0 + 0.8), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
		local blue = body("LightBar", Vector3.new(W * 0.3, 0.4, 0.8), Vector3.new(W * 0.16, style.roofY + 0.5, c0 + 0.8), Color3.fromRGB(40, 90, 255), Enum.Material.Neon)
		red:SetAttribute("Siren", "red")
		blue:SetAttribute("Siren", "blue")
	end

	-- Сиденья: первое — водительское (VehicleSeat даёт газ/руль с клавиатуры, геймпада и телефона).
	for i, offset in cfg.Seats do
		local seat: Seat | VehicleSeat
		if i == 1 then
			local vs = Instance.new("VehicleSeat")
			vs.Name = "DriverSeat"
			vs.MaxSpeed = 0 -- машину двигают шарниры, а не сиденье
			vs.Torque = 0
			vs.HeadsUpDisplay = false
			seat = vs
		else
			seat = Instance.new("Seat")
			seat.Name = "Seat" .. i
		end
		seat.Size = Vector3.new(2, 0.6, 2)
		seat.CFrame = rootCf * CFrame.new(offset)
		seat.Color = DARK
		seat.Massless = true
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat.Parent = model
		weld(chassis, seat)
	end

	-- Колёса.
	local drive = Instance.new("Folder")
	drive.Name = "Drive"
	drive.Parent = model
	local wheelX = W / 2 + WHEEL_WIDTH / 2 + 0.1
	local wheelZ = L / 2 - R - 0.8
	local wheelProps = PhysicalProperties.new(1.2, 1.8, 0, 100, 1)
	local UP = CFrame.Angles(0, 0, math.pi / 2) -- поворачивает ось шарнира (X) вверх

	for _, w in {
		{ "FL", -wheelX, -wheelZ, true },
		{ "FR", wheelX, -wheelZ, true },
		{ "RL", -wheelX, wheelZ, false },
		{ "RR", wheelX, wheelZ, false },
	} do
		local name, x, z, front = w[1], w[2], w[3], w[4]
		local pos = Vector3.new(x, -0.3, z)

		local wheel = Instance.new("Part")
		wheel.Name = "Wheel_" .. name
		wheel.Shape = Enum.PartType.Cylinder -- ось цилиндра = X = ось вращения
		wheel.Size = Vector3.new(WHEEL_WIDTH, R * 2, R * 2)
		wheel.CFrame = rootCf * CFrame.new(pos)
		wheel.Color = DARK
		wheel.Material = Enum.Material.Fabric
		wheel.CustomPhysicalProperties = wheelProps
		wheel.Parent = model
		local wheelAtt = attachment(wheel, "Axle", CFrame.new())

		local hub: BasePart = chassis
		local hubAtt: Attachment
		if front then
			-- Поворотный кулак: невидимая деталь, вокруг вертикали её крутит сервопривод.
			local knuckle = Instance.new("Part")
			knuckle.Name = "Knuckle_" .. name
			knuckle.Size = Vector3.new(0.6, 0.6, 0.6)
			knuckle.CFrame = rootCf * CFrame.new(pos)
			knuckle.Transparency = 1
			knuckle.CanCollide = false
			knuckle.CanQuery = false
			knuckle.CanTouch = false
			knuckle.Parent = model

			local steer = Instance.new("HingeConstraint")
			steer.Name = "Steer_" .. name
			steer.Attachment0 = attachment(chassis, "SteerBase_" .. name, CFrame.new(pos) * UP)
			steer.Attachment1 = attachment(knuckle, "Steer", UP)
			steer.ActuatorType = Enum.ActuatorType.Servo
			steer.ServoMaxTorque = 1e7
			steer.AngularSpeed = 6
			steer.LimitsEnabled = true
			steer.LowerAngle = -cfg.SteerAngle
			steer.UpperAngle = cfg.SteerAngle
			steer.Parent = drive

			hub = knuckle
			hubAtt = attachment(knuckle, "Axle", CFrame.new())
		else
			hubAtt = attachment(chassis, "Axle_" .. name, CFrame.new(pos))
		end

		local motor = Instance.new("HingeConstraint")
		motor.Name = "Motor_" .. name
		motor.Attachment0 = hubAtt
		motor.Attachment1 = wheelAtt
		motor.ActuatorType = Enum.ActuatorType.Motor
		motor.MotorMaxTorque = cfg.Torque * 0.5 -- стоит на «ручнике», пока нет водителя
		motor.AngularVelocity = 0
		motor.Parent = drive

		local noCollide = Instance.new("NoCollisionConstraint")
		noCollide.Part0 = wheel
		noCollide.Part1 = hub
		noCollide.Parent = wheel
	end

	return model
end

return VehicleBuilder
