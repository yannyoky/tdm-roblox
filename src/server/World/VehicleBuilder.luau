-- Собирает машину по её модели: геометрия из World/VehicleModels, характеристики из Config/Vehicles.
--
-- Устройство (всё считается от точки на земле под центром машины: X вправо, h вверх, Z назад):
--   Chassis   -- невидимый груз на высоте осей, несёт почти всю массу (низкий центр тяжести,
--                машина не кувыркается). Это PrimaryPart.
--   Hull_*    -- невидимые коробки по форме кузова: столкновения и попадания пуль.
--                Стёкла (Glass) пули пропускают — можно стрелять из машины и попасть в сидящих.
--   BodyMesh* -- кузов из меша, только картинка.
--   Колёса    -- там же, где колёса на модели, того же размера. Каждое на своей подвеске:
--                шасси → ползун (PrismaticConstraint + SpringConstraint) → [поворотный кулак] → колесо.
--                Поверх нарисованных в меше колёс надеты свои крутящиеся колёса.
--   Сиденья   -- на местах из модели; у каждого своя дверь (кнопка посадки сбоку) и место выхода.
-- Шарниры лежат в папке Drive (Motor_FL/FR/RL/RR, Steer_FL/FR); ими управляет клиент водителя
-- (src/client/VehicleController.luau), потому что физику машины считает его компьютер.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehiclesConfig = require(Shared.Config.Vehicles)
local TeamsConfig = require(Shared.Config.Teams)
local VehicleModels = require(script.Parent.VehicleModels)

local VehicleBuilder = {}

local DARK = Color3.fromRGB(28, 28, 30)
local TIRE = Color3.fromRGB(22, 22, 24)
local RIM = Color3.fromRGB(170, 172, 178)
local UP = CFrame.Angles(0, 0, math.pi / 2) -- поворачивает ось X шарнира/ползуна вверх
local SPAWN_LIFT = 0.25 -- машина появляется чуть над землёй и мягко садится на подвеску

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

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function ghost(p: BasePart)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
end

-- Видимое колесо поверх физического: шина, диск и спицы (по ним видно, что колесо крутится).
local function dressWheel(model: Model, wheel: BasePart, name: string, r: number, w: number, side: number)
	local tire = part({
		Name = "Tire_" .. name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(w + 0.2, (r + 0.08) * 2, (r + 0.08) * 2),
		CFrame = wheel.CFrame,
		Color = TIRE,
		Material = Enum.Material.Rubber,
	})
	ghost(tire)
	tire.Transparency = 0
	tire.Parent = model
	weld(wheel, tire)
	local face = wheel.CFrame * CFrame.new(side * (w / 2 + 0.12), 0, 0)
	local rim = part({
		Name = "Rim_" .. name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, r * 1.25, r * 1.25),
		CFrame = face,
		Color = RIM,
		Material = Enum.Material.Metal,
	})
	ghost(rim)
	rim.Transparency = 0
	rim.Parent = model
	weld(wheel, rim)
	for i = 0, 2 do
		local spoke = part({
			Name = "Spoke_" .. name,
			Size = Vector3.new(0.1, r * 1.2, 0.22),
			CFrame = face * CFrame.new(side * 0.03, 0, 0) * CFrame.Angles(math.rad(i * 60), 0, 0),
			Color = Color3.fromRGB(90, 92, 98),
			Material = Enum.Material.Metal,
		})
		ghost(spoke)
		spoke.Transparency = 0
		spoke.Parent = model
		weld(wheel, spoke)
	end
end

