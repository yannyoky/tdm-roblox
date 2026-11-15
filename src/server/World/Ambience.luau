-- Свет, небо, облака и пост-эффекты. Значения — Config/Decor.Lighting
-- (Default + поля конкретной карты; таблицы эффектов сливаются по полям). Вызывается при смене карты.
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
	Clouds = "Clouds", -- живёт в Workspace.Terrain
}

local function effect(className: string): Instance
	local parent: Instance = if className == "Clouds" then workspace.Terrain else Lighting
	local existing = parent:FindFirstChildOfClass(className :: any)
	if existing then
		return existing
	end
	local inst = Instance.new(className :: any)
	inst.Parent = parent
	return inst
end

function Ambience.apply(mapId: string?)
	local base = Config.Lighting.Default
	local over = (mapId and Config.Lighting[mapId]) or {}
	for key, value in base do
		local v = if over[key] ~= nil then over[key] else value
		-- Таблица эффекта карты дополняет Default, а не заменяет его целиком.
		if type(value) == "table" and type(over[key]) == "table" then
			v = table.clone(value)
			for k2, v2 in over[key] do
				v[k2] = v2
			end
		end
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
