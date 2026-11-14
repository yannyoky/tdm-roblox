-- Свет, небо и пост-эффекты для обычной графики. Значения — Config/Decor.Lighting
-- (Default + поля конкретной карты). Вызывается при смене карты.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Decor)
local Detailer = require(script.Parent.Detailer)

local Ambience = {}

-- Эффекты с этими полями: класс и имя, под которым ищем/создаём.
local EFFECTS = {
	Atmosphere = "Atmosphere",
	ColorCorrection = "ColorCorrectionEffect",
	Bloom = "BloomEffect",
	SunRays = "SunRaysEffect",
}

local function effect(className: string): Instance
	local existing = Lighting:FindFirstChildOfClass(className :: any)
	if existing then
		return existing
	end
	local inst = Instance.new(className :: any)
	inst.Parent = Lighting
	return inst
end

function Ambience.apply(mapId: string?)
	local base = Config.Lighting.Default
	local over = (mapId and Config.Lighting[mapId]) or {}
	for key, value in base do
		local v = if over[key] ~= nil then over[key] else value
		local className = EFFECTS[key]
		if className then
			local inst = effect(className)
			for prop, pv in v do
				pcall(function()
					(inst :: any)[prop] = pv
				end)
			end
		else
			pcall(function()
				(Lighting :: any)[key] = v
			end)
		end
	end
	Lighting.GlobalShadows = true
	-- Размытие дали из шаблона Studio мешает целиться: выключаем.
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end
	Detailer.updateLamps(Lighting.ClockTime)
end

return Ambience
