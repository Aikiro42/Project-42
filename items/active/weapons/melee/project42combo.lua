require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/poly.lua"
require "/scripts/vec2.lua"
require "/scripts/project42_helper.lua"
require "/items/active/weapons/weapon.lua"

-- Melee primary ability
Project42Combo = WeaponAbility:new()

local isFalling = true
local isOnGround = false
local canReblade = false

local canPerfectParry = true
local perfectParryTriggered = false
local perfectParryCombostep = 1
local perfectParryFreeTimer = 0

local heavyChargeTimer = 0
local shiftHeldTime = -1

local parryListener
local windupParryListener
local perfectParryListener
local parryPoly, orientedParryPoly
local parried = false

local dodge = {}
local canDodge = false
local dodgeCooldownTimer
local dodgeTimer = 0

local comboListener
local comboShake = 0
local comboCounter = 0
local comboDurationTimer = 0
local comboPower = 1
local comboDecayTimer = 0

local prevState

local critChance
local critHit = false

local baseStepDamage = {}

local stanceFlipConfig = {}
local parriedProj = false

local parryPolyTimer = 0

function Project42Combo:init()

  -- reset stuff
  animator.setGlobalTag("directives", "")
  mcontroller.setRotation(0)
  animator.setParticleEmitterActive("heavyCharge", false)  -- disables particles emitted while charging
  animator.setParticleEmitterActive("heavyReady", false) -- enables particles emitted when ready

  unparry()

  -- flags and local vars
  isFalling = mcontroller.yVelocity() < 0 and not mcontroller.onGround()  
  
  -- variables and parameters

  dodge.dodgeTriggerTime = config.getParameter("dodgeTriggerTime", 0.5)
  dodge.dodgeTime = config.getParameter("dodgeTime", 0.15)
  dodge.dodgeSpeed = config.getParameter("dodgeSpeed", 60)
  dodge.dodgeCooldown = config.getParameter("dodgeCooldown", 0.05)
  dodge.dodgeCleanseCooldown = config.getParameter("dodgeCleanseCooldown", 7)
  dodge.dodgeEnergyRate = config.getParameter("dodgeEnergyRate", 0.05)
  dodge.dodgeEndXVelocityFactor = config.getParameter("dodgeEndXVelocityFactor", 0.5)
  dodge.dodgeIFrameLinger = config.getParameter("dodgeIFrameLinger", 0)
  dodgeCooldownTimer = dodge.dodgeCooldown

  self.activeTimer = 0

  parryPoly = generateParryPoly(self.parryRange, self.parryDegrees, self.parryStartWidth)

  -- animation states
  animator.setAnimationState("blade", "inactive")

  -- scripted animation parameters
  activeItem.setScriptedAnimationParameter("heavyChargeTime", self.heavyChargeTime)

  -- listeners
  parryListener = damageListener("damageTaken", function(notifications)
    for _,notification in pairs(notifications) do
      if world.entityType(notification.sourceEntityId) ~= "player" and notification.healthLost == 0 then
        self:parryListenerAction(nil, true)
      end
    end
  end)

  comboListener = damageListener("inflictedDamage", function(notifications)
    for _,notification in pairs(notifications) do
      if notification.sourceEntityId == activeItem.ownerEntityId() then
        if notification.healthLost > 0 then
          if critHit then
            self:screenShake(self.strongScreenShakeAmount)
            animator.burstParticleEmitter("critHit")
          else
            self:screenShake(self.weakScreenShakeAmount)
          end
          comboDurationTimer = self.comboDuration
          comboCounter = math.min(comboCounter + 1, self.comboLimit)
          comboShake = self.comboShakeAmount
        end
      end
    end
  end)

  windupParryListener = damageListener("damageTaken", function(notifications)
    for _,notification in pairs(notifications) do
      if world.entityType(notification.sourceEntityId) ~= "player" and notification.healthLost == 0 then
        parried = true
        self:parryListenerAction(self.fire, true)
        return
      end
    end
  end)

  perfectParryListener = damageListener("damageTaken", function(notifications)
    for _,notification in pairs(notifications) do
      if world.entityType(notification.sourceEntityId) ~= "player" then
        animator.stopAllSounds("perfectParryReady")
        
        status.addEphemeralEffect("project42invuln", 1)
        self:parryListenerAction(self.perfectParryFire, false)

        return
        
      end
    end
  end)

  -- generic stuff
  animator.setParticleEmitterActive("dodgeParticles", false)
  animator.setAnimationState("swoosh", "idle")  -- should stop persisting sfx/vfx when wall latching while doing stuff
  self.comboStep = 1
  self:computeDamageAndCooldowns()
  self.weapon:setStance(self.stances.idle)
  if self.stances.idle.flipWeapon then
    animator.setGlobalTag("directives", "?flipx")
  else
    animator.setGlobalTag("directives", "")
  end
  self.edgeTriggerTimer = 0
  self.flashTimer = 0
  self.cooldownTimer = self.cooldowns[1]
  self.animKeyPrefix = self.animKeyPrefix or ""
  self.weapon.onLeaveAbility = function()  
    self.weapon:setStance(self.stances.idle)
    if self.stances.idle.flipWeapon then
      animator.setGlobalTag("directives", "?flipx")
    else
      animator.setGlobalTag("directives", "")
    end
  end

  self.parryTimer = self.parryTimer or 0.2

