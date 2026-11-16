-- Открытый город: карта «Город» (City) в общей ротации TDM и капта. Сетка улиц, кварталы, светофоры, день и ночь, погода.
-- Геометрия сетки считается в src/shared/CityGrid.luau (её же читают трафик и пешеходы),
-- собирает город src/server/World/CityBuilder.luau.
--
-- Сетка: Blocks × Blocks кварталов, между ними и по краю улицы шириной RoadWidth.
-- Север (-Z) сверху, строки Lots идут с севера на юг, столбцы с запада на восток.
local rgb = Color3.fromRGB

local City = {}

City.MapId = "City"

City.Blocks = 5 -- кварталов по каждой оси
City.BlockSize = 176 -- сторона квартала вместе с тротуаром
City.LaneWidth = 10 -- ширина полосы
City.LanesPerDirection = 2 -- полос в каждую сторону (можно перестраиваться)
City.Median = 2 -- двойная сплошная посередине
City.RoadWidth = City.LaneWidth * City.LanesPerDirection * 2 + City.Median + 2 -- + обочины по 1
City.SidewalkWidth = 12
City.CurbHeight = 0.4 -- тротуар и кварталы выше дороги на столько
City.Margin = 70 -- полоса зелени за внешней улицей до края карты

-- Кварталы. Виды:
--   downtown    -- высотки со стеклянными фасадами, внизу магазины
--   commercial  -- магазины и кафе по периметру, во дворе служебная парковка
--   residential -- панельные дома по краям, двор с деревьями, лавочками и площадкой
--   gas         -- заправка: навес с колонками, магазин, стела с ценами
--   parking     -- открытая парковка с разметкой мест
--   park        -- парк: газон, дорожки, фонтан, деревья, скамейки
--   base:Bandits / base:Gov -- база стороны (гетто / полицейский участок), ворота смотрят на Gate
City.Lots = {
	{ "base:Bandits", "residential", "commercial", "residential", "gas" },
	{ "residential", "commercial", "downtown", "commercial", "parking" },
	{ "gas", "downtown", "park", "downtown", "residential" },
	{ "parking", "commercial", "downtown", "commercial", "residential" },
	{ "residential", "residential", "commercial", "park", "base:Gov" },
}
-- В какую сторону смотрят ворота базы: "N" | "S" | "E" | "W".
City.BaseGate = { Bandits = "S", Gov = "N" }

-- Зоны каптов: квартал (col, row) и размер зоны вокруг его центра.
-- Центральный парк спорный, у каждой стороны по «своему» торговому двору поближе.
City.Zones = {
	{ Name = "Центральный парк", col = 3, row = 3, w = 64, d = 64 },
	{ Name = "Рынок", col = 2, row = 2, w = 84, d = 84 },
	{ Name = "Торговый двор", col = 4, row = 4, w = 84, d = 84 },
}

-- Передовые точки появления для TDM: квартал и сдвиг от его центра.
City.Forward = {
	Bandits = { col = 2, row = 1, dx = 0, dz = 0 },
	Gov = { col = 4, row = 5, dx = 0, dz = -48 },
}

City.Seed = 7 -- зерно расстановки внутри кварталов

-- Высотки в центре.
City.Towers = {
	Height = { 60, 130 },
	FloorHeight = 10,
	Glass = { rgb(56, 74, 92), rgb(70, 86, 98), rgb(48, 58, 70), rgb(84, 96, 102) },
	Frame = { rgb(190, 192, 195), rgb(120, 124, 130), rgb(60, 62, 66) },
}

-- Светофоры. Цикл: зелёный по оси север–юг, жёлтый, все красные, то же для востока–запада.
-- Offset — сдвиг цикла на перекрёсток (секунды на шаг сетки): «зелёная волна».
City.Signals = {
	Green = 14,
	Yellow = 3,
	AllRed = 2,
	Offset = 3,
}

------------------------------------------------------------------------
-- Трафик (только в режиме «Город», атрибут CityLife). Машины едут по полосам, стоят на красный,
-- пропускают встречных при левом повороте, тормозят перед людьми и машинами, перестраиваются,
-- чтобы объехать стоящее препятствие. Код — src/server/World/Traffic.luau.
City.Traffic = {
	Cars = 18,
	Types = { "Bandits_Sedan", "Bandits_Sedan", "Bandits_Van", "Bandits_Pickup", "Gov_SUV" },
	Mass = 350, -- чем тяжелее, тем труднее её столкнуть
	Speed = 38, -- студ/с на прямой (≈ км/ч)
	TurnSpeed = 15, -- в повороте
	Accel = 11,
	Decel = 24,
	LaneChangeSpeed = 6, -- студ/с вбок при перестроении
	SpawnAwayFromPlayers = 70, -- не появляются ближе к игрокам
	TurnChance = { Straight = 0.6, Left = 0.2, Right = 0.2 },
}

