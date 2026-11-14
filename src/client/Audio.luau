-- Звуки на клиенте: выстрелы и удары в точке мира, звуки интерфейса.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SoundsConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds)

local Audio = {}

type Cfg = { Id: string, Volume: number?, Pitch: number?, Range: number? }

-- Звук в точке мира: слышен тише с расстоянием, пропадает дальше Range.
function Audio.at(cfg: Cfg?, position: Vector3)
	if not cfg or cfg.Id == "" then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = cfg.Id
	s.Volume = cfg.Volume or 0.8
	s.PlaybackSpeed = (cfg.Pitch or 1) * (0.95 + math.random() * 0.1) -- небольшой разброс, чтобы очередь не звучала одинаково
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = cfg.Range or 200
	s.Parent = anchor
	s:Play()
	-- Убираем после окончания звука (длинные выстрелы снайперки идут дольше 3 секунд).
	Debris:AddItem(anchor, 8)
	s.Ended:Once(function()
		anchor:Destroy()
	end)
end

-- Звук без положения (интерфейс, свои действия).
function Audio.ui(cfg: Cfg?)
	if not cfg or cfg.Id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = cfg.Id
	s.Volume = cfg.Volume or 0.5
	s.PlaybackSpeed = cfg.Pitch or 1
	SoundService:PlayLocalSound(s)
	Debris:AddItem(s, 3)
end

function Audio.shot(weaponId: string?, position: Vector3)
	local cfg = (weaponId and SoundsConfig.Shots[weaponId]) or SoundsConfig.DefaultShot
	Audio.at(cfg, position)
end

Audio.Config = SoundsConfig

return Audio
