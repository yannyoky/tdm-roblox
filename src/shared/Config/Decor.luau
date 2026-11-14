-- Оформление карт в обычной графике Roblox: свет, атмосфера и «отделка» (окна, тротуары,
-- деревья, фонари, мелочь на улицах). Сама отделка — src/server/World/Detailer.luau.
-- Реалистичная графика живёт в отдельной ветке и сюда не входит.
local Decor = {}

local rgb = Color3.fromRGB

------------------------------------------------------------------------
-- Свет и атмосфера. Default — для всех карт, по картам можно переопределить отдельные поля.
-- Технологию освещения (Lighting.Technology) скрипт менять не может: в Studio выберите
-- Lighting → Technology = ShadowMap (чёткие тени, дёшево) или Future.
Decor.Lighting = {
	Default = {
		ClockTime = 14.2,
		GeographicLatitude = 35,
		Brightness = 2.6,
		Ambient = rgb(70, 70, 78),
		OutdoorAmbient = rgb(128, 128, 136),
		ColorShift_Top = rgb(255, 244, 225),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.6,
		ShadowSoftness = 0.25,
		ExposureCompensation = 0.1,
		-- Атмосфера: лёгкая дымка, даль уходит в голубой.
		Atmosphere = { Density = 0.22, Offset = 0.1, Color = rgb(199, 214, 230), Decay = rgb(120, 140, 165), Glare = 0.2, Haze = 1.4 },
		-- Цветокоррекция: чуть больше контраста и цвета, тёплый оттенок.
		ColorCorrection = { Brightness = 0.01, Contrast = 0.1, Saturation = 0.12, TintColor = rgb(255, 250, 242) },
		Bloom = { Intensity = 0.35, Size = 24, Threshold = 1.6 },
		SunRays = { Intensity = 0.06, Spread = 0.7 },
	},
	Industrial = { ClockTime = 15.5, Atmosphere = { Density = 0.25, Offset = 0.08, Color = rgb(205, 205, 200), Decay = rgb(140, 135, 125), Glare = 0.15, Haze = 2 } },
	Suburb = { ClockTime = 13.5 },
	Port = { ClockTime = 16.2, Atmosphere = { Density = 0.24, Offset = 0.1, Color = rgb(190, 210, 228), Decay = rgb(110, 135, 165), Glare = 0.3, Haze = 1.6 } },
	Village = { ClockTime = 12.5, ColorCorrection = { Brightness = 0.01, Contrast = 0.08, Saturation = 0.18, TintColor = rgb(255, 252, 240) } },
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
--   Clutter — мелочь-укрытия, твёрдая.
Decor.Scatter = {
	Default = { Oak = 40, Spruce = 20, Bush = 60, Clutter = 60 },
	Industrial = { Oak = 25, Spruce = 10, Bush = 70, Clutter = 170 },
	Suburb = { Oak = 70, Spruce = 25, Bush = 110, Clutter = 60 },
	Port = { Oak = 12, Spruce = 6, Bush = 40, Clutter = 170 },
	Village = { Oak = 90, Spruce = 70, Bush = 140, Clutter = 40 },
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

Decor.TreeScale = { 0.55, 0.85 } -- деревья из пака высотой ~35 студов, уменьшаем до 19–30
Decor.LeafColors = { rgb(98, 140, 62), rgb(112, 152, 66), rgb(86, 124, 58), rgb(128, 150, 70) }

return Decor
