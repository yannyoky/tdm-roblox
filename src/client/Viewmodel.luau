-- Вид от первого лица: руки персонажа держат оружие перед камерой, как в CS.
-- Руки — копии рук своего персонажа (тот же цвет кожи и одежда скина), оружие — копия
-- деталей своего Tool. Всё рисуется только у себя (детали лежат в камере), другие игроки
-- по-прежнему видят персонажа с оружием в руке.
--
-- Анимации процедурные: доставание, дыхание и покачивание на месте, покачивание при ходьбе,
-- наклон оружия при движении вбок, инерция при повороте камеры, просадка при приземлении,
-- отдача, перезарядка (левая рука уходит за магазином), бег с оружием у груди,
-- удар ножом/битой, бросок гранаты.
-- Положение оружия и левой руки для каждого оружия — таблица HOLD ниже.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Weapons = require(ReplicatedStorage:WaitForChild("Shared").Config.Weapons)
local PlayerSettings = require(script.Parent.PlayerSettings)

local player = Players.LocalPlayer

local Viewmodel = {}

local v = Vector3.new
local rad = math.rad
local CF = CFrame.new
local ANG = CFrame.Angles

-- Масштаб вьюмодели: она меньше и ближе к камере, поэтому меньше влезает в стены,
-- а на экране выглядит так же.
local SCALE = 0.6

-- Плечи в пространстве камеры (до масштаба). Плечи за кадром; если рука не дотягивается,
-- плечо подтягивается к цели, поэтому руки всегда держат оружие.
local SHOULDER_R = v(1.05, -1.55, 0.35)
local SHOULDER_L = v(-0.95, -1.55, 0.35)
-- Куда смотрят локти (вниз и в стороны).
local POLE_R = v(0.7, -1, 0.15)
local POLE_L = v(-0.7, -1, 0.15)

-- Как держать оружие:
--   pos   — точка хвата (правая рука) в пространстве камеры, −Z вперёд
--   rot   — поворот оружия
--   left  — где левая рука (в пространстве оружия, начало — хват, ствол в −Z); nil — левая рука не видна
--   mag   — где магазин (куда тянется левая рука при перезарядке)
--   recoil — сила отдачи (1 — автомат)
--   shell — цвет гильзы (nil — гильз нет)
--   kind  — "gun", "melee", "grenade"
local BRASS = Color3.fromRGB(205, 160, 70)
local GUN_ROT = ANG(0, rad(1.5), 0)
local HOLD: { [string]: any } = {
	Rifle = { pos = v(0.7, -0.85, -1.5), left = v(0, 0.22, -1.05), mag = v(0, -0.2, -0.45), recoil = 1, shell = BRASS },
	SMG = { pos = v(0.68, -0.82, -1.45), left = v(0, 0.25, -0.75), mag = v(0, -0.15, -0.35), recoil = 0.7, shell = BRASS },
	Shotgun = { pos = v(0.7, -0.85, -1.5), left = v(0, 0.12, -1.25), mag = v(0, 0, -0.8), recoil = 2.2, shell = Color3.fromRGB(170, 40, 35) },
	LMG = { pos = v(0.75, -0.95, -1.45), left = v(0.1, 0.1, -1.15), mag = v(0.3, 0, -0.3), recoil = 1.2, shell = BRASS },
	Sniper = { pos = v(0.7, -0.85, -1.5), left = v(0, 0.1, -1.35), mag = v(0, -0.1, -0.35), recoil = 2.6, shell = BRASS },
	Pistol = { pos = v(0.5, -0.78, -1.7), left = v(-0.12, -0.1, 0.06), mag = v(0, -0.45, 0.05), recoil = 1.3, shell = BRASS },
	Revolver = { pos = v(0.5, -0.78, -1.7), left = v(-0.12, -0.1, 0.06), mag = v(0, 0.2, -0.3), recoil = 2 },
	Knife = { kind = "melee", pos = v(0.68, -0.82, -1.5), rot = ANG(rad(25), rad(20), rad(-25)) },
	Bat = { kind = "melee", pos = v(0.8, -1.0, -1.5), rot = ANG(rad(65), rad(10), rad(-20)) },
	Grenade = { kind = "grenade", pos = v(0.62, -0.82, -1.6), rot = ANG(0, rad(-20), 0) },
}

