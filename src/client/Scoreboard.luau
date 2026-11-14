-- Таблица игроков (зажать Tab, на геймпаде — Select) и экран итогов матча.
-- Данные приходят с сервера: MatchState.Scoreboard (JSON), MVP, Winner и атрибут игрока LastMatch.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Teams = require(Shared.Config.Teams)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local C = Ui.Colors

local Scoreboard = {}

local function decode(json: any): any
	if type(json) ~= "string" or json == "" then
		return nil
	end
	local ok, result = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok then result else nil
end

-- Две колонки команд с игроками, отсортированными по убийствам.
local function fillTables(container: Frame, rows: { any })
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, key in Teams.Order do
		local info = Teams.List[key]
		local col = Ui.make("Frame", {
			Position = UDim2.new((i - 1) * 0.5, if i == 1 then 0 else 6, 0, 0),
			Size = UDim2.new(0.5, -6, 1, 0),
			BackgroundColor3 = C.Card,
			BackgroundTransparency = 0.1,
			Parent = container,
		}, {
			Ui.corner(8),
			Ui.padding(8),
			Ui.make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local header = Ui.make("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = col })
		Ui.label({ Size = UDim2.new(0.6, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = info.Color, Text = info.Name, Parent = header })
		Ui.label({ Position = UDim2.new(0.6, 0, 0, 0), Size = UDim2.new(0.2, 0, 1, 0), Text = "У", TextColor3 = C.Grey, Parent = header })
		Ui.label({ Position = UDim2.new(0.8, 0, 0, 0), Size = UDim2.new(0.2, 0, 1, 0), Text = "С", TextColor3 = C.Grey, Parent = header })

		local team = {}
		for _, row in rows do
			if row.t == key then
				table.insert(team, row)
			end
		end
		table.sort(team, function(a, b)
			if a.k ~= b.k then
				return a.k > b.k
			end
			return a.d < b.d
		end)
		for j, row in team do
			local isMe = not row.b and row.u == player.UserId
			local line = Ui.make("Frame", {
				LayoutOrder = j,
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundColor3 = C.Accent,
				BackgroundTransparency = if isMe then 0.6 else 1,
				Parent = col,
			}, { Ui.corner(4) })
			local name = row.n .. (if row.b then " (бот)" elseif row.l then string.format("  [%d]", row.l) else "")
			Ui.label({ Size = UDim2.new(0.6, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham, Text = name, TextColor3 = if row.b then C.Grey else C.White, Parent = line })
			Ui.label({ Position = UDim2.new(0.6, 0, 0, 0), Size = UDim2.new(0.2, 0, 1, 0), Font = Enum.Font.Gotham, Text = tostring(row.k), Parent = line })
			Ui.label({ Position = UDim2.new(0.8, 0, 0, 0), Size = UDim2.new(0.2, 0, 1, 0), Font = Enum.Font.Gotham, Text = tostring(row.d), Parent = line })
		end
	end
end

function Scoreboard.init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	local state = ReplicatedStorage:WaitForChild("MatchState") :: Folder
	local gui = Ui.make("ScreenGui", { Name = "Scoreboard", ResetOnSpawn = false, DisplayOrder = 8 })

	-- Таблица по Tab.
	local board = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.7, 0),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = gui,
	}, { Ui.corner(10), Ui.padding(10), Ui.make("UISizeConstraint", { MaxSize = Vector2.new(760, 520) }) })
	local boardTitle = Ui.label({ Size = UDim2.new(1, 0, 0, 30), Parent = board })
	local boardTables = Ui.make("Frame", { Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 1, -38), BackgroundTransparency = 1, Parent = board })

	-- Экран итогов.
	local results = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.85, 0),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	}, { Ui.corner(10), Ui.padding(12), Ui.make("UISizeConstraint", { MaxSize = Vector2.new(800, 600) }) })
	local banner = Ui.label({ Size = UDim2.new(1, 0, 0, 48), Parent = results })
	local mvpLabel = Ui.label({ Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(1, 0, 0, 24), Font = Enum.Font.Gotham, TextColor3 = C.Accent, Parent = results })
	local rewardLabel = Ui.label({ Position = UDim2.new(0, 0, 0, 80), Size = UDim2.new(1, 0, 0, 24), Font = Enum.Font.Gotham, Parent = results })
	local resultTables = Ui.make("Frame", { Position = UDim2.new(0, 0, 0, 114), Size = UDim2.new(1, 0, 1, -114), BackgroundTransparency = 1, Parent = results })

	local holding = false

	local function rows()
		return decode(state:GetAttribute("Scoreboard")) or {}
	end

	local function refreshBoard()
		if not board.Visible then
			return
		end
		local mode = state:GetAttribute("ModeName") or ""
		boardTitle.Text = if mode ~= "" then string.format("%s  •  %d : %d", mode, state:GetAttribute("ScoreA") or 0, state:GetAttribute("ScoreB") or 0) else "Лобби"
		fillTables(boardTables, rows())
	end

	local function refreshResults()
		local isResults = state:GetAttribute("Phase") == "Results"
		results.Visible = isResults
		if not isResults then
			return
		end
		local winner = state:GetAttribute("Winner")
		local myKey = player.Team and not player.Neutral and player.Team:GetAttribute("Key")
		if winner == "Draw" then
			banner.Text = "НИЧЬЯ"
			banner.TextColor3 = C.White
		elseif winner and Teams.List[winner] then
			local verdict = if myKey == winner then "ПОБЕДА" elseif myKey then "ПОРАЖЕНИЕ" else "ПОБЕДИЛИ"
			banner.Text = string.format("%s — %s", verdict, Teams.List[winner].Name)
			banner.TextColor3 = Teams.List[winner].Color
		end
		local mvp = state:GetAttribute("MVP") or ""
		mvpLabel.Text = if mvp ~= "" then "Лучший игрок: " .. mvp else ""
		local last = decode(player:GetAttribute("LastMatch"))
		rewardLabel.Text = if last and myKey
			then string.format("Ваш счёт: %d убийств, %d смертей  •  +%d опыта, +%d монет", last.kills, last.deaths or 0, last.xp, last.coins)
			else ""
		fillTables(resultTables, rows())
	end

	local function setHolding(on: boolean)
		holding = on
		board.Visible = on and not results.Visible
		refreshBoard()
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.ButtonSelect then
			setHolding(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.ButtonSelect then
			setHolding(false)
		end
	end)

	-- На телефоне — кнопка «Счёт» сверху справа.
	if UserInputService.TouchEnabled then
		local b = Ui.button("Счёт", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 170), Size = UDim2.new(0, 80, 0, 32), Parent = gui })
		b.Activated:Connect(function()
			setHolding(not holding)
		end)
	end

	state.AttributeChanged:Connect(function(name)
		if name == "Phase" or name == "Winner" or name == "MVP" or name == "Scoreboard" then
			refreshResults()
		end
		if board.Visible then
			refreshBoard()
		end
	end)
	player:GetAttributeChangedSignal("LastMatch"):Connect(refreshResults)
	refreshResults()

	gui.Parent = player:WaitForChild("PlayerGui")
end

return Scoreboard
