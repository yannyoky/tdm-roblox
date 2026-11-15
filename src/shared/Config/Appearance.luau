-- Кастомизация персонажа (меню «Персонаж», клавиша U).
--
-- Внешность (Look) общая для обеих сторон: кожа, телосложение, голова/лицо, причёска, борода, очки.
-- Одежда (Outfit) своя у каждой стороны: верх, низ, обувь, головной убор. Вещи — 3D-одежда
-- (layered clothing) из каталога Roblox, надевается поверх формы. Снаряжение формы (бронежилет,
-- бандана, цепь) и цвет ника остаются, поэтому своих и чужих видно издалека.
--
-- «uniform» в одежде — ничего не надевать, остаётся форма выбранного скина.
-- «avatar» во внешности — взять то, что у игрока в аватаре Roblox.
--
-- Asset — id ассета каталога. Чтобы добавить вещь, допишите строку в нужный список.
-- Слои одежды: Type = TShirt | Shirt | Sweater | Jacket | Pants | Shorts | LeftShoe | RightShoe.
-- Головной убор: Hat = id шляпы (тип 8) или Face = id маски в слоте лица (тип 42).
local Appearance = {}

Appearance.AVATAR = "avatar"
Appearance.UNIFORM = "uniform"

-- Тона кожи. 0 — как в аватаре.
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

-- Слоты внешности в порядке меню.
Appearance.LookSlots = {
	{ Key = "Body", Name = "Телосложение" },
	{ Key = "Head", Name = "Голова и лицо" },
	{ Key = "Hair", Name = "Причёска" },
	{ Key = "Beard", Name = "Борода" },
	{ Key = "Glasses", Name = "Очки" },
}

