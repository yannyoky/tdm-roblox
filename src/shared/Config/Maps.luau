-- Карты. Описание лежит в MapsData.json (Rojo превращает его в модуль), собирает их
-- src/server/World/MapBuilder.luau, а tools/map_layout.py строит по тому же файлу схему.
--
-- Устройство любой карты:
--   * База каждой команды на краю карты: точки появления, площадки с машинами, защищённая зона.
--   * Передовые точки (на 45% пути к центру): там появляются в режимах с частым возрождением (TDM).
--     В капте все появляются на базе и добираются до зоны сами: пешком, бегом или на машине.
--   * Зоны каптов в глубине карты. Зона может быть повёрнута (rot), её постройки (Props)
--     задаются относительно центра зоны и поворачиваются вместе с ней.
--
-- Поля карты в MapsData.json:
--   Roads   -- { w = ширина, kind = "road" | "dirt" | "path", pts = { {x, z}, ... } }
--              Точки сглаживаются в плавную кривую. "path" — узкая тропа, обходной путь к зоне.
--   Hills   -- { x, z, r = радиус, h = высота }: холмы из Terrain с пологими склонами.
--   Zones   -- { Name, x, z, w, d, rot, Props = { элементы } }
--   Extras  -- элементы в мировых координатах (трамплины и т.п.)
--   Filler  -- случайная застройка: Seed, Count, Area = {x1, z1, x2, z2}, Kinds,
--              StreetShare = доля домов, которые встают вдоль дорог (остальные вразброс).
--              Виды: block, panel, shell, containers, crates, shed, garages, dacha.
--
-- Элементы (k = вид):
--   block      { x, z, w, d, h, rot, access = { "N"|"S"|"E"|"W", "ladder"|"stairs" }, mat, color = {r,g,b} }
--   shell      { x, z, w, d, h, rot, doors = { "N", ... }, mat }  -- с окнами и люком на крышу
--   container  { x, z, rot, stack = 1|2 }   crate { x, z, s }
--   fence/wall { pts = { {x, z}, ... }, h }  -- ломаная; забор 4 (перемахнуть), стена 7 (подтянуться)
--   ramp       { x, z, w, h, len, rot }      -- поднимается в сторону rot (0 = север, 90 = запад)
--   beam       { x, z, y, w, d, h, rot }     -- висячая балка, мостик
-- Стороны: N = -Z, S = +Z, E = +X, W = -X. Север на схеме сверху.
--
-- После правки карты обновите схему: python3 tools/map_layout.py (см. docs/WORLD.md).
local data = require(script.Parent:WaitForChild("MapsData"))

local lobby = data.Lobby
return {
	Order = data.Order,
	Lobby = { Position = Vector3.new(lobby[1], lobby[2], lobby[3]) },
	List = data.List,
}
