--- The Allovisor Sound engine
-- @classmod SoundEng

namespace("networkscene", "alloverse")

local pretty = require "pl.pretty"

local SoundEng = classNamed("SoundEng", Ent)

function SoundEng.supported()
  return lovr.audio ~= nil and (lovr.headset == nil or (lovr.headset.getName() ~= "Pico"))
end

function SoundEng:_init()
  self.audio = {}
  self.track_id = 0
  
  self:super()
end

function SoundEng:useMic(micName)
  if self.currentMicName == micName then return end
  self.currentMicName = micName

  if self.mic then
    self.mic:stopRecording()
    self.mic = nil
  end
  if micName == "Mute" then
    self.mic = nil
    print("SoundEng: Muted microphone")
    return true
  end

  self.mic = self:_attemptOpenMicrophone(micName)
  if self.mic then
    self.mic:startRecording()
    return true
  else
    return false
  end
end

function SoundEng:_attemptOpenMicrophone(micName)
  local sampleFmts = {48000}
  local bufferSizes = {960*3, 16384, 1024*4}
  local channelss = {1}
  local bitDepths = {16}
  for _, sampleFmt in ipairs(sampleFmts) do
    for _, bufferSize in ipairs(bufferSizes) do
      for _, bitDepth in ipairs(bitDepths) do
        for _, channels in ipairs(channelss) do
          local ok, mic = pcall(lovr.audio.newMicrophone, micName, bufferSize, sampleFmt, bitDepth, channels)
          if ok == true and mic ~= nil then
            print("SoundEng: Opened microphone '", micName, "' at ", sampleFmt, "hz, ", channels, "channels,", bitDepth, "bits and ", bufferSize, "bytes per packet")
            return mic
          else
            print("SoundEng: Incompatible microphone: ", driver, sampleFmt, bufferSize, bitDepth, channels, ":", mic)
          end
        end
      end
    end
  end
  print("SoundEng: No compatible microphones found in", pretty.write(drivers), ":(")
  return nil
end

function SoundEng:onLoad()
  self.client.delegates.onAudio = function(track_id, audio)
    self:onAudio(track_id, audio) 
  end
end

function SoundEng:onAudio(track_id, samples)
  if type(track_id) == "table" then 
    print("Here's broken track ID: ", pretty.write(track_id))
  end
  local audio = self.audio[track_id]
  if audio == nil then
    local stream = lovr.data.newAudioStream(1, 48000)
    audio = {
      stream = stream,
      source = lovr.audio.newSource(stream, "stream"),
      bitrate = 0.0
    }
    self.audio[track_id] = audio
    audio.source:setFalloff(1.0, 10.0, 1.6)
    audio.source:setVolumeLimits(0.0, 1.0)
  end

  local blobLength = #samples
  local now = lovr.timer.getTime()
  local previousAudioTime = audio.lastReceivedTime
  audio.lastReceivedTime = now
  if previousAudioTime and previousAudioTime > 0 then
    local delta = now - previousAudioTime
    local currentBitRate = blobLength / delta
    audio.bitrate = audio.bitrate * 0.90 + currentBitRate * 0.10
  end
  audio.ping = true

  local blob = lovr.data.newBlob(samples, "audio for track #"..track_id)
  audio.stream:append(blob)
  if audio.source:isPlaying() == false and audio.stream:getDuration() >= 0.2 then
    print("Starting playback audio in track "..track_id)
    audio.source:play()
  end
end

-- set position of audio for each entity that has a track_id assigned
function SoundEng:setAudioPositionForEntitiy(entity)
  local media = entity.components.live_media 

  if media == nil then return end

  local track_id = media.track_id
  local track = self.audio[track_id]

  if track == nil then return end 

  local matrix = entity.components.transform:getMatrix()

  local x, y, z, sx, sy, sz, a, ax, ay, az = matrix:unpack()
  track.source:setPose(x, y, z, a, ax, ay, az)
end

function SoundEng:onHeadAdded(head)
  self.head = head
  if self.track_id ~= 0 then return end
  if self.track_allocation_request_id ~= nil then return end

  print("Requesting track for mic")
  self.track_allocation_request_id = self.client:sendInteraction({
    type = "request",
    sender_entity_id = self.parent.head_id,
    receiver_entity_id = "place",
    body = {"allocate_track", "audio", 48000, 1, "opus"}
  }, function (response, body) 
    if body[2] == "ok" then
      self.track_id = body[3]
      print("Our head was allocated track ", self.track_id)
    else
      print("Failed to allocate track:", pretty.write(body))
    end
  end)
end

function SoundEng:onDebugDraw()
  for track_id, audio in pairs(self.audio) do
    local x, y, z = audio.source:getPosition()
    lovr.graphics.setShader(self.parent.engines.graphics.plainShader)
    if audio.source:isPlaying() then
      lovr.graphics.setColor(0.0, 1.0, audio.ping and 1.0 or 0.2, 0.5)
    else
      lovr.graphics.setColor(1.0, 0.0, audio.ping and 1.0 or 0.2, 0.5)
    end
    audio.ping = false
    lovr.graphics.sphere(
      x, y, z,
      0.1,
      0, 0, 1, 0 -- rot
    )

    lovr.graphics.setShader()
    lovr.graphics.setColor(0.0, 0.0, 0.0, 1.0)
    local s = string.format("Track #%d\n%.2fkBps", track_id, audio.bitrate/1024.0)
    lovr.graphics.print(s, 
      x, y+0.15, z,
      0.07, --  scale
      0, 0, 1, 0,
      0, -- wrap
      "left"
    )
  end
end

function SoundEng:onUpdate(dt)
  if self.client == nil then return end

  if self.mic ~= nil and self.mic:getSampleCount() >= 960 then
    local sd = lovr.data.newSoundData(16384, 48000, 16, 1)
    sd = self.mic:getData(960, sd, 0)
    if self.track_id then
      self.client:sendAudio(self.track_id, sd:getBlob():getString():sub(1, 960*2+1))
    end
  end

  for _, entity in pairs(self.client.state.entities) do
    self:setAudioPositionForEntitiy(entity)
  end
  if self.head then
    local matrix = self.head.components.transform:getMatrix()
    local x, y, z, sx, sy, sz, a, ax, ay, az = matrix:unpack()
    lovr.audio.setPose(x, y, z, a, ax, ay, az)
  end
end

function SoundEng:onComponentRemoved(component_key, component)
  if component_key ~= "live_media" then
    return
  end
  
  local audio = self.audio[component.track_id]
  print("Removing incoming audio channel ", component.track_id)

  if audio == nil then return end

  audio.source:stop()
  self.audio[component.track_id] = nil
end

function SoundEng:onDisconnect()
  if self.mic ~= nil then
    self.mic:stopRecording()
  end

  lovr.audio.stop()
end

return SoundEng
