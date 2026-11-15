-- Оформление карт: реалистичный свет, атмосфера, облака и «отделка» (окна, тротуары,
-- деревья, фонари, мелочь на улицах). Сама отделка — src/server/World/Detailer.luau,
-- свет — src/server/World/Ambience.luau, материалы и размытие в прицеле — src/client/Graphics.luau.
local Decor = {}

local rgb = Color3.fromRGB

------------------------------------------------------------------------
-- Свет и атмосфера. Default — для всех карт, по картам можно переопределить отдельные поля
-- (таблицы эффектов сливаются по полям). Lighting.LightingStyle = Realistic (бывший Technology = Future)
-- ставится в Studio (Properties) и хранится в месте: скрипт это свойство менять не может.
-- Фонари включаются сами, если ClockTime вечерний (см. Lamps ниже).
Decor.Lighting = {
	Default = {
		ClockTime = 14.2,
		GeographicLatitude = 41,
		Brightness = 3,
		ExposureCompensation = 0.1,
		Ambient = rgb(40, 42, 48),
		OutdoorAmbient = rgb(120, 122, 130),
		ColorShift_Top = rgb(255, 244, 228),
		ColorShift_Bottom = rgb(0, 0, 0),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		ShadowSoftness = 0.12,
		Atmosphere = { Density = 0.3, Offset = 0.2, Color = rgb(199, 205, 214), Decay = rgb(110, 120, 140), Glare = 0.35, Haze = 1.6 },
		ColorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = -0.08, TintColor = rgb(255, 250, 244) },
		Bloom = { Intensity = 0.5, Size = 26, Threshold = 1.7 },
		SunRays = { Intensity = 0.04, Spread = 0.55 },
		Clouds = { Cover = 0.55, Density = 0.6, Color = rgb(245, 245, 250) },
	},
	-- Промзона: пасмурно, плотный смог, холодные выцветшие цвета.
	Industrial = {
		ClockTime = 13.4,
		Brightness = 2.2,
		OutdoorAmbient = rgb(125, 128, 135),
		ColorShift_Top = rgb(225, 230, 240),
		Atmosphere = { Density = 0.42, Offset = 0.1, Color = rgb(170, 172, 170), Decay = rgb(95, 98, 100), Glare = 0, Haze = 2.6 },
		ColorCorrection = { Contrast = 0.14, Saturation = -0.22, TintColor = rgb(240, 245, 250) },
		SunRays = { Intensity = 0.01 },
		Clouds = { Cover = 0.85, Density = 0.75, Color = rgb(200, 202, 206) },
	},
	-- Спальный район: ясное утро, мягкое тёплое солнце, длинные тени.
	Suburb = {
		ClockTime = 9.3,
		Brightness = 3.2,
		ColorShift_Top = rgb(255, 230, 200),
		Atmosphere = { Density = 0.26, Haze = 1.2, Glare = 0.5, Color = rgb(205, 212, 225) },
		ColorCorrection = { Contrast = 0.1, Saturation = 0, TintColor = rgb(255, 248, 238) },
		SunRays = { Intensity = 0.07 },
		Clouds = { Cover = 0.4 },
	},
	-- Порт: закат над водой, горят фонари (ClockTime после Lamps.NightFrom).
	Port = {
		ClockTime = 18.1,
		Brightness = 2.4,
		ExposureCompensation = 0.25,
		Ambient = rgb(45, 40, 48),
		OutdoorAmbient = rgb(105, 95, 110),
		ColorShift_Top = rgb(255, 170, 110),
		Atmosphere = { Density = 0.36, Offset = 0.15, Color = rgb(215, 170, 140), Decay = rgb(120, 85, 95), Glare = 1.2, Haze = 2 },
		ColorCorrection = { Contrast = 0.15, Saturation = 0.05, TintColor = rgb(255, 238, 225) },
		Bloom = { Intensity = 0.8, Size = 30, Threshold = 1.4 },
		SunRays = { Intensity = 0.12, Spread = 0.7 },
		Clouds = { Cover = 0.6, Density = 0.5, Color = rgb(255, 205, 180) },
	},
	-- Деревня: летний день после обеда, тёплый и насыщенный.
	Village = {
		ClockTime = 16.2,
		ColorShift_Top = rgb(255, 225, 185),
		Atmosphere = { Density = 0.28, Haze = 1.4, Glare = 0.6, Color = rgb(210, 210, 200), Decay = rgb(130, 125, 110) },
		ColorCorrection = { Contrast = 0.1, Saturation = 0.06, TintColor = rgb(255, 246, 232) },
		SunRays = { Intensity = 0.08 },
		Clouds = { Cover = 0.45 },
	},
}

------------------------------------------------------------------------
-- Отделка зданий и элементов: окна, карнизы, двери, рёбра контейнеров, столбы заборов.
Decor.Detail = true
Decor.LitWindows = false -- светящиеся окна (для ночных карт)

