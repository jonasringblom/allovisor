namespace("pose_eng", "alloverse")

local tablex = require "pl.tablex"
local pretty = require "pl.pretty"
local allomath = require "lib.allomath"
alloBasicShader = require "shader/alloBasicShader"
alloPointerRayShader = require "shader/alloPointerRayShader"
local HandRay = require "eng.pose_eng.hand_ray"


PoseEng = classNamed("PoseEng", Ent)

PoseEng.hands = {"hand/left", "hand/right"}
PoseEng.buttons = {"trigger", "thumbstick", "touchpad", "grip", "menu", "a", "b", "x", "y", "proximity"}

function PoseEng:_init()
  self.yaw = 0.0
  self.handRays = {HandRay(), HandRay()}
  self.isFocused = true
  self.mvp = lovr.math.newMat4()
  self.oldMousePos = lovr.math.newVec2()
  self.fakeMousePos = lovr.math.newVec2()
  self.mousePitch = 0
  self:super()
end

function PoseEng:onLoad()
  
end

function PoseEng:onUpdate(dt)
  self:updateButtons()

  if self.parent.active == false then return end
  if self.client == nil then return end
  
  if lovr.mouse then
    self:updateMouse()
  end
  self:updateIntent()
  for handIndex, hand in ipairs(PoseEng.hands) do
    self:updatePointing(hand, self.handRays[handIndex])
  end

  self:routeButtonEvents()
end

function PoseEng:onDraw()
  -- Gotta pick up the MVP at the time of drawing so it matches the transform applied in network scene
  lovr.graphics.getProjection(1, self.mvp)
  local view = lovr.math.mat4()
  lovr.graphics.getViewPose(1, view, false)
  self.mvp:mul(view)
  self.mvp:mul(self.parent.transform) -- todo use lovr.graphics.getTransform when it exists

  if self.parent.active then
    for _, ray in ipairs(self.handRays) do
      ray:draw()
    end
  end

  -- if lovr.mouse and self.mouseInWorld then
  --   lovr.graphics.setColor(1,0,0,0.5)
  --   lovr.graphics.sphere(self.mouseInWorld, 0.05)
  -- end
end

function PoseEng:onDebugDraw()
  lovr.graphics.push()
  lovr.graphics.origin()
  lovr.graphics.translate(1.5, 0, -3)
  
  lovr.graphics.setColor(1,1,1,0.3)
  lovr.graphics.setShader()
  lovr.graphics.plane("fill", 0, 0, 0, 1.6, 1.5)

  lovr.graphics.translate(-0.75, 0.70, 0.01)
  lovr.graphics.setColor(0,0,0,1.0)
  local pen = {
    x=0.0, y=0.0,
    print= function(self, s, moveX, moveY)
      lovr.graphics.print(s, self.x, self.y, 0, 0.05, 0,0,0,0,  0,"left")
      self.x = self.x + moveX
      self.y = self.y + moveY
    end
  }
  pen:print("device", 0.3, 0.0)
  pen:print("button", 0.3, 0.0)
  pen:print("dwn?", 0.18, 0.0)
  pen:print("touch?", 0.18, 0.0)
  pen:print("wasP?", 0.18, 0.0)
  pen:print("wasR?", 0.18, 0.0)
  pen:print("x", 0.18, 0.0)
  pen:print("y", 0.18, 0.0)
  pen.y = pen.y - 0.07
  pen.x = 0
  for _, hand in ipairs(PoseEng.hands) do
    pen:print(hand, 0.3, 0.0)
    for _, button in ipairs(PoseEng.buttons) do
      pen:print(button, 0.3, 0.0)
      pen:print(tostring(self:isDown(hand, button)), 0.18, 0.0)
      pen:print(tostring(self:isTouched(hand, button)), 0.18, 0.0)
      pen:print(tostring(self:wasPressed(hand, button)), 0.18, 0.0)
      pen:print(tostring(self:wasReleased(hand, button)), 0.18, 0.0)
      if button == "grip" or button == "trigger" or button == "thumbstick" or button == "touchpad" then
        local x, y = self:getAxis(hand, button)
        pen:print(tostring(x), 0.18, 0.0)
        pen:print(tostring(y), 0.18, 0.0)
      end
      pen.y = pen.y - 0.07
      pen.x = 0.3
    end
    pen.x = 0
  end

  lovr.graphics.pop()
