-- Скины сторон (комплекты 3D-одежды) и кастомизация персонажа: что открыто у игрока, выбор,
-- покупка за монеты, надевание при появлении.
-- Клиент получает атрибуты: OwnedSkins (через запятую), Skin_Bandits, Skin_Gov,
-- Look (JSON внешности), Outfit_Bandits / Outfit_Gov (JSON одежды стороны).
-- Предпросмотр для меню сервер собирает в PlayerGui.LookPreview: модель видна только этому игроку.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skins = require(Shared.Config.Skins)
local Meta = require(Shared.Config.Meta)
local AppearanceApply = require(Shared.AppearanceApply)
local CharacterLook = require(Shared.CharacterLook)
local GeneratedBody = require(Shared.GeneratedBody)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)
local PhysicsSetup = require(script.Parent.PhysicsSetup)

local StarterPlayer = game:GetService("StarterPlayer")

local SkinService = {}

local previewBusy: { [Player]: boolean } = {}
local previewQueued: { [Player]: any } = {}

local function seasonTier(data): number
	if data.Season.Id ~= Meta.Season.Id then
		return 0
	end
	return math.min(Meta.Season.Tiers, math.floor(data.Season.XP / Meta.Season.TierXP))
end

-- Открыт ли скин. Сезонные скины, однажды полученные, остаются навсегда.
function SkinService.owns(player: Player, skinId: string): boolean
	local def = Skins.List[skinId]
	local data = DataService.get(player)
	if not def or not data then
		return false
	end
	local u = def.Unlock
	if u.Type == "Default" or table.find(data.OwnedSkins, skinId) then
		return true
	elseif u.Type == "Rank" then
		local index = Meta.rankFor(def.Faction, data.FactionXP[def.Faction] or 0)
		return index >= u.Rank
	elseif u.Type == "Season" then
		if seasonTier(data) >= u.Tier then
			table.insert(data.OwnedSkins, skinId)
			return true
		end
	elseif u.Type == "Pass" then
		return ShopService.ownsPass(player, u.Pass)
	end
	return false
end

function SkinService.selected(player: Player, faction: string): string
	local data = DataService.get(player)
	local id = data and data.Skin[faction]
	if id and Skins.List[id] and Skins.List[id].Faction == faction and SkinService.owns(player, id) then
		return id
	end
	return Skins.Default[faction]
end

