require "/scripts/util.lua"
require "/scripts/poly.lua"
require "/scripts/vec2.lua"
require "/items/active/weapons/weapon.lua"
require "/scripts/status.lua"
require "/scripts/project42_helper.lua"


FatedSlash = WeaponAbility:new()

local tpLock = nil
local charged = false
local fullCharged = false
local showIndicator = false
local offCooldownAudio = false
local canDodge = false

local channelTime = 0
local shiftHeldTime = -1
local prevState

local baseDmgConfig = {}
local dodge = {}
local dodgeCooldownTimer
local dodgeCleanseCooldownTimer

local playerCollisionPoly = mcontroller.baseParameters().standingPoly
local playerCollisionPolyCenter = poly.center(playerCollisionPoly)

function FatedSlash:init()

  FatedSlash:reset()
  -- flags and local vars
  channelTime = 0
  charged = false
  fullCharged = false
  showIndicator = false
  baseDmgConfig.baseDamage = self.damageConfig.baseDamage or 1
  --debug_hits = 0

  dodge.dodgeTriggerTime = config.getParameter("dodgeTriggerTime", 0.3)
  dodge.dodgeTime = config.getParameter("dodgeTime", 0.15)
  dodge.dodgeSpeed = config.getParameter("dodgeSpeed", 60)
  dodge.dodgeCooldown = config.getParameter("dodgeCooldown", 0.05)
  dodge.dodgeCleanseCooldown = config.getParameter("dodgeCleanseCooldown", 7)
  dodge.dodgeEnergyRate = config.getParameter("dodgeEnergyRate", 0.05)
  dodge.dodgeEndXVelocityFactor = config.getParameter("dodgeEndXVelocityFactor", 0.5)
  dodge.dodgeIFrameLinger = config.getParameter("dodgeIFrameLinger", 0)
  dodgeCooldownTimer = dodge.dodgeCooldown
  dodgeCleanseCooldownTimer = dodge.dodgeCleanseCooldown

  -- parameters
  self.channelVelocityFactor = self.channelVelocityFactor or {0.1, 0.1}

  self.maxIndicatorLineThickness = self.maxIndicatorLineThickness or 2
  self.minIndicatorLineThickness = self.minIndicatorLineThickness or 0.5
  self.indicatorLineShrinkFactor = self.indicatorLineShrinkFactor or 1
  self.indicatorColor = self.indicatorColor or {255,75,50}
  self.indicatorColorCharged = self.indicatorColorCharged or {255,150,150}
  self.indicatorColorBad = self.indicatorColorBad or {125,125,125}


  self.fullChargeDamageFactor = self.fullChargeDamageFactor or 2

  -- generic
  self.cooldownTimer = 0  -- ability is cooled down on equip

end