end

-- Ticks on every update regardless if this is the active ability
function Project42Combo:update(dt, fireMode, shiftHeld)

  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  parryPolyTimer = math.max(0, parryPolyTimer - dt)

  -- blade appearance stuff
  if self.weapon.currentAbility then
    self.activeTimer = config.getParameter("activeTime", 1)
  end
  self.activeTimer = math.max(0, self.activeTimer - self.dt)
  if self.activeTimer == 0 then
    self:deactivateBlade()
  end

  -- timers
  dodgeCooldownTimer = math.max(0, dodgeCooldownTimer - self.dt)
  comboDurationTimer = math.max(comboDurationTimer - (heavyChargeTimer > 0 and 0 or self.dt), 0)
  comboDecayTimer = math.max(comboDecayTimer - self.dt, 0)

  -- flags
  canDodge = shiftHeldTime >= 0 and (shiftHeldTime < dodge.dodgeTriggerTime or dodge.dodgeTriggerTime <= 0) and dodgeCooldownTimer == 0 and not shiftHeld and not perfectParryTriggered
  canPerfectParry = shiftHeld and not self.weapon.currentAbility and not status.resourceLocked("energy")
  canReblade = animator.animationState("handle") ~= "noblade" or status.resourcePercentage("health") > config.getParameter("rebladeHealthCostRate")
  isFalling = mcontroller.yVelocity() < 0 and not mcontroller.onGround()

  -- combo stuff
  comboListener:update()
  comboShake = math.max(comboShake - self.dt, 0)
  if comboDurationTimer == 0 and comboDecayTimer == 0 and comboCounter > 0 then
      comboCounter = comboCounter - 1
      comboDecayTimer = self.comboDecay
  end
  comboPower = 1 + comboCounter * self.comboPowerMult
  activeItem.setScriptedAnimationParameter("comboShake", comboShake)
  activeItem.setScriptedAnimationParameter("comboCounter", comboCounter)
  activeItem.setScriptedAnimationParameter("comboTextColor", comboCounter == self.comboLimit and self.comboTextColorMax or self.comboTextColor)

  -- heavy charge stuff
  activeItem.setScriptedAnimationParameter("heavyChargeTimer", heavyChargeTimer)

  -- crit stuff
  critChance = (1 - status.resourcePercentage("health")) * self.critChanceCap
  activeItem.setScriptedAnimationParameter("critChance", string.format("^shadow;%.1f%% Crit Chance", critChance*100))

  if shiftHeld then
    if shiftHeldTime < 0 then
      shiftHeldTime = 0
    end
    if not self.weapon.currentAbility then
      status.removeEphemeralEffect("project42invuln")
    end
    shiftHeldTime = shiftHeldTime + self.dt
  else
    if canDodge and not self.weapon.currentAbility then
      self:setState(self.dodge)
    end
    if #status.getPersistentEffects("project42_noFallDamage") > 0 then
      status.clearPersistentEffects("project42_noFallDamage")
    end
    status.removeEphemeralEffect("project42invuln")
    perfectParryFreeTimer = self.perfectParryFreeTime
    perfectParryCombostep = 1
    perfectParryTriggered = false
    shiftHeldTime = -1
  end

  -- gives damage boost when energy is locked
  if status.resourceLocked("energy") then
    status.addEphemeralEffect("project42energylockdamageboost")
  else
    status.removeEphemeralEffect("project42energylockdamageboost")
  end

  -- generic stuff
  if self.cooldownTimer > 0 then
    self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)
    if self.cooldownTimer == 0 then
      self:readyFlash()
    end
  end

  if self.flashTimer > 0 then
    self.flashTimer = math.max(0, self.flashTimer - self.dt)
    if self.flashTimer == 0 then
      animator.setGlobalTag("bladeDirectives", "")
    end
  end

  self.edgeTriggerTimer = math.max(0, self.edgeTriggerTimer - dt)
  if self.lastFireMode ~= (self.activatingFireMode or self.abilitySlot) and fireMode == (self.activatingFireMode or self.abilitySlot) then
    self.edgeTriggerTimer = self.edgeTriggerGrace
  end
  self.lastFireMode = fireMode

  if not self.weapon.currentAbility and self:shouldActivate() then
    if canPerfectParry then
      self:setState(self.perfectParryReady)
    elseif shiftHeldTime < 0 and not status.resourceLocked("energy") then
      self:setState(self.heavyCharge)
    else
      self:setState(self.windup)
    end
  end
