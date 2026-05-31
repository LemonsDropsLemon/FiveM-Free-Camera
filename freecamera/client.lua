local _ready = false
local function ensureConfig()
    if _ready then return true end
    if not Config or not Config.Filters or #Config.Filters == 0 then return false end
    _ready = true
    return true
end

local cam, freeCamActive          = nil, false
local frozenVehicle               = nil
local initialPos                  = nil
local initialHeading              = 0.0
local currentFOV                  = nil
local filterActive                = false
local helpersVisible              = nil
local currentFilterIndex          = nil

local followVehicle               = nil
local camLocalOffset              = nil
local camLocalPitchOffset         = 0.0
local camLocalYawOffset           = 0.0
local camLocalRollOffset          = 0.0

local aiDriveActive               = false
local lockedCamPressedThisFrame   = false
local lockedCamActive             = false
local lockedCamVehicle            = nil
local lockedLocalOffset           = nil
local lockedLocalPitch            = 0.0
local lockedLocalYaw              = 0.0

local sin, cos, rad, abs, sqrt = math.sin, math.cos, math.rad, math.abs, math.sqrt
local function clamp(v, lo, hi) return v < lo and lo or v > hi and hi or v end

local function getLocalOffset(veh, worldPos)
    return GetOffsetFromEntityGivenWorldCoords(veh, worldPos.x, worldPos.y, worldPos.z)
end

local function getWorldFromLocal(veh, local_off)
    return GetOffsetFromEntityInWorldCoords(veh, local_off.x, local_off.y, local_off.z)
end

local function vehicleBodyCamRot(vehRot, pitchOfs, yawOfs, rollOfs)
    return vector3(
        vehRot.x + pitchOfs,
        vehRot.y + rollOfs,
        vehRot.z + yawOfs
    )
end

local enabledControls = { 1, 2, 32, 33, 34, 35, 44, 38, 174, 175, 16, 17, 288, 289, 170, 245 }

local function setHudVisible(visible)
    SendNUIMessage({ type = "pgn_setVisible", visible = visible })
end

local function updateHudState(fov, filter, aiDrive, lockedCam)
    local msg = { type = "pgn_updateState" }
    if fov       ~= nil then msg.fov       = fov       end
    if filter    ~= nil then msg.filter    = filter    end
    if aiDrive   ~= nil then msg.aiDrive   = aiDrive   end
    if lockedCam ~= nil then msg.lockedCam = lockedCam end
    SendNUIMessage(msg)
end

local function sendHudConfig()
    SendNUIMessage({
        type    = "pgn_setConfig",
        hudTop  = tostring(Config.HudTop  or "16vh"),
        hudLeft = tostring(Config.HudLeft or "1vw"),
    })
end

local function clampToRange(newPos)
    local maxRange = Config.MaxRange or 0
    if maxRange <= 0 or not initialPos then return newPos end
    local dx, dy, dz = newPos.x - initialPos.x, newPos.y - initialPos.y, newPos.z - initialPos.z
    local dist = sqrt(dx*dx + dy*dy + dz*dz)
    if dist <= maxRange then return newPos end
    local s = maxRange / dist
    return vector3(initialPos.x + dx*s, initialPos.y + dy*s, initialPos.z + dz*s)
end

local function getCamForward(rot)
    local rz, rx = rad(rot.z), rad(rot.x)
    return vector3(-sin(rz) * abs(cos(rx)), cos(rz) * abs(cos(rx)), sin(rx))
end

local function beginVehicleFollow(veh)
    followVehicle  = veh
    local camPos   = GetCamCoord(cam)
    camLocalOffset = getLocalOffset(veh, camPos)
    local camRot   = GetCamRot(cam, 2)
    local vehRot   = GetEntityRotation(veh, 2)
    camLocalPitchOffset = camRot.x - vehRot.x
    camLocalYawOffset   = camRot.z - vehRot.z
    camLocalRollOffset  = 0.0
end