end

function PoseEng:onFocus(focused)
  self.isFocused = focused
end

function PoseEng:getPose(device)
  local pose = lovr.math.mat4()
  if lovr.headset then
    pose = lovr.math.mat4(lovr.headset.getPose(device))
  else
    if device == "head" then
      pose:translate(0, 1.7, 0)
      pose:rotate(self.mousePitch, 1,0,0)
    elseif device == "hand/left" then
      pose:translate(-0.18, 1.45, -0.0)
      local ava = self.parent:getAvatar()
      if lovr.mouse and self.mouseInWorld and ava then
        local worldFromAvatar = ava.components.transform:getMatrix()
        local avatarFromWorld = lovr.math.mat4(worldFromAvatar):invert()
        local worldFromHand = worldFromAvatar:mul(pose)
        local from = worldFromHand:mul(lovr.math.vec3())
        local to = self.mouseInWorld
        worldFromHand:identity():lookAt(from, to):translate(0,0,-0.35)
        local avatarFromHand = avatarFromWorld * worldFromHand
        pose:set(avatarFromHand)
      else
        pose:rotate(-3.1416/2, 1,0,0):translate(0,0,-0.35)
      end
      -- todo: let this location override headset if not tracking too
    end
  end
  return pose
end

function PoseEng:_recalculateMouseInWorld(x, y, w, h)
  -- https://antongerdelan.net/opengl/raycasting.html
  -- https://github.com/bjornbytes/lovr/pull/237
  -- Unproject from world space
  local matrix = lovr.math.mat4(self.mvp):invert()
  local ndcX = -1 + x/w * 2 -- Normalized Device Coordinates
  local ndcY = 1 - y/h * 2 -- Note: Mouse coordinates have y+ down but OpenGL NDCs are y+ up
  local near = matrix:mul( lovr.math.vec3(ndcX, ndcY, 0) ) -- Where you clicked, touching the screen
  local far  = matrix:mul( lovr.math.vec3(ndcX, ndcY, 1) ) -- Where you clicked, touching the clip plane
  local ray = (far-near):normalize()

  -- point 3 meters into the world by default
  local mouseInWorld = near + ray*3

  -- see if we hit something closer than that, and if so move 3d mouse there
  local nearestHit = nil
  local nearestDistance = 10000
  self.parent.engines.physics.world:raycast(near.x, near.y, near.z, mouseInWorld.x, mouseInWorld.y, mouseInWorld.z, function(shape, hx, hy, hz)
    local newHit = shape:getCollider():getUserData()
    local newLocation = newHit.components.transform:getMatrix():mul(lovr.math.vec3(0,0,0))
    local newDistance = (newLocation - near):length()
    if newDistance < nearestDistance then
      nearestHit = newHit
      nearestDistance = newDistance
      mouseInWorld = lovr.math.vec3(hx, hy, hz)
    end
  end)
  
  self.mouseInWorld = mouseInWorld
  self.mouseTouchesEntity = nearestHit ~= nil
end

