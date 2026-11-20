-- Контроллер анимаций своего персонажа (вместо стандартного скрипта Animate Roblox).
-- Анимации своего персонажа играет клиент, и Roblox сам показывает их всем остальным.
--
-- Чем лучше стандартного:
--   * покой, шаг и бег играют одновременно и смешиваются весами по скорости (blend tree),
--     а не переключаются рывком; скорость проигрывания подогнана под скорость движения,
--     чтобы ступни не скользили по земле;
--   * шаг и бег спиной вперёд — та же анимация задом наперёд (а не бег вперёд при движении назад);
--   * длинные мягкие переходы между состояниями (покой ↔ движение, прыжок, падение, сидение);
--   * в покое время от времени — вторая поза покоя (переминается, осматривается).
-- Процедурные добавки поверх (наклоны, разворот бёдер, дыхание, взгляд, IK ног) делают
-- Locomotion и BodyLife для всех персонажей. Настройки — Config/Character (Director).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.Character)
local Config = CharacterConfig.Director
local ANIMS = CharacterConfig.Animations

local player = Players.LocalPlayer

local AnimDirector = {}

local TINY = 1e-4 -- вес «почти ноль»: трек продолжает идти, чтобы переход был плавным

type Slot = { track: AnimationTrack, weight: number, speed: number }

type Rig = {
	char: Model,
	hum: Humanoid,
	root: BasePart,
	slots: { [string]: Slot },
	moving: number, -- 0 — стоит, 1 — идёт (сглажено)
	dir: number, -- 1 — вперёд, −1 — спиной вперёд
	mode: string,
	modeAt: number,
	idle2Until: number,
	nextIdle2: number,
	blending: boolean,
	conns: { RBXScriptConnection },
}

local rig: Rig? = nil

local function idOf(value: any): string?
	local v = if type(value) == "table" then value[1] else value
	if type(v) == "string" and v ~= "" then
		return "rbxassetid://" .. v
	end
	return nil
end

local function heightScale(hum: Humanoid): number
	local v = hum:FindFirstChild("BodyHeightScale")
	if v and v:IsA("NumberValue") and v.Value > 0 then
		return v.Value
	end
	return 1
end

-- Вес и скорость трека меняем только при заметной разнице: каждое изменение уходит по сети.
local function setWeight(slot: Slot?, w: number, fade: number)
	if not slot then
		return
	end
	w = math.max(TINY, w)
	if math.abs(slot.weight - w) > 0.04 or (w == TINY and slot.weight ~= TINY) or (w >= 0.999 and slot.weight < 0.999) then
		slot.weight = w
		slot.track:AdjustWeight(w, fade)
	end
end

local function setSpeed(slot: Slot?, s: number)
	if slot and math.abs(slot.speed - s) > 0.05 then
		slot.speed = s
		slot.track:AdjustSpeed(s)
	end
end

local function destroyRig()
	local r = rig
	if not r then
		return
	end
	rig = nil
	for _, c in r.conns do
		c:Disconnect()
	end
	for _, slot in r.slots do
		pcall(function()
			slot.track:Stop(0.2)
		end)
	end
end

