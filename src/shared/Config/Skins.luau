-- Скины сторон — готовые комплекты реалистичной 3D-одежды (layered clothing) из каталога Roblox.
-- Вещи берутся из Config/Appearance.Clothing по id: Top, Bottom, Shoes, Hat (Hat можно не указывать).
-- Игрок может заменить любую вещь комплекта в меню «Персонаж»; что не заменено — берётся из скина.
-- Лицо, причёска и цвет кожи — из внешности игрока. Своих и чужих отличает стиль одежды
-- (Банда — уличная, Силовики — форма и тактика) и цвет ника.
--
-- Unlock — как открыть скин:
--   { Type = "Default" }                 -- есть у всех
--   { Type = "Rank", Rank = 3 }          -- звание фракции (номер в Meta.Ranks)
--   { Type = "Coins", Price = 500 }      -- купить за монеты
--   { Type = "Season", Tier = 10 }       -- уровень сезонного пропуска (бесплатная дорожка)
--   { Type = "Pass", Pass = "SkinPack" } -- Game Pass из Config/Shop
--
-- Shirt / Pants — только цвета значка в меню.
local Skins = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Skins.List = {
	-- Банда
	b_street = {
		Faction = "Bandits",
		DisplayName = "Уличный",
		Unlock = { Type = "Default" },
		Shirt = rgb(150, 30, 30),
		Pants = rgb(60, 80, 120),
		Outfit = { Top = "red_hoodie", Bottom = "baggy", Shoes = "sneakers_white" },
	},
	b_tracksuit = {
		Faction = "Bandits",
		DisplayName = "Спортивный",
		Unlock = { Type = "Rank", Rank = 2 },
		Shirt = rgb(25, 25, 25),
		Pants = rgb(30, 30, 30),
		Outfit = { Top = "zip_hoodie", Bottom = "tracksuit_stripes", Shoes = "sneakers_white2", Hat = "beanie" },
	},
	b_leather = {
		Faction = "Bandits",
		DisplayName = "Кожанка",
		Unlock = { Type = "Coins", Price = 600 },
		Shirt = rgb(30, 25, 22),
		Pants = rgb(25, 25, 30),
		Outfit = { Top = "leather", Bottom = "jeans_black", Shoes = "work_tan" },
	},
	b_brigade = {
		Faction = "Bandits",
		DisplayName = "Бригада",
		Unlock = { Type = "Rank", Rank = 4 },
		Shirt = rgb(20, 20, 20),
		Pants = rgb(35, 35, 35),
		Outfit = { Top = "puffer_black", Bottom = "cargo_black", Shoes = "running", Hat = "ski_mask" },
	},
	b_season = {
		Faction = "Bandits",
		DisplayName = "Передел (сезон 1)",
		Unlock = { Type = "Season", Tier = 20 },
		Shirt = rgb(120, 120, 125),
		Pants = rgb(30, 30, 30),
		Outfit = { Top = "gray_hood", Bottom = "tracksuit_2000", Shoes = "canvas", Hat = "cap" },
	},
	b_boss = {
		Faction = "Bandits",
		DisplayName = "Авторитет",
		Unlock = { Type = "Pass", Pass = "SkinPack" },
		Shirt = rgb(90, 60, 40),
		Pants = rgb(20, 20, 20),
		Outfit = { Top = "leather_brown", Bottom = "cargo_black2", Shoes = "running" },
	},

	-- Силовики
	g_patrol = {
		Faction = "Gov",
		DisplayName = "Патрульный",
		Unlock = { Type = "Default" },
		Shirt = rgb(35, 50, 90),
		Pants = rgb(25, 25, 30),
		Outfit = { Top = "police_blue", Bottom = "tactical_black", Shoes = "boots_black", Hat = "police_cap" },
	},
	g_assault = {
		Faction = "Gov",
		DisplayName = "Штурмовик",
		Unlock = { Type = "Rank", Rank = 2 },
		Shirt = rgb(25, 25, 28),
		Pants = rgb(25, 25, 28),
		Outfit = { Top = "swat_black", Bottom = "blackops", Shoes = "boots_black", Hat = "swat_black" },
	},
	g_camo = {
		Faction = "Gov",
		DisplayName = "Полевая форма",
		Unlock = { Type = "Coins", Price = 600 },
		Shirt = rgb(80, 90, 60),
		Pants = rgb(75, 80, 55),
		Outfit = { Top = "woodland", Bottom = "camo", Shoes = "boots_camo", Hat = "swat_olive" },
	},
	g_special = {
		Faction = "Gov",
		DisplayName = "Спецназ",
		Unlock = { Type = "Rank", Rank = 4 },
		Shirt = rgb(20, 20, 22),
		Pants = rgb(20, 20, 22),
		Outfit = { Top = "swat_armor", Bottom = "strapped", Shoes = "boots_black", Hat = "pasgt" },
	},
	g_season = {
		Faction = "Gov",
		DisplayName = "Передел (сезон 1)",
		Unlock = { Type = "Season", Tier = 20 },
		Shirt = rgb(85, 90, 60),
		Pants = rgb(30, 30, 30),
		Outfit = { Top = "olive", Bottom = "blackout_camo", Shoes = "boots_brown", Hat = "tactical_cap" },
	},
	g_elite = {
		Faction = "Gov",
		DisplayName = "Полковник",
		Unlock = { Type = "Pass", Pass = "SkinPack" },
		Shirt = rgb(30, 40, 60),
		Pants = rgb(25, 25, 30),
		Outfit = { Top = "police_jacket", Bottom = "tactical_black", Shoes = "work_black", Hat = "ru_police_cap" },
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
