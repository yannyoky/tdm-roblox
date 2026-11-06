-- Глобальные таблицы лидеров (рейтинг, победы, убийства) через OrderedDataStore.
-- Топ-10 раз в 2 минуты кладётся JSON-ом в ReplicatedStorage.Leaderboards (StringValue).
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)

local BOARDS = {
	{ Key = "Rating", Title = "Рейтинг", Field = "Rating" },
	{ Key = "Wins", Title = "Победы", Field = "Wins" },
	{ Key = "Kills", Title = "Убийства", Field = "Kills" },
}
local REFRESH_INTERVAL = 120
local TOP = 10

local LeaderboardService = {}

local stores = {}
local nameCache: { [number]: string } = {}
local value: StringValue

local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = if ok then name else ("#" .. userId)
	return nameCache[userId]
end

-- Записать текущие значения игрока в таблицы.
function LeaderboardService.submit(player: Player)
	local data = DataService.get(player)
	if not data or player.UserId <= 0 then
		return
	end
	nameCache[player.UserId] = player.Name
	for _, board in BOARDS do
		local store = stores[board.Key]
		if store then
			pcall(store.SetAsync, store, tostring(player.UserId), math.floor(data[board.Field] or 0))
		end
	end
end

local function refresh()
	local result = {}
	for _, board in BOARDS do
		local store = stores[board.Key]
		local rows = {}
		if store then
			local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
			if ok then
				for i, entry in pages:GetCurrentPage() do
					table.insert(rows, { Place = i, Name = nameOf(tonumber(entry.key) or 0), Value = entry.value })
				end
			end
		end
		table.insert(result, { Title = board.Title, Rows = rows })
	end
	value.Value = HttpService:JSONEncode(result)
end

function LeaderboardService.init()
	value = Instance.new("StringValue")
	value.Name = "Leaderboards"
	value.Value = "[]"
	value.Parent = ReplicatedStorage

	for _, board in BOARDS do
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "LB_" .. board.Key)
		if ok then
			stores[board.Key] = store
		else
			warn("[LeaderboardService] Таблица недоступна: ", board.Key)
		end
	end

	Players.PlayerRemoving:Connect(LeaderboardService.submit)
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				LeaderboardService.submit(player)
			end
			refresh()
			task.wait(REFRESH_INTERVAL)
		end
	end)
end

return LeaderboardService