local function build(char: Model)
	destroyRig()
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hum or not root or hum.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	local animator = hum:WaitForChild("Animator", 5) :: Animator?
	if not animator then
		return
	end
	-- Стандартный Animate выключаем и гасим его анимации.
	local animate = char:WaitForChild("Animate", 5)
	if animate and animate:IsA("LocalScript") then
		animate.Disabled = true
	end
	for _, t in animator:GetPlayingAnimationTracks() do
		t:Stop(0.2)
	end

	local slots: { [string]: Slot } = {}
	local function load(name: string, id: string?, looped: boolean)
		if not id then
			return
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, anim)
		if ok and track then
			track.Looped = looped
			track.Priority = Enum.AnimationPriority.Core
			slots[name] = { track = track, weight = TINY, speed = 1 }
		end
	end
	local idle = ANIMS.idle
	load("idle", idOf(idle), true)
	load("idle2", if type(idle) == "table" and idle[2] then "rbxassetid://" .. idle[2] else nil, true)
	load("walk", idOf(ANIMS.walk), true)
	load("run", idOf(ANIMS.run), true)
	load("jump", idOf(ANIMS.jump), false)
	load("fall", idOf(ANIMS.fall), true)
	load("climb", idOf(ANIMS.climb), true)
	load("swim", idOf(ANIMS.swim), true)
	load("swimidle", idOf(ANIMS.swimidle), true)
	load("sit", idOf(ANIMS.sit), true)

	-- Покой, шаг и бег играют всё время (смешиваются весами), остальные — по необходимости.
	for _, name in { "idle", "walk", "run" } do
		local slot = slots[name]
		if slot then
			slot.weight = if name == "idle" then 1 else TINY
			slot.track:Play(0.3, slot.weight, 1)
		end
	end

	local now = os.clock()
	local r: Rig = {
		char = char,
		hum = hum,
		root = root,
		slots = slots,
		moving = 0,
		dir = 1,
		mode = "ground",
		modeAt = now,
		idle2Until = 0,
		nextIdle2 = now + math.random(Config.Idle2Min, Config.Idle2Max),
		blending = false,
		conns = {},
	}
	rig = r
	table.insert(
		r.conns,
		hum.Died:Connect(function()
			for _, slot in r.slots do
				slot.track:Stop(0.4)
			end
			if rig == r then
				rig = nil
			end
		end)
	)
end

local AIR_STATES = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
}

local function modeOf(r: Rig): string
	local hum = r.hum
	local state = hum:GetState()
	if hum.SeatPart or hum.Sit or state == Enum.HumanoidStateType.Seated then
		return "sit"
	elseif state == Enum.HumanoidStateType.Climbing then
		return "climb"
	elseif state == Enum.HumanoidStateType.Swimming then
		return "swim"
	elseif AIR_STATES[state] then
		return "air"
	end
	return "ground"
end

-- Играть трек (если ещё не играет) и вывести его вес на 1.
local function ensure(slot: Slot?, fade: number, restart: boolean?)
	if not slot then
		return
	end
	if not slot.track.IsPlaying or restart then
		slot.weight = 1
		slot.track:Play(fade, 1, slot.speed)
	else
		setWeight(slot, 1, fade)
	end
end

local function stopSlot(slot: Slot?, fade: number)
	if slot and slot.track.IsPlaying then
		slot.track:Stop(fade)
		slot.weight = TINY
	end
end

