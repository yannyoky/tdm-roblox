-- «Город»: свободная прогулка по открытому городу. Без счёта и победителя: матч идёт до конца
-- времени (Duration), потом итоги и новое голосование. Стороны остаются, стрелять друг в друга можно.
-- Прохожие и трафик включаются по атрибуту ReplicatedStorage.CityLife (ставит MatchService по def.CityLife).
local ModeBase = require(script.Parent.ModeBase)

local FreeRoam = setmetatable({}, { __index = ModeBase })
FreeRoam.__index = FreeRoam

function FreeRoam.new(api, def)
	return setmetatable(ModeBase.new(api, def), FreeRoam)
end

function FreeRoam:Start()
	self:PushScore()
	self.api.setState("Message", "Свободная прогулка: машины, светофоры, день и ночь, погода")
end

function FreeRoam:GetTimeoutWinner(): string
	return "Draw"
end

return FreeRoam
