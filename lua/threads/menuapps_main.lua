print("Booting allomenu apps")

lovr = require 'lovr'
lovr.filesystem, lovr.thread = require 'lovr.filesystem', require 'lovr.thread'
local util = require "lib.util"
local allonet = util.load_allonet()
local running = true
local chan = lovr.thread.getChannel("appserv")
local port = chan:pop(true)
print("Connecting apps to port", port)
local apps = {
   require("alloapps.menu.app")(port),
   require("alloapps.avatar_chooser")(port),
   require("alloapps.app_chooser")(port)
}

print("allomenu apps started")
local _, read = chan:push("booted", 2.0)
if not read then error("hey you gotta pop booted") end
while running do
  for _, app in ipairs(apps) do
    app:update()
  end
  local m = chan:pop()
  if m == "exit" then running = false end
end

print("Allomenu apps ending")