local function step(dt: number)
	local r = rig
	if not r or not r.root.Parent or r.hum.Health <= 0 then
		return
	end
	local s = r.slots
	local hum, root = r.hum, r.root
	local now = os.clock()

	local mode = modeOf(r)
	if mode ~= r.mode then
		local prev = r.mode
		r.mode = mode
		r.modeAt = now
		-- Выход из прежнего состояния.
		if prev == "air" then
			stopSlot(s.jump, Config.LandFade)
			stopSlot(s.fall, Config.LandFade)
		elseif prev == "sit" then
			stopSlot(s.sit, Config.SitFade)
		elseif prev == "climb" then
			stopSlot(s.climb, 0.25)
		elseif prev == "swim" then
			stopSlot(s.swim, 0.4)
			stopSlot(s.swimidle, 0.4)
		end
		-- Вход в новое.
		if mode == "air" then
			if hum:GetState() == Enum.HumanoidStateType.Jumping then
				ensure(s.jump, 0.1, true)
			end
		elseif mode == "sit" then
			ensure(s.sit, Config.SitFade, true)
		elseif mode == "climb" then
			ensure(s.climb, 0.2, true)
		end
	end

	local vel = root.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude

	-- Пока играет «чужое» состояние, покой/шаг/бег уходят в почти ноль.
	local ground = mode == "ground"
	local groundFade = if ground then Config.GroundFade else 0.15

	if mode == "air" then
		-- Прыжок, затем падение. Короткий прыжок с места — без анимации падения.
		local t = now - r.modeAt
		if (t > 0.3 or vel.Y < -8) and s.fall then
			ensure(s.fall, 0.25)
			setWeight(s.jump, TINY, 0.25)
		end
	elseif mode == "climb" then
		setSpeed(s.climb, math.clamp(vel.Y / 5, -1.5, 1.5))
	elseif mode == "swim" then
		if speed > 1.5 then
			ensure(s.swim, 0.4)
			stopSlot(s.swimidle, 0.4)
			setSpeed(s.swim, math.clamp(speed / 10, 0.4, 1.6))
		else
			ensure(s.swimidle, 0.4)
			stopSlot(s.swim, 0.4)
		end
	end

	-- Покой ↔ движение: сглаженный вес.
	local movingTarget = if speed > Config.MoveThreshold then 1 else 0
	local rate = if movingTarget > r.moving then Config.StartRate else Config.StopRate
	r.moving += (movingTarget - r.moving) * math.min(1, dt * rate)

	-- Спиной вперёд: движение больше чем на ~110° от взгляда.
	if speed > 0.5 then
		local fwd = flat.Unit:Dot(root.CFrame.LookVector)
		if fwd < -0.35 then
			r.dir = -1
		elseif fwd > -0.2 then
			r.dir = 1
		end
	end

	-- Шаг/бег: те же пороги, что у стандартного Animate (нормированная скорость с учётом роста).
	local n = speed * 1.25 / heightScale(hum) / 16
	local walkW, runW, walkSpeed, runSpeed
	if n <= Config.WalkNorm then
		walkW, runW = 1, 0
		walkSpeed, runSpeed = math.max(Config.MinPlaySpeed, n / Config.WalkNorm), 1
	elseif n < Config.RunNorm then
		local f = (n - Config.WalkNorm) / (Config.RunNorm - Config.WalkNorm)
		f = f * f * (3 - 2 * f) -- плавная кривая смешивания
		walkW, runW = 1 - f, f
		walkSpeed, runSpeed = 1, 1
	else
		walkW, runW = 0, 1
		walkSpeed, runSpeed = 1, math.min(Config.MaxPlaySpeed, n / Config.RunNorm)
	end
	-- В зоне смешивания шаг и бег идут в одной фазе (ступни не «перебирают» вразнобой).
	local blending = walkW > 0.05 and runW > 0.05
	if blending and not r.blending and s.walk and s.run and s.walk.track.Length > 0 and s.run.track.Length > 0 then
		local phase = s.walk.track.TimePosition / s.walk.track.Length
		s.run.track.TimePosition = phase * s.run.track.Length
	end
	r.blending = blending

	-- Вторая поза покоя время от времени.
	local useIdle2 = false
	if s.idle2 and ground and r.moving < 0.05 then
		if now >= r.nextIdle2 and r.idle2Until < now then
			r.idle2Until = now + math.max(2.5, math.min(s.idle2.track.Length, 6))
			r.nextIdle2 = r.idle2Until + math.random(Config.Idle2Min, Config.Idle2Max)
			if not s.idle2.track.IsPlaying then
				s.idle2.track:Play(0.6, TINY, 1)
			end
		end
		useIdle2 = now < r.idle2Until
	elseif now < r.idle2Until then
		r.idle2Until = 0
	end

	local g = if ground then 1 else 0
	local m = r.moving
	setWeight(s.idle, g * (1 - m) * (if useIdle2 then 0 else 1), if useIdle2 then 0.6 else groundFade)
	if s.idle2 and s.idle2.track.IsPlaying then
		setWeight(s.idle2, g * (1 - m) * (if useIdle2 then 1 else 0), 0.6)
		if not useIdle2 and r.idle2Until == 0 or now > r.idle2Until + 1 then
			stopSlot(s.idle2, 0.6)
		end
	end
	setWeight(s.walk, g * m * walkW, groundFade)
	setWeight(s.run, g * m * runW, groundFade)
	setSpeed(s.walk, walkSpeed * r.dir)
	setSpeed(s.run, runSpeed * r.dir)
end

function AnimDirector.init()
	if not Config or Config.Enabled == false then
		return
	end
	player.CharacterAdded:Connect(function(char)
		task.spawn(build, char)
	end)
	player.CharacterRemoving:Connect(function()
		destroyRig()
	end)
	if player.Character then
		task.spawn(build, player.Character)
	end
	RunService.Heartbeat:Connect(function(dt)
		step(math.min(dt, 0.1))
	end)
end

return AnimDirector
