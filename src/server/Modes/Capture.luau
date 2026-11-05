-- «Капт»: одна команда атакует район, другая держит. Раунды без возрождения,
-- стороны меняются каждый раунд, матч до def.WinsNeeded побед.
-- Захват идёт, пока атакующих в зоне больше, чем защитников.
local ModeBase = require(script.Parent.ModeBase)

local GRACE_PERIOD = 3 -- секунд в начале раунда без проверки «все погибли» (игроки ещё появляются)

local Capture = setmetatable({}, { __index = ModeBase })
Capture.__index = Capture

function Capture.new(api, def)
	local self = setmetatable(ModeBase.new(api, def), Capture)
	self.round = 0
	self.attackers = api.teams[1]
	self.progress = 0
	self.timeLeft = 0
	self.elapsed = 0
	self.pause = nil
	self.winner = nil
	return self
end

function Capture:Start()
	local folder = self.api.map:FindFirstChild("CapturePoints")
	local points = if folder then folder:GetChildren() else {}
	assert(#points > 0, "На карте нет зон захвата (Workspace.Map.CapturePoints)")
	self.zone = points[math.random(#points)]
	self.zoneColor = self.zone.Color
	self.attackers = self.api.teams[math.random(2)]
	self:PushScore()
	self:_startRound()
end

function Capture:_defenders(): string
	return self.api.otherTeam(self.attackers)
end

function Capture:_startRound()
	local api = self.api
	self.round += 1
	self.progress = 0
	self.timeLeft = self.def.RoundTime
	self.elapsed = 0
	api.setState("Round", self.round)
	api.setState("Attackers", self.attackers)
	api.setState("CaptureProgress", 0)
	api.setState("ZoneName", self.zone.Name)
	api.setState("TimeLeft", self.timeLeft)
	api.setState("Message", string.format("Раунд %d: %s атакуют «%s»", self.round, api.teamName(self.attackers), self.zone.Name))
	self.zone.Color = api.teamColor(self.attackers)
end

function Capture:_inZone(player: Player): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local rel = self.zone.CFrame:PointToObjectSpace(root.Position)
	local size = self.zone.Size
	return math.abs(rel.X) <= size.X / 2 and math.abs(rel.Z) <= size.Z / 2 and rel.Y >= -2 and rel.Y <= 10
end

-- Возвращает (живых в команде, из них в зоне).
function Capture:_count(team: string): (number, number)
	local alive, inZone = 0, 0
	for _, player in self.api.getTeamPlayers(team) do
		if self.api.isAlive(player) then
			alive += 1
			if self:_inZone(player) then
				inZone += 1
			end
		end
	end
	return alive, inZone
end

function Capture:_endRound(team: string, reason: string)
	if self.api.onRoundWon then
		self.api.onRoundWon(team)
	end
	self.score[team] += 1
	self:PushScore()
	self.api.setState("Message", string.format("Раунд за командой «%s»: %s", self.api.teamName(team), reason))
	if self.score[team] >= self.def.WinsNeeded then
		self.winner = team
	else
		self.pause = self.def.PauseBetweenRounds
	end
end

function Capture:OnTick(dt: number)
	if self.winner then
		return
	end
	if self.pause then
		self.pause -= dt
		if self.pause <= 0 then
			self.pause = nil
			self.attackers = self:_defenders()
			self.api.respawnAll()
			self:_startRound()
		end
		return
	end

	self.elapsed += dt
	self.timeLeft -= dt
	self.api.setState("TimeLeft", math.max(0, math.ceil(self.timeLeft)))

	local attackers, defenders = self.attackers, self:_defenders()
	local attackersAlive, attackersInZone = self:_count(attackers)
	local defendersAlive, defendersInZone = self:_count(defenders)

	local rate = 100 / self.def.CaptureTime
	if attackersInZone > defendersInZone then
		-- Каждый лишний атакующий ускоряет захват на 25%.
		local bonus = 1 + 0.25 * (attackersInZone - defendersInZone - 1)
		self.progress = math.min(100, self.progress + rate * bonus * dt)
	elseif attackersInZone == 0 then
		self.progress = math.max(0, self.progress - rate * 0.5 * dt)
	end
	self.api.setState("CaptureProgress", math.floor(self.progress))

	if self.progress >= 100 then
		self:_endRound(attackers, "район захвачен")
	elseif self.timeLeft <= 0 then
		self:_endRound(defenders, "район удержан")
	elseif self.elapsed > GRACE_PERIOD then
		-- Проверку на уничтожение делаем, только когда в обеих командах есть игроки
		-- (иначе в Studio одному игроку раунд засчитывался бы мгновенно).
		local hasBoth = #self.api.getTeamPlayers(attackers) > 0 and #self.api.getTeamPlayers(defenders) > 0
		if hasBoth then
			if attackersAlive == 0 then
				self:_endRound(defenders, "атака уничтожена")
			elseif defendersAlive == 0 then
				self:_endRound(attackers, "защита уничтожена")
			end
		end
	end
end

-- Зашедшие посреди раунда ждут в лобби до следующего раунда.
function Capture:OnPlayerAdded(_player: Player): boolean
	return false
end

function Capture:CanRespawn(_player: Player): boolean
	return false
end

function Capture:GetWinner(): string?
	return self.winner
end

-- Боты обеих сторон идут в зону: атакующие захватывать, защитники держать.
function Capture:GetObjective(bot): Vector3?
	if not self.zone or self.pause then
		return nil
	end
	bot.zoneOffset = bot.zoneOffset
		or Vector3.new((math.random() - 0.5) * self.zone.Size.X * 0.6, 0, (math.random() - 0.5) * self.zone.Size.Z * 0.6)
	return self.zone.Position + bot.zoneOffset
end

function Capture:Cleanup()
	if self.zone then
		self.zone.Color = self.zoneColor
	end
end

return Capture
