-- Миникарта (справа сверху): вокруг игрока ~140 студов, север вверху.
-- Показывает здания, базы, зоны капта (текущая подсвечена), союзников и врагов, которые только что стреляли.
-- Стрелка в центре — вы и направление взгляда.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Teams = require(Shared.Config.Teams)
local Ui = require(script.Parent.Ui)
local Menus = require(script.Parent.Menus)

local player = Players.LocalPlayer

local Minimap = {}

local SIZE = 190 -- px
local RADIUS = 140 -- студов от центра до края
local SCALE = SIZE / (RADIUS * 2) -- px на студ
local MAX_PARTS = 1500
local PING_TIME = 2 -- сколько секунд виден стрелявший враг

local BUILDING = Color3.fromRGB(95, 98, 110)
local GROUND = Color3.fromRGB(32, 36, 40)

local function myTeam(): string?
	if player.Team and not player.Neutral then
		return player.Team:GetAttribute("Key")
	end
	return nil
end

local function teamOfCharacter(char: Model): string?
	local p = Players:GetPlayerFromCharacter(char)
	if p then
		return if p.Team and not p.Neutral then p.Team:GetAttribute("Key") else nil
	end
	return char:GetAttribute("TeamKey")
end

function Minimap.init()
	local state = ReplicatedStorage:WaitForChild("MatchState") :: Folder
	local gui = Ui.make("ScreenGui", { Name = "Minimap", ResetOnSpawn = false, DisplayOrder = 1 })
	local holder = Ui.make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	-- CanvasGroup обрезает всё, что выходит за круг, в том числе повёрнутые здания.
	local canvas = Ui.make("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = GROUND,
		BackgroundTransparency = 0.15,
		GroupTransparency = 0.05,
		Parent = holder,
	}, { Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	Ui.make("UIStroke", { Color = Color3.fromRGB(200, 200, 210), Thickness = 2, Transparency = 0.4, Parent = holder })
	Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = holder })
	Ui.label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(16, 14), Text = "С", TextSize = 12, Parent = holder })

	-- Слой мира: здания, базы и зоны в координатах карты. Двигается так, чтобы игрок был в центре.
	local world = Ui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Parent = canvas })
	local dots = Ui.make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = canvas })

	local arrow = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		Text = "▲",
		TextSize = 16,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		TextStrokeTransparency = 0.2,
		ZIndex = 5,
		Parent = canvas,
	})

	local origin = Vector2.zero -- мировые X, Z левого верхнего угла слоя мира
	local builtFor: Instance? = nil
	local zoneFrames: { [string]: Frame } = {}

	local function worldToLayer(x: number, z: number): UDim2
		return UDim2.fromOffset((x - origin.X) * SCALE, (z - origin.Y) * SCALE)
	end

	local function rect(part: BasePart, color: Color3, transparency: number, z: number): Frame
		local yaw = select(2, part.CFrame:ToEulerAnglesYXZ())
		return Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = worldToLayer(part.Position.X, part.Position.Z),
			Size = UDim2.fromOffset(math.max(2, part.Size.X * SCALE), math.max(2, part.Size.Z * SCALE)),
			Rotation = -math.deg(yaw),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = world,
		})
	end

	local function rebuild(map: Instance?)
		world:ClearAllChildren()
		table.clear(zoneFrames)
		builtFor = map
		if not map then
			return
		end
		-- Границы карты.
		local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
		local parts = {}
		for _, inst in map:GetDescendants() do
			if inst:IsA("BasePart") then
				local p = inst.Position
				minX, minZ = math.min(minX, p.X - inst.Size.X / 2), math.min(minZ, p.Z - inst.Size.Z / 2)
				maxX, maxZ = math.max(maxX, p.X + inst.Size.X / 2), math.max(maxZ, p.Z + inst.Size.Z / 2)
				table.insert(parts, inst)
			end
		end
		if minX == math.huge then
			return
		end
		origin = Vector2.new(minX, minZ)
		world.Size = UDim2.fromOffset((maxX - minX) * SCALE, (maxZ - minZ) * SCALE)
		local mapArea = (maxX - minX) * (maxZ - minZ)

		-- Здания и стены: высокие непрозрачные детали, крупные первыми.
		local candidates = {}
		for _, part in parts do
			local area = part.Size.X * part.Size.Z
			if part.Anchored and part.Transparency < 0.5 and part.Size.Y >= 3 and area >= 12 and area < mapArea * 0.3
				and not part:IsDescendantOf(map:FindFirstChild("CapturePoints") or part)
				and not part:IsDescendantOf(map:FindFirstChild("Bases") or part) then
				table.insert(candidates, part)
			end
		end
		table.sort(candidates, function(a, b)
			return a.Size.X * a.Size.Z > b.Size.X * b.Size.Z
		end)
		for i = 1, math.min(#candidates, MAX_PARTS) do
			rect(candidates[i], BUILDING, 0.1, 1)
		end

		-- Базы команд.
		local bases = map:FindFirstChild("Bases")
		if bases then
			for _, key in Teams.Order do
				local folder = bases:FindFirstChild(key)
				for _, part in if folder then folder:GetDescendants() else {} do
					if part:IsA("BasePart") then
						rect(part, Teams.List[key].Color, 0.65, 2)
					end
				end
			end
		end

		-- Зоны капта.
		local points = map:FindFirstChild("CapturePoints")
		if points then
			for _, part in points:GetChildren() do
				if part:IsA("BasePart") then
					local f = rect(part, Color3.fromRGB(230, 230, 230), 0.75, 3)
					Ui.make("UIStroke", { Color = Color3.fromRGB(230, 230, 230), Thickness = 1, Parent = f })
					zoneFrames[part.Name] = f
				end
			end
		end
	end

	-- Перестраиваем при смене карты.
	local function checkMap()
		local map = workspace:FindFirstChild("Map")
		if map ~= builtFor then
			task.wait(0.5) -- дать карте догрузиться
			rebuild(workspace:FindFirstChild("Map"))
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("MapName"):Connect(function()
		builtFor = nil
		task.spawn(checkMap)
	end)
	task.spawn(function()
		while true do
			checkMap()
			task.wait(3)
		end
	end)

	-- Враги, которые стреляли: короткая метка на месте выстрела.
	local pings: { { pos: Vector3, t: number } } = {}
	Net.get("ShotFx").OnClientEvent:Connect(function(origin3: Vector3, _endPos, _isMelee, _hit, first: boolean?)
		if not first then
			return
		end
		local mine = myTeam()
		local best, bestDist = nil, 8
		for _, model in workspace:GetChildren() do
			local head = model:IsA("Model") and model:FindFirstChild("Head")
			if head and head:IsA("BasePart") then
				local d = (head.Position - origin3).Magnitude
				if d < bestDist then
					best, bestDist = model, d
				end
			end
		end
		if best and best ~= player.Character and teamOfCharacter(best) ~= mine then
			table.insert(pings, { pos = origin3, t = os.clock() })
		end
	end)

	local dotPool: { Frame } = {}
	local function dot(i: number, color: Color3, size: number): Frame
		local f = dotPool[i]
		if not f then
			f = Ui.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 4, Parent = dots }, { Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
			dotPool[i] = f
		end
		f.BackgroundColor3 = color
		f.Size = UDim2.fromOffset(size, size)
		f.Visible = true
		return f
	end

	RunService.RenderStepped:Connect(function()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local show = root ~= nil and not char:GetAttribute("InLobby") and not Menus.isOpen("Main")
		holder.Visible = show
		if not show or not root then
			return
		end
		local me = root.Position
		local center = Vector2.new(SIZE / 2, SIZE / 2)
		world.Position = UDim2.fromOffset(center.X - (me.X - origin.X) * SCALE, center.Y - (me.Z - origin.Y) * SCALE)

		local look = workspace.CurrentCamera.CFrame.LookVector
		arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))

		-- Текущая зона капта мигает.
		local active = state:GetAttribute("ModeId") == "Capture" and state:GetAttribute("ZoneName") or nil
		for name, f in zoneFrames do
			local on = name == active
			f.BackgroundTransparency = if on then 0.45 + 0.2 * math.sin(os.clock() * 5) else 0.8
			local attackers = state:GetAttribute("Attackers")
			f.BackgroundColor3 = if on and attackers and Teams.List[attackers] then Teams.List[attackers].Color else Color3.fromRGB(230, 230, 230)
		end

		local n = 0
		local function place(pos: Vector3, color: Color3, size: number)
			local dx, dz = (pos.X - me.X) * SCALE, (pos.Z - me.Z) * SCALE
			if dx * dx + dz * dz > (SIZE / 2 - 4) ^ 2 then
				return
			end
			n += 1
			dot(n, color, size).Position = UDim2.fromOffset(center.X + dx, center.Y + dz)
		end

		-- Союзники: игроки и боты своей команды.
		local mine = myTeam()
		if mine then
			local color = Teams.List[mine].Color
			for _, other in Players:GetPlayers() do
				local c = other.Character
				local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
				if other ~= player and r and teamOfCharacter(c :: Model) == mine then
					place(r.Position, color, 7)
				end
			end
			for _, model in workspace:GetChildren() do
				if model:IsA("Model") and model:GetAttribute("BotId") ~= nil and model:GetAttribute("TeamKey") == mine then
					local r = model:FindFirstChild("HumanoidRootPart") :: BasePart?
					local hum = model:FindFirstChildOfClass("Humanoid")
					if r and hum and hum.Health > 0 then
						place(r.Position, color, 6)
					end
				end
			end
		end

		-- Стрелявшие враги.
		local now = os.clock()
		for i = #pings, 1, -1 do
			if now - pings[i].t > PING_TIME then
				table.remove(pings, i)
			else
				place(pings[i].pos, Color3.fromRGB(255, 70, 60), 7)
			end
		end

		for i = n + 1, #dotPool do
			dotPool[i].Visible = false
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return Minimap