function FatedSlash:update(dt, fireMode, shiftHeld)

  WeaponAbility.update(self, dt, fireMode, shiftHeld)
  self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)

  -- generic stuff above, don't touch

  local isFalling = mcontroller.yVelocity() < 0 and not mcontroller.onGround()

  canDodge = shiftHeldTime > 0 and shiftHeldTime < dodge.dodgeTriggerTime and dodgeCooldownTimer == 0 and not shiftHeld
  dodgeCooldownTimer = math.max(0, dodgeCooldownTimer - self.dt)
  dodgeCleanseCooldownTimer = math.max(0, dodgeCleanseCooldownTimer - self.dt)

  if shiftHeld then
    if shiftHeldTime < 0 then
      shiftHeldTime = 0
    end
    shiftHeldTime = shiftHeldTime + self.dt

    -- detect entities and light them up within range
    --[[

    Put in fatedslash.weaponability
    {  
      "detectEnabled": false,
      "entityDetectionRadius": 32,
      "detectedEntityColor": [100, 0, 0],
    }

    if self.detectEnabled then
      detectedCreatures = world.entityQuery(mcontroller.position(), self.entityDetectionRadius or 8, {__includedTypes__ = {"npc", "monster"}})
      activeItem.setScriptedAnimationParameter("detectedCreatures", detectedCreatures)
      activeItem.setScriptedAnimationParameter("detectedEntityColor", self.detectedEntityColor or {100, 0, 0})
    end
    --]]
  else
    shiftHeldTime = -1
    -- activeItem.setScriptedAnimationParameter("detectedCreatures", nil)
  end
  
  if self.cooldownTimer <= self.offCooldownAudioOffset and not offCooldownAudio then
    animator.playSound("fatedSlashReady")
    offCooldownAudio = true
  end

  activeItem.setScriptedAnimationParameter("showIndicator", showIndicator)

  if showIndicator then

    setTpLock()

    if isFalling then
      mcontroller.controlApproachVelocity(vec2.mul(mcontroller.velocity(), self.channelVelocityFactor), self.channelVelocityControlForce)
    end

    local indicatorImageLocation = tpLock or notLineOfSight(activeItem.ownerAimPosition()) or activeItem.ownerAimPosition()
    activeItem.setScriptedAnimationParameter("fatedChargeTime", self.stances.charged.duration)
    activeItem.setScriptedAnimationParameter("fatedChargeTimer", channelTime - self.stances.windup.duration)

    activeItem.setScriptedAnimationParameter("indicatorImageLocation", indicatorImageLocation)
    activeItem.setScriptedAnimationParameter("indicatorDestination", tpRay())
    activeItem.setScriptedAnimationParameter("indicatorBrightness", self.indicatorBrightness or 0.5)
    activeItem.setScriptedAnimationParameter("indicatorImage", self.indicatorImage)
    activeItem.setScriptedAnimationParameter("indicatorFacesRight", indicatorImageLocation[1] >= mcontroller.position()[1])
    
    local currentIndicatorThickness = (self.maxIndicatorLineThickness/(self.indicatorLineShrinkFactor*channelTime + 1)) + self.minIndicatorLineThickness
    activeItem.setScriptedAnimationParameter("currentIndicatorThickness", currentIndicatorThickness)

    if tpLock then
        if fullCharged then
          activeItem.setScriptedAnimationParameter("indicatorColor", self.indicatorColorCharged)
        else
          activeItem.setScriptedAnimationParameter("indicatorColor", self.indicatorColor)
        end
        activeItem.setCursor("/cursors/chargeready.cursor")
    else
        activeItem.setScriptedAnimationParameter("indicatorColor", self.indicatorColorBad)
        activeItem.setCursor("/cursors/chargeinvalid.cursor")
    end
  end

  -- generic stuff below, don't touch

  if self.cooldownTimer == 0 and not self.weapon.currentAbility and not status.resourceLocked("energy") and self.fireMode == "alt" then
    rebladeCost = config.getParameter("rebladeHealthCostRate", 0.1)
    if animator.animationState("handle") ~= "noblade" or status.resourcePercentage("health") > rebladeCost then
      if animator.animationState("handle") == "noblade" then
        status.modifyResourcePercentage("health", -1 * rebladeCost)
      end
      channelTime = 0
      self:setState(self.windup)
    end
  end
end

function FatedSlash:dodge()

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
  dodged = true
  if prevState then
    local nextState = prevState
    prevState = nil
    self:setState(nextState)
  else
    self:setState(self.init)
  end
end

local windupAudioPlaying = false
local chargedAudioPlayed = false
local channelAudioPlaying = false
local fullChargedAudioPlayed = false
local inChargedStance = false
local inFullChargedStance = false