local function holdFor(id: string, def): any
	if HOLD[id] then
		return HOLD[id]
	end
	if def and def.Kind == "Grenade" then
		return HOLD.Grenade
	end
	if def and def.Melee then
		return HOLD.Knife
	end
	if def and def.Slot == "Secondary" then
		return HOLD.Pistol
	end
	return HOLD.Rifle
end

------------------------------------------------------------------------
-- Небольшие помощники

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Перевод CFrame из пространства вьюмодели (без масштаба) в мир.
local function toWorld(cam: CFrame, cf: CFrame): CFrame
	return cam * (cf - cf.Position + cf.Position * SCALE)
end

-- Базис, у которого ось −Y идёт вдоль кости, а X как можно ближе к ref.
local function basis(bone: Vector3, ref: Vector3): CFrame
	local y = -bone.Unit
	local x = ref - y * ref:Dot(y)
	if x.Magnitude < 1e-3 then
		x = Vector3.zAxis:Cross(y)
	end
	x = x.Unit
	return CFrame.fromMatrix(Vector3.zero, x, y)
end

-- Пружина для отдачи: импульс в скорость, затухает сама.
local function spring(k: number, damp: number)
	return { x = 0, v = 0, k = k, d = damp }
end
local function stepSpring(s, dt: number)
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	for _ = 1, steps do
		s.v += (-s.k * s.x - s.d * s.v) * h
		s.x += s.v * h
	end
end

------------------------------------------------------------------------
-- Руки

type Arm = {
	upper: BasePart,
	lower: BasePart,
	hand: BasePart,
	shoulderU: Vector3, -- точка плеча в детали плеча
	boneU: Vector3, -- плечо→локоть в детали плеча
	elbowL: Vector3, -- точка локтя в предплечье
	boneL: Vector3, -- локоть→хват в предплечье (кисть считается продолжением предплечья)
	handOffset: CFrame, -- кисть относительно предплечья
	a: number,
	b: number,
}

local function attPos(part: Instance, name: string, fallback: Vector3): Vector3
	local a = part:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.Position else fallback
end

local function cleanCopy(part: BasePart, parent: Instance): BasePart
	local c = part:Clone()
	-- Внутри детали тела суставы, крепления аксессуаров, звуки — ничего этого не нужно.
	for _, child in c:GetChildren() do
		-- Текстуры (Texture/Decal) оставляем: на них камуфляж и надписи моделей оружия.
		if not (child:IsA("SpecialMesh") or child:IsA("SurfaceAppearance") or child:IsA("Texture") or child:IsA("Decal")) then
			child:Destroy()
		end
	end
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	c.Massless = true
	c.Transparency = 0
	c.LocalTransparencyModifier = 0
	c.Size *= SCALE
	local mesh = c:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.Scale *= SCALE
	end
	c.Parent = parent
	return c
end

-- Простая рука из брусков, если у персонажа не R15.
local function boxArm(parent: Instance, color: Color3, side: string): Arm
	local function box(name: string, size: Vector3, c: Color3): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * SCALE
		p.Color = c
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = parent
		return p
	end
	local upper = box(side .. "UpperArm", v(0.8, 1.1, 0.8), color)
	local lower = box(side .. "LowerArm", v(0.7, 1.0, 0.7), color)
	local hand = box(side .. "Hand", v(0.6, 0.5, 0.6), color)
	return {
		upper = upper,
		lower = lower,
		hand = hand,
		shoulderU = v(0, 0.45, 0),
		boneU = v(0, -0.9, 0),
		elbowL = v(0, 0.45, 0),
		boneL = v(0, -1.15, 0),
		handOffset = CF(0, -0.75, 0),
		a = 0.9,
		b = 1.15,
	}
