function init()
    --Power
    self.powerModifier = config.getParameter("powerModifier", 1.25)
    self.protectionModifier = config.getParameter("protectionModifier", 0.5)
    effect.addStatModifierGroup({{stat = "powerMultiplier", effectiveMultiplier = self.powerModifier}})
    effect.addStatModifierGroup({{stat = "protection", effectiveMultiplier = self.protectionModifier}})
end


function update(dt)

end

function uninit()

end
