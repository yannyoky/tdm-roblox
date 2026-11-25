-- Поза рук с оружием, которую видно со стороны (вид от третьего лица, другие игроки, боты).
-- Вместо стандартной позы Roblox «рука с предметом вытянута вперёд» персонаж держит
-- автомат двумя руками у плеча, пистолет — двумя вытянутыми руками, нож и гранату — у груди.
-- Руки поднимаются и опускаются вслед за взглядом (атрибут AimPitch, его ставит сервер),
-- при перезарядке оружие наклоняется, а левая рука идёт к магазину, на бегу оружие опускается.
--
-- Позу считает каждый клиент у себя: поверх анимаций выставляются Transform суставов рук R15
-- (Motor6D или AnimationConstraint, смотря какой риг у персонажа).
-- Корпус и голова наклоняются вслед за прицелом (часть наклона берёт поясница, часть шея),
-- при каждом выстреле оружие отдаёт назад и вверх, на бегу оружие несут наискосок у груди.
-- Ноги анимируются как раньше.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = require(ReplicatedStorage:WaitForChild("Shared").Config.Weapons)
local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local ArmIK = require(script.Parent.ArmIK)
local PoseStack = require(script.Parent.PoseStack)

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

-- Рука из двух костей: общий решатель в ArmIK (им же руки кладутся на руль и тянутся к предметам).
type Joint = ArmIK.Joint
type Arm = ArmIK.Arm
local joint = ArmIK.joint
local buildArm = ArmIK.buildArm
local solve = ArmIK.solve
local setJoint = ArmIK.setJoint

------------------------------------------------------------------------

-- Доля наклона прицела, которую берут поясница и шея (остальное — руки).
local WAIST_SHARE = 0.4
local NECK_SHARE = 0.35
-- Отдача со стороны: насколько уходит оружие на один выстрел (1 — автомат).
local KICK = { Rifle = 1, SMG = 0.7, Shotgun = 2, LMG = 1.1, Sniper = 2.2, Pistol = 1.1, Revolver = 1.6 }

-- Наклон сустава поверх анимации и других слоёв (общий стек поз).
type Bend = { joint: Joint }

local function bendJoint(b: Bend, extra: CFrame): CFrame
	return PoseStack.add(b.joint.inst, extra)
end

type State = {
	right: Arm?,
	left: Arm?,
	weight: number,
	reload: number,
	sprint: number,
	pitch: number,
	kick: number,
	waist: Bend?,
	neck: Bend?,
	root: Joint?,
}
local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any

