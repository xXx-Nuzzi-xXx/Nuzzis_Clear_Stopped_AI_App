-- Author - Nuzzi

-- USER VARS START
local allowLowerCspVersions = false  -- Set this to true to make minimum CSP version allowed CSP 0.2.0.  (Warning likely to experience bugs!)
-- USER VARS END

-- Global Vars
local driverCount = 0
local aiDriversStationaryTime = {}
local hasDriverBeenSentToPits = {}
local sessionState = "Initial Setup"
local TimeStationaryToCauseRetirement = 10
local RaceStartTimer = 0

-- Runs once on session restart
ac.onSessionStart(function(sessionIndex, restarted)
  -- Check CSP version is supported
  if CheckCspVersion() then
    ac.log("---------------------")
    ac.log("Session Restarted")
    ac.log("---------------------")
    sessionState = "Initial Setup"
  end
end)

-- Runs once per frame
---@diagnostic disable-next-line: duplicate-set-field
function script.update(dt)
  -- Check session is offline
  if ac.getSim().isOnlineRace == false then
    -- Check CSP version is supported
    if CheckCspVersion() then
      -- Check physics is allowed
      if physics.allowed() == true then
        -- Check not in replay mode
        if ac.getSim().isReplayActive == false then
          -- Runs once at session start & restart
          if sessionState == "Initial Setup" then
            driverCount = ac.getSim().carsCount - 1
            SetupAiDriverStoppedTimeArray()
            ResetCarsRetiredOnRaceStart()
            RaceStartTimer = 0
            sessionState = "Waiting on Race Start"
            ac.log("Session Setup Complete, waiting on Race Start")
          end
          -- Run Once Each Frame
          if sessionState == "Waiting on Race Start" then
            CheckForRaceStart()
          end
          if sessionState == "Race Started" then
            HandleAnyCarsStoppedAtRaceStart()
            CheckAllAiForStopped(dt)
            ResetStationaryTimerIfGotGoingAgain()
            KeepCarsSentToPitsStoppedInBox()
          end
        else
          ac.log("App in-active whilst in replay mode.")
        end
      else
        ac.log("App in-active, physics not enabled for track.")
      end
    end
  else
    ac.log("App in-active, current session is online")
  end
end

-- Runs once per frame on the Main window
---@diagnostic disable-next-line: duplicate-set-field
function script.windowMain(dt)
  -- Check session is offline
  if ac.getSim().isOnlineRace == false then
    -- Check CSP version is supported
    if CheckCspVersion() then
      -- Check physics is enabled
      if physics.allowed() == false then
        -- Button to enable physics here.
        if ui.button("Enable Track Physics") then
          EnablePhysics()
          ui.toast(ui.Icons.Code, "Track Physics Enabled, restart from C.M to apply.")
        end
        ui.newLine(3)
        ui.text("Track layout physics must be enabled for this app to work.")
      else
        -- Button to disable track physics
        if ui.button("Reset track physics for playing online") then
          DisablePhysics()
          ui.toast(ui.Icons.Code, "Track Physics Disabled, restart from C.M to apply.")
        end
        -- Driver Live Info
        for i = 1, ac.getSim().carsCount - 1, 1
        do
          ui.text("Session Info:")
          ui.text("Current Session Type: " .. ac.getSessionName(ac.getSim().currentSessionIndex))
          ui.text("Session State: " .. sessionState)
          ui.text("--------------------------")
          ui.text(ac.getDriverName(i) .. "")
          ui.text("Current Lap: " .. ac.getCar(i).lapCount + 1)
          ui.text("Time Stopped on track: " .. math.round(aiDriversStationaryTime[i], 1))
          if hasDriverBeenSentToPits[i] == nil then
            ui.text("Has Driver retired & been sent to pits? False")
          else
            ui.text("Has Driver retired & been sent to pits? " .. tostring(hasDriverBeenSentToPits[i]))
          end
        end
      end
    else
      ui.text("CSP too low. (Check Lua Debug App in-game for more info.)")
    end
  else
    ui.text("App only active in offline sessions.")
  end
end

-- FUNCTIONS
function SetupAiDriverStoppedTimeArray()
  -- Loop through ai drivers
  for i = 1, driverCount, 1
  do
    aiDriversStationaryTime[i] = 0
  end
end

function CheckForRaceStart()
  if ac.getSim().isSessionStarted == true then
    sessionState = "Race Started"
    ac.log("Race Started")
  end
end

function CheckAllAiForStopped(dt)
  -- Loop through ai drivers
  for i = 1, driverCount, 1
  do
    -- Count stationary time when out on track and stopped.
    if ac.getCar(i).speedKmh < 5 and ac.getCar(i).isInPitlane == false and ac.getCar(i).isInPit == false then
      aiDriversStationaryTime[i] = aiDriversStationaryTime[i] + dt
    end

    -- Send back to pits when stopped on track too long.
    if aiDriversStationaryTime[i] > TimeStationaryToCauseRetirement and ac.getCar(i).isInPit == false and ac.getCar(i).isInPitlane == false  then
      SendBackToPits(i)
    end
  end
end

