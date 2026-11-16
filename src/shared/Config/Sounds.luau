-- Звуки оружия и шагов.
-- Это бесплатные звуки из Creator Store (Audio). Чтобы заменить звук: найдите в Creator Store → Audio
-- нужный (например «rifle shot»), скопируйте Id и впишите сюда в виде "rbxassetid://123456".
-- В комментарии рядом — название звука в магазине и автор, чтобы его можно было найти.
local Sounds = {}

local function id(n: number): string
	return "rbxassetid://" .. n
end

-- Выстрел: звук, громкость, высота тона (меньше 1 — ниже и «тяжелее»), дальность слышимости.
Sounds.Shots = {
	Rifle = { Id = id(18820743226), Volume = 0.9, Pitch = 1, Range = 350 }, -- Rifle Single Shot 2 (CBE_Simon)
	SMG = { Id = id(134975275558568), Volume = 0.8, Pitch = 1.05, Range = 250 }, -- Rifle MP5 Single Shot (CBE_Simon)
	Shotgun = { Id = id(71816202649396), Volume = 1, Pitch = 1, Range = 300 }, -- Shotgun Single Shot (CBE_Simon)
	LMG = { Id = id(18820473061), Volume = 1, Pitch = 0.9, Range = 400 }, -- Rifle Single Shot 1, G3 (CBE_Simon)
	Sniper = { Id = id(98063753863205), Volume = 1, Pitch = 1, Range = 600 }, -- Sniper Rifle Single Shot 1 (CBE_Simon)
	Pistol = { Id = id(92967624763578), Volume = 0.8, Pitch = 1, Range = 250 }, -- Pistol Shot 1 (Dodfoz)
	Revolver = { Id = id(1583819337), Volume = 0.95, Pitch = 1, Range = 300 }, -- Pistol / Revolver Shot (Kosty829)
}
Sounds.DefaultShot = Sounds.Shots.Rifle

-- Перезарядка у каждого оружия своя; если оружия нет в списке — Sounds.Reload.
-- Громкость заметно ниже выстрела: сами записи перезарядки громкие.
Sounds.Reloads = {
	Rifle = { Id = id(140069224599018), Volume = 0.25, Pitch = 1, Range = 40 }, -- Assault Rifle Reloading Audio
	SMG = { Id = id(139644400203673), Volume = 0.25, Pitch = 1, Range = 40 }, -- reload_smg
	LMG = { Id = id(140069224599018), Volume = 0.25, Pitch = 0.85, Range = 40 },
	Shotgun = { Id = id(139827026287805), Volume = 0.25, Pitch = 1, Range = 40 }, -- shotgun_reload
	Sniper = { Id = id(4649193317), Volume = 0.25, Pitch = 1, Range = 40 }, -- sniper reload
	Pistol = { Id = id(5445945972), Volume = 0.25, Pitch = 1, Range = 40 }, -- Glock Reload
	Revolver = { Id = id(5445945972), Volume = 0.25, Pitch = 0.9, Range = 40 },
}
Sounds.Reload = Sounds.Reloads.Rifle

Sounds.Melee = { Id = id(79732830869206), Volume = 0.7, Pitch = 1, Range = 60 } -- swing 2
Sounds.Empty = { Id = id(136577938825060), Volume = 0.6, Pitch = 1, Range = 20 } -- DF1 (сухой щелчок)
Sounds.HitMarker = { Id = "rbxasset://sounds/hit.wav", Volume = 0.4, Pitch = 1.6 }

-- Шаги: отдельный звук на каждое касание стопы (варианты чередуются, чтобы не звучало одинаково).
-- Звучат в такт анимации: шаг — когда стопа опускается на землю.
Sounds.Footsteps = {
	Ids = { -- Black Laboratory concrete footstep 1–8 (Diman_x86)
		id(104345504554799),
		id(70639393862430),
		id(108290664490396),
		id(96955798612091),
		id(120195545352847),
		id(78982375383648),
		id(112000835797556),
		id(106961831442199),
	},
	Walk = { Volume = 0.45, Pitch = 1 },
	Sprint = { Volume = 0.7, Pitch = 1.05 },
	Crouch = { Volume = 0.15, Pitch = 0.9 },
	Range = 70,
}

return Sounds
