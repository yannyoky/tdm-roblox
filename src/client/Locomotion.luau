-- Живая пластика тела поверх анимаций ходьбы и бега (Rthro, Config/Character.Animations):
--   * инерция: при разгоне корпус уходит вперёд, при торможении — назад, на бегу и спринте
--     постоянный наклон вперёд, плавно, с запаздыванием;
--   * повороты: на ходу тело кренится внутрь поворота, тем сильнее, чем выше скорость;
--   * приземление: после высокого прыжка или падения таз проседает, колени сгибаются, ступни
--     остаются на земле, затем тело пружинисто выпрямляется (сила зависит от скорости падения);
--   * переходы: все добавки сглажены, резких скачков позы нет.
-- Считается на каждом клиенте для всех видимых персонажей (игроки и боты), как WeaponPose:
-- поверх анимаций выставляются Transform суставов Root, бёдер, коленей и голеностопов.
-- Корпус выше пояса (Waist, Neck) не трогается: его наклоняет WeaponPose вслед за прицелом.
-- Настройки — src/shared/Config/Character.luau (Locomotion).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Character).Locomotion

local player = Players.LocalPlayer

local Locomotion = {}

type Bend = { inst: any, base: CFrame, last: CFrame? }

type State = {
	hum: Humanoid,
	root: BasePart,
	joints: { [string]: Bend },
	pivot: Vector3, -- точка между ступнями в системе сустава Root
	leg: number, -- длина бедра (≈ голени)
	prevVel: Vector3,
	accel: Vector3,
	yaw: number,
	yawRate: number,
	pitch: number,
	roll: number,
	landX: number, -- просадка таза (студы, ≤ 0)
	landV: number,
	fallSpeed: number,
	active: boolean,
	c0: CFrame, -- C0 сустава Root (в HumanoidRootPart)
	lastRoot: CFrame,
	lastSeat: Instance?,
	seatAt: number,
	trans: CFrame?, -- откуда «переезжает» тело при посадке/выходе (в системе HumanoidRootPart)
	transT: number,
	transCf: CFrame?, -- добавка этого кадра (её повторяем после физики, см. Heartbeat)
}

local states: { [Model]: State } = {}
local bots: { [Model]: true } = {}

local JOINTS = {
	Root = "LowerTorso",
	LeftHip = "LeftUpperLeg",
	RightHip = "RightUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightKnee = "RightLowerLeg",
	LeftAnkle = "LeftFoot",
	RightAnkle = "RightFoot",
}

local function attPos(part: Instance?, name: string): Vector3?
	local a = part and part:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.Position else nil
end

local function build(char: Model): State?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local joints = {}
	for name, partName in JOINTS do
		local part = char:FindFirstChild(partName)
		local inst = part and part:FindFirstChild(name)
		if not inst or not (inst:IsA("Motor6D") or inst:IsA("AnimationConstraint")) then
			return nil
		end
		joints[name] = { inst = inst, base = CFrame.identity, last = nil }
	end
	-- Точка опоры наклона — между ступнями, в системе сустава Root (C0 в HumanoidRootPart).
	local rootJoint = joints.Root.inst
	local c0 = if rootJoint:IsA("Motor6D") then rootJoint.C0 else (rootJoint.Attachment0 :: Attachment).CFrame
	local feet = Vector3.new(0, -(hum.HipHeight + root.Size.Y / 2), 0)
	local upper = char:FindFirstChild("LeftUpperLeg")
	local hip = attPos(upper, "LeftHipRigAttachment")
	local knee = attPos(upper, "LeftKneeRigAttachment")
	local leg = if hip and knee then (hip - knee).Magnitude else 1.4
	return {
		hum = hum,
		root = root,
		joints = joints,
		pivot = c0:PointToObjectSpace(feet),
		leg = math.max(0.6, leg),
		prevVel = Vector3.zero,
		accel = Vector3.zero,
		yaw = 0,
		yawRate = 0,
		pitch = 0,
		roll = 0,
		landX = 0,
		landV = 0,
		fallSpeed = 0,
		active = false,
		c0 = c0,
		lastRoot = root.CFrame,
		lastSeat = hum.SeatPart,
		seatAt = -10,
		trans = nil,
		transT = 0,
		transCf = nil,
	}
end

-- Добавка к позе анимации: Transform = pre · (поза анимации) · extra. Если анимация в этом кадре сустав не трогала, в Transform осталось
-- наше значение с прошлого кадра: тогда берём сохранённую позу анимации.
local function bend(b: Bend, extra: CFrame, pre: CFrame?)
	local current: CFrame = b.inst.Transform
	if b.last == nil or current ~= b.last then
		b.base = current
	end
	local t = if pre then pre * b.base * extra else b.base * extra
	b.inst.Transform = t
	b.last = t
