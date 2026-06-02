local _cfgReady = false
local function ensureConfig()
    if _cfgReady then return true end
    if not Config or not Config.Filters or #Config.Filters == 0 then return false end
    _cfgReady = true
    return true
end

local cam, freeCamActive        = nil, false
local frozenVehicle             = nil
local initialPos                = nil
local currentFOV                = nil
local filterActive              = false
local helpersVisible            = nil
local currentFilterIndex        = nil

local followVehicle             = nil
local camLocalOffset            = nil
local camLocalPitch             = 0.0
local camLocalYaw               = 0.0
local camLocalRoll              = 0.0

local lockedCamPressedThisFrame = false
local lockedCamActive           = false
local lockedCamVehicle          = nil
local lockedLocalOffset         = nil
local lockedLocalPitch          = 0.0
local lockedLocalYaw            = 0.0

local aiDriveActive             = false

local sin, cos, rad, abs, sqrt = math.sin, math.cos, math.rad, math.abs, math.sqrt
local function clamp(v, lo, hi) return v < lo and lo or v > hi and hi or v end

local function setHudVisible(v)
    SendNUIMessage({ type = "pgn_setVisible", visible = v })
end

local function updateHudState(fov, filter, aiDrive, lockedCam, inVehicle, isPassenger)
    local msg = { type = "pgn_updateState" }
    if fov         ~= nil then msg.fov         = fov         end
    if filter      ~= nil then msg.filter      = filter      end
    if aiDrive     ~= nil then msg.aiDrive     = aiDrive     end
    if lockedCam   ~= nil then msg.lockedCam   = lockedCam   end
    if inVehicle   ~= nil then msg.inVehicle   = inVehicle   end
    if isPassenger ~= nil then msg.isPassenger = isPassenger end
    SendNUIMessage(msg)
end

local function sendHudConfig()
    SendNUIMessage({
        type    = "pgn_setConfig",
        hudTop  = tostring(Config.HudTop  or "16vh"),
        hudLeft = tostring(Config.HudLeft or "1vw"),
    })
end

local function getCamForward(rot)
    local rz, rx = rad(rot.z), rad(rot.x)
    return vector3(-sin(rz) * abs(cos(rx)), cos(rz) * abs(cos(rx)), sin(rx))
end

local function worldToLocal(veh, wp)
    return GetOffsetFromEntityGivenWorldCoords(veh, wp.x, wp.y, wp.z)
end

local function localToWorld(veh, lp)
    return GetOffsetFromEntityInWorldCoords(veh, lp.x, lp.y, lp.z)
end

local function beginVehicleFollow(veh)
    followVehicle    = veh
    camLocalOffset   = vector3(0.0, 0.0, 0.0)
    camLocalPitch    = 0.0
    camLocalYaw      = 0.0
    camLocalRoll     = 0.0
end

local function endVehicleFollow()
    followVehicle  = nil
    camLocalOffset = nil
    camLocalPitch  = 0.0
    camLocalYaw    = 0.0
    camLocalRoll   = 0.0
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
    lockedLocalOffset = worldToLocal(lockedCamVehicle, GetCamCoord(cam))
    local camRot      = GetCamRot(cam, 2)
    local vehRot      = GetEntityRotation(lockedCamVehicle, 2)
    lockedLocalPitch  = camRot.x - vehRot.x
    lockedLocalYaw    = camRot.z - vehRot.z
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    FreezeEntityPosition(lockedCamVehicle, false)
    if aiDriveActive then
        ClearPedTasks(ped)
        aiDriveActive = false
        updateHudState(nil, nil, false)
    end
    lockedCamActive = true
    updateHudState(nil, nil, nil, true)
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
    if not followVehicle then return end
    local ped = PlayerPedId()
    if GetPedInVehicleSeat(followVehicle, -1) ~= ped then return end
    FreezeEntityPosition(ped, false)
    FreezeEntityPosition(followVehicle, false)
    TaskVehicleDriveWander(ped, followVehicle, 20.0, 786603)
    aiDriveActive = true
    updateHudState(nil, nil, true)
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

local enabledControls = { 1, 2, 32, 33, 34, 35, 44, 38, 174, 175, 16, 17, 288, 289, 170, 245 }

local function disableControls()
    DisableAllControlActions(0)
    for i = 1, #enabledControls do
        EnableControlAction(0, enabledControls[i], true)
    end
    DisableControlAction(0, 75, true)