function PoseEng:updateMouse()
  -- figure out where in the world the mouse is...
  local x, y = lovr.mouse.position:unpack()
  local w, h = lovr.graphics.getWidth(), lovr.graphics.getHeight()
  local isOutOfBounds = x < 0 or y < 0 or x > w or y > h
  if self.isFocused == false or (self.mouseIsDown == false and isOutOfBounds) then
    self.mouseInWorld = nil
    --self.mouseMode = "move"
    self.mouseIsDown = false
    return
  end

  -- if (x ~= self.fakeMousePos.x) and self.fakeMousePos.x ~= 0 then
  --   print("===============================")
  --   print("x                     ", x)
  --   print("self.fakeMousePos.x   ", self.fakeMousePos.x)
  --   print("y                     ", y)
  --   print("self.fakeMousePos.y   ", self.fakeMousePos.y)
  --   print("self.mouseMode        ", self.mouseMode)
  --   print("self.mouseIsDown      ", self.mouseIsDown)
  -- end

  if self.mouseMode == "move" and self.mouseIsDown then
    -- make it look like cursor is fixed in place, since lovr-mouse fakes relative movement by hiding cursor
    self:_recalculateMouseInWorld(self.fakeMousePos.x, self.fakeMousePos.y, w, h)
  else
    self:_recalculateMouseInWorld(x, y, w, h)
  end

  -- okay great, we know where the mouse is.
  -- Now figure out what to do with mouse buttons.
  local mouseIsDown = lovr.mouse.buttons[1]

  -- started clicking/dragging; choose mousing mode
  if not self.mouseIsDown and mouseIsDown then
    if self.handRays[1].highlightedEntity then
      self.mouseMode = "interact"
    else
      self.mouseMode = "move"
      self.oldMousePos:set(x, y)
      self.fakeMousePos:set(x, y)
      lovr.mouse.setRelativeMode(true)
    end
  end
  self.mouseIsDown = mouseIsDown
  if self.mouseMode == "move" and not mouseIsDown then
    lovr.mouse.setRelativeMode(false)
  end

  if self.mouseIsDown and self.mouseMode == "move" then
    local newMousePos = lovr.math.vec2(x, y)
    local delta = lovr.math.vec2(newMousePos) - self.oldMousePos
    self.yaw = self.yaw + (delta.x/500)
    self.mousePitch = utils.clamp(self.mousePitch - (delta.y/500), -3.14/2, 3.14/2)
    self.oldMousePos:set(newMousePos)
  end
end


function PoseEng:updateIntent()
  if self.client.avatar_id == "" then return end

  -- root entity movement
  local mx, my = self:getAxis("hand/left", "thumbstick")
  local tx, ty = self:getAxis("hand/right", "thumbstick")

  -- It'd be nice if we could have some ownership model, where grabbing "took ownership" of the
  -- stick so this code wouldn't have to hard-code whether it's allowed to use the sticks or not.
  if self.handRays[1].heldEntity ~= nil then 
    mx = 0; my = 0;
  end
  if self.handRays[2].heldEntity ~= nil then
    tx = 0; ty = 0;
  end

  -- not allowed to walk around in the overlay menu
  if self.parent.isOverlayScene then
    mx = 0; my = 0; tx = 0; ty = 0
  end

  if math.abs(tx) > 0.5 and not self.didTurn then
    self.yaw = self.yaw + allomath.sign(tx) * math.pi/4
    self.didTurn = true
  end
  if math.abs(tx) < 0.5 and self.didTurn then
    self.didTurn = false
  end


  
  local intent = {
    entity_id = self.client.avatar_id,
    xmovement = mx,
    zmovement = -my,
    yaw = self.yaw,
    pitch = 0.0,
    poses = {}
  }

  -- child entity positioning
  for i, device in ipairs({"hand/left", "hand/right", "head"}) do
    intent.poses[device] = {
      matrix = {self:getPose(device):unpack(true)},
      skeleton = self:getSkeletonTable(device),
      grab = self:grabForDevice(i, device)
    }
  end
  
  self.client:setIntent(intent)
end