end

local function release(st: State)
	for _, b in st.joints do
		if b.last and b.inst.Transform == b.last then
			b.inst.Transform = b.base
		end
		b.last = nil
	end
	st.active = false
end

local function update(char: Model, st: State, dt: number, camPos: Vector3)
	local hum, root = st.hum, st.root
	if not root.Parent or hum.Health <= 0 then
		st.transCf = nil
		return
	end
	-- Посадка в машину и выход: сервер переносит персонажа рывком (на сиденье или к двери).
	-- Тело не прыгает, а за ~0.5 с «переходит» из прежнего места, пригибаясь (как в дверной проём).
	local now = os.clock()
	if hum.SeatPart ~= st.lastSeat then
		st.lastSeat = hum.SeatPart
		st.seatAt = now
	end
	local moved = (root.Position - st.lastRoot.Position).Magnitude
	if moved > 1.5 and moved < 30 and now - st.seatAt < 0.8 then
		st.trans = root.CFrame:ToObjectSpace(st.lastRoot)
		st.transT = 0
	end
	st.lastRoot = root.CFrame
	local transCf: CFrame? = nil
	if st.trans then
		st.transT += dt / Config.EnterTime
		if st.transT >= 1 then
			st.trans = nil
		else
			local e = 1 - (1 - st.transT) ^ 3 -- плавное замедление в конце
			local duck = math.sin(math.pi * st.transT)
			local rel = CFrame.identity:Lerp(st.trans :: CFrame, 1 - e)
			-- В системе сустава Root: C0⁻¹ · смещение · C0, плюс наклон и приседание посередине пути.
			transCf = st.c0:Inverse() * rel * st.c0 * CFrame.new(0, -Config.EnterDuck * duck, 0) * CFrame.Angles(-0.35 * duck, 0, 0)
		end
	end

	local vel = root.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local prevFlat = Vector3.new(st.prevVel.X, 0, st.prevVel.Z)
	local look = root.CFrame.LookVector
	local right = root.CFrame.RightVector

	-- Приземление: падали быстро, а теперь почти стоим по вертикали.
	if vel.Y < -2 then
		st.fallSpeed = math.max(st.fallSpeed, -vel.Y)
	end
	if st.prevVel.Y < -Config.LandMinSpeed and vel.Y > -4 then
		local impact = math.clamp((st.fallSpeed - Config.LandMinSpeed) / (Config.LandMaxSpeed - Config.LandMinSpeed), 0.15, 1)
		st.landV = math.min(st.landV, -impact * Config.LandKick)
		st.fallSpeed = 0
	elseif vel.Y > -2 then
		st.fallSpeed = 0
	end
	st.prevVel = vel

	-- Ускорение (сглаженное) и скорость поворота.
	local a = (flat - prevFlat) / dt
	st.accel = st.accel:Lerp(a, math.min(1, dt * 10))
	local yaw = math.atan2(-look.X, -look.Z)
	local dYaw = (yaw - st.yaw + math.pi) % (2 * math.pi) - math.pi
	st.yaw = yaw
	st.yawRate += (dYaw / dt - st.yawRate) * math.min(1, dt * 8)

	local state = hum:GetState()
	local grounded = hum.FloorMaterial ~= Enum.Material.Air or (state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping)
	local busy = hum.SeatPart ~= nil or hum.Sit or char:GetAttribute("Downed") or state == Enum.HumanoidStateType.Climbing
		or state == Enum.HumanoidStateType.Swimming or state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.PlatformStanding

	local speed = flat.Magnitude
	local targetPitch, targetRoll = 0, 0
	if grounded and not busy then
		local aF = st.accel:Dot(look)
		-- Разгон/торможение + постоянный наклон на бегу (отрицательный угол — вперёд).
		targetPitch = -math.clamp(aF * Config.AccelLean, -Config.MaxPitch, Config.MaxPitch)
			- Config.SpeedLean * math.clamp(speed / Config.SprintSpeed, 0, 1.2)
		targetRoll = math.clamp(st.yawRate * speed * Config.TurnLean, -Config.MaxRoll, Config.MaxRoll)
	end
	st.pitch += (targetPitch - st.pitch) * math.min(1, dt * Config.Smooth)
	st.roll += (targetRoll - st.roll) * math.min(1, dt * Config.Smooth)

	-- Пружина приседа при приземлении.
	local k = Config.LandStiffness
	local c = 2 * math.sqrt(k) * Config.LandDamping
	st.landV += (-k * st.landX - c * st.landV) * dt
	st.landX = math.clamp(st.landX + st.landV * dt, -Config.LandMaxDrop, 0.15)
	if busy then
		st.landX, st.landV = 0, 0
	end

	-- Своё тело в виде от первого лица и далёкие персонажи: ничего не добавляем.
	local head = char:FindFirstChild("Head") :: BasePart?
	local far = (root.Position - camPos).Magnitude > Config.MaxDistance
	local firstPerson = char == player.Character and head ~= nil and (head.Position - camPos).Magnitude < 1.6
	local tiny = math.abs(st.pitch) < 0.002 and math.abs(st.roll) < 0.002 and math.abs(st.landX) < 0.005
	st.transCf = if transCf and not far and not firstPerson then transCf else nil
	if st.transCf then
		st.active = true
		bend(st.joints.Root, CFrame.identity, st.transCf)
		return
	end
	if far or firstPerson or busy or tiny then
		if st.active then
			release(st)
		end
		return
	end
	st.active = true

	local drop = math.min(0, st.landX)
	local legs = not char:GetAttribute("Crouching")
	local pivot = st.pivot
	bend(st.joints.Root, CFrame.new(pivot) * CFrame.Angles(st.pitch, 0, st.roll) * CFrame.new(-pivot) * CFrame.new(0, if legs then drop else 0, 0))
	if legs and drop < -0.005 then
		-- Бедро вперёд на α, голень назад на 2α, стопа обратно на α: ступни остаются под тазом.
		local alpha = math.acos(math.clamp(1 + drop / (2 * st.leg), -1, 1))
		local hipCf = CFrame.Angles(alpha, 0, 0)
		local kneeCf = CFrame.Angles(-2 * alpha, 0, 0)
		local ankleCf = CFrame.Angles(alpha, 0, 0)
		bend(st.joints.LeftHip, hipCf)
		bend(st.joints.RightHip, hipCf)
		bend(st.joints.LeftKnee, kneeCf)
		bend(st.joints.RightKnee, kneeCf)
		bend(st.joints.LeftAnkle, ankleCf)
		bend(st.joints.RightAnkle, ankleCf)
	end
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

