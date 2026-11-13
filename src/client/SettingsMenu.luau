-- Окно настроек: чувствительность, поле зрения, тряска экрана, подсказки клавиш, графика.
-- Открывается из главного меню и кнопкой на панели.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Settings)
local Ui = require(script.Parent.Ui)
local Menus = require(script.Parent.Menus)
local PlayerSettings = require(script.Parent.PlayerSettings)

local C = Ui.Colors

local SettingsMenu = {}

local function formatValue(def, value): string
	if def.Step >= 1 then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%.2f", value)
end

function SettingsMenu.init()
	local window, content, close = Ui.window("Настройки", UDim2.new(0, 420, 0, 480))
	close.Activated:Connect(Menus.close)

	local refreshers: { [string]: () -> () } = {}

	for i, key in Config.Order do
		local def = Config.List[key]
		local row = Ui.make("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, if def.Type == "Number" then 60 else 40),
			BackgroundColor3 = C.Card,
			Parent = content,
		}, { Ui.corner(6) })
		Ui.label({ Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -120, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham, Text = def.Name, Parent = row })

		if def.Type == "Toggle" then
			local b = Ui.button("", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 90, 0, 28), Parent = row })
			b.Activated:Connect(function()
				PlayerSettings.set(key, not PlayerSettings.get(key))
			end)
			refreshers[key] = function()
				local on = PlayerSettings.get(key)
				b.Text = if on then "Вкл" else "Выкл"
				b.BackgroundColor3 = if on then C.Good else C.Button
			end
		else
			local valueLabel = Ui.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.new(0, 90, 0, 22), TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
			local track = Ui.make("Frame", { Position = UDim2.new(0, 10, 0, 38), Size = UDim2.new(1, -20, 0, 10), BackgroundColor3 = Color3.fromRGB(60, 60, 70), Parent = row }, { Ui.corner(4) })
			local fill = Ui.make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, Parent = track }, { Ui.corner(4) })
			local knob = Ui.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C.White, Parent = track }, { Ui.corner(9) })
			local hit = Ui.make("TextButton", { Position = UDim2.new(0, 0, 0, -10), Size = UDim2.new(1, 0, 1, 20), BackgroundTransparency = 1, Text = "", Parent = track })

			refreshers[key] = function()
				local v = PlayerSettings.get(key)
				local f = (v - def.Min) / (def.Max - def.Min)
				fill.Size = UDim2.fromScale(f, 1)
				knob.Position = UDim2.fromScale(f, 0.5)
				valueLabel.Text = formatValue(def, v)
			end

			local dragging = false
			local function setFromX(x: number)
				local f = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
				PlayerSettings.set(key, def.Min + f * (def.Max - def.Min))
			end
			hit.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					setFromX(input.Position.X)
				end
			end)
			UserInputService.InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					setFromX(input.Position.X)
				end
			end)
			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = false
				end
			end)
		end
	end

	local resetButton = Ui.button("Сбросить", { LayoutOrder = 100, Size = UDim2.new(0.5, 0, 0, 34), Parent = content })
	resetButton.Activated:Connect(function()
		for key, def in Config.List do
			PlayerSettings.set(key, def.Default)
		end
	end)

	-- Подсказка по управлению.
	Ui.label({
		LayoutOrder = 101,
		Size = UDim2.new(1, 0, 0, 120),
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Gotham,
		TextColor3 = C.Grey,
		Text = "Управление: ЛКМ — огонь, ПКМ — прицел, R — перезарядка, 1–9 — оружие, Q — прошлое оружие, G — граната, "
			.. "Shift — бег, C — присесть, Пробел у препятствия — перелезть, E — поднять союзника или сесть за руль, F — пассажиром, T — перевернуть машину, "
			.. "Tab — таблица игроков, M — меню, I — инвентарь, U — скины, J — прогресс, B — магазин.",
		Parent = content,
	})

	local function refreshAll()
		for _, fn in refreshers do
			fn()
		end
	end
	PlayerSettings.onChanged(function(key)
		if refreshers[key] then
			refreshers[key]()
		end
	end)
	refreshAll()

	Menus.register("Settings", { title = "Настройки", order = 6, panel = window, onOpen = refreshAll })
end

return SettingsMenu
