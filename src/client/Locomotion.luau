-- Живая пластика тела поверх анимаций ходьбы и бега (Rthro, Config/Character.Animations):
--   * инерция: при разгоне корпус уходит вперёд, при торможении — назад, на бегу и спринте
--     постоянный наклон вперёд, плавно, с запаздыванием;
--   * повороты: на ходу тело кренится внутрь поворота, тем сильнее, чем выше скорость;
--   * приземление: после высокого прыжка или падения таз проседает, колени сгибаются, ступни
--     остаются на земле, затем тело пружинисто выпрямляется (сила зависит от скорости падения);
--   * ступни на земле: стоя на лестнице, бордюре или склоне, таз опускается к нижней ступне,
--     а нога на верхней ступеньке сгибается; стопа ложится по наклону поверхности (IK ног);
--   * переходы: все добавки сглажены, резких скачков позы нет.
-- Считается на каждом клиенте для всех видимых персонажей (игроки и боты), как WeaponPose:
-- поверх анимаций выставляются Transform суставов Root, бёдер, коленей и голеностопов.
-- Корпус выше пояса (Waist, Neck) не трогается: его наклоняет WeaponPose вслед за прицелом.
-- Настройки — src/shared/Config/Character.luau (Locomotion).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Character).Locomotion
local PoseStack = require(script.Parent.PoseStack)

local player = Players.LocalPlayer

local Locomotion = {}

type Bend = { inst: any }

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
	ikW: number, -- вес IK ног (1 — стоит, 0 — идёт)
	ikL: number, -- высота земли под левой/правой ступнёй относительно обычного уровня ступней
	ikR: number,
	nL: Vector3, -- нормаль земли под ступнёй (в системе HumanoidRootPart)
	nR: Vector3,
	leftFoot: BasePart?,
	rightFoot: BasePart?,
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
		joints[name] = { inst = inst }
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
		ikW = 0,
		ikL = 0,
		ikR = 0,
		nL = Vector3.yAxis,
		nR = Vector3.yAxis,
		leftFoot = char:FindFirstChild("LeftFoot") :: BasePart?,
		rightFoot = char:FindFirstChild("RightFoot") :: BasePart?,
	}
end

-- Добавка к позе анимации: Transform = pre · (поза анимации) · extra (через общий стек поз).
local function bend(b: Bend, extra: CFrame, pre: CFrame?)
	PoseStack.add(b.inst, extra, pre)
end

-- Земля под ступнёй: насколько она выше (+) или ниже (−) обычного уровня ступней.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function groundUnder(char: Model, root: BasePart, foot: BasePart?, floorY: number): (number, Vector3)
	if not foot then
		return 0, Vector3.yAxis
	end
	local p = foot.Position
	local from = Vector3.new(p.X, floorY + Config.FootIKUp, p.Z)
	rayParams.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(from, Vector3.new(0, -(Config.FootIKUp + Config.FootIKDown), 0), rayParams)
	if not hit then
		return 0, Vector3.yAxis
	end
	return math.clamp(hit.Position.Y - floorY, -Config.FootIKDown, Config.FootIKUp), root.CFrame:VectorToObjectSpace(hit.Normal)
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
		and not (Config.FootIK and speed < 3)
	-- Переход при посадке и выходе — и в виде от первого лица: камера в этот момент переключается,
	-- и без этого добавка пропадала на 2–3 кадра (тело «прыгало»).
	st.transCf = if transCf and not far then transCf else nil
	if st.transCf then
		st.active = true
		bend(st.joints.Root, CFrame.identity, st.transCf)
		return
	end
	if far or firstPerson or busy or tiny then
		st.active = false
		st.ikW = 0
		return
	end
	st.active = true

	local drop = math.min(0, st.landX)
	local legs = not char:GetAttribute("Crouching")

	-- IK ног: стоя (и почти стоя) ступни встают на свою высоту земли.
	local ikTarget = if legs and grounded and Config.FootIK and (root.Position - camPos).Magnitude < Config.FootIKDistance
		then math.clamp(1 - speed / 3, 0, 1)
		else 0
	st.ikW += (ikTarget - st.ikW) * math.min(1, dt * 8)
	local ikDrop = 0
	if st.ikW > 0.01 then
		local floorY = root.Position.Y - root.Size.Y / 2 - hum.HipHeight
		local dL, nL = groundUnder(char, root, st.leftFoot, floorY)
		local dR, nR = groundUnder(char, root, st.rightFoot, floorY)
		local k = math.min(1, dt * 14)
		st.ikL += (dL - st.ikL) * k
		st.ikR += (dR - st.ikR) * k
		st.nL = st.nL:Lerp(nL, k)
		st.nR = st.nR:Lerp(nR, k)
		ikDrop = math.min(0, st.ikL, st.ikR) * st.ikW
	else
		st.ikL, st.ikR = 0, 0
	end

	local pivot = st.pivot
	bend(st.joints.Root, CFrame.new(pivot) * CFrame.Angles(st.pitch, 0, st.roll) * CFrame.new(-pivot) * CFrame.new(0, if legs then drop + ikDrop else 0, 0))
	if not legs then
		return
	end
	-- Каждая нога укорачивается на s: бедро вперёд на α, голень назад на 2α, стопа обратно на α —
	-- ступня остаётся под тазом. Плюс стопа ложится по наклону земли.
	local function leg(side: string, height: number, n: Vector3)
		local s = -drop + (height * st.ikW - ikDrop)
		local slopeW = st.ikW
		if s < 0.005 and slopeW < 0.01 then
			return
		end
		local alpha = math.acos(math.clamp(1 - math.max(0, s) / (2 * st.leg), -1, 1))
		local up = math.max(0.3, n.Y)
		local tilt = math.clamp(math.atan2(n.Z, up), -Config.FootMaxTilt, Config.FootMaxTilt) * slopeW
		local roll = math.clamp(math.atan2(-n.X, up), -Config.FootMaxTilt, Config.FootMaxTilt) * slopeW
		bend(st.joints[side .. "Hip"], CFrame.Angles(alpha, 0, 0))
		bend(st.joints[side .. "Knee"], CFrame.Angles(-2 * alpha, 0, 0))
		bend(st.joints[side .. "Ankle"], CFrame.Angles(alpha + tilt, 0, roll))
	end
	leg("Left", st.ikL, st.nL)
	leg("Right", st.ikR, st.nR)
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

	-- После анимаций (первым в стеке поз): добавки ложатся на позу этого кадра.
	PoseStack.layer(10, function(dt)
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
				PoseStack.reapply(st.joints.Root.inst)
			end
		end
	end)
end

return Locomotion
