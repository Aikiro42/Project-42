
require "/scripts/util.lua"
require "/scripts/vec2.lua"

function getSlashMoveVector(normDirectionVector, slashCarry, slashCarryFactor, slashMomentum)

    local dashVector = normDirectionVector
    local finalSlashCarry = slashCarry
  
    if canSlashLaunch then
      finalSlashCarry = finalSlashCarry * slashCarryFactor
    end
  
    dashVector = vec2.mul(dashVector, finalSlashCarry)
    dashVector = vec2.mul(dashVector, slashMomentum)
  
    if isOnGround then
      dashVector[2] = math.max(dashVector[2], 0)
    end
  
    return dashVector
  
end

function isIn2dTable(table2d, index, search)
    for _, x in ipairs(table2d) do
        if x[index] == search then
            return true
        end
        coroutine.yield()
    end
    return false
end

function computeAngularVelocity(finalAngle, initialAngle, time)
    return (finalAngle - initialAngle) / time
end

function debugPrint(x)
    sb.logInfo("[PROJECT 42] " .. x)
end

function xor(a, b)
    return (a or b) and (not (a and b))
end

function xnor(a, b)
    return (a and b) or ((not a) and (not b))
end

function polarRectangle(theta, boundBox)
    local a, b
    if theta >= math.pi then
        a = math.abs(boundBox[1])
        b = math.abs(boundBox[2])
    else
        a = math.abs(boundBox[3])
        b = math.abs(boundBox[4])
    end

    local ratio = b/a
    if math.abs(math.tan(theta)) <= ratio then
        return a/math.abs(math.cos(theta))
    else
        return b/math.abs(math.sin(theta))
    end
end