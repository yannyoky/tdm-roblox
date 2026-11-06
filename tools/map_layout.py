#!/usr/bin/env python3
"""Раскладка карт для схемы (вид сверху) без Roblox Studio.

Повторяет расстановку из src/server/World/MapBuilder.luau: сглаживание дорог,
базы, передовые точки, зоны, холмы и случайную застройку с тем же генератором
случайных чисел, поэтому схема совпадает с картой в игре.

Запуск: python3 tools/map_layout.py > tools/out/layout.json
Предупреждения о пересечениях (холм на дороге и т.п.) пишутся в stderr.
"""
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "src", "shared", "Config", "MapsData.json")

TEAM_ORDER = ["Bandits", "Gov"]
BASE_W, BASE_D = 110, 84
SMOOTH_STEPS = 6
SIDES = {"N": (0, -1), "S": (0, 1), "E": (1, 0), "W": (-1, 0)}


class Rng:
    """MINSTD, как Rng в MapBuilder.luau."""

    def __init__(self, seed):
        s = int(seed) % 2147483647
        if s <= 0:
            s += 2147483646
        self.s = s

    def next(self):
        self.s = (self.s * 48271) % 2147483647
        return self.s

    def float(self):
        return (self.next() - 1) / 2147483646

    def range(self, a, b):
        return a + self.float() * (b - a)

    def int(self, a, b):
        return a + math.floor(self.float() * (b - a + 1))


def rot_xz(lx, lz, deg):
    """Как CFrame.Angles(0, rad, 0) * Vector3(lx, 0, lz)."""
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    return c * lx + s * lz, -s * lx + c * lz


def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return tuple(
        0.5 * (2 * p1[i] + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2 + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3)
        for i in range(2)
    )


def smooth(pts):
    pts = [tuple(p) for p in pts]
    if len(pts) < 3:
        return pts
    out = [pts[0]]
    n = len(pts)
    for i in range(n - 1):
        p0 = pts[max(i - 1, 0)]
        p1, p2 = pts[i], pts[i + 1]
        p3 = pts[min(i + 2, n - 1)]
        for k in range(1, SMOOTH_STEPS + 1):
            out.append(catmull(p0, p1, p2, p3, k / SMOOTH_STEPS))
    return out


def dist_seg(p, a, b):
    abx, abz = b[0] - a[0], b[1] - a[1]
    l2 = abx * abx + abz * abz
    t = 0 if l2 == 0 else max(0, min(1, ((p[0] - a[0]) * abx + (p[1] - a[1]) * abz) / l2))
    return math.hypot(p[0] - (a[0] + abx * t), p[1] - (a[1] + abz * t))


class Occupancy:
    def __init__(self):
        self.circles = []
        self.segments = []

    def add_circle(self, x, z, r):
        self.circles.append((x, z, r))

    def add_segment(self, a, b, r):
        self.segments.append((a, b, r))

    def free(self, x, z, r):
        for cx, cz, cr in self.circles:
            if math.hypot(cx - x, cz - z) < cr + r:
                return False
        for a, b, sr in self.segments:
            if dist_seg((x, z), a, b) < sr + r * 0.55:
                return False
        return True


# ---- Генераторы застройки (порядок вызовов rng как в Luau!) ----

def g_block(rng, x, z, rot):
    w, d = rng.int(14, 28), rng.int(12, 24)
    h = rng.int(9, 22)
    side = ["N", "S", "E", "W"][rng.int(1, 4) - 1]
    kind = "stairs" if rng.float() < 0.4 else "ladder"
    return [{"k": "block", "x": x, "z": z, "w": w, "d": d, "h": h, "rot": rot, "access": [side, kind]}], max(w, d) / 2 + 5


def g_panel(rng, x, z, rot):
    w, d = rng.int(36, 56), rng.int(12, 15)
    h = rng.int(16, 24)
    side = "E" if rng.float() < 0.5 else "W"
    return [{"k": "block", "x": x, "z": z, "w": w, "d": d, "h": h, "rot": rot, "access": [side, "ladder"], "mat": "Concrete"}], w / 2 + 5


