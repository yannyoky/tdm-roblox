-- Внешний вид персонажей: пропорции тела и анимации движения.
-- Одежду, лица и кастомизацию делает отдельная система (скины и кастомизация).

local Character = {}

-- Пропорции R15 (HumanoidDescription). 0 — классический «кубический» Roblox, 1 — реалистичные пропорции (Rthro).
-- Рост почти не меняем, чтобы укрытия, окна и двери на картах подходили по высоте.
Character.Body = {
	BodyTypeScale = 0.6,
	ProportionScale = 0.5,
	HeightScale = 1,
	WidthScale = 1,
	DepthScale = 1,
	HeadScale = 1,
}

-- Анимации ходьбы, бега, прыжков (официальный пакет Roblox «Rthro», реалистичнее стандартного).
-- id из документации Roblox: create.roblox.com/docs/animation/using. Пусто — стандартная анимация.
Character.Animations = {
	idle = { "2510197257", "2510196951" },
	walk = "2510202577",
	run = "2510198475",
	jump = "2510197830",
	fall = "2510195892",
	climb = "2510192778",
	swim = "2510199791",
	swimidle = "2510201162",
}

return Character
