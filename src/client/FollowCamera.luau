-- Камера от третьего лица в стиле GTA: включается, когда выключен вид от первого лица (V) и в машине.
--   Пешком:
--     * камера через правое плечо, мышь вращает её всегда (без зажатой правой кнопки), прицел в центре;
--     * плавно догоняет персонажа: по горизонтали быстрее, по вертикали мягче (прыжки и ступеньки
--       не дёргают кадр), лёгкое «живое» покачивание в покое;
--     * правая кнопка с оружием — камера ближе к плечу, персонаж разворачивается к прицелу;
--     * персонаж плавно поворачивается по ходу движения (а не мгновенно, как в Roblox по умолчанию);
--     * колесо мыши — дальше/ближе; стены не пропускают камеру (она мягко подъезжает к персонажу).
--   В машине:
--     * камера сзади и выше, дальше на скорости; в поворотах отстаёт и сама возвращается за машину,
--       если мышь не трогали ~1 с.
-- Тряска (CombatFx) и другие поправки камеры сохраняются: их поворот вливается в углы камеры.
-- Настройки — Config/Character (Camera).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Character).Camera
local PlayerSettings = require(script.Parent.PlayerSettings)
local Menus = require(script.Parent.Menus)

local player = Players.LocalPlayer

local FollowCamera = {}

local active = false
local yaw, pitch = 0, math.rad(-12)
local focus: Vector3? = nil
local dist = Config.Distance
local zoom = Config.Distance
local shoulder = Config.Shoulder
local blocked = math.huge -- расстояние до стены (сглажено)
local lastCf: CFrame? = nil
local lastLookInput = 0
local autoRotateOff: Humanoid? = nil
local stick = Vector2.zero
local touches: { [InputObject]: boolean } = {}
local lastFire = 0
local landKick = 0
local prevVelY = 0

local MOUSE_SPEED = math.rad(0.4) -- радиан на пиксель (чувствительность — в настройках)
local TOUCH_SPEED = math.rad(0.35)
local STICK_YAW, STICK_PITCH = 3.6, 2.4 -- радиан в секунду на полном отклонении стика

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.RespectCanCollide = true

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function damp(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function vehicleOf(hum: Humanoid): Model?
	local seat = hum.SeatPart
	local m = seat and seat.Parent
	if m and m:IsA("Model") and m:GetAttribute("IsVehicle") then
		return m
	end
	return nil
end

local function armed(char: Model): boolean
	local tool = char:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("WeaponId") ~= nil
end

local function wanted(): (boolean, Model?, Humanoid?)
	if not Config.Enabled then
		return false
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.Health <= 0 or not char:FindFirstChild("HumanoidRootPart") then
		return false
	end
	if workspace.CurrentCamera.CameraSubject ~= hum then
		return false -- экран смерти, наблюдение: камерой управляет Roblox
	end
	if PlayerSettings.get("FirstPerson") and not hum.SeatPart then
		return false
	end
	return true, char, hum
end

local function restoreRotate()
	if autoRotateOff and autoRotateOff.Parent then
		autoRotateOff.AutoRotate = true
	end
	autoRotateOff = nil
end

local function activate(cam: Camera)
	active = true
	local look = cam.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), math.rad(Config.MinPitch), math.rad(Config.MaxPitch))
	focus = nil
	lastCf = nil
	blocked = math.huge
	cam.CameraType = Enum.CameraType.Scriptable
end

local function deactivate(cam: Camera)
	active = false
	restoreRotate()
	lastCf = nil
	if cam.CameraType == Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Custom
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

-- Персонаж плавно поворачивается по ходу движения (или к прицелу, когда целится/стреляет).
local function turnCharacter(hum: Humanoid, root: BasePart, dt: number, faceCam: boolean)
	if root:FindFirstChild("ParkourAlign") then
		-- перелезание (Movement) само держит разворот
		return
	end
	local state = hum:GetState()
	local free = state == Enum.HumanoidStateType.Swimming or state == Enum.HumanoidStateType.Climbing
	if hum.SeatPart or free or hum.PlatformStand then
		restoreRotate()
		return
	end
	if autoRotateOff ~= hum then
		restoreRotate()
		hum.AutoRotate = false
		autoRotateOff = hum
	end
	local look = root.CFrame.LookVector
	local cur = math.atan2(-look.X, -look.Z)
	local target = cur
	local move = hum.MoveDirection
	if faceCam then
		target = yaw
	elseif move.Magnitude > 0.1 then
		target = math.atan2(-move.X, -move.Z)
	end
	local rate = if faceCam then Config.AimTurnRate else Config.TurnRate
	cur = wrap(cur + wrap(target - cur) * damp(rate, dt))
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, cur, 0)
end