end

local function toggleFreeCam()
    if not ensureConfig() then return end
    if currentFOV         == nil then currentFOV         = Config.DefaultFOV              end
    if helpersVisible     == nil then helpersVisible     = Config.HelpersVisibleByDefault  end
    if currentFilterIndex == nil then currentFilterIndex = #Config.Filters                end

    local ped      = PlayerPedId()
    local doFreeze = Config.FreezeOnActivate == true
    freeCamActive  = not freeCamActive

    if freeCamActive then
        initialPos = GetEntityCoords(ped)

        local inDriverSeat  = false
        local isPassenger   = false
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(veh, -1) == ped then
                inDriverSeat = true
                if doFreeze then FreezeEntityPosition(ped, true) end
                frozenVehicle = nil
            else
                isPassenger   = true
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
        DisplayHud(false)
        DisplayRadar(false)

        local inVeh = IsPedInAnyVehicle(ped, false)
        if inDriverSeat or isPassenger then
            beginVehicleFollow(GetVehiclePedIsIn(ped, false))
        end

        sendHudConfig()
        updateHudState(currentFOV, Config.Filters[currentFilterIndex].label, false, nil, inVeh, isPassenger)
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
        DisplayHud(true)
        DisplayRadar(true)
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
    local lastFov       = 0
    local lastInVehicle = false

    while true do
        if not (freeCamActive and cam) then
            lastInVehicle = false
            Wait(500)
        else
            if not lockedCamActive then disableControls() end

            local moveSpeed = Config.MoveSpeed or 0.07
            local zoomSpeed = Config.ZoomSpeed or 0.9
            local minFOV    = Config.MinFOV    or 1.0
            local maxFOV    = Config.MaxFOV    or 120.0

            if followVehicle and DoesEntityExist(followVehicle) and not lockedCamActive then
                local vehRot = GetEntityRotation(followVehicle, 2)

                local mx = GetControlNormal(0, 1) * 8.0
                local my = GetControlNormal(0, 2) * 8.0
                camLocalYaw   = camLocalYaw   - mx
                camLocalPitch = clamp(camLocalPitch - my, -89.0, 89.0)
                if IsControlPressed(1, 174) then camLocalRoll = camLocalRoll - 1.0 end
                if IsControlPressed(1, 175) then camLocalRoll = camLocalRoll + 1.0 end

                SetCamRot(cam,
                    vehRot.x + camLocalPitch,
                    vehRot.y + camLocalRoll,
                    vehRot.z + camLocalYaw,
                    2)

                local rot = GetCamRot(cam, 2)
                local fwd = getCamForward(rot)
                local rgt = vector3(-fwd.y, fwd.x, 0.0)
                local dx, dy, dz = 0.0, 0.0, 0.0
                if IsControlPressed(1, 32) then dx = dx + fwd.x * moveSpeed; dy = dy + fwd.y * moveSpeed; dz = dz + fwd.z * moveSpeed end
                if IsControlPressed(1, 33) then dx = dx - fwd.x * moveSpeed; dy = dy - fwd.y * moveSpeed; dz = dz - fwd.z * moveSpeed end
                if IsControlPressed(1, 34) then dx = dx + rgt.x * moveSpeed; dy = dy + rgt.y * moveSpeed end
                if IsControlPressed(1, 35) then dx = dx - rgt.x * moveSpeed; dy = dy - rgt.y * moveSpeed end
                if IsControlPressed(1, 44) then dz = dz + moveSpeed end
                if IsControlPressed(1, 38) then dz = dz - moveSpeed end

                if dx ~= 0.0 or dy ~= 0.0 or dz ~= 0.0 then
                    local curWorld = localToWorld(followVehicle, camLocalOffset)
                    local newWorld = vector3(curWorld.x + dx, curWorld.y + dy, curWorld.z + dz)
                    camLocalOffset = worldToLocal(followVehicle, newWorld)
                    local maxRange = Config.MaxRange or 0
                    if maxRange > 0 then
                        local d = sqrt(camLocalOffset.x^2 + camLocalOffset.y^2 + camLocalOffset.z^2)
                        if d > maxRange then
                            local s = maxRange / d
                            camLocalOffset = vector3(camLocalOffset.x*s, camLocalOffset.y*s, camLocalOffset.z*s)
                        end
                    end
                end

                local wp = localToWorld(followVehicle, camLocalOffset)
                SetCamCoord(cam, wp.x, wp.y, wp.z)

            elseif lockedCamActive and lockedCamVehicle and DoesEntityExist(lockedCamVehicle) then
                local vehRot = GetEntityRotation(lockedCamVehicle, 2)
                SetCamRot(cam,
                    vehRot.x + lockedLocalPitch,
                    vehRot.y,
                    vehRot.z + lockedLocalYaw,
                    2)
                if lockedLocalOffset then
                    local wp = localToWorld(lockedCamVehicle, lockedLocalOffset)
                    SetCamCoord(cam, wp.x, wp.y, wp.z)
                end

            elseif not followVehicle then
                local pos = GetCamCoord(cam)
                local rot = GetCamRot(cam, 2)
                local fwd = getCamForward(rot)
                local rgt = vector3(-fwd.y, fwd.x, 0.0)
                local dx, dy, dz = 0.0, 0.0, 0.0
                if IsControlPressed(1, 32) then dx = dx + fwd.x * moveSpeed; dy = dy + fwd.y * moveSpeed; dz = dz + fwd.z * moveSpeed end
                if IsControlPressed(1, 33) then dx = dx - fwd.x * moveSpeed; dy = dy - fwd.y * moveSpeed; dz = dz - fwd.z * moveSpeed end
                if IsControlPressed(1, 34) then dx = dx + rgt.x * moveSpeed; dy = dy + rgt.y * moveSpeed end
                if IsControlPressed(1, 35) then dx = dx - rgt.x * moveSpeed; dy = dy - rgt.y * moveSpeed end
                if IsControlPressed(1, 44) then dz = dz + moveSpeed end
                if IsControlPressed(1, 38) then dz = dz - moveSpeed end
                if dx ~= 0.0 or dy ~= 0.0 or dz ~= 0.0 then
                    local maxRange = Config.MaxRange or 0
                    local newPos   = vector3(pos.x + dx, pos.y + dy, pos.z + dz)
                    if maxRange > 0 and initialPos then
                        local ex, ey, ez = newPos.x - initialPos.x, newPos.y - initialPos.y, newPos.z - initialPos.z
                        local dist = sqrt(ex*ex + ey*ey + ez*ez)
                        if dist > maxRange then
                            local s = maxRange / dist
                            newPos = vector3(initialPos.x + ex*s, initialPos.y + ey*s, initialPos.z + ez*s)
                        end
                    end
                    SetCamCoord(cam, newPos.x, newPos.y, newPos.z)
                end

                local mx2 = GetControlNormal(0, 1) * 8.0
                local my2 = GetControlNormal(0, 2) * 8.0
                local roll2 = rot.y
                if IsControlPressed(1, 174) then roll2 = roll2 - 1.0 end
                if IsControlPressed(1, 175) then roll2 = roll2 + 1.0 end
                if mx2 ~= 0.0 or my2 ~= 0.0 or IsControlPressed(1, 174) or IsControlPressed(1, 175) then
                    SetCamRot(cam, rot.x - my2, roll2, rot.z - mx2, 2)
                end
            end

            local fovChanged = false
            if IsControlPressed(1, 16) then
                currentFOV = clamp(currentFOV - zoomSpeed, minFOV, maxFOV)
                fovChanged = true
            elseif IsControlPressed(1, 17) then
                currentFOV = clamp(currentFOV + zoomSpeed, minFOV, maxFOV)
                fovChanged = true
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
                local ped2 = PlayerPedId()
                local isDriver = followVehicle and GetPedInVehicleSeat(followVehicle, -1) == ped2
                if isDriver then
                    if aiDriveActive then stopAIDrive() else startAIDrive() end
                end
            end
            if lockedCamPressedThisFrame then
                lockedCamPressedThisFrame = false
                if lockedCamActive then stopLockedCam() else startLockedCam() end
            end

            local ped2  = PlayerPedId()
            local inVeh = IsPedInAnyVehicle(ped2, false)
            if inVeh ~= lastInVehicle then
                lastInVehicle = inVeh
                local pass = false
                if inVeh then
                    local veh2 = GetVehiclePedIsIn(ped2, false)
                    pass = GetPedInVehicleSeat(veh2, -1) ~= ped2
                end
                updateHudState(nil, nil, nil, nil, inVeh, pass)
            end

            Wait(0)
        end
    end
end)