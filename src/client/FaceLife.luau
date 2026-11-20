-- Мимика персонажей с динамической головой (FaceControls): считается у каждого клиента
-- для всех лиц рядом с камерой.
--   * моргание раз в 2–5 с (иногда двойное), чаще — когда запыхался;
--   * глаза смотрят туда же, куда голова (и дальше, если голова уже не доворачивается),
--     с мелкими быстрыми движениями (саккадами), как у живого человека;
--   * после бега рот приоткрыт в такт дыханию, брови напряжены;
--   * с оружием — сосредоточенный взгляд (прищур, сведённые брови);
--   * попадание — гримаса боли, раненый (Downed) — боль не отпускает;
--   * в покое — едва заметные движения бровей и губ, лицо не «замирает» маской.
-- Если у головы нет FaceControls (обычная голова), ничего не делает.
-- Настройки — Config/Character (Face).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Character).Face
local PoseStack = require(script.Parent.PoseStack)
local BodyLife = require(script.Parent.BodyLife)

local player = Players.LocalPlayer

local FaceLife = {}

type State = {
	face: FaceControls,
	hum: Humanoid,
	seed: number,
	nextBlink: number,
	blinkAt: number,
	double: boolean,
	eyeX: number,
	eyeY: number,
	sacX: number,
	sacY: number,
	nextSac: number,
	wince: number,
	lastHealth: number,
	written: { [string]: number },
}

local states: { [Model]: State } = {}
local broken: { [string]: boolean } = {} -- свойства, которых нет у этой версии FaceControls

local function set(st: State, prop: string, value: number)
	if broken[prop] then
		return
	end
	value = math.clamp(value, 0, 1)
	local old = st.written[prop]
	if old and math.abs(old - value) < 0.01 then
		return
	end
	local ok = pcall(function()
		(st.face :: any)[prop] = value
	end)
	if ok then
		st.written[prop] = value
	else
		broken[prop] = true
	end
end

local function both(st: State, prop: string, value: number)
	set(st, "Left" .. prop, value)
	set(st, "Right" .. prop, value)
end

local function build(char: Model): State?
	local head = char:FindFirstChild("Head")
	local face = head and head:FindFirstChildOfClass("FaceControls")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not face or not hum then
		return nil
	end
	local now = os.clock()
	return {
		face = face,
		hum = hum,
		seed = math.random() * 100,
		nextBlink = now + math.random() * 3,
		blinkAt = -10,
		double = false,
		eyeX = 0,
		eyeY = 0,
		sacX = 0,
		sacY = 0,
		nextSac = now,
		wince = 0,
		lastHealth = hum.Health,
		written = {},
	}
end

