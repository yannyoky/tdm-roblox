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
local PlayerSettings = require(script.Parent.PlayerSettings)

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

	-- Прицел снайперской винтовки: правая кнопка мыши (или кнопка на экране) приближает.
	local camera = workspace.CurrentCamera
	local normalFov = PlayerSettings.get("FieldOfView")
	local zoomed = false
	camera.FieldOfView = normalFov
	PlayerSettings.onChanged(function(key, value)
		if key == "FieldOfView" then
			normalFov = value
			if not zoomed then
				camera.FieldOfView = value
			end
		end
	end)
	local function setZoom(on: boolean)
		local _, def = currentDef()
		on = on and def ~= nil and def.Zoom ~= nil
		if on == zoomed then
			return
		end
		zoomed = on
		camera.FieldOfView = if on then def.Zoom else normalFov
		PlayerSettings.setAiming(on)
	end
	ContextActionService:BindAction("Aim", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			local _, def = currentDef()
			if not (def and def.Zoom) then
				return Enum.ContextActionResult.Pass
			end
			setZoom(not zoomed)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	ContextActionService:SetTitle("Aim", "Прицел")
	RunService.RenderStepped:Connect(function()
		if zoomed and not current then
			setZoom(false)
		end
	end)

	-- Трассеры и следы попаданий от выстрелов всех бойцов.
	local function effectPart(size: Vector3, cframe: CFrame, color: Color3, lifetime: number)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = size
		p.CFrame = cframe
		p.Parent = workspace
		Debris:AddItem(p, lifetime)
	end

	Net.get("ShotFx").OnClientEvent:Connect(function(origin: Vector3, endPos: Vector3, isMelee: boolean, hitSomething: boolean)
		if isMelee then
			return
		end
		local distance = (endPos - origin).Magnitude
		if distance >= 0.5 then
			effectPart(
				Vector3.new(0.08, 0.08, distance),
				CFrame.lookAt(origin, endPos) * CFrame.new(0, 0, -distance / 2),
				Color3.fromRGB(255, 220, 120),
				0.06
			)
		end
		if hitSomething then
			effectPart(Vector3.new(0.35, 0.35, 0.35), CFrame.new(endPos), Color3.fromRGB(255, 170, 60), 0.12)
		end
	end)
end

return WeaponController
