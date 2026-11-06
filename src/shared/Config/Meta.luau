-- Мета-прогрессия: звания фракций, ежедневные задания, сезонный пропуск, рейтинг.
local Meta = {}

-- Звания: свои у каждой стороны. Опыт фракции копится, когда играешь за неё.
Meta.Ranks = {
	Bandits = {
		{ Name = "Шестёрка", XP = 0 },
		{ Name = "Бродяга", XP = 300 },
		{ Name = "Боец", XP = 900 },
		{ Name = "Бригадир", XP = 2000 },
		{ Name = "Смотрящий", XP = 4000 },
		{ Name = "Авторитет", XP = 8000 },
	},
	Gov = {
		{ Name = "Рядовой", XP = 0 },
		{ Name = "Сержант", XP = 300 },
		{ Name = "Лейтенант", XP = 900 },
		{ Name = "Капитан", XP = 2000 },
		{ Name = "Майор", XP = 4000 },
		{ Name = "Полковник", XP = 8000 },
	},
}

function Meta.rankFor(faction: string, xp: number): (number, string)
	local list = Meta.Ranks[faction]
	local index = 1
	for i, rank in list do
		if xp >= rank.XP then
			index = i
		end
	end
	return index, list[index].Name
end

-- Ежедневные задания: каждый день игроку выпадает 3 из списка.
-- Event: Kill, Headshot, GrenadeKill, Revive, Win, Match, CaptureRound.
Meta.QuestsPerDay = 3
Meta.Quests = {
	{ Id = "Kills15", Text = "Убейте 15 врагов", Event = "Kill", Goal = 15, Coins = 60, SeasonXP = 300 },
	{ Id = "Wins2", Text = "Выиграйте 2 матча", Event = "Win", Goal = 2, Coins = 80, SeasonXP = 400 },
	{ Id = "Play3", Text = "Сыграйте 3 матча", Event = "Match", Goal = 3, Coins = 40, SeasonXP = 250 },
	{ Id = "Headshots5", Text = "Убейте 5 врагов в голову", Event = "Headshot", Goal = 5, Coins = 70, SeasonXP = 350 },
	{ Id = "Revive3", Text = "Поднимите 3 союзников", Event = "Revive", Goal = 3, Coins = 60, SeasonXP = 300 },
	{ Id = "Grenade2", Text = "Убейте 2 врагов гранатой", Event = "GrenadeKill", Goal = 2, Coins = 70, SeasonXP = 350 },
	{ Id = "Capture3", Text = "Выиграйте 3 раунда в капте", Event = "CaptureRound", Goal = 3, Coins = 70, SeasonXP = 350 },
}

-- Сезонный пропуск. Бесплатная дорожка доступна всем, премиум — по Game Pass (Shop.GamePasses.SeasonPass).
Meta.Season = {
	Id = "S1",
	Name = "Сезон 1: Передел",
	EndsText = "до 31 января",
	Tiers = 30,
	TierXP = 500,
}

-- Награда за уровень пропуска: { Coins?, Title?, XPBoostSeconds? }.
function Meta.seasonReward(tier: number, premium: boolean)
	if premium then
		if tier % 10 == 0 then
			return { Coins = 100, XPBoostSeconds = 3600 }
		elseif tier == 15 then
			return { Coins = 50, Title = "Легенда района" }
		elseif tier == Meta.Season.Tiers then
			return { Coins = 300, Title = "Хозяин города" }
		end
		return { Coins = 50 }
	end
	if tier % 5 == 0 then
		local titles = { [5] = "Новичок", [10] = "Свой", [15] = "Опасный", [20] = "Бывалый", [25] = "Ветеран", [30] = "Легенда сезона" }
		return { Coins = 50, Title = titles[tier] }
	end
	return { Coins = 25 }
end

-- Рейтинг: меняется только в матчах, где в каждой команде хотя бы MinHumansPerTeam живых игроков.
Meta.Rating = {
	Start = 1000,
	K = 32,
	MinHumansPerTeam = 2,
	Divisions = {
		{ Name = "Бронза", Min = 0 },
		{ Name = "Серебро", Min = 1100 },
		{ Name = "Золото", Min = 1250 },
		{ Name = "Платина", Min = 1400 },
		{ Name = "Алмаз", Min = 1600 },
		{ Name = "Элита", Min = 1850 },
	},
}

function Meta.divisionFor(rating: number): string
	local name = Meta.Rating.Divisions[1].Name
	for _, d in Meta.Rating.Divisions do
		if rating >= d.Min then
			name = d.Name
		end
	end
	return name
end

return Meta
