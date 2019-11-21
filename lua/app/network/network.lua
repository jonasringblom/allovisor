namespace("networkscene", "alloverse")

local json = require "json"

local NetworkScene = classNamed("NetworkScene", Ent)

--  If ran from lovr.app/lodr/testapp, liballonet.so is in project root

local success, allonet = pcall(require, "liballonet")
if success == false then
  print("No liballonet, trying in lovr binary as if we're on a Mac...")
  local pkg = package.loadlib("lovr", "luaopen_liballonet")
  if pkg == nil then
    print("No allonet in lovr, trying in liblovr.so as if we're on Android...")
    pkg = package.loadlib("liblovr.so", "luaopen_liballonet")

	if pkg == nil then
	  print("No liblovr.so, trying in allonet.dll as if we're on Windows...")
	  pkg = package.loadlib("allonet.dll", "luaopen_liballonet")
	end
  end
  if pkg == nil then
    error("Allonet missing. Giving up.")
  end
  allonet = pkg()
  print("allonet loaded")
end


function NetworkScene:_init(displayName, url)
  self.client = allonet.connect(
    url,
    json.encode({display_name = displayName}),
    json.encode({
      children = {
        {
          geometry = {
            type = "hardcoded-model",
            name = "lefthand"
          },
          intent = {
            actuate_pose = "hand/left"
          }
        },
        {
          geometry = {
            type = "hardcoded-model",
            name = "righthand"
          },
          intent = {
            actuate_pose = "hand/right"
          }
        },
        {
          geometry = {
            type = "hardcoded-model",
            name = "head"
          },
          intent = {
            actuate_pose = "head"
          }
        }
      }
    })
  )
  self.client:set_disconnected_callback(self.onDisconnect)
  self.yaw = 0.0
  
  self:super()
end

function NetworkScene:onLoad()
  --world = lovr.physics.newWorld()
  self.helmet = lovr.graphics.newModel('assets/models/mask.glb')
  self.lefthand = lovr.graphics.newModel('assets/models/left-hand/LeftHand.gltf', 'assets/models/test-texture.png')
  self.righthand = lovr.graphics.newModel('assets/models/right-hand/RightHand.gltf', 'assets/models/test-texture.png')

  self.shader = lovr.graphics.newShader('standard', {
    flags = {
      normalTexture = false,
      indirectLighting = true,
      occlusion = true,
      emissive = true,
      skipTonemap = false
    }
  })

  self.skybox = lovr.graphics.newTexture({
    left = 'assets/env/nx.png',
    right = 'assets/env/px.png',
    top = 'assets/env/py.png',
    bottom = 'assets/env/ny.png',
    back = 'assets/env/pz.png',
    front = 'assets/env/nz.png'
  }, { linear = true })

  self.environmentMap = lovr.graphics.newTexture(256, 256, { type = 'cube' })
  for mipmap = 1, self.environmentMap:getMipmapCount() do
    for face, dir in ipairs({ 'px', 'nx', 'py', 'ny', 'pz', 'nz' }) do
      local filename = ('assets/env/m%d_%s.png'):format(mipmap - 1, dir)
      local image = lovr.data.newTextureData(filename, false)
      self.environmentMap:replacePixels(image, 0, 0, face, mipmap)
    end
  end


  self.shader:send('lovrLightDirection', { -1, -1, -1 })
  self.shader:send('lovrLightColor', { .9, .9, .8, 1.0 })
  self.shader:send('lovrExposure', 2)
  --self.shader:send('lovrSphericalHarmonics', require('assets/env/sphericalHarmonics'))
  self.shader:send('lovrEnvironmentMap', self.environmentMap)
end

function NetworkScene:onDisconnect()
  print("disconnecting...")
  self.client:disconnect(0)
  scene:insert(lovr.scenes.menu)
  queueDoom(self)
end

