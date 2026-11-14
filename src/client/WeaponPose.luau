-- Поза рук с оружием, которую видно со стороны (вид от третьего лица, другие игроки, боты).
-- Вместо стандартной позы Roblox «рука с предметом вытянута вперёд» персонаж держит
-- автомат двумя руками у плеча, пистолет — двумя вытянутыми руками, нож и гранату — у груди.
-- Руки поднимаются и опускаются вслед за взглядом (атрибут AimPitch, его ставит сервер),
-- при перезарядке оружие наклоняется, а левая рука идёт к магазину, на бегу оружие опускается.
--
-- Позу считает каждый клиент у себя: поверх анимаций выставляются Transform суставов рук R15
-- (Motor6D или AnimationConstraint, смотря какой риг у персонажа).
-- Ноги и корпус анимируются как раньше.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Weapons = require(ReplicatedStorage:WaitForChild("Shared").Config.Weapons)
local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local player = Players.LocalPlayer

local WeaponPose = {}

local v = Vector3.new
local rad = math.rad
local CF = CFrame.new
local ANG = CFrame.Angles

local MAX_DISTANCE = 220 -- дальше позу не считаем (не видно)

-- Где оружие (точка хвата правой руки) относительно груди: X вправо, Y вверх, −Z вперёд.
--   left — точка левой руки на оружии (в пространстве оружия, ствол в −Z), nil — левая рука свободна
--   mag  — куда идёт левая рука при перезарядке
local POSES: { [string]: any } = {
	Long = { grip = v(0.45, -0.25, -1.05), rot = ANG(0, rad(3), 0), left = v(0, 0.2, -1.05), mag = v(0, -0.2, -0.45) },
	SMG = { grip = v(0.45, -0.2, -1.0), rot = ANG(0, rad(3), 0), left = v(0, 0.22, -0.75), mag = v(0, -0.15, -0.35) },
	Pistol = { grip = v(0.15, 0, -1.75), rot = ANG(0, rad(2), 0), left = v(-0.12, -0.12, 0.06), mag = v(0, -0.45, 0.05) },
	Melee = { grip = v(0.75, -0.75, -0.9), rot = ANG(rad(35), rad(10), rad(-15)) },
	Grenade = { grip = v(0.7, -0.6, -0.9), rot = CFrame.identity },
}

local function poseFor(id: string, def): any
	if def and def.Kind == "Grenade" then
		return POSES.Grenade
	elseif def and def.Melee then
		return POSES.Melee
	elseif id == "SMG" then
		return POSES.SMG
	elseif def and def.Slot == "Secondary" then
		return POSES.Pistol
	end
	return POSES.Long
end

------------------------------------------------------------------------
-- Рука из двух костей (как в Viewmodel, но для настоящих суставов персонажа)

-- Сустав: Motor6D (C0/C1) у старых ригов или AnimationConstraint (Attachment0/1) у новых.
-- У обоих Part1 = Part0 * c0 * Transform * c1⁻¹.
type Joint = { inst: Instance, c0: CFrame, c1: CFrame }

local function joint(inst: Instance?): Joint?
	if inst and inst:IsA("Motor6D") then
		return { inst = inst, c0 = inst.C0, c1 = inst.C1 }
	elseif inst and inst:IsA("AnimationConstraint") and inst.Attachment0 and inst.Attachment1 then
		return { inst = inst, c0 = inst.Attachment0.CFrame, c1 = inst.Attachment1.CFrame }
	end
	return nil
end

type Arm = {
	upper: BasePart,
	lower: BasePart,
	hand: BasePart,
	shoulder: Joint,
	elbow: Joint,
	wrist: Joint,
	shoulderU: Vector3,
	boneU: Vector3,
	elbowL: Vector3,
	boneL: Vector3, -- локоть→запястье в предплечье
	wristH: Vector3, -- запястье в кисти
	gripH: CFrame, -- точка хвата в кисти
	handOffset: CFrame, -- кисть относительно предплечья в исходной позе
	a: number,
	b: number,
}

local function attCf(part: Instance, name: string, fallback: CFrame): CFrame
	local a = part:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.CFrame else fallback
end

