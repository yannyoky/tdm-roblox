-- Настройки игрока на клиенте: читаются из атрибута Settings (его ставит сервер),
-- применяются сразу и сохраняются на сервере с небольшой задержкой.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Settings)
local Net = require(Shared.Net)

local player = Players.LocalPlayer

local PlayerSettings = {}

local values: { [string]: any } = {}
local listeners: { (key: string, value: any) -> () } = {}
local aiming = false
local saveScheduled = false
local loadedFromServer = false

for key, def in Config.List do
	values[key] = def.Default
end

local function applySensitivity()
	local base = values.Sensitivity
	UserInputService.MouseDeltaSensitivity = if aiming then base * values.AimSensitivity else base
end

local function notify(key: string)
	if key == "Sensitivity" or key == "AimSensitivity" then
		applySensitivity()
	end
	for _, fn in listeners do
		task.spawn(fn, key, values[key])
	end
end

function PlayerSettings.get(key: string): any
	return values[key]
end

function PlayerSettings.set(key: string, value: any)
	local def = Config.List[key]
	if not def then
		return
	end
	if def.Type == "Number" then
		value = math.clamp(math.floor(value / def.Step + 0.5) * def.Step, def.Min, def.Max)
	end
	if values[key] == value then
		return
	end
	values[key] = value
	notify(key)
	if not saveScheduled then
		saveScheduled = true
		task.delay(1.5, function()
			saveScheduled = false
			Net.get("SaveSettings"):FireServer(values)
		end)
	end
end

-- fn(key, value) вызывается при каждом изменении (и один раз для всех ключей при загрузке).
function PlayerSettings.onChanged(fn: (key: string, value: any) -> ())
	table.insert(listeners, fn)
end

-- WeaponController сообщает, когда игрок смотрит в прицел.
local aimListeners: { (on: boolean) -> () } = {}

function PlayerSettings.setAiming(on: boolean)
	local changed = aiming ~= on
	aiming = on
	applySensitivity()
	if changed then
		for _, fn in aimListeners do
			task.spawn(fn, on)
		end
	end
end

-- fn(on) вызывается, когда игрок входит в прицел или выходит из него.
function PlayerSettings.onAimingChanged(fn: (on: boolean) -> ())
	table.insert(aimListeners, fn)
end

function PlayerSettings.isAiming(): boolean
	return aiming
end

function PlayerSettings.init()
	local function load()
		local json = player:GetAttribute("Settings")
		if loadedFromServer or type(json) ~= "string" then
			return
		end
		local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
		if not ok or type(data) ~= "table" then
			return
		end
		loadedFromServer = true
		for key, def in Config.List do
			local v = data[key]
			if (def.Type == "Number" and type(v) == "number") or (def.Type == "Toggle" and type(v) == "boolean") then
				values[key] = v
			end
		end
		for key in Config.List do
			notify(key)
		end
	end
	player:GetAttributeChangedSignal("Settings"):Connect(load)
	load()
	applySensitivity()
end

return PlayerSettings
