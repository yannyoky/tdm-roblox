-- Меню «Персонаж» (клавиша U): тело (мужское или женское), кожа, лицо, причёска, борода, очки,
-- одежда и форма каждой стороны. Всё сохраняется сразу при выборе.
-- Предпросмотр собирает сервер (ApplyDescription клиенту недоступен) и кладёт модель
-- в PlayerGui.LookPreview; меню показывает её копию в ViewportFrame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Skins = require(Shared.Config.Skins)
local Appearance = require(Shared.Config.Appearance)
local Teams = require(Shared.Config.Teams)
local Meta = require(Shared.Config.Meta)
local Shop = require(Shared.Config.Shop)
local Ui = require(script.Parent.Ui)
local Menus = require(script.Parent.Menus)

local player = Players.LocalPlayer
local C = Ui.Colors

local SkinMenu = {}

local LOOK_TAB = "Look"

local function unlockText(def): string
	if def.Unlock.Type == "Rank" then
		local rank = Meta.Ranks[def.Faction][def.Unlock.Rank]
		return "Звание: " .. (if rank then rank.Name else "№" .. def.Unlock.Rank)
	end
	return Skins.unlockText(def)
end

local function decode(attr: string): { [string]: any }
	local raw = player:GetAttribute(attr)
	if type(raw) ~= "string" or raw == "" then
		return {}
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(value) == "table" then value else {}
end

-- Список вариантов для слота: внешность или одежда стороны (с «формой» первой строкой).
local function optionsFor(tab: string, key: string): { any }
	if tab == LOOK_TAB then
		return Appearance.Options[key] or {}
	end
	local list = { { Id = Appearance.UNIFORM, Name = "Как в скине" } }
	for _, opt in (Appearance.Clothing[tab] or {})[key] or {} do
		table.insert(list, opt)
	end
	return list
end