end

local function buildArm(char: Model, parent: Instance, side: string): Arm
	local upperSrc = char:FindFirstChild(side .. "UpperArm")
	local lowerSrc = char:FindFirstChild(side .. "LowerArm")
	local handSrc = char:FindFirstChild(side .. "Hand")
	if not (upperSrc and lowerSrc and handSrc and upperSrc:IsA("BasePart") and lowerSrc:IsA("BasePart") and handSrc:IsA("BasePart")) then
		local src = char:FindFirstChild(side .. " Arm")
		local color = if src and src:IsA("BasePart") then src.Color else Color3.fromRGB(204, 142, 105)
		return boxArm(parent, color, side)
	end
	local shoulderU = attPos(upperSrc, side .. "ShoulderRigAttachment", v(0, 0.4, 0))
	local elbowU = attPos(upperSrc, side .. "ElbowRigAttachment", v(0, -0.3, 0))
	local elbowL = attPos(lowerSrc, side .. "ElbowRigAttachment", v(0, 0.3, 0))
	local wristL = attPos(lowerSrc, side .. "WristRigAttachment", v(0, -0.45, 0))
	local wristH = attPos(handSrc, side .. "WristRigAttachment", v(0, 0.2, 0))
	local gripH = attPos(handSrc, side .. "GripAttachment", v(0, -0.1, 0))
	-- В исходной позе суставы без поворота, поэтому кисть просто сдвинута относительно предплечья.
	local handOffset = CF(wristL - wristH)
	local gripInLower = wristL + (gripH - wristH)
	local arm: Arm = {
		upper = cleanCopy(upperSrc, parent),
		lower = cleanCopy(lowerSrc, parent),
		hand = cleanCopy(handSrc, parent),
		shoulderU = shoulderU,
		boneU = elbowU - shoulderU,
		elbowL = elbowL,
		boneL = gripInLower - elbowL,
		handOffset = handOffset,
		a = (elbowU - shoulderU).Magnitude,
		b = (gripInLower - elbowL).Magnitude,
	}
	return arm
end

-- Решение руки из двух костей: плечо, цель (точка хвата), направление локтя.
-- Возвращает CFrame трёх деталей в пространстве вьюмодели (до масштаба).
local function solveArm(arm: Arm, shoulder: Vector3, target: Vector3, pole: Vector3, roll: Vector3): (CFrame, CFrame, CFrame)
	local a, b = arm.a, arm.b
	local toT = target - shoulder
	local d = toT.Magnitude
	local dir = if d > 1e-4 then toT / d else v(0, 0, -1)
	local maxReach = (a + b) * 0.97
	if d > maxReach then
		shoulder = target - dir * maxReach
		d = maxReach
	end
	d = math.max(d, math.abs(a - b) + 0.05)
	local cosA = math.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local perp = pole - dir * pole:Dot(dir)
	perp = if perp.Magnitude > 1e-4 then perp.Unit else v(0, -1, 0)
	local elbow = shoulder + dir * (a * cosA) + perp * (a * sinA)

	local rU = basis(elbow - shoulder, roll) * basis(arm.boneU, Vector3.xAxis):Inverse()
	local upperCf = CFrame.new(shoulder - rU:VectorToWorldSpace(arm.shoulderU)) * rU
	local rL = basis(target - elbow, roll) * basis(arm.boneL, Vector3.xAxis):Inverse()
	local lowerCf = CFrame.new(elbow - rL:VectorToWorldSpace(arm.elbowL)) * rL
	return upperCf, lowerCf, lowerCf * arm.handOffset
end

------------------------------------------------------------------------
-- Сборка

type Built = {
	tool: Tool,
	id: string,
	def: any,
	hold: any,
	model: Model,
	right: Arm,
	left: Arm,
	pieces: { { part: BasePart, rel: CFrame } },
	muzzle: Vector3?,
	equipT: number,
}

