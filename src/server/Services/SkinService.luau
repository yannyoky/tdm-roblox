-- Скины фракций и кастомизация персонажа: что открыто у игрока, выбор, покупка за монеты,
-- надевание при появлении.
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
local SkinApply = require(Shared.SkinApply)
local AppearanceApply = require(Shared.AppearanceApply)
local CharacterLook = require(Shared.CharacterLook)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)

local SkinService = {}

-- Описание аватара Roblox каждого игрока (берём один раз за сессию).
local avatarDescs: { [Player]: HumanoidDescription } = {}
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

local function avatarDesc(player: Player): HumanoidDescription?
	if avatarDescs[player] then
		return avatarDescs[player]
	end
	if player.UserId <= 0 then
		return nil -- тестовые игроки Studio без аватара
	end
	local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, player.UserId)
	if ok and desc then
		avatarDescs[player] = desc
		return desc
	end
	return nil
end

-- Описание персонажа игрока: внешность + (в бою) одежда стороны. faction = nil — лобби.
function SkinService.describe(player: Player, faction: string?): HumanoidDescription
	return AppearanceApply.describe(avatarDesc(player), SkinService.look(player), faction, if faction then SkinService.outfit(player, faction) else nil)
end

-- Появление персонажа сразу в нужной внешности (вместо player:LoadCharacter()).
function SkinService.loadCharacter(player: Player, faction: string?)
	local ok, err = pcall(function()
		player:LoadCharacterWithHumanoidDescription(SkinService.describe(player, faction))
	end)
	if not ok then
		warn("[SkinService] Внешность не применилась, обычное появление: ", err)
		player:LoadCharacter()
	elseif player.Character then
		AppearanceApply.tag(player.Character)
	end
end

-- Надеть форму стороны поверх внешности.
function SkinService.applyToPlayer(player: Player, char: Model, faction: string)
	local skinId = SkinService.selected(player, faction)
	local opts = { ownHat = AppearanceApply.hasOwnHat(SkinService.outfit(player, faction)) }
	AppearanceApply.tag(char)
	SkinApply.apply(char, skinId, opts)
end

-- Модель бота: случайная внешность, одежда и скин его стороны.
function SkinService.botModel(faction: string): Model
	local outfit = AppearanceApply.randomOutfit(faction)
	local desc = AppearanceApply.describe(nil, AppearanceApply.randomLook(), faction, outfit)
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
	if not ok then
		warn("[SkinService] Внешность бота не загрузилась: ", model)
		model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		outfit = nil
	end
	AppearanceApply.tag(model)
	local list = Skins.Order[faction]
	if list then
		SkinApply.apply(model, list[math.random(#list)], { ownHat = AppearanceApply.hasOwnHat(outfit) })
	end
	return model
end

-- Случайный скин для готовой модели бота (старый путь, если модель создана не через botModel).
function SkinService.applyToBot(model: Model, faction: string)
	local list = Skins.Order[faction]
	if list then
		SkinApply.apply(model, list[math.random(#list)])
	end
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
	local ok = pcall(hum.ApplyDescription, hum, SkinService.describe(player, nil))
	if ok and player.Character == char then
		AppearanceApply.tag(char)
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
		local desc = AppearanceApply.describe(avatarDesc(player), look, faction, outfit)
		local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if ok and model and gui and player.Parent == Players then
			AppearanceApply.tag(model)
			if faction then
				local skinId = request.skin
				if not (skinId and Skins.List[skinId] and Skins.List[skinId].Faction == faction) then
					skinId = SkinService.selected(player, faction)
				end
				SkinApply.apply(model, skinId, { ownHat = AppearanceApply.hasOwnHat(outfit) })
			end
			for _, inst in model:GetDescendants() do
				if inst:IsA("Script") or inst:IsA("LocalScript") then
					inst:Destroy()
				elseif inst:IsA("BasePart") then
					inst.Anchored = true
				end
			end
			model.Name = "Preview"
			local folder = gui:FindFirstChild("LookPreview")
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = "LookPreview"
				folder.Parent = gui
			end
			folder:ClearAllChildren()
			model.Parent = folder
		elseif not ok then
			warn("[SkinService] Предпросмотр не собрался: ", model)
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
		avatarDescs[player] = nil
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
		task.spawn(avatarDesc, player)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return SkinService
