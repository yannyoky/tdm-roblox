-- «Город»: свободная прогулка по открытому городу. Без счёта и победителя: матч идёт до конца
-- времени (Duration), потом итоги и новое голосование. Стороны остаются, стрелять друг в друга можно.
-- Прохожие и трафик включаются по атрибуту ReplicatedStorage.CityLife (ставит MatchService по def.CityLife).
local ModeBase = require(script.Parent.ModeBase)

local FreeRoam = setmetatable({}, { __index = ModeBase })
FreeRoam.__index = FreeRoam

function FreeRoam.new(api, def)
	return setmetatable(ModeBase.new(api, def), FreeRoam)
end

-- Зоны каптов в прогулке не нужны: прячем, после режима возвращаем.
local function showZones(map: Instance?, visible: boolean)
	local points = map and map:FindFirstChild("CapturePoints")
	for _, p in if points then points:GetChildren() else {} do
		if p:IsA("BasePart") then
			if p:GetAttribute("ZoneTransparency") == nil then
				p:SetAttribute("ZoneTransparency", p.Transparency)
			end
			p.Transparency = if visible then p:GetAttribute("ZoneTransparency") else 1
		end
	end
end

function FreeRoam:Start()
	showZones(self.api.map, false)
	self:PushScore()
	self.api.setState("Message", "Свободная прогулка: машины, светофоры, день и ночь, погода")
end

function FreeRoam:Cleanup()
	showZones(self.api.map, true)
end

function FreeRoam:GetTimeoutWinner(): string
	return "Draw"
end

return FreeRoam