def g_shell(rng, x, z, rot):
    w, d = rng.int(16, 28), rng.int(14, 22)
    h = rng.int(9, 12)
    sides = ["N", "S", "E", "W"]
    doors = [sides[rng.int(1, 4) - 1]]
    if rng.float() < 0.6:
        second = sides[rng.int(1, 4) - 1]
        if second != doors[0]:
            doors.append(second)
    return [{"k": "shell", "x": x, "z": z, "w": w, "d": d, "h": h, "rot": rot, "doors": doors}], max(w, d) / 2 + 5


def g_containers(rng, x, z, rot):
    items = []
    n = rng.int(1, 3)
    for i in range(1, n + 1):
        lx, lz = (i - (n + 1) / 2) * 9, rng.range(-3, 3)
        ox, oz = rot_xz(lx, lz, rot)
        stack = 2 if rng.float() < 0.35 else 1
        items.append({"k": "container", "x": x + ox, "z": z + oz, "rot": rot, "stack": stack})
    return items, 16


def g_crates(rng, x, z, rot):
    items = []
    for _ in range(rng.int(2, 5)):
        items.append({"k": "crate", "x": x + rng.range(-6, 6), "z": z + rng.range(-6, 6), "s": rng.int(3, 4)})
    return items, 9


def g_shed(rng, x, z, rot):
    return [{"k": "block", "x": x, "z": z, "w": 7, "d": 7, "h": rng.int(5, 7), "rot": rot, "mat": "WoodPlanks"}], 7


def g_garages(rng, x, z, rot):
    n = rng.int(4, 8)
    w = n * 6
    return [{"k": "block", "x": x, "z": z, "w": w, "d": 8, "h": rng.int(5, 6), "rot": rot, "mat": "CorrodedMetal"}], w / 2 + 4


def g_dacha(rng, x, z, rot):
    W, D = rng.int(26, 34), rng.int(22, 30)
    gate = rng.range(-W / 2 + 4, W / 2 - 8)
    hx = rng.range(-3, 3)

    def p(lx, lz):
        ox, oz = rot_xz(lx, lz, rot)
        return [x + ox, z + oz]

    x0, x1, z0, z1 = -W / 2, W / 2, -D / 2, D / 2
    hpx, hpz = p(hx, -D / 6)
    items = [
        {"k": "fence", "pts": [p(gate + 5, z1), p(x1, z1), p(x1, z0), p(x0, z0), p(x0, z1), p(gate, z1)]},
        {"k": "shell", "x": hpx, "z": hpz, "w": 12, "d": 10, "h": 8, "rot": rot, "doors": ["S"], "mat": "WoodPlanks"},
    ]
    if rng.float() < 0.5:
        sx, sz = p(x1 - 5, z1 - 6)
        items.append({"k": "block", "x": sx, "z": sz, "w": 5, "d": 5, "h": 5, "rot": rot, "mat": "WoodPlanks"})
    return items, max(W, D) / 2 + 5


FILLERS = {
    "block": g_block, "panel": g_panel, "shell": g_shell, "containers": g_containers,
    "crates": g_crates, "shed": g_shed, "garages": g_garages, "dacha": g_dacha,
}


def zone_local(zone, e):
    """Постройки зоны заданы относительно её центра и поворота."""
    zr = zone.get("rot", 0)
    out = dict(e)
    if "pts" in e:
        out["pts"] = []
        for px, pz in e["pts"]:
            ox, oz = rot_xz(px, pz, zr)
            out["pts"].append([zone["x"] + ox, zone["z"] + oz])
    else:
        ox, oz = rot_xz(e["x"], e["z"], zr)
        out["x"], out["z"] = zone["x"] + ox, zone["z"] + oz
        out["rot"] = e.get("rot", 0) + zr
    return out


