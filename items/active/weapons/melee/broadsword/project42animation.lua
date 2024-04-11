require "/scripts/vec2.lua"
function update()
  localAnimator.clearDrawables()
  localAnimator.clearLightSources()

  -- main animation stuff


  local playerPosition = animationConfig.animationParameter("playerPosition")
  local playerHandPosition = animationConfig.animationParameter("playerHandPosition")
  local playerAimPosition = animationConfig.animationParameter("playerAimPosition")
  local playerFacingDirection = animationConfig.animationParameter("playerFacingDirection")
  
  local heavyChargeTimer = animationConfig.animationParameter("heavyChargeTimer")
  local heavyChargeTime = animationConfig.animationParameter("heavyChargeTime")

  local comboCounter = animationConfig.animationParameter("comboCounter")
  local comboShake = animationConfig.animationParameter("comboShake")
  local comboTextColor = animationConfig.animationParameter("comboTextColor")


  if animationConfig.animationParameter("displayText") then

    local healthMissing = animationConfig.animationParameter("healthMissing")
    
    local textHealthThreshold = math.max(animationConfig.animationParameter("textHealthThreshold"), 0.01)
    
    local textShake = animationConfig.animationParameter("textShake")

    local textOffset = animationConfig.animationParameter("textOffset")
    textOffset[1] = textOffset[1] * playerFacingDirection
    
    local textIntensity = math.max((healthMissing-1)/textHealthThreshold + 1, 0)
    
    local textColor = animationConfig.animationParameter("textColor")
    textColor[4] = math.floor(255 * textIntensity)

    localAnimator.spawnParticle({
      type = "text",
      text= animationConfig.animationParameter("critChance"),
      color = textColor,
      size = math.max(0.75*textIntensity, 0.5),
      fullbright = true,
      flippable = false,
      layer = "front",
      variance = {
        position = {textShake*textIntensity, textShake*textIntensity}
      }
    }, vec2.add(textOffset, playerPosition))

    

    if comboCounter > 1 then
      localAnimator.spawnParticle({
        type = "text",
        text= "^shadow;" .. animationConfig.animationParameter("comboCounter") .. "x",
        color = comboTextColor,
        size = 1,
        fullbright = true,
        flippable = false,
        layer = "front",
        variance = {
          position = {comboShake, comboShake}
        }
      }, vec2.add({-2.25 * playerFacingDirection, 1}, playerPosition))
    end

  end
  
  if heavyChargeTimer > 0 then
    local chargeProgress = heavyChargeTimer / heavyChargeTime

    local scale = math.max(-chargeProgress^3 + 1, 0)
    local fade = string.format("%2x", math.floor(math.min(chargeProgress^3, 1) * 255))
    local red = string.format("%2x", math.floor(scale * 255))
    local heavyChargeEffectPos = vec2.add(playerPosition, playerHandPosition)

    localAnimator.addDrawable({
      image = "/items/active/weapons/melee/broadsword/project42swoosh/charge.png?scale="..scale.."?multiply=ff"..red..red..fade,
      position = heavyChargeEffectPos,
      color = {255,255,255},
      fullbright = false,
    }, "Player+1")
    
  end

  local showIndicator = animationConfig.animationParameter("showIndicator")
  
  if showIndicator then

    local fatedChargeTime = animationConfig.animationParameter("fatedChargeTime")
    local fatedChargeTimer = animationConfig.animationParameter("fatedChargeTimer")

    local indicatorBrightness = animationConfig.animationParameter("indicatorBrightness")
    local indicatorImage = animationConfig.animationParameter("indicatorImage")
    local indicatorColor = animationConfig.animationParameter("indicatorColor")
    local indicatorFacesRight = animationConfig.animationParameter("indicatorFacesRight")
    local indicatorImageLocation = animationConfig.animationParameter("indicatorImageLocation")
    local indicatorDestination = animationConfig.animationParameter("indicatorDestination") or indicatorImageLocation
    local indicatorPortraitId = animationConfig.animationParameter("indicatorPortraitId")
    local currentIndicatorThickness = animationConfig.animationParameter("currentIndicatorThickness")

    local indicatorLightColor = {
      indicatorColor[1]*indicatorBrightness,
      indicatorColor[2]*indicatorBrightness,
      indicatorColor[3]*indicatorBrightness
    }

    localAnimator.addLightSource({
      position = indicatorImageLocation,
      color = indicatorLightColor
    })

    indicatorLine = worldify(playerPosition, indicatorDestination)

    --sb.logInfo("[PROJECT 42] Drawn Line: " .. sb.printJson(daLine))
    localAnimator.addDrawable({
      line = indicatorLine,
      width = currentIndicatorThickness,
      fullbright = true,
      color = indicatorColor
    }, "Player-1")

    localAnimator.addDrawable({
      image = "/items/active/weapons/melee/abilities/broadsword/fatedslash/block_circle.png",
      position = indicatorDestination,
      color = indicatorColor,
      fullbright = true,
    }, "Player+2")
    
    localAnimator.addDrawable({
      image = indicatorImage,
      position = indicatorImageLocation,
      color = indicatorColor,
      fullbright = true,
      mirrored = not indicatorFacesRight
    }, "Player+3")

    local fatedChargeProgress = fatedChargeTimer / fatedChargeTime
    local ringScale = math.max(-fatedChargeProgress^3 + 1, 0)
    local ringFade = string.format("%2x", math.floor(math.min(fatedChargeProgress^3, 1) * 255))


    localAnimator.addDrawable({
      image = "/items/active/weapons/melee/abilities/broadsword/fatedslash/ring.png?scalenearest="..ringScale.."?multiply=ffffff"..ringFade,
      position = indicatorImageLocation,
      color = indicatorColor,
      fullbright = true
    }, "Player+1")
        
  end
end

function worldify(alfa, beta)
  local a = alfa
  local b = beta
  local xmax = world.size()[1]
  local dispvec = vec2.sub(b, a)
  if a[1] > xmax/2 then 
    a[1] = -1 * (xmax - a[1])
  end
  b = vec2.add(a, dispvec)
  return {a, b}
end