end

function Project42Combo:dodge()

  if dodge.dodgeEnergyRate then
    if not status.resourceLocked("energy") then
      status.overConsumeResource("energy", dodge.dodgeEnergyRate * status.resourceMax("energy"))
    else
      status.setResourcePercentage("energy", 0)
    end
  end
    
  if not isIn2dTable(status.activeUniqueStatusEffectSummary(), 1, "project42cleanse") then
    status.addEphemeralEffect("project42cleanse", dodge.dodgeCleanseCooldown)
  end
  status.addEphemeralEffect("project42dodging", dodge.dodgeTime + dodge.dodgeIFrameLinger)

  local dodgeDirection
  if mcontroller.xVelocity() ~= 0 then
    dodgeDirection = mcontroller.movingDirection()
  else
    dodgeDirection = mcontroller.facingDirection()
  end

  --local airborne = not mcontroller.onGround()
  animator.playSound("dodge")
  util.wait(dodge.dodgeTime, function(dt)
    mcontroller.setVelocity({dodge.dodgeSpeed*dodgeDirection, 0})
  end)

  mcontroller.setRotation(0)
  mcontroller.setXVelocity(mcontroller.xVelocity() * dodge.dodgeEndXVelocityFactor)
  animator.setParticleEmitterActive("dodgeParticles", false)
  dodgeCooldownTimer = dodge.dodgeCooldown
  shiftHeldTime = -1

  if prevState then
    local nextState = prevState
    prevState = nil
    self:setState(nextState)
  end
end

-- State: windup
function Project42Combo:windup()


  self:activateBlade()
  
  parried = false

  local stance = self.stances["windup"..self.comboStep]
  self.weapon:setStance(stance)
  heavyChargeTimer = 0

  if stance.flipWeapon then
    animator.setGlobalTag("directives", "?flipx")
  else
    animator.setGlobalTag("directives", "")
  end

  self.edgeTriggerTimer = 0
  parryPolyTimer = self.parryTimer

  if stance.hold then
    while self.fireMode == (self.activatingFireMode or self.abilitySlot) do
      orientParryPoly()
      parryUpdate(windupParryListener, orientedParryPoly, 0, 0, nil, self.parryRange, nil, true)
      coroutine.yield()
    end
  else
    util.wait(stance.duration, function()
      orientParryPoly()
      parryUpdate(windupParryListener, orientedParryPoly, 0, 0, nil, self.parryRange, nil, true)
    end)
  end

  if self.stances["preslash"..self.comboStep] then
    self:setState(self.preslash)
  else
    self:setState(self.fire)
  end
end

-- State: wait
-- waiting for next combo input
function Project42Combo:wait()

  unparry()

  local stance = self.stances["wait"..(self.comboStep - 1)]

  self.weapon:setStance(stance)

  if stance.flipWeapon then
    animator.setGlobalTag("directives", "?flipx")
  else
    animator.setGlobalTag("directives", "")
  end

  util.wait(stance.duration, function()

    -- interrupts combo to use alt ability
    if self.fireMode == "alt" then
      animator.setGlobalTag("directives", "")
      self:setState(self.init)
      return
    end
    
    if canDodge then
      prevState = self.wait
      self:setState(self.dodge)
      return
    end
    
    if self:shouldActivate() then
      animator.setGlobalTag("directives", "")
      if shiftHeldTime >= 0 then
        self:setState(self.perfectParryReady)
      elseif not status.resourceLocked("energy") and not parried then
        self:setState(self.heavyCharge)
      else
        self:setState(self.windup)
      end
      return
    end
    
  end)

  animator.setGlobalTag("directives", "")
  self.cooldownTimer = math.max(0, self.cooldowns[self.comboStep - 1] - stance.duration)
  self.comboStep = 1

end

