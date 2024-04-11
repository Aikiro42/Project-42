function update(dt)

  if mcontroller.xVelocity() > 0 then
    projectile.processAction(
      {
        action="particle",
        specification="project42slashdash",
      }
    )
  else
    projectile.processAction(
      {
        action="particle",
        specification="project42slashdashleft",
      }
    )
  end
  
end

function hit(entityId)
  if projectile.getParameter("upgraded", false) then
    projectile.processAction(
      {
        action= "config",
        file = "/projectiles/explosions/project42_dashexplosion/project42_dashexplosion.config"
      }
    )
  end
end