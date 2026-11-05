-- Интерфейс: счёт и таймер, полоса захвата, голосование, патроны, лента убийств,
-- маркер попадания, уровень и магазин. Всё строится кодом, чтобы не зависеть от файла места.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Weapons = require(Shared.Config.Weapons)
local Teams = require(Shared.Config.Teams)
local Shop = require(Shared.Config.Shop)

local player = Players.LocalPlayer

local TEAM_A, TEAM_B = Teams.Order[1], Teams.Order[2]
local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(20, 20, 26)

local Hud = {}

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

local function corner(radius: number?)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

local function label(props: { [string]: any }): TextLabel
	local base = {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextStrokeTransparency = 0.6,
		Text = "",
	}
	for key, value in props do
		base[key] = value
	end
	return make("TextLabel", base)
end

local function button(text: string, size: UDim2): TextButton
	return make("TextButton", {
		Size = size,
		BackgroundColor3 = Color3.fromRGB(45, 45, 55),
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = text,
		AutoButtonColor = true,
	}, { corner(6), make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Hud.init()
	local state = ReplicatedStorage:WaitForChild("MatchState") :: Folder
	local gui = make("ScreenGui", { Name = "Hud", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

	-- Верхняя панель: счёт, таймер, сообщение.
	local top = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(0, 380, 0, 74),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.25,
	}, { corner() })
	top.Parent = gui
	local scoreA = label({ Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(0.28, 0, 0, 38), TextColor3 = Teams.List[TEAM_A].Color })
	local timer = label({ Position = UDim2.new(0.28, 8, 0, 4), Size = UDim2.new(0.44, -16, 0, 38) })
	local scoreB = label({ Position = UDim2.new(0.72, -8, 0, 4), Size = UDim2.new(0.28, 0, 0, 38), TextColor3 = Teams.List[TEAM_B].Color })
	local message = label({ Position = UDim2.new(0, 8, 0, 44), Size = UDim2.new(1, -16, 0, 24), Font = Enum.Font.Gotham })
	scoreA.Parent, timer.Parent, scoreB.Parent, message.Parent = top, top, top, top

	-- Полоса захвата (капт).
	local captureBar = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 86),
		Size = UDim2.new(0, 320, 0, 16),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.25,
		Visible = false,
	}, { corner(4) })
	local captureFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE }, { corner(4) })
	captureFill.Parent = captureBar
	local captureText = label({ Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	captureText.Parent = captureBar
	captureBar.Parent = gui

	-- Голосование в лобби.
	local votePanel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.new(0, 420, 0, 50),
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	})
	votePanel.Parent = gui
	local voteButtons: { [string]: TextButton } = {}
	local myVote = nil
	for id in string.gmatch(state:GetAttribute("VoteOptions") or "", "[^,]+") do
		local b = button(id, UDim2.new(0, 200, 1, 0))
		b.Activated:Connect(function()
			myVote = id
			Net.get("VoteMode"):FireServer(id)
		end)
		b.Parent = votePanel
		voteButtons[id] = b
	end

	-- Команда и уровень (слева снизу).
	local teamLabel = label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -44), Size = UDim2.new(0, 220, 0, 26), TextXAlignment = Enum.TextXAlignment.Left })
	teamLabel.Parent = gui
	local levelLabel = label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.new(0, 260, 0, 24), Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left })
	levelLabel.Parent = gui

	-- Патроны (справа снизу).
	local ammoLabel = label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -90), Size = UDim2.new(0, 220, 0, 40), TextXAlignment = Enum.TextXAlignment.Right, Visible = false })
	ammoLabel.Parent = gui

	-- Маркер попадания.
	local hitMarker = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 34, 0, 34), Text = "×", Visible = false })
	hitMarker.Parent = gui

	-- Лента убийств (справа сверху).
	local feed = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 320, 0, 150),
		BackgroundTransparency = 1,
	}, { make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4) }) })
	feed.Parent = gui

	-- Магазин.
	local shopButton = button("Магазин", UDim2.new(0, 120, 0, 36))
	shopButton.AnchorPoint = Vector2.new(0, 0)
	shopButton.Position = UDim2.new(0, 12, 0, 60)
	shopButton.Parent = gui
	local shopPanel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 340, 0, 330),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.1,
		Visible = false,
	}, {
		corner(),
		make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		make("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	shopPanel.Parent = gui
	shopButton.Activated:Connect(function()
		shopPanel.Visible = not shopPanel.Visible
	end)

	local shopItems = {
		{ text = "VIP: +25% опыта и монет", pass = Shop.GamePasses.VIP.Id },
	}
	for _, product in Shop.Products do
		local text = if product.Coins then string.format("%d монет", product.Coins) else "x2 опыта на 1 час"
		table.insert(shopItems, { text = text, product = product.Id })
	end
	for _, item in shopItems do
		local id = item.pass or item.product
		local b = button(if id == 0 then item.text .. " (скоро)" else item.text, UDim2.new(1, 0, 0, 40))
		b.Activated:Connect(function()
			if id == 0 then
				return
			end
			if item.pass then
				MarketplaceService:PromptGamePassPurchase(player, id)
			else
				MarketplaceService:PromptProductPurchase(player, id)
			end
		end)
		b.Parent = shopPanel
	end
	local closeButton = button("Закрыть", UDim2.new(0.5, 0, 0, 34))
	closeButton.Activated:Connect(function()
		shopPanel.Visible = false
	end)
	closeButton.Parent = shopPanel

	-- Обновление по состоянию матча.
	local function refresh()
		local phase = state:GetAttribute("Phase") or "Lobby"
		scoreA.Text = tostring(state:GetAttribute("ScoreA") or 0)
		scoreB.Text = tostring(state:GetAttribute("ScoreB") or 0)
		local modeName = state:GetAttribute("ModeName") or ""
		local time = formatTime(state:GetAttribute("TimeLeft") or 0)
		timer.Text = if modeName ~= "" then modeName .. "  " .. time else time
		message.Text = state:GetAttribute("Message") or ""

		local isCapture = phase == "Match" and state:GetAttribute("ModeId") == "Capture"
		captureBar.Visible = isCapture
		if isCapture then
			local progress = state:GetAttribute("CaptureProgress") or 0
			local attackers = state:GetAttribute("Attackers")
			captureFill.Size = UDim2.fromScale(math.clamp(progress / 100, 0, 1), 1)
			captureFill.BackgroundColor3 = if attackers and Teams.List[attackers] then Teams.List[attackers].Color else WHITE
			captureText.Text = string.format("Захват %d%%", progress)
		end

		votePanel.Visible = phase == "Lobby"
		for id, b in voteButtons do
			local name = state:GetAttribute("ModeName_" .. id) or id
			b.Text = string.format("%s%s (%d)", if myVote == id then "✓ " else "", name, state:GetAttribute("Votes_" .. id) or 0)
		end
	end
	state.AttributeChanged:Connect(refresh)
	refresh()

	local function refreshPlayer()
		local key = if player.Team and not player.Neutral then player.Team:GetAttribute("Key") else nil
		if key and Teams.List[key] then
			teamLabel.Text = "Вы: " .. Teams.List[key].Name
			teamLabel.TextColor3 = Teams.List[key].Color
		else
			teamLabel.Text = "Лобби"
			teamLabel.TextColor3 = WHITE
		end
		local level = player:GetAttribute("Level")
		if level then
			local boost = (player:GetAttribute("XPBoostUntil") or 0) > os.time()
			levelLabel.Text = string.format(
				"Ур. %d  •  %d/%d XP  •  %d монет%s%s",
				level,
				player:GetAttribute("XP") or 0,
				player:GetAttribute("XPNeeded") or 0,
				player:GetAttribute("Coins") or 0,
				if player:GetAttribute("VIP") then "  •  VIP" else "",
				if boost then "  •  x2 XP" else ""
			)
		end
	end
	player:GetPropertyChangedSignal("Team"):Connect(refreshPlayer)
	player:GetPropertyChangedSignal("Neutral"):Connect(refreshPlayer)
	player.AttributeChanged:Connect(refreshPlayer)
	refreshPlayer()

	-- Патроны выбранного оружия.
	RunService.RenderStepped:Connect(function()
		local char = player.Character
		local tool = char and char:FindFirstChildOfClass("Tool")
		local def = tool and Weapons.List[tool:GetAttribute("WeaponId")]
		if not def then
			ammoLabel.Visible = false
			return
		end
		ammoLabel.Visible = true
		if tool:GetAttribute("Count") then
			ammoLabel.Text = string.format("%s: %d", def.DisplayName, tool:GetAttribute("Count"))
		elseif not def.MagSize then
			ammoLabel.Text = def.DisplayName
		elseif tool:GetAttribute("Reloading") then
			ammoLabel.Text = "Перезарядка..."
		else
			ammoLabel.Text = string.format("%d / %d", tool:GetAttribute("Ammo") or 0, def.MagSize)
		end
	end)

	Net.get("HitMarker").OnClientEvent:Connect(function(isHead: boolean)
		hitMarker.TextColor3 = if isHead then Color3.fromRGB(255, 80, 80) else WHITE
		hitMarker.Visible = true
		task.delay(0.15, function()
			hitMarker.Visible = false
		end)
	end)

	Net.get("KillFeed").OnClientEvent:Connect(function(killerName: string?, victimName: string, weaponId: string?)
		local weapon = if weaponId and Weapons.List[weaponId] then Weapons.List[weaponId].DisplayName else nil
		local text
		if killerName then
			text = string.format("%s [%s] %s", killerName, weapon or "?", victimName)
		else
			text = victimName .. " погиб"
		end
		local entry = label({
			Size = UDim2.new(1, 0, 0, 22),
			Text = text,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		entry.Parent = feed
		local entries = {}
		for _, child in feed:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(entries, child)
			end
		end
		if #entries > 5 then
			entries[1]:Destroy()
		end
		task.delay(6, function()
			entry:Destroy()
		end)
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return Hud
