-- Главное меню (клавиша M): открывается при входе в игру.
-- Выбор стороны, кнопка «Играть», переходы в скины, инвентарь, прогресс, магазин и настройки.
-- Пока игрок не нажал «Играть», он стоит в лобби и не попадает в матч.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Teams = require(Shared.Config.Teams)
local Ui = require(script.Parent.Ui)
local Menus = require(script.Parent.Menus)

local player = Players.LocalPlayer
local C = Ui.Colors

local MainMenu = {}

function MainMenu.init()
	local state = ReplicatedStorage:WaitForChild("MatchState") :: Folder
	local played = false
	local preferred = "Any"

	local root = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 8, 12),
		BackgroundTransparency = 0.25,
		Active = true, -- не пропускать клики к интерфейсу под меню
	})
	local column = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.9, 0),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Ui.make("UISizeConstraint", { MaxSize = Vector2.new(460, 620) }),
		Ui.make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})

	local title = Ui.make("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Parent = column })
	Ui.label({ Size = UDim2.new(0.42, 0, 1, 0), Text = "БАНДА", TextColor3 = Teams.List[Teams.Order[1]].Color, TextXAlignment = Enum.TextXAlignment.Right, Parent = title })
	Ui.label({ Position = UDim2.new(0.42, 0, 0.2, 0), Size = UDim2.new(0.16, 0, 0.6, 0), Text = "vs", Font = Enum.Font.Gotham, Parent = title })
	Ui.label({ Position = UDim2.new(0.58, 0, 0, 0), Size = UDim2.new(0.42, 0, 1, 0), Text = "СИЛОВИКИ", TextColor3 = Teams.List[Teams.Order[2]].Color, TextXAlignment = Enum.TextXAlignment.Left, Parent = title })

	local status = Ui.label({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 22), Font = Enum.Font.Gotham, TextColor3 = C.Grey, Parent = column })
	local profile = Ui.label({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 22), Font = Enum.Font.Gotham, Parent = column })

	-- Выбор стороны.
	Ui.label({ LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 22), Text = "За кого играть", Parent = column })
	local teamRow = Ui.make("Frame", { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = column }, {
		Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local teamButtons: { [string]: TextButton } = {}
	local options = { Teams.Order[1], "Any", Teams.Order[2] }
	for i, key in options do
		local b = Ui.button(if key == "Any" then "Любая" else Teams.List[key].Name, {
			LayoutOrder = i,
			Size = UDim2.new(1 / 3, -6, 1, 0),
			Parent = teamRow,
		})
		b.Activated:Connect(function()
			preferred = key
			for k, other in teamButtons do
				local color = if k == "Any" then C.Accent else Teams.List[k].Color
				other.BackgroundColor3 = if k == preferred then color else C.Button
			end
			if played then
				Net.get("Play"):FireServer(preferred) -- сменить сторону со следующего матча
			end
		end)
		teamButtons[key] = b
	end
	teamButtons.Any.BackgroundColor3 = C.Accent
	local teamHint = Ui.label({
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 18),
		Font = Enum.Font.Gotham,
		TextColor3 = C.Grey,
		Text = "Если выбранная сторона больше другой, игра поставит в меньшую",
		Parent = column,
	})

	local playButton = Ui.button("ИГРАТЬ", { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = C.Good, Parent = column })

	local grid = Ui.make("Frame", { LayoutOrder = 8, Size = UDim2.new(1, 0, 0, 128), BackgroundTransparency = 1, Parent = column }, {
		Ui.make("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 38), CellPadding = UDim2.new(0, 10, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local links = {
		{ "Скины", "Skins" },
		{ "Инвентарь", "Inventory" },
		{ "Прогресс", "Progress" },
		{ "Магазин", "Shop" },
		{ "Настройки", "Settings" },
	}
	for i, link in links do
		local b = Ui.button(link[1], { LayoutOrder = i, Parent = grid })
		b.Activated:Connect(function()
			Menus.open(link[2])
		end)
	end

	playButton.Activated:Connect(function()
		if not played then
			played = true
			Net.get("Play"):FireServer(preferred)
		end
		Menus.close()
	end)

	local function refresh()
		playButton.Text = if played then "ПРОДОЛЖИТЬ" else "ИГРАТЬ"
		teamHint.Text = if played
			then "Смена стороны действует со следующего матча"
			else "Если выбранная сторона больше другой, игра поставит в меньшую"
		local phase = state:GetAttribute("Phase") or "Lobby"
		if phase == "Match" then
			status.Text = string.format("Идёт матч: %s, %s", state:GetAttribute("ModeName") or "", Ui.formatTime(state:GetAttribute("TimeLeft") or 0))
		elseif phase == "Results" then
			status.Text = "Матч закончился, скоро новый"
		else
			status.Text = state:GetAttribute("Message") or "Лобби"
		end
		local level = player:GetAttribute("Level")
		profile.Text = if level
			then string.format("Ур. %d  •  %d монет  •  %s", level, player:GetAttribute("Coins") or 0, player:GetAttribute("Division") or "Бронза")
			else "Загрузка профиля..."
	end
	state.AttributeChanged:Connect(function()
		if root.Visible then
			refresh()
		end
	end)
	player.AttributeChanged:Connect(function()
		if root.Visible then
			refresh()
		end
	end)

	Menus.register("Main", { title = "Меню", key = Enum.KeyCode.M, order = 1, panel = root, onOpen = refresh })

	-- Пока игрок не нажал «Играть», после любого окна возвращаемся в главное меню.
	Menus.onChanged(function(name)
		Menus.setBarVisible(played and name ~= "Main")
		if name == nil and not played then
			task.defer(Menus.open, "Main")
		end
	end)
	Menus.open("Main")
end

return MainMenu