local glinted = false
function Project42Combo:heavyCharge()

  self:activateBlade()
  -- local stance = self.stances.heavyWindup

  animator.setAnimationState("swoosh", "heavyCharge")
  animator.setParticleEmitterActive("heavyCharge", true)  -- enables particles emitted while charging

  while self.fireMode == "primary" do
    heavyChargeTimer = heavyChargeTimer + self.dt
    if canDodge then
      prevState = self.heavyCharge
      self:setState(self.dodge)
    end

    -- if falling, slow descent
    if isFalling and self.heavyChargeVelocityFactor then
      mcontroller.controlApproachVelocity(vec2.mul(mcontroller.velocity(), self.heavyChargeVelocityFactor), self.heavyChargeVelocityControlForce)
    end    

    if heavyChargeTimer > self.heavyChargeTime then
      
      -- stance = self.stances.heavyReady
      -- self.weapon:setStance(stance)

      if status.resourcePercentage("health") <= 0.01 then break end

      status.overConsumeResource("health", self.heavyHealthDegenRate * status.resourceMax("health") * self.dt)
      animator.setParticleEmitterActive("heavyCharge", false)  -- disables particles emitted while charging
      animator.setParticleEmitterActive("heavyReady", true) -- enables particles emitted when ready
      
      if not glinted then
        status.addEphemeralEffect("project42perfectunleash", self.perfectHeavyTime)
        animator.setParticleEmitterBurstCount("heavyGlint", 3)
        animator.burstParticleEmitter("heavyGlint") -- shine when ready
        glinted = true
      end
      
      animator.setGlobalTag("bladeDirectives", "border=".. math.min(math.floor(heavyChargeTimer), self.heavyMaxBorderWidth) ..";"..self.heavyChargeBorder..";00000000")
      animator.setAnimationState("swoosh", "heavyReady")
      
    end
    
    coroutine.yield()
  
  end

  animator.setGlobalTag("directives", "")

  -- when letting go of the primary key, stop charging
  animator.setParticleEmitterActive("heavyCharge", false)
  animator.setParticleEmitterActive("heavyReady", false)

  glinted = false

  status.removeEphemeralEffect("project42perfectunleash")

  -- if there is available energy and weapon is sufficiently charged,
  if heavyChargeTimer > self.heavyChargeTime and status.overConsumeResource("energy", status.resourceMax("energy") * self.heavyEnergyUsageRate) then
      self:setState(self.heavyWindup)
  else
      -- heavyChargeTimer = 0
      self:setState(self.windup)
  end
end

function Project42Combo:heavyWindup()

  self:activateBlade()

  local stance = self.stances["windup"..self.comboStep]
  self.weapon:setStance(stance)

  if stance.flipWeapon then
    animator.setGlobalTag("directives", "?flipx")
  else
    animator.setGlobalTag("directives", "")
  end

  self.edgeTriggerTimer = 0

  if stance.hold then
    while self.fireMode == (self.activatingFireMode or self.abilitySlot) do
      coroutine.yield()
    end
  else
    util.wait(stance.duration)
  end

  if self.stances["preslash"..self.comboStep] then
    self:setState(self.heavyPreslash)
  else
    self:setState(self.heavyFire)
  end
end


-- State: preslash
-- brief frame in between windup and fire
function Project42Combo:heavyPreslash()

  self:activateBlade()

  local stance = self.stances["preslash"..self.comboStep]

  self.weapon:setStance(stance)
  self.weapon:updateAim()

  util.wait(stance.duration)

  self:setState(self.heavyFire)

end