------------------------------------------------------------------------
-- Прохожие (только в режиме «Город», атрибут CityLife). Ходят по тротуарам вокруг кварталов
-- (маршрут строит PathfindingService), переходят улицу по зебре на зелёного человечка,
-- садятся на скамейки, останавливаются поболтать, уступают дорогу, отскакивают от машин,
-- разбегаются от выстрелов. Код — src/server/World/Pedestrians.luau.
City.Pedestrians = {
	Count = 22,
	WalkSpeed = { 5.5, 8 }, -- у каждого своя походка
	RunSpeed = 17, -- когда напуган
	WalkLine = 7.5, -- от бордюра до линии, по которой идут (тротуар 12)
	SpawnAwayFromPlayers = 60,
	-- Что делать на углу квартала (веса).
	Choice = { Walk = 0.55, Cross = 0.3, Sit = 0.15 },
	SitTime = { 12, 35 },
	TalkChance = 0.3, -- при встрече с другим прохожим
	TalkTime = { 5, 10 },
	TalkCooldown = 45,
	CrossMinWalk = 6, -- переходить, только если «идите» горит ещё столько секунд
	PanicRadius = 90, -- слышат выстрел
	PanicTime = 12,
	DodgeDistance = 14, -- отскок от машины, едущей прямо на него
	-- Одежда — из гардероба Config/Appearance (Bandits), только повседневные вещи.
	Wear = {
		Top = { "tee_black", "tee_gray", "knit", "leather_brown", "gray_hood", "puffer", "hoodie" },
		Bottom = { "jeans", "jeans_black", "cargo_brown", "sweats_gray", "baggy" },
		Shoes = { "sneakers_white", "sneakers_gray", "running", "canvas", "work_tan" },
		Hat = { "cap", "beanie" },
		HatChance = 0.25,
	},
}

------------------------------------------------------------------------
-- Смена дня и ночи. Работает на картах с DayNight = true (город).

City.DayNight = {
	Enabled = true,
	DayMinutes = 24, -- реальных минут на полные игровые сутки
	StartTime = 9, -- во сколько начинается матч
	-- Ночью горит такая доля окон домов (и полосы окон в высотках).
	LitWindows = 0.35,
	LitColor = rgb(196, 128, 66), -- Neon светится ярче цвета: тёмно-оранжевый даёт тёплый жёлтый свет
	-- Уличные фонари в городе ярче, чем на остальных картах.
	LampRange = 60,
	LampBrightness = 6,
	-- Свет днём и ночью; между ними плавный переход по высоте солнца.
	Day = {
		Brightness = 3,
		ExposureCompensation = 0.1,
		Ambient = rgb(40, 42, 48),
		OutdoorAmbient = rgb(120, 122, 130),
		AtmosphereColor = rgb(199, 205, 214),
		AtmosphereDecay = rgb(110, 120, 140),
		Tint = rgb(248, 250, 255),
	},
	Dusk = {
		Brightness = 2.2,
		ExposureCompensation = 0.25,
		Ambient = rgb(50, 42, 48),
		OutdoorAmbient = rgb(110, 92, 100),
		AtmosphereColor = rgb(220, 170, 140),
		AtmosphereDecay = rgb(120, 80, 90),
		Tint = rgb(255, 228, 205),
	},
	Night = {
		Brightness = 1.1,
		ExposureCompensation = 0.85,
		Ambient = rgb(48, 54, 70),
		OutdoorAmbient = rgb(78, 88, 116),
		AtmosphereColor = rgb(46, 54, 74),
		AtmosphereDecay = rgb(34, 40, 58),
		Tint = rgb(210, 220, 255),
	},
}

------------------------------------------------------------------------
-- Погода. Сервер выбирает погоду по весам и держит её Duration секунд, переходы плавные.
-- Дождь (капли, звук, мокрый асфальт, молнии) рисует клиент: src/client/Weather.luau.

City.Weather = {
	Enabled = true,
	Duration = { 150, 300 }, -- сколько держится погода (секунды)
	Transition = 25, -- секунд на плавный переход
	States = {
		Clear = { Weight = 4, Rain = 0, Clouds = 0.35, CloudDensity = 0.45, Haze = 1.4, Density = 0.28, Light = 1 },
		Cloudy = { Weight = 3, Rain = 0, Clouds = 0.8, CloudDensity = 0.7, Haze = 2, Density = 0.34, Light = 0.8 },
		Rain = { Weight = 2, Rain = 0.6, Clouds = 0.95, CloudDensity = 0.85, Haze = 2.6, Density = 0.4, Light = 0.62 },
		Storm = { Weight = 1, Rain = 1, Clouds = 1, CloudDensity = 1, Haze = 3, Density = 0.46, Light = 0.48, Lightning = true },
	},
	Start = "Clear",
	-- Клиент.
	Drops = 450, -- капель вокруг камеры при сильнейшем дожде
	DropRadius = 70,
	DropSpeed = 95,
	WetReflectance = 0.16, -- блеск мокрого асфальта
	-- Звуки (rbxassetid). 0 — без звука.
	RainSound = 0,
	ThunderSound = 0,
}

return City
