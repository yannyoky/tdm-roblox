-- Кастомизация персонажа (меню «Персонаж», клавиша U).
--
-- Тело одно из двух реалистичных: мужское или женское (UGC-тела с каталога Roblox).
-- Аватар игрока Roblox не используется: все персонажи собираются с нуля из этих тел.
-- Внешность (Look) общая для обеих сторон: тело, цвет кожи, лицо, причёска, борода, очки.
-- Лицо, причёска и борода зависят от тела: в списке только подходящие (Gender = "M"/"F",
-- без Gender — подходит обоим).
-- Одежда (Outfit) своя у каждой стороны: верх, низ, обувь, головной убор. Вещи — 3D-одежда
-- (layered clothing), она садится на любое из двух тел. Скины (Config/Skins) — готовые комплекты.
--
-- «uniform» в одежде — «как в скине»: вещь берётся из комплекта выбранного скина.
--
-- Asset — id ассета каталога. Чтобы добавить вещь, допишите строку в нужный список.
-- Слои одежды: Type = TShirt | Shirt | Sweater | Jacket | Pants | Shorts | LeftShoe | RightShoe.
-- Головной убор: Hat = id шляпы (тип 8) или Face = id маски в слоте лица (тип 42).
local Appearance = {}

Appearance.UNIFORM = "uniform"

-- Тона кожи.
Appearance.Tones = {
	Color3.fromRGB(255, 219, 190),
	Color3.fromRGB(241, 194, 158),
	Color3.fromRGB(224, 172, 135),
	Color3.fromRGB(198, 145, 106),
	Color3.fromRGB(168, 117, 82),
	Color3.fromRGB(134, 89, 60),
	Color3.fromRGB(104, 67, 45),
	Color3.fromRGB(72, 46, 32),
}

-- Слоты внешности в порядке меню (тело выбирается отдельными кнопками).
Appearance.LookSlots = {
	{ Key = "Head", Name = "Лицо" },
	{ Key = "Hair", Name = "Причёска" },
	{ Key = "Beard", Name = "Борода", Gender = "M" },
	{ Key = "Glasses", Name = "Очки" },
}