local function gripFrame(tool: Tool): CFrame?
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return nil
	end
	return handle.CFrame * tool.Grip
end

local function build(char: Model, tool: Tool): Built?
	local id = tool:GetAttribute("WeaponId")
	if type(id) ~= "string" then
		return nil
	end
	local def = Weapons.List[id]
	local grip = gripFrame(tool)
	if not grip then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Viewmodel"
	-- Humanoid нужен, чтобы на руках рисовалась одежда (Shirt).
	local hum = Instance.new("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.EvaluateStateMachine = false
	hum.Parent = model
	local shirt = char:FindFirstChildOfClass("Shirt")
	if shirt then
		shirt:Clone().Parent = model
	end

	local pieces = {}
	for _, d in tool:GetDescendants() do
		-- Детали дальше 6 студов от хвата — мусор модели (они висели бы перед камерой).
		if d:IsA("BasePart") and d.Transparency < 1 and (d.Position - grip.Position).Magnitude < 6 then
			local rel = grip:ToObjectSpace(d.CFrame)
			local c = cleanCopy(d, model)
			c.Name = "W_" .. d.Name
			c.Transparency = d.Transparency
			table.insert(pieces, { part = c, rel = rel })
		end
	end
	local muzzle: Vector3? = nil
	local handle = tool:FindFirstChild("Handle")
	local m = handle and handle:FindFirstChild("Muzzle")
	if m and m:IsA("Attachment") then
		muzzle = grip:PointToObjectSpace(m.WorldPosition)
	end

	return {
		tool = tool,
		id = id,
		def = def,
		hold = holdFor(id, def),
		model = model,
		right = buildArm(char, model, "Right"),
		left = buildArm(char, model, "Left"),
		pieces = pieces,
		muzzle = muzzle,
		equipT = 0,
	}
end

------------------------------------------------------------------------
-- Состояние анимаций

local built: Built? = nil
local lastGunCf: CFrame? = nil -- оружие в мире на последнем кадре
local lastCam: CFrame? = nil

local recoilBack = spring(260, 20)
local recoilPitch = spring(220, 16)
local recoilRoll = spring(200, 14)
local recoilYaw = spring(240, 18) -- увод ствола вбок, у каждого выстрела свой
local camPunch = spring(180, 18)
local sway = v(0, 0, 0)
local bobT = 0
local bobAmt = 0
local sprintA = 0
local airY = 0
local strafe = 0 -- движение вбок относительно взгляда, −1..1
local forward = 0 -- движение вперёд, −1..1
local landDip = spring(170, 13) -- просадка при приземлении
local wasGrounded = true
local fallSpeed = 0
local reloadStart: number? = nil
local reloadEnd: number? = nil
local swingStart: number? = nil
local swingDir = 1
local throwStart: number? = nil
local hiddenUntil = 0

type Shell = { part: BasePart, vel: Vector3, rot: Vector3, t: number }
local shells: { Shell } = {}

local function lerpV(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, smooth(t))
end

-- Где левая рука во время перезарядки (доля p от 0 до 1).
local function reloadLeft(p: number, fore: Vector3, mag: Vector3, down: Vector3): Vector3
	if p < 0.12 then
		return fore
	elseif p < 0.25 then
		return lerpV(fore, mag, (p - 0.12) / 0.13)
	elseif p < 0.42 then
		return lerpV(mag, down, (p - 0.25) / 0.17)
	elseif p < 0.58 then
		return down
	elseif p < 0.72 then
		return lerpV(down, mag, (p - 0.58) / 0.14)
	elseif p < 0.85 then
		return mag
	end
	return lerpV(mag, fore, (p - 0.85) / 0.15)
end

local function setVisible(part: BasePart, on: boolean)
	part.Transparency = if on then 0 else 1
end

local function clearBuilt()
	if built then
		built.model:Destroy()
		built = nil
	end
	lastGunCf = nil
	reloadStart = nil
	swingStart = nil
	throwStart = nil
end

------------------------------------------------------------------------
-- Что видно

local function firstPerson(char: Model?): boolean
	if not char or player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local head = char:FindFirstChild("Head")
	if not hum or hum.Health <= 0 or hum.SeatPart or not head or char:GetAttribute("Downed") then
		return false
	end
	local cam = workspace.CurrentCamera
	return cam.CameraSubject == hum and (cam.CFrame.Position - (head :: BasePart).Position).Magnitude < 2.5
end

local function hideReal(char: Model, tool: Tool?)
	for _, name in { "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand", "Right Arm", "Left Arm" } do
		local p = char:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.LocalTransparencyModifier = 1
		end
	end
	-- Одежда и аксессуары настоящего персонажа (рукава 3D-одежды, перчатки, часы):
	-- его руки держат оружие перед грудью, и без этого рукава висели бы перед камерой.
	for _, acc in char:GetChildren() do
		if acc:IsA("Accessory") then
			for _, d in acc:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = 1
				end
			end
		end
	end
	if tool then
		-- Texture и Decal рисуются, даже когда деталь спрятана, поэтому прячем и их
		-- (иначе камуфляж и стекло прицела висят перед камерой). Texture — наследник Decal.
		for _, d in tool:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = 1
			end
		end
	end
end

local function showRealTool(tool: Tool?)
	if tool and tool.Parent then
		for _, d in tool:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = 0
			end
		end
	end
end

------------------------------------------------------------------------
-- Кадр

local function update(dt: number)
	dt = math.min(dt, 0.1)
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("WeaponId") == nil then
		tool = nil
	end
	local on = tool ~= nil and firstPerson(char) and not PlayerSettings.isAiming()

	if not on then
		if built then
			showRealTool(built.tool)
			clearBuilt()
		end
		return
	end
	assert(char and tool)
	if not built or built.tool ~= tool then
		if built then
			showRealTool(built.tool)
		end
		clearBuilt()
		built = build(char, tool)
		if not built then
			return
		end
		built.model.Parent = workspace.CurrentCamera
	end
	local b = built :: Built
	hideReal(char, tool)

	local cam = workspace.CurrentCamera
	local camCf = cam.CFrame
	local hold = b.hold
	local now = os.clock()
	b.equipT += dt

	-- Движение персонажа.
	local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local vel = if root then root.AssemblyLinearVelocity else Vector3.zero
	local flat = v(vel.X, 0, vel.Z).Magnitude
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local moving = grounded and flat > 1
	bobAmt += ((if moving then math.min(flat / 16, 1.6) else 0) - bobAmt) * math.min(1, dt * 8)
	bobT += dt * (4 + flat * 0.42)
	local reloading = tool:GetAttribute("Reloading") == true
	local busy = reloading or swingStart ~= nil or throwStart ~= nil
	local sprinting = grounded and flat > 19.5 and not busy
	sprintA += ((if sprinting then 1 else 0) - sprintA) * math.min(1, dt * 9)
	airY += ((if grounded then 0 else math.clamp(-vel.Y * 0.006, -0.2, 0.2)) - airY) * math.min(1, dt * 10)
	-- Приземление: оружие проседает и пружинит обратно, сильнее после долгого падения.
	if not grounded then
		fallSpeed = math.max(fallSpeed, -vel.Y)
	elseif not wasGrounded then
		landDip.v -= math.clamp(fallSpeed * 0.09, 0.6, 4)
		fallSpeed = 0
	end
	wasGrounded = grounded
	stepSpring(landDip, dt)
	-- Скорость относительно взгляда: вбок — наклон оружия, вперёд — оружие чуть отстаёт.
	local localVel = camCf:VectorToObjectSpace(vel)
	strafe += (math.clamp(localVel.X / 16, -1, 1) - strafe) * math.min(1, dt * 6)
	forward += (math.clamp(-localVel.Z / 16, -1, 1) - forward) * math.min(1, dt * 5)

	-- Инерция при повороте камеры.
	local swayTarget = Vector3.zero
	if lastCam then
		local delta = lastCam:ToObjectSpace(camCf)
		local rx, ry = delta:ToOrientation()
		swayTarget = v(math.clamp(rx / dt * 0.012, -0.12, 0.12), math.clamp(ry / dt * 0.012, -0.12, 0.12), 0)
	end
	lastCam = camCf
	sway += (swayTarget - sway) * math.min(1, dt * 12)

	-- Перезарядка.
	if reloading and not reloadStart then
		reloadStart = now
		reloadEnd = nil
	elseif not reloading and reloadStart then
		reloadStart = nil
		reloadEnd = now
	end
	local reloadTime = (b.def and b.def.ReloadTime) or 2
	local reloadP = if reloadStart then math.clamp((now - reloadStart) / reloadTime, 0, 1) else 1
	local tilt = 0
	if reloadStart then
		tilt = smooth(reloadP / 0.15) * (1 - smooth((reloadP - 0.85) / 0.15))
	elseif reloadEnd and now - reloadEnd < 0.25 then
		tilt = 1 - smooth((now - reloadEnd) / 0.25)
	end

	stepSpring(recoilBack, dt)
	stepSpring(recoilPitch, dt)
	stepSpring(recoilRoll, dt)
	stepSpring(recoilYaw, dt)

	-- Доставание: оружие поднимается снизу.
	local e = 1 - (1 - math.clamp(b.equipT / 0.4, 0, 1)) ^ 3
	local ue = 1 - e

	-- Смещения в пространстве камеры.
	-- Шаг: восьмёрка (вбок на каждый шаг, вниз на каждое касание), на бегу размашистее.
	local stride = bobAmt * (1 + 0.7 * sprintA)
	local bobX = math.sin(bobT) * 0.05 * stride
	local bobY = -math.abs(math.cos(bobT)) * 0.045 * stride
	-- На месте: дыхание (вверх-вниз и чуть по наклону) и медленное покачивание рук.
	local still = math.max(0, 1 - bobAmt) * (1 - sprintA)
	local breath = math.sin(now * 1.25)
	local idleX = math.sin(now * 0.55) * 0.018 * still
	local idleY = (breath * 0.014 + math.sin(now * 1.1) * 0.005) * still
	local idlePitch = breath * 0.012 * still
	local idleRoll = math.sin(now * 0.55 + 1.3) * 0.02 * still
	local dip = landDip.x
	local offset = CF(
		bobX - sway.Y * 0.6 + idleX - strafe * 0.05,
		bobY + idleY + airY + dip * 0.25 - ue * 1.1 + sway.X * 0.5,
		ue * 0.2 + forward * 0.05 * (1 - sprintA)
	)
	local rotView = ANG(
		sway.X * 0.9 - ue * 0.9 + bobY * 0.4 + idlePitch + dip * 0.2,
		sway.Y * 1.1,
		sway.Y * 0.8 + bobX * 0.6 + idleRoll - strafe * 0.1 + ue * 0.4
	)
	-- Бег: оружие у груди наискосок, стволом влево-вниз.
	local sprintCf = CF(-0.3 * sprintA, -0.28 * sprintA, 0.2 * sprintA) * ANG(-0.5 * sprintA, 0.85 * sprintA, 0.42 * sprintA)

	-- Анимации в пространстве оружия: отдача, наклон при перезарядке, удар, бросок.
	local local_ = CF(0, 0.08 * tilt, 0) * ANG(0.2 * tilt, 0.25 * tilt, 0.75 * tilt)
	-- Толчок, когда магазин встаёт на место.
	if reloadStart and reloadP > 0.72 and reloadP < 0.8 then
		local k = math.sin((reloadP - 0.72) / 0.08 * math.pi)
		local_ *= CF(0, 0.05 * k, 0) * ANG(0.06 * k, 0, 0)
	end
	local_ *= CF(0, 0, recoilBack.x) * ANG(recoilPitch.x, recoilYaw.x, recoilRoll.x)

	local swingCf = CFrame.identity
	if swingStart then
		local t = (now - swingStart) / 0.38
		if t >= 1 then
			swingStart = nil
		else
			local s = math.sin(math.pi * math.min(t / 0.85, 1))
			swingCf = CF(-0.7 * s * swingDir, 0.2 * s, -0.45 * s) * ANG(-0.25 * s, 0.9 * s * swingDir, -0.6 * s * swingDir)
		end
	end
	local weaponHidden = now < hiddenUntil
	if throwStart then
		local t = now - throwStart
		if t >= 0.55 then
			throwStart = nil
		else
			local back = smooth(t / 0.22)
			local fwd = smooth((t - 0.22) / 0.18)
			local s = back - fwd
			swingCf = CF(0.15 * back - 0.5 * fwd, 0.7 * s + 0.1 * fwd, 0.6 * s - 0.9 * fwd) * ANG(0.9 * s - 0.6 * fwd, 0, -0.3 * s)
		end
	end

	local gunCf = offset * CF(hold.pos) * rotView * sprintCf * swingCf * (hold.rot or GUN_ROT) * local_

	-- Детали оружия.
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	for _, piece in b.pieces do
		table.insert(parts, piece.part)
		table.insert(cfs, toWorld(camCf, gunCf * piece.rel))
		piece.part.LocalTransparencyModifier = if weaponHidden then 1 else 0
	end
	lastGunCf = toWorld(camCf, gunCf)

	-- Правая рука на рукоятке.
	local rollR = v(1, -0.35, 0)
	local uR, lR, hR = solveArm(b.right, SHOULDER_R, gunCf.Position, POLE_R, rollR)

	-- Левая рука: цевьё, при перезарядке — к магазину и вниз за кадр.
	local leftVisible = hold.left ~= nil
	local uL, lL, hL
	if leftVisible then
		local fore = gunCf * hold.left
		local target = fore
		if reloadStart then
			local mag = gunCf * (hold.mag or v(0, -0.3, -0.4))
			local down = v(-0.4, -2.8, -0.6)
			target = reloadLeft(reloadP, fore, mag, down)
		end
		uL, lL, hL = solveArm(b.left, SHOULDER_L, target, POLE_L, v(0.2, 1, 0))
	else
		-- Без левой руки: прячем её внизу за кадром.
		uL, lL, hL = solveArm(b.left, SHOULDER_L, v(-0.8, -3, -0.5), POLE_L, v(0, 1, 0))
	end
	for _, pair in { { b.right.upper, uR }, { b.right.lower, lR }, { b.right.hand, hR }, { b.left.upper, uL }, { b.left.lower, lL }, { b.left.hand, hL } } do
		table.insert(parts, pair[1])
		table.insert(cfs, toWorld(camCf, pair[2]))
	end
	for _, p in { b.left.upper, b.left.lower, b.left.hand } do
		setVisible(p, leftVisible)
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)

	-- Гильзы летят в мире, падают и исчезают.
	for i = #shells, 1, -1 do
		local s = shells[i]
		s.t += dt
		if s.t > 0.7 then
			s.part:Destroy()
			table.remove(shells, i)
		else
			s.vel += v(0, -workspace.Gravity * 0.25, 0) * dt
			s.part.CFrame = (s.part.CFrame + s.vel * dt) * ANG(s.rot.X * dt, s.rot.Y * dt, s.rot.Z * dt)
		end
	end
