-- Скины фракций: форма и снаряжение поверх аватара игрока.
-- Лицо, причёска и цвет кожи остаются от аватара, а одежда заменяется формой стороны,
-- чтобы своих и чужих было видно издалека.
--
-- Unlock — как открыть скин:
--   { Type = "Default" }                 -- есть у всех
--   { Type = "Rank", Rank = 3 }          -- звание фракции (номер в Meta.Ranks)
--   { Type = "Coins", Price = 500 }      -- купить за монеты
--   { Type = "Season", Tier = 10 }       -- уровень сезонного пропуска (бесплатная дорожка)
--   { Type = "Pass", Pass = "SkinPack" } -- Game Pass из Config/Shop
--
-- Gear — детали снаряжения: Vest, Helmet, Cap, Beanie, Bandana, Balaclava, Chain, Backpack, Visor.
local Skins = {}

Skins.List = {
	-- Банда
	b_street = {
		Faction = "Bandits",
		DisplayName = "Уличный",
		Unlock = { Type = "Default" },
		Shirt = Color3.fromRGB(120, 30, 30),
		Pants = Color3.fromRGB(40, 40, 48),
		Shoes = Color3.fromRGB(230, 230, 230),
		Gear = { { Kind = "Bandana", Color = Color3.fromRGB(170, 30, 30) } },
	},
	b_tracksuit = {
		Faction = "Bandits",
		DisplayName = "Спортивный костюм",
		Unlock = { Type = "Rank", Rank = 2 },
		Shirt = Color3.fromRGB(30, 30, 30),
		Pants = Color3.fromRGB(30, 30, 30),
		Shoes = Color3.fromRGB(240, 240, 240),
		Gear = {
			{ Kind = "Beanie", Color = Color3.fromRGB(25, 25, 25) },
			{ Kind = "Chain", Color = Color3.fromRGB(230, 190, 60) },
		},
	},
	b_leather = {
		Faction = "Bandits",
		DisplayName = "Кожанка",
		Unlock = { Type = "Coins", Price = 600 },
		Shirt = Color3.fromRGB(60, 40, 30),
		Pants = Color3.fromRGB(35, 45, 70),
		Shoes = Color3.fromRGB(40, 30, 25),
		Gear = { { Kind = "Chain", Color = Color3.fromRGB(230, 190, 60) } },
	},
	b_brigade = {
		Faction = "Bandits",
		DisplayName = "Бригада",
		Unlock = { Type = "Rank", Rank = 4 },
		Shirt = Color3.fromRGB(90, 20, 20),
		Pants = Color3.fromRGB(25, 25, 25),
		Shoes = Color3.fromRGB(20, 20, 20),
		Gear = {
			{ Kind = "Balaclava", Color = Color3.fromRGB(20, 20, 20) },
			{ Kind = "Vest", Color = Color3.fromRGB(50, 50, 45) },
		},
	},
	b_season = {
		Faction = "Bandits",
		DisplayName = "Передел (сезон 1)",
		Unlock = { Type = "Season", Tier = 20 },
		Shirt = Color3.fromRGB(200, 140, 30),
		Pants = Color3.fromRGB(30, 30, 30),
		Shoes = Color3.fromRGB(200, 140, 30),
		Gear = {
			{ Kind = "Cap", Color = Color3.fromRGB(30, 30, 30) },
			{ Kind = "Bandana", Color = Color3.fromRGB(200, 140, 30) },
		},
	},
	b_boss = {
		Faction = "Bandits",
		DisplayName = "Авторитет",
		Unlock = { Type = "Pass", Pass = "SkinPack" },
		Shirt = Color3.fromRGB(240, 240, 240),
		Pants = Color3.fromRGB(20, 20, 20),
		Shoes = Color3.fromRGB(20, 20, 20),
		Gear = {
			{ Kind = "Chain", Color = Color3.fromRGB(240, 200, 70) },
			{ Kind = "Visor", Color = Color3.fromRGB(20, 20, 20) },
		},
	},

	-- Силовики
	g_patrol = {
		Faction = "Gov",
		DisplayName = "Патрульный",
		Unlock = { Type = "Default" },
		Shirt = Color3.fromRGB(40, 60, 110),
		Pants = Color3.fromRGB(30, 35, 55),
		Shoes = Color3.fromRGB(20, 20, 20),
		Gear = { { Kind = "Cap", Color = Color3.fromRGB(30, 40, 80) } },
	},
	g_assault = {
		Faction = "Gov",
		DisplayName = "Штурмовик",
		Unlock = { Type = "Rank", Rank = 2 },
		Shirt = Color3.fromRGB(35, 35, 40),
		Pants = Color3.fromRGB(35, 35, 40),
		Shoes = Color3.fromRGB(20, 20, 20),
		Gear = {
			{ Kind = "Helmet", Color = Color3.fromRGB(30, 30, 35) },
			{ Kind = "Vest", Color = Color3.fromRGB(25, 25, 30) },
		},
	},
	g_camo = {
		Faction = "Gov",
		DisplayName = "Полевая форма",
		Unlock = { Type = "Coins", Price = 600 },
		Shirt = Color3.fromRGB(85, 95, 60),
		Pants = Color3.fromRGB(75, 80, 55),
		Shoes = Color3.fromRGB(50, 40, 30),
		Gear = {
			{ Kind = "Helmet", Color = Color3.fromRGB(80, 90, 60) },
			{ Kind = "Backpack", Color = Color3.fromRGB(70, 75, 50) },
		},
	},
	g_special = {
		Faction = "Gov",
		DisplayName = "Спецназ",
		Unlock = { Type = "Rank", Rank = 4 },
		Shirt = Color3.fromRGB(20, 20, 25),
		Pants = Color3.fromRGB(20, 20, 25),
		Shoes = Color3.fromRGB(15, 15, 15),
		Gear = {
			{ Kind = "Balaclava", Color = Color3.fromRGB(15, 15, 15) },
			{ Kind = "Helmet", Color = Color3.fromRGB(20, 20, 25) },
			{ Kind = "Vest", Color = Color3.fromRGB(35, 35, 40) },
		},
	},
	g_season = {
		Faction = "Gov",
		DisplayName = "Передел (сезон 1)",
		Unlock = { Type = "Season", Tier = 20 },
		Shirt = Color3.fromRGB(230, 230, 235),
		Pants = Color3.fromRGB(40, 60, 110),
		Shoes = Color3.fromRGB(20, 20, 20),
		Gear = {
			{ Kind = "Helmet", Color = Color3.fromRGB(230, 230, 235) },
			{ Kind = "Visor", Color = Color3.fromRGB(40, 60, 110) },
		},
	},
	g_elite = {
		Faction = "Gov",
		DisplayName = "Полковник",
		Unlock = { Type = "Pass", Pass = "SkinPack" },
		Shirt = Color3.fromRGB(30, 50, 40),
		Pants = Color3.fromRGB(30, 50, 40),
		Shoes = Color3.fromRGB(15, 15, 15),
		Gear = {
			{ Kind = "Cap", Color = Color3.fromRGB(30, 50, 40) },
			{ Kind = "Chain", Color = Color3.fromRGB(220, 180, 60) },
		},
	},
}

-- Порядок в меню.
Skins.Order = {
	Bandits = { "b_street", "b_tracksuit", "b_leather", "b_brigade", "b_season", "b_boss" },
	Gov = { "g_patrol", "g_assault", "g_camo", "g_special", "g_season", "g_elite" },
}

Skins.Default = { Bandits = "b_street", Gov = "g_patrol" }

for id, def in Skins.List do
	def.Id = id
end

-- Текст условия открытия для меню.
function Skins.unlockText(def): string
	local u = def.Unlock
	if u.Type == "Rank" then
		return "Звание №" .. u.Rank
	elseif u.Type == "Coins" then
		return u.Price .. " монет"
	elseif u.Type == "Season" then
		return "Сезон, уровень " .. u.Tier
	elseif u.Type == "Pass" then
		return "Набор скинов (Robux)"
	end
	return "Есть у всех"
end

return Skins