local function update(char: Model, st: State, dt: number, camPos: Vector3, now: number)
	local hum = st.hum
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head or not st.face.Parent then
		states[char] = nil
		return
	end
	if (head.Position - camPos).Magnitude > Config.MaxDistance then
		return
	end
	if char == player.Character and (head.Position - camPos).Magnitude < 1.6 then
		return -- своё лицо в виде от первого лица не видно
	end

	local dead = hum.Health <= 0
	-- Боль: при каждом попадании — гримаса, тем сильнее, чем больше урон.
	if hum.Health < st.lastHealth - 0.5 then
		local frac = (st.lastHealth - hum.Health) / math.max(1, hum.MaxHealth)
		st.wince = math.min(1, st.wince + 0.45 + frac * 2)
	end
	st.lastHealth = hum.Health
	local downed = char:GetAttribute("Downed") == true
	st.wince = math.max(if downed then 0.55 else 0, st.wince - dt * 1.4)

	local exertion = BodyLife.exertion(char)
	local tool = char:FindFirstChildOfClass("Tool")
	local focus = if tool and tool:GetAttribute("WeaponId") then 1 else 0
	local seat = hum.SeatPart
	if seat and seat:IsA("VehicleSeat") then
		local v = seat.AssemblyLinearVelocity.Magnitude
		focus = math.max(focus, math.clamp(v / 80, 0, 0.8))
	end

	-- Моргание (быстро закрыть, чуть медленнее открыть).
	if now >= st.nextBlink then
		st.blinkAt = now
		st.double = math.random() < 0.18
		local gap = Config.BlinkMin + math.random() * (Config.BlinkMax - Config.BlinkMin)
		st.nextBlink = now + gap * (1 - 0.45 * exertion)
	end
	local bt = (now - st.blinkAt) / Config.BlinkTime
	local blink = 0
	if bt < 1 then
		blink = if bt < 0.4 then bt / 0.4 else 1 - (bt - 0.4) / 0.6
	elseif st.double and bt < 2.2 and bt > 1.2 then
		local b2 = bt - 1.2
		blink = if b2 < 0.4 then b2 / 0.4 else math.max(0, 1 - (b2 - 0.4) / 0.6)
	end

	-- Глаза: остаток взгляда, который голова не взяла, плюс мелкие саккады.
	local wantYaw, wantPitch, headYaw, headPitch = BodyLife.gaze(char)
	if now >= st.nextSac then
		st.nextSac = now + 0.35 + math.random() * 1.4
		st.sacX = (math.random() - 0.5) * 0.25
		st.sacY = (math.random() - 0.5) * 0.15
	end
	local ex = math.clamp((wantYaw - headYaw) / 0.55, -1, 1) + st.sacX
	local ey = math.clamp((wantPitch - headPitch) / 0.4, -1, 1) + st.sacY
	local k = math.min(1, dt * 22)
	st.eyeX += (ex - st.eyeX) * k
	st.eyeY += (ey - st.eyeY) * k

	-- Едва заметная «жизнь» в покое.
	local t = now * 0.35 + st.seed
	local micro = math.noise(t, st.seed) * 0.08
	local micro2 = math.noise(st.seed, t * 1.3) * 0.06

	local w = st.wince
	local breath = math.sin(BodyLife.breathPhase(char))
	local mouth = exertion * (0.18 + 0.12 * breath)

	if dead then
		both(st, "EyeClosed", 0.75)
		set(st, "JawDrop", 0.15)
		both(st, "BrowLowerer", 0)
		both(st, "LidTightener", 0)
		both(st, "LipStretcher", 0)
		both(st, "NoseWrinkler", 0)
		return
	end

	both(st, "EyeClosed", math.max(blink, w * 0.35, exertion * 0.08))
	set(st, "EyesLookLeft", math.max(0, st.eyeX))
	set(st, "EyesLookRight", math.max(0, -st.eyeX))
	set(st, "EyesLookUp", math.max(0, st.eyeY))
	set(st, "EyesLookDown", math.max(0, -st.eyeY))
	both(st, "BrowLowerer", math.max(0, micro) + focus * 0.28 + exertion * 0.2 + w * 0.8)
	both(st, "InnerBrowRaiser", math.max(0, -micro) * 0.8 + w * 0.25)
	both(st, "LidTightener", focus * 0.3 + exertion * 0.15 + w * 0.75)
	set(st, "Corrugator", focus * 0.2 + w * 0.6)
	both(st, "NoseWrinkler", w * 0.5)
	both(st, "LipStretcher", w * 0.55 + exertion * 0.1)
	both(st, "LipCornerPuller", math.max(0, micro2) * 0.6)
	set(st, "LipsTogether", focus * 0.25 * (1 - exertion))
	set(st, "JawDrop", math.max(mouth, w * 0.22))
end

function FaceLife.init()
	if not Config or Config.Enabled == false then
		return
	end
	local npcs: { [Model]: true } = {}
	local function trackNpc(c: Instance)
		if c:IsA("Model") and (c:GetAttribute("BotId") ~= nil or (c.Parent and c.Parent.Name == "Pedestrians")) then
			npcs[c] = true
		end
	end
	workspace.ChildAdded:Connect(function(c)
		trackNpc(c)
		if c:IsA("Folder") and c.Name == "Pedestrians" then
			c.ChildAdded:Connect(trackNpc)
		end
	end)
	for _, c in workspace:GetChildren() do
		trackNpc(c)
		if c:IsA("Folder") and c.Name == "Pedestrians" then
			c.ChildAdded:Connect(trackNpc)
			for _, p in c:GetChildren() do
				trackNpc(p)
			end
		end
	end

	-- Последним в стеке поз: после анимаций (в том числе мимики из анимаций) и тела.
	PoseStack.layer(50, function(dt)
		local camPos = workspace.CurrentCamera.CFrame.Position
		local now = os.clock()
		local function run(char: Model?)
			if not char or not char.Parent then
				return
			end
			local st = states[char]
			if not st or st.face.Parent == nil then
				st = build(char)
				states[char] = st :: any
				if not st then
					return
				end
			end
			update(char, st :: State, dt, camPos, now)
		end
		for _, p in Players:GetPlayers() do
			run(p.Character)
		end
		for npc in npcs do
			if npc.Parent then
				run(npc)
			else
				npcs[npc] = nil
			end
		end
		for char in states do
			if not char.Parent then
				states[char] = nil
			end
		end
	end)
end

return FaceLife