function FatedSlash:windup()

  if not (charged or fullCharged) then
    self.weapon:setStance(self.stances.windup)
    self.weapon:updateAim()
  end

  animator.setAnimationState("bladeCharge", "charge")
  shineBlade()

  -- generic stuff above, don't touch

  if not windupAudioPlaying then
    animator.playSound("fatedSlashWindup", -1)
    windupAudioPlaying = true
  end

  while self.fireMode == "alt" and not status.resourceLocked("energy") do

    if canDodge then
      prevState = self.windup
      self:setState(self.dodge)
    end

    channelTime = channelTime + self.dt
    charged = channelTime > self.stances.windup.duration and not fullCharged
    fullCharged = channelTime > self.stances.windup.duration + self.stances.charged.duration
    showIndicator = charged or fullCharged

    if charged then
      animator.setGlobalTag("bladeDirectives", "border=".. self.chargedBorderThickness ..";"..self.chargedBorder..";00000000")

      if self.stances.charged and not inChargedStance then
        self.weapon:setStance(self.stances.charged)
        self.weapon:updateAim()
        inChargedStance = true
      end

      if not channelAudioPlaying then
        animator.playSound("fatedSlashChannel", -1)
        channelAudioPlaying = true
      end

    end

    if fullCharged then
      activateBlade()
      animator.setParticleEmitterActive("bladeCharge", true)
      animator.setGlobalTag("bladeDirectives", "border=".. self.fullChargedBorderThickness ..";"..self.fullChargedBorder..";00000000")
      if self.stances.fullcharged and not fullChargedStance then
        self.weapon:setStance(self.stances.fullcharged)
        self.weapon:updateAim()
        inFullChargedStance = true
      end
    end

    if channelTime > self.stances.windup.duration - self.chargeAudioOffset and not chargedAudioPlayed then
      animator.stopAllSounds("fatedSlashWindup")
      windupAudioPlaying = false
      animator.playSound("fatedSlashCharged")
      chargedAudioPlayed = true
    end
    

    if channelTime > self.stances.windup.duration + self.stances.charged.duration - self.fullChargeAudioOffset and not fullChargedAudioPlayed then
      animator.playSound("fatedSlashFullCharged")
      fullChargedAudioPlayed = true
    end

    status.overConsumeResource("energy", status.resourceMax("energy") * self.channelEnergyUsageRate * self.dt)

    coroutine.yield()

  end  

  animator.stopAllSounds("fatedSlashWindup")
  windupAudioPlaying = false

  animator.stopAllSounds("fatedSlashCharged")
  chargedAudioPlayed = false

  animator.stopAllSounds("fatedSlashChannel")
  channelAudioPlaying = false

  animator.stopAllSounds("fatedSlashFullCharged")
  fullChargedAudioPlayed = false

  inChargedStance = false
  inFullChargedStance = false

  local consumedEnergyRate = fullCharged and self.fullEnergyUsageRate or self.energyUsageRate

  if (charged or fullCharged) and status.overConsumeResource("energy", status.resourceMax("energy")*consumedEnergyRate) then
    self:setState(self.dash)
  end

end

function FatedSlash:dash()

  showIndicator = false

  animator.playSound(fullCharged and "fullFatedSlashDash" or "fatedSlashDash")

  status.addEphemeralEffect("invulnerable", 60)

  if tpLock then
    
    -- teleport to destination
    local oldPlayerPos = mcontroller.position()      

    status.addEphemeralEffect("project42invis", self.dashTravelTime + self.dt)
    util.wait(self.dt) -- add delay to let stat fx settle so we won't briefly appear at the destination
    mcontroller.setPosition(tpLock)
    if fullCharged then
      status.addEphemeralEffect("project42datsu")
    end
    local newPlayerPos = mcontroller.position()
    activeItem.setTwoHandedGrip(false)

    
    local translationMagnitude = world.magnitude(newPlayerPos, oldPlayerPos) 
    local projAim = vec2.norm(world.distance(newPlayerPos,oldPlayerPos))
    
    local projParams = {}
    
    -- calculate projectile speed and lifetime so that it dies right at the destination
    projParams.speed = translationMagnitude / self.dashTravelTime
    projParams.animationCycle = self.dashTravelTime
    projParams.timeToLive = self.dashTravelTime
    
    projParams.powerMultiplier = activeItem.ownerPowerMultiplier() * (fullCharged and self.fullChargeDamageFactor or 1)
    projParams.power = self:damageAmount()
    if config.getParameter("upgraded", false) then
      projParams.damageType = "IgnoresDef"
    end
    projParams.upgraded = config.getParameter("upgraded", false)
      
    local dashProjectile = world.spawnProjectile(
        self.dashProjectileType,
        oldPlayerPos,
        activeItem.ownerEntityId(),
        projAim,
        false,
        projParams
    )

    --debug_hits = 0
    activeItem.setCameraFocusEntity(dashProjectile)
    util.wait(self.dashTravelTime, function()
      mcontroller.setVelocity({0,0})
    end)
    --sb.logInfo("[PROJECT 42] Dash Projectile Hits: " .. debug_hits)

  else
    status.addEphemeralEffect("colorred", self.dashTravelTime)
  end
  
  status.removeEphemeralEffect("project42invis")

  self:setState(self.slash)