-- Фары, габариты, стоп-сигналы и задний ход. Включает и выключает их клиент
-- (src/client/VehicleLights.luau): фары ночью и в ливень, стопы при торможении, белые при заднем ходе.
local function addLights(model: Model, geo, at: (number, number, number) -> CFrame, chassis: BasePart)
	if geo.lights then
		local L = geo.lights
		local rearZ = geo.size.Z / 2 - 0.05
		for _, side in { -1, 1 } do
			local x = side * L.x
			local holder = part({ Name = "Headlight", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = at(x, L.h, L.z) })
			ghost(holder)
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Front
			light.Range = 60
			light.Angle = 55
			light.Brightness = 2
			light.Color = Color3.fromRGB(255, 245, 220)
			light.Shadows = true
			light.Enabled = false
			light.Parent = holder
			holder.Parent = model
			weld(chassis, holder)
			-- Стекло фары: светится, когда фары включены.
			local hd = L.head or {}
			local glow = part({ Name = "HeadlightGlow", Size = Vector3.new(hd.w or 0.8, hd.ht or 0.32, 0.7), CFrame = at(side * (hd.x or L.x * 0.9), hd.h or L.h, hd.z or L.z + 0.3), Color = Color3.fromRGB(255, 250, 235), Material = Enum.Material.Neon })
			ghost(glow)
			glow.Transparency = 1
			glow.CastShadow = false
			glow.Parent = model
			weld(chassis, glow)
			-- Задний фонарь (габарит + стоп) и фонарь заднего хода.
			local tl = L.tail or {}
			local tx, th, tz = side * (tl.x or L.x * 0.9), tl.h or L.h + 0.35, tl.z or rearZ - 0.4
			local tw, tht = tl.w or 0.8, tl.ht or 0.3
			local tail = part({ Name = "TailLight", Size = Vector3.new(tw, tht, 0.7), CFrame = at(tx, th, tz), Color = Color3.fromRGB(255, 30, 25), Material = Enum.Material.Neon })
			ghost(tail)
			tail.Transparency = 1
			tail.CastShadow = false
			local red = Instance.new("PointLight")
			red.Color = Color3.fromRGB(255, 40, 30)
			red.Range = 6
			red.Brightness = 0.6
			red.Enabled = false
			red.Parent = tail
			tail.Parent = model
			weld(chassis, tail)
			-- Задний ход — рядом с фонарём ближе к середине (у вертикального фонаря — под ним).
			local rx, rh = if tht > tw then tx else tx - side * (tw / 2 + 0.25), if tht > tw then th - tht / 2 - 0.2 else th
			local rev = part({ Name = "ReverseLight", Size = Vector3.new(0.35, 0.26, 0.7), CFrame = at(rx, rh, tz), Color = Color3.fromRGB(255, 255, 250), Material = Enum.Material.Neon })
			ghost(rev)
			rev.Transparency = 1
			rev.CastShadow = false
			local white = Instance.new("SpotLight")
			white.Face = Enum.NormalId.Back
			white.Range = 16
			white.Angle = 70
			white.Brightness = 0.8
			white.Enabled = false
			white.Parent = rev
			rev.Parent = model
			weld(chassis, rev)
		end
	end
end

