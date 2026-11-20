-- «Живое» тело поверх анимаций для всех видимых персонажей (игроки, боты, прохожие).
--   * разворот бёдер: при движении вбок или спиной вперёд таз и ноги поворачиваются по ходу,
--     а грудь и голова остаются смотреть вперёд (как в GTA при стрельбе на ходу);
--   * дыхание: грудь мягко поднимается; после бега дыхание частое и глубокое;
--   * взгляд: голова (и немного корпус) поворачивается туда, куда смотрит игрок (камера),
--     заранее «заглядывает» в поворот; боты и прохожие смотрят на тех, кто рядом;
--   * раненый (Downed) держится сгорбившись;
--   * взаимодействие (E): рука тянется к предмету, голова смотрит на него.
-- Всё считается у каждого клиента локально, сеть нужна только для LookYaw/AimPitch и InteractPos.
-- Настройки — Config/Character (Body).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Character).Body
local PoseStack = require(script.Parent.PoseStack)
local ArmIK = require(script.Parent.ArmIK)

local player = Players.LocalPlayer

local BodyLife = {}

local ANG = CFrame.Angles
local v = Vector3.new

type State = {
	hum: Humanoid,
	root: BasePart,
	rootJ: ArmIK.Joint?,
	waist: ArmIK.Joint?,
	neck: ArmIK.Joint?,
	twist: number,
	breath: number, -- фаза дыхания
	exertion: number, -- 0..1: насколько запыхался
	headYaw: number,
	headPitch: number,
	targetYaw: number,
	targetPitch: number,
	yaw: number,
	yawRate: number,
	hunch: number,
	social: Model?, -- на кого смотрит (боты, прохожие)
	socialAt: number,
	reach: number,
	arms: { [string]: ArmIK.Arm }?,
}

local states: { [Model]: State } = {}
local npcs: { [Model]: true } = {}

local function build(char: Model): State?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local lower = char:FindFirstChild("LowerTorso")
	local upper = char:FindFirstChild("UpperTorso")
	local head = char:FindFirstChild("Head")
	local look = root.CFrame.LookVector
	return {
		hum = hum,
		root = root,
		rootJ = lower and ArmIK.joint(lower:FindFirstChild("Root")),
		waist = upper and ArmIK.joint(upper:FindFirstChild("Waist")),
		neck = head and ArmIK.joint(head:FindFirstChild("Neck")),
		twist = 0,
		breath = math.random() * math.pi * 2,
		exertion = 0,
		headYaw = 0,
		headPitch = 0,
		targetYaw = 0,
		targetPitch = 0,
		yaw = math.atan2(-look.X, -look.Z),
		yawRate = 0,
		hunch = 0,
		social = nil,
		socialAt = 0,
		reach = 0,
		arms = nil,
	}
end

local function stateFor(char: Model): State?
	local st = states[char]
	if st and st.root.Parent == char then
		return st
	end
	st = build(char)
	states[char] = st :: any
	return st
end

local function armed(char: Model): boolean
	local tool = char:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("WeaponId") ~= nil
end

local function isDriver(hum: Humanoid): boolean
	local seat = hum.SeatPart
	return seat ~= nil and seat:IsA("VehicleSeat")
end

-- Угол направления (в системе корня): yaw влево +, pitch вверх +.
local function anglesTo(root: BasePart, dir: Vector3): (number, number)
	local l = root.CFrame:VectorToObjectSpace(dir)
	local yaw = math.atan2(-l.X, -l.Z)
	local pitch = math.atan2(l.Y, math.sqrt(l.X * l.X + l.Z * l.Z))
	return yaw, pitch
end

