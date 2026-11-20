-- Реалистичные пропорции тела и анимации движения (Config/Character).
-- Анимации ставит CharacterAnimService (игроки) и BotService (боты).
-- Пропорции применяет система внешности (applyToDescription / applyBody).
local Config = require(script.Parent.Config.Character)

local CharacterLook = {}

-- Имя папки в скрипте Animate -> имя объекта Animation внутри.
local ANIMATE_SLOTS = {
	walk = { "WalkAnim" },
	run = { "RunAnim" },
	jump = { "JumpAnim" },
	fall = { "FallAnim" },
	climb = { "ClimbAnim" },
	swim = { "Swim" },
	swimidle = { "SwimIdle" },
	idle = { "Animation1", "Animation2" },
	sit = { "SitAnim" },
}

local function id(value: string): string
	return "rbxassetid://" .. value
end

-- Пропорции в описании (для новых моделей, например ботов).
function CharacterLook.applyToDescription(desc: HumanoidDescription)
	for key, value in Config.Body do
		pcall(function()
			(desc :: any)[key] = value
		end)
	end
end

-- Пропорции уже существующего персонажа игрока. Только на сервере, может подождать.
function CharacterLook.applyBody(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	local ok, desc = pcall(hum.GetAppliedDescription, hum)
	if not ok or not desc then
		return
	end
	local changed = false
	for key, value in Config.Body do
		if (desc :: any)[key] ~= value then
			(desc :: any)[key] = value
			changed = true
		end
	end
	if changed then
		pcall(hum.ApplyDescription, hum, desc)
	end
end

-- Меняет анимации в скрипте Animate персонажа игрока. Animate сам подхватывает изменения.
function CharacterLook.applyAnimations(char: Model)
	local animate = char:FindFirstChild("Animate") or char:WaitForChild("Animate", 5)
	if not animate then
		return
	end
	for slot, value in Config.Animations do
		local holder = animate:FindFirstChild(slot)
		local names = ANIMATE_SLOTS[slot]
		if holder and names then
			local values = if type(value) == "table" then value else { value }
			for i, name in names do
				local anim = holder:FindFirstChild(name)
				local v = values[i] or values[1]
				if anim and anim:IsA("Animation") and v and v ~= "" then
					anim.AnimationId = id(v)
				end
			end
		end
	end
end

-- id анимаций для ботов (BotService запускает треки сам): имя -> rbxassetid.
function CharacterLook.botAnimations(): { [string]: string }
	local out = {}
	for slot, value in Config.Animations do
		local v = if type(value) == "table" then value[1] else value
		if v and v ~= "" then
			out[slot] = id(v)
		end
	end
	return out
end

return CharacterLook
