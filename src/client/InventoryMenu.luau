-- Меню инвентаря: игрок отмечает, что брать в бой. Ограничений нет, можно взять всё открытое.
-- Изменения применяются при следующем появлении.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Weapons = require(Shared.Config.Weapons)

local player = Players.LocalPlayer

local InventoryMenu = {}

local PANEL = Color3.fromRGB(20, 20, 26)
local ON = Color3.fromRGB(60, 140, 80)
local OFF = Color3.fromRGB(45, 45, 55)
local LOCKED = Color3.fromRGB(30, 30, 34)

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	return inst
end

function InventoryMenu.init()
	local gui = make("ScreenGui", { Name = "InventoryMenu", ResetOnSpawn = false })

	local openButton = make("TextButton", {
		Position = UDim2.new(0, 12, 0, 102),
		Size = UDim2.new(0, 120, 0, 36),
		BackgroundColor3 = OFF,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = "Инвентарь",
	}, { make("UICorner", { CornerRadius = UDim.new(0, 6) }) })
	openButton.Parent = gui

	local panel = make("ScrollingFrame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 360, 0, 420),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.1,
		Visible = false,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
	}, {
		make("UICorner", { CornerRadius = UDim.new(0, 8) }),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 14),
		}),
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	panel.Parent = gui
	openButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local buttons: { [string]: TextButton } = {}

	make("TextLabel", {
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextWrapped = true,
		Text = "Отметьте, что брать в бой. Можно взять всё. Действует со следующего появления.",
	}).Parent = panel

	for _, slot in Weapons.Slots do
		make("TextLabel", {
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			TextColor3 = Color3.new(1, 1, 1),
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = Weapons.SlotNames[slot] or slot,
		}).Parent = panel

		local ids = {}
		for id, def in Weapons.List do
			if def.Slot == slot then
				table.insert(ids, id)
			end
		end
		table.sort(ids, function(a, b)
			return (Weapons.List[a].UnlockLevel or 1) < (Weapons.List[b].UnlockLevel or 1)
		end)

		for _, id in ids do
			local b = make("TextButton", {
				LayoutOrder = nextOrder(),
				Size = UDim2.new(1, 0, 0, 38),
				BackgroundColor3 = OFF,
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				Text = Weapons.List[id].DisplayName,
			}, {
				make("UICorner", { CornerRadius = UDim.new(0, 6) }),
				make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
			})
			b.Parent = panel
			buttons[id] = b
			b.Activated:Connect(function()
				local level = player:GetAttribute("Level") or 1
				if not Weapons.isUnlocked(id, level) then
					return
				end
				local selected = string.split(player:GetAttribute("Inventory") or "", ",")
				Net.get("SetInventoryItem"):FireServer(id, table.find(selected, id) == nil)
			end)
		end
	end

	local function refresh()
		local level = player:GetAttribute("Level") or 1
		local selected = string.split(player:GetAttribute("Inventory") or "", ",")
		for id, b in buttons do
			local def = Weapons.List[id]
			if not Weapons.isUnlocked(id, level) then
				b.BackgroundColor3 = LOCKED
				b.Text = string.format("%s  (ур. %d)", def.DisplayName, def.UnlockLevel)
			elseif table.find(selected, id) then
				b.BackgroundColor3 = ON
				b.Text = "✓ " .. def.DisplayName
			else
				b.BackgroundColor3 = OFF
				b.Text = def.DisplayName
			end
		end
	end
	player.AttributeChanged:Connect(function(name)
		if name == "Inventory" or name == "Level" then
			refresh()
		end
	end)
	refresh()

	gui.Parent = player:WaitForChild("PlayerGui")
end

return InventoryMenu