end

-- Лёгкий подброс камеры при выстреле. Ставится до вьюмодели, чтобы руки шли вместе с камерой.
-- Камера Roblox считает следующий кадр от текущего CFrame камеры, поэтому подброс
-- добавляем только разницей с прошлым кадром: когда пружина вернулась, прицел стоит там же,
-- где был, и очередь не уводит вверх.
local appliedPunch = 0
local function updateCamera(dt: number)
	stepSpring(camPunch, math.min(dt, 0.1))
	local target = if built then camPunch.x else 0
	local delta = target - appliedPunch
	if math.abs(delta) > 1e-6 then
		workspace.CurrentCamera.CFrame *= ANG(delta, 0, 0)
		appliedPunch = target
	end
end

------------------------------------------------------------------------
-- Публичное

-- Вызывается WeaponController после своего выстрела, удара или броска.
function Viewmodel.onFire()
	local b = built
	if not b then
		return
	end
	local kind = b.hold.kind or "gun"
	if kind == "melee" then
		swingStart = os.clock()
		swingDir = -swingDir
		return
	end
	if kind == "grenade" then
		throwStart = os.clock()
		hiddenUntil = os.clock() + 0.9
		return
	end
	local r = b.hold.recoil or 1
	recoilBack.v += 2.2 * r
	recoilPitch.v += 0.8 * r
	recoilRoll.v += (math.random() - 0.5) * 0.8 * r
	recoilYaw.v += (math.random() - 0.5) * 0.5 * r
	camPunch.v += 0.07 * r

	-- Вспышка у дула и гильза.
	local cam = workspace.CurrentCamera
	local muzzleWorld = Viewmodel.muzzle()
	if muzzleWorld and lastGunCf then
		local dirCf = lastGunCf - lastGunCf.Position + muzzleWorld
		local flash = Instance.new("Part")
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanQuery = false
		flash.CanTouch = false
		flash.CastShadow = false
		flash.Material = Enum.Material.Neon
		flash.Color = Color3.fromRGB(255, 205, 110)
		flash.Size = v(0.22, 0.22, 0.6) * SCALE * (0.8 + r * 0.2)
		flash.CFrame = dirCf * CF(0, 0, -0.25 * SCALE) * ANG(0, 0, math.random() * math.pi)
		local light = Instance.new("PointLight")
		light.Color = flash.Color
		light.Range = 12
		light.Brightness = 3
		light.Parent = flash
		local star = flash:Clone()
		star:ClearAllChildren()
		star.Size = v(0.5, 0.06, 0.06) * SCALE * (0.8 + r * 0.2)
		star.CFrame = dirCf * ANG(0, 0, math.random() * math.pi)
		star.Parent = cam
		flash.Parent = cam
		task.delay(0.045, function()
			flash:Destroy()
			star:Destroy()
		end)
	end
	if b.hold.shell and lastGunCf then
		local port = lastGunCf * CF(v(0.12, 0.45, -0.25) * SCALE)
		local shell = Instance.new("Part")
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.CastShadow = false
		shell.Material = Enum.Material.Metal
		shell.Color = b.hold.shell
		shell.Size = v(0.06, 0.06, 0.18) * (if b.hold.shell == BRASS then 1 else 1.5)
		shell.CFrame = port
		shell.Parent = cam
		local right = lastGunCf.RightVector
		local up = lastGunCf.UpVector
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local base = if root then root.AssemblyLinearVelocity else Vector3.zero
		table.insert(shells, {
			part = shell,
			vel = base + right * (7 + math.random() * 3) + up * (4 + math.random() * 2) + lastGunCf.LookVector * -1,
			rot = v(math.random() * 20 - 10, math.random() * 20 - 10, math.random() * 20 - 10),
			t = 0,
		})
	end
end

-- Точка у дула вьюмодели в мире (для трассера своих выстрелов). nil, если вьюмодели нет.
function Viewmodel.muzzle(): Vector3?
	local b = built
	if not b or not lastGunCf or not b.muzzle then
		return nil
	end
	return lastGunCf * (b.muzzle * SCALE)
end

function Viewmodel.active(): boolean
	return built ~= nil
end

function Viewmodel.init()
	RunService:BindToRenderStep("ViewmodelCamera", Enum.RenderPriority.Camera.Value + 4, updateCamera)
	RunService:BindToRenderStep("Viewmodel", Enum.RenderPriority.Camera.Value + 5, update)
	player.CharacterAdded:Connect(function()
		clearBuilt()
		for _, s in shells do
			s.part:Destroy()
		end
		table.clear(shells)
	end)
end

return Viewmodel
