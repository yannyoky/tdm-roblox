-- Главное меню (клавиша M): открывается при входе в игру.
-- До «Играть» за меню идёт пролёт камеры над картой (client/MenuCamera.luau), после «Играть»
-- камера опускается в штаб стороны, где игрок ждёт матч и голосует за режим кругами на полу.
--
-- Управление: мышь, клавиатура (↑↓ или W/S — выбор, ←→ или A/D — сторона, Enter/Пробел — выбрать)
-- и геймпад (крестовина, A).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Teams = require(Shared.Config.Teams)
local Ui = require(script.Parent.Ui)
local Menus = require(script.Parent.Menus)
local MenuCamera = require(script.Parent.MenuCamera)

local player = Players.LocalPlayer
local C = Ui.Colors

local MainMenu = {}

local NAV_ACTION = "MainMenuNav"
local TEAM_A, TEAM_B = Teams.Order[1], Teams.Order[2]
local SIDES = { TEAM_A, "Any", TEAM_B }

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

type Item = {
	button: TextButton,
	text: TextLabel,
	value: TextLabel?,
	activate: () -> (),
	left: (() -> ())?,
	right: (() -> ())?,
}

function MainMenu.init()
	local state = ReplicatedStorage:WaitForChild("MatchState") :: Folder
	local played = false
	local preferred = "Any"

	local root = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 8, 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true, -- не пропускать клики к интерфейсу под меню
	})
	-- Затемнение слева, чтобы текст читался на фоне города.
	Ui.make("Frame", {
		Size = UDim2.fromScale(0.6, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = root,
	}, {
		Ui.make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.55, 0.5),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	local column = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 64, 0.5, 0),
		Size = UDim2.new(0.42, 0, 0.9, 0),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Ui.make("UISizeConstraint", { MaxSize = Vector2.new(420, 660), MinSize = Vector2.new(280, 0) }),
		Ui.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})

	local colorA, colorB = Teams.List[TEAM_A].Color, Teams.List[TEAM_B].Color
	Ui.label({
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 52),
		TextSize = 40,
		Font = Enum.Font.GothamBlack,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = string.format('<font color="%s">%s</font> <font color="#b4b4be" size="24">vs</font> <font color="%s">%s</font>', hex(colorA), Teams.List[TEAM_A].Name, hex(colorB), Teams.List[TEAM_B].Name),
		Parent = column,
	})
	local status = Ui.label({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 22), TextSize = 16, Font = Enum.Font.Gotham, TextColor3 = C.Grey, TextXAlignment = Enum.TextXAlignment.Left, Parent = column })
	local profile = Ui.label({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 22), TextSize = 16, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, Parent = column })
	Ui.make("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Parent = column })

	-- Пункты меню.
	local items: { Item } = {}
	local focus = 2

	local function setFocus(i: number)
		focus = math.clamp(i, 1, #items)
		for j, item in items do
			local on = j == focus
			item.button.BackgroundTransparency = if on then 0.04 else 1
			item.text.TextColor3 = if on then Color3.fromRGB(15, 15, 18) else C.White
			if item.value then
				local color = if preferred == "Any" then C.Accent else Teams.List[preferred].Color
				item.value.TextColor3 = if on then color:Lerp(Color3.new(0, 0, 0), 0.25) else color
			end
		end
	end

	local function addItem(order: number, text: string, big: boolean?): Item
		local b = Ui.make("TextButton", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, if big then 54 else 42),
			BackgroundColor3 = Color3.fromRGB(245, 245, 245),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Selectable = false,
			Text = "",
			Parent = column,
		}, { Ui.corner(4) })
		local t = Ui.label({
			Position = UDim2.new(0, 16, 0, 0),
			Size = UDim2.new(1, -32, 1, 0),
			TextSize = if big then 28 else 21,
			Font = if big then Enum.Font.GothamBlack else Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextStrokeTransparency = 1,
			Text = text,
			Parent = b,
		})
		local item: Item = { button = b, text = t, activate = function() end }
		table.insert(items, item)
		local index = #items
		b.MouseEnter:Connect(function()
			setFocus(index)
		end)
		b.Activated:Connect(function()
			setFocus(index)
			item.activate()
		end)
		return item
	end

	-- Сторона: ‹ Банда | Любая | Силовики ›.
	local sideItem = addItem(5, "Сторона")
	sideItem.value = Ui.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 1,
		Parent = sideItem.button,
	})
	local function sideName(key: string): string
		return if key == "Any" then "Любая" else Teams.List[key].Name
	end
	local function setSide(key: string)
		preferred = key
		sideItem.value.Text = "‹  " .. sideName(key) .. "  ›"
		Net.get("ChooseSide"):FireServer(preferred) -- в лобби сразу переводит в штаб этой стороны
		setFocus(focus)
	end
	local function stepSide(delta: number)
		local i = table.find(SIDES, preferred) or 2
		setSide(SIDES[(i - 1 + delta) % #SIDES + 1])
	end
	sideItem.left = function()
		stepSide(-1)
	end
	sideItem.right = function()
		stepSide(1)
	end
	sideItem.activate = sideItem.right :: () -> ()
	sideItem.value.Text = "‹  " .. sideName(preferred) .. "  ›"

	local playItem = addItem(6, "ИГРАТЬ", true)
	playItem.activate = function()
		if not played then
			played = true
			Net.get("Play"):FireServer(preferred)
			Menus.close()
			MenuCamera.stop(true) -- камера опускается в штаб
			return
		end
		Menus.close()
	end

	local links = {
		{ "Персонаж", "Skins" },
		{ "Инвентарь", "Inventory" },
		{ "Прогресс", "Progress" },
		{ "Магазин", "Shop" },
		{ "Настройки", "Settings" },
	}
	for i, link in links do
		local item = addItem(6 + i, link[1])
		item.activate = function()
			Menus.open(link[2])
		end
	end

	local teamHint = Ui.label({ LayoutOrder = 20, Size = UDim2.new(1, 0, 0, 34), TextSize = 14, TextWrapped = true, Font = Enum.Font.Gotham, TextColor3 = C.Grey, TextXAlignment = Enum.TextXAlignment.Left, Parent = column })
	local hints = Ui.label({ LayoutOrder = 21, Size = UDim2.new(1, 0, 0, 20), TextSize = 14, Font = Enum.Font.Gotham, TextColor3 = C.Grey, TextXAlignment = Enum.TextXAlignment.Left, Parent = column })

	-- Клавиатура и геймпад.
	local function onNav(_, inputState: Enum.UserInputState, input: InputObject)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Up or k == Enum.KeyCode.W or k == Enum.KeyCode.DPadUp then
			setFocus(if focus <= 1 then #items else focus - 1)
		elseif k == Enum.KeyCode.Down or k == Enum.KeyCode.S or k == Enum.KeyCode.DPadDown then
			setFocus(if focus >= #items then 1 else focus + 1)
		elseif k == Enum.KeyCode.Left or k == Enum.KeyCode.A or k == Enum.KeyCode.DPadLeft then
			local item = items[focus]
			if item.left then
				item.left()
			end
		elseif k == Enum.KeyCode.Right or k == Enum.KeyCode.D or k == Enum.KeyCode.DPadRight then
			local item = items[focus]
			if item.right then
				item.right()
			end
		else
			items[focus].activate()
		end
		return Enum.ContextActionResult.Sink
	end
	local bound = false
	local function bindNav(on: boolean)
		if on == bound then
			return
		end
		bound = on
		if on then
			ContextActionService:BindActionAtPriority(NAV_ACTION, onNav, false, Enum.ContextActionPriority.High.Value + 50,
				Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
				Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.A, Enum.KeyCode.D,
				Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.Space,
				Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.ButtonA)
		else
			ContextActionService:UnbindAction(NAV_ACTION)
		end
	end

	local function refresh()
		playItem.text.Text = if played then "ПРОДОЛЖИТЬ" else "ИГРАТЬ"
		-- Без пролёта камеры (меню открыто посреди игры) фон темнее.
		root.BackgroundTransparency = if MenuCamera.isRunning() then 1 else 0.45
		teamHint.Text = if played
			then "Смена стороны действует со следующего матча"
			else "Если выбранная сторона больше другой, игра поставит в меньшую"
		hints.Text = if UserInputService.GamepadEnabled
			then "Крестовина — выбор и сторона   •   A — выбрать"
			else "↑↓ — выбор   •   ←→ — сторона   •   Enter — выбрать"
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
		setFocus(focus)
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
		bindNav(name == "Main")
		if name == nil and not played then
			task.defer(Menus.open, "Main")
		end
	end)
	MenuCamera.start()
	Menus.open("Main")
end

return MainMenu