end

function FatedSlash:slash()

  animator.setAnimationState("handle", "bladed")
  animator.setAnimationState("blade", "active")

  local tpSuccess = false
  
  local swooshStateKey
  local stance
  
  if fullCharged then

    -- if fully charged, spawn slash projectile (multislash flurry default)
    -- upon arrival at destination
    -- and wait for it to leech health
    -- projectile lifetime is directly affected by duration of preslash

    local projAim = vec2.norm(mcontroller.position(), activeItem.ownerAimPosition())
    local projParams = self.slashProjectileParameters or {}
    projParams.activeTime = self.stances.fullfatedfire.duration
    projParams.timeToLive = self.stances.fullfatedfire.duration
    projParams.powerMultiplier = activeItem.ownerPowerMultiplier()
    local slashProjectile = world.spawnProjectile(
      self.slashProjectileType,
      mcontroller.position(),
      activeItem.ownerEntityId(),
      projAim,
      false,
      self.slashProjectileParameters
    )

    self.weapon:setStance(self.stances.fullfatedfire)
    self.weapon:updateAim()
    
    -- projectiles won't steal health unless damageListener is constantly updated during their lifetime. Too bad!
    --debug_hits = 0
    util.wait(self.stances.fullfatedfire.duration, function()
      if tpLock then
        mcontroller.setVelocity({0,0})
      end
    end)
    --sb.logInfo("[PROJECT 42] Full charged Projectile Hits: " .. debug_hits)

    if self.stances.fullfatedpreslash then
      self.weapon:setStance(self.stances.fullfatedpreslash)
      self.weapon:updateAim()
      util.wait(self.stances.fullfatedpreslash.duration)
    else
      util.wait(self.slashDelay or self.dt)
    end

    stance = self.stances.fullfatedslash
    swoosh = "fullfatedslash"
  else

    stance = self.stances.fatedslash
    swoosh = "fatedslash"
    if self.stances.fatedpreslash then
      self.weapon:setStance(self.stances.fatedpreslash)
      self.weapon:updateAim()
      util.wait(self.stances.fatedpreslash.duration or self.dt)
    else
      util.wait(self.slashDelay or self.dt)
    end

  end

  animator.setAnimationState("bladeCharge", "idle")
  animator.setParticleEmitterActive("bladeCharge", false)
  animator.setAnimationState("swoosh", swoosh)
  animator.playSound("fatedSlashSlash")

  self.damageConfig.baseDamageFactor = fullCharged and self.fullChargeDamageFactor or 1
  self.weapon:setStance(stance)
  self.weapon:updateAim()
  
  --debug_hits = 0
  util.wait(stance.duration, function()
    mcontroller.setVelocity({0, 0})
    local damageArea = partDamageArea("swoosh")
    self.weapon:setDamage(self.damageConfig, damageArea)
  end)
  --sb.logInfo("[PROJECT 42] Slash Hits: " .. debug_hits)

  if self.stances.postslash then
    self.weapon:setStance(self.stances.postslash)
    self.weapon:updateAim()
    util.wait(self.stances.postslash.duration)
  end

  if tpLock then
    offCooldownAudio = false
    self.cooldownTimer = self.cooldownTime
  end

  tpLock = nil
  channelTime = 0
  charged = false
  fullCharged = false

  status.removeEphemeralEffect("invulnerable")

  