function Locomotion.init()
	if not Config or Config.Enabled == false then
		return
	end
	local function track(child: Instance)
		if child:IsA("Model") and child:GetAttribute("BotId") ~= nil then
			bots[child] = true
		end
	end
	workspace.ChildAdded:Connect(track)
	workspace.ChildRemoved:Connect(function(child)
		bots[child :: Model] = nil
		states[child :: Model] = nil
	end)
	-- Прохожие режима «Город» (World/Pedestrians) лежат в папке workspace.Pedestrians.
	local function watchPeds(f: Instance)
		if f.Name ~= "Pedestrians" or not f:IsA("Folder") then
			return
		end
		f.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				bots[child] = true
			end
		end)
		f.ChildRemoved:Connect(function(child)
			bots[child :: Model] = nil
			states[child :: Model] = nil
		end)
		for _, child in f:GetChildren() do
			if child:IsA("Model") then
				bots[child] = true
			end
		end
	end
	workspace.ChildAdded:Connect(watchPeds)
	local pf = workspace:FindFirstChild("Pedestrians")
	if pf then
		watchPeds(pf)
	end
	for _, child in workspace:GetChildren() do
		track(child)
	end
	Players.PlayerRemoving:Connect(function(p)
		if p.Character then
			states[p.Character] = nil
		end
	end)

	-- После анимаций (как WeaponPose): добавки ложатся на позу этого кадра.
	RunService.Stepped:Connect(function(_, dt)
		dt = math.clamp(dt, 1 / 240, 0.1)
		local camPos = workspace.CurrentCamera.CFrame.Position
		local function run(char: Model?)
			if not char then
				return
			end
			local st = stateFor(char)
			if st then
				update(char, st, dt, camPos)
			end
		end
		for _, p in Players:GetPlayers() do
			run(p.Character)
		end
		for bot in bots do
			run(bot)
		end
		for char in states do
			if not char.Parent then
				states[char] = nil
			end
		end
	end)
	-- Сидящий персонаж — часть сборки машины, и через кадр поза таза приходит заново
	-- уже после Stepped: без повтора тело на кадр «прыгает» на сиденье. Повторяем добавку после физики.
	RunService.Heartbeat:Connect(function()
		for char, st in states do
			if st.transCf and char.Parent then
				local b = st.joints.Root
				if b.inst.Transform ~= b.last then
					bend(b, CFrame.identity, st.transCf)
				end
			end
		end
	end)
end

return Locomotion
