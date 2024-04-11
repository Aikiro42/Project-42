function init()
    --Power
    self.maxPowerModifier = config.getParameter("maxPowerModifier", 2)
    self.statEffectId = effect.addStatModifierGroup({{stat = "powerMultiplier", effectiveMultiplier = 1}})
end


function update(dt)
    local x = 1 + ((self.maxPowerModifier - 1) * (1 - status.resourcePercentage("health"))) 
    --sb.logInfo(sb.printJson(status.resourcePercentage("health")))
    effect.setStatModifierGroup(self.statEffectId, {{stat = "powerMultiplier", effectiveMultiplier = x}})
end

function uninit()

end
