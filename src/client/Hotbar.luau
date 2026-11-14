-- Своя панель оружия вместо стандартной панели Roblox.
--   1–9 — взять оружие из слота (повторно — убрать), Q — предыдущее оружие,
--   G — граната (повторно — следующий тип гранаты), геймпад: L1/R1 — листать.
--   На телефоне слоты нажимаются пальцем.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Config.Weapons)
local Ui = require(script.Parent.Ui)
local PlayerSettings = require(script.Parent.PlayerSettings)

local player = Players.LocalPlayer
local C = Ui.Colors

local Hotbar = {}

local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

local function slotIndex(def): number
	return table.find(Weapons.Slots, def.Slot) or 99
end

-- Все инструменты-оружие игрока по порядку: основное, пистолеты, ближний бой, гранаты.
local function getTools(): { Tool }
	local list = {}
	local function collect(container: Instance?)
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and Weapons.List[child:GetAttribute("WeaponId")] then
				table.insert(list, child)
			end
		end
	end
	collect(player:FindFirstChildOfClass("Backpack"))
	collect(player.Character)
	table.sort(list, function(a, b)
		local da, db = Weapons.List[a:GetAttribute("WeaponId")], Weapons.List[b:GetAttribute("WeaponId")]
		if slotIndex(da) ~= slotIndex(db) then
			return slotIndex(da) < slotIndex(db)
		end
		if (da.UnlockLevel or 1) ~= (db.UnlockLevel or 1) then
			return (da.UnlockLevel or 1) < (db.UnlockLevel or 1)
		end
		return da.Id < db.Id
	end)
	return list
end

local function equipped(): Tool?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Tool")
end

local function humanoid(): Humanoid?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return if hum and hum.Health > 0 then hum else nil
end

function Hotbar.init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	local gui = Ui.make("ScreenGui", { Name = "Hotbar", ResetOnSpawn = false, DisplayOrder = 2 })
	local row = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0, 0, 0, 62),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})

	local tools: { Tool } = {}
	local cells: { { frame: TextButton, name: TextLabel, info: TextLabel, key: TextLabel } } = {}
	local previous: Tool? = nil
	local lastEquipped: Tool? = nil

	local function equip(tool: Tool?)
		local hum = humanoid()
		if not hum then
			return
		end
		local current = equipped()
		if tool == nil or tool == current then
			hum:UnequipTools()
			return
		end
		hum:EquipTool(tool)
	end

	local function equipIndex(i: number)
		local tool = tools[i]
		if tool then
			equip(tool)
		end
	end

	local function rebuild()
		tools = getTools()
		for _, cell in cells do
			cell.frame:Destroy()
		end
		table.clear(cells)
		local hints = PlayerSettings.get("KeyHints") and not UserInputService.TouchEnabled
		for i, tool in tools do
			local def = Weapons.List[tool:GetAttribute("WeaponId")]
			local frame = Ui.make("TextButton", {
				LayoutOrder = i,
				Size = UDim2.new(0, 96, 1, 0),
				BackgroundColor3 = C.Panel,
				BackgroundTransparency = 0.25,
				Text = "",
				AutoButtonColor = false,
				Parent = row,
			}, { Ui.corner(6), Ui.make("UIStroke", { Color = C.Accent, Thickness = 2, Transparency = 1 }) })
			local key = Ui.label({ Position = UDim2.new(0, 5, 0, 3), Size = UDim2.new(0, 18, 0, 16), Text = tostring(i), TextColor3 = C.Grey, Visible = hints and i <= 9, Parent = frame })
			local name = Ui.label({ Position = UDim2.new(0, 4, 0, 18), Size = UDim2.new(1, -8, 0, 20), Font = Enum.Font.GothamBold, Text = def.DisplayName, Parent = frame })
			local info = Ui.label({ Position = UDim2.new(0, 4, 0, 40), Size = UDim2.new(1, -8, 0, 16), Font = Enum.Font.Gotham, TextColor3 = C.Grey, Parent = frame })
			frame.Activated:Connect(function()
				equip(tool)
			end)
			table.insert(cells, { frame = frame, name = name, info = info, key = key })
		end
	end

	-- Подписи патронов и подсветка выбранного каждый кадр (дёшево: несколько надписей).
	RunService.RenderStepped:Connect(function()
		local current = equipped()
		if current ~= lastEquipped then
			if lastEquipped and lastEquipped.Parent then
				previous = lastEquipped
			end
			lastEquipped = current
		end
		for i, cell in cells do
			local tool = tools[i]
			if tool then
				local def = Weapons.List[tool:GetAttribute("WeaponId")]
				local stroke = cell.frame:FindFirstChildOfClass("UIStroke")
				local isOn = tool == current
				if stroke then
					stroke.Transparency = if isOn then 0 else 1
				end
				cell.frame.BackgroundTransparency = if isOn then 0.05 else 0.35
				if tool:GetAttribute("Count") then
					cell.info.Text = "x" .. tostring(tool:GetAttribute("Count"))
				elseif def.MagSize then
					cell.info.Text = if tool:GetAttribute("Reloading") then "перезарядка" else string.format("%d/%d", tool:GetAttribute("Ammo") or 0, def.MagSize)
				else
					cell.info.Text = ""
				end
			end
		end
		row.Visible = humanoid() ~= nil and #cells > 0 and not (player.Character and player.Character:GetAttribute("InLobby"))
	end)

	-- Пересобрать панель, когда появляются или пропадают инструменты.
	local pending = false
	local function scheduleRebuild()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			rebuild()
		end)
	end
	local function watchContainer(container: Instance)
		container.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				scheduleRebuild()
			end
		end)
		container.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				scheduleRebuild()
			end
		end)
		scheduleRebuild()
	end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watchContainer(child)
		end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		watchContainer(backpack)
	end
	player.CharacterAdded:Connect(function(char)
		previous, lastEquipped = nil, nil
		watchContainer(char)
	end)
	if player.Character then
		watchContainer(player.Character)
	end
	PlayerSettings.onChanged(function(key)
		if key == "KeyHints" then
			scheduleRebuild()
		end
	end)

	local function cycle(step: number)
		if #tools == 0 then
			return
		end
		local current = equipped()
		local index = if current then table.find(tools, current) or 0 else 0
		index = (index + step - 1) % #tools + 1
		equip(tools[index])
	end

	local function nextGrenade()
		local grenades = {}
		for _, tool in tools do
			if Weapons.List[tool:GetAttribute("WeaponId")].Kind == "Grenade" then
				table.insert(grenades, tool)
			end
		end
		if #grenades == 0 then
			return
		end
		local current = equipped()
		local index = if current then table.find(grenades, current) else nil
		local target = grenades[if index then index % #grenades + 1 else 1]
		if target ~= equipped() then
			equip(target)
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local number = NUMBER_KEYS[input.KeyCode]
		if number then
			equipIndex(number)
		elseif input.KeyCode == Enum.KeyCode.Q then
			if previous and previous.Parent and previous ~= equipped() then
				equip(previous)
			end
		elseif input.KeyCode == Enum.KeyCode.G then
			nextGrenade()
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			cycle(1)
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			cycle(-1)
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return Hotbar
