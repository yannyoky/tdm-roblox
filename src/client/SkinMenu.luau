-- Меню скинов (клавиша U): предпросмотр на своём персонаже, выбор и покупка за монеты.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Skins = require(Shared.Config.Skins)
local Teams = require(Shared.Config.Teams)
local Meta = require(Shared.Config.Meta)
local Shop = require(Shared.Config.Shop)
local SkinApply = require(Shared.SkinApply)
local Ui = require(script.Parent.Ui)
local Menus = require(script.Parent.Menus)

local player = Players.LocalPlayer
local C = Ui.Colors

local SkinMenu = {}

local function unlockText(def): string
	if def.Unlock.Type == "Rank" then
		local rank = Meta.Ranks[def.Faction][def.Unlock.Rank]
		return "Звание: " .. (if rank then rank.Name else "№" .. def.Unlock.Rank)
	end
	return Skins.unlockText(def)
end

function SkinMenu.init()
	local window = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.8, 0),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
	}, {
		Ui.corner(10),
		Ui.make("UISizeConstraint", { MaxSize = Vector2.new(760, 520) }),
	})
	Ui.label({ Position = UDim2.new(0, 14, 0, 8), Size = UDim2.new(0.5, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Text = "Скины", Parent = window })
	local close = Ui.button("×", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.new(0, 34, 0, 30), BackgroundColor3 = C.Bad, Parent = window })
	close.Activated:Connect(Menus.close)

	-- Вкладки сторон.
	local tabs = {}
	for i, key in Teams.Order do
		local tab = Ui.button(Teams.List[key].Name, {
			Position = UDim2.new(0, 14 + (i - 1) * 140, 0, 46),
			Size = UDim2.new(0, 130, 0, 32),
			Parent = window,
		})
		tabs[key] = tab
	end

	-- Предпросмотр слева.
	local viewport = Ui.make("ViewportFrame", {
		Position = UDim2.new(0, 14, 0, 88),
		Size = UDim2.new(0.42, -14, 1, -102),
		BackgroundColor3 = C.Card,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = window,
	}, { Ui.corner(8) })
	local world = Ui.make("WorldModel", { Parent = viewport })
	local vpCamera = Ui.make("Camera", { FieldOfView = 40, Parent = viewport })
	viewport.CurrentCamera = vpCamera
	local noPreview = Ui.label({ Size = UDim2.fromScale(1, 1), Text = "Предпросмотр появится, когда персонаж в игре", TextWrapped = true, Font = Enum.Font.Gotham, Visible = false, Parent = viewport })
	noPreview.Size = UDim2.new(1, -20, 0, 60)
	noPreview.Position = UDim2.new(0, 10, 0.5, -30)

	-- Список справа.
	local list = Ui.make("ScrollingFrame", {
		Position = UDim2.new(0.42, 12, 0, 88),
		Size = UDim2.new(0.58, -26, 1, -102),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		Parent = window,
	}, { Ui.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local faction = Teams.Order[1]
	local previewId: string? = nil
	local previewModel: Model? = nil
	local angle = 0

	local function buildPreview()
		world:ClearAllChildren()
		previewModel = nil
		local char = player.Character
		if not char or not char:FindFirstChild("HumanoidRootPart") then
			noPreview.Visible = true
			return
		end
		noPreview.Visible = false
		local wasArchivable = char.Archivable
		char.Archivable = true
		local clone = char:Clone()
		char.Archivable = wasArchivable
		if not clone then
			return
		end
		for _, inst in clone:GetDescendants() do
			if inst:IsA("LuaSourceContainer") or inst:IsA("Tool") or inst:IsA("BillboardGui") or inst:IsA("ForceField") then
				inst:Destroy()
			elseif inst:IsA("BasePart") then
				inst.Anchored = true
			end
		end
		clone:PivotTo(CFrame.new())
		SkinApply.apply(clone, previewId)
		clone.Parent = world
		previewModel = clone
	end

	RunService.RenderStepped:Connect(function(dt)
		if not window.Visible or not previewModel then
			return
		end
		angle += dt * 0.6
		local target = Vector3.new(0, 0.5, 0)
		vpCamera.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(angle) * 9, 1.5, math.cos(angle) * 9), target)
	end)

	local function owned(id: string): boolean
		return table.find(string.split(player:GetAttribute("OwnedSkins") or "", ","), id) ~= nil
	end

	local function rebuild()
		for key, tab in tabs do
			tab.BackgroundColor3 = if key == faction then Teams.List[key].Color else C.Button
		end
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local selected = player:GetAttribute("Skin_" .. faction) or Skins.Default[faction]
		local coins = player:GetAttribute("Coins") or 0
		for i, id in Skins.Order[faction] do
			local def = Skins.List[id]
			local row = Ui.make("Frame", {
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 54),
				BackgroundColor3 = if previewId == id then C.Button else C.Card,
				Parent = list,
			}, { Ui.corner(6) })
			local swatch = Ui.make("Frame", { Position = UDim2.new(0, 8, 0, 8), Size = UDim2.new(0, 38, 0, 38), BackgroundColor3 = def.Shirt, Parent = row }, { Ui.corner(6) })
			Ui.make("Frame", { Position = UDim2.new(0, 0, 0.6, 0), Size = UDim2.new(1, 0, 0.4, 0), BackgroundColor3 = def.Pants, BorderSizePixel = 0, Parent = swatch })
			Ui.label({ Position = UDim2.new(0, 54, 0, 6), Size = UDim2.new(1, -190, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Text = def.DisplayName, Parent = row })
			Ui.label({ Position = UDim2.new(0, 54, 0, 30), Size = UDim2.new(1, -190, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham, TextColor3 = C.Grey, Text = unlockText(def), Parent = row })

			local action: TextButton
			if id == selected then
				action = Ui.button("Надет", { BackgroundColor3 = C.Good, AutoButtonColor = false })
			elseif owned(id) then
				action = Ui.button("Надеть")
				action.Activated:Connect(function()
					Net.get("EquipSkin"):FireServer(id)
				end)
			elseif def.Unlock.Type == "Coins" then
				local afford = coins >= def.Unlock.Price
				action = Ui.button(string.format("%d монет", def.Unlock.Price), { BackgroundColor3 = if afford then C.Accent else C.Locked })
				action.Activated:Connect(function()
					if afford then
						Net.get("BuySkin"):FireServer(id)
					end
				end)
			elseif def.Unlock.Type == "Pass" then
				local passId = Shop.GamePasses[def.Unlock.Pass] and Shop.GamePasses[def.Unlock.Pass].Id or 0
				action = Ui.button(if passId ~= 0 then "Купить" else "Скоро", { BackgroundColor3 = Color3.fromRGB(110, 70, 180) })
				action.Activated:Connect(function()
					if passId ~= 0 then
						MarketplaceService:PromptGamePassPurchase(player, passId)
					end
				end)
			else
				action = Ui.button("Закрыт", { BackgroundColor3 = C.Locked, AutoButtonColor = false })
			end
			action.AnchorPoint = Vector2.new(1, 0.5)
			action.Position = UDim2.new(1, -8, 0.5, 0)
			action.Size = UDim2.new(0, 120, 0, 34)
			action.Parent = row

			-- Клик по строке показывает скин на персонаже.
			local hit = Ui.make("TextButton", { Size = UDim2.new(1, -136, 1, 0), BackgroundTransparency = 1, Text = "", Parent = row })
			hit.Activated:Connect(function()
				previewId = id
				buildPreview()
				rebuild()
			end)
		end
	end

	for key, tab in tabs do
		tab.Activated:Connect(function()
			faction = key
			previewId = player:GetAttribute("Skin_" .. key) or Skins.Default[key]
			buildPreview()
			rebuild()
		end)
	end

	Menus.register("Skins", {
		title = "Скины",
		key = Enum.KeyCode.U,
		order = 3,
		panel = window,
		onOpen = function()
			local team = player.Team and not player.Neutral and player.Team:GetAttribute("Key")
			local preferred = player:GetAttribute("PreferredTeam")
			faction = if team and Skins.Order[team] then team elseif preferred and Skins.Order[preferred] then preferred else faction
			previewId = player:GetAttribute("Skin_" .. faction) or Skins.Default[faction]
			buildPreview()
			rebuild()
		end,
	})

	player.AttributeChanged:Connect(function(name)
		if window.Visible and (name == "OwnedSkins" or name == "Coins" or string.sub(name, 1, 5) == "Skin_") then
			rebuild()
		end
	end)
end

return SkinMenu
