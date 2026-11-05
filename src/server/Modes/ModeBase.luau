-- Базовый режим. Каждый сценарий наследует его и переопределяет нужные функции.
--
-- api (передаёт MatchService):
--   api.map                       -- папка Workspace.Map
--   api.teams                     -- { "Bandits", "Gov" }
--   api.getTeamPlayers(team)      -- игроки команды
--   api.getTeamKey(player)        -- ключ команды игрока или nil
--   api.isAlive(player)           -- жив и на арене (не в лобби)
--   api.otherTeam(team)
--   api.teamName(team), api.teamColor(team)
--   api.setState(name, value)     -- атрибут состояния матча, его видит HUD
--   api.respawnAll()              -- возродить всех игроков команд
local ModeBase = {}
ModeBase.__index = ModeBase

function ModeBase.new(api, def)
	local self = setmetatable({}, ModeBase)
	self.api = api
	self.def = def
	self.score = {}
	for _, team in api.teams do
		self.score[team] = 0
	end
	return self
end

function ModeBase:PushScore()
	local a, b = self.api.teams[1], self.api.teams[2]
	self.api.setState("ScoreA", self.score[a])
	self.api.setState("ScoreB", self.score[b])
end

-- Матч начался, игроки уже распределены по командам.
function ModeBase:Start()
	self:PushScore()
	self.api.setState("Message", self.def.Description or self.def.DisplayName)
end

-- Вызывается примерно 5 раз в секунду.
function ModeBase:OnTick(_dt: number) end

-- Игрок зашёл посреди матча. true = сразу выпустить на арену.
function ModeBase:OnPlayerAdded(_player: Player): boolean
	return true
end

function ModeBase:OnPlayerRemoved(_player: Player) end

function ModeBase:OnPlayerKilled(_victim: Player, _killer: Player?) end

function ModeBase:CanRespawn(_player: Player): boolean
	return true
end

function ModeBase:GetRespawnDelay(): number
	return self.def.RespawnDelay or 3
end

-- Ключ команды-победителя, "Draw" или nil, если матч продолжается.
function ModeBase:GetWinner(): string?
	return nil
end

-- Кто победил, когда вышло общее время матча (def.Duration).
function ModeBase:GetTimeoutWinner(): string
	local a, b = self.api.teams[1], self.api.teams[2]
	if self.score[a] > self.score[b] then
		return a
	elseif self.score[b] > self.score[a] then
		return b
	end
	return "Draw"
end

function ModeBase:Cleanup() end

return ModeBase
