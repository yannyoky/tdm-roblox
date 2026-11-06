-- Цикл игры: лобби и голосование → матч → итоги → снова лобби.
-- Состояние матча хранится атрибутами папки ReplicatedStorage.MatchState, его читает HUD.
--
-- «Боец» — это Player или бот (таблица из BotService). У обоих есть Character, DisplayName, UserId.
-- Команда игрока — его Team, команда бота — поле TeamKey.
local Players = game:GetService("Players")
local TeamsService = game:GetService("Teams")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModesConfig = require(Shared.Config.Modes)
local TeamsConfig = require(Shared.Config.Teams)
local BotsConfig = require(Shared.Config.Bots)
local Combat = require(Shared.Config.Combat)
local Weapons = require(Shared.Config.Weapons)
local Meta = require(Shared.Config.Meta)
local Progression = require(Shared.Config.Progression)
local Net = require(Shared.Net)

local Services = script.Parent
local ModesFolder = Services.Parent:WaitForChild("Modes")
local DataService = require(Services.DataService)
local ShopService = require(Services.ShopService)
local WeaponService = require(Services.WeaponService)
local MapService = require(Services.MapService)
local VehicleService = require(Services.Parent:WaitForChild("World"):WaitForChild("VehicleService"))
local BotService = require(Services.BotService)
local PhysicsSetup = require(Services.PhysicsSetup)
local DamageService = require(Services.DamageService)
local ProgressionService = require(Services.ProgressionService)

local MatchConfig = ModesConfig.Match
local TEAM_KEYS = TeamsConfig.Order

local MatchService = {}

local state: Folder
local map: Folder
local teams: { [string]: Team } = {}
local phase = "Lobby" -- Lobby | Match | Results
local mode = nil
local votes: { [Player]: string } = {}
local matchStats = {} -- [боец] = { kills = n }

local function setState(name: string, value: any)
	state:SetAttribute(name, value)
end

local function isBot(entity): boolean
	return type(entity) == "table" and entity.IsBot == true
end

local function getTeamKey(entity): string?
	if isBot(entity) then
		return entity.TeamKey
	end
	if entity.Neutral or not entity.Team then
		return nil
	end
	return entity.Team:GetAttribute("Key")
end

local function getTeamHumans(key: string): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if getTeamKey(player) == key then
			table.insert(list, player)
		end
	end
	return list
end

local function getTeamBots(key: string)
	local list = {}
	for _, bot in BotService.all() do
		if bot.TeamKey == key then
			table.insert(list, bot)
		end
	end
	return list
end

-- Все бойцы команды: игроки и боты.
local function getTeamMembers(key: string)
	local list = getTeamHumans(key)
	for _, bot in getTeamBots(key) do
		table.insert(list, bot)
	end
	return list
end

-- Жив (в том числе ранен) и находится на арене, а не в лобби.
local function isAlive(entity): boolean
	local char = entity.Character
	if not char or char.Parent == nil or char:GetAttribute("InLobby") then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") ~= nil
end

-- В строю: жив и не ранен. Раненый не держит точку и не считается живым для раундов.
local function isActive(entity): boolean
	return isAlive(entity) and not DamageService.isDowned(entity.Character)
end

local function otherTeam(key: string): string
	return if key == TEAM_KEYS[1] then TEAM_KEYS[2] else TEAM_KEYS[1]
end

local function entityId(entity): string
	return if isBot(entity) then "b" .. entity.Id else "p" .. entity.UserId
end

local function entityFromId(id: string?)
	if type(id) ~= "string" then
		return nil
	end
	local kind, num = id:sub(1, 1), tonumber(id:sub(2))
	if not num then
		return nil
	end
	if kind == "p" then
		return Players:GetPlayerByUserId(num)
	end
	for _, bot in BotService.all() do
		if bot.Id == num then
			return bot
		end
	end
	return nil
end

local function entityFromCharacter(model: Model)
	return Players:GetPlayerFromCharacter(model) or BotService.fromCharacter(model)
end

