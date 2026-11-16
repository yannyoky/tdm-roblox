-- Смена дня и ночи и погода (сервер). Работает на картах с DayNight = true в MapsData.json (город);
-- на остальных картах свет фиксированный (World/Ambience.luau).
--
-- Время идёт в Lighting.ClockTime (сутки за Config/City.DayNight.DayMinutes минут), свет плавно
-- смешивается между пресетами Day, Dusk и Night по высоте солнца, фонари загораются вечером.
-- Погода (Clear, Cloudy, Rain, Storm) меняется сама, переходы плавные. Клиенту передаётся через
-- атрибуты ReplicatedStorage: Weather (имя), RainIntensity (0..1), LightningStrike (счётчик вспышек).
-- Капли, звук дождя, мокрый асфальт и вспышки молний рисует src/client/Weather.luau.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.City)
local MapsConfig = require(Shared.Config.Maps)
local Detailer = require(script.Parent.Detailer)
local DecorConfig = require(Shared.Config.Decor)

local Environment = {}

local enabled = false
local clock = Config.DayNight.StartTime
local lampsNight: boolean? = nil
local windowsNight: boolean? = nil

-- Погода: текущие значения плавно идут к целевым.
local W = Config.Weather
local current = table.clone(W.States[W.Start] or W.States.Clear)
local target = current
local weatherName = W.Start
local weatherLeft = 0
local strikes = 0
local nextStrike = 0

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function pickWeather(): string
	local total = 0
	for _, s in W.States do
		total += s.Weight
	end
	local r = math.random() * total
	for name, s in W.States do
		r -= s.Weight
		if r <= 0 then
			return name
		end
	end
	return "Clear"
end

local function setWeather(name: string)
	weatherName = name
	target = W.States[name] or W.States.Clear
	weatherLeft = math.random(W.Duration[1], W.Duration[2])
	ReplicatedStorage:SetAttribute("Weather", name)
end

-- Окна с тегом NightWindow (ставит CityBuilder) ночью светятся тёплым светом.
local function setWindows(night: boolean)
	local lit = Config.DayNight.LitColor
	for _, p in CollectionService:GetTagged("NightWindow") do
		if not p:IsA("BasePart") then
			continue
		end
		if p:GetAttribute("DayColor") == nil then
			p:SetAttribute("DayColor", p.Color)
			p:SetAttribute("DayMaterial", p.Material.Name)
			p:SetAttribute("DayTransparency", p.Transparency)
		end
		if night then
			p.Color = lit
			p.Material = Enum.Material.Neon
			p.Transparency = 0
		else
			p.Color = p:GetAttribute("DayColor")
			p.Material = (Enum.Material :: any)[p:GetAttribute("DayMaterial")]
			p.Transparency = p:GetAttribute("DayTransparency")
		end
	end
end

-- Смесь трёх пресетов света по высоте солнца.
local function blend(): { [string]: any }
	local sun = math.sin((clock - 6) / 12 * math.pi) -- 1 в полдень, 0 на рассвете и закате, -1 в полночь
	local wDay = smoothstep(0.05, 0.4, sun)
	local wNight = smoothstep(0.02, -0.18, sun)
	local wDusk = math.max(0, 1 - wDay - wNight)
	local D, K, Nt = Config.DayNight.Day, Config.DayNight.Dusk, Config.DayNight.Night
	local out = {}
	for key, v in D do
		if typeof(v) == "Color3" then
			local c = v:Lerp(K[key], wDusk / math.max(wDusk + wDay, 1e-3))
			out[key] = c:Lerp(Nt[key], wNight)
		else
			out[key] = v * wDay + K[key] * wDusk + Nt[key] * wNight
		end
	end
	out.sun = sun
	return out
end

