-- Оружие. FireRate — выстрелов в секунду, Range — дальность в studs.
return {
	DefaultLoadout = { "Rifle", "Pistol", "Knife" },

	List = {
		Rifle = {
			DisplayName = "Автомат",
			Damage = 22,
			HeadshotMultiplier = 1.5,
			FireRate = 10,
			Range = 300,
			Automatic = true,
			MagSize = 30,
			ReloadTime = 2.2,
			HandleSize = Vector3.new(0.4, 0.8, 2.4),
			Color = Color3.fromRGB(45, 45, 50),
		},
		Pistol = {
			DisplayName = "Пистолет",
			Damage = 30,
			HeadshotMultiplier = 1.6,
			FireRate = 4,
			Range = 200,
			Automatic = false,
			MagSize = 12,
			ReloadTime = 1.4,
			HandleSize = Vector3.new(0.3, 0.6, 1),
			Color = Color3.fromRGB(30, 30, 30),
		},
		Knife = {
			DisplayName = "Нож",
			Damage = 55,
			HeadshotMultiplier = 1,
			FireRate = 1.5,
			Range = 7,
			Automatic = false,
			Melee = true,
			HandleSize = Vector3.new(0.2, 0.4, 1.4),
			Color = Color3.fromRGB(180, 180, 190),
		},
	},
}
