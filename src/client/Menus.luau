-- Окна игры и горячие клавиши. Открыто только одно окно за раз.
-- Слева панель кнопок с подсказками клавиш, на ПК окна открываются клавишами:
--   M — главное меню, I — инвентарь, U — скины, J — прогресс, B — магазин, Esc/повтор — закрыть.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local PlayerSettings = require(script.Parent.PlayerSettings)

local player = Players.LocalPlayer

local Menus = {}

type Entry = {
	name: string,
	title: string,
	key: Enum.KeyCode?,
	order: number,
	panel: GuiObject,
	onOpen: (() -> ())?,
	button: TextButton?,
	inBar: boolean,
}

local entries: { [string]: Entry } = {}
local current: string? = nil
local gui: ScreenGui
local bar: Frame
local modal: TextButton
local openListeners: { (name: string?) -> () } = {}

local function keyName(key: Enum.KeyCode?): string
	return if key then key.Name else ""
end

local function refreshButtons()
	local hints = PlayerSettings.get("KeyHints") and not UserInputService.TouchEnabled
	for _, e in entries do
		if e.button then
			e.button.Text = if hints and e.key then string.format("%s  [%s]", e.title, keyName(e.key)) else e.title
			e.button.BackgroundColor3 = if current == e.name then Ui.Colors.Accent else Ui.Colors.Button
		end
	end
end

function Menus.isOpen(name: string?): boolean
	if name then
		return current == name
	end
	return current ~= nil
end

function Menus.close()
	if current and entries[current] then
		entries[current].panel.Visible = false
	end
	current = nil
	modal.Visible = false
	refreshButtons()
	for _, fn in openListeners do
		task.spawn(fn, nil)
	end
end

function Menus.open(name: string)
	local e = entries[name]
	if not e then
		return
	end
	if current and current ~= name and entries[current] then
		entries[current].panel.Visible = false
	end
	current = name
	e.panel.Visible = true
	modal.Visible = true -- освобождает курсор в режиме от первого лица
	if e.onOpen then
		task.spawn(e.onOpen)
	end
	refreshButtons()
	for _, fn in openListeners do
		task.spawn(fn, name)
	end
end

function Menus.toggle(name: string)
	if current == name then
		Menus.close()
	else
		Menus.open(name)
	end
end

-- fn(name) вызывается при открытии окна и fn(nil) при закрытии.
function Menus.onChanged(fn: (name: string?) -> ())
	table.insert(openListeners, fn)
end

-- Зарегистрировать окно. panel кладётся в общий ScreenGui.
function Menus.register(name: string, opts: { title: string, key: Enum.KeyCode?, order: number?, panel: GuiObject, onOpen: (() -> ())?, inBar: boolean? })
	local e: Entry = {
		name = name,
		title = opts.title,
		key = opts.key,
		order = opts.order or 100,
		panel = opts.panel,
		onOpen = opts.onOpen,
		inBar = opts.inBar ~= false,
	}
	entries[name] = e
	opts.panel.Visible = false
	opts.panel.Parent = gui
	if e.inBar then
		local b = Ui.button(e.title, {
			LayoutOrder = e.order,
			Size = UDim2.new(1, 0, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = bar,
		})
		b.Activated:Connect(function()
			Menus.toggle(name)
		end)
		e.button = b
	end
	refreshButtons()
end

-- Показать или спрятать панель кнопок (например, пока открыто главное меню).
function Menus.setBarVisible(on: boolean)
	bar.Visible = on
end

function Menus.gui(): ScreenGui
	return gui
end

function Menus.init()
	gui = Ui.make("ScreenGui", { Name = "Menus", ResetOnSpawn = false, DisplayOrder = 10, IgnoreGuiInset = false })
	bar = Ui.make("Frame", {
		Position = UDim2.new(0, 12, 0, 60),
		Size = UDim2.new(0, 170, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	modal = Ui.make("TextButton", {
		Size = UDim2.fromOffset(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Modal = true,
		Visible = false,
		Parent = gui,
	})

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape and current then
			Menus.close()
			return
		end
		for name, e in entries do
			if e.key and input.KeyCode == e.key then
				Menus.toggle(name)
				return
			end
		end
	end)

	PlayerSettings.onChanged(function(key)
		if key == "KeyHints" then
			refreshButtons()
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return Menus