local function buildArm(char: Model, side: string): Arm?
	local upper = char:FindFirstChild(side .. "UpperArm")
	local lower = char:FindFirstChild(side .. "LowerArm")
	local hand = char:FindFirstChild(side .. "Hand")
	if not (upper and lower and hand and upper:IsA("BasePart") and lower:IsA("BasePart") and hand:IsA("BasePart")) then
		return nil
	end
	local shoulder = joint(upper:FindFirstChild(side .. "Shoulder"))
	local elbow = joint(lower:FindFirstChild(side .. "Elbow"))
	local wrist = joint(hand:FindFirstChild(side .. "Wrist"))
	if not (shoulder and elbow and wrist) then
		return nil
	end
	local shoulderU = attCf(upper, side .. "ShoulderRigAttachment", CF(0, 0.4, 0)).Position
	local elbowU = attCf(upper, side .. "ElbowRigAttachment", CF(0, -0.3, 0)).Position
	local elbowL = attCf(lower, side .. "ElbowRigAttachment", CF(0, 0.3, 0)).Position
	local wristL = attCf(lower, side .. "WristRigAttachment", CF(0, -0.45, 0)).Position
	local wristH = attCf(hand, side .. "WristRigAttachment", CF(0, 0.2, 0)).Position
	local gripH = attCf(hand, side .. "GripAttachment", CF(0, -0.1, 0) * ANG(rad(-90), 0, 0))
	return {
		upper = upper,
		lower = lower,
		hand = hand,
		shoulder = shoulder,
		elbow = elbow,
		wrist = wrist,
		shoulderU = shoulderU,
		boneU = elbowU - shoulderU,
		elbowL = elbowL,
		boneL = wristL - elbowL,
		wristH = wristH,
		gripH = gripH,
		handOffset = CF(wristL - wristH),
		a = (elbowU - shoulderU).Magnitude,
		b = (wristL - elbowL).Magnitude,
	}
end

local function basis(bone: Vector3, ref: Vector3): CFrame
	local y = -bone.Unit
	local x = ref - y * ref:Dot(y)
	if x.Magnitude < 1e-3 then
		x = Vector3.zAxis:Cross(y)
	end
	return CFrame.fromMatrix(Vector3.zero, x.Unit, y)
end

-- Плечо и предплечье так, чтобы запястье оказалось в точке wrist. Возвращает CFrame деталей.
local function solve(arm: Arm, shoulder: Vector3, wrist: Vector3, pole: Vector3, roll: Vector3): (CFrame, CFrame)
	local a, b = arm.a, arm.b
	local toT = wrist - shoulder
	local d = math.clamp(toT.Magnitude, math.abs(a - b) + 0.05, (a + b) * 0.999)
	local dir = if toT.Magnitude > 1e-4 then toT.Unit else v(0, 0, -1)
	local cosA = math.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local perp = pole - dir * pole:Dot(dir)
	perp = if perp.Magnitude > 1e-4 then perp.Unit else v(0, -1, 0)
	local elbow = shoulder + dir * (a * cosA) + perp * (a * sinA)
	-- если не дотягивается, предплечье просто тянется в сторону цели
	local reach = elbow + (wrist - elbow).Unit * b
	local rU = basis(elbow - shoulder, roll) * basis(arm.boneU, Vector3.xAxis):Inverse()
	local upperCf = CF(shoulder - rU:VectorToWorldSpace(arm.shoulderU)) * rU
	local rL = basis(reach - elbow, roll) * basis(arm.boneL, Vector3.xAxis):Inverse()
	local lowerCf = CF(elbow - rL:VectorToWorldSpace(arm.elbowL)) * rL
	return upperCf, lowerCf
end

-- Transform сустава, чтобы деталь part1 встала в cf1 при детали part0 в cf0.
local function setJoint(j: Joint, cf0: CFrame, cf1: CFrame, weight: number)
	local m = j.inst :: any
	local t = j.c0:Inverse() * cf0:Inverse() * cf1 * j.c1
	m.Transform = if weight >= 1 then t else m.Transform:Lerp(t, weight)
end

------------------------------------------------------------------------

type State = { right: Arm?, left: Arm?, weight: number, reload: number, sprint: number, pitch: number }
local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any

local function getState(char: Model): State
	local st = states[char]
	if not st then
		st = { right = buildArm(char, "Right"), left = buildArm(char, "Left"), weight = 0, reload = 0, sprint = 0, pitch = 0 }
		states[char] = st
	end
	return st
end