function NetworkScene:onDraw()  
  lovr.graphics.skybox(self.skybox)
  
  lovr.graphics.setBackgroundColor(.3, .3, .40)
  lovr.graphics.setCullingEnabled(true)
  lovr.graphics.setBlendMode()
  lovr.graphics.setColor({1,1,1})
  lovr.graphics.setShader(self.shader)


  -- iterera igenom client.get_state().entities
  -- rita ut varje entity som en kub

  for _, entity in ipairs(self.client:get_state().entities) do

    local trans = entity.components.transform
    local geom = entity.components.geometry

    if trans ~= nil and geom ~= nil then

      if geom.type == "hardcoded-model" then

        if geom.name == "head" then   
            self.helmet:draw(
              trans.position.x, trans.position.y, trans.position.z, 
              0.35, 
              euler2axisangle(trans.rotation.x, trans.rotation.y, trans.rotation.z)
          )
        end

        if geom.name == "lefthand" then
          self.lefthand:draw(
            trans.position.x, trans.position.y, trans.position.z, 
            1, 
            euler2axisangle(trans.rotation.x, trans.rotation.y, trans.rotation.z)
          )
        end
        
        if geom.name == "righthand" then
          self.righthand:draw(
            trans.position.x, trans.position.y, trans.position.z, 
            1, 
            euler2axisangle(trans.rotation.x, trans.rotation.y, trans.rotation.z)
          )
        end
    
      elseif geom.type == "inline" then
          
      end
    end
  end

end

function axisangle2euler(angle, x, y, z)
  local s = math.sin(angle)
  local c = math.cos(angle)
  local t = 1-c
  local roll, yaw, pitch

  if ((x*y*t + z*s) > 0.998) then -- north pole singularity detected lul
    roll = 2*math.atan2(x*math.sin(angle/2), math.cos(angle/2))
		yaw = math.pi/2
		pitch = 0
  elseif ((x*y*t + z*s) < -0.998) then -- south pole singularity detected
    roll = -2*math.atan2(x*math.sin(angle/2), math.cos(angle/2))
    yaw = -math.pi/2
    pitch = 0
  else
    roll = math.atan2(y*s-x*z*t, 1-(y*y+z*z)*t)
    yaw = math.asin(x*y*t+z*s)
    pitch = math.atan2(x*s-y*z*t, 1-(x*x+z*z)*t)
  end
  return yaw, pitch, roll
end


-- https://www.euclideanspace.com/maths/geometry/rotations/conversions/eulerToAngle/
function euler2axisangle(pitch, yaw, roll)
	local c1 = math.cos(yaw/2)
	local s1 = math.sin(yaw/2)
	local c2 = math.cos(pitch/2)
	local s2 = math.sin(pitch/2)
	local c3 = math.cos(roll/2)
	local s3 = math.sin(roll/2)
	local c1c2 = c1*c2
	local s1s2 = s1*s2
	w =c1c2*c3 - s1s2*s3
	x =c1c2*s3 + s1s2*c3
	y =s1*c2*c3 + c1*s2*s3
	z =c1*s2*c3 - s1*c2*s3
	local angle = 2 * math.acos(w)
	local norm = x*x+y*y+z*z
  if norm < 0.001 then 
    -- when all euler angles are zero angle =0 so
		-- we can set axis to anything to avoid divide by zero
		x=1
    y=0
    z=0
	else
		norm = math.sqrt(norm)
    x = x / norm;
    y = y / norm;
    z = z / norm;
  end
  return angle, x, y, z
end

function pos2vec(x, y, z)

  if (x==nil or y==nil or z==nil) then
    error("x, y and/or z is nil");
  end

  return {x = x, y = y, z = z}
end

function NetworkScene:onUpdate(dt)
  local mx, my = lovr.headset.getAxis("hand/left", "thumbstick")
  local tx, ty = lovr.headset.getAxis("hand/right", "thumbstick")
  self.yaw = self.yaw - (tx/30.0)
  local intent = {
    xmovement = mx,
    zmovement = -my,
    yaw = self.yaw,
    pitch = 0.0,
    poses = {}
  }
  for i, device in ipairs({"head", "hand/left", "hand/right"}) do
    intent.poses[device] = {
      position = pos2vec(lovr.headset.getPosition(device)),
      rotation = pos2vec(axisangle2euler(lovr.headset.getOrientation(device)))
    }
  end
  print("Intent: " .. json.encode(intent))
  self.client:set_intent(intent)
  self.client:poll()
end

lovr.scenes.network = NetworkScene

return NetworkScene