function Project42Combo:heavyFire()

  self:deblade()
  local isPerfectHeavy = heavyChargeTimer - self.heavyChargeTime < self.perfectHeavyTime

  local perfectHeavyDamageFactor = isPerfectHeavy and self.perfectHeavyDamageMult or 1
  -- local stance = self.stances.heavyFire
  local stance = self.stances["fire" .. self.comboStep]
  self.weapon:setStance(stance)
  self.weapon:updateAim()
  local animStateKey = self.animKeyPrefix .. (self.comboStep > 1 and "fire"..self.comboStep or "fire")

  animator.setAnimationState("swoosh", animStateKey)
  animator.playSound(animStateKey)

  local swooshKey = self.animKeyPrefix .. (self.elementalType or self.weapon.elementalType) .. "swoosh"
  animator.setParticleEmitterOffsetRegion(swooshKey, self.swooshOffsetRegions[self.comboStep])
  animator.burstParticleEmitter(swooshKey)

  if isPerfectHeavy then
    self:screenShake(self.strongScreenShakeAmount)
    status.addEphemeralEffect("project42zan")
  else
    self:screenShake(self.weakScreenShakeAmount)
  end
  animator.playSound("heavyFire")
    
  local heavyDmgFactor = (1 + ((heavyChargeTimer - self.heavyChargeTime) * self.heavyChargeDamageBoostPercent)) * perfectHeavyDamageFactor * comboPower
  comboCounter = 0

  local recoilVector = vec2.norm(world.distance(activeItem.ownerAimPosition(),mcontroller.position()))
  local launchSpeed = self.heavySlashCarry
  local isOnGround = mcontroller.onGround()

  local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(0, 0))
  aimVector[1] = aimVector[1] * mcontroller.facingDirection()	
  
  local params = self.heavyProjectileParameters or {}
  params.powerMultiplier = activeItem.ownerPowerMultiplier() * heavyDmgFactor * config.getParameter("damageLevelMultiplier")
  params.upgraded = config.getParameter("upgraded", false)
  mcontroller.setVelocity(vec2.mul(recoilVector, launchSpeed))
  if self.heavyProjectiles and #self.heavyProjectiles > 0 then
    for _,projectile in pairs(self.heavyProjectiles) do
      world.spawnProjectile(
            projectile,
            mcontroller.position(),
            activeItem.ownerEntityId(),
            aimVector,
            false,
            params
          )
      util.wait(self.heavyProjectileFiretime)
    end
  elseif self.heavyProjectile then
    world.spawnProjectile(
      self.heavyProjectile,
      mcontroller.position(),
      activeItem.ownerEntityId(),
      aimVector,
      false,
      params
    )
  end
  
  self.heavyDamageConfig.baseDamageMultiplier = heavyDmgFactor

  util.wait(stance.duration, function()
    local damageArea = partDamageArea("swoosh")
    self.weapon:setDamage(self.heavyDamageConfig, damageArea)
  end)

  heavyChargeTimer = 0

  -- self.cooldownTimer = self.cooldowns[self.comboStep]
  -- self.comboStep = 1

  if stance.cooldown then
    util.wait(stance.cooldown)
  end
  
  if self.comboStep < self.comboSteps then
    self.comboStep = self.comboStep + 1
    self:setState(self.wait)
  else
    self.cooldownTimer = self.cooldowns[self.comboStep]
    self.comboStep = 1
  end


end

-- State: preslash
-- brief frame in between windup and fire
function Project42Combo:preslash()

  self:activateBlade()

  local stance = self.stances["preslash"..self.comboStep]

  if stance.flipWeapon then
    animator.setGlobalTag("directives", "?flipx")
  else
    animator.setGlobalTag("directives", "")
  end

  self.weapon:setStance(stance)
  self.weapon:updateAim()

  util.wait(stance.duration, function()
    windupParryListener:update()
  end)

  self:setState(self.fire)
end

function Project42Combo:perfectParryReady()

  if not canPerfectParry then
    status.removeEphemeralEffect("project42invuln")
    animator.setAnimationState("swoosh", "idle")
    return
  end

  self:reblade()

  local stance = self.stances.perfectParryReady
  if stance.flipWeapon then
    animator.setGlobalTag("directives", "?flipx")
  else
    animator.setGlobalTag("directives", "")
  end
  self.weapon:setStance(stance)
  self.weapon:updateAim()
  animator.setAnimationState("swoosh", "perfectParryReady")
  animator.playSound("perfectParryReady")

  self.comboStep = 1
  perfectParryTriggered = true

  if perfectParryFreeTimer > 0 then
    status.addEphemeralEffect("project42perfectparry", perfectParryFreeTimer)
  end

  status.removeEphemeralEffect("project42invuln")
  -- parry detection radius: 3.5625
  parryUpdate(perfectParryListener, stance.parryPoly, stance.armRotation, self.weapon.aimAngle, 0, 3.5625, nil, nil, status.resourceMax("energy"))
  
  while self.fireMode == "primary" and shiftHeldTime >= 0 and status.resourcePositive("energy") do
    parryUpdate(perfectParryListener, stance.parryPoly, stance.armRotation, self.weapon.aimAngle, 0, 3.5625, nil, nil, status.resourceMax("energy"))
    status.overConsumeResource("energy", self.dt * self.perfectParryChannelEnergyRate * status.resourceMax("energy"))
    perfectParryFreeTimer = math.max(perfectParryFreeTimer - self.dt, 0)
    if perfectParryFreeTimer == 0 then
      animator.setAnimationState("blade", "inactive")
    else
      shineBlade()
    end
    coroutine.yield()
  end
  self:deactivateBlade()
  status.removeEphemeralEffect("project42perfectparry")
  unparry()
end