local function endVehicleFollow()
    followVehicle       = nil
    camLocalOffset      = nil
    camLocalPitchOffset = 0.0
    camLocalYawOffset   = 0.0
    camLocalRollOffset  = 0.0
end

local function stopAIDrive()
    if not aiDriveActive then return end
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    if Config.FreezeOnActivate and followVehicle then
        FreezeEntityPosition(followVehicle, true)
        FreezeEntityPosition(ped, true)
    end
    aiDriveActive = false
    updateHudState(nil, nil, false)
end

local function startAIDrive()
    local ped = PlayerPedId()
    if not followVehicle then return end
    if GetPedInVehicleSeat(followVehicle, -1) ~= ped then return end
    FreezeEntityPosition(ped, false)
    FreezeEntityPosition(followVehicle, false)
    TaskVehicleDriveWander(ped, followVehicle, 20.0, 786603)
    aiDriveActive = true
    updateHudState(nil, nil, true)
end

local function stopLockedCam()
    if not lockedCamActive then return end
    lockedCamActive   = false
    lockedCamVehicle  = nil
    lockedLocalOffset = nil
    lockedLocalPitch  = 0.0
    lockedLocalYaw    = 0.0
    updateHudState(nil, nil, nil, false)
end

local function startLockedCam()
    if not followVehicle or not DoesEntityExist(followVehicle) then return end
    if lockedCamActive then return end
    lockedCamVehicle  = followVehicle
    local camPos      = GetCamCoord(cam)
    lockedLocalOffset = getLocalOffset(lockedCamVehicle, camPos)
    local camRot      = GetCamRot(cam, 2)
    local vehRot      = GetEntityRotation(lockedCamVehicle, 2)
    lockedLocalPitch  = camRot.x - vehRot.x
    lockedLocalYaw    = camRot.z - vehRot.z
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    FreezeEntityPosition(lockedCamVehicle, false)
    if aiDriveActive then stopAIDrive() end
    lockedCamActive = true
    updateHudState(nil, nil, nil, true)
end

local function cycleFilter()
    if not ensureConfig() then return end
    if filterActive then StopScreenEffect(Config.Filters[currentFilterIndex].id) end
    currentFilterIndex = currentFilterIndex % #Config.Filters + 1
    local f = Config.Filters[currentFilterIndex]
    if f.id == "FocusOut" then
        ClearTimecycleModifier()
        StopAllScreenEffects()
        filterActive = false
    else
        StartScreenEffect(f.id, 0, true)
        filterActive = true
    end
    updateHudState(nil, f.label, nil)
end

local function disableControls()
    DisableAllControlActions(0)
    for i = 1, #enabledControls do EnableControlAction(0, enabledControls[i], true) end
end

local function toggleFreeCam()
    if not ensureConfig() then return end
    if currentFOV         == nil then currentFOV         = Config.DefaultFOV             end
    if helpersVisible     == nil then helpersVisible     = Config.HelpersVisibleByDefault end
    if currentFilterIndex == nil then currentFilterIndex = #Config.Filters               end

    local ped      = PlayerPedId()
    local doFreeze = Config.FreezeOnActivate == true
    freeCamActive  = not freeCamActive

    if freeCamActive then
        initialPos     = GetEntityCoords(ped)
        initialHeading = GetEntityHeading(ped)

        local inDriverSeat = false
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(veh, -1) == ped then
                inDriverSeat = true
                if doFreeze then FreezeEntityPosition(ped, true) end
                frozenVehicle = nil
            else
                frozenVehicle = veh
                if doFreeze then
                    FreezeEntityPosition(ped, true)
                    FreezeEntityPosition(frozenVehicle, true)
                end
            end
        else
            frozenVehicle = nil
            if doFreeze then FreezeEntityPosition(ped, true) end
        end

        cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        SetCamCoord(cam, initialPos.x, initialPos.y, initialPos.z + 1.0)
        SetCamRot(cam, 0.0, 0.0, 0.0, 2)
        SetCamFov(cam, currentFOV)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        DisplayHud(false); DisplayRadar(false)

        if inDriverSeat then beginVehicleFollow(GetVehiclePedIsIn(ped, false)) end

        sendHudConfig()
        updateHudState(currentFOV, Config.Filters[currentFilterIndex].label, false)
        if helpersVisible then setHudVisible(true) end
    else
        if lockedCamActive then stopLockedCam() end
        if aiDriveActive   then stopAIDrive()   end
        if followVehicle   then endVehicleFollow() end

        if doFreeze then
            if frozenVehicle then
                FreezeEntityPosition(frozenVehicle, false)
                frozenVehicle = nil
            else
                FreezeEntityPosition(ped, false)
            end
        end

        if filterActive then
            ClearTimecycleModifier()
            StopScreenEffect(Config.Filters[currentFilterIndex].id)
            filterActive       = false
            currentFilterIndex = #Config.Filters
        end

        DestroyCam(cam, false)
        RenderScriptCams(false, false, 0, true, true)
        cam = nil
        DisplayHud(true); DisplayRadar(true)
        setHudVisible(false)
    end
