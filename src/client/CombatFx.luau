-- Боевые эффекты на экране: ослепление, ранение с таймером, броня,
-- и скрытие подсказки «Поднять» у раненых врагов.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local player = Players.LocalPlayer

local CombatFx = {}

local function make(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	return inst
end

local function myTeamKey(): string?
	if player.Neutral or not player.Team then
		return nil
	end
	return player.Team:GetAttribute("Key")
end

function CombatFx.init()
	local gui = make("ScreenGui", { Name = "CombatFx", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5 })

	-- Ослепление.
	local flash = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10,
	})
	flash.Parent = gui
	Net.get("Flash").OnClientEvent:Connect(function(intensity: number)
		intensity = math.clamp(intensity, 0, 1)
		flash.BackgroundTransparency = 1 - intensity
		TweenService:Create(flash, TweenInfo.new(0.5 + 2.5 * intensity, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
	end)

	-- Ранение.
	local downed = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(120, 0, 0),
		BackgroundTransparency = 0.7,
		Visible = false,
	})
	downed.Parent = gui
	local downedText = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.65),
		Size = UDim2.new(0, 420, 0, 60),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.4,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = "",
	})
	downedText.Parent = downed

	-- Броня.
	local armor = make("TextLabel", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -134),
		Size = UDim2.new(0, 220, 0, 30),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(140, 190, 255),
		TextStrokeTransparency = 0.5,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
	})
	armor.Parent = gui

	RunService.RenderStepped:Connect(function()
		local char = player.Character
		local isDowned = char ~= nil and char:GetAttribute("Downed") == true
		downed.Visible = isDowned
		if isDowned then
			local left = math.ceil(char:GetAttribute("BleedOut") or 0)
			downedText.Text = string.format("Вы ранены. Ждите союзника: %d с", left)
		end
		local points = char and char:GetAttribute("Armor") or 0
		armor.Visible = points > 0
		armor.Text = string.format("Броня %d", math.floor(points))
	end)

	-- Тряска камеры при получении урона (выключается в настройках).
	local PlayerSettings = require(script.Parent.PlayerSettings)
	local shake = 0
	local lastHealth: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any
	local function watchHumanoid(char: Model)
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		if not hum then
			return
		end
		lastHealth[hum] = hum.Health
		hum.HealthChanged:Connect(function(health)
			local prev = lastHealth[hum] or health
			lastHealth[hum] = health
			if health < prev and health > 0 and PlayerSettings.get("ScreenShake") then
				shake = math.min(1, shake + (prev - health) / 40)
			end
		end)
	end
	player.CharacterAdded:Connect(watchHumanoid)
	if player.Character then
		task.spawn(watchHumanoid, player.Character)
	end
	RunService:BindToRenderStep("DamageShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if shake <= 0 then
			return
		end
		local a = math.rad(1.5) * shake
		workspace.CurrentCamera.CFrame *= CFrame.Angles((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
		shake = math.max(0, shake - dt * 4)
	end)

	-- Подсказку «Поднять» видят только союзники раненого (Enabled меняем только у себя на клиенте).
	local function checkPrompt(inst: Instance)
		if inst:IsA("ProximityPrompt") and inst.Name == "RevivePrompt" then
			inst.Enabled = inst:GetAttribute("TeamKey") == myTeamKey()
		end
	end
	workspace.DescendantAdded:Connect(checkPrompt)
	for _, inst in workspace:GetDescendants() do
		checkPrompt(inst)
	end

	gui.Parent = player:WaitForChild("PlayerGui")
end

return CombatFx
