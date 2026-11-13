-- Реалистичная графика (ветка graphics). В обычной ветке этого файла нет.
--
-- Что где:
--   default.project.json        -- Lighting.Technology = Future (из скрипта его поменять нельзя, только так или в Studio)
--   src/client/Graphics.luau    -- освещение, атмосфера, пост-эффекты, туман, облака; у каждого игрока свой переключатель
--   src/server/World/Realism.luau -- земля из Terrain с травой, фонари, свет в зданиях, фары машин
--
-- Настроение (Mood) выбирается по карте. Цвета — Color3.fromRGB, время — часы (14.5 = 14:30).
-- Подбирать значения удобнее всего в Studio: запустите Play, меняйте свойства Lighting/Atmosphere
-- в Explorer, а удачные числа перенесите сюда.

local rgb = Color3.fromRGB

local Graphics = {}

-- Свои PBR-материалы. Создайте в MaterialService объект MaterialVariant с таким именем
-- (BaseMaterial = ключ слева, текстуры ColorMap/NormalMap/RoughnessMap/MetalnessMap),
-- и все детали этого материала в игре станут им. Нет варианта — остаётся стандартный материал.
-- Если варианта с таким именем нет, берётся любой MaterialVariant из MaterialService с тем же
-- BaseMaterial. Так бесплатный пак материалов из Toolbox работает сразу, без переименования.
Graphics.AutoPickMaterialVariants = true

Graphics.MaterialOverrides = {
	[Enum.Material.Concrete] = "Real_Concrete",
	[Enum.Material.Brick] = "Real_Brick",
	[Enum.Material.Asphalt] = "Real_Asphalt",
	[Enum.Material.WoodPlanks] = "Real_WoodPlanks",
	[Enum.Material.CorrodedMetal] = "Real_RustyMetal",
	[Enum.Material.Metal] = "Real_Metal",
	[Enum.Material.DiamondPlate] = "Real_DiamondPlate",
	[Enum.Material.Grass] = "Real_Grass",
	[Enum.Material.Sand] = "Real_Sandbags",
	[Enum.Material.Fabric] = "Real_Fabric",
}

-- Земля из Terrain вместо одной большой детали: трава шевелится, есть переходы, лучше свет.
Graphics.TerrainGround = true
-- Травинки на Terrain Grass. Низкие, но немного прячут ползущих раненых.
Graphics.GrassDecoration = true

-- Отделка карты (World/Detailer.luau): окна, карнизы, двери, рёбра контейнеров, тротуары и т. д.
Graphics.Detail = true

-- Тротуары с бордюром вдоль дорог (твёрдые, высота как у ступеньки) и разметка.
Graphics.Sidewalks = {
	Enabled = true,
	Width = 3,
	Height = 0.35,
	Color = rgb(150, 148, 142),
	CurbColor = rgb(185, 183, 176),
}
Graphics.RoadMarkings = true

-- Готовые модели (бесплатные из Toolbox или свои из Blender) кладутся в ServerStorage/RealisticModels:
--   Container, Crate, StreetLamp -- модель (или папка с несколькими моделями) заменяет процедурную
--   Trees, Bushes, Clutter       -- папки с моделями, они расставляются по карте (числа ниже)
-- Нет папки или модели — остаётся процедурная отделка.
Graphics.ScatterSlots = {
	Trees = { Height = { 18, 30 }, Clearance = 6, Collider = 2 },
	Bushes = { Height = { 3, 5 }, Clearance = 3 }, -- сквозь кусты можно пройти и прострелить
	Clutter = { Height = { 3, 5 }, Clearance = 3, Solid = true }, -- бочки, баки, поддоны: укрытие
}
Graphics.Scatter = {
	Default = { Trees = 20, Bushes = 20, Clutter = 20 },
	Industrial = { Trees = 10, Bushes = 15, Clutter = 60 },
	Suburb = { Trees = 60, Bushes = 50, Clutter = 30 },
	Port = { Trees = 5, Bushes = 10, Clutter = 60 },
	Village = { Trees = 90, Bushes = 70, Clutter = 20 },
}

-- Фонари вдоль дорог.
Graphics.StreetLamps = {
	Enabled = true,
	Spacing = 70, -- студов между фонарями
	Height = 14,
	Color = rgb(255, 200, 140),
	Brightness = 2.2,
	Range = 38,
}

-- Свет под потолком в зданиях с интерьером (ящик освещения на крыше не виден снаружи).
Graphics.InteriorLights = {
	Enabled = true,
	Color = rgb(255, 225, 185),
	Brightness = 1.4,
	Range = 22,
}

-- Фары машин.
Graphics.Headlights = {
	Color = rgb(255, 245, 225),
	Brightness = 3,
	Range = 55,
	Angle = 55,
}

