-- Звуки на клиенте: выстрелы и удары в точке мира, звуки интерфейса.
--
-- Почему звуки заранее загружаются: если создать новый Sound и сразу вызвать Play, Roblox сначала
-- скачивает звук и только потом играет, поэтому первый выстрел (и первое попадание) звучали
-- с задержкой. Теперь при входе в игру для каждого звука создаётся загруженный образец
-- в SoundService (ContentProvider:PreloadAsync), а при выстреле играется его копия — мгновенно.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local SoundsConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds)

local Audio = {}

type Cfg = { Id: string, Volume: number?, Pitch: number?, Range: number? }

local folder = Instance.new("Folder")
folder.Name = "PreloadedSounds"
folder.Parent = SoundService

-- Загруженные образцы по SoundId.
local templates: { [string]: Sound } = {}

local function template(soundId: string): Sound
	local t = templates[soundId]
	if not t then
		t = Instance.new("Sound")
		t.Name = soundId
		t.SoundId = soundId
		t.Volume = 0
		t.Parent = folder
		templates[soundId] = t
	end
	return t
end

-- Новый Sound из загруженного образца (копия загруженного звука играет без ожидания).
local function newSound(soundId: string): Sound
	local s = template(soundId):Clone()
	s.Name = "Sound"
	return s
end

local function collectIds(value: any, out: { string })
	if type(value) == "string" then
		if string.find(value, "^rbxasset") then
			table.insert(out, value)
		end
	elseif type(value) == "table" then
		for _, v in value do
			collectIds(v, out)
		end
	end
end

-- Загружает все звуки из Config/Sounds. Вызывается один раз при запуске клиента.
function Audio.preload()
	local ids = {}
	collectIds(SoundsConfig, ids)
	local list = {}
	for _, soundId in ids do
		table.insert(list, template(soundId))
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		if not ok then
			warn("[Audio] не удалось заранее загрузить звуки:", err)
		end
		-- Короткое беззвучное проигрывание «прогревает» звук, чтобы первый выстрел не подвисал.
		for _, t in list do
			t.Volume = 0
			t:Play()
			task.delay(0.1, function()
				t:Stop()
			end)
		end
	end)
end

-- Звук в точке мира: слышен тише с расстоянием, пропадает дальше Range.
function Audio.at(cfg: Cfg?, position: Vector3)
	if not cfg or cfg.Id == "" then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	local s = newSound(cfg.Id)
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

-- Звук без положения: Sound внутри SoundService играет одинаково громко где угодно.
local function playFlat(soundId: string, volume: number, speed: number, lifetime: number)
	local s = newSound(soundId)
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.Parent = folder
	s:Play()
	Debris:AddItem(s, lifetime)
	s.Ended:Once(function()
		s:Destroy()
	end)
end

-- Звук интерфейса и своих действий.
function Audio.ui(cfg: Cfg?)
	if not cfg or cfg.Id == "" then
		return
	end
	playFlat(cfg.Id, cfg.Volume or 0.5, cfg.Pitch or 1, 3)
end

function Audio.shot(weaponId: string?, position: Vector3)
	local cfg = (weaponId and SoundsConfig.Shots[weaponId]) or SoundsConfig.DefaultShot
	Audio.at(cfg, position)
end

-- Свой выстрел: звучит сразу, без ожидания ответа сервера, и не зависит от положения.
function Audio.shotLocal(weaponId: string?)
	local cfg = (weaponId and SoundsConfig.Shots[weaponId]) or SoundsConfig.DefaultShot
	if not cfg or cfg.Id == "" then
		return
	end
	playFlat(cfg.Id, (cfg.Volume or 0.8) * 0.85, (cfg.Pitch or 1) * (0.96 + math.random() * 0.08), 4)
end

-- Звук попадания. Клиент играет его сам, как только его луч попал во врага (predicted = true),
-- не дожидаясь сервера. Подтверждение сервера после этого звук не повторяет.
local PREDICT_WINDOW = 0.6
local lastPredicted = -math.huge
local hitListeners: { (boolean) -> () } = {}

function Audio.onHit(fn: (isHead: boolean) -> ())
	table.insert(hitListeners, fn)
end

function Audio.hit(isHead: boolean, predicted: boolean)
	local now = os.clock()
	if predicted then
		lastPredicted = now
	elseif now - lastPredicted < PREDICT_WINDOW then
		return -- уже сыграно сразу при выстреле
	end
	Audio.ui(SoundsConfig.HitMarker)
	for _, fn in hitListeners do
		task.spawn(fn, isHead)
	end
end

Audio.Config = SoundsConfig

return Audio
