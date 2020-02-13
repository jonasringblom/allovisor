namespace("menu", "alloverse")

local MenuScene = require("app.menu.menu_scene")
local MenuItem = require("app.menu.menu_item")

local OverlayMenuScene = classNamed("OverlayMenuScene ", MenuScene)
function OverlayMenuScene :_init(networkScene)
  local overlayItems = {
    MenuItem("Dismiss", function() 
      queueDoom(self)
    end),
    MenuItem("Disconnect", function()
      networkScene:onDisconnect()
      queueDoom(self)
    end),
    MenuItem("Quit", function()
      lovr.event.quit(0)
    end),
  }

  self:super(overlayItems)

  self.drawBackground = false
end

return OverlayMenuScene