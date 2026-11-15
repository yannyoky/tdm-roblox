-- Автопарк фракций. Машины появляются на площадках у базы своей команды.
-- Сесть: E у двери (у водительской — за руль), F — на любое свободное место. Выйти: прыжок
-- (встаёте у своей двери). Ручник: Shift.
-- Чужой машиной воспользоваться нельзя (TeamLocked), но её можно расстрелять.
--
-- Форма машины (кузов, колёса, сиденья, двери, коробки столкновений) — в src/server/World/VehicleModels.luau.
-- Здесь — характеристики и управляемость:
--   Mass         -- масса (почти вся на высоте осей, машина не кувыркается). Тяжелее = инертнее, сильнее таранит
--   Drive        -- ведущие колёса: RWD (задний привод), FWD (передний), AWD (полный)
--   MaxSpeed     -- студов/с вперёд (пешком 16, бегом 24)
--   ReverseSpeed -- студов/с назад
--   Torque       -- общий крутящий момент на ведущих колёсах (разгон и подъём в горку)
--   Brake        -- общий тормозной момент
--   SteerAngle   -- угол поворота передних колёс, градусы
--   MinRadius    -- самый крутой разворот, студов (меньше = вертлявее)
--   YawLow/YawHigh -- скорость разворота на малой и на максимальной скорости, рад/с
--   Grip         -- как сильно машина держит дорогу боком (меньше = больше заносит)
--   Suspension   -- Hz: жёсткость (больше = жёстче, меньше = мягче и раскачивается),
--                   Damping: гашение раскачки (0..1), Up/Down: ход колеса вверх/вниз, студов
--   Health       -- прочность; 0 = взрыв, пассажиры получают урон
--   RespawnTime  -- через сколько секунд после потери машина снова появится на площадке
--   LightBar     -- мигалка на крыше
return {
	-- Знак вращения мотора колёс. Если машины в Studio едут задом при нажатии W, поменяйте на 1.
	DriveSign = -1,
	-- Знак поворота руля. Если машина поворачивает влево при нажатии D, поменяйте на 1.
	SteerSign = -1,

	ShowHull = false, -- true: показать невидимые коробки кузова (оранжевые) и стёкла (синие) для подгонки

	TeamLocked = true,
	AbandonTime = 45, -- брошенная вдали от базы пустая машина возвращается на площадку через N секунд
	RamMinSpeed = 35, -- с какой скорости машина наносит урон сбитому противнику
	RamDamage = 45,
	ExplosionDamage = 60, -- урон сидящим внутри при взрыве

	Types = {
		-- Банда: быстрые и дешёвые, на скорость и внезапность.
		Bandits_Sedan = { -- Мерседес W124: задний привод, лёгкий и вёрткий, мягко идёт в занос
			Name = "Седан",
			Mass = 380,
			Drive = "RWD",
			MaxSpeed = 90,
			ReverseSpeed = 30,
			Torque = 30000,
			Brake = 44000,
			SteerAngle = 34,
			MinRadius = 10,
			YawLow = 2.4,
			YawHigh = 1.3,
			Grip = 6.5,
			Suspension = { Hz = 2.6, Damping = 0.55, Up = 0.6, Down = 0.5 },
			Health = 350,
			RespawnTime = 20,
		},
		Bandits_Pickup = { -- Toyota Tacoma 4x4: полный привод, мягкая высокая подвеска, кузов для стрелков
			Name = "Пикап",
			Mass = 480,
			Drive = "AWD",
			MaxSpeed = 76,
			ReverseSpeed = 28,
			Torque = 42000,
			Brake = 52000,
			SteerAngle = 32,
			MinRadius = 11.5,
			YawLow = 2.1,
			YawHigh = 1.15,
			Grip = 7,
			Suspension = { Hz = 2.1, Damping = 0.5, Up = 0.8, Down = 0.8 },
			Health = 500,
			RespawnTime = 25,
		},
		Bandits_Van = { -- Mercedes Vito: задний привод, тяжёлый, неповоротливый, много мест
			Name = "Фургон",
			Mass = 560,
			Drive = "RWD",
			MaxSpeed = 66,
			ReverseSpeed = 24,
			Torque = 40000,
			Brake = 56000,
			SteerAngle = 30,
			MinRadius = 12.5,
			YawLow = 1.9,
			YawHigh = 1.0,
			Grip = 6.5,
			Suspension = { Hz = 2.3, Damping = 0.55, Up = 0.6, Down = 0.5 },
			Health = 650,
			RespawnTime = 35,
		},

		-- Силовики: тяжелее и крепче, медленнее разгоняются.
		Gov_Patrol = { -- Полицейский седан-перехватчик: задний привод, жёсткая подвеска, самый быстрый
			Name = "Патрульная",
			Mass = 400,
			Drive = "RWD",
			MaxSpeed = 92,
			ReverseSpeed = 30,
			Torque = 34000,
			Brake = 48000,
			SteerAngle = 33,
			MinRadius = 10,
			YawLow = 2.4,
			YawHigh = 1.35,
			Grip = 7.5,
			Suspension = { Hz = 2.9, Damping = 0.6, Up = 0.5, Down = 0.5 },
			Health = 400,
			RespawnTime = 20,
			LightBar = true,
		},
		Gov_SUV = { -- Chevrolet Tahoe: полный привод, тяжёлый, качается на поворотах
			Name = "Внедорожник",
			Mass = 600,
			Drive = "AWD",
			MaxSpeed = 78,
			ReverseSpeed = 28,
			Torque = 48000,
			Brake = 60000,
			SteerAngle = 31,
			MinRadius = 12,
			YawLow = 2.0,
			YawHigh = 1.1,
			Grip = 7,
			Suspension = { Hz = 2.2, Damping = 0.5, Up = 0.8, Down = 0.7 },
			Health = 650,
			RespawnTime = 25,
			LightBar = true,
		},
		Gov_Armored = { -- Mercedes Unimog: полный привод, огромный ход подвески, медленный танк
			Name = "Унимог",
			Mass = 1000,
			Drive = "AWD",
			MaxSpeed = 56,
			ReverseSpeed = 22,
			Torque = 85000,
			Brake = 100000,
			SteerAngle = 28,
			MinRadius = 14,
			YawLow = 1.6,
			YawHigh = 0.85,
			Grip = 7,
			Suspension = { Hz = 1.9, Damping = 0.5, Up = 1.0, Down = 1.0 },
			Health = 1100,
			RespawnTime = 45,
			LightBar = true,
		},
	},

	-- Сколько и каких машин стоит на базе каждой команды. Порядок = порядок площадок.
	Fleet = {
		Bandits = {
			{ Type = "Bandits_Sedan", Count = 2 },
			{ Type = "Bandits_Pickup", Count = 2 },
			{ Type = "Bandits_Van", Count = 1 },
		},
		Gov = {
			{ Type = "Gov_Patrol", Count = 2 },
			{ Type = "Gov_SUV", Count = 2 },
			{ Type = "Gov_Armored", Count = 1 },
		},
	},
}
