-- Персонаж в машине (видно всем, считается у каждого клиента для всех сидящих в машинах):
--   * водитель держит руль двумя руками «на 9 и 3 часа», руки поворачиваются вместе с рулём
--     (по SteerFloat сиденья), голова смотрит в поворот;
--   * все сидящие кренятся от перегрузок: в повороте корпус уходит наружу, при разгоне — назад,
--     при торможении — вперёд, голова частично держит горизонт.
-- Посадку и выход (переход от двери к сиденью с пригибанием) делает Locomotion.
-- Настройки — Config/Character (Driving).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Character).Driving
local PoseStack = require(script.Parent.PoseStack)
local ArmIK = require(script.Parent.ArmIK)

local DriverPose = {}

local ANG = CFrame.Angles
local MAX_DISTANCE = 140

type State = {
	seat: BasePart,
	since: number,
	prevVel: Vector3,
	accel: Vector3,
	roll: number,
	pitch: number,
	steer: number,
	hands: number,
	rootJ: ArmIK.Joint?,
	waist: ArmIK.Joint?,
	neck: ArmIK.Joint?,
	left: ArmIK.Arm?,
	right: ArmIK.Arm?,
}

local states: { [Humanoid]: State } = setmetatable({}, { __mode = "k" }) :: any

local function vehicleOf(seat: BasePart): Model?
	local m = seat.Parent
	if m and m:IsA("Model") and m:GetAttribute("IsVehicle") then
		return m
	end
	return nil
end

local function build(char: Model, seat: BasePart): State
	local lower = char:FindFirstChild("LowerTorso")
	local upper = char:FindFirstChild("UpperTorso")
	local head = char:FindFirstChild("Head")
	return {
		seat = seat,
		since = os.clock(),
		prevVel = seat.AssemblyLinearVelocity,
		accel = Vector3.zero,
		roll = 0,
		pitch = 0,
		steer = 0,
		hands = 0,
		rootJ = lower and ArmIK.joint(lower:FindFirstChild("Root")),
		waist = upper and ArmIK.joint(upper:FindFirstChild("Waist")),
		neck = head and ArmIK.joint(head:FindFirstChild("Neck")),
		left = ArmIK.buildArm(char, "Left"),
		right = ArmIK.buildArm(char, "Right"),
	}
end