-- Ближайший персонаж перед ботом/прохожим, на которого стоит посмотреть.
local function pickSocial(char: Model, st: State, now: number): Model?
	if now - st.socialAt < 1.2 then
		return st.social
	end
	st.socialAt = now + math.random() * 0.6
	local best, bestD = nil, Config.SocialRange
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then
		return nil
	end
	local function consider(other: Model?)
		if not other or other == char then
			return
		end
		local oh = other:FindFirstChild("Head") :: BasePart?
		if not oh then
			return
		end
		local d = (oh.Position - head.Position).Magnitude
		if d < bestD then
			local yaw = anglesTo(st.root, oh.Position - head.Position)
			if math.abs(yaw) < math.rad(100) then
				best, bestD = other, d
			end
		end
	end
	for _, p in Players:GetPlayers() do
		consider(p.Character)
	end
	st.social = best
	return best
end

local function update(char: Model, st: State, dt: number, cam: CFrame, now: number)
	local hum, root = st.hum, st.root
	if not root.Parent or hum.Health <= 0 then
		return
	end
	local head = char:FindFirstChild("Head") :: BasePart?
	local camPos = cam.Position
	if (root.Position - camPos).Magnitude > Config.MaxDistance then
		return
	end
	local own = char == player.Character
	local firstPerson = own and head ~= nil and (head.Position - camPos).Magnitude < 1.6
	if firstPerson then
		return
	end

	local vel = root.AssemblyLinearVelocity
	local flat = v(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	local seated = hum.SeatPart ~= nil
	local state = hum:GetState()
	local onFeet = not seated
		and state ~= Enum.HumanoidStateType.Climbing
		and state ~= Enum.HumanoidStateType.Swimming
		and state ~= Enum.HumanoidStateType.Ragdoll
		and state ~= Enum.HumanoidStateType.PlatformStanding

	-- Скорость поворота корпуса (для «заглядывания» в поворот).
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local dYaw = (yaw - st.yaw + math.pi) % (2 * math.pi) - math.pi
	st.yaw = yaw
	st.yawRate += (dYaw / dt - st.yawRate) * math.min(1, dt * 6)

	-- Запыхался: растёт на бегу, спадает в покое.
	if speed > Config.SprintSpeed * 0.85 and onFeet then
		st.exertion = math.min(1, st.exertion + dt * Config.ExertionGain)
	else
		st.exertion = math.max(0, st.exertion - dt * Config.ExertionDecay)
	end

	-- 1. Разворот бёдер по ходу движения.
	local twistTarget = 0
	if onFeet and speed > 1 and not char:GetAttribute("Downed") then
		local m = root.CFrame:VectorToObjectSpace(flat.Unit)
		local a = math.atan2(-m.X, -m.Z)
		if math.abs(a) > math.rad(110) then
			a -= math.sign(a) * math.pi -- спиной вперёд: бёдра по обратному направлению
		end
		twistTarget = math.clamp(a, -Config.MaxTwist, Config.MaxTwist) * math.clamp((speed - 1) / 3, 0, 1)
	end
	st.twist += (twistTarget - st.twist) * math.min(1, dt * Config.TwistRate)

	-- 2. Дыхание (сильнее в покое и после бега).
	local period = Config.BreathPeriod + (Config.BreathPeriodTired - Config.BreathPeriod) * st.exertion
	st.breath = (st.breath + dt * 2 * math.pi / period) % (2 * math.pi)
	local calm = math.clamp(1 - speed / 6, 0, 1)
	local amp = (Config.BreathAmp + (Config.BreathAmpTired - Config.BreathAmp) * st.exertion) * (0.35 + 0.65 * calm)
	local breath = math.sin(st.breath) * amp

	-- 3. Раненый держится сгорбившись.
	st.hunch += ((if char:GetAttribute("Downed") then 1 else 0) - st.hunch) * math.min(1, dt * 4)

	-- 4. Взгляд.
	local wantYaw, wantPitch = 0, 0
	local interactPos = char:GetAttribute("InteractPos")
	local interactAt = char:GetAttribute("InteractAt")
	local interacting = typeof(interactPos) == "Vector3"
		and (char:GetAttribute("Interacting") == true or (type(interactAt) == "number" and workspace:GetServerTimeNow() - interactAt < 1.1))
	if interacting and head then
		wantYaw, wantPitch = anglesTo(root, (interactPos :: Vector3) - head.Position)
	elseif own then
		wantYaw, wantPitch = anglesTo(root, cam.LookVector)
	elseif npcs[char] then
		local other = pickSocial(char, st, now)
		local oh = other and other:FindFirstChild("Head") :: BasePart?
		if oh and head then
			wantYaw, wantPitch = anglesTo(root, oh.Position - head.Position)
		end
	else
		wantYaw = math.rad(char:GetAttribute("LookYaw") or 0)
		wantPitch = math.rad(char:GetAttribute("AimPitch") or 0)
	end
	-- Смотрит за спину — голова возвращается вперёд (не выворачивается).
	if math.abs(wantYaw) > math.rad(Config.LookBehind) then
		wantYaw = 0
	end
	-- Заглядывает в поворот.
	wantYaw += math.clamp(st.yawRate * Config.LookAhead, -0.4, 0.4)
	st.targetYaw, st.targetPitch = wantYaw, wantPitch
	local maxYaw = math.rad(Config.MaxHeadYaw)
	local cy = math.clamp(wantYaw, -maxYaw, maxYaw)
	local cp = math.clamp(wantPitch, -math.rad(Config.MaxHeadDown), math.rad(Config.MaxHeadUp))
	-- С оружием голову и корпус по вертикали ведёт WeaponPose; здесь только поворот в стороны,
	-- а в руках оружие — взгляд и так совпадает с корпусом.
	local headW = if armed(char) and not interacting then 0 elseif isDriver(hum) then 0 else 1
	local k = math.min(1, dt * Config.HeadRate)
	st.headYaw += (cy * headW - st.headYaw) * k
	st.headPitch += (cp * headW - st.headPitch) * k

	-- Применяем к суставам: Root (разворот бёдер), Waist (противоповорот, дыхание, взгляд, сутулость),
	-- Neck (остаток взгляда, противодыхание).
	local tw = st.twist
	if st.rootJ and math.abs(tw) > 1e-3 then
		PoseStack.add(st.rootJ.inst, nil, ANG(0, tw, 0))
	end
	local hunch = st.hunch
	if st.waist then
		local waistYaw = -tw * 0.75 + st.headYaw * Config.WaistShare
		local waistPitch = breath + st.headPitch * 0.15 - hunch * 0.45
		PoseStack.add(st.waist.inst, ANG(waistPitch, waistYaw, 0))
	end
	if st.neck then
		local neckYaw = -tw * 0.25 + st.headYaw * (1 - Config.WaistShare)
		local neckPitch = -breath * 0.8 + st.headPitch * 0.7 + hunch * 0.25
		PoseStack.add(st.neck.inst, ANG(neckPitch, neckYaw, 0))
	end
end

-- Рука тянется к предмету, с которым взаимодействует персонаж (E у двери, раненого, колонки и т. п.).
-- Сервер ставит атрибуты InteractPos (точка), InteractAt (время), Interacting (держит кнопку).
local function reach(char: Model, st: State, dt: number, camPos: Vector3)
	local pos = char:GetAttribute("InteractPos")
	local at = char:GetAttribute("InteractAt")
	local holding = char:GetAttribute("Interacting") == true
	local active = false
	local t = 0
	if typeof(pos) == "Vector3" and type(at) == "number" then
		t = workspace:GetServerTimeNow() - at
		active = holding or t < Config.ReachTime
	end
	local target = if active then 1 else 0
	st.reach += (target - st.reach) * math.min(1, dt * (if active then 7 else 5))
	if st.reach < 0.01 or st.hum.Health <= 0 or st.hum.SeatPart then
		return
	end
	if (st.root.Position - camPos).Magnitude > Config.MaxDistance then
		return
	end
	local torso = char:FindFirstChild("UpperTorso") :: BasePart?
	if not torso or typeof(pos) ~= "Vector3" then
		return
	end
	if not st.arms then
		st.arms = {}
		for _, side in { "Left", "Right" } do
			local arm = ArmIK.buildArm(char, side)
			if arm then
				(st.arms :: any)[side] = arm
			end
		end
	end
	-- С оружием тянется левая рука (правая держит оружие), без — ближняя к предмету.
	local localPos = torso.CFrame:PointToObjectSpace(pos)
	local side = if armed(char) then "Left" elseif localPos.X >= 0 then "Right" else "Left"
	local arm = (st.arms :: any)[side] :: ArmIK.Arm?
	if not arm then
		return
	end
	local torsoCf = torso.CFrame
	local shoulder = (torsoCf * arm.shoulder.c0).Position
	local toT = pos - shoulder
	local maxReach = (arm.a + arm.b) * 0.92
	local wrist = shoulder + (if toT.Magnitude > maxReach then toT.Unit * maxReach else toT)
	local up = torsoCf.UpVector
	local out = torsoCf.RightVector * (if side == "Right" then 1 else -1)
	local u, l = ArmIK.solve(arm, shoulder, wrist, out * 0.7 - up, out)
	local w = st.reach * st.reach * (3 - 2 * st.reach)
	ArmIK.setJoint(arm.shoulder, torsoCf, u, w)
	ArmIK.setJoint(arm.elbow, u, l, w)
	ArmIK.setJoint(arm.wrist, l, l * arm.handOffset, w)
end

-- Насколько персонаж запыхался (0..1) — для мимики.
function BodyLife.exertion(char: Model): number
	local st = states[char]
	return if st then st.exertion else 0
end

-- Куда хочет смотреть персонаж и куда уже повернул голову (радианы, в системе корня).
function BodyLife.gaze(char: Model): (number, number, number, number)
	local st = states[char]
	if not st then
		return 0, 0, 0, 0
	end
	return st.targetYaw, st.targetPitch, st.headYaw, st.headPitch
end

function BodyLife.breathPhase(char: Model): number
	local st = states[char]
	return if st then st.breath else 0
end

function BodyLife.init()
	if not Config or Config.Enabled == false then
		return
	end
	local function trackNpc(child: Instance)
		if child:IsA("Model") and (child:GetAttribute("BotId") ~= nil or child.Parent and child.Parent.Name == "Pedestrians") then
			npcs[child] = true
		end
	end
	local function watchFolder(f: Instance)
		if f:IsA("Folder") and f.Name == "Pedestrians" then
			f.ChildAdded:Connect(trackNpc)
			f.ChildRemoved:Connect(function(c)
				npcs[c :: Model] = nil
				states[c :: Model] = nil
			end)
			for _, c in f:GetChildren() do
				trackNpc(c)
			end
		end
	end
	workspace.ChildAdded:Connect(function(c)
		trackNpc(c)
		watchFolder(c)
	end)
	workspace.ChildRemoved:Connect(function(c)
		npcs[c :: Model] = nil
		states[c :: Model] = nil
	end)
	for _, c in workspace:GetChildren() do
		trackNpc(c)
		watchFolder(c)
	end
	Players.PlayerRemoving:Connect(function(p)
		if p.Character then
			states[p.Character] = nil
		end
	end)

	local function each(fn: (Model) -> ())
		for _, p in Players:GetPlayers() do
			if p.Character then
				fn(p.Character)
			end
		end
		for npc in npcs do
			if npc.Parent then
				fn(npc)
			end
		end
	end

	-- После Locomotion (10), до DriverPose (30) и рук с оружием (40).
	PoseStack.layer(20, function(dt)
		local cam = workspace.CurrentCamera.CFrame
		local now = os.clock()
		each(function(char)
			local st = stateFor(char)
			if st then
				update(char, st, dt, cam, now)
			end
		end)
		for char in states do
			if not char.Parent then
				states[char] = nil
			end
		end
	end)
	-- Рука к предмету — после рук с оружием, чтобы перекрыть их на время взаимодействия.
	PoseStack.layer(45, function(dt)
		local camPos = workspace.CurrentCamera.CFrame.Position
		each(function(char)
			local st = states[char]
			if st then
				reach(char, st, dt, camPos)
			end
		end)
	end)
end

return BodyLife
