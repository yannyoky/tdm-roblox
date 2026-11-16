-- Геометрия города (Config/City): где улицы, перекрёстки, кварталы и полосы.
-- Чистая математика без Instance: её используют сборка города (сервер), трафик, пешеходы и клиент.
--
-- Индексы: улицы (линии сетки) 0..N по каждой оси, кварталы 1..N.
-- Вертикальная улица i идёт с севера на юг по x = line(i), горизонтальная j — по z = line(j).
-- Движение правостороннее: полосы направления d лежат справа от осевой (CityGrid.right(d)).
local Config = require(script.Parent:WaitForChild("Config"):WaitForChild("City"))

local CityGrid = {}

local N = Config.Blocks
local B = Config.BlockSize
local R = Config.RoadWidth

CityGrid.N = N
CityGrid.Pitch = B + R
CityGrid.Total = N * B + (N + 1) * R -- от края до края по внешним улицам
CityGrid.Half = CityGrid.Total / 2
CityGrid.Size = CityGrid.Total + 2 * Config.Margin -- сторона карты

-- Направления: N = -Z, S = +Z, E = +X, W = -X.
CityGrid.Dirs = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}
CityGrid.Opposite = { N = "S", S = "N", E = "W", W = "E" }

-- Координата улицы с индексом i (0..N).
function CityGrid.line(i: number): number
	return -CityGrid.Total / 2 + R / 2 + i * CityGrid.Pitch
end

-- Центр перекрёстка улиц i и j.
function CityGrid.intersection(i: number, j: number): Vector3
	return Vector3.new(CityGrid.line(i), 0, CityGrid.line(j))
end

-- Центр квартала (col, row), 1..N; row 1 — самый северный.
function CityGrid.blockCenter(col: number, row: number): Vector3
	return Vector3.new((CityGrid.line(col - 1) + CityGrid.line(col)) / 2, 0, (CityGrid.line(row - 1) + CityGrid.line(row)) / 2)
end

-- Какие улицы выходят из перекрёстка: { N = true, ... }.
function CityGrid.legs(i: number, j: number): { [string]: boolean }
	return { N = j > 0, S = j < N, W = i > 0, E = i < N }
end

-- Вправо от направления движения (в плоскости XZ).
function CityGrid.right(d: Vector3): Vector3
	return Vector3.new(-d.Z, 0, d.X)
end

-- Смещение центра полосы lane (1 — у осевой, LanesPerDirection — у тротуара) вправо от оси дороги.
function CityGrid.laneOffset(lane: number): number
	return Config.Median / 2 + (lane - 0.5) * Config.LaneWidth
end

-- Ось движения по направлению: "NS" или "EW".
function CityGrid.axis(d: Vector3): string
	return if math.abs(d.Z) > math.abs(d.X) then "NS" else "EW"
end

-- Ближайшая к точке улица: возвращает "V"/"H", индекс и расстояние до оси.
function CityGrid.nearestRoad(p: Vector3): (string, number, number)
	local function nearest(v: number): (number, number)
		local i = math.clamp(math.floor((v + CityGrid.Total / 2 - R / 2) / CityGrid.Pitch + 0.5), 0, N)
		return i, math.abs(v - CityGrid.line(i))
	end
	local ix, dx = nearest(p.X)
	local iz, dz = nearest(p.Z)
	if dx <= dz then
		return "V", ix, dx
	end
	return "H", iz, dz
end

-- Точка на проезжей части (а не на тротуаре или в квартале)?
function CityGrid.onRoad(p: Vector3): boolean
	local _, _, d = CityGrid.nearestRoad(p)
	return d <= R / 2 and math.abs(p.X) <= CityGrid.Half and math.abs(p.Z) <= CityGrid.Half
end

-- Вид квартала из Config.City.Lots.
function CityGrid.lot(col: number, row: number): string
	local r = Config.Lots[row]
	return r and r[col] or "residential"
end

return CityGrid