local requiredGripStrength = 0.4
function PoseEng:grabForDevice(handIndex, device)
  if device == "head" then return nil end
  local ray = self.handRays[handIndex]
  if ray.hand == nil then return nil end

  local gripStrength = self:getAxis(device, "grip")

  -- released grip button?
  if ray.heldEntity and gripStrength < requiredGripStrength then
    ray.heldEntity = nil

  -- started holding grip button while something is highlighted?
  elseif ray.heldEntity == nil and gripStrength > requiredGripStrength and ray.highlightedEntity then
    ray.heldEntity = ray.highlightedEntity

    local worldFromHand = ray.hand.components.transform:getMatrix()
    local handFromWorld = worldFromHand:invert()
    local worldFromHeld = ray.heldEntity.components.transform:getMatrix()
    local handFromHeld = handFromWorld * worldFromHeld

    ray.grabber_from_entity_transform:set(handFromHeld)
  end

  if ray.heldEntity == nil then
    return nil
  else
    -- Move things to/away from hand with stick
    local stickX, stickY = self:getAxis(device, "thumbstick")

    if math.abs(stickY) > 0.05 then
      local translation = lovr.math.mat4():translate(0,0,-stickY*0.1)
      local newOffset = translation * ray.grabber_from_entity_transform
      if newOffset:mul(lovr.math.vec3()).z < 0 then
        ray.grabber_from_entity_transform:set(newOffset)
      end
    end

    -- return thing to put in intent
    return {
      entity = ray.heldEntity.id,
      grabber_from_entity_transform = ray.grabber_from_entity_transform
    }
  end
end

function PoseEng:updatePointing(hand_pose, ray)
  -- Find the  hand whose parent is my avatar and whose pose is hand_pose
  -- todo: save this in HandRay
  local hand_id = tablex.find_if(self.client.state.entities, function(entity)
    return entity.components.relationships ~= nil and
           entity.components.relationships.parent == self.client.avatar_id and
           entity.components.intent ~= nil and
           entity.components.intent.actuate_pose == hand_pose
  end)

  if hand_id == nil then return end

  
  local hand = self.client.state.entities[hand_id]
  if hand == nil then return end
  ray.hand = hand

  local previouslyHighlighted = ray.highlightedEntity
  ray:highlightEntity(nil)

  local handPos = hand.components.transform:getMatrix():mul(lovr.math.vec3())
    --if position is nan, stop trying to raycast (as raycasting with nan will crash ODE)
  if handPos.x ~= handPos.x then
    return
  end

  ray.from = lovr.math.newVec3(handPos)
  ray.to = lovr.math.newVec3(hand.components.transform:getMatrix():mul(lovr.math.vec3(0,0,-10)))

  -- Raycast from the hand
  self.parent.engines.physics.world:raycast(handPos.x, handPos.y, handPos.z, ray.to.x, ray.to.y, ray.to.z, function(shape, hx, hy, hz)
    -- assuming first hit is nearest; skip all other hovered entities.
    if ray.highlightedEntity == nil then
      ray:highlightEntity(shape:getCollider():getUserData())
      ray.to = lovr.math.newVec3(hx, hy, hz)
    end
  end)

  if previouslyHighlighted and previouslyHighlighted ~= ray.highlightedEntity then
    self.client:sendInteraction({
      type = "one-way",
      receiver_entity_id = previouslyHighlighted.id,
      body = {"point-exit"}
    })
  end

  if ray.highlightedEntity then
    self.client:sendInteraction({
      type = "one-way",
      receiver_entity_id = ray.highlightedEntity.id,
      body = {"point", {ray.from.x, ray.from.y, ray.from.z}, {ray.to.x, ray.to.y, ray.to.z}}
    })

    if ray.selectedEntity == nil and self:isDown(hand_pose, "trigger") then
      ray:selectEntity(ray.highlightedEntity)
      self.client:sendInteraction({
        type = "request",
        receiver_entity_id = ray.selectedEntity.id,
        body = {"poke", true}
      })
    end
  end

  if ray.selectedEntity and not self:isDown(hand_pose, "trigger") then
    self.client:sendInteraction({
      type = "request",
      receiver_entity_id = ray.selectedEntity.id,
      body = {"poke", false}
    })
    ray:selectEntity(nil)
  end
end

require "eng.pose_eng.skeleton"
require "eng.pose_eng.buttons"

return PoseEng