end

RegisterCommand(Config.ActivationCommand or "freecam", function() toggleFreeCam() end, false)

RegisterCommand("pgn_lockedcam", function()
    lockedCamPressedThisFrame = true
end, false)
RegisterKeyMapping("pgn_lockedcam", "Freecam: Toggle Locked Camera", "keyboard", "F4")

CreateThread(function()
    Wait(500)
    if ensureConfig() then sendHudConfig() end
end)

CreateThread(function()
    local lastFov = 0

    while true do
        if freeCamActive and cam then
            if not lockedCamActive then disableControls() end

            local moveSpeed = Config.MoveSpeed or 0.07
            local zoomSpeed = Config.ZoomSpeed or 0.9
            local minFOV    = Config.MinFOV    or 1.0
            local maxFOV    = Config.MaxFOV    or 120.0

            if followVehicle and DoesEntityExist(followVehicle) and not lockedCamActive then
                local vehRot = GetEntityRotation(followVehicle, 2)

                local mx = GetControlNormal(0, 1) * 8.0
                local my = GetControlNormal(0, 2) * 8.0
                camLocalYawOffset   = camLocalYawOffset   - mx
                camLocalPitchOffset = clamp(camLocalPitchOffset - my, -89.0, 89.0)

                if IsControlPressed(1, 174) then camLocalRollOffset = camLocalRollOffset - 1.0 end
                if IsControlPressed(1, 175) then camLocalRollOffset = camLocalRollOffset + 1.0 end

                local finalRot = vehicleBodyCamRot(vehRot, camLocalPitchOffset, camLocalYawOffset, camLocalRollOffset)
                SetCamRot(cam, finalRot.x, finalRot.y, finalRot.z, 2)

                if camLocalOffset then
                    local rot = GetCamRot(cam, 2)
                    local fwd = getCamForward(rot)
                    local rgt = vector3(-fwd.y, fwd.x, 0.0)
                    local mv  = vector3(0, 0, 0)
                    if IsControlPressed(1, 32) then mv = mv + fwd * moveSpeed end
                    if IsControlPressed(1, 33) then mv = mv - fwd * moveSpeed end
                    if IsControlPressed(1, 34) then mv = mv + rgt * moveSpeed end
                    if IsControlPressed(1, 35) then mv = mv - rgt * moveSpeed end
                    if IsControlPressed(1, 44) then mv = mv + vector3(0, 0,  moveSpeed) end
                    if IsControlPressed(1, 38) then mv = mv + vector3(0, 0, -moveSpeed) end

                    if mv.x ~= 0 or mv.y ~= 0 or mv.z ~= 0 then
                        local curWorld = getWorldFromLocal(followVehicle, camLocalOffset)
                        local newWorld = vector3(curWorld.x + mv.x, curWorld.y + mv.y, curWorld.z + mv.z)
                        camLocalOffset = getLocalOffset(followVehicle, newWorld)
                        local maxRange = Config.MaxRange or 0
                        if maxRange > 0 then
                            local d = sqrt(camLocalOffset.x^2 + camLocalOffset.y^2 + camLocalOffset.z^2)
                            if d > maxRange then
                                local s = maxRange / d
                                camLocalOffset = vector3(camLocalOffset.x*s, camLocalOffset.y*s, camLocalOffset.z*s)
                            end
                        end
                    end

                    local wp = getWorldFromLocal(followVehicle, camLocalOffset)
                    SetCamCoord(cam, wp.x, wp.y, wp.z)
                end

            elseif lockedCamActive and lockedCamVehicle and DoesEntityExist(lockedCamVehicle) then
                local vehRot   = GetEntityRotation(lockedCamVehicle, 2)
                local finalRot = vehicleBodyCamRot(vehRot, lockedLocalPitch, lockedLocalYaw, 0.0)
                SetCamRot(cam, finalRot.x, finalRot.y, finalRot.z, 2)
                if lockedLocalOffset then
                    local wp = getWorldFromLocal(lockedCamVehicle, lockedLocalOffset)
                    SetCamCoord(cam, wp.x, wp.y, wp.z)
                end

            elseif not followVehicle then
                local pos = GetCamCoord(cam)
                local rot = GetCamRot(cam, 2)
                local fwd = getCamForward(rot)
                local rgt = vector3(-fwd.y, fwd.x, 0.0)
                local mv  = vector3(0, 0, 0)
                if IsControlPressed(1, 32) then mv = mv + fwd * moveSpeed end
                if IsControlPressed(1, 33) then mv = mv - fwd * moveSpeed end
                if IsControlPressed(1, 34) then mv = mv + rgt * moveSpeed end
                if IsControlPressed(1, 35) then mv = mv - rgt * moveSpeed end
                if IsControlPressed(1, 44) then mv = mv + vector3(0, 0,  moveSpeed) end
                if IsControlPressed(1, 38) then mv = mv + vector3(0, 0, -moveSpeed) end
                if mv.x ~= 0 or mv.y ~= 0 or mv.z ~= 0 then
                    SetCamCoord(cam, clampToRange(pos + mv))
                end
                local rot2 = GetCamRot(cam, 2)
                local mx2  = GetControlNormal(0, 1) * 8.0
                local my2  = GetControlNormal(0, 2) * 8.0
                local roll2 = rot2.y
                if IsControlPressed(1, 174) then roll2 = roll2 - 1.0 end
                if IsControlPressed(1, 175) then roll2 = roll2 + 1.0 end
                if mx2 ~= 0 or my2 ~= 0 or IsControlPressed(1, 174) or IsControlPressed(1, 175) then
                    SetCamRot(cam, rot2.x - my2, roll2, rot2.z - mx2, 2)
                end
            end

            local fovChanged = false
            if IsControlPressed(1, 16) then
                currentFOV = clamp(currentFOV - zoomSpeed, minFOV, maxFOV); fovChanged = true
            elseif IsControlPressed(1, 17) then
                currentFOV = clamp(currentFOV + zoomSpeed, minFOV, maxFOV); fovChanged = true
            end
            if fovChanged then
                SetCamFov(cam, currentFOV)
                if math.abs(currentFOV - lastFov) >= 0.5 then
                    updateHudState(currentFOV, nil, nil)
                    lastFov = currentFOV
                end
            end

            if IsControlJustPressed(1, 288) then cycleFilter() end
            if IsControlJustPressed(1, 289) then
                helpersVisible = not helpersVisible
                setHudVisible(helpersVisible)
            end
            if IsControlJustPressed(1, 170) then
                if aiDriveActive then stopAIDrive() else startAIDrive() end
            end
            if lockedCamPressedThisFrame then
                lockedCamPressedThisFrame = false
                if lockedCamActive then stopLockedCam() else startLockedCam() end
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)