-- Gender = "M"/"F" нужен только ботам, чтобы не собирать голову одного пола на тело другого.
-- Игроки могут сочетать что угодно.
-- Все id проверены через economy.roblox.com (тип ассета совпадает). Вещи Roblox или реалистичные UGC.
Appearance.Options = {
	-- Меши частей тела (Torso, RightArm, LeftArm, LeftLeg, RightLeg).
	Body = {
		{ Id = "avatar", Name = "Как в аватаре" },
		{ Id = "man", Gender = "M", Name = "Мужское", Parts = { Torso = 86500008, RightArm = 86500036, LeftArm = 86500054, LeftLeg = 86500064, RightLeg = 86500078 } },
		{ Id = "xbox_m", Gender = "M", Name = "Мужское, крепкое", Parts = { Torso = 301826032, RightArm = 301825492, LeftArm = 301824684, LeftLeg = 301825699, RightLeg = 301825891 } },
		{ Id = "real_m", Gender = "M", Name = "Мужское, реалистичное", Parts = { Torso = 79418338717280, RightArm = 121594678924210, LeftArm = 77458402169586, LeftLeg = 84512788424940, RightLeg = 113243143782428 } },
		{ Id = "woman", Gender = "F", Name = "Женское", Parts = { Torso = 86499666, RightArm = 86499698, LeftArm = 86499716, LeftLeg = 86499753, RightLeg = 86499793 } },
		{ Id = "xbox_f", Gender = "F", Name = "Женское, спортивное", Parts = { Torso = 301824116, RightArm = 301822975, LeftArm = 301822804, LeftLeg = 301823492, RightLeg = 301823806 } },
		{ Id = "city_f", Gender = "F", Name = "Женское, городское", Parts = { Torso = 2492674027, RightArm = 2492669375, LeftArm = 2492667589, LeftLeg = 2492671662, RightLeg = 2492670347 } },
	},
	-- Динамические головы (лицо с мимикой).
	Head = {
		{ Id = "avatar", Name = "Как в аватаре" },
		{ Id = "man", Gender = "M", Name = "Мужчина", Asset = 10725826963 },
		{ Id = "classic_m", Gender = "M", Name = "Мужчина, классика", Asset = 11180212350 },
		{ Id = "beard", Gender = "M", Name = "Бородач", Asset = 97709344552035 },
		{ Id = "beard_blond", Gender = "M", Name = "Светлый бородач", Asset = 87840847758855 },
		{ Id = "scar", Gender = "M", Name = "Шрам", Asset = 74295716469720 },
		{ Id = "sly", Gender = "M", Name = "Хитрый", Asset = 75853796532602 },
		{ Id = "real_m", Gender = "M", Name = "Реалистичный", Asset = 136087963795680 },
		{ Id = "stare", Gender = "M", Name = "Тяжёлый взгляд", Asset = 75162147518322 },
		{ Id = "serious", Gender = "M", Name = "Серьёзный", Asset = 84057525262855 },
		{ Id = "woman", Gender = "F", Name = "Женщина", Asset = 10725626210 },
		{ Id = "classic_f", Gender = "F", Name = "Женщина, классика", Asset = 11159990982 },
		{ Id = "city_f", Gender = "F", Name = "Горожанка", Asset = 15093243863 },
		{ Id = "real_f", Gender = "F", Name = "Женщина, реалистичная", Asset = 84811141036354 },
		{ Id = "cheeky_f", Gender = "F", Name = "Женщина, дерзкая", Asset = 138825541299076 },
	},
	Hair = {
		{ Id = "avatar", Name = "Как в аватаре" },
		{ Id = "none", Name = "Бритая голова" },
		{ Id = "buzz", Name = "Под машинку", Asset = 10418543489 },
		{ Id = "buzz2", Name = "Ёжик", Asset = 118122971099393 },
		{ Id = "short_brown", Name = "Короткие русые", Asset = 62234425 },
		{ Id = "short_black", Name = "Короткие чёрные", Asset = 13655562 },
		{ Id = "classic", Name = "Классическая", Asset = 13477818 },
		{ Id = "slick", Name = "Зачёс назад", Asset = 29781229 },
		{ Id = "curly_fade", Name = "Кудри с фейдом", Asset = 7193405096 },
		{ Id = "afro", Name = "Афро", Asset = 7193450455 },
		{ Id = "dreads", Name = "Дреды", Asset = 26778066 },
		{ Id = "braids", Name = "Косички, чёрные", Asset = 7193454569 },
		{ Id = "braids_brown", Name = "Косички, каштановые", Asset = 9244150641 },
		{ Id = "man_bun", Name = "Пучок", Asset = 343584973 },
		{ Id = "messy_bun", Gender = "F", Name = "Небрежный пучок", Asset = 80922251 },
		{ Id = "chestnut_bun", Gender = "F", Name = "Каштановый пучок", Asset = 62724852 },
		{ Id = "ponytail", Gender = "F", Name = "Хвост", Asset = 376527350 },
		{ Id = "long", Gender = "F", Name = "Длинные", Asset = 12519986 },
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
		{ Id = "andrew", Name = "Аккуратная", Asset = 158066137 },
		{ Id = "blond", Name = "Светлая", Asset = 323418594 },
	},
	Glasses = {
		{ Id = "none", Name = "Без очков" },
		{ Id = "aviators", Name = "Авиаторы", Asset = 376526673 },
		{ Id = "aviators_silver", Name = "Авиаторы, серебро", Asset = 134823161 },
		{ Id = "sleek", Name = "Узкие тёмные", Asset = 51245241 },
		{ Id = "black", Name = "Чёрные очки", Asset = 16855968427 },
		{ Id = "ballistic", Name = "Баллистические", Asset = 124790757893843 },
		{ Id = "ballistic2", Name = "Тактические", Asset = 17814942071 },
		{ Id = "thick", Name = "Толстая оправа", Asset = 62690529 },
		{ Id = "horn", Name = "Роговая оправа", Asset = 22151904 },
		{ Id = "john", Name = "Простые", Asset = 12520031 },
	},
}

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
	Tone = 0,
	Body = "avatar",
	Head = "avatar",
	Hair = "avatar",
	Beard = "none",
	Glasses = "none",
}

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

return Appearance
