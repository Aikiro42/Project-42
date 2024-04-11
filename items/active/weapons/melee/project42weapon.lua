require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/project42_helper.lua"
require "/items/active/weapons/weapon.lua"

local lifestealListener

function init()

  -- debug stuff above

  animator.setGlobalTag("paletteSwaps", config.getParameter("paletteSwaps", ""))
  animator.setGlobalTag("directives", "")
  animator.setGlobalTag("bladeDirectives", "")

  self.weapon = Weapon:new()

  self.weapon:addTransformationGroup("weapon", {0,0}, util.toRadians(config.getParameter("baseWeaponRotation", 0)))
  self.weapon:addTransformationGroup("swoosh", {0,0}, math.pi/2)

  local primaryAbility = getPrimaryAbility()
  self.weapon:addAbility(primaryAbility)

  local secondaryAttack = getAltAbility()
  if secondaryAttack then
    self.weapon:addAbility(secondaryAttack)
  end

  self.weapon:init()

  self.movementSpeedFactor = config.getParameter("movementSpeedFactor", 1.75)
  self.jumpHeightFactor = config.getParameter("jumpHeightFactor", 1.5)

  self.displayText = config.getParameter("displayText", true)
  self.textOffset = config.getParameter("textOffset", {2, 2})
  self.textShake = config.getParameter("textShake", 0.1)
  self.textColor = config.getParameter("textColor", {255, 75, 10})
  self.textHealthThreshold = config.getParameter("textHealthThreshold", 0.75)

  self.lifestealRate = config.getParameter("lifestealRate", 0.01)
  self.critLifestealMult = config.getParameter("critLifestealMult", 3)
  self.critLifeThreshold = config.getParameter("critLifeThreshold", 0.3)

  lifestealListener = damageListener("inflictedDamage", function(notifications)
    for _,notification in pairs(notifications) do
      if notification.sourceEntityId == activeItem.ownerEntityId() then
        if notification.healthLost > 0 then
          local lifestealFactor = 1 + (self.critLifestealMult * (1 - math.min(status.resourcePercentage("health") / self.critLifeThreshold, 1)))
          status.giveResource("health", status.resourceMax("health") * self.lifestealRate * lifestealFactor)
        end
      end
    end
  end)

  mcontroller.setAutoClearControls(true)

end

function update(dt, fireMode, shiftHeld)

  -- DEBUG STUFF ABOVE

  self.weapon:update(dt, fireMode, shiftHeld)
  lifestealListener:update()
    
  activeItem.setScriptedAnimationParameter("playerPosition", mcontroller.position())
  activeItem.setScriptedAnimationParameter("playerHandPosition", activeItem.handPosition())
  activeItem.setScriptedAnimationParameter("playerAimPosition", activeItem.ownerAimPosition())
  activeItem.setScriptedAnimationParameter("playerFacingDirection", mcontroller.facingDirection())
  
  activeItem.setScriptedAnimationParameter("healthMissing", 1 - status.resourcePercentage("health"))
  
  -- activeItem.setScriptedAnimationParameter("currentDamageMultiplier", string.format("^shadow;%.1f%% Power", status.stat("powerMultiplier")*100))
  activeItem.setScriptedAnimationParameter("displayText", self.displayText)
  activeItem.setScriptedAnimationParameter("textOffset", self.textOffset)
  activeItem.setScriptedAnimationParameter("textShake", self.textShake)
  activeItem.setScriptedAnimationParameter("textColor", self.textColor)
  activeItem.setScriptedAnimationParameter("textHealthThreshold", self.textHealthThreshold)
  
  status.addEphemeralEffect("project42healthdamageboost")

  if shiftHeld then
    if not self.weapon.currentAbility then
      status.addEphemeralEffect("project42passive")
    else
      status.removeEphemeralEffect("project42passive")
    end
    mcontroller.controlModifiers({
      speedModifier = 1,
      airJumpModifier = self.jumpHeightFactor
    })
  else
    mcontroller.controlModifiers({
      speedModifier = self.movementSpeedFactor,
      airJumpModifier = self.jumpHeightFactor
    })
  end

end

function uninit()
  status.clearPersistentEffects("comboCounterDamageBoost")
  status.removeEphemeralEffect("project42healthdamageboost")
  self.weapon:uninit()
end
