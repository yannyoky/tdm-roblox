-- Цикл игры: лобби и голосование → матч → итоги → снова лобби.
-- Состояние матча хранится атрибутами папки ReplicatedStorage.MatchState, его читает HUD.
local Players = game:GetService("Players")
local TeamsService = game:GetService("Teams")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModesConfig = require(Shared.Config.Modes)
local TeamsConfig = require(Shared.Config.Teams)
local Progression = require(Shared.Config.Progression)
local Net = require(Shared.Net)

local Services = script.Parent
local ModesFolder = Services.Parent:WaitForChild("Modes")
local DataService = require(Services.DataService)
local ShopService = require(Services.ShopService)
local WeaponService = require(Services.WeaponService)
local MapService = require(Services.MapService)

local MatchConfig = ModesConfig.Match
local TEAM_KEYS = TeamsConfig.Order

local MatchService = {}

local state: Folder
local map: Folder
local teams: { [string]: Team } = {}
local phase = "Lobby" -- Lobby | Match | Results
local mode = nil
local votes: { [Player]: string } = {}
local matchStats: { [Player]: { kills: number } } = {}

local function setState(name: string, value: any)
	state:SetAttribute(name, value)
end

local function getTeamKey(player: Player): string?
	if player.Neutral or not player.Team then
		return nil
	end
	return player.Team:GetAttribute("Key")
end

local function getTeamPlayers(key: string): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if getTeamKey(player) == key then
			table.insert(list, player)
		end
	end
	return list
end

-- Жив и находится на арене (не в лобби).
local function isAlive(player: Player): boolean
	local char = player.Character
	if not char or char:GetAttribute("InLobby") then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") ~= nil
end

local function otherTeam(key: string): string
	return if key == TEAM_KEYS[1] then TEAM_KEYS[2] else TEAM_KEYS[1]
end

local function pickSpawn(folderName: string): CFrame
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

-- Появление игрока: на арене за свою команду или в лобби.
local function spawnPlayer(player: Player, forceLobby: boolean?)
	if player.Parent ~= Players then
		return
	end
	local key = getTeamKey(player)
	local onArena = phase == "Match" and key ~= nil and not forceLobby
	player:LoadCharacter()
	local char = player.Character
	if not char or player.Parent ~= Players then
		return
	end
	char:SetAttribute("InLobby", not onArena)
	char:PivotTo(pickSpawn(if onArena then key :: string else "Lobby"))
	if onArena then
		WeaponService.giveLoadout(player)
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
	for _, player in Players:GetPlayers() do
		if getTeamKey(player) then
			task.spawn(spawnPlayer, player)
		end
	end
end

local function assignTeam(player: Player): string
	local countA, countB = #getTeamPlayers(TEAM_KEYS[1]), #getTeamPlayers(TEAM_KEYS[2])
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

local api = {
	teams = TEAM_KEYS,
	getTeamPlayers = getTeamPlayers,
	getTeamKey = getTeamKey,
	isAlive = isAlive,
	otherTeam = otherTeam,
	respawnAll = respawnAll,
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

local function onDied(player: Player, hum: Humanoid)
	local char = hum.Parent
	local killerId = hum:GetAttribute("LastAttacker")
	local killer = if killerId then Players:GetPlayerByUserId(killerId) else nil
	local weaponId = hum:GetAttribute("LastWeapon")

	if phase == "Match" and mode and not (char and char:GetAttribute("InLobby")) then
		Net.get("KillFeed"):FireAllClients(if killer then killer.DisplayName else nil, player.DisplayName, weaponId)
		if killer and killer ~= player and getTeamKey(killer) ~= getTeamKey(player) then
			local stats = matchStats[killer]
			if stats then
				stats.kills += 1
			end
		end
		mode:OnPlayerKilled(player, killer)
		if mode:CanRespawn(player) then
			task.delay(mode:GetRespawnDelay(), function()
				if phase == "Match" and player.Character == char and getTeamKey(player) then
					spawnPlayer(player)
				end
			end)
		else
			-- Без возрождения: смотрим бой из лобби до следующего раунда.
			task.delay(3, function()
				if phase == "Match" and player.Character == char then
					spawnPlayer(player, true)
				end
			end)
		end
	else
		task.delay(2, function()
			if player.Character == char then
				spawnPlayer(player, phase == "Match")
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
	return if RunService:IsStudio() then MatchConfig.MinPlayersStudio else MatchConfig.MinPlayers
end

local function runLobby(): string
	phase = "Lobby"
	mode = nil
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
		task.spawn(spawnPlayer, player)
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
			setState("Message", "Голосуйте за режим")
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
	for player, stats in matchStats do
		if player.Parent == Players and getTeamKey(player) then
			local won = getTeamKey(player) == winner
			local xp = R.Play.XP + stats.kills * R.Kill.XP + (if won then R.Win.XP else 0)
			local coins = R.Play.Coins + stats.kills * R.Kill.Coins + (if won then R.Win.Coins else 0)
			local xpMult, coinMult = ShopService.getMultipliers(player)
			DataService.addReward(player, math.floor(xp * xpMult), math.floor(coins * coinMult), {
				kills = stats.kills,
				won = won,
			})
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

	mode = ModeClass.new(api, def)
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
		spawnPlayer(player, not mode:OnPlayerAdded(player))
	else
		spawnPlayer(player)
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

	WeaponService.setDamageFilter(function(attacker, victim)
		if phase ~= "Match" then
			return false
		end
		local a, v = getTeamKey(attacker), getTeamKey(victim)
		return a ~= nil and v ~= nil and a ~= v and isAlive(victim)
	end)

	Net.get("VoteMode").OnServerEvent:Connect(function(player, modeId)
		if phase ~= "Lobby" or typeof(modeId) ~= "string" or not ModesConfig.List[modeId] then
			return
		end
		votes[player] = modeId
		refreshVotes()
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