function Project42Combo:perfectParryFire()

  -- delay for a tick since this is instant
  -- util.wait(self.dt)
  
  local stance = self.stances["perfectParryFire" .. perfectParryCombostep]

  self.weapon:setStance(stance)
  
  if stance.flipWeapon then
    animator.setGlobalTag("directives", "?flipx")
  else
    animator.setGlobalTag("directives", "")
  end

  self.weapon:updateAim()

  animator.setAnimationState("swoosh", "perfectParryFire" .. perfectParryCombostep)
  animator.playSound("perfectParryFire" .. perfectParryCombostep)

  -- for the duration of the slash...
  util.wait(stance.duration, function()
    local damageArea = partDamageArea("swoosh")
    self.weapon:setDamage(self.perfectParryDamageConfig, damageArea)
  end)
  
  unparry()

  if perfectParryFreeTimer == 0 then
    status.overConsumeResource("energy", self.perfectParryEnergyUsageRate * status.resourceMax("energy"))
  else
    perfectParryFreeTimer = self.perfectParryFreeTime
  end

  perfectParryCombostep = (perfectParryCombostep % self.perfectParryCombosteps) + 1
  
end

-- State: fire
function Project42Combo:fire()


  -- DEBUG STUFF ABOVE

  -- arrest velocity
  mcontroller.setVelocity(vec2.mul(mcontroller.velocity(), 0.2))

  self:activateBlade()

  local stance = self.stances["fire"..self.comboStep]

  if parried and stance.disableCounter then
    self.comboStep = self.comboStep + 1
    if self.comboStep > self.comboSteps then
      self.comboStep = 1
    end
    stance = self.stances["fire"..self.comboStep]
  end

  self.weapon:setStance(stance)
  
  if stance.flipWeapon then
    animator.setGlobalTag("directives", "?flipx")
  else
    animator.setGlobalTag("directives", "")
  end

  self.weapon:updateAim()

  local animStateKey = self.animKeyPrefix .. (self.comboStep > 1 and "fire"..self.comboStep or "fire")
  animator.setAnimationState("swoosh", animStateKey)
  animator.playSound(animStateKey)

  local swooshKey = self.animKeyPrefix .. (self.elementalType or self.weapon.elementalType) .. "swoosh"
  animator.setParticleEmitterOffsetRegion(swooshKey, self.swooshOffsetRegions[self.comboStep])
  animator.burstParticleEmitter(swooshKey)

  -- determine aim vector
  -- local aimVector = vec2.rotate({1, 0}, activeItem.aimAngle(0, activeItem.ownerAimPosition()))

  -- consume energy on slash
  if self.energyUsageRate then
    if not status.resourceLocked("energy") then
      status.overConsumeResource("energy", self.energyUsageRate * status.resourceMax("energy"))
    else
      status.setResourcePercentage("energy", 0)
    end
  end

  local wasOnGround = mcontroller.onGround()
  
  self.aerialLaunchVelocityAdd = 9
  local actualAdd = math.sin(activeItem.aimAngle(0, activeItem.ownerAimPosition())) * self.aerialLaunchVelocityAdd

  local v = {
    mcontroller.xVelocity(),
    math.max(math.abs(mcontroller.yVelocity()), mcontroller.yVelocity() + actualAdd)
  }

  -- calculate crit
  local critMult = self:rollCrit()
  if critMult > 1 then critHit = true end

  -- for the duration of the slash...
  util.wait(stance.duration, function()

    if not parried then
      -- parryUpdate(parryListener, partDamageArea("swoosh"), stance.armRotation, self.weapon.aimAngle)
      parryUpdate(parryListener, orientedParryPoly, stance.armRotation, self.weapon.aimAngle, nil, self.parryRange, nil, true)
    end

    if not wasOnGround then
      mcontroller.controlApproachVelocity(v, 1000)
    end

    local damageArea = partDamageArea("swoosh")
    self.stepDamageConfig[self.comboStep].baseDamage = baseStepDamage[self.comboStep] * comboPower * critMult
    self.weapon:setDamage(self.stepDamageConfig[self.comboStep], damageArea)

  end)

  critHit = false

  -- remove shield
  unparry()

  if stance.cooldown and (parried or status.resourceLocked("energy")) then
    util.wait(stance.cooldown)
  end
  
  if self.comboStep < self.comboSteps then
    self.comboStep = self.comboStep + 1
    self:setState(self.wait)
  else
    self.cooldownTimer = self.cooldowns[self.comboStep]
    self.comboStep = 1
  end
end

function Project42Combo:shouldActivate()
  if self.cooldownTimer == 0 and canReblade then
    if self.comboStep > 1 then
      return self.edgeTriggerTimer > 0
    else
      return self.fireMode == (self.activatingFireMode or self.abilitySlot)
    end
  end
end

function Project42Combo:readyFlash()
  animator.setGlobalTag("bladeDirectives", self.flashDirectives)
  self.flashTimer = self.flashTime
end