function VehicleBuilder.build(typeId: string, groundCf: CFrame, teamKey: string): Model
	local cfg = VehiclesConfig.Types[typeId]
	assert(cfg, "Нет машины " .. tostring(typeId))
	local geo = VehicleModels[typeId]
	assert(geo, "Нет модели машины " .. tostring(typeId) .. " в World/VehicleModels")
	local wh = geo.wheels
	local R, WW = wh.r, wh.w
	local wheelbase = wh.rear - wh.front
	local midZ = (wh.front + wh.rear) / 2
	local base = groundCf * CFrame.new(0, SPAWN_LIFT, 0)
	local function at(x: number, h: number, z: number): CFrame
		return base * CFrame.new(x, h, z)
	end

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
	model:SetAttribute("Brake", cfg.Brake or cfg.Torque)
	model:SetAttribute("SteerAngle", cfg.SteerAngle)
	model:SetAttribute("Drive", cfg.Drive or "AWD")
	model:SetAttribute("MinRadius", cfg.MinRadius or 11)
	model:SetAttribute("YawLow", cfg.YawLow or 2.3)
	model:SetAttribute("YawHigh", cfg.YawHigh or 1.25)
	model:SetAttribute("Grip", cfg.Grip or 7)
	model:SetAttribute("WheelRadius", R)
	model:SetAttribute("DriveSign", VehiclesConfig.DriveSign)
	model:SetAttribute("SteerSign", VehiclesConfig.SteerSign)
	model:SetAttribute("Wheelbase", wheelbase)
	model:SetAttribute("Length", geo.size.Z)
	model:SetAttribute("Width", geo.size.X)

	-- Груз-шасси: между колёсами на высоте осей.
	local chassisSize = Vector3.new(math.max(1, wh.x * 2 - WW - 1), 0.6, math.max(2, wheelbase - R * 2))
	local mass = cfg.Mass or 400
	local chassis = part({
		Name = "Chassis",
		Size = chassisSize,
		CFrame = at(0, R, midZ),
		Transparency = 1,
		CanCollide = false,
		CanTouch = true,
		CustomPhysicalProperties = PhysicalProperties.new(
			math.clamp(mass / (chassisSize.X * chassisSize.Y * chassisSize.Z), 0.01, 100), 0.3, 0, 1, 1),
	})
	chassis.Parent = model
	model.PrimaryPart = chassis

	-- Коробки кузова: столкновения и попадания.
	local showHull = VehiclesConfig.ShowHull == true
	for i, box in geo.hull do
		local lo, hi = box.min, box.max
		local hull = part({
			Name = (if box.glass then "Glass_" else "Hull_") .. i,
			Size = hi - lo,
			CFrame = at((lo.X + hi.X) / 2, (lo.Y + hi.Y) / 2, (lo.Z + hi.Z) / 2),
			Transparency = if showHull then 0.6 else 1,
			Color = if box.glass then Color3.fromRGB(80, 160, 255) else Color3.fromRGB(255, 120, 40),
			Massless = true,
			CanQuery = not box.glass, -- через стёкла пули летят к сидящим внутри
			CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.35, 0.1, 1, 1),
		})
		pcall(function()
			hull.CollisionGroup = "VehicleHull" -- группу регистрирует PhysicsSetup
		end)
		hull.Parent = model
		weld(chassis, hull)
	end

	-- Кузов из меша.
	local bodyCf = base * CFrame.new(0, geo.size.Y / 2, 0)
	for i, piece in geo.parts do
		local p = part({
			Name = "BodyMesh" .. i,
			Size = Vector3.new(0.4, 0.4, 0.4),
			CFrame = bodyCf * CFrame.new(piece.pos) * CFrame.Angles(0, math.rad(piece.yaw or 0), 0),
		})
		ghost(p)
		p.Transparency = 0
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = "rbxassetid://" .. piece.mesh
		if piece.tex then
			mesh.TextureId = "rbxassetid://" .. piece.tex
		end
		mesh.Scale = piece.scale
		mesh.Parent = p
		p.Parent = model
		weld(chassis, p)
	end

	-- Полоса цвета команды на крыше и мигалка у силовиков.
	local roof = geo.roof
	local teamColor = TeamsConfig.List[teamKey] and TeamsConfig.List[teamKey].Color or cfg.Accent
	local stripe = part({
		Name = "TeamStripe",
		Size = Vector3.new(roof.w * 0.45, 0.1, roof.len * 0.7),
		CFrame = at(0, roof.h + 0.05, roof.z),
		Color = teamColor,
		Material = Enum.Material.Neon,
	})
	ghost(stripe)
	stripe.Transparency = 0
	stripe.Parent = model
	weld(chassis, stripe)
	if cfg.LightBar then
		for _, s in { { "red", -1, Color3.fromRGB(255, 40, 40) }, { "blue", 1, Color3.fromRGB(40, 90, 255) } } do
			local lamp = part({
				Name = "LightBar",
				Size = Vector3.new(roof.w * 0.22, 0.4, 0.8),
				CFrame = if geo.siren
					then at(s[2] * roof.w * 0.12, geo.siren.h, geo.siren.z)
					else at(s[2] * roof.w * 0.12, roof.h + 0.25, roof.z - roof.len * 0.3),
				Color = s[3],
				Material = Enum.Material.Neon,
			})
			ghost(lamp)
			lamp.Transparency = 0
			lamp:SetAttribute("Siren", s[1])
			lamp.Parent = model
			weld(chassis, lamp)
		end
	end

	addLights(model, geo, at, chassis)

	-- Сиденья, двери и места выхода. Первое сиденье — водительское.
	local doors = Instance.new("Folder")
	doors.Name = "Doors"
	doors.Parent = model
	local halfW = geo.size.X / 2
	for i, s in geo.seats do
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
		seat.Size = Vector3.new(2, 0.4, 2)
		seat.CFrame = at(s.pos.X, s.pos.Y - 0.2, s.pos.Z) -- pos.Y — верх подушки
		seat.Transparency = 1
		seat.CanCollide = false
		seat.CanTouch = false -- садятся только через двери, а не случайным касанием
		seat.Massless = true
		seat.Parent = model
		weld(chassis, seat)

		-- Дверь: точка сбоку у сиденья (для мест в кузове — у борта или сзади).
		local side = if s.door == "back" then 0 elseif s.pos.X < 0 then -1 else 1
		local doorPos, exitPos
		if side == 0 then
			doorPos = Vector3.new(s.pos.X, math.max(2.5, s.pos.Y - 0.5), geo.size.Z / 2 + 0.3)
			exitPos = Vector3.new(s.pos.X, 3, geo.size.Z / 2 + 2.5)
		else
			doorPos = Vector3.new(side * (halfW + 0.2), 3, s.pos.Z)
			exitPos = Vector3.new(side * (halfW + 2.2), 3, s.pos.Z)
		end
		local door = attachment(chassis, "Door" .. i, chassis.CFrame:ToObjectSpace(at(doorPos.X, doorPos.Y, doorPos.Z)))
		door:SetAttribute("Seat", seat.Name)
		local exit = attachment(chassis, "Exit" .. i, chassis.CFrame:ToObjectSpace(at(exitPos.X, exitPos.Y, exitPos.Z)))
		seat:SetAttribute("Door", door.Name)
		seat:SetAttribute("Exit", exit.Name)
		seat:SetAttribute("Open", s.open == true) -- открытое место (кузов): можно стрелять во все стороны
	end

	-- Колёса на подвеске.
	local drive = Instance.new("Folder")
	drive.Name = "Drive"
	drive.Parent = model
	local wheelProps = PhysicalProperties.new(1.2, 1.8, 0, 100, 1)
	-- Ползуны и кулаки должны весить хоть сколько-то (≈13): слишком лёгкая деталь между тяжёлым
	-- шасси и жёсткой пружиной разгоняет физику, и машина разлетается при появлении.
	local tinyProps = PhysicalProperties.new(60, 0.3, 0, 1, 1)
	local susp = cfg.Suspension or {}
	local hz = susp.Hz or 2.5
	local damping = susp.Damping or 0.55
	local travelUp, travelDown = susp.Up or 0.7, susp.Down or 0.6
	local cornerMass = mass / 4
	local stiffness = (2 * math.pi * hz) ^ 2 * cornerMass
	local sag = cornerMass * workspace.Gravity / stiffness
	local SPRING_TOP = 2 -- на сколько выше оси крепится пружина
	local wheels = {}
	model:SetAttribute("SpringStiffness", stiffness)

	for _, w in {
		{ "FL", -1, wh.front, true },
		{ "FR", 1, wh.front, true },
		{ "RL", -1, wh.rear, false },
		{ "RR", 1, wh.rear, false },
	} do
		local name, side, z, front = w[1], w[2], w[3], w[4]
		local x = side * wh.x
		local axleCf = at(x, R, z)
		local localAxle = chassis.CFrame:ToObjectSpace(axleCf)

		-- Ползун подвески: ходит только вверх-вниз, его держит пружина.
		local strut = part({ Name = "Strut_" .. name, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = axleCf, CustomPhysicalProperties = tinyProps })
		strut.Transparency = 1
		strut.CanCollide = false
		strut.CanQuery = false
		strut.CanTouch = false
		strut.Parent = model
		local slide = Instance.new("PrismaticConstraint")
		slide.Name = "Slide_" .. name
		slide.Attachment0 = attachment(chassis, "SlideBase_" .. name, localAxle * UP)
		slide.Attachment1 = attachment(strut, "Slide", UP)
		slide.LimitsEnabled = true
		slide.LowerLimit = -travelDown
		slide.UpperLimit = travelUp
		slide.Restitution = 0
		slide.Parent = drive
		local spring = Instance.new("SpringConstraint")
		spring.Name = "Spring_" .. name
		spring.Attachment0 = attachment(chassis, "SpringTop_" .. name, localAxle * CFrame.new(0, SPRING_TOP, 0))
		spring.Attachment1 = attachment(strut, "Spring", CFrame.new())
		spring.Stiffness = stiffness
		spring.Damping = 2 * damping * math.sqrt(stiffness * cornerMass)
		spring.FreeLength = SPRING_TOP + sag -- под весом машины колесо стоит ровно там, где на модели
		spring.Visible = false
		spring.Parent = drive

		local hub: BasePart = strut
		if front then
			-- Поворотный кулак: вокруг вертикали его крутит сервопривод.
			local knuckle = part({ Name = "Knuckle_" .. name, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = axleCf, CustomPhysicalProperties = tinyProps })
			knuckle.Transparency = 1
			knuckle.CanCollide = false
			knuckle.CanQuery = false
			knuckle.CanTouch = false
			knuckle.Parent = model
			local steer = Instance.new("HingeConstraint")
			steer.Name = "Steer_" .. name
			steer.Attachment0 = attachment(strut, "SteerBase", UP)
			steer.Attachment1 = attachment(knuckle, "Steer", UP)
			steer.ActuatorType = Enum.ActuatorType.Servo
			steer.ServoMaxTorque = 1e7
			steer.AngularSpeed = 6
			steer.LimitsEnabled = true
			steer.LowerAngle = -cfg.SteerAngle
			steer.UpperAngle = cfg.SteerAngle
			steer.Parent = drive
			hub = knuckle
		end

		local wheel = part({
			Name = "Wheel_" .. name,
			Shape = Enum.PartType.Cylinder, -- ось цилиндра = X = ось вращения
			Size = Vector3.new(WW, R * 2, R * 2),
			CFrame = axleCf,
			Transparency = 1,
			CustomPhysicalProperties = wheelProps,
		})
		pcall(function()
			wheel.CollisionGroup = "VehicleWheels" -- группу регистрирует PhysicsSetup
		end)
		wheel.Parent = model
		dressWheel(model, wheel, name, R, WW, side)
		table.insert(wheels, wheel)

		local motor = Instance.new("HingeConstraint")
		motor.Name = "Motor_" .. name
		motor.Attachment0 = attachment(hub, "Axle_" .. name, CFrame.new())
		motor.Attachment1 = attachment(wheel, "Axle", CFrame.new())
		motor.ActuatorType = Enum.ActuatorType.Motor
		motor.MotorMaxTorque = (cfg.Brake or cfg.Torque) * 0.25 -- стоит на «ручнике», пока нет водителя
		motor.AngularVelocity = 0
		motor:SetAttribute("Driven", (cfg.Drive or "AWD") == "AWD" or (cfg.Drive == "FWD") == front)
		motor.Parent = drive
	end

	-- Колёса не сталкиваются с собственным кузовом (иначе повёрнутое колесо упирается в коробки
	-- кузова, а сжатая подвеска заедает).
	for _, wheel in wheels do
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p.CanCollide and p ~= wheel then
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = wheel
				nc.Part1 = p
				nc.Parent = wheel
			end
		end
	end

	-- Помощник поворота: крутящий момент вокруг вертикали шасси. Его выставляет клиент водителя
	-- (VehicleController), чтобы машина поворачивала уверенно, даже когда колёса скользят.
	local center = attachment(chassis, "Center", CFrame.new())
	local assist = Instance.new("Torque")
	assist.Name = "SteerAssist"
	assist.Attachment0 = center
	assist.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	assist.Torque = Vector3.zero
	assist.Parent = drive

	return model
