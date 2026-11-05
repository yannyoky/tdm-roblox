-- Сохранение прогресса игроков в DataStore.
-- Для живого сервера с большим онлайном стоит перейти на ProfileStore
-- (защита от одновременной записи с двух серверов). Для MVP хватает этого.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared.Config.Progression)
local Weapons = require(Shared.Config.Weapons)

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 120
local MAX_PURCHASE_HISTORY = 50

local DEFAULT_DATA = {
	Level = 1,
	XP = 0,
	Coins = 0,
	Kills = 0,
	Wins = 0,
	Matches = 0,
	XPBoostUntil = 0, -- os.time(), до которого действует буст опыта
	Purchases = {}, -- последние PurchaseId, чтобы не выдать покупку дважды
	Inventory = { "Rifle", "Pistol", "Knife" }, -- что игрок берёт в бой (любое открытое, без ограничений)
}

type Profile = { data: { [string]: any }, canSave: boolean }

local DataService = {}
local profiles: { [Player]: Profile } = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore недоступен (включите API Services в Studio): ", result)
	end
end

local function deepCopy(t)
	local copy = {}
	for k, v in t do
		copy[k] = if type(v) == "table" then deepCopy(v) else v
	end
	return copy
end

local function reconcile(data)
	for k, v in DEFAULT_DATA do
		if data[k] == nil then
			data[k] = if type(v) == "table" then deepCopy(v) else v
		end
	end
	return data
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

local function refreshStats(player: Player)
	local profile = profiles[player]
	local stats = player:FindFirstChild("leaderstats")
	if not profile or not stats then
		return
	end
	local data = profile.data
	local level = stats:FindFirstChild("Уровень") :: IntValue?
	local coins = stats:FindFirstChild("Монеты") :: IntValue?
	if level then
		level.Value = data.Level
	end
	if coins then
		coins.Value = data.Coins
	end
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("XP", data.XP)
	player:SetAttribute("XPNeeded", Progression.xpForLevel(data.Level))
	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("XPBoostUntil", data.XPBoostUntil)
	player:SetAttribute("Inventory", table.concat(data.Inventory, ","))
end

local function createStats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local level = Instance.new("IntValue")
	level.Name = "Уровень"
	level.Parent = stats
	local coins = Instance.new("IntValue")
	coins.Name = "Монеты"
	coins.Parent = stats
	stats.Parent = player
end

local function load(player: Player)
	local raw = nil
	local canSave = false
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(store.GetAsync, store, keyFor(player))
			if ok then
				raw = result
				canSave = true
				break
			end
			warn(string.format("[DataService] Ошибка загрузки %s (попытка %d): %s", player.Name, attempt, tostring(result)))
			task.wait(attempt * 2)
		end
	end
	if player.Parent ~= Players then
		return
	end
	if not canSave then
		warn("[DataService] Прогресс игрока не будет сохраняться в этой сессии: " .. player.Name)
	end
	local data = reconcile(if type(raw) == "table" then raw else deepCopy(DEFAULT_DATA))
	profiles[player] = { data = data, canSave = canSave }
	createStats(player)
	refreshStats(player)
	player:SetAttribute("DataLoaded", true)
end

function DataService.get(player: Player): { [string]: any }?
	local profile = profiles[player]
	return if profile then profile.data else nil
end

function DataService.save(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile.canSave or not store then
		return false
	end
	local ok, err = pcall(store.UpdateAsync, store, keyFor(player), function()
		return profile.data
	end)
	if not ok then
		warn("[DataService] Ошибка сохранения " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

-- Награда за матч: опыт, монеты, статистика.
function DataService.addReward(player: Player, xp: number, coins: number, stats: { kills: number, won: boolean }?)
	local profile = profiles[player]
	if not profile then
		return
	end
	local d = profile.data
	d.Coins += coins
	d.XP += xp
	if stats then
		d.Matches += 1
		d.Kills += stats.kills
		if stats.won then
			d.Wins += 1
		end
	end
	while d.Level < Progression.MaxLevel and d.XP >= Progression.xpForLevel(d.Level) do
		d.XP -= Progression.xpForLevel(d.Level)
		d.Level += 1
	end
	refreshStats(player)
end

-- Инвентарь игрока: только открытые по уровню предметы. Пустой инвентарь заменяется стандартным.
function DataService.getInventory(player: Player): { string }
	local data = DataService.get(player)
	local result = {}
	if data then
		for _, id in data.Inventory do
			if Weapons.isUnlocked(id, data.Level) and not table.find(result, id) then
				table.insert(result, id)
			end
		end
	end
	if #result == 0 then
		result = table.clone(Weapons.DefaultInventory)
	end
	return result
end

-- Взять предмет в бой или убрать его из инвентаря.
function DataService.setInventoryItem(player: Player, itemId: string, enabled: boolean): boolean
	local data = DataService.get(player)
	if not data or not Weapons.isUnlocked(itemId, data.Level) then
		return false
	end
	local index = table.find(data.Inventory, itemId)
	if enabled and not index then
		table.insert(data.Inventory, itemId)
	elseif not enabled and index then
		table.remove(data.Inventory, index)
	end
	refreshStats(player)
	return true
end

function DataService.addCoins(player: Player, amount: number)
	DataService.addReward(player, 0, amount, nil)
end

function DataService.addXPBoost(player: Player, seconds: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.XPBoostUntil = math.max(os.time(), data.XPBoostUntil) + seconds
	refreshStats(player)
end

function DataService.hasPurchase(player: Player, purchaseId: string): boolean
	local data = DataService.get(player)
	return data ~= nil and table.find(data.Purchases, purchaseId) ~= nil
end

function DataService.recordPurchase(player: Player, purchaseId: string)
	local data = DataService.get(player)
	if not data then
		return
	end
	table.insert(data.Purchases, purchaseId)
	while #data.Purchases > MAX_PURCHASE_HISTORY do
		table.remove(data.Purchases, 1)
	end
end

function DataService.init()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		profiles[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(DataService.save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.save(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait()
		end
	end)
end

return DataService
