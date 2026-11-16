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

	Order = { "TDM", "Capture", "City" },

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
			SpawnAtBase = true, -- появление на базе, до зоны добираться самим (пешком или на машине)
			Duration = nil, -- временем управляет сам режим (раунды)
			RoundTime = 240, -- 4 минуты на раунд
			CaptureTime = 30, -- секунд на захват одним игроком
			WinsNeeded = 3, -- до 3 побед
			PauseBetweenRounds = 5,
		},
		-- Свободная прогулка по открытому городу. Только здесь по улицам ходят прохожие
		-- и ездят машины-NPC (CityLife); в боевых режимах на карте «Город» их нет.
		City = {
			Id = "City",
			DisplayName = "Город",
			Description = "Свободная прогулка по городу",
			Module = "FreeRoam",
			Map = "City", -- режим всегда на этой карте
			Bots = false, -- без ботов-бойцов
			CityLife = true, -- прохожие и трафик
			Duration = 1500, -- 25 минут
			RespawnDelay = 4,
		},
	},
}
