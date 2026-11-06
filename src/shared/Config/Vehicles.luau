-- Автопарк фракций. Машины появляются на площадках у базы своей команды.
-- Сесть: E — за руль, F — пассажиром (на телефоне кнопки над машиной). Выйти: прыжок.
-- Чужой машиной воспользоваться нельзя (TeamLocked), но её можно расстрелять.
--
-- Поля машины:
--   Style        -- внешний вид кузова: sedan | pickup | van | suv | armored
--   Width/Length -- размер шасси в студах; вперёд — это -Z модели
--   WheelRadius  -- радиус колёс (больше = выше клиренс, лучше по бездорожью)
--   MaxSpeed     -- студов/с вперёд (пешком 16, бегом 24)
--   ReverseSpeed -- студов/с назад
--   Torque       -- крутящий момент на колесо (разгон и подъём в горку)
--   SteerAngle   -- угол поворота передних колёс, градусы
--   Health       -- прочность; 0 = взрыв, пассажиры получают урон
--   RespawnTime  -- через сколько секунд после потери машина снова появится на площадке
--   Seats        -- места: первое — водитель. Vector3 относительно центра шасси (X вправо, Z назад)
--   Body/Accent  -- цвета кузова
--   LightBar     -- мигалка на крыше
return {
	-- Знак вращения мотора колёс. Если машины в Studio едут задом при нажатии W, поменяйте на 1.
	DriveSign = -1,
	-- Знак поворота руля. Если машина поворачивает влево при нажатии D, поменяйте на 1.
	SteerSign = -1,

	TeamLocked = true,
	AbandonTime = 45, -- брошенная вдали от базы пустая машина возвращается на площадку через N секунд
	RamMinSpeed = 35, -- с какой скорости машина наносит урон сбитому противнику
	RamDamage = 45,
	ExplosionDamage = 60, -- урон сидящим внутри при взрыве

	Types = {
		-- Банда: быстрые и дешёвые, на скорость и внезапность.
		Bandits_Sedan = {
			Name = "Седан",
			Style = "sedan",
			Width = 6,
			Length = 12,
			WheelRadius = 1.4,
			MaxSpeed = 88,
			ReverseSpeed = 30,
			Torque = 9000,
			SteerAngle = 32,
			Health = 350,
			RespawnTime = 20,
			Body = Color3.fromRGB(70, 28, 30),
			Accent = Color3.fromRGB(25, 25, 25),
			Seats = {
				Vector3.new(-1.3, 1, -0.6),
				Vector3.new(1.3, 1, -0.6),
				Vector3.new(-1.3, 1, 2.2),
				Vector3.new(1.3, 1, 2.2),
			},
		},
		Bandits_Pickup = {
			Name = "Пикап",
			Style = "pickup",
			Width = 6.4,
			Length = 14,
			WheelRadius = 1.7,
			MaxSpeed = 74,
			ReverseSpeed = 28,
			Torque = 12000,
			SteerAngle = 30,
			Health = 500,
			RespawnTime = 25,
			Body = Color3.fromRGB(96, 92, 70),
			Accent = Color3.fromRGB(40, 38, 32),
			Seats = {
				Vector3.new(-1.3, 1, -2.4),
				Vector3.new(1.3, 1, -2.4),
				-- кузов: стоят открыто, могут стрелять во все стороны
				Vector3.new(-1.6, 1.4, 2.6),
				Vector3.new(1.6, 1.4, 2.6),
				Vector3.new(0, 1.4, 5),
			},
		},
		Bandits_Van = {
			Name = "Фургон",
			Style = "van",
			Width = 7,
			Length = 15,
			WheelRadius = 1.5,
			MaxSpeed = 64,
			ReverseSpeed = 24,
			Torque = 13000,
			SteerAngle = 28,
			Health = 650,
			RespawnTime = 35,
			Body = Color3.fromRGB(200, 196, 185),
			Accent = Color3.fromRGB(90, 30, 30),
			Seats = {
				Vector3.new(-1.5, 1, -3.4),
				Vector3.new(1.5, 1, -3.4),
				Vector3.new(-1.5, 1, -0.4),
				Vector3.new(1.5, 1, -0.4),
				Vector3.new(-1.5, 1, 2.6),
				Vector3.new(1.5, 1, 2.6),
			},
		},

		-- Силовики: тяжелее и крепче, медленнее разгоняются.
		Gov_Patrol = {
			Name = "Патрульная",
			Style = "sedan",
			Width = 6,
			Length = 12.5,
			WheelRadius = 1.4,
			MaxSpeed = 84,
			ReverseSpeed = 30,
			Torque = 9500,
			SteerAngle = 31,
			Health = 400,
			RespawnTime = 20,
			Body = Color3.fromRGB(235, 235, 240),
			Accent = Color3.fromRGB(40, 70, 160),
			LightBar = true,
			Seats = {
				Vector3.new(-1.3, 1, -0.6),
				Vector3.new(1.3, 1, -0.6),
				Vector3.new(-1.3, 1, 2.2),
				Vector3.new(1.3, 1, 2.2),
			},
		},
		Gov_SUV = {
			Name = "Внедорожник",
			Style = "suv",
			Width = 6.8,
			Length = 13,
			WheelRadius = 1.8,
			MaxSpeed = 72,
			ReverseSpeed = 28,
			Torque = 13000,
			SteerAngle = 30,
			Health = 650,
			RespawnTime = 25,
			Body = Color3.fromRGB(30, 34, 40),
			Accent = Color3.fromRGB(40, 70, 160),
			LightBar = true,
			Seats = {
				Vector3.new(-1.4, 1, -1.2),
				Vector3.new(1.4, 1, -1.2),
				Vector3.new(-1.4, 1, 1.8),
				Vector3.new(1.4, 1, 1.8),
			},
		},
		Gov_Armored = {
			Name = "Бронефургон",
			Style = "armored",
			Width = 7.6,
			Length = 16,
			WheelRadius = 1.9,
			MaxSpeed = 56,
			ReverseSpeed = 22,
			Torque = 17000,
			SteerAngle = 26,
			Health = 1100,
			RespawnTime = 45,
			Body = Color3.fromRGB(55, 65, 55),
			Accent = Color3.fromRGB(40, 70, 160),
			LightBar = true,
			Seats = {
				Vector3.new(-1.6, 1, -3.8),
				Vector3.new(1.6, 1, -3.8),
				Vector3.new(-1.6, 1, -1),
				Vector3.new(1.6, 1, -1),
				Vector3.new(-1.6, 1, 1.8),
				Vector3.new(1.6, 1, 1.8),
				Vector3.new(-1.6, 1, 4.6),
				Vector3.new(1.6, 1, 4.6),
			},
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