function SkinService.publish(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local owned = {}
	for id in Skins.List do
		if SkinService.owns(player, id) then
			table.insert(owned, id)
		end
	end
	player:SetAttribute("OwnedSkins", table.concat(owned, ","))
	for faction in Skins.Default do
		player:SetAttribute("Skin_" .. faction, SkinService.selected(player, faction))
	end
end

function SkinService.look(player: Player): { [string]: any }
	local data = DataService.get(player)
	return AppearanceApply.sanitizeLook(data and data.Look)
end

function SkinService.outfit(player: Player, faction: string): { [string]: string }
	local data = DataService.get(player)
	return AppearanceApply.sanitizeOutfit(faction, data and data.Outfit and data.Outfit[faction])
end

-- Описание персонажа игрока: внешность + (в бою) скин и одежда стороны. faction = nil — лобби.
-- Аватар Roblox не используется: тело всегда одно из двух реалистичных (Config/Appearance).
function SkinService.describe(player: Player, faction: string?): HumanoidDescription
	if not faction then
		return AppearanceApply.describe(SkinService.look(player), nil)
	end
	return AppearanceApply.describe(
		SkinService.look(player),
		faction,
		SkinService.outfit(player, faction),
		SkinService.selected(player, faction)
	)
end

-- Персонаж из сгенерированной модели тела (GeneratedBody). Как LoadCharacter: старый
-- персонаж удаляется, скрипты StarterCharacterScripts кладутся в новый.
local function loadGenerated(player: Player, faction: string?): boolean
	local look = SkinService.look(player)
	if not GeneratedBody.has(look.Body) then
		return false
	end
	local model = AppearanceApply.buildModel(look, SkinService.describe(player, faction))
	if not model or model:GetAttribute(GeneratedBody.ATTR) == nil then
		if model then
			model:Destroy()
		end
		return false
	end
	model.Name = player.Name
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayName = player.DisplayName
	-- У шаблона модели нет Animator (его движок добавляет только при LoadCharacter):
	-- без него не играет ни одна анимация и тело висит в исходной позе, «кружась» на полу.
	if not hum:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = hum
	end
	local scripts = StarterPlayer:FindFirstChild("StarterCharacterScripts")
	for _, child in (scripts and scripts:GetChildren()) or {} do
		local existing = model:FindFirstChild(child.Name)
		if existing then
			existing:Destroy()
		end
		child:Clone().Parent = model
	end
	local old = player.Character
	model.Parent = workspace
	player.Character = model
	if old and old ~= model then
		old:Destroy()
	end
	return true
end

-- Появление персонажа сразу в нужной внешности (вместо player:LoadCharacter()).
function SkinService.loadCharacter(player: Player, faction: string?)
	local okGenerated, generated = pcall(loadGenerated, player, faction)
	if okGenerated and generated then
		return
	elseif not okGenerated then
		warn("[SkinService] Сгенерированное тело не загрузилось, каталожное: ", generated)
	end
	local ok, err = pcall(function()
		player:LoadCharacterWithHumanoidDescription(SkinService.describe(player, faction))
	end)
	if not ok then
		-- Не загрузилась одежда — появляемся хотя бы в теле по умолчанию, без аватара.
		warn("[SkinService] Внешность не применилась, тело по умолчанию: ", err)
		local okDefault = pcall(function()
			player:LoadCharacterWithHumanoidDescription(AppearanceApply.describe({}, faction, nil, nil))
		end)
		if not okDefault then
			player:LoadCharacter()
		end
	end
end

-- Скин уже надет при появлении (loadCharacter). Оставлено для совместимости вызовов.
function SkinService.applyToPlayer(player: Player, char: Model, faction: string)
	char:SetAttribute("Skin", SkinService.selected(player, faction))
end

-- Модель бота: случайная внешность, скин его стороны и иногда пара своих вещей.
function SkinService.botModel(faction: string): Model
	local list = Skins.Order[faction]
	local skinId = if list then list[math.random(#list)] else nil
	local look = AppearanceApply.randomLook()
	local desc = AppearanceApply.describe(look, faction, AppearanceApply.randomOutfit(faction), skinId)
	local model = AppearanceApply.buildModel(look, desc, true)
	if not model then
		model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end
	model:SetAttribute("Skin", skinId)
	return model
end

function SkinService.publishLook(player: Player)
	player:SetAttribute("Look", HttpService:JSONEncode(SkinService.look(player)))
	for faction in Skins.Default do
		player:SetAttribute("Outfit_" .. faction, HttpService:JSONEncode(SkinService.outfit(player, faction)))
	end
end

-- В лобби меняем внешность сразу на живом персонаже.
local function refreshLobbyCharacter(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.Health <= 0 or not char:GetAttribute("InLobby") then
		return
	end
	local look = SkinService.look(player)
	local current = char:GetAttribute(GeneratedBody.ATTR)
	if current ~= nil and current == look.Body and GeneratedBody.has(look.Body) then
		-- То же сгенерированное тело: только переодеть.
		GeneratedBody.dress(char, AppearanceApply.clothesOnly(SkinService.describe(player, nil), look))
		return
	elseif current ~= nil or GeneratedBody.has(look.Body) then
		-- Сменилось тело: персонаж появляется заново на том же месте.
		local pivot = char:GetPivot()
		SkinService.loadCharacter(player, nil)
		local fresh = player.Character
		if fresh and fresh ~= char then
			PhysicsSetup.prepareCharacter(fresh)
			fresh:SetAttribute("InLobby", true)
			fresh:PivotTo(pivot)
		end
		return
	end
	local ok = pcall(hum.ApplyDescription, hum, SkinService.describe(player, nil))
	if ok and player.Character == char then
		CharacterLook.applyAnimations(char)
	end
end

-- Собрать модель предпросмотра и положить в PlayerGui игрока. Запросы сливаются:
-- пока строится одна модель, хранится только последний запрос.
local function buildPreview(player: Player, request)
	if previewBusy[player] then
		previewQueued[player] = request
		return
	end
	previewBusy[player] = true
	while request do
		previewQueued[player] = nil
		local faction = request.faction
		local look = AppearanceApply.sanitizeLook(request.look)
		local outfit = if faction then AppearanceApply.sanitizeOutfit(faction, request.outfit) else nil
		local skinId = request.skin
		if faction and not (skinId and Skins.List[skinId] and Skins.List[skinId].Faction == faction) then
			skinId = SkinService.selected(player, faction)
		end
		local desc = AppearanceApply.describe(look, faction, outfit, if faction then skinId else nil)
		local model = AppearanceApply.buildModel(look, desc)
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if model and gui and player.Parent == Players then
			local parts = 0
			for _, inst in model:GetDescendants() do
				if inst:IsA("Script") or inst:IsA("LocalScript") then
					inst:Destroy()
				elseif inst:IsA("BasePart") then
					inst.Anchored = true
					parts += 1
				end
			end
			-- Клиент ждёт, пока доедут все детали, и только потом копирует модель в окно.
			model:SetAttribute("Parts", parts)
			model.Archivable = true
			model.Name = "Preview"
			local folder = gui:FindFirstChild("LookPreview")
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = "LookPreview"
				folder.Parent = gui
			end
			folder:ClearAllChildren()
			model.Parent = folder
		elseif model then
			model:Destroy()
		end
		request = previewQueued[player]
	end
	previewBusy[player] = nil
end

function SkinService.init()
	Net.get("EquipSkin").OnServerEvent:Connect(function(player, skinId)
		if typeof(skinId) ~= "string" or not Skins.List[skinId] or not SkinService.owns(player, skinId) then
			return
		end
		local data = DataService.get(player)
		if data then
			data.Skin[Skins.List[skinId].Faction] = skinId
			SkinService.publish(player)
		end
	end)

	Net.get("BuySkin").OnServerEvent:Connect(function(player, skinId)
		local def = typeof(skinId) == "string" and Skins.List[skinId]
		local data = DataService.get(player)
		if not def or not data or def.Unlock.Type ~= "Coins" or SkinService.owns(player, skinId) then
			return
		end
		if data.Coins < def.Unlock.Price then
			return
		end
		data.Coins -= def.Unlock.Price
		table.insert(data.OwnedSkins, skinId)
		data.Skin[def.Faction] = skinId
		DataService.refresh(player)
		SkinService.publish(player)
	end)

	Net.get("SetLook").OnServerEvent:Connect(function(player, look)
		local data = DataService.get(player)
		if not data or type(look) ~= "table" then
			return
		end
		data.Look = AppearanceApply.sanitizeLook(look)
		SkinService.publishLook(player)
		refreshLobbyCharacter(player)
	end)

	Net.get("SetOutfit").OnServerEvent:Connect(function(player, faction, outfit)
		local data = DataService.get(player)
		if not data or typeof(faction) ~= "string" or not Skins.Default[faction] or type(outfit) ~= "table" then
			return
		end
		data.Outfit = data.Outfit or {}
		data.Outfit[faction] = AppearanceApply.sanitizeOutfit(faction, outfit)
		SkinService.publishLook(player)
	end)

	Net.get("PreviewLook").OnServerEvent:Connect(function(player, look, faction, outfit, skinId)
		if type(look) ~= "table" then
			return
		end
		if typeof(faction) ~= "string" or not Skins.Default[faction] then
			faction = nil
		end
		task.spawn(buildPreview, player, {
			look = look,
			faction = faction,
			outfit = if type(outfit) == "table" then outfit else nil,
			skin = if typeof(skinId) == "string" then skinId else nil,
		})
	end)

	Players.PlayerRemoving:Connect(function(player)
		previewBusy[player] = nil
		previewQueued[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _, purchased)
		if purchased then
			task.delay(1, SkinService.publish, player)
		end
	end)

	local function watch(player: Player)
		player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
			SkinService.publish(player)
			SkinService.publishLook(player)
		end)
		if player:GetAttribute("DataLoaded") then
			SkinService.publish(player)
			SkinService.publishLook(player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return SkinService
