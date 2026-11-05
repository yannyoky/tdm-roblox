-- Меню «Прогресс»: звания фракций, рейтинг, задания на сегодня, сезонный пропуск, лидеры.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Meta = require(Shared.Config.Meta)
local Teams = require(Shared.Config.Teams)
local Shop = require(Shared.Config.Shop)

local player = Players.LocalPlayer

local ProgressMenu = {}

local PANEL = Color3.fromRGB(20, 20, 26)
local CARD = Color3.fromRGB(38, 38, 48)
local WHITE = Color3.new(1, 1, 1)
local GREY = Color3.fromRGB(190, 190, 200)

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	return inst
end

local function text(parent: Instance, order: number, str: string, height: number, color: Color3?, bold: boolean?)
	return make("TextLabel", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		TextColor3 = color or WHITE,
		Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = str,
		Parent = parent,
	})
end

local function bar(parent: Instance, order: number, fraction: number, color: Color3)
	local back = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Color3.fromRGB(60, 60, 70),
		Parent = parent,
	}, { make("UICorner", { CornerRadius = UDim.new(0, 4) }) })
	make("Frame", {
		Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
		BackgroundColor3 = color,
		Parent = back,
	}, { make("UICorner", { CornerRadius = UDim.new(0, 4) }) })
	return back
end

local function decode(json: string?)
	if not json or json == "" then
		return {}
	end
	local ok, result = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok then result else {}
end

function ProgressMenu.init()
	local gui = make("ScreenGui", { Name = "ProgressMenu", ResetOnSpawn = false })
	local openButton = make("TextButton", {
		Position = UDim2.new(0, 12, 0, 144),
		Size = UDim2.new(0, 120, 0, 36),
		BackgroundColor3 = Color3.fromRGB(45, 45, 55),
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = "Прогресс",
	}, { make("UICorner", { CornerRadius = UDim.new(0, 6) }) })
	openButton.Parent = gui

	local panel = make("ScrollingFrame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 400, 0.8, 0),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.05,
		Visible = false,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
	}, {
		make("UICorner", { CornerRadius = UDim.new(0, 8) }),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 16),
		}),
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	panel.Parent = gui
	openButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	local leaderboards = ReplicatedStorage:WaitForChild("Leaderboards") :: StringValue

	local function rebuild()
		for _, child in panel:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local n = 0
		local function order()
			n += 1
			return n
		end

		-- Звания.
		text(panel, order(), "Звания", 28, WHITE, true)
		for _, faction in Teams.Order do
			local xp = player:GetAttribute("FactionXP_" .. faction) or 0
			local nextXp = player:GetAttribute("FactionNextXP_" .. faction) or 0
			local rank = player:GetAttribute("Rank_" .. faction) or "—"
			local line = string.format("%s: %s", Teams.List[faction].Name, rank)
			if nextXp > 0 then
				line ..= string.format("  (%d / %d)", xp, nextXp)
			else
				line ..= "  (высшее звание)"
			end
			text(panel, order(), line, 22, Teams.List[faction].Color)
			if nextXp > 0 then
				bar(panel, order(), xp / nextXp, Teams.List[faction].Color)
			end
		end

		-- Рейтинг.
		text(panel, order(), "Рейтинг", 28, WHITE, true)
		text(panel, order(), string.format("%s, %d очков", player:GetAttribute("Division") or "Бронза", player:GetAttribute("Rating") or 1000), 22, GREY)
		text(panel, order(), string.format("Считается в матчах, где в каждой команде от %d живых игроков.", Meta.Rating.MinHumansPerTeam), 30, GREY)

		-- Задания.
		text(panel, order(), "Задания на сегодня", 28, WHITE, true)
		for _, q in decode(player:GetAttribute("Quests")) do
			local mark = if q.Done then "✓ " else ""
			text(panel, order(), string.format("%s%s  %d/%d  (+%d монет)", mark, q.Text, q.Progress, q.Goal, q.Coins), 22, if q.Done then Color3.fromRGB(120, 220, 120) else GREY)
			bar(panel, order(), q.Progress / q.Goal, Color3.fromRGB(240, 190, 60))
		end

		-- Сезонный пропуск.
		local tier = player:GetAttribute("SeasonTier") or 0
		local seasonXp = player:GetAttribute("SeasonXP") or 0
		local premium = player:GetAttribute("SeasonPremium") == true
		text(panel, order(), string.format("%s (%s)", Meta.Season.Name, Meta.Season.EndsText), 28, WHITE, true)
		text(panel, order(), string.format("Уровень %d / %d%s", tier, Meta.Season.Tiers, if premium then "  •  премиум" else ""), 22, GREY)
		if tier < Meta.Season.Tiers then
			bar(panel, order(), (seasonXp % Meta.Season.TierXP) / Meta.Season.TierXP, Color3.fromRGB(160, 110, 240))
			local nextFree = Meta.seasonReward(tier + 1, false)
			local desc = string.format("Следующая награда: %d монет", nextFree.Coins or 0)
			if nextFree.Title then
				desc ..= ", титул «" .. nextFree.Title .. "»"
			end
			text(panel, order(), desc, 22, GREY)
		end
		if not premium then
			local buy = make("TextButton", {
				LayoutOrder = order(),
				Size = UDim2.new(1, 0, 0, 38),
				BackgroundColor3 = Color3.fromRGB(110, 70, 180),
				TextColor3 = WHITE,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				Text = if Shop.GamePasses.SeasonPass.Id ~= 0 then "Купить премиум-пропуск" else "Премиум-пропуск (скоро)",
				Parent = panel,
			}, { make("UICorner", { CornerRadius = UDim.new(0, 6) }) })
			buy.Activated:Connect(function()
				if Shop.GamePasses.SeasonPass.Id ~= 0 then
					MarketplaceService:PromptGamePassPurchase(player, Shop.GamePasses.SeasonPass.Id)
				end
			end)
		end

		-- Лидеры.
		for _, board in decode(leaderboards.Value) do
			text(panel, order(), "Лидеры: " .. board.Title, 28, WHITE, true)
			local card = make("Frame", {
				LayoutOrder = order(),
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = CARD,
				Parent = panel,
			}, {
				make("UICorner", { CornerRadius = UDim.new(0, 6) }),
				make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
				make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			if #board.Rows == 0 then
				text(card, 1, "Пока пусто", 20, GREY)
			end
			for i, row in board.Rows do
				text(card, i, string.format("%d. %s — %d", row.Place, row.Name, row.Value), 20, GREY)
			end
		end
	end

	local pending = false
	local function scheduleRebuild()
		if pending then
			return
		end
		pending = true
		task.delay(0.2, function()
			pending = false
			if panel.Visible then
				rebuild()
			end
		end)
	end
	player.AttributeChanged:Connect(scheduleRebuild)
	leaderboards.Changed:Connect(scheduleRebuild)
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.Visible then
			rebuild()
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return ProgressMenu
