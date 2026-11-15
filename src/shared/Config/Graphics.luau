-- Реалистичная графика: то, что не входит в Config/Decor (свет и отделка карт).
--   src/client/Graphics.luau      -- PBR-материалы из MaterialService, размытие в прицеле
--   src/server/World/Realism.luau -- земля из Terrain с травой, свет в зданиях

local rgb = Color3.fromRGB

local Graphics = {}

-- Свои PBR-материалы. MaterialVariant с таким именем в MaterialService заменит стандартный
-- материал (BaseMaterial = ключ слева) на всех деталях. Нет варианта с таким именем —
-- берётся любой MaterialVariant с тем же BaseMaterial (если AutoPickMaterialVariants = true).
-- Так пак материалов из Toolbox работает сразу, без переименования.
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

-- Земля из Terrain вместо одной большой детали: трава шевелится, лучше свет.
-- Холмы карты (тоже Terrain) не трогаются: заполняется только слой ниже y = 0.
-- ВЫКЛЮЧЕНО: поверхность Terrain на y = 0 совпадает с плитами, площадками и полами баз,
-- и при движении камеры трава мерцает поверх них. Вернуть можно, когда плоские детали
-- карты будут подняты над землёй хотя бы на 0.5 студа.
Graphics.TerrainGround = false
-- Травинки на Terrain Grass. Низкие, но немного прячут ползущих раненых.
Graphics.GrassDecoration = true

-- Свет под потолком в зданиях с интерьером.
Graphics.InteriorLights = {
	Enabled = true,
	Color = rgb(255, 225, 185),
	Brightness = 1.4,
	Range = 22,
}

-- Размытие в прицеле: фокус на том, куда смотрит игрок, своё оружие и даль размыты.
-- Ограничения Roblox: FocusDistance 0..200, InFocusRadius 0..50. Настройка игрока «Размытие в прицеле».
Graphics.AimBlur = {
	NearIntensity = 0.35,
	FarIntensity = 0.06,
	MinInFocusRadius = 25,
}

return Graphics