local function getState(char: Model): State
	local st = states[char]
	if not st then
		local upper = char:FindFirstChild("UpperTorso")
		local head = char:FindFirstChild("Head")
		local waist = upper and joint(upper:FindFirstChild("Waist"))
		local lowerPart = char:FindFirstChild("LowerTorso")
		local lowerRoot = lowerPart and joint(lowerPart:FindFirstChild("Root"))
		local neck = head and joint(head:FindFirstChild("Neck"))
		st = {
			right = buildArm(char, "Right"),
			left = buildArm(char, "Left"),
			weight = 0,
			reload = 0,
			sprint = 0,
			pitch = 0,
			kick = 0,
			waist = if waist then { joint = waist } else nil,
			neck = if neck then { joint = neck } else nil,
			root = lowerRoot,
		}
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
		-- Убрали оружие: поясница и шея вернутся к позе анимации сами (стек поз).
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
	st.kick = math.max(0, st.kick - dt * 9)
	local pitch = math.clamp(st.pitch, -70, 70)

	-- Поясница и шея берут часть наклона прицела (на бегу и при перезарядке — меньше).
	-- Положение груди считаем уже с новым наклоном, иначе руки отстанут от корпуса на кадр.
	-- Таз считаем от корня с позой этого кадра (наклоны и разворот бёдер уже добавлены).
	local lower = char:FindFirstChild("LowerTorso") :: BasePart?
	local torsoCf = torso.CFrame
	local calm = (1 - st.sprint) * (1 - st.reload * 0.5)
	if st.waist and lower then
		local lowerCf = lower.CFrame
		if st.root then
			lowerCf = root.CFrame * ArmIK.c0(st.root) * PoseStack.get(st.root.inst) * st.root.c1:Inverse()
		end
		local wj = st.waist.joint
		local t = bendJoint(st.waist, ANG(rad(pitch * WAIST_SHARE * calm * st.weight), 0, 0))
		torsoCf = lowerCf * ArmIK.c0(wj) * t * wj.c1:Inverse()
	end
	if st.neck then
		bendJoint(st.neck, ANG(rad(pitch * NECK_SHARE * calm * st.weight), 0, 0))
	end

	-- Грудь: по повороту корпуса (yaw берём у корня, чтобы не дрожало от анимации ходьбы).
	local look = root.CFrame.LookVector
	local flat = v(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	-- Точка груди — чуть ниже середины между плечами (а не доля высоты торса): у тел разных
	-- пропорций (сгенерированные модели с низкими узкими плечами) оружие остаётся у плеча.
	local chest
	if left then
		local mid = (right.shoulder.c0.Position + left.shoulder.c0.Position) / 2
		chest = torsoCf:PointToWorldSpace(mid - v(0, 0.1, 0))
	else
		chest = torsoCf.Position + torsoCf.UpVector * (torso.Size.Y * 0.3)
	end
	-- На бегу оружие несут наискосок у груди, стволом вниз-влево.
	local aim = CFrame.lookAt(chest, chest + flat.Unit)
		* ANG(rad(pitch * (1 - st.sprint) - 40 * st.sprint - 20 * st.reload), rad(50 * st.sprint), rad(-25 * st.sprint))
	local kick = st.kick
	local gun = aim * CF(pose.grip) * CF(-0.15 * st.sprint, 0.1 * st.sprint, 0.35 * st.sprint)
		* CF(0, 0.04 * kick, 0.28 * kick) * ANG(rad(7 * kick), 0, 0)
		* pose.rot * ANG(0, 0, rad(40) * st.reload)
	-- Короткие руки не дотягиваются до цевья: подтягиваем оружие к себе на нехватку.
	if left and pose.left then
		local shoulderL0 = (torsoCf * left.shoulder.c0).Position
		local reachL = (left.a + left.b) * 0.95
		local over = ((gun * pose.left) - shoulderL0).Magnitude - reachL
		if over > 0 then
			gun = gun - aim.LookVector * math.min(over, 0.7)
		end
	end

	-- Правая рука: кисть держит рукоятку так же, как держала бы инструмент Roblox.
	local rightHand = gun * right.gripH:Inverse()
	local wrist = rightHand * right.wristH
	local shoulderR = (torsoCf * right.shoulder.c0).Position
	local up = aim.UpVector
	local rightCf = aim.RightVector
	local uR, lR = solve(right, shoulderR, wrist, rightCf * 0.6 - up, rightCf - up * 0.3)
	local w = st.weight
	setJoint(right.shoulder, torsoCf, uR, w)
	setJoint(right.elbow, uR, lR, w)
	setJoint(right.wrist, lR, rightHand, w)

	-- Левая рука на цевье (или у магазина при перезарядке).
	if left and pose.left then
		local target = gun * pose.left:Lerp(pose.mag or pose.left, st.reload)
		local shoulderL = (torsoCf * left.shoulder.c0).Position
		-- Кисть — продолжение предплечья; запястье чуть позади точки хвата.
		local gripOff = (left.gripH.Position - left.wristH).Magnitude
		local dirToTarget = (target - shoulderL)
		local wristL = target - (if dirToTarget.Magnitude > 0 then dirToTarget.Unit else aim.LookVector) * gripOff
		local uL, lL = solve(left, shoulderL, wristL, -rightCf * 0.6 - up, up)
		setJoint(left.shoulder, torsoCf, uL, w)
		setJoint(left.elbow, uL, lL, w)
		setJoint(left.wrist, lL, lL * left.handOffset, w)
	end
end

function WeaponPose.init()
	-- Свой наклон взгляда отправляем серверу (не чаще ~8 раз в секунду и только при изменении).
	local AimPitch = Net.get("AimPitch")
	local sentPitch, sentYaw, sentAt = 0, 0, 0

	local bots: { [Model]: true } = {}
	local function track(child: Instance)
		if child:IsA("Model") and child:GetAttribute("BotId") ~= nil then
			bots[child] = true
		end
	end
	workspace.ChildAdded:Connect(track)

	-- Отдача со стороны: выстрел приходит с точкой у дула, ищем стрелка рядом с ней.
	Net.get("ShotFx").OnClientEvent:Connect(function(origin: Vector3, _endPos, isMelee: boolean, _hit, _flash, weaponId: string?)
		if isMelee or typeof(origin) ~= "Vector3" then
			return
		end
		local best, bestD = nil, 7
		for char, st in states do
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local d = (root.Position - origin).Magnitude
				if d < bestD then
					best, bestD = st, d
				end
			end
		end
		if best then
			best.kick = math.min(1.5, best.kick + (KICK[weaponId or ""] or 1) * 0.6)
		end
	end)
	workspace.ChildRemoved:Connect(function(child)
		bots[child :: Model] = nil
	end)
	for _, child in workspace:GetChildren() do
		track(child)
	end

	-- После анимаций и слоёв тела (стек поз): наши Transform рук заменяют позу из анимации на этот кадр.
	PoseStack.layer(40, function(dt)
		local cam = workspace.CurrentCamera
		local camPos = cam.CFrame.Position
		local myPitch = math.deg(math.asin(math.clamp(cam.CFrame.LookVector.Y, -1, 1)))
		-- Куда смотрит голова относительно корпуса (влево +), чтобы другие видели взгляд.
		local myYaw = 0
		local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if myRoot then
			local l = myRoot.CFrame:VectorToObjectSpace(cam.CFrame.LookVector)
			myYaw = math.deg(math.atan2(-l.X, -l.Z))
		end
		local now = os.clock()
		if (math.abs(myPitch - sentPitch) > 3 or math.abs(myYaw - sentYaw) > 6) and now - sentAt > 0.12 then
			sentPitch, sentYaw, sentAt = myPitch, myYaw, now
			AimPitch:FireServer(myPitch, myYaw)
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
