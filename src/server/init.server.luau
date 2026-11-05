-- Точка входа сервера.
local Services = script:WaitForChild("Services")

local PhysicsSetup = require(Services.PhysicsSetup)
local DataService = require(Services.DataService)
local ShopService = require(Services.ShopService)
local WeaponService = require(Services.WeaponService)
local ProgressionService = require(Services.ProgressionService)
local LeaderboardService = require(Services.LeaderboardService)
local MatchService = require(Services.MatchService)

PhysicsSetup.init()
DataService.init()
ShopService.init()
WeaponService.init()
ProgressionService.init()
LeaderboardService.init()
MatchService.start()
