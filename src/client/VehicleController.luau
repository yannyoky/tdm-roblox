-- Управление машиной и её HUD.
-- Газ/тормоз/руль приходят от VehicleSeat (W/S/A/D, стрелки, геймпад, джойстик на телефоне).
-- Клиент водителя сам выставляет моторы колёс и угол руля: физику машины считает его компьютер,
-- поэтому управление отзывчивое даже с пингом. Выйти из машины — прыжок.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local VehicleController = {}

local gui: ScreenGui
local panel: Frame
local speedLabel: TextLabel
local nameLabel: TextLabel
local hpFill: Frame
local hintLabel: TextLabel
local baseWarning: TextLabel

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function buildGui()
	gui = make("ScreenGui", { Name = "VehicleHud", ResetOnSpawn = false, IgnoreGuiInset = false }, player:WaitForChild("PlayerGui"))
	panel = make("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -110),
		Size = UDim2.fromOffset(200, 74),
		BackgroundColor3 = Color3.fromRGB(15, 15, 18),
		BackgroundTransparency = 0.35,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
	nameLabel = make("TextLabel", {
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, panel)
	speedLabel = make("TextLabel", {
		Position = UDim2.fromOffset(10, 20),
		Size = UDim2.new(1, -20, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 26,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "0 км/ч",
	}, panel)
	local hpBack = make("Frame", {
		Position = UDim2.new(0, 10, 1, -16),
		Size = UDim2.new(1, -20, 0, 6),
		BackgroundColor3 = Color3.fromRGB(60, 60, 60),
		BorderSizePixel = 0,
	}, panel)
	hpFill = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(90, 200, 90),
		BorderSizePixel = 0,
	}, hpBack)
	hintLabel = make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 1, 4),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "Прыжок — выйти",
	}, panel)
	baseWarning = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(420, 36),
		BackgroundColor3 = Color3.fromRGB(150, 20, 20),
		BackgroundTransparency = 0.2,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "Чужая база! Уходите, вы получаете урон",
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, baseWarning)
end

local function vehicleOf(seat: Instance?): Model?
	local model = seat and seat.Parent
	if model and model:IsA("Model") and model:GetAttribute("IsVehicle") then
		return model
	end
	return nil
end

-- Выставляем моторы и руль по вводу водителя.
local function drive(model: Model, seat: VehicleSeat)
	local root = model.PrimaryPart
	local driveFolder = model:FindFirstChild("Drive")
	if not root or not driveFolder or model:GetAttribute("Destroyed") then
		return
	end
	local maxSpeed = model:GetAttribute("MaxSpeed") or 60
	local reverse = model:GetAttribute("ReverseSpeed") or 20
	local torque = model:GetAttribute("Torque") or 8000
	local radius = model:GetAttribute("WheelRadius") or 1.5
	local maxSteer = model:GetAttribute("SteerAngle") or 30
	local driveSign = model:GetAttribute("DriveSign") or -1
	local steerSign = model:GetAttribute("SteerSign") or -1

	local throttle, steer = seat.ThrottleFloat, seat.SteerFloat
	local forward = root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector)

	local wheelSpeed, wheelTorque
	if throttle > 0.05 then
		if forward < -3 then
			wheelSpeed, wheelTorque = 0, torque * 2 -- тормозим перед сменой направления
		else
			wheelSpeed, wheelTorque = maxSpeed / radius * throttle, torque
		end
	elseif throttle < -0.05 then
		if forward > 3 then
			wheelSpeed, wheelTorque = 0, torque * 2
		else
			wheelSpeed, wheelTorque = -reverse / radius, torque
		end
	else
		wheelSpeed, wheelTorque = 0, torque * 0.08 -- накат с лёгким сопротивлением
	end

	-- На скорости руль поворачивается меньше, чтобы машина не переворачивалась.
	local speedFactor = math.clamp(math.abs(forward) / maxSpeed, 0, 1)
	local angle = steerSign * steer * maxSteer * (1 - 0.55 * speedFactor)

	for _, c in driveFolder:GetChildren() do
		if c:IsA("HingeConstraint") then
			if c.ActuatorType == Enum.ActuatorType.Motor then
				c.AngularVelocity = driveSign * wheelSpeed
				c.MotorMaxTorque = wheelTorque
			else
				c.TargetAngle = angle
			end
		end
	end
end

local sirenClock = 0
local function updateSirens(model: Model, dt: number)
	sirenClock += dt
	local phase = math.floor(sirenClock / 0.3) % 2 == 0
	for _, part in model:GetChildren() do
		local kind = part:GetAttribute("Siren")
		if kind then
			(part :: BasePart).Transparency = if (kind == "red") == phase then 0 else 0.7
		end
	end
end

local function step(dt: number)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local model = vehicleOf(seat)

	baseWarning.Visible = char ~= nil and char:GetAttribute("InEnemyBase") == true

	if not model then
		panel.Visible = false
		return
	end
	panel.Visible = true
	local root = model.PrimaryPart
	local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0
	-- 1 студ ≈ 0.28 м, поэтому студы/с примерно равны км/ч.
	speedLabel.Text = string.format("%d км/ч", math.floor(speed + 0.5))
	nameLabel.Text = model.Name
	local hp, maxHp = model:GetAttribute("Health") or 0, model:GetAttribute("MaxHealth") or 1
	local frac = math.clamp(hp / maxHp, 0, 1)
	hpFill.Size = UDim2.fromScale(frac, 1)
	hpFill.BackgroundColor3 = Color3.fromRGB(220, 60, 50):Lerp(Color3.fromRGB(90, 200, 90), frac)

	if seat:IsA("VehicleSeat") then
		drive(model, seat)
		updateSirens(model, dt)
		hintLabel.Text = "W/S — газ/тормоз, A/D — руль, прыжок — выйти"
	else
		hintLabel.Text = "Прыжок — выйти"
	end
end

function VehicleController.init()
	buildGui()
	-- Stepped идёт до расчёта физики: новые значения моторов применяются в этом же кадре.
	RunService.Stepped:Connect(function(_, dt)
		step(dt)
	end)
end

return VehicleController