-- Тротуары с бордюром вдоль асфальтовых дорог и прерывистая разметка.
Decor.Sidewalks = {
	Enabled = true,
	Width = 3,
	Height = 0.25,
	Color = rgb(150, 148, 142),
	CurbColor = rgb(185, 183, 176),
}
Decor.RoadMarkings = true

-- Фонари вдоль асфальтовых дорог: шаг в студах. Свет включается, только если
-- Lighting.ClockTime вечерний (см. Lamps.NightFrom/NightTo).
Decor.Lamps = { Enabled = true, Spacing = 60, NightFrom = 18, NightTo = 6.5 }

-- Деревья и кусты (меши из Creator Store, см. World/DecorAssets.luau) и уличная мелочь
-- (бочки, мусорные баки, поддоны, покрышки, скамейки, кучи плит). Числа — сколько штук на карту.
--   Oak / Spruce / Bush — деревья и кусты; сквозь куст можно пройти, ствол дерева твёрдый.
--   Clutter — мелочь-укрытия, твёрдая (бочки, баки, поддоны, покрышки, мешки, диваны, плиты...).
Decor.Scatter = {
	Default = { Oak = 70, Spruce = 30, Bush = 120, Clutter = 110 },
	Industrial = { Oak = 55, Spruce = 20, Bush = 140, Clutter = 260 },
	Suburb = { Oak = 130, Spruce = 40, Bush = 220, Clutter = 140 },
	Port = { Oak = 30, Spruce = 12, Bush = 90, Clutter = 260 },
	Village = { Oak = 140, Spruce = 110, Bush = 240, Clutter = 70 },
}
-- Пятна на земле, чтобы она не была однотонной: трава, земля, тёмные пятна (масло, сырость),
-- светлые заплатки. Плоские, без столкновений. Числа — сколько пятен на карту.
Decor.Patches = {
	Default = { Grass = 60, Dirt = 60, Stain = 30, Light = 20 },
	Industrial = { Grass = 70, Dirt = 90, Stain = 90, Light = 40 },
	Suburb = { Grass = 0, Dirt = 80, Stain = 10, Light = 50 },
	Port = { Grass = 30, Dirt = 50, Stain = 110, Light = 50 },
	Village = { Grass = 0, Dirt = 110, Stain = 0, Light = 60 },
}

-- Улицы вдоль асфальтовых дорог: шаг в студах для каждого вида (0 или нет поля — выключено).
--   Bins урны, Signs дорожные знаки, Poles столбы ЛЭП с проводами, Trees деревья вдоль улицы,
--   Hydrants гидранты, BusStops остановки, Kiosks киоски, Billboards рекламные щиты,
--   Hedges живые изгороди, Crosswalks пешеходные переходы («зебра» и знаки).
-- Всё ставится только на свободные места: не на дорогу, не в дома, не на перекрёсток.
Decor.Street = {
	Default = { Bins = 34, Signs = 95, Poles = 0, Trees = 30, Hydrants = 120, BusStops = 280, Kiosks = 210, Billboards = 320, Hedges = 70, Crosswalks = 170 },
	Industrial = { Bins = 50, Signs = 90, Poles = 70, Trees = 55, Hydrants = 110, BusStops = 340, Kiosks = 260, Billboards = 240, Hedges = 0, Crosswalks = 220 },
	Suburb = { Bins = 30, Signs = 90, Poles = 0, Trees = 24, Hydrants = 110, BusStops = 230, Kiosks = 170, Billboards = 300, Hedges = 48, Crosswalks = 150 },
	Port = { Bins = 50, Signs = 90, Poles = 80, Trees = 60, Hydrants = 120, BusStops = 360, Kiosks = 280, Billboards = 260, Hedges = 0, Crosswalks = 240 },
	Village = { Bins = 0, Signs = 140, Poles = 60, Trees = 0, Hydrants = 0, BusStops = 400, Kiosks = 0, Billboards = 0, Hedges = 0, Crosswalks = 0 },
}

-- Дворы у домов: контейнерные площадки и мешки с мусором у задних стен, таблички с адресом,
-- граффити внизу стен. Числа — вероятность для каждого дома (0..1).
Decor.Yards = {
	Default = { Trash = 0.55, Address = 0.6, Graffiti = 0.25 },
	Industrial = { Trash = 0.45, Address = 0.35, Graffiti = 0.35 },
	Suburb = { Trash = 0.6, Address = 0.7, Graffiti = 0.25 },
	Port = { Trash = 0.4, Address = 0.3, Graffiti = 0.35 },
	Village = { Trash = 0, Address = 0.5, Graffiti = 0 },
}

-- Как выглядят базы команд (World/BaseStyles.luau): Police — полицейский участок, Ghetto — район гетто.
-- Уберите команду из списка, чтобы вернуть простую базу со стенами и флагом.
Decor.BaseStyle = { Gov = "Police", Bandits = "Ghetto" }

Decor.TreeScale = { 0.55, 0.85 } -- деревья из пака высотой ~35 студов, уменьшаем до 19–30
Decor.LeafColors = { rgb(98, 140, 62), rgb(112, 152, 66), rgb(86, 124, 58), rgb(128, 150, 70) }

return Decor