local function update(char: Model, hum: Humanoid, dt: number, camPos: Vector3)
	local seat = hum.SeatPart
	if not seat or hum.Health <= 0 then
		states[hum] = nil
		return
	end
	local model = vehicleOf(seat)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not model or not root or (seat.Position - camPos).Magnitude > MAX_DISTANCE then
		return
	end
	local st = states[hum]
	if not st or st.seat ~= seat then
		st = build(char, seat)
		states[hum] = st
	end
	local s = st :: State

	-- Перегрузки в системе машины (сглажено, чтобы кочки не трясли корпус).
	local vel = seat.AssemblyLinearVelocity
	local a = (vel - s.prevVel) / dt
	s.prevVel = vel
	s.accel = s.accel:Lerp(a, math.min(1, dt * 5))
	local cf = seat.CFrame
	local lat = s.accel:Dot(cf.RightVector)
	local fwd = s.accel:Dot(cf.LookVector)
	local targetRoll = math.clamp(lat * Config.LeanRoll, -Config.MaxRoll, Config.MaxRoll)
	local targetPitch = math.clamp(fwd * Config.LeanPitch, -Config.MaxPitch, Config.MaxPitch)
	s.roll += (targetRoll - s.roll) * math.min(1, dt * 6)
	s.pitch += (targetPitch - s.pitch) * math.min(1, dt * 6)

	local driver = seat:IsA("VehicleSeat")
	if driver then
		local steer = (seat :: VehicleSeat).SteerFloat
		s.steer += (steer - s.steer) * math.min(1, dt * 9)
	end

	-- Корпус кренится, голова держит горизонт наполовину и (у водителя) смотрит в поворот.
	if s.waist then
		PoseStack.add(s.waist.inst, ANG(s.pitch, 0, s.roll))
	end
	if s.neck then
		local look = if driver then -s.steer * Config.HeadTurn else 0
		PoseStack.add(s.neck.inst, ANG(-s.pitch * 0.5, look, -s.roll * 0.6))
	end

	-- Руль машины крутится вместе с руками (Motor6D «Turn» у оси руля, см. VehicleBuilder).
	if driver then
		local sw = model:FindFirstChild("SteeringWheel")
		local pivot = sw and sw:FindFirstChild("Pivot")
		local turnMotor = pivot and pivot:FindFirstChild("Turn")
		if turnMotor and turnMotor:IsA("Motor6D") then
			turnMotor.Transform = ANG(0, 0, -s.steer * math.rad(Config.WheelTurn))
		end
	end

	-- Руки на руле.
	if not driver or not s.left or not s.right then
		return
	end
	local ready = os.clock() - s.since > Config.HandsDelay
	s.hands += ((if ready then 1 else 0) - s.hands) * math.min(1, dt * 5)
	if s.hands < 0.01 then
		return
	end
	local lower = char:FindFirstChild("LowerTorso") :: BasePart?
	local torso = char:FindFirstChild("UpperTorso") :: BasePart?
	if not lower or not torso then
		return
	end
	-- Грудь с позой этого кадра: корень → таз → поясница (с креном выше).
	local lowerCf = lower.CFrame
	if s.rootJ then
		lowerCf = root.CFrame * ArmIK.c0(s.rootJ) * PoseStack.get(s.rootJ.inst) * s.rootJ.c1:Inverse()
	end
	local torsoCf = torso.CFrame
	if s.waist then
		torsoCf = lowerCf * ArmIK.c0(s.waist) * PoseStack.get(s.waist.inst) * s.waist.c1:Inverse()
	end
	local top = cf * CFrame.new(0, seat.Size.Y / 2, 0)
	local wheel = top * CFrame.new(Config.WheelOffset) * ANG(math.rad(Config.WheelTilt), 0, 0)
	local turn = -s.steer * math.rad(Config.WheelTurn)
	local up = cf.UpVector
	local w = s.hands * s.hands * (3 - 2 * s.hands)
	for _, side in { "Left", "Right" } do
		local arm = (if side == "Left" then s.left else s.right) :: ArmIK.Arm
		local base = if side == "Left" then math.pi else 0
		-- Руки идут по ободу не дальше HandTurn: на полном повороте руль чуть проскальзывает в ладонях,
		-- и отстающая рука не отрывается от обода.
		local handTurn = math.clamp(turn, -math.rad(Config.HandTurn), math.rad(Config.HandTurn))
		local grip = (wheel * ANG(0, 0, base + handTurn) * CFrame.new(Config.WheelRadius, 0, 0)).Position
		local shoulder = (torsoCf * arm.shoulder.c0).Position
		local gripOff = (arm.gripH.Position - arm.wristH).Magnitude
		local toGrip = grip - shoulder
		local wrist = grip - (if toGrip.Magnitude > 0 then toGrip.Unit else cf.LookVector) * gripOff
		local out = cf.RightVector * (if side == "Right" then 1 else -1)
		local u, l = ArmIK.solve(arm, shoulder, wrist, out * 0.8 - up, out)
		ArmIK.setJoint(arm.shoulder, torsoCf, u, w)
		ArmIK.setJoint(arm.elbow, u, l, w)
		ArmIK.setJoint(arm.wrist, l, l * arm.handOffset, w)
	end
end

function DriverPose.init()
	if not Config or Config.Enabled == false then
		return
	end
	-- Все сидящие в машинах: игроки и боты.
	local bots: { [Model]: true } = {}
	local function track(c: Instance)
		if c:IsA("Model") and c:GetAttribute("BotId") ~= nil then
			bots[c] = true
		end
	end
	workspace.ChildAdded:Connect(track)
	workspace.ChildRemoved:Connect(function(c)
		bots[c :: Model] = nil
	end)
	for _, c in workspace:GetChildren() do
		track(c)
	end
	PoseStack.layer(30, function(dt)
		local camPos = workspace.CurrentCamera.CFrame.Position
		for _, p in Players:GetPlayers() do
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.SeatPart then
				update(char :: Model, hum, dt, camPos)
			end
		end
		for bot in bots do
			local hum = bot.Parent and bot:FindFirstChildOfClass("Humanoid")
			if hum and hum.SeatPart then
				update(bot, hum, dt, camPos)
			end
		end
	end)
end

return DriverPose