def layout(map_id, cfg, warn):
    occ = Occupancy()
    result = {"id": map_id, "name": cfg["Name"], "size": cfg["Size"], "roads": [], "hills": [], "bases": [], "forward": [], "zones": [], "items": []}

    roads = []
    for road in cfg.get("Roads", []):
        pts = smooth(road["pts"])
        roads.append({"pts": pts, "w": road["w"], "kind": road.get("kind", "road")})
        for a, b in zip(pts, pts[1:]):
            occ.add_segment(a, b, road["w"] / 2 + 2)
    result["roads"] = [{"pts": [[round(x, 2), round(z, 2)] for x, z in r["pts"]], "w": r["w"], "kind": r["kind"]} for r in roads]

    for team in TEAM_ORDER:
        b = cfg["Bases"].get(team)
        if not b:
            continue
        bx, bz = b["x"], b["z"]
        result["bases"].append({"team": team, "x": bx, "z": bz, "w": BASE_W, "d": BASE_D})
        occ.add_circle(bx, bz, max(BASE_W, BASE_D) / 2 + 20)
        fx, fz = bx * 0.55, bz * 0.55  # lerp к центру на 0.45
        ln = math.hypot(bx, bz)
        ux, uz = -bx / ln, -bz / ln
        sx, sz = -uz, ux
        for shift in (0, 30, -30, 55, -55):
            cx, cz = fx + sx * shift, fz + sz * shift
            if occ.free(cx, cz, 14):
                fx, fz = cx, cz
                break
        result["forward"].append({"team": team, "x": fx, "z": fz})
        occ.add_circle(fx, fz, 26)

    for hill in cfg.get("Hills", []):
        result["hills"].append(hill)
        for road in roads:
            for a, b in zip(road["pts"], road["pts"][1:]):
                if dist_seg((hill["x"], hill["z"]), a, b) < hill["r"] * 0.85 + road["w"] / 2:
                    warn(f"{map_id}: холм ({hill['x']},{hill['z']}) задевает дорогу")
                    break
        occ.add_circle(hill["x"], hill["z"], hill["r"] * 0.85)

    for zone in cfg["Zones"]:
        result["zones"].append({k: zone[k] for k in ("Name", "x", "z", "w", "d")} | {"rot": zone.get("rot", 0)})
        for e in zone.get("Props", []):
            result["items"].append(zone_local(zone, e))
        zr = max(zone["w"], zone["d"]) / 2 + 8
        for b in result["bases"] + result["hills"]:
            br = b.get("r", 60)
            if math.hypot(b["x"] - zone["x"], b["z"] - zone["z"]) < zr + br * 0.85:
                warn(f"{map_id}: зона {zone['Name']} пересекает холм/базу")
        occ.add_circle(zone["x"], zone["z"], zr)

    for e in cfg.get("Extras", []):
        result["items"].append(e)
        occ.add_circle(e["x"], e["z"], 16)

    f = cfg.get("Filler")
    if f:
        rng = Rng(f["Seed"])
        x1, z1, x2, z2 = f["Area"]
        placed = tries = 0
        street_roads = [r for r in roads if len(r["pts"]) >= 2]
        while placed < f["Count"] and tries < f["Count"] * 50:
            tries += 1
            kind = f["Kinds"][rng.int(1, len(f["Kinds"])) - 1]
            gen = FILLERS[kind]
            seed = rng.int(1, 2 ** 30)
            _, radius = gen(Rng(seed), 0, 0, 0)
            if street_roads and rng.float() < f.get("StreetShare", 0):
                road = street_roads[rng.int(1, len(street_roads)) - 1]
                pts = road["pts"]
                i = rng.int(1, len(pts) - 1) - 1
                a, b = pts[i], pts[i + 1]
                t = rng.float()
                px, pz = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                ln = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
                tx, tz = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
                side = -1 if rng.float() < 0.5 else 1
                nx, nz = -tz * side, tx * side
                dist = road["w"] / 2 + 3 + radius * 0.55 + rng.float() * 5
                x, z = px + nx * dist, pz + nz * dist
                rot = math.degrees(math.atan2(-tz, tx)) + (180 if side < 0 else 0)
            else:
                x, z = rng.range(x1, x2), rng.range(z1, z2)
                rot = rng.range(0, 360)
            if x1 <= x <= x2 and z1 <= z <= z2 and occ.free(x, z, radius):
                items, _ = gen(Rng(seed), x, z, rot)
                result["items"].extend(items)
                occ.add_circle(x, z, radius)
                placed += 1
        if placed < f["Count"]:
            warn(f"{map_id}: застройка {placed}/{f['Count']}")
    return result


def main():
    with open(DATA, encoding="utf-8") as fh:
        data = json.load(fh)
    warns = []
    out = {"order": data["Order"], "maps": {}}
    for map_id in data["Order"]:
        out["maps"][map_id] = layout(map_id, data["List"][map_id], warns.append)
    for w in warns:
        print("ВНИМАНИЕ:", w, file=sys.stderr)
    json.dump(out, sys.stdout, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
