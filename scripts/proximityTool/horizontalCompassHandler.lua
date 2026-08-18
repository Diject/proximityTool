local I = require("openmw.interfaces")
local async = require("openmw.async")
local util = require("openmw.util")

local realTimer = require("scripts.proximityTool.realTimer")
local config = require("scripts.proximityTool.config")
local commonData = require("scripts.proximityTool.common")
local mainMenu = require("scripts.proximityTool.ui.mainMenu")

local activeMarkers = require("scripts.proximityTool.activeMarkers")

---@type HorizontalCompass.Interface
local interface = nil

local this = {}

this.markers = {}


async:newUnsavableSimulationTimer(0.1, function ()
    if not I.HorizontalCompassByValcule or not config.data.horizontalCompassIntegration then return end
    ---@type HorizontalCompass.Interface
    interface = I.HorizontalCompassByValcule

    config.data.ui.hideHUDAlt = true
    I.proximityTool.destroyMenu()

    interface.subscribeAllMarkersRemoved(function ()
        this.markers = {}

        for mId, markerData in activeMarkers.iterator() do
            this.registerMarker(markerData)
        end
    end)

    for mId, markerData in activeMarkers.iterator() do
        this.registerMarker(markerData)
    end
end)


---@param activeMarker proximityTool.activeMarker
function this.registerMarker(activeMarker)
    if not interface then return end

    ---@type proximityTool.activeMarkerData?
    local topRecord = activeMarker.topIconMarker or activeMarker.topMarker
    if not topRecord or not topRecord.isValid then
        this.unregisterMarker(activeMarker.id)
        return
    end

    local mId = activeMarker.id
    local rec = topRecord.record
    local icon = topRecord.record.icon
    local distance, distance2D, heightDiff, obj = activeMarker:getDistancesToPlayer()

    if this.markers[mId] then
        local id = this.markers[mId].id
        if id then
            interface.removeMarker(id)
        end
        this.markers[mId] = nil
    end

    local propSize
    if topRecord.record and topRecord.record.iconRatio then
        local ratio = topRecord.record.iconRatio
        if ratio == 0 then ratio = 0.1 end
        propSize = util.vector2(1 / ratio, 1)
    end

    local iconColor
    -- override icon for quest guider markers
    if not icon and topRecord.record and topRecord.record.userData and topRecord.record.userData.type == "tracking" then
        icon = commonData.qgMapMarkerIconPath
        iconColor = rec.nameColor and util.color.rgb(rec.nameColor[1] or 1, rec.nameColor[2] or 1, rec.nameColor[3] or 1) or nil
        propSize = nil
    elseif icon == commonData.qgDoorIconPath then
        icon = commonData.qgMapMarkerDoorIconPath
        iconColor = rec.nameColor and util.color.rgb(rec.nameColor[1] or 1, rec.nameColor[2] or 1, rec.nameColor[3] or 1) or nil
        propSize = nil
    end

    if not icon or not obj then
        this.unregisterMarker(activeMarker.id)
        return
    end

    iconColor = iconColor or rec.iconColor and util.color.rgb(rec.iconColor[1] or 1, rec.iconColor[2] or 1, rec.iconColor[3] or 1) or nil

    ---@type HorizontalCompass.Markers.createMarker.params
    local params = {
        texture = icon,
        propSize = propSize,
        object = obj,
        color = iconColor
    }
    local markerId = interface.createMarker(params)

    local hide = (distance > activeMarker.proximity) or (activeMarker.alpha <= 0) or activeMarker.hidden
    if hide then
        interface.updateMarkerAlpha(markerId, 0) ---@diagnostic disable-line: param-type-mismatch
    end

    this.markers[mId] = params
end


---@param activeMarkerId string
function this.unregisterMarker(activeMarkerId)
    if not interface then return end

    local markerParams = this.markers[activeMarkerId]
    if not markerParams then return end

    this.markers[activeMarkerId] = nil

    local markerId = markerParams.id
    if markerId then
        interface.removeMarker(markerId)
    end
end


function this.update()
    if not interface then return end

    local removed = {}

    for activeMarkerId, markerParams in pairs(this.markers) do
        local activeMarker = activeMarkers.get(activeMarkerId)
        if not activeMarker or not activeMarker.isValid or not activeMarker.topMarker then
            table.insert(removed, activeMarkerId)
            goto continue
        end

        local distance, distance2D, heightDiff, obj = activeMarker:getDistancesToPlayer()
        if not obj or not obj:isValid() then
            table.insert(removed, activeMarkerId)
            goto continue
        end

        markerParams.object = obj

        local hide = (distance > activeMarker.proximity) or (activeMarker.alpha <= 0) or activeMarker.hidden
        interface.updateMarkerAlpha(markerParams.id or "", hide and 0 or 1)

        ::continue::
    end

    for _, mId in pairs(removed) do
        this.unregisterMarker(mId)
    end
end



return this