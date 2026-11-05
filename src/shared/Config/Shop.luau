-- Покупки за Robux.
-- Game Passes и Developer Products создаются в Creator Hub (create.roblox.com),
-- там же задаётся цена. Сюда вставляем их Id. Пока Id = 0, покупка выключена.
return {
	GamePasses = {
		VIP = {
			Id = 0, -- 299 R$
			XpMultiplier = 1.25,
			CoinMultiplier = 1.25,
		},
		SeasonPass = {
			Id = 0, -- 399 R$, премиум-дорожка сезонного пропуска
		},
	},

	Products = {
		{ Key = "Coins100", Id = 0, Coins = 100 }, -- 49 R$
		{ Key = "Coins350", Id = 0, Coins = 350 }, -- 149 R$
		{ Key = "Coins1000", Id = 0, Coins = 1000 }, -- 399 R$
		{ Key = "XPBoost1h", Id = 0, XPBoostSeconds = 3600 }, -- 39 R$, x2 опыта на час
	},
}
