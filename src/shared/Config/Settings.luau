-- Настройки игрока. Сохраняются на сервере вместе с прогрессом.
-- Type: "Number" (ползунок Min..Max с шагом Step) или "Toggle".
return {
	Order = { "Sensitivity", "AimSensitivity", "FieldOfView", "ScreenShake", "KeyHints" },
	List = {
		Sensitivity = { Type = "Number", Name = "Чувствительность мыши", Min = 0.2, Max = 3, Step = 0.1, Default = 1 },
		AimSensitivity = { Type = "Number", Name = "Чувствительность в прицеле", Min = 0.2, Max = 1.5, Step = 0.05, Default = 0.6 },
		FieldOfView = { Type = "Number", Name = "Поле зрения (FOV)", Min = 60, Max = 100, Step = 1, Default = 70 },
		ScreenShake = { Type = "Toggle", Name = "Тряска экрана", Default = true },
		KeyHints = { Type = "Toggle", Name = "Подсказки клавиш", Default = true },
	},
}
