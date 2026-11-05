-- Точка входа клиента.
local Hud = require(script:WaitForChild("Hud"))
local WeaponController = require(script:WaitForChild("WeaponController"))

task.spawn(WeaponController.init)
task.spawn(Hud.init)
