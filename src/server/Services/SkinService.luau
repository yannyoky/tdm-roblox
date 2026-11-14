-- Скины фракций: что открыто у игрока, выбор, покупка за монеты, надевание при появлении.
-- Клиент получает атрибуты: OwnedSkins (через запятую), Skin_Bandits, Skin_Gov.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skins = require(Shared.Config.Skins)
local Meta = require(Shared.Config.Meta)
local SkinApply = require(Shared.SkinApply)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local ShopService = require(script.Parent.ShopService)

local SkinService = {}

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

-- Надеть скин на персонажа. Одежда аватара догружается позже, поэтому повторяем после загрузки.
function SkinService.applyToPlayer(player: Player, char: Model, faction: string)
	local skinId = SkinService.selected(player, faction)
	SkinApply.apply(char, skinId)
	if not player:HasAppearanceLoaded() then
		task.spawn(function()
			player.CharacterAppearanceLoaded:Wait()
			if player.Character == char then
				SkinApply.apply(char, skinId)
			end
		end)
	end
end

-- Случайный скин для бота его стороны.
function SkinService.applyToBot(model: Model, faction: string)
	local list = Skins.Order[faction]
	if list then
		SkinApply.apply(model, list[math.random(#list)])
	end
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

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _, purchased)
		if purchased then
			task.delay(1, SkinService.publish, player)
		end
	end)

	local function watch(player: Player)
		player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
			SkinService.publish(player)
		end)
		if player:GetAttribute("DataLoaded") then
			SkinService.publish(player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return SkinService
