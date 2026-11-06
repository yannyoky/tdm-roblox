-- Покупки: Game Passes (разовые) и Developer Products (повторяемые).
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(ReplicatedStorage:WaitForChild("Shared").Config.Shop)
local DataService = require(script.Parent.DataService)

local ShopService = {}

local passCache: { [Player]: { [string]: boolean } } = {}
local productsById: { [number]: any } = {}

function ShopService.ownsPass(player: Player, key: string): boolean
	local def = Shop.GamePasses[key]
	if not def or def.Id == 0 then
		return false
	end
	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end
	if cache[key] ~= nil then
		return cache[key]
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, def.Id)
	if not ok then
		warn("[ShopService] Не удалось проверить Game Pass: ", owns)
		return false -- не кэшируем, проверим ещё раз позже
	end
	cache[key] = owns
	return owns
end

-- Множители наград: VIP и буст опыта.
function ShopService.getMultipliers(player: Player): (number, number)
	local xp, coins = 1, 1
	if ShopService.ownsPass(player, "VIP") then
		xp *= Shop.GamePasses.VIP.XpMultiplier
		coins *= Shop.GamePasses.VIP.CoinMultiplier
	end
	local data = DataService.get(player)
	if data and data.XPBoostUntil > os.time() then
		xp *= 2
	end
	return xp, coins
end

local function grantProduct(player: Player, product): boolean
	if product.Coins then
		DataService.addCoins(player, product.Coins)
	end
	if product.XPBoostSeconds then
		DataService.addXPBoost(player, product.XPBoostSeconds)
	end
	return true
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or not DataService.get(player) then
		-- Игрок вышел или данные не загрузились: Roblox повторит позже.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if DataService.hasPurchase(player, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = productsById[receipt.ProductId]
	if not product then
		warn("[ShopService] Неизвестный товар: ", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not grantProduct(player, product) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService.recordPurchase(player, receipt.PurchaseId)
	-- Сохраняем сразу. Если не вышло, Roblox повторит, а повтор не выдаст товар дважды.
	if not DataService.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function refreshVip(player: Player)
	player:SetAttribute("VIP", ShopService.ownsPass(player, "VIP"))
end

function ShopService.init()
	for _, product in Shop.Products do
		if product.Id ~= 0 then
			productsById[product.Id] = product
		end
	end
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, def in Shop.GamePasses do
			if def.Id == passId then
				passCache[player] = passCache[player] or {}
				passCache[player][key] = true
			end
		end
		refreshVip(player)
	end)

	Players.PlayerAdded:Connect(refreshVip)
	for _, player in Players:GetPlayers() do
		task.spawn(refreshVip, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
	end)
end

return ShopService
