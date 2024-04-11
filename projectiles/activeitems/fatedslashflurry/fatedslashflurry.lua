local dmgListener
function init()
    spawnSound = config.getParameter("spawnSound")
    projectile.processAction({action="sound", options={spawnSound}}) 
end

function update(dt)
    
end