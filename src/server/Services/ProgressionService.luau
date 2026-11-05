-- Звания фракций, ежедневные задания, сезонный пропуск, рейтинг и табличка над головой.
-- Клиент получает всё через атрибуты игрока (Quests и SeasonRewards — JSON).
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Meta = require(Shared.Config.Meta)
local TeamsConfig = require(Shared.Config.Teams)

local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)

local ProgressionService = {}

local function today(): number
	return math.floor(os.time() / 86400)
end

-- Задания на день выбираются детерминированно: одинаковые после перезахода.
local function rollDailyQuests(player: Player, day: number)
	local rng = Random.new(day * 7919 + player.UserId)
	local pool = table.clone(Meta.Quests)
	local result = {}
	for _ = 1, math.min(Meta.QuestsPerDay, #pool) do
		local quest = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(result, { Id = quest.Id, Progress = 0, Done = false })
	end
	return result
end

local function questDef(id: string)
	for _, q in Meta.Quests do
		if q.Id == id then
			return q
		end
	end
	return nil
end

local function hasPremium(player: Player): boolean
	return ShopService.ownsPass(player, "SeasonPass")
end

local function grantReward(player: Player, data, reward)
	if not reward then
		return
	end
	if reward.Coins then
		data.Coins += reward.Coins
	end
	if reward.XPBoostSeconds then
		data.XPBoostUntil = math.max(os.time(), data.XPBoostUntil) + reward.XPBoostSeconds
	end
	if reward.Title and not table.find(data.Titles, reward.Title) then
		table.insert(data.Titles, reward.Title)
		data.Title = reward.Title -- новый титул сразу надевается
	end
end

-- Выдать награды пропуска за все достигнутые уровни, которые ещё не выданы.
local function claimSeasonRewards(player: Player, data)
	local tier = math.min(Meta.Season.Tiers, math.floor(data.Season.XP / Meta.Season.TierXP))
	while data.Season.ClaimedFree < tier do
		data.Season.ClaimedFree += 1
		grantReward(player, data, Meta.seasonReward(data.Season.ClaimedFree, false))
	end
	if hasPremium(player) then
		while data.Season.ClaimedPremium < tier do
			data.Season.ClaimedPremium += 1
			grantReward(player, data, Meta.seasonReward(data.Season.ClaimedPremium, true))
		end
	end
end

local function ensureFresh(player: Player, data)
	local day = today()
	if data.Daily.Day ~= day then
		data.Daily = { Day = day, Quests = rollDailyQuests(player, day) }
	end
	if data.Season.Id ~= Meta.Season.Id then
		data.Season = { Id = Meta.Season.Id, XP = 0, ClaimedFree = 0, ClaimedPremium = 0 }
	end
	for _, faction in TeamsConfig.Order do
		data.FactionXP[faction] = data.FactionXP[faction] or 0
	end
end

-- Отправить клиенту всё, что показывает меню прогресса.
function ProgressionService.publish(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	ensureFresh(player, data)
	claimSeasonRewards(player, data)

	for _, faction in TeamsConfig.Order do
		local index, name = Meta.rankFor(faction, data.FactionXP[faction])
		local nextRank = Meta.Ranks[faction][index + 1]
		player:SetAttribute("Rank_" .. faction, name)
		player:SetAttribute("FactionXP_" .. faction, data.FactionXP[faction])
		player:SetAttribute("FactionNextXP_" .. faction, if nextRank then nextRank.XP else 0)
	end

	local quests = {}
	for _, q in data.Daily.Quests do
		local def = questDef(q.Id)
		if def then
			table.insert(quests, { Text = def.Text, Progress = q.Progress, Goal = def.Goal, Done = q.Done, Coins = def.Coins })
		end
	end
	player:SetAttribute("Quests", HttpService:JSONEncode(quests))

	local tier = math.min(Meta.Season.Tiers, math.floor(data.Season.XP / Meta.Season.TierXP))
	player:SetAttribute("SeasonXP", data.Season.XP)
	player:SetAttribute("SeasonTier", tier)
	player:SetAttribute("SeasonPremium", hasPremium(player))
	player:SetAttribute("Rating", math.floor(data.Rating))
	player:SetAttribute("Division", Meta.divisionFor(data.Rating))
	player:SetAttribute("Title", data.Title)
	DataService.refresh(player)
end

function ProgressionService.addSeasonXP(player: Player, xp: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	ensureFresh(player, data)
	data.Season.XP += xp
	claimSeasonRewards(player, data)
end

function ProgressionService.addFactionXP(player: Player, faction: string, xp: number)
	local data = DataService.get(player)
	if not data or not Meta.Ranks[faction] then
		return
	end
	data.FactionXP[faction] = (data.FactionXP[faction] or 0) + xp
end

-- Событие для заданий: Kill, Headshot, GrenadeKill, Revive, Win, Match, CaptureRound.
function ProgressionService.record(player: Player, event: string, amount: number?)
	local data = DataService.get(player)
	if not data then
		return
	end
	ensureFresh(player, data)
	amount = amount or 1
	if event == "Headshot" then
		data.Headshots += amount
	elseif event == "Revive" then
		data.Revives += amount
	end
	for _, q in data.Daily.Quests do
		local def = questDef(q.Id)
		if def and not q.Done and def.Event == event then
			q.Progress = math.min(def.Goal, q.Progress + amount)
			if q.Progress >= def.Goal then
				q.Done = true
				data.Coins += def.Coins
				data.Season.XP += def.SeasonXP
			end
		end
	end
	ProgressionService.publish(player)
end

-- Звание игрока за сторону, за которую он сейчас играет.
function ProgressionService.rankName(player: Player, faction: string): string
	local data = DataService.get(player)
	local xp = if data then data.FactionXP[faction] or 0 else 0
	local _, name = Meta.rankFor(faction, xp)
	return name
end

-- Рейтинг по системе Эло: команда против команды по средним рейтингам.
-- humansByTeam = { [teamKey] = { Player } }, winner = ключ команды или "Draw".
function ProgressionService.updateRatings(humansByTeam: { [string]: { Player } }, winner: string)
	local keys = TeamsConfig.Order
	for _, key in keys do
		if #(humansByTeam[key] or {}) < Meta.Rating.MinHumansPerTeam then
			return -- матч с ботами вместо людей не рейтинговый
		end
	end
	local avg = {}
	for _, key in keys do
		local sum, n = 0, 0
		for _, player in humansByTeam[key] do
			local data = DataService.get(player)
			if data then
				sum += data.Rating
				n += 1
			end
		end
		avg[key] = if n > 0 then sum / n else Meta.Rating.Start
	end
	for _, key in keys do
		local other = if key == keys[1] then keys[2] else keys[1]
		local expected = 1 / (1 + 10 ^ ((avg[other] - avg[key]) / 400))
		local score = if winner == "Draw" then 0.5 elseif winner == key then 1 else 0
		local delta = Meta.Rating.K * (score - expected)
		for _, player in humansByTeam[key] do
			local data = DataService.get(player)
			if data then
				data.Rating = math.max(0, data.Rating + delta)
				data.RatedMatches += 1
			end
		end
	end
end

-- Табличка над головой: имя, звание и титул. Видна вблизи и не просвечивает стены.
function ProgressionService.attachNameTag(char: Model, name: string, subtitle: string, color: Color3)
	local head = char:FindFirstChild("Head")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not head or not hum then
		return
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local old = head:FindFirstChild("NameTag")
	if old then
		old:Destroy()
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.new(0, 200, 0, 44)
	tag.StudsOffset = Vector3.new(0, 2.2, 0)
	tag.MaxDistance = 70
	tag.AlwaysOnTop = false
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = color
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = name
	nameLabel.Parent = tag
	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.new(0, 0, 0.55, 0)
	sub.Size = UDim2.new(1, 0, 0.45, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(230, 230, 230)
	sub.TextStrokeTransparency = 0.5
	sub.Text = subtitle
	sub.Parent = tag
	tag.Parent = head
end

function ProgressionService.init()
	local function onLoaded(player: Player)
		if player:GetAttribute("DataLoaded") then
			ProgressionService.publish(player)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
			onLoaded(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
			onLoaded(player)
		end)
		onLoaded(player)
	end

	-- Купили премиум-пропуск: выдать награды за уже пройденные уровни.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _, purchased)
		if purchased then
			task.delay(1, ProgressionService.publish, player)
		end
	end)

	-- Новый день: обновить задания у всех.
	task.spawn(function()
		local day = today()
		while true do
			task.wait(60)
			if today() ~= day then
				day = today()
				for _, player in Players:GetPlayers() do
					ProgressionService.publish(player)
				end
			end
		end
	end)
end

return ProgressionService