end

-- Машина городского трафика (режим «Город», World/Traffic.luau): тот же кузов, коробки и свет,
-- но без подвески и сидений. Её ведёт сервер: AlignPosition/AlignOrientation на шасси тянут машину
-- по полосе, колёса крутятся моторами по скорости. Физику считает сервер, поэтому у всех она
-- плавная, и машина толкается при столкновениях (масса Mass).
function VehicleBuilder.buildTraffic(typeId: string, groundCf: CFrame, mass: number): Model
	local geo = VehicleModels[typeId]
	assert(geo, "Нет модели машины " .. tostring(typeId))
	local wh = geo.wheels
	local R, WW = wh.r, wh.w
	local wheelbase = wh.rear - wh.front
	local midZ = (wh.front + wh.rear) / 2
	local function at(x: number, h: number, z: number): CFrame
		return groundCf * CFrame.new(x, h, z)
	end

	local model = Instance.new("Model")
	model.Name = "Traffic_" .. typeId
	model:SetAttribute("IsTraffic", true)
	model:SetAttribute("AIDriver", true)
	model:SetAttribute("VehicleType", typeId)
	model:SetAttribute("Length", geo.size.Z)
	model:SetAttribute("Width", geo.size.X)
	model:SetAttribute("WheelRadius", R)

	-- Шасси в центре габарита на высоте осей (ровно над точкой groundCf).
	local chassisSize = Vector3.new(math.max(1, wh.x * 2 - WW - 1), 0.6, math.max(2, wheelbase - R * 2))
	local chassis = part({
		Name = "Chassis",
		Size = chassisSize,
		CFrame = at(0, R, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CustomPhysicalProperties = PhysicalProperties.new(math.clamp(mass / (chassisSize.X * chassisSize.Y * chassisSize.Z), 0.01, 100), 0.3, 0, 1, 1),
	})
	chassis.Parent = model
	model.PrimaryPart = chassis

	for i, box in geo.hull do
		local lo, hi = box.min, box.max
		local hull = part({
			Name = (if box.glass then "Glass_" else "Hull_") .. i,
			Size = hi - lo,
			CFrame = at((lo.X + hi.X) / 2, (lo.Y + hi.Y) / 2, (lo.Z + hi.Z) / 2),
			Transparency = 1,
			Massless = true,
			CanQuery = true,
			CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.35, 0.1, 1, 1),
		})
		pcall(function()
			hull.CollisionGroup = "VehicleHull"
		end)
		hull.Parent = model
		weld(chassis, hull)
	end

	local bodyCf = groundCf * CFrame.new(0, geo.size.Y / 2, 0)
	for i, piece in geo.parts do
		local p = part({
			Name = "BodyMesh" .. i,
			Size = Vector3.new(0.4, 0.4, 0.4),
			CFrame = bodyCf * CFrame.new(piece.pos) * CFrame.Angles(0, math.rad(piece.yaw or 0), 0),
		})
		ghost(p)
		p.Transparency = 0
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = "rbxassetid://" .. piece.mesh
		if piece.tex then
			mesh.TextureId = "rbxassetid://" .. piece.tex
		end
		mesh.Scale = piece.scale
		mesh.Parent = p
		p.Parent = model
		weld(chassis, p)
	end

	addLights(model, geo, at, chassis)

	-- Колёса: крутятся моторами (скорость выставляет Traffic), в столкновениях не участвуют.
	local drive = Instance.new("Folder")
	drive.Name = "Drive"
	drive.Parent = model
	for _, w in { { "FL", -1, wh.front }, { "FR", 1, wh.front }, { "RL", -1, wh.rear }, { "RR", 1, wh.rear } } do
		local name, side, z = w[1], w[2], w[3]
		local axleCf = at(side * wh.x, R, z)
		local wheel = part({
			Name = "Wheel_" .. name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(WW, R * 2, R * 2),
			CFrame = axleCf,
		})
		ghost(wheel)
		wheel.Parent = model
		dressWheel(model, wheel, name, R, WW, side)
		local motor = Instance.new("HingeConstraint")
		motor.Name = "Motor_" .. name
		motor.Attachment0 = attachment(chassis, "Axle_" .. name, chassis.CFrame:ToObjectSpace(axleCf))
		motor.Attachment1 = attachment(wheel, "Axle", CFrame.new())
		motor.ActuatorType = Enum.ActuatorType.Motor
		motor.MotorMaxTorque = 1e6
		motor.AngularVelocity = 0
		motor.Parent = drive
	end

	-- Ведение по полосе: цель ставит Traffic каждый кадр.
	local center = attachment(chassis, "Center", CFrame.new())
	local align = Instance.new("AlignPosition")
	align.Name = "Follow"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = center
	align.MaxForce = mass * 800
	align.MaxVelocity = 120
	align.Responsiveness = 40
	align.Position = chassis.Position
	align.Parent = chassis
	local orient = Instance.new("AlignOrientation")
	orient.Name = "Face"
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = center
	orient.MaxTorque = mass * 4000
	orient.MaxAngularVelocity = 6
	orient.Responsiveness = 30
	orient.CFrame = chassis.CFrame.Rotation
	orient.Parent = chassis
	return model
end

return VehicleBuilder