function Project42Combo:computeDamageAndCooldowns()
  local attackTimes = {}
  for i = 1, self.comboSteps do
    local attackTime = self.stances["windup"..i].duration + self.stances["fire"..i].duration
    if self.stances["preslash"..i] then
      attackTime = attackTime + self.stances["preslash"..i].duration
    end
    table.insert(attackTimes, attackTime)
  end

  self.cooldowns = {}
  local totalAttackTime = 0
  local totalDamageFactor = 0
  for i, attackTime in ipairs(attackTimes) do
    self.stepDamageConfig[i] = util.mergeTable(copy(self.damageConfig), self.stepDamageConfig[i])
    self.stepDamageConfig[i].timeoutGroup = "primary"..i

    local damageFactor = self.stepDamageConfig[i].baseDamageFactor
    self.stepDamageConfig[i].baseDamage = damageFactor * self.baseDps * self.fireTime
    baseStepDamage[i] = damageFactor * self.baseDps * self.fireTime

    totalAttackTime = totalAttackTime + attackTime
    totalDamageFactor = totalDamageFactor + damageFactor

    local targetTime = totalDamageFactor * self.fireTime
    local speedFactor = 1.0 * (self.comboSpeedFactor ^ i)
    table.insert(self.cooldowns, (targetTime - totalAttackTime) * speedFactor)
  end
end

function Project42Combo:uninit()
  self.weapon:setDamage()
  status.clearPersistentEffects("broadswordParry")
  status.clearPersistentEffects("project42_noFallDamage")
  animator.setAnimationState("swoosh", "idle")
  heavyChargeTimer = 0
end

-- helper functions

function Project42Combo:parryListenerAction(nextState, projIgnoresDef)

  -- should prevent damage leakage through parries
  -- status.addEphemeralEffect("cultistshield", 0.1)

  if status.resourcePositive("shieldStamina") then

    activeItem.setRecoil(true)
    -- unparry()
    if parriedProj then
      animator.stopAllSounds("reflect")
      animator.playSound("reflect") 
      local aimVector = vec2.rotate({1, 0}, activeItem.aimAngle(0, activeItem.ownerAimPosition()) + math.rad(sb.nrand(self.reflectProjectileInaccuracy, 0)))
      local params = self.projectileParameters or {}
      params.power = projIgnoresDef and status.resourceMax("energy") * self.energyDamageScaling or (self.baseDps * config.getParameter("damageLevelMultiplier"))
      params.powerMultiplier = activeItem.ownerPowerMultiplier()
      params.damageType = projIgnoresDef and "IgnoresDef" or "damage"
      world.spawnProjectile(
        self.reflectProjectile,
        mcontroller.position(),
        activeItem.ownerEntityId(),
        aimVector,
        false,
        params
      )
    else
      self:screenShake(self.weakScreenShakeAmount)
      animator.stopAllSounds("parry")
      animator.playSound("parry")
    end
  else
    self:screenShake(self.strongScreenShakeAmount)
    animator.playSound("parryBreak")
    status.overConsumeResource("energy", status.resourceMax("energy"))
  end
  if nextState then
    self:setState(nextState)
  end
end

function parry(parryPoly, centerOnPlayer, shieldHealth)
  
  status.setPersistentEffects("broadswordParry", {{stat = "shieldHealth", amount = shieldHealth or status.resource("energy")}})
  status.resetResource("shieldStamina")

  if not centerOnPlayer then
    activeItem.setItemShieldPolys({parryPoly})
  else
    activeItem.setShieldPolys({parryPoly})
  end

end

function unparry()
  status.clearPersistentEffects("broadswordParry")
  activeItem.setItemShieldPolys({})
  activeItem.setShieldPolys({})
end

-- FIXME: what value should this return? The function's return value isn't used at all.
function parryUpdate(parryListener, parryPoly, armRotation, aimAngle, offset, queryRadius, queryPosition, centerOnPlayer, shieldHealth)
  
  if (not perfectParryTriggered) and parryPolyTimer <= 0 then
    unparry()
    return true
  end
  
  -- local offset = offset or 0
  -- local queryRadius = queryRadius or 3.5625
  -- local queryPosition = queryPosition or vec2.add(mcontroller.position(), activeItem.handPosition())
  if not status.resourcePositive("shieldStamina") then return true end
  if parryPoly then
    parriedProj = projectileInHurtbox(parryPoly, armRotation, aimAngle, offset, queryRadius, queryPosition, centerOnPlayer)
        
    parry(parryPoly, centerOnPlayer, shieldHealth)

    parryListener:update()
  end
  activeItem.setRecoil(false)
end