end

function FatedSlash:reset()
  animator.setGlobalTag("bladeDirectives", "")
  animator.setParticleEmitterActive("bladeCharge", false)
  animator.setAnimationState("bladeCharge", "idle")
  activeItem.setCursor("/cursors/reticle0.cursor")
  status.removeEphemeralEffect("project42invis")
  status.removeEphemeralEffect("invulnerable")
  showIndicator = false
  charged = false
  fullCharged = false
  offCooldownAudio = false
  channelTime = 0
end

function FatedSlash:uninit()
  self:reset()
end

function FatedSlash:damageAmount()
  return status.resourceMax("energy")  * self.energyDamageScaling
end

-- teleport stuff --

function setTpLock()

  local checkCenterOffset = 0.2
  local currentPlayerPos = mcontroller.position()
  local playerCenterOffset = poly.center(playerCollisionPoly)
  local tpDestination = tpRay()
  
  world.debugLine(currentPlayerPos, tpDestination, "cyan")

  if not playerCollides(tpDestination) then
    tpLock = tpDestination
    return
  end

  local checkLineOffset = vec2.rotate({1, 0}, activeItem.aimAngle(0, activeItem.ownerAimPosition()))
  local checkAngle = vec2.angle(checkLineOffset)
  checkLineOffset = vec2.rotate({polarRectangle(checkAngle, poly.boundBox(playerCollisionPoly)), 0}, activeItem.aimAngle(0, activeItem.ownerAimPosition()))
  local checkLine = vec2.add(tpDestination, checkLineOffset)
  world.debugLine(tpDestination, checkLine, "yellow")

  local collisionPoint = world.lineCollision(tpDestination, checkLine, {"Block", "Dynamic"})
  if collisionPoint then
    local correctionOffset = vec2.sub(collisionPoint, checkLine)
    tpDestination = vec2.add(tpDestination, correctionOffset)
    if not playerCollides(tpDestination) then
      tpLock = tpDestination
      return
    end
  end

  local floorLine = vec2.add(tpDestination, {0, -2.5})
  local floor = world.lineCollision(vec2.add(tpDestination, {0, -checkCenterOffset}), floorLine, {"Block", "Dynamic"})
  local ceilingLine = vec2.add(tpDestination, {0, 1.22})
  local ceiling = world.lineCollision(vec2.add(tpDestination, {0, checkCenterOffset}), ceilingLine, {"Block", "Dynamic"})

  if floor and ceiling then
    --[[
    if vec2.eq(ceiling, vec2.add(tpDestination, {0, checkCenterOffset})) and vec2.eq(floor, vec2.add(tpDestination, {0, -checkCenterOffset})) then
      goto wall_resolve
    else
      tpLock = nil
      return
    end
    --]]
    goto wall_resolve
  end

  if floor and not ceiling then
    local correctionOffset = vec2.sub(floor, floorLine)
    tpDestination = vec2.add(tpDestination, correctionOffset)
    if not playerCollides(tpDestination) then
      tpLock = tpDestination
      return
    else
      goto wall_resolve
    end
  end

  if ceiling and not floor then
    local correctionOffset = vec2.sub(ceiling, ceilingLine)
    tpDestination = vec2.add(tpDestination, correctionOffset)
    if not playerCollides(tpDestination) then
      tpLock = tpDestination
      return
    else
      goto wall_resolve
    end
  end

  ::wall_resolve::

  local rightWallLine = vec2.add(tpDestination, {0.75, 0})
  local rightWall = world.lineCollision(vec2.add(tpDestination, {checkCenterOffset, 0}), rightWallLine, {"Block", "Dynamic"})
  local leftWallLine = vec2.add(tpDestination, {-0.75, 0})
  local leftWall = world.lineCollision(vec2.add(tpDestination, {-checkCenterOffset, 0}), leftWallLine, {"Block", "Dynamic"})

  if leftWall and rightWall then
    tpLock = nil
    return
  end

  if leftWall and not rightWall then
    local correctionOffset = vec2.sub(leftWall, leftWallLine)
    tpDestination = vec2.add(tpDestination, correctionOffset)
    if not playerCollides(tpDestination) then
      tpLock = tpDestination
      return
    else
      goto auto_resolve
    end
  end

  if rightWall and not leftWall then
    local correctionOffset = vec2.sub(rightWall, rightWallLine)
    tpDestination = vec2.add(tpDestination, correctionOffset)
    if not playerCollides(tpDestination) then
      tpLock = tpDestination
      return
    else
      goto auto_resolve
    end
  end
  
  ::auto_resolve::
    
  tpDestination = resolvePlayerCollision(tpDestination)
  if tpDestination then
    tpLock = tpDestination
    return
  end

  tpLock = nil

