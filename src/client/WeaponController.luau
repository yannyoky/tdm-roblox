-- Стрельба на стороне игрока: прицеливание, автоогонь, перезарядка, трассеры.
-- Работает на ПК (мышь, R), телефоне (тап, кнопка перезарядки) и геймпаде.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Config.Weapons)
local Net = require(Shared.Net)

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local WeaponController = {}

local AIM_DISTANCE = 1000

function WeaponController.init()
	local FireWeapon = Net.get("FireWeapon")
	local Reload = Net.get("Reload")

	local current: Tool? = nil
	local firing = false
	local lastShot = 0
	local hooked = setmetatable({}, { __mode = "k" })

	local function currentDef()
		if not current then
			return nil, nil
		end
		local id = current:GetAttribute("WeaponId")
		return id, Weapons.List[id]
	end

	local function fireOnce()
		local tool = current
		local id, def = currentDef()
		if not tool or not def then
			return
		end
		local now = os.clock()
		if now - lastShot < 1 / def.FireRate then
			return
		end
		if def.MagSize then
			if tool:GetAttribute("Reloading") then
				return
			end
			if (tool:GetAttribute("Ammo") or 0) <= 0 then
				Reload:FireServer(id)
				return
			end
		end
		local char = player.Character
		local head = char and char:FindFirstChild("Head") :: BasePart?
		if not head then
			return
		end
		lastShot = now

		-- Луч из камеры через курсор (или точку касания) находит, куда целится игрок.
		local camera = workspace.CurrentCamera
		local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, params)
		local target = if hit then hit.Position else ray.Origin + ray.Direction * AIM_DISTANCE
		local dir = target - head.Position
		if dir.Magnitude < 0.1 then
			return
		end
		FireWeapon:FireServer(id, head.Position, dir.Unit)
	end

	local function hookTool(tool: Instance)
		if not tool:IsA("Tool") or hooked[tool] or tool:GetAttribute("WeaponId") == nil then
			return
		end
		hooked[tool] = true
		tool.Equipped:Connect(function()
			current = tool
		end)
		tool.Unequipped:Connect(function()
			if current == tool then
				current = nil
				firing = false
			end
		end)
		tool.Activated:Connect(function()
			firing = true
			fireOnce()
		end)
		tool.Deactivated:Connect(function()
			firing = false
		end)
	end

	local function watch(container: Instance)
		for _, child in container:GetChildren() do
			hookTool(child)
		end
		container.ChildAdded:Connect(hookTool)
	end

	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watch(child)
		end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		watch(backpack)
	end
	player.CharacterAdded:Connect(function(char)
		current = nil
		firing = false
		watch(char)
	end)
	if player.Character then
		watch(player.Character)
	end

	-- Автоматический огонь, пока зажата кнопка.
	RunService.Heartbeat:Connect(function()
		if not firing then
			return
		end
		local _, def = currentDef()
		if def and def.Automatic then
			fireOnce()
		end
	end)

	-- Перезарядка: R на клавиатуре, X на геймпаде, кнопка на экране телефона.
	ContextActionService:BindAction("Reload", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local id, def = currentDef()
		if def and def.MagSize then
			Reload:FireServer(id)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("Reload", "R")

	-- Трассеры от выстрелов всех игроков.
	Net.get("ShotFx").OnClientEvent:Connect(function(_shooter, origin: Vector3, endPos: Vector3, isMelee: boolean)
		if isMelee then
			return
		end
		local distance = (endPos - origin).Magnitude
		if distance < 0.5 then
			return
		end
		local tracer = Instance.new("Part")
		tracer.Anchored = true
		tracer.CanCollide = false
		tracer.CanQuery = false
		tracer.CanTouch = false
		tracer.CastShadow = false
		tracer.Material = Enum.Material.Neon
		tracer.Color = Color3.fromRGB(255, 220, 120)
		tracer.Size = Vector3.new(0.08, 0.08, distance)
		tracer.CFrame = CFrame.lookAt(origin, endPos) * CFrame.new(0, 0, -distance / 2)
		tracer.Parent = workspace
		Debris:AddItem(tracer, 0.06)
	end)
end

return WeaponController
