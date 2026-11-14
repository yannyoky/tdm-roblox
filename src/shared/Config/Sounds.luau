-- Звуки оружия и шагов.
-- Сейчас стоят встроенные звуки клиента Roblox (rbxasset://), чтобы было хоть что-то.
-- Настоящие звуки выстрелов: Creator Store → Audio, поиск «gunshot», «rifle», «pistol», «reload»
-- (бесплатные, лучше от автора Roblox). Скопируйте Id и впишите сюда в виде "rbxassetid://123456".
local Sounds = {}

local SHOT = "rbxasset://sounds/paintball.wav"

-- Выстрел: звук, громкость, высота тона (меньше 1 — ниже и «тяжелее»), дальность слышимости.
Sounds.Shots = {
	Rifle = { Id = SHOT, Volume = 0.9, Pitch = 0.75, Range = 350 },
	SMG = { Id = SHOT, Volume = 0.8, Pitch = 0.95, Range = 250 },
	Shotgun = { Id = SHOT, Volume = 1, Pitch = 0.5, Range = 300 },
	LMG = { Id = SHOT, Volume = 1, Pitch = 0.6, Range = 400 },
	Sniper = { Id = SHOT, Volume = 1, Pitch = 0.42, Range = 600 },
	Pistol = { Id = SHOT, Volume = 0.8, Pitch = 1, Range = 250 },
	Revolver = { Id = SHOT, Volume = 0.95, Pitch = 0.7, Range = 300 },
}
Sounds.DefaultShot = { Id = SHOT, Volume = 0.8, Pitch = 0.8, Range = 300 }

Sounds.Melee = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.7, Pitch = 1, Range = 60 }
Sounds.Reload = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.6, Pitch = 0.8, Range = 40 }
Sounds.Empty = { Id = "rbxasset://sounds/snap.wav", Volume = 0.5, Pitch = 1.4, Range = 20 }
Sounds.HitMarker = { Id = "rbxasset://sounds/hit.wav", Volume = 0.4, Pitch = 1.6 }

-- Шаги: скорость и громкость звука бега в зависимости от темпа.
Sounds.Footsteps = {
	Id = "rbxasset://sounds/action_footsteps_plastic.mp3", -- стандартный звук шагов Roblox
	Walk = { Speed = 1, Volume = 0.45 },
	Sprint = { Speed = 1.45, Volume = 0.75 },
	Crouch = { Speed = 0.7, Volume = 0.15 },
	Range = 70,
}

return Sounds