end

--[[

function movePlayerPoly(iPosition, xDirection, yDirection)
  local bb = poly.boundBox(mcontroller.baseParameters().standingPoly)
  local x = math.abs(bb[1])
  local v = {
    xDirection == "right" and x or -x,
    yDirection == "up"    and math.abs(bb[2]) or -math.abs(bb[4])
  }
  return vec2.add(iPosition, v)
end

-- direction is string indicating direction in lowercase i.e. "right", "up", "left", "down"
-- direction indicates direction of collision i.e. "right" means it's colliding with the right wall
function resolveDirection(collisionPoint, desiredLocation, direction, preserve)
  local translatedPlayerPoly = poly.translate(playerCollisionPoly, desiredLocation)
  local preserve = preserve or false
  local directionTable = {}
  directionTable["up"] = 1
  directionTable["right"] = 2
  directionTable["down"] = 3
  directionTable["left"] = 4
  local direction = directionTable[direction]

  local maxPolys = {
    translatedPlayerPoly[6],
    translatedPlayerPoly[5],
    translatedPlayerPoly[2],
    translatedPlayerPoly[1],
  }

  local offset = maxPolys[direction][(direction % 2) + 1] - collisionPoint[(direction % 2) + 1]
  local offsetVector = {0, 0}
  offsetVector[(direction % 2) + 1] = -1 * offset
  local newCollisionPos = vec2.add(desiredLocation, offsetVector)
  if not preserve then
    newCollisionPos = resolvePlayerCollision(newCollisionPos)
  end
  return newCollisionPos
end

--]]

function resolvePlayerCollision(location, threshold)
  local threshold = 1 or false
  if not playerCollides(location) then
    return location
  end
  local newLocation = world.resolvePolyCollision(playerCollisionPoly, location, threshold)
  if newLocation then
    if not notLineOfSight(newLocation) then
      return newLocation
    end
  end
  return nil
end

function playerCollides(location)
  return world.polyCollision(playerCollisionPoly, location, {"Block", "Dynamic"})
end

function tpRay(tpPos)
  local tpPos = tpPos or activeItem.ownerAimPosition()
  return notLineOfSight(tpPos) or tpPos
end

function notLineOfSight(location, threshold)
  local offsetLoc = location

  if threshold then
    local angle = vec2.angle(vec2.sub(location, mcontroller.position()))
    local thresholdVector = vec2.withAngle(angle, threshold)
    offsetLoc = vec2.add(location, thresholdVector)
  end
  
  --world.debugLine(mcontroller.position(), location, "yellow")

  return world.lineCollision(mcontroller.position(), offsetLoc, {"Block", "Dynamic"})
end

function reblade()
  if animator.animationState("handle") == "noblade" then
    animator.setAnimationState("handle", "reblade")
  end
end

function shineBlade()
  reblade()
  if animator.animationState("blade") ~= "sheen" and animator.animationState("blade") ~= "retractSheen" then
    if animator.animationState("blade") == "inactive" then
      animator.setAnimationState("blade", "sheen")
    else
      animator.setAnimationState("blade", "retractSheen")
    end
  end
end

function activateBlade()
  reblade()
  if animator.animationState("blade") ~= "active" and animator.animationState("blade") ~= "extend" then
    animator.setAnimationState("blade", "extend")
  end
end