function projectileInHurtbox(damageArea, parryArmRotation, parryAimAngle, offset, queryRadius, queryPosition, centerOnPlayer)
  local queryPosition = queryPosition or mcontroller.position()
  local queryRadius = queryRadius or 12
  local entityIDs = world.entityQuery(queryPosition, queryRadius,
    {
      withoutEntityId = entity.id(),
      includedTypes = {"projectile"},
      order = "nearest"
    }
  )
  local world_parrybox = convertToWorldCoords(damageArea, parryArmRotation, parryAimAngle, offset, centerOnPlayer)
  world.debugPoly(world_parrybox, "green")
  if #entityIDs > 0 then
    for _, entityId in pairs(entityIDs) do
      if entityId > 0 and world.polyContains(world_parrybox, world.entityPosition(entityId)) and not root.projectileConfig(world.entityName(entityId)).piercing then
        return true
      end
    end
  end
  return false
end

function convertToWorldCoords(hurtbox, armRotation, aimAngle, offset, centerOnPlayer)
    
  local offset = offset or 0
  local worldpoly = hurtbox
  local armRotation = armRotation or 0
  local direction = mcontroller.facingDirection()


  if not centerOnPlayer then

    -- rotate poly by stance's armRotation and aimAngle
    polyOrientation = math.rad(armRotation) + aimAngle -- compute
    worldpoly = poly.rotate(worldpoly, polyOrientation) -- apply

    -- flip poly to facing direction
    if direction == -1 then
      worldpoly = poly.flip(worldpoly)
    end

    -- translate to hand position
    worldpoly = poly.translate(worldpoly, activeItem.handPosition())

    -- convert to world coords    
    worldpoly = poly.translate(worldpoly, mcontroller.position())

    -- offset poly
    local offsetVector = {offset * math.cos(aimAngle)*direction, offset * math.sin(aimAngle)}
    worldpoly = poly.translate(worldpoly, offsetVector)

  else
    -- convert to world coords
    worldpoly = poly.translate(worldpoly, mcontroller.position())

  end
      
    return worldpoly
end

function Project42Combo:deblade()
  animator.setAnimationState("blade", "inactive")
  animator.setAnimationState("handle", "noblade")
end

function Project42Combo:reblade()
  if animator.animationState("handle") == "noblade" then
    status.modifyResourcePercentage("health", -1 * config.getParameter("rebladeHealthCostRate", 0.1))
    animator.setAnimationState("handle", "reblade")
  end
end

function Project42Combo:activateBlade()
  self:reblade()
  if animator.animationState("blade") ~= "active" and animator.animationState("blade") ~= "extend" then
    animator.setAnimationState("blade", "extend")
  end
end

function Project42Combo:shineBlade()
  self:reblade()
  if animator.animationState("blade") ~= "sheen" and animator.animationState("blade") ~= "retractSheen" then
    if animator.animationState("blade") == "inactive" then
      animator.setAnimationState("blade", "sheen")
    else
      animator.setAnimationState("blade", "retractSheen")
    end
  end
end

function Project42Combo:deactivateBlade()
  if animator.animationState("blade") ~= "inactive" and animator.animationState("blade") ~= "retract" then
    if animator.animationState("blade") == "sheen" then
      animator.setAnimationState("blade", "inactive")
    else
      animator.setAnimationState("blade", "retract")
    end
  end
end

function Project42Combo:rollCrit()
  math.randomseed(os.time())
  return math.random() < critChance and self.critMult or 1
end

function generateParryPoly(parryRange, parryDegrees, parryStartWidth)

  local parryPoly = {{0,-parryStartWidth/2}, {0,parryStartWidth/2}}

  local i = 0
  local segment = parryDegrees/7
  local angle = parryDegrees/2

  while i < 8 do
    angle = angle - (i > 0 and segment or 0)
    parryPoly[i+3] = {math.cos(math.rad(angle))*parryRange , math.sin(math.rad(angle))*parryRange}
    i = i + 1
  end

  return parryPoly

end

function orientParryPoly()
  orientedParryPoly = poly.rotate(parryPoly, activeItem.aimAngle(0, activeItem.ownerAimPosition())) -- rotate based on aimAngle
  orientedParryPoly = poly.translate(orientedParryPoly, {0, poly.center(mcontroller.baseParameters().standingPoly)[2]}) -- offset to center of player model
  return orientedParryPoly
end

function Project42Combo:screenShake(screenShakeAmount, shakeTime)
  local cam = world.spawnProjectile(
    "invisibleprojectile",
    vec2.add(mcontroller.position(), {sb.nrand(screenShakeAmount), sb.nrand(screenShakeAmount)}),
    0,
    {0, 0},
    false,
    {
      power = 0,
      timeToLive = shakeTime or 0.05,
      damageType = "NoDamage"
    }
  )
  activeItem.setCameraFocusEntity(cam)
end