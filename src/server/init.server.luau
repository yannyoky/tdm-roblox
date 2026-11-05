-- Точка входа сервера.
local Services = script:WaitForChild("Services")

local PhysicsSetup = require(Services.PhysicsSetup)
local DataService = require(Services.DataService)
local ShopService = require(Services.ShopService)
local WeaponService = require(Services.WeaponService)
local MatchService = require(Services.MatchService)

PhysicsSetup.init()
DataService.init()
ShopService.init()
WeaponService.init()
MatchService.start()
