-- Настройки матча и режимов.
-- Чтобы добавить сценарий: создать модуль в src/server/Modes, добавить запись в List и id в Order.
return {
	Match = {
		MinPlayers = 2, -- сколько игроков нужно для старта на живом сервере
		MinPlayersStudio = 1, -- в Studio можно тестировать одному
		IntermissionTime = 15, -- секунд на голосование в лобби
		ResultsTime = 8, -- секунд на экран итогов
		SpawnProtection = 2, -- секунд защиты после появления
	},

	Order = { "TDM", "Capture" },

	List = {
		TDM = {
			Id = "TDM",
			DisplayName = "Перестрелка",
			Description = "Первыми до 50 убийств",
			Module = "TDM",
			Duration = 480, -- 8 минут
			ScoreLimit = 50,
			RespawnDelay = 3,
		},
		Capture = {
			Id = "Capture",
			DisplayName = "Капт",
			Description = "Захват района по раундам, без возрождения",
			Module = "Capture",
			Duration = nil, -- временем управляет сам режим (раунды)
			RoundTime = 240, -- 4 минуты на раунд
			CaptureTime = 30, -- секунд на захват одним игроком
			WinsNeeded = 3, -- до 3 побед
			PauseBetweenRounds = 5,
		},
	},
}
