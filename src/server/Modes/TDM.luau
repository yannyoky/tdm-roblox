-- «Перестрелка»: классический командный бой до лимита убийств или конца времени.
local ModeBase = require(script.Parent.ModeBase)

local TDM = setmetatable({}, { __index = ModeBase })
TDM.__index = TDM

function TDM.new(api, def)
	return setmetatable(ModeBase.new(api, def), TDM)
end

function TDM:OnPlayerKilled(victim: Player, killer: Player?)
	if not killer or killer == victim then
		return
	end
	local killerTeam = self.api.getTeamKey(killer)
	local victimTeam = self.api.getTeamKey(victim)
	if killerTeam and victimTeam and killerTeam ~= victimTeam then
		self.score[killerTeam] += 1
		self:PushScore()
	end
end

function TDM:GetWinner(): string?
	for team, score in self.score do
		if score >= self.def.ScoreLimit then
			return team
		end
	end
	return nil
end

return TDM