-- Все id проверены через catalog.roblox.com. Только реалистичные вещи: старые «кубические»
-- головы, причёски и тела Roblox убраны.
Appearance.Options = {
	-- Два тела. Model — сгенерированная модель (тело с головой) из assets/characters/<Model>.rbxm
	-- (src/shared/GeneratedBody.luau): если файл есть, персонаж игрока собирается из неё,
	-- лицо, причёска и цвет кожи у неё свои. Без файла — каталожное тело:
	-- Parts — меши частей тела, Head — лицо по умолчанию для этого тела.
	-- Голова и тело подобраны и проверены в Studio вместе: голова садится на шею без зазора.
	Body = {
		{
			-- Тело «Realistic Muscle Male Doll» (Limerence #), бандл 17319439671905.
			Id = "male",
			Gender = "M",
			Name = "Мужское",
			Model = "Male",
			Head = "m_gta",
			Parts = { Torso = 86020764157979, RightArm = 136084963335699, LeftArm = 118230420636257, LeftLeg = 88372396093345, RightLeg = 95060431528417 },
		},
		{
			-- «Woman Fashion Model Doll» (angelshefford), бандл 181282816119101.
			Id = "female",
			Gender = "F",
			Name = "Женское",
			Model = "Female",
			Head = "f_model",
			Parts = { Torso = 122831550366162, RightArm = 95246976223366, LeftArm = 106832235837446, LeftLeg = 124333485905753, RightLeg = 86653892031792 },
		},
	},
	-- Динамические головы (лицо с мимикой, FaceControls). Только естественные лица:
	-- кукольные, с большими глазами и мультяшные убраны.
	-- SkinTone — у головы кожа нарисована текстурой и HeadColor на неё не действует:
	-- тело красится в этот цвет, выбор цвета кожи в меню для такой головы не показывается.
	-- Rest — «лицо в покое» поверх мимики (Config/Character.Face, src/client/FaceLife.luau):
	-- значения FaceControls без Left/Right (ставятся на обе стороны). Подобраны в Studio,
	-- чтобы глаза не выглядели крупными и «стеклянными». EyeClosed больше 0.25 — лицо сонное.
	Head = {
		{
			-- Голова из бандла «Realistic GTA Man PS2» (loveanwgel), 8600248977437.
			-- Хмурые брови нарисованы в текстуре: поднимаем внутренние края бровей и чуть улыбаемся.
			Id = "m_gta",
			Gender = "M",
			Name = "Мужчина",
			Asset = 85999187125569,
			SkinTone = Color3.fromRGB(205, 140, 90),
			Rest = { InnerBrowRaiser = 0.25, LipCornerPuller = 0.15, CheekRaiser = 0.1, LipsTogether = 0.3 },
		},
		{
			-- Временно, пока делаем свою женскую голову: родная голова тела «Woman Fashion Model Doll».
			Id = "f_model",
			Gender = "F",
			Name = "Женщина",
			Asset = 76846031172896,
			SkinTone = Color3.fromRGB(236, 196, 170),
			Rest = { EyeClosed = 0.22, UpperLidRaiser = 0, CheekRaiser = 0.12, LipCornerPuller = 0.08 },
		},
	},
	Hair = {
		{ Id = "none", Name = "Бритая голова" },
		{ Id = "buzz", Name = "Под машинку", Asset = 10418543489 },
		{ Id = "buzz2", Name = "Ёжик", Asset = 118122971099393 },
		{ Id = "curly_fade", Gender = "M", Name = "Кудри с фейдом", Asset = 7193405096 },
		{ Id = "afro", Name = "Афро", Asset = 7193450455 },
		{ Id = "braids", Name = "Косички, чёрные", Asset = 7193454569 },
		{ Id = "braids_brown", Gender = "F", Name = "Косички, каштановые", Asset = 9244150641 },
		{ Id = "wavy", Gender = "F", Name = "Волнистые, пробор", Asset = 9244111257 },
		{ Id = "auburn", Gender = "F", Name = "Прямые рыжие", Asset = 3814481268 },
	},
	Beard = {
		{ Id = "none", Name = "Без бороды" },
		{ Id = "stubble", Name = "Щетина", Asset = 4940496302 },
		{ Id = "stubble_goatee", Name = "Щетина с эспаньолкой", Asset = 136781932550953 },
		{ Id = "mustache", Name = "Тонкие усы", Asset = 84531882938352 },
		{ Id = "goatee", Name = "Эспаньолка", Asset = 140468746932375 },
		{ Id = "goatee2", Name = "Козлиная бородка", Asset = 129103898151118 },
		{ Id = "full_black", Name = "Густая чёрная", Asset = 122529465337911 },
		{ Id = "full_brown", Name = "Густая русая", Asset = 14078903680 },
		{ Id = "beard", Name = "Борода", Asset = 96842327519524 },
	},
	Glasses = {
		{ Id = "none", Name = "Без очков" },
		{ Id = "black", Name = "Чёрные очки", Asset = 16855968427 },
		{ Id = "ballistic", Name = "Баллистические", Asset = 124790757893843 },
		{ Id = "ballistic2", Name = "Тактические", Asset = 17814942071 },
		{ Id = "aviators", Name = "Авиаторы", Asset = 376526673 },
	},
}

-- Сгенерированные модели и для ботов с прохожими. false — у них каталожные тела с разными
-- лицами и причёсками, иначе все боты одного пола на одно лицо.
Appearance.GeneratedForNpc = false

-- Одежда в лобби (ещё нет стороны): простые вещи из гардероба Банды.
Appearance.LobbyOutfit = { Faction = "Bandits", Top = "tee_gray", Bottom = "baggy", Shoes = "sneakers_white" }

-- Слоты одежды в порядке меню.
Appearance.ClothingSlots = {
	{ Key = "Top", Name = "Верх" },
	{ Key = "Bottom", Name = "Низ" },
	{ Key = "Shoes", Name = "Обувь" },
	{ Key = "Hat", Name = "Головной убор" },
}

-- Вещи сторон. Палитры разные: у Банды уличная одежда (чёрное, красное, джинса),
-- у Силовиков тёмно-синее, чёрное и олива.
Appearance.Clothing = {
	Bandits = {
		Top = {
			{ Id = "zip_hoodie", Name = "Худи на молнии, чёрное", Layers = { { Id = 7192553841, Type = "Jacket" } } },
			{ Id = "hoodie", Name = "Худи чёрное", Layers = { { Id = 13366458116, Type = "Jacket" } } },
			{ Id = "red_hoodie", Name = "Худи красное", Layers = { { Id = 12444039569, Type = "Sweater" } } },
			{ Id = "gray_hood", Name = "Куртка с капюшоном, серая", Layers = { { Id = 8516620262, Type = "Jacket" } } },
			{ Id = "leather", Name = "Кожанка чёрная", Layers = { { Id = 7192549218, Type = "Jacket" } } },
			{ Id = "leather_brown", Name = "Кожанка коричневая", Layers = { { Id = 6984767443, Type = "Jacket" } } },
			{ Id = "puffer", Name = "Пуховик", Layers = { { Id = 135914245941538, Type = "Jacket" } } },
			{ Id = "puffer_black", Name = "Пуховик чёрный", Layers = { { Id = 131726584013805, Type = "Jacket" } } },
			{ Id = "knit", Name = "Свитер чёрный", Layers = { { Id = 9240757332, Type = "Sweater" } } },
			{ Id = "tee_black", Name = "Футболка чёрная", Layers = { { Id = 7178736794, Type = "TShirt" } } },
			{ Id = "tee_gray", Name = "Футболка серая", Layers = { { Id = 9112474888, Type = "TShirt" } } },
		},
		Bottom = {
			{ Id = "tracksuit", Name = "Спортивки чёрные", Layers = { { Id = 17712013370, Type = "Pants" } } },
			{ Id = "tracksuit_stripes", Name = "Спортивки с лампасами", Layers = { { Id = 9248293838, Type = "Pants" } } },
			{ Id = "tracksuit_2000", Name = "Спортивки нулевых", Layers = { { Id = 12330590440, Type = "Pants" } } },
			{ Id = "baggy", Name = "Широкие джинсы", Layers = { { Id = 126911375831145, Type = "Pants" } } },
			{ Id = "jeans", Name = "Джинсы", Layers = { { Id = 87573325329630, Type = "Pants" } } },
			{ Id = "jeans_black", Name = "Чёрные джинсы", Layers = { { Id = 129124259516721, Type = "Pants" } } },
			{ Id = "cargo_black", Name = "Карго чёрные", Layers = { { Id = 17163024759, Type = "Pants" } } },
			{ Id = "cargo_black2", Name = "Карго чёрные, свободные", Layers = { { Id = 9178382609, Type = "Pants" } } },
			{ Id = "cargo_brown", Name = "Карго коричневые", Layers = { { Id = 6984740059, Type = "Pants" } } },
			{ Id = "sweats", Name = "Треники чёрные", Layers = { { Id = 6984763785, Type = "Pants" } } },
			{ Id = "sweats_gray", Name = "Треники серые", Layers = { { Id = 7192664790, Type = "Pants" } } },
		},
		Shoes = {
			{ Id = "sneakers_white", Name = "Кроссовки белые", Layers = { { Id = 9482987287, Type = "LeftShoe" }, { Id = 9482991343, Type = "RightShoe" } } },
			{ Id = "sneakers_gray", Name = "Кроссовки серые", Layers = { { Id = 7193165925, Type = "LeftShoe" }, { Id = 7193166879, Type = "RightShoe" } } },
			{ Id = "sneakers_white2", Name = "Кроссовки белые, высокие", Layers = { { Id = 9614684090, Type = "LeftShoe" }, { Id = 9614686845, Type = "RightShoe" } } },
			{ Id = "running", Name = "Беговые чёрные", Layers = { { Id = 8722159299, Type = "LeftShoe" }, { Id = 8722157748, Type = "RightShoe" } } },
			{ Id = "canvas", Name = "Кеды", Layers = { { Id = 9481782649, Type = "LeftShoe" }, { Id = 9481786623, Type = "RightShoe" } } },
			{ Id = "work_tan", Name = "Рабочие ботинки", Layers = { { Id = 7193170137, Type = "LeftShoe" }, { Id = 7193171232, Type = "RightShoe" } } },
		},
		Hat = {
			{ Id = "beanie", Name = "Шапка чёрная", Hat = 6467488863 },
			{ Id = "robber", Name = "Шапка грабителя", Hat = 81708856 },
			{ Id = "beanie2", Name = "Шапка чёрная, вязаная", Hat = 12051951936 },
			{ Id = "cap", Name = "Бейсболка", Hat = 417457461 },
			{ Id = "cap_red", Name = "Бейсболка красная", Hat = 12803855954 },
			{ Id = "biker", Name = "Кепка байкера", Hat = 14462497 },
			{ Id = "ski_mask", Name = "Лыжная маска", Face = 14192556029 },
			{ Id = "ski_mask2", Name = "Маска с прорезями", Face = 15685748398 },
			{ Id = "balaclava", Name = "Балаклава", Face = 12586895741 },
		},
	},
	Gov = {
		Top = {
			{ Id = "swat_armor", Name = "Броня спецназа", Layers = { { Id = 16111137472, Type = "Jacket" } } },
			{ Id = "swat_black", Name = "Тактика СОБР, чёрная", Layers = { { Id = 71509476632035, Type = "Jacket" } } },
			{ Id = "police_blue", Name = "Форма полиции, синяя", Layers = { { Id = 122125423174643, Type = "Jacket" } } },
			{ Id = "police_jacket", Name = "Куртка полиции", Layers = { { Id = 70384594323580, Type = "Jacket" } } },
			{ Id = "special_jacket", Name = "Куртка спецназа", Layers = { { Id = 105724408403894, Type = "Jacket" } } },
			{ Id = "police_shirt", Name = "Рубашка полиции", Layers = { { Id = 108410559788414, Type = "Shirt" } } },
			{ Id = "vest", Name = "Тактический жилет", Layers = { { Id = 15216709355, Type = "Jacket" } } },
			{ Id = "olive", Name = "Куртка спецназа, олива", Layers = { { Id = 118277287771920, Type = "Jacket" } } },
			{ Id = "woodland", Name = "Камуфляж «лес»", Layers = { { Id = 86103326955062, Type = "Jacket" } } },
			{ Id = "desert", Name = "Камуфляж «пустыня»", Layers = { { Id = 12415687663, Type = "Jacket" } } },
			{ Id = "stalker", Name = "Полевая куртка", Layers = { { Id = 103986220210847, Type = "Jacket" } } },
		},
		Bottom = {
			{ Id = "tactical_black", Name = "Тактические чёрные", Layers = { { Id = 117128296983703, Type = "Pants" } } },
			{ Id = "strapped", Name = "Тактические с ремнями", Layers = { { Id = 84043119663111, Type = "Pants" } } },
			{ Id = "blackops", Name = "Штурмовые чёрные", Layers = { { Id = 76485083014922, Type = "Pants" } } },
			{ Id = "blackout_camo", Name = "Камуфляж чёрный", Layers = { { Id = 12548114026, Type = "Pants" } } },
			{ Id = "camo", Name = "Камуфляж", Layers = { { Id = 132918996432202, Type = "Pants" } } },
		},
		Shoes = {
			{ Id = "boots_black", Name = "Берцы чёрные", Layers = { { Id = 9614836327, Type = "LeftShoe" }, { Id = 9614841343, Type = "RightShoe" } } },
			{ Id = "boots_brown", Name = "Берцы коричневые", Layers = { { Id = 9542367726, Type = "LeftShoe" }, { Id = 9542376078, Type = "RightShoe" } } },
			{ Id = "boots_camo", Name = "Берцы камуфляж", Layers = { { Id = 9530352974, Type = "LeftShoe" }, { Id = 9530355170, Type = "RightShoe" } } },
			{ Id = "work_black", Name = "Рабочие чёрные", Layers = { { Id = 9542395442, Type = "LeftShoe" }, { Id = 9542450828, Type = "RightShoe" } } },
		},
		Hat = {
			{ Id = "police_cap", Name = "Фуражка полиции", Hat = 104751413508452 },
			{ Id = "tactical_cap", Name = "Тактическая кепка", Hat = 85862929843857 },
			{ Id = "ru_police_cap", Name = "Фуражка", Hat = 28116846 },
			{ Id = "sergeant", Name = "Фуражка сержанта", Hat = 1081392 },
			{ Id = "riot", Name = "Шлем ОМОНа", Hat = 16469532 },
			{ Id = "swat_black", Name = "Шлем СОБР, чёрный", Hat = 12715896786 },
			{ Id = "swat_olive", Name = "Шлем, олива", Hat = 12715900728 },
			{ Id = "pasgt", Name = "Шлем PASGT", Hat = 85549992031892 },
			{ Id = "tactical", Name = "Тактический шлем", Hat = 114472411314837 },
			{ Id = "balaclava", Name = "Балаклава", Face = 13003130877 },
		},
	},
}

Appearance.DefaultLook = {
	Tone = 3,
	Body = "male",
	Head = "m_gta",
	Hair = "buzz",
	Beard = "none",
	Glasses = "none",
}

-- Что ставить по умолчанию для каждого тела, если выбранное к нему не подходит.
Appearance.GenderDefaults = {
	M = { Head = "m_gta", Hair = "buzz", Beard = "none" },
	F = { Head = "f_model", Hair = "wavy", Beard = "none" },
}

-- Подходит ли вариант к телу этого пола.
function Appearance.fits(opt: any, gender: string): boolean
	return opt ~= nil and (opt.Gender == nil or opt.Gender == gender)
end

-- Варианты слота для тела этого пола (для меню и ботов).
function Appearance.optionsFor(slot: string, gender: string): { any }
	local list = {}
	for _, opt in Appearance.Options[slot] or {} do
		if Appearance.fits(opt, gender) then
			table.insert(list, opt)
		end
	end
	return list
end

function Appearance.genderOf(bodyId: string?): string
	for _, opt in Appearance.Options.Body do
		if opt.Id == bodyId then
			return opt.Gender
		end
	end
	return "M"
end

function Appearance.findIn(list: { any }?, id: string?): any
	if not list or not id then
		return nil
	end
	for _, opt in list do
		if opt.Id == id then
			return opt
		end
	end
	return nil
end

function Appearance.option(slot: string, id: string?): any
	return Appearance.findIn(Appearance.Options[slot], id)
end

-- Голова по id ассета (для мимики: клиент знает только HumanoidDescription.Head).
function Appearance.headByAsset(asset: number?): any
	if not asset or asset == 0 then
		return nil
	end
	for _, opt in Appearance.Options.Head do
		if opt.Asset == asset then
			return opt
		end
	end
	return nil
end

return Appearance