function SendBackToPits(i)
  physics.teleportCarTo(i, ac.SpawnSet.Pits)
  hasDriverBeenSentToPits[i] = true
  aiDriversStationaryTime[i] = 0
  ac.log(ac.getDriverName(i) .. " was stopped & has been retired to pits")
end

function ResetStationaryTimerIfGotGoingAgain()
  for i = 1, driverCount, 1
  do
    if ac.getCar(i).speedKmh > 50 then
      aiDriversStationaryTime[i] = 0
    end
  end
end

function ResetCarsRetiredOnRaceStart()
  for i = 1, driverCount, 1
  do
    if hasDriverBeenSentToPits[i] == true then
      hasDriverBeenSentToPits[i] = false
      ac.setDriverVisible(i, true)
      physics.setAIThrottleLimit(i, 1)
      ac.log(ac.getDriverName(i) .. " reset to normal as retired")
      -- Still won't pull away with the rest of the grid but that is a CSP issue.
    end
  end
end

function KeepCarsSentToPitsStoppedInBox()
  for i = 1, driverCount, 1
  do
    -- if not Quick Race or Race then allow rejoin
    if ac.getSessionName(ac.getSim().currentSessionIndex) == "Quick Race" or ac.getSessionName(ac.getSim().currentSessionIndex) == "Race" then
      if hasDriverBeenSentToPits[i] == true and ac.getCar(i).isInPitlane == true or ac.getCar(i).isInPit == true then
        physics.overrideSteering(i, 0)
        physics.setAIThrottleLimit(i, 0)
        physics.teleportCarTo(i, ac.SpawnSet.Pits)
        physics.resetCarState(i, 0.5)
        ac.setDriverVisible(i, false)
      end
    end
  end
end

function HandleAnyCarsStoppedAtRaceStart()
  for i = 1, driverCount, 1
  do
    -- Only start counting timer on race start
    if ac.getSim().isSessionStarted == true then
      RaceStartTimer = math.round((-1 * ac.getSim().timeToSessionStart) / 1000, 1)
      --ac.log("Race Timer = " .. RaceStartTimer)
      -- Check for a couple seconds at race start
      if RaceStartTimer >= 1 and RaceStartTimer <= 2 then
        --ac.log("Checking for race start stalled car")
        -- Check if driver is not in pitbox or pitlane
        if ac.getCar(i).isInPit == false or ac.getCar(i).isInPitlane == false then
          -- Check if driver is not pressing the throttle
          if ac.getCar(i).gas < 0.1 then
            -- Send to pits
            ac.log(ac.getDriverName(i) .. " stuck at race start, sent to pits")
            SendBackToPits(i)
          end
        end
      end
    end
  end
end

function CheckCspVersion()
  if allowLowerCspVersions == true then
    if ac.getPatchVersionCode() >= 2651 then -- 2651 == CSP 0.2.0
      return true
    else
      ac.log("ERROR: CSP too low. Minimum CSP 0.2.0 when allowing lower versions.")
      return false
    end
  else
    if ac.getPatchVersionCode() >= 3044 then -- 3044 == CSP 0.2.3  (Preview versions min CSP 0.2.4 - preview)
      return true
    else
      ac.log("ERROR: CSP too low. Minimum free version is CSP 0.2.3.  Minimum preview version is CSP 0.2.4 - Preview.")
      return false
    end
  end
end

function EnablePhysics()
  local trackFolderPath = ac.getFolder(tostring(ac.FolderID.ContentTracks)) .. "\\" .. ac.getTrackID()
  local surfacesFilePath = trackFolderPath .. "\\" .. ac.getTrackLayout() .. "\\data\\surfaces.ini"
  local surfacesIni = ac.INIConfig.load(surfacesFilePath, ac.INIFormat.Default)
  surfacesIni:setAndSave("SURFACE_0", "WAV_PITCH", "extended-0")
  surfacesIni:setAndSave("_SCRIPTING_PHYSICS", "ALLOW_APPS", "1")
  ac.log("Enabled Track Physics")
end

function DisablePhysics()
-- Get surfaces.ini file path
local trackFolderPath = ac.getFolder(tostring(ac.FolderID.ContentTracks)) .. "\\" .. ac.getTrackID()
local surfacesFilePath = trackFolderPath .. "\\" .. ac.getTrackLayout() .. "\\data\\surfaces.ini"

-- Read all lines from surfaces.ini (apart those we want to delete)
local newLines = {}
local readFile = io.open(surfacesFilePath, "r")
if readFile ~= nil then
  for line in readFile:lines() do
    if line == "ALLOW_APPS=1" or line == "[_SCRIPTING_PHYSICS]" then
      -- Ignore these lines are for removal
    elseif line == "WAV_PITCH=extended-0" then
      table.insert(newLines, "WAV_PITCH=0")
    else
      table.insert(newLines, line)
    end
  end
end

-- Re-write the new version of the file
local writeFile = io.open(surfacesFilePath, "w+")
if writeFile ~= nil then
  for i = 1, #newLines, 1 do
    writeFile:write(newLines[i] .. "\n")
    ac.log(newLines[i])
  end
end

ac.log("Physics Disabled.")
end