function init()
  enableParticleEmitter("healing")
  enableParticleEmitter("energy")
  enableParticleEmitter("feathers")

  self.healthRate = config.getParameter("healthRate", 0.05)
  self.energyRate = config.getParameter("energyRate", 0.175)
  self.fallDamageMultiplier = config.getParameter("fallDamageMultiplier", 0.1)

  effect.addStatModifierGroup({{stat = "fallDamageMultiplier", effectiveMultiplier = self.fallDamageMultiplier}})

end

function update(dt)
  status.giveResource("health", self.healthRate * status.resourceMax("health") * dt)
  status.giveResource("energy", self.energyRate * status.resourceMax("energy") * dt)
end

function uninit()
  
end

function enableParticleEmitter(particleEmitter)
  animator.setParticleEmitterOffsetRegion(particleEmitter, mcontroller.boundBox())
  animator.setParticleEmitterEmissionRate(particleEmitter, config.getParameter("emissionRate", 3))
  animator.setParticleEmitterActive(particleEmitter, true)
end
