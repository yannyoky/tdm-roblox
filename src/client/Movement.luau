-- Передвижение пешком: бег с выносливостью и паркур.
--   Бег: Shift (геймпад: нажатие левого стика; телефон: кнопка «Бег», включается/выключается).
--   Паркур работает от обычного прыжка перед препятствием:
--     * низкое (забор, ящик, прилавок) — перемахнуть через него или запрыгнуть сверху;
--     * высокое до ~10 студов (гараж, контейнер, стена) — подтянуться и залезть;
--     * в прыжке у края крыши — ухватиться и подтянуться.
--   Лестницы (решётчатые фермы на стенах зданий) работают сами: подойти и идти вперёд.
-- Персонажем управляет клиент, поэтому движение сразу видно всем без лишней сети.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Movement"))
local SPRINT = Config.Sprint
local PARKOUR = Config.Parkour

local player = Players.LocalPlayer

local Movement = {}

local stamina = SPRINT.StaminaMax
local wantSprint = false
local exhausted = false
local lastSprintTime = 0
local busy = false
local lastParkour = 0
local baseSpeed = 16

local staminaFill: Frame
local staminaBar: Frame

local function getParts()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return nil
	end
	return char, hum, root
end

------------------------------------------------------------------------
-- Бег

local function onSprintAction(_, inputState: Enum.UserInputState, input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch then
		if inputState == Enum.UserInputState.Begin then
			wantSprint = not wantSprint
		end
	else
		if inputState == Enum.UserInputState.Begin then
			wantSprint = true
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			wantSprint = false
		end
	end
	return Enum.ContextActionResult.Pass
end

local function updateSprint(dt: number)
	local char, hum = getParts()
	if not char then
		return
	end
	local moving = hum.MoveDirection.Magnitude > 0.1
	local canSprint = wantSprint and moving and not exhausted and not busy and hum.SeatPart == nil
		and hum:GetState() ~= Enum.HumanoidStateType.Climbing and not char:GetAttribute("InLobby")

	if canSprint then
		stamina = math.max(0, stamina - SPRINT.Drain * dt)
		lastSprintTime = os.clock()
		if stamina <= 0 then
			exhausted = true
		end
	elseif os.clock() - lastSprintTime > SPRINT.RegenDelay then
		stamina = math.min(SPRINT.StaminaMax, stamina + SPRINT.Regen * dt)
	end
	if exhausted and stamina >= SPRINT.MinToStart then
		exhausted = false
	end

	local sprintSpeed = baseSpeed * SPRINT.Multiplier
	if canSprint then
		hum.WalkSpeed = sprintSpeed
	elseif hum.WalkSpeed == sprintSpeed then
		hum.WalkSpeed = baseSpeed
	end
	char:SetAttribute("Stamina", math.floor(stamina))

	local frac = stamina / SPRINT.StaminaMax
	staminaFill.Size = UDim2.fromScale(frac, 1)
	staminaFill.BackgroundColor3 = if exhausted then Color3.fromRGB(200, 80, 60) else Color3.fromRGB(230, 200, 80)
	staminaBar.Visible = frac < 0.999 and hum.SeatPart == nil
end

------------------------------------------------------------------------
-- Паркур

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.RespectCanCollide = true

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

-- Свободно ли место для персонажа, стоящего ногами в точке feet.
local function spaceFree(feet: Vector3): boolean
	local hits = workspace:GetPartBoundsInBox(CFrame.new(feet + Vector3.new(0, 2.9, 0)), Vector3.new(1.6, 5, 1.6), overlapParams)
	return #hits == 0
end

-- Проводит корень персонажа по ломаной points за duration секунд.
local function runPath(hum: Humanoid, root: BasePart, points: { Vector3 }, duration: number, face: Vector3)
	busy = true
	lastParkour = os.clock()
	local attachment = root:FindFirstChild("RootAttachment") :: Attachment?
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "ParkourAttachment"
		attachment.Parent = root
	end

	local mover = Instance.new("LinearVelocity")
	mover.Name = "ParkourMover"
	mover.Attachment0 = attachment
	mover.MaxForce = math.huge
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VectorVelocity = Vector3.zero
	mover.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "ParkourAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.CFrame = CFrame.lookAt(Vector3.zero, face)
	align.Parent = root

	local autoRotate = hum.AutoRotate
	hum.AutoRotate = false
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	-- Длины отрезков, чтобы скорость была равномерной.
	local path = { root.Position }
	for _, p in points do
		table.insert(path, p)
	end
	local lengths, total = {}, 0
	for i = 2, #path do
		lengths[i] = (path[i] - path[i - 1]).Magnitude
		total += lengths[i]
	end
	local function pointAt(t: number): Vector3
		local dist = math.clamp(t / duration, 0, 1) * total
		for i = 2, #path do
			if dist <= lengths[i] or i == #path then
				local a = if lengths[i] > 0 then math.clamp(dist / lengths[i], 0, 1) else 1
				return path[i - 1]:Lerp(path[i], a)
			end
			dist -= lengths[i]
		end
		return path[#path]
	end

	local t = 0
	while t < duration + 0.15 do
		local dt = RunService.Heartbeat:Wait()
		if hum.Health <= 0 or root.Parent == nil or hum.SeatPart then
			break
		end
		t += dt
		local target = pointAt(t + dt)
		local v = (target - root.Position) / math.max(dt, 1 / 120)
		if v.Magnitude > 90 then
			v = v.Unit * 90
		end
		mover.VectorVelocity = v
	end

	mover:Destroy()
	align:Destroy()
	if attachment.Name == "ParkourAttachment" then
		attachment:Destroy()
	end
	hum.AutoRotate = autoRotate
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	if root.Parent then
		root.AssemblyLinearVelocity = face * math.min(hum.WalkSpeed, 20) * 0.6
	end
	busy = false
end

local function tryParkour()
	if busy or os.clock() - lastParkour < PARKOUR.Cooldown then
		return
	end
	local char, hum, root = getParts()
	if not char or hum.SeatPart or char:GetAttribute("InLobby") then
		return
	end
	local state = hum:GetState()
	if state == Enum.HumanoidStateType.Climbing or state == Enum.HumanoidStateType.Swimming then
		return
	end

	rayParams.FilterDescendantsInstances = { char }
	overlapParams.FilterDescendantsInstances = { char }

	local rootOffset = hum.HipHeight + root.Size.Y / 2
	local feetY = root.Position.Y - rootOffset
	local dir = if hum.MoveDirection.Magnitude > 0.1 then flat(hum.MoveDirection) else flat(root.CFrame.LookVector)
	local reach = PARKOUR.ReachDistance + root.Size.X / 2

	-- Ищем стену перед собой на нескольких высотах (в прыжке колени могут быть уже выше забора).
	local wall: RaycastResult? = nil
	for _, height in { 0.8, 2.2, 3.6, 5.0 } do
		local origin = Vector3.new(root.Position.X, feetY + height, root.Position.Z)
		local r = workspace:Raycast(origin, dir * reach, rayParams)
		if r and math.abs(r.Normal.Y) < 0.35 then
			wall = r
			break
		end
	end
	if not wall then
		return
	end
	local face = flat(-wall.Normal)

	-- Верх препятствия: луч сверху вниз чуть за краем стены.
	local probe = wall.Position + face * 0.7
	local fromY = feetY + PARKOUR.ClimbMaxHeight + 1.5
	local top = workspace:Raycast(Vector3.new(probe.X, fromY, probe.Z), Vector3.new(0, -(fromY - feetY - 0.5), 0), rayParams)
	if not top or top.Normal.Y < 0.7 then
		return
	end
	local ledgeY = top.Position.Y
	local height = ledgeY - feetY
	if height < PARKOUR.MinHeight or height > PARKOUR.ClimbMaxHeight then
		return
	end
	local standFeet = Vector3.new(top.Position.X, ledgeY, top.Position.Z) + face * 1.2
	local up = Vector3.new(0, rootOffset + 0.4, 0)

	-- Низкое препятствие: пробуем перемахнуть насквозь.
	if height <= PARKOUR.VaultMaxHeight then
		local k = 0.6
		while k <= PARKOUR.VaultMaxThickness + 0.5 do
			local p = wall.Position + face * k
			local r = workspace:Raycast(Vector3.new(p.X, ledgeY + 0.5, p.Z), Vector3.new(0, -(height + 3), 0), rayParams)
			if r and r.Position.Y < ledgeY - 1.2 then
				-- За препятствием обрыв: приземляемся на ту сторону.
				local land = Vector3.new(p.X, r.Position.Y, p.Z) + face * 1.8
				if spaceFree(land) then
					local over = wall.Position + face * (k / 2)
					runPath(hum, root, {
						Vector3.new(root.Position.X, ledgeY, root.Position.Z) + up,
						Vector3.new(over.X, ledgeY, over.Z) + up,
						land + Vector3.new(0, rootOffset, 0),
					}, PARKOUR.VaultTime, face)
					return
				end
				break
			end
			if not r then
				break
			end
			k += 0.5
		end
	end

	-- Подтягивание / запрыгивание наверх.
	if not spaceFree(standFeet) then
		return
	end
	local climbing = height > PARKOUR.VaultMaxHeight
	if climbing then
		if stamina < PARKOUR.ClimbStaminaCost then
			return
		end
		stamina -= PARKOUR.ClimbStaminaCost
		lastSprintTime = os.clock()
	end
	runPath(hum, root, {
		Vector3.new(root.Position.X, ledgeY, root.Position.Z) + up,
		standFeet + Vector3.new(0, rootOffset, 0),
	}, if climbing then PARKOUR.ClimbTime else PARKOUR.VaultTime, face)
end

------------------------------------------------------------------------

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MovementHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	staminaBar = Instance.new("Frame")
	staminaBar.AnchorPoint = Vector2.new(0.5, 1)
	staminaBar.Position = UDim2.new(0.5, 0, 1, -96)
	staminaBar.Size = UDim2.fromOffset(180, 5)
	staminaBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	staminaBar.BackgroundTransparency = 0.3
	staminaBar.BorderSizePixel = 0
	staminaBar.Visible = false
	staminaBar.Parent = gui

	staminaFill = Instance.new("Frame")
	staminaFill.Size = UDim2.fromScale(1, 1)
	staminaFill.BorderSizePixel = 0
	staminaFill.Parent = staminaBar
end

local function onCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	baseSpeed = hum.WalkSpeed
	stamina = SPRINT.StaminaMax
	exhausted = false
	busy = false
end

function Movement.init()
	buildGui()
	ContextActionService:BindAction("Sprint", onSprintAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("Sprint", "Бег")
	ContextActionService:SetPosition("Sprint", UDim2.new(1, -170, 1, -150))

	UserInputService.JumpRequest:Connect(function()
		task.spawn(tryParkour)
	end)
	RunService.Heartbeat:Connect(updateSprint)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return Movement
