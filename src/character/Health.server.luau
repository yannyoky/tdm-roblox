-- Заменяет стандартную регенерацию Roblox: здоровье восстанавливается,
-- только если 6 секунд не было урона и персонаж не ранен.
local char = script.Parent
local hum = char:WaitForChild("Humanoid") :: Humanoid

local REGEN_DELAY = 6
local REGEN_PER_SECOND = 0.08 -- доля максимального здоровья в секунду

local lastHealth = hum.Health
local lastDamage = 0
hum.HealthChanged:Connect(function(health)
	if health < lastHealth then
		lastDamage = os.clock()
	end
	lastHealth = health
end)

while hum.Health > 0 and char.Parent do
	task.wait(0.5)
	if not char:GetAttribute("Downed") and os.clock() - lastDamage > REGEN_DELAY and hum.Health < hum.MaxHealth then
		hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * REGEN_PER_SECOND * 0.5)
	end
end
