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

Appearance.Options = {
	Body = {
		{ Id = "avatar", Name = "Как в аватаре" },
	},
	Head = {
		{ Id = "avatar", Name = "Как в аватаре" },
	},
	Hair = {
		{ Id = "avatar", Name = "Как в аватаре" },
		{ Id = "none", Name = "Бритая голова" },
	},
	Beard = {
		{ Id = "none", Name = "Без бороды" },
	},
	Glasses = {
		{ Id = "none", Name = "Без очков" },
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
		Top = {},
		Bottom = {},
		Shoes = {},
		Hat = {},
	},
	Gov = {
		Top = {},
		Bottom = {},
		Shoes = {},
		Hat = {},
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
