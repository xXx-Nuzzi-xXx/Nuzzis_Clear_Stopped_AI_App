-- Author - Nuzzi

-- USER VARS START
local hideDisableTrackPhysicsSection = false -- Set to true to hide this part of the in session UI.
-- USER VARS END

-- Global Vars
local aiDriversStationaryTime = {}
local hasDriverBeenSentToPits = {}
local firstFrame = true
local driverFocusedInUI = 1
local speedConsideredStopped = 50
local timeStationaryToCauseRetirement = 10 -- (Must be >= 10)


-- Runs once on session restart
ac.onSessionStart(function(sessionIndex, restarted)
    ac.log("---------------------")
    ac.log("Session Restarted")
    ac.log("---------------------")
    firstFrame = true
end)

-- Runs once per frame
---@diagnostic disable-next-line: duplicate-set-field
function script.update(dt)
  if CheckSessionValidity() == true then
    -- Run once at session start & restart
    if firstFrame == true then
      ConstructAiDriverArrays()
      firstFrame = false
      driverFocusedInUI = 1
      ac.log("Setup Complete")
    else -- Run Once Each Frame
      -- Only run over duration of the session
      if ac.getSim().isSessionStarted == true and ac.getSim().isSessionFinished == false then
        CheckAllAiForStopped(dt)
        KeepCarsSentToPitsStoppedInBox()
      end
    end
  else
    ac.log("ERROR - Session Invalid")

    -- Ensure AI drivers are visible in replay mode
    if ac.getSim().isReplayActive == true then
      SetAllAIDriversVisible()
    end
  end
end

-- Runs once per frame on the Main window
---@diagnostic disable-next-line: duplicate-set-field
function script.windowMain(dt)
  -- BG + Border
  ui.drawRectFilled(10, vec2(ui.windowWidth(), ui.windowHeight()), rgbm.colors.black, nil, nil)
  ui.drawRect(10, vec2(ui.windowWidth()-10, ui.windowHeight()-1), rgbm.colors.cyan, nil, nil, 4)

  -- Title
  ui.dwriteDrawTextClipped("Clear Stopped AI Monitor", 18, vec2(10,10), vec2(260,40), ui.Alignment.Center, ui.Alignment.End, true, rgbm.colors.white)
  ui.drawLine(vec2(0,45), vec2(ui.windowWidth(), 45), rgbm.colors.cyan, 3)
  ui.newLine(40)

  -- Check session valid
  if CheckSessionValidity() == true then
    -- Buttons to navigate UI
    ui.columns(3, false)
    ui.setColumnWidth(0, 10)
    ui.setColumnWidth(1, 110)
    ui.setColumnWidth(2, 110)
    ui.nextColumn()
    if ui.modernButton("Last", vec2(90,35), nil, ui.Icons.ArrowLeft, 15, nil) then
      if driverFocusedInUI > 1 then -- Don't let lower than 1
        driverFocusedInUI = driverFocusedInUI -1
      end
    end
    ui.nextColumn()
    if ui.modernButton("Next", vec2(90,35), nil, ui.Icons.ArrowRight, 15, nil) then
      if driverFocusedInUI < ac.getSim().carsCount - 1 then -- Don't let higher than cars available
        driverFocusedInUI = driverFocusedInUI +1
      end
    end
    ui.columns(0)
    ui.newLine(1)

    -- Show Driver Live Info
    ui.text("  " .. ac.getDriverName(driverFocusedInUI))
    ui.text("  ID: " .. driverFocusedInUI)
    ui.text("  Lap: " .. ac.getCar(driverFocusedInUI).lapCount +1)
    ui.text("  Time Stopped on track: " .. tostring(math.round(aiDriversStationaryTime[driverFocusedInUI], 1)))
    ui.text("  Has been sent to pits: " .. tostring(hasDriverBeenSentToPits[driverFocusedInUI]))

    -- Disable track physics button
    ShowDisableTrackPhysicsButton()
  else -- Session Invalid
    ShowWhySessionInvalid()
  end
  ui.newLine(0)
end

-- FUNCTIONS
function CheckSessionValidity()
  if ac.getPatchVersionCode() < 3281 then -- 3281 == CSP 0.2.6  (Preview versions min CSP 0.2.7 - preview)
    ac.log("CSP version too low")
    return false
  end

  if ac.getSessionName(ac.getSim().currentSessionIndex) ~= "Quick Race"
    and ac.getSessionName(ac.getSim().currentSessionIndex) ~= "Race"
    and ac.getSessionName(ac.getSim().currentSessionIndex) ~= "car" -- "car" is for trackdays
    and ac.getSessionName(ac.getSim().currentSessionIndex) ~= "Qualifying"
  then
    ac.log("Invalid session type: " .. ac.getSessionName(ac.getSim().currentSessionIndex))
    return false
  end

  if physics.allowed() == false then
    ac.log("Track Physics is not enabled")
    return false
  end

  if ac.getSim().isReplayActive == true then
    ac.log("In Replay mode, app inactive")
    return false
  end

  if ac.getSim().isOnlineRace == true then
    ac.log("Not in an offline session")
    return false
  end

  return true
end

