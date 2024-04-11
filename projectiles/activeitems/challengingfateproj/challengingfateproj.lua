function hit(entityId)
    if projectile.getParameter("upgraded", false) then
      projectile.processAction(
        {
          action= "config",
          file = "/projectiles/explosions/project42_hitexplosion/project42_hitexplosion.config"
        }
      )
    end
  end