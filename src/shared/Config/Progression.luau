-- Награды за матч и кривая уровней.
local Progression = {
	MaxLevel = 50,
	Rewards = {
		Play = { XP = 20, Coins = 10 }, -- за участие в матче
		Kill = { XP = 10, Coins = 2 }, -- за каждое убийство
		Win = { XP = 50, Coins = 30 }, -- за победу команды
	},
}

-- Сколько опыта нужно, чтобы перейти с уровня level на следующий.
function Progression.xpForLevel(level: number): number
	return 100 + (level - 1) * 50
end

return Progression