-- Глубина резкости.
Graphics.DepthOfField = {
	-- Лёгкое размытие дальнего плана (выключается настройкой «Размытие вдали»).
	-- Ограничения Roblox: FocusDistance 0..200, InFocusRadius 0..50.
	FarIntensity = 0.12,
	FocusDistance = 150,
	InFocusRadius = 50,
	-- В прицеле фокус переезжает на то, куда смотрит игрок, а ближнее (своё оружие) размывается.
	AimNearIntensity = 0.35,
	AimFarIntensity = 0.06,
	AimInFocusRadius = 25,
}

-- Настроения по картам. Поля:
--   Lighting       -- свойства Lighting (ClockTime, Brightness, Ambient, ...)
--   Atmosphere     -- дымка и цвет неба у горизонта
--   ColorCorrection, Bloom, SunRays -- пост-эффекты
--   Clouds         -- облака Terrain.Clouds (Cover 0..1)
--   LampsOn        -- включить фонари и свет в зданиях
local DAY = {
	Lighting = {
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
	},
	Atmosphere = { Density = 0.3, Offset = 0.2, Color = rgb(199, 205, 214), Decay = rgb(110, 120, 140), Glare = 0.35, Haze = 1.6 },
	ColorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = -0.08, TintColor = rgb(255, 250, 244) },
	Bloom = { Intensity = 0.5, Size = 26, Threshold = 1.7 },
	SunRays = { Intensity = 0.04, Spread = 0.55 },
	Clouds = { Cover = 0.55, Density = 0.6, Color = rgb(245, 245, 250) },
	LampsOn = false,
}

local function variant(base, changes)
	local t = table.clone(base)
	for group, fields in changes do
		if type(fields) == "table" and type(t[group]) == "table" then
			local merged = table.clone(t[group])
			for k, v in fields do
				merged[k] = v
			end
			t[group] = merged
		else
			t[group] = fields
		end
	end
	return t
end

Graphics.Moods = {
	Default = DAY,

	-- Промзона: пасмурно, плотный смог, холодные выцветшие цвета.
	Industrial = variant(DAY, {
		Lighting = { ClockTime = 13.4, Brightness = 2.2, OutdoorAmbient = rgb(125, 128, 135), ColorShift_Top = rgb(225, 230, 240) },
		Atmosphere = { Density = 0.42, Offset = 0.1, Color = rgb(170, 172, 170), Decay = rgb(95, 98, 100), Glare = 0, Haze = 2.6 },
		ColorCorrection = { Contrast = 0.14, Saturation = -0.22, TintColor = rgb(240, 245, 250) },
		SunRays = { Intensity = 0.01 },
		Clouds = { Cover = 0.85, Density = 0.75, Color = rgb(200, 202, 206) },
	}),

	-- Спальный район: ясное утро, мягкое тёплое солнце, длинные тени.
	Suburb = variant(DAY, {
		Lighting = { ClockTime = 9.3, Brightness = 3.2, ColorShift_Top = rgb(255, 230, 200) },
		Atmosphere = { Density = 0.26, Haze = 1.2, Glare = 0.5, Color = rgb(205, 212, 225) },
		ColorCorrection = { Contrast = 0.1, Saturation = 0, TintColor = rgb(255, 248, 238) },
		SunRays = { Intensity = 0.07 },
		Clouds = { Cover = 0.4 },
	}),

	-- Порт: вечер, закат над водой, горят фонари.
	Port = variant(DAY, {
		Lighting = {
			ClockTime = 18.1,
			Brightness = 2.4,
			ExposureCompensation = 0.25,
			Ambient = rgb(45, 40, 48),
			OutdoorAmbient = rgb(105, 95, 110),
			ColorShift_Top = rgb(255, 170, 110),
		},
		Atmosphere = { Density = 0.36, Offset = 0.15, Color = rgb(215, 170, 140), Decay = rgb(120, 85, 95), Glare = 1.2, Haze = 2 },
		ColorCorrection = { Contrast = 0.15, Saturation = 0.05, TintColor = rgb(255, 238, 225) },
		Bloom = { Intensity = 0.8, Size = 30, Threshold = 1.4 },
		SunRays = { Intensity = 0.12, Spread = 0.7 },
		Clouds = { Cover = 0.6, Density = 0.5, Color = rgb(255, 205, 180) },
		LampsOn = true,
	}),

	-- Деревня: летний день после обеда, тёплый и насыщенный.
	Village = variant(DAY, {
		Lighting = { ClockTime = 16.2, Brightness = 3, ColorShift_Top = rgb(255, 225, 185) },
		Atmosphere = { Density = 0.28, Haze = 1.4, Glare = 0.6, Color = rgb(210, 210, 200), Decay = rgb(130, 125, 110) },
		ColorCorrection = { Contrast = 0.1, Saturation = 0.06, TintColor = rgb(255, 246, 232) },
		SunRays = { Intensity = 0.08 },
		Clouds = { Cover = 0.45 },
	}),
}

return Graphics