local function poseCharacter(char: Model, dt: number, camPos: Vector3, myPitch: number?)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = char:FindFirstChild("UpperTorso") :: BasePart?
	if not hum or not root or not torso or hum.Health <= 0 or hum.SeatPart or char:GetAttribute("Downed") then
		return
	end
	if (root.Position - camPos).Magnitude > MAX_DISTANCE then
		return
	end
	local tool = char:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("WeaponId")
	if not tool or type(id) ~= "string" then
		states[char] = nil
		return
	end
	local st = getState(char)
	local right, left = st.right, st.left
	if not right then
		return
	end
	local def = Weapons.List[id]
	local pose = poseFor(id, def)

	st.weight = math.min(1, st.weight + dt * 6)
	local vel = root.AssemblyLinearVelocity
	local speed = v(vel.X, 0, vel.Z).Magnitude
	local reloading = tool:GetAttribute("Reloading") == true
	st.reload += ((if reloading then 1 else 0) - st.reload) * math.min(1, dt * 8)
	st.sprint += ((if speed > 20 and not reloading then 1 else 0) - st.sprint) * math.min(1, dt * 8)
	local targetPitch = myPitch or (char:GetAttribute("AimPitch") or 0)
	st.pitch += (targetPitch - st.pitch) * math.min(1, dt * 12)

	-- Грудь: по повороту корпуса (yaw берём у корня, чтобы не дрожало от анимации ходьбы).
	local look = root.CFrame.LookVector
	local flat = v(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local chest = torso.Position + torso.CFrame.UpVector * (torso.Size.Y * 0.3)
	local aim = CFrame.lookAt(chest, chest + flat.Unit)
		* ANG(rad(math.clamp(st.pitch, -70, 70) - 30 * st.sprint - 20 * st.reload), rad(35 * st.sprint), 0)
	local gun = aim * CF(pose.grip) * pose.rot * ANG(0, 0, rad(40) * st.reload)

	-- Правая рука: кисть держит рукоятку так же, как держала бы инструмент Roblox.
	local rightHand = gun * right.gripH:Inverse()
	local wrist = rightHand * right.wristH
	local shoulderR = (torso.CFrame * right.shoulder.c0).Position
	local up = aim.UpVector
	local rightCf = aim.RightVector
	local uR, lR = solve(right, shoulderR, wrist, rightCf * 0.6 - up, rightCf - up * 0.3)
	local w = st.weight
	setJoint(right.shoulder, torso.CFrame, uR, w)
	setJoint(right.elbow, uR, lR, w)
	setJoint(right.wrist, lR, rightHand, w)

	-- Левая рука на цевье (или у магазина при перезарядке).
	if left and pose.left then
		local target = gun * pose.left:Lerp(pose.mag or pose.left, st.reload)
		local shoulderL = (torso.CFrame * left.shoulder.c0).Position
		-- Кисть — продолжение предплечья; запястье чуть позади точки хвата.
		local gripOff = (left.gripH.Position - left.wristH).Magnitude
		local dirToTarget = (target - shoulderL)
		local wristL = target - (if dirToTarget.Magnitude > 0 then dirToTarget.Unit else aim.LookVector) * gripOff
		local uL, lL = solve(left, shoulderL, wristL, -rightCf * 0.6 - up, up)
		setJoint(left.shoulder, torso.CFrame, uL, w)
		setJoint(left.elbow, uL, lL, w)
		setJoint(left.wrist, lL, lL * left.handOffset, w)
	end
end

function WeaponPose.init()
	-- Свой наклон взгляда отправляем серверу (не чаще ~8 раз в секунду и только при изменении).
	local AimPitch = Net.get("AimPitch")
	local sentPitch, sentAt = 0, 0

	local bots: { [Model]: true } = {}
	local function track(child: Instance)
		if child:IsA("Model") and child:GetAttribute("BotId") ~= nil then
			bots[child] = true
		end
	end
	workspace.ChildAdded:Connect(track)
	workspace.ChildRemoved:Connect(function(child)
		bots[child :: Model] = nil
	end)
	for _, child in workspace:GetChildren() do
		track(child)
	end

	-- Stepped идёт после анимаций: наши Transform рук заменяют позу из анимации на этот кадр.
	RunService.Stepped:Connect(function(_, dt)
		dt = math.min(dt, 0.1)
		local cam = workspace.CurrentCamera
		local camPos = cam.CFrame.Position
		local myPitch = math.deg(math.asin(math.clamp(cam.CFrame.LookVector.Y, -1, 1)))
		local now = os.clock()
		if math.abs(myPitch - sentPitch) > 3 and now - sentAt > 0.12 then
			sentPitch, sentAt = myPitch, now
			AimPitch:FireServer(myPitch)
		end
		for _, p in Players:GetPlayers() do
			local char = p.Character
			if char then
				poseCharacter(char, dt, camPos, if p == player then myPitch else nil)
			end
		end
		for bot in bots do
			poseCharacter(bot, dt, camPos, nil)
		end
	end)
end

return WeaponPose