-- Точка появления. Сюда подключается MapService с отдельными базами команд.
local function pickSpawn(folderName: string): CFrame
	if folderName ~= "Lobby" then
		folderName = MapService.spawnFolder(folderName, mode and mode.def)
	end
	local spawns = map:FindFirstChild("Spawns")
	local folder = spawns and spawns:FindFirstChild(folderName)
	local list = if folder then folder:GetChildren() else {}
	if #list == 0 then
		warn("[MatchService] Нет точек появления в Map.Spawns." .. folderName)
		return CFrame.new(0, 10, 0)
	end
	local spot = list[math.random(#list)] :: BasePart
	return spot.CFrame + Vector3.new(0, 4, 0)
end

-- Появление бойца: на арене за свою команду или в лобби (только игроки).
local function spawnEntity(entity, forceLobby: boolean?)
	local key = getTeamKey(entity)
	if isBot(entity) then
		if phase == "Match" and key and not forceLobby then
			BotService.spawn(entity, pickSpawn(key), MatchConfig.SpawnProtection)
			if entity.Character then
				if math.random() < 0.5 then
					DamageService.giveArmor(entity.Character)
				end
				local ranks = Meta.Ranks[key]
				entity.RankName = entity.RankName or ranks[math.random(#ranks)].Name
				ProgressionService.attachNameTag(entity.Character, entity.DisplayName, entity.RankName, TeamsConfig.List[key].Color)
			end
		else
			BotService.despawn(entity)
		end
		return
	end

	local player = entity :: Player
	if player.Parent ~= Players then
		return
	end
	local onArena = phase == "Match" and key ~= nil and not forceLobby
	player:LoadCharacter()
	local char = player.Character
	if not char or player.Parent ~= Players then
		return
	end
	PhysicsSetup.prepareCharacter(char)
	char:SetAttribute("InLobby", not onArena)
	char:PivotTo(pickSpawn(if onArena then key :: string else "Lobby"))
	if onArena then
		local inventory = DataService.getInventory(player)
		WeaponService.giveInventory(player, inventory)
		if table.find(inventory, "Armor") then
			DamageService.giveArmor(char)
		end
		local subtitle = ProgressionService.rankName(player, key :: string)
		local title = player:GetAttribute("Title")
		if title and title ~= "" then
			subtitle ..= " • " .. title
		end
		ProgressionService.attachNameTag(char, player.DisplayName, subtitle, TeamsConfig.List[key :: string].Color)
		local shield = Instance.new("ForceField")
		shield.Parent = char
		task.delay(MatchConfig.SpawnProtection, function()
			if shield.Parent then
				shield:Destroy()
			end
		end)
	end
end

local function respawnAll()
	VehicleService.resetFleet() -- каждый раунд машины снова стоят на базах
	for _, key in TEAM_KEYS do
		for _, entity in getTeamMembers(key) do
			task.spawn(spawnEntity, entity)
		end
	end
end

local function assignTeam(player: Player): string
	local countA, countB = #getTeamHumans(TEAM_KEYS[1]), #getTeamHumans(TEAM_KEYS[2])
	local key
	if countA == countB then
		key = TEAM_KEYS[math.random(2)]
	else
		key = if countA < countB then TEAM_KEYS[1] else TEAM_KEYS[2]
	end
	player.Neutral = false
	player.Team = teams[key]
	matchStats[player] = matchStats[player] or { kills = 0 }
	return key
end

-- Боты добивают каждую команду до BotsConfig.TeamSize и уходят, когда приходят игроки.
local function rebalanceBots()
	if phase ~= "Match" or not BotsConfig.Enabled or not mode then
		return
	end
	for _, key in TEAM_KEYS do
		local desired = math.max(0, BotsConfig.TeamSize - #getTeamHumans(key))
		local teamBots = getTeamBots(key)
		for i = #teamBots, desired + 1, -1 do
			matchStats[teamBots[i]] = nil
			BotService.remove(teamBots[i])
		end
		for _ = #teamBots + 1, desired do
			local bot = BotService.create(key)
			matchStats[bot] = { kills = 0 }
			if mode:OnPlayerAdded(bot) then
				task.spawn(spawnEntity, bot)
			end
		end
	end
end

local function removeAllBots()
	for _, bot in table.clone(BotService.all()) do
		BotService.remove(bot)
	end
end

local api = {
	teams = TEAM_KEYS,
	getTeamPlayers = getTeamMembers, -- старое имя, оставлено для совместимости
	getTeamMembers = getTeamMembers,
	getTeamKey = getTeamKey,
	isAlive = isActive, -- для режимов «живой» = в строю (не ранен)
	isAliveOrDowned = isAlive,
	isBot = isBot,
	otherTeam = otherTeam,
	respawnAll = respawnAll,
	-- Команда выиграла раунд (капт): засчитываем задания её игрокам.
	onRoundWon = function(key: string)
		for _, player in getTeamHumans(key) do
			ProgressionService.record(player, "CaptureRound")
		end
	end,
	setState = function(name: string, value: any)
		setState(name, value)
	end,
	teamName = function(key: string): string
		return TeamsConfig.List[key].Name
	end,
	teamColor = function(key: string): Color3
		return TeamsConfig.List[key].Color
	end,
	map = nil :: Folder?,
}

local function onDied(entity, hum: Humanoid)
	local char = hum.Parent :: Model
	local killer = entityFromId(hum:GetAttribute("LastAttacker"))
	local weaponId = hum:GetAttribute("LastWeapon")
	local inLobby = char and char:GetAttribute("InLobby")

	if char then
		PhysicsSetup.ragdoll(char)
	end

	if phase == "Match" and mode and not inLobby then
		Net.get("KillFeed"):FireAllClients(if killer then killer.DisplayName else nil, entity.DisplayName, weaponId)
		if killer and killer ~= entity and getTeamKey(killer) ~= getTeamKey(entity) then
			local stats = matchStats[killer]
			if stats then
				stats.kills += 1
			end
			if not isBot(killer) then
				ProgressionService.record(killer, "Kill")
				if hum:GetAttribute("LastHeadshot") then
					ProgressionService.record(killer, "Headshot")
				end
				local weaponDef = weaponId and Weapons.List[weaponId]
				if weaponDef and weaponDef.Kind == "Grenade" then
					ProgressionService.record(killer, "GrenadeKill")
				end
			end
		end
		mode:OnPlayerKilled(entity, killer)
	end

	if isBot(entity) then
		-- Тело остаётся лежать несколько секунд.
		if char then
			Debris:AddItem(char, 6)
		end
		if phase == "Match" and mode and mode:CanRespawn(entity) then
			task.delay(mode:GetRespawnDelay(), function()
				if phase == "Match" and entity.Character == char and table.find(BotService.all(), entity) then
					spawnEntity(entity)
				end
			end)
		end
		return
	end

	local player = entity :: Player
	if phase == "Match" and mode and not inLobby then
		if mode:CanRespawn(player) then
			task.delay(mode:GetRespawnDelay(), function()
				if phase == "Match" and player.Character == char and getTeamKey(player) then
					spawnEntity(player)
				end
			end)
		else
			-- Без возрождения: смотрим бой из лобби до следующего раунда.
			task.delay(3, function()
				if phase == "Match" and player.Character == char then
					spawnEntity(player, true)
				end
			end)
		end
	else
		task.delay(2, function()
			if player.Character == char then
				spawnEntity(player, phase == "Match")
			end
		end)
	end
end

local function onCharacterAdded(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Died:Connect(function()
		onDied(player, hum)
	end)
end

local function refreshVotes()
	local counts = {}
	for _, modeId in votes do
		counts[modeId] = (counts[modeId] or 0) + 1
	end
	for _, id in ModesConfig.Order do
		setState("Votes_" .. id, counts[id] or 0)
	end
end

local function countVotes(): string
	local counts = {}
	for _, modeId in votes do
		counts[modeId] = (counts[modeId] or 0) + 1
	end
	local best, bestCount = {}, -1
	for _, id in ModesConfig.Order do
		local c = counts[id] or 0
		if c > bestCount then
			best, bestCount = { id }, c
		elseif c == bestCount then
			table.insert(best, id)
		end
	end
	return best[math.random(#best)]
end

local function minPlayers(): number
	if RunService:IsStudio() then
		return MatchConfig.MinPlayersStudio
	end
	-- С ботами можно играть и одному.
	return if BotsConfig.Enabled then 1 else MatchConfig.MinPlayers
end

local function runLobby(): string
	phase = "Lobby"
	mode = nil
	removeAllBots()
	setState("Phase", "Lobby")
	setState("ModeId", "")
	setState("ModeName", "")
	setState("ScoreA", 0)
	setState("ScoreB", 0)
	setState("CaptureProgress", 0)
	setState("Winner", "")
	for _, player in Players:GetPlayers() do
		player.Neutral = true
		player.Team = nil
		task.spawn(spawnEntity, player)
	end

	while true do
		while #Players:GetPlayers() < minPlayers() do
			setState("Message", string.format("Ждём игроков: %d/%d", #Players:GetPlayers(), minPlayers()))
			setState("TimeLeft", 0)
			task.wait(1)
		end

		table.clear(votes)
		refreshVotes()
		local enough = true
		for t = MatchConfig.IntermissionTime, 1, -1 do
			setState("Message", "Голосуйте за режим и выберите оружие")
			setState("TimeLeft", t)
			task.wait(1)
			if #Players:GetPlayers() < minPlayers() then
				enough = false
				break
			end
		end
		if enough then
			break
		end
	end
	return countVotes()
end

local function giveRewards(winner: string)
	local R = Progression.Rewards
	local humansByTeam = {}
	for _, key in TEAM_KEYS do
		humansByTeam[key] = getTeamHumans(key)
	end
	ProgressionService.updateRatings(humansByTeam, winner)

	for entity, stats in matchStats do
		if not isBot(entity) and entity.Parent == Players and getTeamKey(entity) then
			local player = entity :: Player
			local won = getTeamKey(player) == winner
			local xp = R.Play.XP + stats.kills * R.Kill.XP + (if won then R.Win.XP else 0)
			local coins = R.Play.Coins + stats.kills * R.Kill.Coins + (if won then R.Win.Coins else 0)
			local xpMult, coinMult = ShopService.getMultipliers(player)
			local finalXp = math.floor(xp * xpMult)
			DataService.addReward(player, finalXp, math.floor(coins * coinMult), {
				kills = stats.kills,
				won = won,
			})
			ProgressionService.addFactionXP(player, getTeamKey(player) :: string, finalXp)
			ProgressionService.addSeasonXP(player, finalXp)
			ProgressionService.record(player, "Match")
			if won then
				ProgressionService.record(player, "Win")
			end
			ProgressionService.publish(player)
		end
	end
end

local function runMatch(modeId: string)
	local def = ModesConfig.List[modeId]
	local ModeClass = require(ModesFolder:FindFirstChild(def.Module))

	table.clear(matchStats)
	local list = Players:GetPlayers()
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	for _, player in list do
		player.Neutral = true
		player.Team = nil
	end
	for _, player in list do
		assignTeam(player)
	end

	phase = "Match"
	setState("Phase", "Match")
	setState("ModeId", modeId)
	setState("ModeName", def.DisplayName)
	setState("TimeLeft", def.Duration or 0)

	-- Ротация карт: каждый матч на следующей карте.
	map = MapService.nextMap()
	api.map = map

	mode = ModeClass.new(api, def)
	rebalanceBots()
	respawnAll()
	mode:Start()

	local timeLeft = def.Duration
	local winner = nil
	local last = os.clock()
	while not winner do
		task.wait(0.2)
		local now = os.clock()
		local dt = now - last
		last = now
		mode:OnTick(dt)
		winner = mode:GetWinner()
		if not winner and timeLeft then
			timeLeft -= dt
			setState("TimeLeft", math.max(0, math.ceil(timeLeft)))
			if timeLeft <= 0 then
				winner = mode:GetTimeoutWinner()
			end
		end
		if not winner and #Players:GetPlayers() == 0 then
			winner = "Draw"
		end
	end

	phase = "Results"
	setState("Phase", "Results")
	setState("Winner", winner)
	setState("Message", if winner == "Draw" then "Ничья!" else string.format("Победа: %s!", api.teamName(winner)))
	giveRewards(winner)
	mode:Cleanup()
	mode = nil
	task.wait(MatchConfig.ResultsTime)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	if phase == "Match" and mode then
		assignTeam(player)
		rebalanceBots() -- игрок заменяет бота в своей команде
		spawnEntity(player, not mode:OnPlayerAdded(player))
	else
		spawnEntity(player)
	end
end

function MatchService.start()
	Players.CharacterAutoLoads = false
	map = MapService.get()
	api.map = map

	state = Instance.new("Folder")
	state.Name = "MatchState"
	state.Parent = ReplicatedStorage

	for _, key in TEAM_KEYS do
		local info = TeamsConfig.List[key]
		local team = Instance.new("Team")
		team.Name = info.Name
		team.TeamColor = info.BrickColor
		team.AutoAssignable = false
		team:SetAttribute("Key", key)
		team.Parent = TeamsService
		teams[key] = team
	end

	setState("VoteOptions", table.concat(ModesConfig.Order, ","))
	for _, id in ModesConfig.Order do
		setState("ModeName_" .. id, ModesConfig.List[id].DisplayName)
	end

	WeaponService.setHooks({
		canDamage = function(attacker, victim)
			if phase ~= "Match" then
				return false
			end
			local a, v = getTeamKey(attacker), getTeamKey(victim)
			return a ~= nil and v ~= nil and a ~= v and isAlive(victim)
		end,
		fromCharacter = entityFromCharacter,
		idOf = entityId,
	})

	DamageService.setHooks({
		getTeamKey = getTeamKey,
		fromCharacter = entityFromCharacter,
		onRevive = function(rescuer)
			if rescuer and not isBot(rescuer) then
				ProgressionService.record(rescuer, "Revive")
			end
		end,
		downedAllowed = function()
			return phase == "Match" and mode ~= nil and Combat.Downed.Enabled and mode.def.DownedEnabled ~= false
		end,
	})

	BotService.setHooks({
		getEnemies = function(bot)
			return getTeamMembers(otherTeam(bot.TeamKey))
		end,
		getAllies = function(bot)
			return getTeamMembers(bot.TeamKey)
		end,
		isAlive = isActive,
		getObjective = function(bot)
			return if mode then mode:GetObjective(bot) else nil
		end,
		onDied = onDied,
	})
	BotService.start()

	Net.get("VoteMode").OnServerEvent:Connect(function(player, modeId)
		if phase ~= "Lobby" or typeof(modeId) ~= "string" or not ModesConfig.List[modeId] then
			return
		end
		votes[player] = modeId
		refreshVotes()
	end)

	Net.get("SetInventoryItem").OnServerEvent:Connect(function(player, itemId, enabled)
		if typeof(itemId) ~= "string" or typeof(enabled) ~= "boolean" then
			return
		end
		DataService.setInventoryItem(player, itemId, enabled)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		votes[player] = nil
		matchStats[player] = nil
		if mode then
			mode:OnPlayerRemoved(player)
		end
		if phase == "Lobby" then
			refreshVotes()
		end
		-- Ушедшего игрока заменит бот (после того как игрок покинет список).
		task.delay(0.5, rebalanceBots)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			local modeId = runLobby()
			local ok, err = pcall(runMatch, modeId)
			if not ok then
				warn("[MatchService] Ошибка в матче: ", err)
				if mode then
					pcall(mode.Cleanup, mode)
					mode = nil
				end
			end
		end
	end)
end

return MatchService