function SkinMenu.init()
	local window = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.84, 0),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
	}, {
		Ui.corner(10),
		Ui.make("UISizeConstraint", { MaxSize = Vector2.new(860, 560) }),
	})
	Ui.label({ Position = UDim2.new(0, 14, 0, 8), Size = UDim2.new(0.5, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Text = "Персонаж", Parent = window })
	local close = Ui.button("×", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.new(0, 34, 0, 30), BackgroundColor3 = C.Bad, Parent = window })
	close.Activated:Connect(Menus.close)

	-- Вкладки: внешность и стороны.
	local tabs: { [string]: TextButton } = {}
	local tabOrder = { LOOK_TAB }
	for _, key in Teams.Order do
		table.insert(tabOrder, key)
	end
	for i, key in tabOrder do
		tabs[key] = Ui.button(if key == LOOK_TAB then "Внешность" else Teams.List[key].Name, {
			Position = UDim2.new(0, 14 + (i - 1) * 140, 0, 46),
			Size = UDim2.new(0, 130, 0, 32),
			Parent = window,
		})
	end

	-- Предпросмотр слева.
	local viewport = Ui.make("ViewportFrame", {
		Position = UDim2.new(0, 14, 0, 88),
		Size = UDim2.new(0.4, -14, 1, -102),
		BackgroundColor3 = C.Card,
		Ambient = Color3.fromRGB(150, 150, 160),
		LightColor = Color3.new(1, 0.97, 0.92),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		Parent = window,
	}, { Ui.corner(8) })
	local world = Ui.make("WorldModel", { Parent = viewport })
	local vpCamera = Ui.make("Camera", { FieldOfView = 30, Parent = viewport })
	viewport.CurrentCamera = vpCamera
	local status = Ui.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -20, 0, 20),
		Font = Enum.Font.Gotham,
		TextColor3 = C.Grey,
		Text = "",
		Parent = viewport,
	})
	Ui.label({
		Position = UDim2.new(0, 8, 0, 6),
		Size = UDim2.new(1, -16, 0, 16),
		Font = Enum.Font.Gotham,
		TextColor3 = C.Grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Тяните, чтобы повернуть",
		Parent = viewport,
	})

	-- Настройки справа.
	local list = Ui.make("ScrollingFrame", {
		Position = UDim2.new(0.4, 12, 0, 88),
		Size = UDim2.new(0.6, -26, 1, -102),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		Parent = window,
	}, {
		Ui.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.make("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	})

	local tab = LOOK_TAB
	local look: { [string]: any } = {}
	local outfits: { [string]: { [string]: string } } = {}
	local previewSkin: { [string]: string } = {}
	local angle = math.rad(200)
	local dragging = false
	local previewModel: Model? = nil

	local function loadState()
		look = decode("Look")
		for _, key in Teams.Order do
			outfits[key] = decode("Outfit_" .. key)
			previewSkin[key] = player:GetAttribute("Skin_" .. key) or Skins.Default[key]
		end
	end

	-- Предпросмотр: просим сервер собрать модель и ждём её в PlayerGui.LookPreview.
	local function requestPreview()
		status.Text = "Загрузка…"
		if tab == LOOK_TAB then
			Net.get("PreviewLook"):FireServer(look)
		else
			Net.get("PreviewLook"):FireServer(look, tab, outfits[tab], previewSkin[tab])
		end
	end

	local function showModel(source: Instance)
		if not source:IsA("Model") then
			return
		end
		world:ClearAllChildren()
		local clone = source:Clone()
		clone:PivotTo(CFrame.new())
		clone.Parent = world
		previewModel = clone
		status.Text = ""
	end

	task.spawn(function()
		local gui = player:WaitForChild("PlayerGui")
		local function watchFolder(folder: Instance)
			if folder.Name ~= "LookPreview" then
				return
			end
			folder.ChildAdded:Connect(function(child)
				-- Даём детям модели доехать до клиента.
				task.wait()
				showModel(child)
			end)
			local existing = folder:FindFirstChildWhichIsA("Model")
			if existing then
				showModel(existing)
			end
		end
		gui.ChildAdded:Connect(watchFolder)
		local folder = gui:FindFirstChild("LookPreview")
		if folder then
			watchFolder(folder)
		end
	end)

	viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	viewport.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	viewport.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			angle -= input.Delta.X * 0.01
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not window.Visible or not previewModel then
			return
		end
		if not dragging then
			angle += dt * 0.25
		end
		-- На вкладке внешности камера ближе к лицу.
		local closeUp = tab == LOOK_TAB
		local target = if closeUp then Vector3.new(0, 1.3, 0) else Vector3.new(0, 0.2, 0)
		local dist = if closeUp then 7 else 13
		vpCamera.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(angle) * dist, 0.4, math.cos(angle) * dist), target)
	end)

	local rebuild: () -> ()

	local function header(order: number, text: string)
		Ui.label({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Accent, Text = text, Parent = list })
	end

	-- Строка «Название   < вариант >».
	local function picker(order: number, title: string, options: { any }, current: string, onPick: (string) -> ())
		local row = Ui.make("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = C.Card, Parent = list }, { Ui.corner(6) })
		Ui.label({ Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(0.38, -10, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 15, Text = title, Parent = row })
		local index = 1
		for i, opt in options do
			if opt.Id == current then
				index = i
			end
		end
		Ui.label({
			Position = UDim2.new(0.38, 40, 0, 0),
			Size = UDim2.new(0.62, -88, 1, 0),
			Font = Enum.Font.Gotham,
			TextSize = 15,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = if options[index] then string.format("%s  (%d/%d)", options[index].Name, index, #options) else "—",
			Parent = row,
		})
		local function step(delta: number)
			if #options < 2 then
				return
			end
			local nextIndex = (index - 1 + delta) % #options + 1
			onPick(options[nextIndex].Id)
		end
		local prev = Ui.button("<", { Position = UDim2.new(0.38, 0, 0.5, -15), Size = UDim2.new(0, 34, 0, 30), Parent = row })
		local nxt = Ui.button(">", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0.5, -15), Size = UDim2.new(0, 34, 0, 30), Parent = row })
		prev.Activated:Connect(function()
			step(-1)
		end)
		nxt.Activated:Connect(function()
			step(1)
		end)
	end

	local function setLook(key: string, value: any)
		look[key] = value
		Net.get("SetLook"):FireServer(look)
		requestPreview()
		rebuild()
	end

	-- Сменить тело: лицо, причёску и бороду другого пола заменяем на подходящие.
	local function setBody(bodyId: string)
		look.Body = bodyId
		local gender = Appearance.genderOf(bodyId)
		for key, value in Appearance.GenderDefaults[gender] do
			if not Appearance.fits(Appearance.option(key, look[key]), gender) or key == "Beard" and gender ~= "M" then
				look[key] = value
			end
		end
		Net.get("SetLook"):FireServer(look)
		requestPreview()
		rebuild()
	end

	local function buildLookTab()
		local bodyId = look.Body or Appearance.DefaultLook.Body
		local gender = Appearance.genderOf(bodyId)
		header(1, "Тело")
		local bodies = Ui.make("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = list }, {
			Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i, opt in Appearance.Options.Body do
			local b = Ui.button(opt.Name, {
				LayoutOrder = i,
				Size = UDim2.new(0.5, -4, 0, 42),
				BackgroundColor3 = if opt.Id == bodyId then C.Accent else C.Button,
				Parent = bodies,
			})
			b.Activated:Connect(function()
				if opt.Id ~= bodyId then
					setBody(opt.Id)
				end
			end)
		end

		-- У головы с кожей в текстуре цвет тела задан самой головой: выбор не показываем.
		local lookHead = Appearance.option("Head", look.Head or Appearance.GenderDefaults[gender].Head)
		local fixedTone = lookHead ~= nil and lookHead.SkinTone ~= nil
		if not fixedTone then
			header(3, "Цвет кожи")
			local tones = Ui.make("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = list }, {
				Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			local currentTone = look.Tone or Appearance.DefaultLook.Tone
			for i, color in Appearance.Tones do
				local b = Ui.button("", {
					LayoutOrder = i,
					Size = UDim2.new(0, 36, 0, 36),
					BackgroundColor3 = color,
					Parent = tones,
				})
				if currentTone == i then
					Ui.make("UIStroke", { Color = C.Accent, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
				end
				b.Activated:Connect(function()
					setLook("Tone", i)
				end)
			end
		end

		header(5, "Лицо и причёска")
		for i, slot in Appearance.LookSlots do
			if slot.Gender == nil or slot.Gender == gender then
				local current = look[slot.Key] or Appearance.GenderDefaults[gender][slot.Key] or Appearance.DefaultLook[slot.Key]
				picker(5 + i, slot.Name, Appearance.optionsFor(slot.Key, gender), current, function(id)
					setLook(slot.Key, id)
				end)
			end
		end
		Ui.label({
			LayoutOrder = 20,
			Size = UDim2.new(1, 0, 0, 36),
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = C.Grey,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "Внешность общая для обеих сторон. Одежда — на вкладках сторон. В лобби меняется сразу, в бою — со следующего появления.",
			Parent = list,
		})
	end

	local function owned(id: string): boolean
		return table.find(string.split(player:GetAttribute("OwnedSkins") or "", ","), id) ~= nil
	end

	local function buildFactionTab(faction: string)
		local outfit = outfits[faction]
		header(1, "Одежда")
		for i, slot in Appearance.ClothingSlots do
			picker(1 + i, slot.Name, optionsFor(faction, slot.Key), outfit[slot.Key] or Appearance.UNIFORM, function(id)
				outfit[slot.Key] = id
				Net.get("SetOutfit"):FireServer(faction, outfit)
				requestPreview()
				rebuild()
			end)
		end
		header(10, "Скины (готовые комплекты)")

		local selected = player:GetAttribute("Skin_" .. faction) or Skins.Default[faction]
		local coins = player:GetAttribute("Coins") or 0
		for i, id in Skins.Order[faction] do
			local def = Skins.List[id]
			local row = Ui.make("Frame", {
				LayoutOrder = 10 + i,
				Size = UDim2.new(1, 0, 0, 54),
				BackgroundColor3 = if previewSkin[faction] == id then C.Button else C.Card,
				Parent = list,
			}, { Ui.corner(6) })
			local swatch = Ui.make("Frame", { Position = UDim2.new(0, 8, 0, 8), Size = UDim2.new(0, 38, 0, 38), BackgroundColor3 = def.Shirt, Parent = row }, { Ui.corner(6) })
			Ui.make("Frame", { Position = UDim2.new(0, 0, 0.6, 0), Size = UDim2.new(1, 0, 0.4, 0), BackgroundColor3 = def.Pants, BorderSizePixel = 0, Parent = swatch })
			Ui.label({ Position = UDim2.new(0, 54, 0, 6), Size = UDim2.new(1, -190, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Text = def.DisplayName, Parent = row })
			Ui.label({ Position = UDim2.new(0, 54, 0, 30), Size = UDim2.new(1, -190, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham, TextColor3 = C.Grey, Text = unlockText(def), Parent = row })

			local action: TextButton
			if id == selected then
				action = Ui.button("Надет", { BackgroundColor3 = C.Good, AutoButtonColor = false })
			elseif owned(id) then
				action = Ui.button("Надеть")
				action.Activated:Connect(function()
					Net.get("EquipSkin"):FireServer(id)
				end)
			elseif def.Unlock.Type == "Coins" then
				local afford = coins >= def.Unlock.Price
				action = Ui.button(string.format("%d монет", def.Unlock.Price), { BackgroundColor3 = if afford then C.Accent else C.Locked })
				action.Activated:Connect(function()
					if afford then
						Net.get("BuySkin"):FireServer(id)
					end
				end)
			elseif def.Unlock.Type == "Pass" then
				local passId = Shop.GamePasses[def.Unlock.Pass] and Shop.GamePasses[def.Unlock.Pass].Id or 0
				action = Ui.button(if passId ~= 0 then "Купить" else "Скоро", { BackgroundColor3 = Color3.fromRGB(110, 70, 180) })
				action.Activated:Connect(function()
					if passId ~= 0 then
						MarketplaceService:PromptGamePassPurchase(player, passId)
					end
				end)
			else
				action = Ui.button("Закрыт", { BackgroundColor3 = C.Locked, AutoButtonColor = false })
			end
			action.AnchorPoint = Vector2.new(1, 0.5)
			action.Position = UDim2.new(1, -8, 0.5, 0)
			action.Size = UDim2.new(0, 120, 0, 34)
			action.Parent = row

			-- Клик по строке примеряет комплект на предпросмотре.
			local hit = Ui.make("TextButton", { Size = UDim2.new(1, -136, 1, 0), BackgroundTransparency = 1, Text = "", Parent = row })
			hit.Activated:Connect(function()
				previewSkin[faction] = id
				requestPreview()
				rebuild()
			end)
		end
	end

	rebuild = function()
		for key, button in tabs do
			button.BackgroundColor3 = if key == tab then (if key == LOOK_TAB then C.Accent else Teams.List[key].Color) else C.Button
		end
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if tab == LOOK_TAB then
			buildLookTab()
		else
			buildFactionTab(tab)
		end
	end

	for key, button in tabs do
		button.Activated:Connect(function()
			tab = key
			if key ~= LOOK_TAB then
				previewSkin[key] = player:GetAttribute("Skin_" .. key) or Skins.Default[key]
			end
			requestPreview()
			rebuild()
		end)
	end

	Menus.register("Skins", {
		title = "Персонаж",
		key = Enum.KeyCode.U,
		order = 3,
		panel = window,
		onOpen = function()
			loadState()
			local team = player.Team and not player.Neutral and player.Team:GetAttribute("Key")
			tab = if team and Skins.Order[team] then team else LOOK_TAB
			requestPreview()
			rebuild()
		end,
	})

	player.AttributeChanged:Connect(function(name)
		if not window.Visible then
			return
		end
		if name == "OwnedSkins" or name == "Coins" or string.sub(name, 1, 5) == "Skin_" then
			rebuild()
			if string.sub(name, 1, 5) == "Skin_" and tab ~= LOOK_TAB then
				previewSkin[tab] = player:GetAttribute("Skin_" .. tab) or Skins.Default[tab]
				requestPreview()
			end
		end
	end)
end

return SkinMenu
