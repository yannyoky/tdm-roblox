-- Вид от первого лица. Включён по умолчанию, переключается клавишей V или в настройках.
-- В машине, после смерти (камера на убийце) и при выключенной настройке — вид от третьего лица.
-- От первого лица руки с оружием рисует Viewmodel, в центре экрана прицел.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local Menus = require(script.Parent.Menus)
local PlayerSettings = require(script.Parent.PlayerSettings)

local player = Players.LocalPlayer

local CameraView = {}

local THIRD_PERSON_ZOOM = 10

local function wantFirstPerson(): boolean
	if not PlayerSettings.get("FirstPerson") then
		return false
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.SeatPart then
		return false
	end
	-- Камера смотрит не на себя (экран смерти, наблюдение) — свободный вид.
	return workspace.CurrentCamera.CameraSubject == hum
end

function CameraView.init()
	local gui = Ui.make("ScreenGui", { Name = "Crosshair", ResetOnSpawn = false, DisplayOrder = 1, IgnoreGuiInset = true })
	local cross = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	for _, spec in { { 0.5, 0, 2, 6 }, { 0.5, 1, 2, 6 }, { 0, 0.5, 6, 2 }, { 1, 0.5, 6, 2 } } do
		Ui.make("Frame", {
			AnchorPoint = Vector2.new(spec[1], spec[2]),
			Position = UDim2.fromScale(spec[1], spec[2]),
			Size = UDim2.fromOffset(spec[3], spec[4]),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = cross,
		})
	end
	Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = cross,
	})
	gui.Parent = player:WaitForChild("PlayerGui")

	local firstPerson: boolean? = nil

	local function apply(on: boolean)
		if firstPerson == on then
			return
		end
		firstPerson = on
		if on then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		else
			player.CameraMode = Enum.CameraMode.Classic
			-- Отодвинуть камеру за спину: на миг поднимаем минимальное приближение.
			player.CameraMinZoomDistance = THIRD_PERSON_ZOOM
			task.delay(0.1, function()
				player.CameraMinZoomDistance = 0.5
			end)
		end
	end

	-- Режим камеры обновляем после того, как отработала камера Roblox.
	RunService:BindToRenderStep("FirstPersonArms", Enum.RenderPriority.Camera.Value + 2, function()
		local on = wantFirstPerson()
		apply(on)
		local menuOpen = Menus.isOpen()
		cross.Visible = on and not menuOpen
		UserInputService.MouseIconEnabled = not on or menuOpen
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.V then
			PlayerSettings.set("FirstPerson", not PlayerSettings.get("FirstPerson"))
		end
	end)
end

return CameraView