function ConstructAiDriverArrays()
  -- Loop through ai drivers
  for i = 1, (ac.getSim().carsCount - 1), 1
  do
    aiDriversStationaryTime[i] = 0
    hasDriverBeenSentToPits[i] = false
    ac.setDriverVisible(i, true)
  end
end

function CheckAllAiForStopped(dt)
  -- Loop through ai drivers
  for i = 1, (ac.getSim().carsCount - 1), 1
  do
    -- Count stationary time when out on track and stopped.
    if ac.getCar(i).speedKmh < speedConsideredStopped and ac.getCar(i).isInPitlane == false and ac.getCar(i).isInPit == false then
      aiDriversStationaryTime[i] = aiDriversStationaryTime[i] + dt
    end

    -- Send back to pits when stopped on track too long, only do once
    if aiDriversStationaryTime[i] > timeStationaryToCauseRetirement and hasDriverBeenSentToPits[i] == false and ac.getCar(i).isInPit == false and ac.getCar(i).isInPitlane == false then
      physics.teleportCarTo(i, ac.SpawnSet.Pits)
      hasDriverBeenSentToPits[i] = true
      ac.log(ac.getDriverName(i) .. " was stopped so has been sent to the pits")
    end

    -- Reset counter if they have got going again
    if ac.getCar(i).speedKmh > speedConsideredStopped then
      aiDriversStationaryTime[i] = 0
    end

    -- Reset have been sent to pits if they are back out on track
    if ac.getCar(i).speedKmh > 30 and ac.getCar(i).isInPitlane == false and ac.getCar(i).isInPit == false and hasDriverBeenSentToPits[i] == true then
      hasDriverBeenSentToPits[i] = false
      ac.log(ac.getDriverName(i) .. " has rejoined the session.")
    end
  end
end

function KeepCarsSentToPitsStoppedInBox()
  -- Only keep in stationary (aka retired) box if in race session. They can rejoin in quali and track days
  if ac.getSessionName(ac.getSim().currentSessionIndex) == "Quick Race"
    or ac.getSessionName(ac.getSim().currentSessionIndex) == "Race"
  then
    for i = 1, (ac.getSim().carsCount - 1), 1
    do
      if hasDriverBeenSentToPits[i] == true then
        physics.overrideSteering(i, 0)
        physics.setGentleStop(i, true)
        ac.setDriverVisible(i, false)
      end
    end
  end
end


function SetAllAIDriversVisible()
  -- Loop through ai drivers
  for i = 1, (ac.getSim().carsCount - 1), 1
  do
    ac.setDriverVisible(i, true)
  end
end

-- UI FUNCTIONS
function ShowEnableTrackPhysicsButton()
  -- Setup Columns
  ui.columns(2, false, "Enable Track Physics Button Columns")
  ui.setColumnWidth(0, 33)
  ui.setColumnWidth(1, 200)
  ui.nextColumn()

  if ui.button("Enable Track Physics") then
    EnablePhysics()
    ui.toast(ui.Icons.Confirm, "Track Physics Enabled, please restart to apply.")
  end

  -- End columns
  ui.columns(0)
end

function ShowDisableTrackPhysicsButton()
  if hideDisableTrackPhysicsSection == false then
    ui.text("________________________________")

    -- Setup Columns
    ui.columns(2, false, "Disable Track Physics Button Columns")
    ui.setColumnWidth(0, 33)
    ui.setColumnWidth(1, 200)
    ui.nextColumn()

    if ui.button("Disable Track Physics") then
     DisablePhysics()
     ui.toast(ui.Icons.LoadingSpinner, "Track Physics Disabled, please restart to apply.")
    end

    -- End columns
    ui.columns(0)

    ui.pushFont(5)
    ui.text("  Press if you enabled them and")
    ui.text("  want to use track online. It")
    ui.text("  will stop server 'Checksum error'")
    ui.pushFont(4)
  end
end

function ShowWhySessionInvalid()
  -- CSP version is too low
  if ac.getPatchVersionCode() < 3281 then   -- 3281 == CSP 0.2.6  (Preview versions min CSP 0.2.7 - preview)
    ui.text("    ERROR: CSP version too low:")
    ui.text("    Min free = 0.2.6")
    ui.text("    Min paid = 0.2.7 preview")

  -- Not in race session
  elseif ac.getSessionName(ac.getSim().currentSessionIndex) ~= "Quick Race"
    and ac.getSessionName(ac.getSim().currentSessionIndex) ~= "Race"
    and ac.getSessionName(ac.getSim().currentSessionIndex) ~= "car" -- "car" is for trackdays
    and ac.getSessionName(ac.getSim().currentSessionIndex) ~= "Qualifying"
  then
    ui.text("    NOTE: Not in valid session type ")
    ui.text("          App inactive.")

  -- Track Physics is disabled
  elseif physics.allowed() == false then
    ui.text("ERROR: Track Physics is disabled.")
    ShowEnableTrackPhysicsButton()

  -- In Online Session
  elseif ac.getSim().isOnlineRace == true then
    ui.text("NOTE: Online session, app inactive")

  -- In Replay Mode
  elseif ac.getSim().isReplayActive == true then
    ui.text("  NOTE: Replay Mode, app inactive")

  -- Unknown Error
  else
    ui.text("       ERROR: Unknown error.")
  end
end

-- MISC FUNCTIONS
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