local function readInput(dt: number, menuOpen: boolean): boolean
	local moved = false
	if not menuOpen then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local d = UserInputService:GetMouseDelta()
		if d.Magnitude > 0 then
			yaw -= d.X * MOUSE_SPEED
			pitch -= d.Y * MOUSE_SPEED
			moved = true
		end
		if stick.Magnitude > 0.15 then
			yaw -= stick.X * STICK_YAW * dt
			pitch += stick.Y * STICK_PITCH * dt
			moved = true
		end
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	pitch = math.clamp(pitch, math.rad(Config.MinPitch), math.rad(Config.MaxPitch))
	return moved
end

-- Насколько можно отъехать от точки from в сторону to, не заходя в стену.
local function clearDistance(from: Vector3, to: Vector3): number
	local dir = to - from
	local len = dir.Magnitude
	if len < 1e-3 then
		return len
	end
	local hit = workspace:Spherecast(from, Config.CollisionRadius, dir, castParams)
	if hit then
		return math.max(0, hit.Distance - 0.1)
	end
	return len
end

local function step(dt: number)
	local cam = workspace.CurrentCamera
	local want, char, hum = wanted()
	if not want then
		if active then
			deactivate(cam)
		end
		return
	end
	if not active then
		activate(cam)
	end
	char = char :: Model
	hum = hum :: Humanoid
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
	-- Посадка и другие системы могут вернуть камеру Roblox — держим свою.
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	-- После вида от первого лица Roblox оставляет тело невидимым (LocalTransparencyModifier = 1),
	-- а при нашей камере его никто не возвращает.
	for _, d in char:GetDescendants() do
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.LocalTransparencyModifier ~= 0 and d.Name ~= "HumanoidRootPart" then
			d.LocalTransparencyModifier = 0
		end
	end
	dt = math.clamp(dt, 1 / 240, 0.1)
	local now = os.clock()

	-- Что поменяли в камере после нас (тряска, отдача) — вливаем в свои углы.
	if lastCf and cam.CFrame ~= lastCf then
		local d = lastCf.Rotation:Inverse() * cam.CFrame.Rotation
		local rx, ry = d:ToEulerAnglesYXZ()
		pitch += rx
		yaw += ry
	end

	local menuOpen = Menus.isOpen()
	if readInput(dt, menuOpen) then
		lastLookInput = now
	end

	local vehicle = vehicleOf(hum)
	local vroot = vehicle and vehicle.PrimaryPart
	local isArmed = armed(char)
	local aiming = not vehicle
		and isArmed
		and not menuOpen
		and (PlayerSettings.isAiming() or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
	if isArmed and not menuOpen and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		lastFire = now
	end
	local faceCam = aiming or (isArmed and now - lastFire < 1.0)

	if not vehicle then
		turnCharacter(hum, root, dt, faceCam)
	else
		restoreRotate()
	end

	-- Точка, за которой следит камера.
	local target: Vector3
	local wantDist: number
	local wantShoulder: number
	local rateXZ, rateY
	if vehicle and vroot then
		local len = vehicle:GetAttribute("Length") or 14
		local vel = vroot.AssemblyLinearVelocity
		local speed = vel.Magnitude
		target = vroot.Position + Vector3.new(0, Config.CarHeight, 0)
		wantDist = len * 0.5 * Config.CarDistance + 6 + math.min(speed, 120) * 0.04
		wantShoulder = 0
		rateXZ, rateY = 22, 10
		-- Не трогали мышь — камера сама уходит за машину (по направлению движения) и к обычному наклону.
		if now - lastLookInput > Config.CarRecenterDelay then
			local look = vroot.CFrame.LookVector
			local flatVel = Vector3.new(vel.X, 0, vel.Z)
			local dir = if flatVel.Magnitude > 8 and flatVel.Unit:Dot(look) > -0.2 then flatVel.Unit else look
			local targetYaw = math.atan2(-dir.X, -dir.Z)
			local k = damp(Config.CarRecenterRate * math.clamp(speed / 20, 0.3, 1.5), dt)
			yaw = wrap(yaw + wrap(targetYaw - yaw) * k)
			pitch += (math.rad(Config.CarPitch) - pitch) * k
		end
	else
		target = root.Position + Vector3.new(0, Config.Height, 0)
		local vel = root.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		wantDist = if aiming then Config.AimDistance else zoom + math.clamp((speed - 16) / 8, 0, 1) * 1.2
		wantShoulder = if aiming then Config.AimShoulder else Config.Shoulder
		rateXZ, rateY = Config.FollowRate, Config.FollowRateY
		-- Приземление: камера чуть «проседает» и пружинит обратно.
		if prevVelY < -35 and vel.Y > -5 then
			landKick = math.min(0.6, -prevVelY / 120)
		end
		prevVelY = vel.Y
	end
	landKick = math.max(0, landKick - dt * 2.2)

	-- Мягкое следование (по вертикали медленнее). После телепорта — сразу на место.
	local f = focus
	if not f or (f - target).Magnitude > 25 then
		f = target
	else
		local kx, ky = damp(rateXZ, dt), damp(rateY, dt)
		f = Vector3.new(f.X + (target.X - f.X) * kx, f.Y + (target.Y - f.Y) * ky, f.Z + (target.Z - f.Z) * kx)
	end
	focus = f
	local fp = (f :: Vector3) - Vector3.new(0, landKick, 0)

	dist += (wantDist - dist) * damp(Config.ZoomRate, dt)
	shoulder += (wantShoulder - shoulder) * damp(Config.ZoomRate, dt)

	-- Лёгкое покачивание «из рук» (только пешком и если включена тряска экрана).
	local swayX, swayY = 0, 0
	if not vehicle and Config.Sway > 0 and PlayerSettings.get("ScreenShake") ~= false then
		local t = now * 0.6
		swayX = math.noise(t, 3.1) * math.rad(Config.Sway)
		swayY = math.noise(5.7, t) * math.rad(Config.Sway)
	end
	local rot = CFrame.fromEulerAnglesYXZ(pitch + swayX, yaw + swayY, 0)

	-- Столкновения: сначала до плеча, потом от плеча назад.
	castParams.FilterDescendantsInstances = if vehicle then { char, vehicle } else { char }
	local side = rot.RightVector * shoulder
	local sideLen = clearDistance(fp, fp + side)
	local pivot = fp + (if shoulder > 1e-3 then side.Unit * sideLen else Vector3.zero)
	local back = rot.LookVector * -dist
	local free = clearDistance(pivot, pivot + back)
	-- Стена ближе — камера сразу подъезжает; стена ушла — отъезжает плавно.
	if free < blocked then
		blocked = free
	else
		blocked += (free - blocked) * damp(4, dt)
	end
	local d = math.min(dist, blocked)
	local pos = pivot + rot.LookVector * -d

	local cf = CFrame.new(pos) * rot
	cam.CFrame = cf
	cam.Focus = CFrame.new(fp)
	lastCf = cf
end

function FollowCamera.isActive(): boolean
	return active
end

function FollowCamera.init()
	if not Config or Config.Enabled == false then
		return
	end
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			if not processed and active and not Menus.isOpen() then
				zoom = math.clamp(zoom - input.Position.Z * 1.5, Config.MinDistance, Config.MaxDistance)
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.UserInputType == Enum.UserInputType.Touch and touches[input] and active then
			yaw -= input.Delta.X * TOUCH_SPEED
			pitch -= input.Delta.Y * TOUCH_SPEED
			lastLookInput = os.clock()
		end
	end)
	-- Касание правой части экрана (не по кнопкам) вращает камеру.
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.Touch and not processed then
			local vp = workspace.CurrentCamera.ViewportSize
			if input.Position.X > vp.X * 0.4 then
				touches[input] = true
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		touches[input] = nil
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.zero
		end
	end)
	-- До камеры Roblox (200) и тряски (CombatFx, 201): тряска ложится поверх нашего кадра.
	RunService:BindToRenderStep("GtaFollowCamera", Enum.RenderPriority.Camera.Value - 1, step)
	-- Модуль камеры Roblox может вернуть мышь в обычный режим — после него закрепляем снова.
	RunService:BindToRenderStep("GtaFollowCameraMouse", Enum.RenderPriority.Camera.Value + 3, function()
		if active and not Menus.isOpen() then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
	end)
end

return FollowCamera
