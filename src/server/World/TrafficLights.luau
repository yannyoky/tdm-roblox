-- Светофоры города (перекрёстки строит World/CityBuilder.luau, тайминги — Config/City.Signals).
-- Цикл на каждом перекрёстке: зелёный север–юг → жёлтый → все красные → зелёный восток–запад →
-- жёлтый → все красные. Сдвиг по перекрёсткам даёт «зелёную волну».
-- Состояние пишется в атрибуты модели перекрёстка (NS, EW = "G" | "Y" | "R"), по ним едет трафик;
-- пешеходный зелёный (Walk) горит для перехода через улицу, по которой сейчас красный.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.City)

local TrafficLights = {}

local OFF = Color3.fromRGB(26, 26, 28)

type Signal = {
	model: Model,
	offset: number,
	lamps: { BasePart },
	ped: { BasePart },
	ns: string,
	ew: string,
}

local signals: { Signal } = {}
local byKey: { [string]: Signal } = {}

-- Состояние осей в момент t для перекрёстка со сдвигом offset.
local function phase(t: number, offset: number): (string, string)
	local c = Config.Signals
	local half = c.Green + c.Yellow + c.AllRed
	local p = (t + offset) % (half * 2)
	if p < c.Green then
		return "G", "R"
	elseif p < c.Green + c.Yellow then
		return "Y", "R"
	elseif p < half then
		return "R", "R"
	elseif p < half + c.Green then
		return "R", "G"
	elseif p < half + c.Green + c.Yellow then
		return "R", "Y"
	end
	return "R", "R"
end

local function paint(lamp: BasePart, on: boolean)
	if on then
		lamp.Material = Enum.Material.Neon
		lamp.Color = lamp:GetAttribute("On") or Color3.new(1, 1, 1)
	else
		lamp.Material = Enum.Material.SmoothPlastic
		lamp.Color = OFF
	end
end

local function apply(s: Signal, ns: string, ew: string)
	s.ns, s.ew = ns, ew
	s.model:SetAttribute("NS", ns)
	s.model:SetAttribute("EW", ew)
	local state = { NS = ns, EW = ew }
	for _, lamp in s.lamps do
		paint(lamp, state[lamp:GetAttribute("Axis")] == lamp:GetAttribute("Color"))
	end
	for _, lamp in s.ped do
		local axis = lamp:GetAttribute("Axis")
		local other = if axis == "NS" then ew else ns
		local walk = state[axis] == "R" and other == "G"
		paint(lamp, (lamp:GetAttribute("Kind") == "Walk") == walk)
	end
end

function TrafficLights.attach(map: Instance?)
	table.clear(signals)
	table.clear(byKey)
	local city = map and map:FindFirstChild("City")
	local folder = city and city:FindFirstChild("Intersections")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") or not model:GetAttribute("Signalized") then
			continue
		end
		local s: Signal = {
			model = model,
			offset = ((model:GetAttribute("I") or 0) + (model:GetAttribute("J") or 0)) * Config.Signals.Offset,
			lamps = {},
			ped = {},
			ns = "",
			ew = "",
		}
		for _, inst in model:GetChildren() do
			if inst:IsA("BasePart") then
				if inst.Name == "Lamp" then
					table.insert(s.lamps, inst)
				elseif inst.Name == "PedLamp" then
					table.insert(s.ped, inst)
				end
			end
		end
		table.insert(signals, s)
		byKey[model.Name] = s
	end
end

-- Сигнал для машин оси axis ("NS" | "EW") на перекрёстке (i, j): "G" | "Y" | "R"; без светофора — "G".
function TrafficLights.get(i: number, j: number, axis: string): string
	local s = byKey[string.format("I_%d_%d", i, j)]
	if not s then
		return "G"
	end
	return if axis == "NS" then s.ns else s.ew
end

function TrafficLights.init(mapChanged: RBXScriptSignal)
	mapChanged:Connect(TrafficLights.attach)
	local map = workspace:FindFirstChild("Map")
	if map then
		TrafficLights.attach(map)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 or #signals == 0 then
			return
		end
		acc = 0
		local t = workspace:GetServerTimeNow()
		for _, s in signals do
			if not s.model.Parent then
				continue
			end
			local ns, ew = phase(t, s.offset)
			if ns ~= s.ns or ew ~= s.ew then
				apply(s, ns, ew)
			end
		end
	end)
end

return TrafficLights
