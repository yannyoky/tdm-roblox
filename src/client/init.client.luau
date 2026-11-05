-- Точка входа клиента.
local Hud = require(script:WaitForChild("Hud"))
local WeaponController = require(script:WaitForChild("WeaponController"))
local InventoryMenu = require(script:WaitForChild("InventoryMenu"))
local CombatFx = require(script:WaitForChild("CombatFx"))
local ProgressMenu = require(script:WaitForChild("ProgressMenu"))

task.spawn(WeaponController.init)
task.spawn(Hud.init)
task.spawn(InventoryMenu.init)
task.spawn(CombatFx.init)
task.spawn(ProgressMenu.init)