local function applyLight()
	local L = blend()
	local w = current
	Lighting.ClockTime = clock
	-- Пасмурно и дождь: меньше прямого солнца, свет ровнее.
	Lighting.Brightness = L.Brightness * w.Light
	Lighting.ExposureCompensation = L.ExposureCompensation
	Lighting.Ambient = L.Ambient
	Lighting.OutdoorAmbient = L.OutdoorAmbient:Lerp(Color3.fromRGB(110, 114, 122), (1 - w.Light) * 0.5 * math.max(L.sun, 0))
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		atm.Density = w.Density
		atm.Haze = w.Haze
		atm.Color = L.AtmosphereColor:Lerp(Color3.fromRGB(150, 154, 160), w.Rain * 0.6 * math.max(L.sun, 0))
		atm.Decay = L.AtmosphereDecay
		atm.Glare = if w.Rain > 0.1 then 0 else 0.35 * math.max(L.sun, 0)
	end
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then
		cc.TintColor = L.Tint
		cc.Saturation = -0.2 - w.Rain * 0.12
	end
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Intensity = 0.05 * math.clamp(w.Light * 2 - 1, 0, 1)
	end
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Cover = w.Clouds
		clouds.Density = w.CloudDensity
		clouds.Color = Color3.fromRGB(245, 245, 250):Lerp(Color3.fromRGB(120, 124, 132), w.Rain)
	end
	-- Фонари: вечером и ночью, а в сильный дождь и днём.
	local night = clock >= DecorConfig.Lamps.NightFrom or clock <= DecorConfig.Lamps.NightTo or w.Rain > 0.8
	if night ~= lampsNight then
		lampsNight = night
		ReplicatedStorage:SetAttribute("Night", night) -- фары машин (client/VehicleLights)
		Detailer.updateLamps(if night then 0 else 12)
	end
	-- Окна загораются только в темноте (не днём в ливень).
	local dark = clock >= DecorConfig.Lamps.NightFrom or clock <= DecorConfig.Lamps.NightTo
	if dark ~= windowsNight then
		windowsNight = dark
		setWindows(dark)
	end
end

local function onMap(map: Instance?)
	local id = map and map:GetAttribute("MapId")
	local cfg = id and MapsConfig.List[id]
	enabled = cfg ~= nil and cfg.DayNight == true and Config.DayNight.Enabled
	lampsNight = nil
	windowsNight = nil
	if enabled then
		clock = Config.DayNight.StartTime
		current = table.clone(W.States[W.Start] or W.States.Clear)
		setWeather(W.Start)
		applyLight()
	else
		ReplicatedStorage:SetAttribute("Weather", "Clear")
		ReplicatedStorage:SetAttribute("RainIntensity", 0)
		-- Свет карты фиксированный (Ambience): ночь, если время вечернее.
		local t = Lighting.ClockTime
		ReplicatedStorage:SetAttribute("Night", t >= DecorConfig.Lamps.NightFrom or t <= DecorConfig.Lamps.NightTo)
	end
end

function Environment.init(mapChanged: RBXScriptSignal)
	ReplicatedStorage:SetAttribute("Weather", "Clear")
	ReplicatedStorage:SetAttribute("RainIntensity", 0)
	ReplicatedStorage:SetAttribute("LightningStrike", 0)
	mapChanged:Connect(onMap)
	onMap(workspace:FindFirstChild("Map"))
	-- Для проверки в Studio: из командной строки сервера
	--   game.ReplicatedStorage:SetAttribute("DebugTime", 22)
	--   game.ReplicatedStorage:SetAttribute("DebugWeather", "Storm")
	ReplicatedStorage:GetAttributeChangedSignal("DebugTime"):Connect(function()
		local t = ReplicatedStorage:GetAttribute("DebugTime")
		if type(t) == "number" then
			Environment.setTime(t)
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal("DebugWeather"):Connect(function()
		local name = ReplicatedStorage:GetAttribute("DebugWeather")
		if type(name) == "string" and W.States[name] then
			Environment.setWeather(name)
			current = table.clone(W.States[name])
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not enabled then
			return
		end
		clock = (clock + dt * 24 / (Config.DayNight.DayMinutes * 60)) % 24
		acc += dt
		if acc < 0.25 then
			return
		end
		local step = acc
		acc = 0

		-- Погода.
		if W.Enabled then
			weatherLeft -= step
			if weatherLeft <= 0 then
				setWeather(pickWeather())
			end
			local k = math.clamp(step / W.Transition, 0, 1)
			for key, v in target do
				if type(v) == "number" and type(current[key]) == "number" then
					current[key] = lerp(current[key], v, k * 3) -- ~95% пути за Transition
				end
			end
			current.Lightning = target.Lightning
			local rain = math.floor(current.Rain * 100 + 0.5) / 100
			if rain ~= ReplicatedStorage:GetAttribute("RainIntensity") then
				ReplicatedStorage:SetAttribute("RainIntensity", rain)
			end
			-- Молнии в грозу: счётчик вспышек, клиенты показывают вспышку и гром.
			if current.Lightning and current.Rain > 0.6 then
				nextStrike -= step
				if nextStrike <= 0 then
					strikes += 1
					ReplicatedStorage:SetAttribute("LightningStrike", strikes)
					nextStrike = math.random(8, 25)
				end
			end
		end
		applyLight()
	end)
end

-- Для тестов и админов: сразу поставить время/погоду.
function Environment.setTime(t: number)
	clock = t % 24
end

function Environment.setWeather(name: string)
	if W.States[name] then
		setWeather(name)
	end
end

return Environment
