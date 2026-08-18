local player = require('openmw.self')
local util = require("openmw.util")
local core = require("openmw.core")
local types = require("openmw.types")

local log = require("scripts.proximityTool.utils.log")
local tableLib = require("scripts.proximityTool.utils.table")
local getObject = require("scripts.proximityTool.utils.getObject")
local uniqueId = require("scripts.proximityTool.uniqueId")
local common = require("scripts.proximityTool.common")
local config = require("scripts.proximityTool.config")

local mapData = require("scripts.proximityTool.data.mapDataHandler")
local activeObjects = require("scripts.proximityTool.activeObjects")
local cellLib = require("scripts.proximityTool.cell")

local this = {}

---@class proximityTool.activeMarker
---@field markerId string?
---@field markers table<string, proximityTool.activeMarkerData> by marker id
---@field topMarker proximityTool.activeMarkerData?
---@field topIconMarker proximityTool.activeMarkerData?
---@field groupName string
---@field nextUpdate number
---@field lastTrackedObject any
---@field trackAllTypes boolean
---@field hidden boolean
---@field id string
---@field isValid boolean

---@type table<string, proximityTool.activeMarker> by record id
this.data = {}


local function getNexUpdateTimestamp(val)
    return val + config.data.objectPosUpdateInterval * (1 + (math.random() - 0.5) * 0.5)
end


---@param markerData proximityTool.activeMarkerData
---@param eventName string
---@param eventParams table?
function this.triggerEventForMarkerData(markerData, eventName, eventParams)
    if markerData.record.invalid or markerData.marker.invalid
            or not markerData.record.events or not markerData.record.events[eventName] then
        return
    end

    local eventCallbackName = markerData.record.events[eventName]

    local eventData = {
        id = markerData.marker.id,
        groupId = markerData.marker.groupId,
        data = markerData.marker,
        recordId = markerData.record.id,
        recordData = markerData.record,
        eventArgument = eventParams,
    }

    player:sendEvent(eventCallbackName, eventData)
end


---@class proximityTool.activeMarker
local activeMarker = {}
activeMarker.__index = activeMarker


---@return proximityTool.activeMarkerData? topRecord
---@return proximityTool.activeMarkerData? topRecordWithIcon
function activeMarker:getTopPriorityRecord()
    local topRecord
    local topIconRecord
    for markerId, data in pairs(self.markers) do
        if not topRecord or topRecord.record.priority < data.record.priority then
            topRecord = data
        end
        if data.record.icon and (not topIconRecord or topIconRecord.record.priority < data.record.priority) then
            topRecord = data
        end
    end
    return topRecord, topIconRecord
end

---@param eventName string
---@param eventParams table?
function activeMarker:triggerEvent(eventName, eventParams)
    if not self.isValid then return end

    for _, rec in pairs(self.markers) do

        if not rec.record.invalid and not rec.marker.invalid
                and rec.record.events and rec.record.events[eventName]
                and (not rec.record.options or rec.record.options.enableGroupEvent ~= false) then

            this.triggerEventForMarkerData(rec, eventName, eventParams)
        end
    end
end

function activeMarker:removeRecord(recordId)
    local record = self.markers[recordId]
    if not record then return end

    record.isValid = false

    self.markers[recordId] = nil
    if tableLib.count(self.markers) == 0 then
        self.isValid = false
        this.data[recordId] = nil
    end
end

function activeMarker:getClosestPos()
    local posData = {}

    local resultPos, resultObject
    local timestamp = core.getRealTime()

    if self.nextUpdate < timestamp or not self.lastTrackedObject then
        ---@type proximityTool.activeMarkerData?
        local topMarkerRecord = self.topMarker
        if not topMarkerRecord then return end

        for _, markerRecord in pairs(self.markers) do

            local markerRecordData = markerRecord.marker
            local filterDead = markerRecord.record.options and markerRecord.record.options.hideDead

            local foundPos = false
            local trackAllTypes = markerRecord.record.options and markerRecord.record.options.trackAllTypesTogether

            if markerRecordData.object then
                local objectRef = markerRecordData.object
                local posData = activeObjects.getObjectPositionData(objectRef, nil, markerRecordData.itemId, filterDead)
                if posData then
                    table.insert(posData, posData)
                    foundPos = true
                end
            end

            if markerRecordData.objects then
                local posData = activeObjects.getClosestReferencePosition(markerRecordData.objects, player, markerRecordData.itemId, filterDead)
                if posData then
                    table.insert(posData, posData)
                    foundPos = true
                end
            end

            if markerRecordData.objectId and (not foundPos or trackAllTypes) then
                local trackedObjPosition = activeObjects.getClosestObjectPosition(markerRecordData.objectId, player, markerRecordData.itemId, filterDead)
                if trackedObjPosition then
                    table.insert(posData, trackedObjPosition)
                    foundPos = true
                end
            end

            if markerRecordData.objectIds and (not foundPos or trackAllTypes) then
                local pos = activeObjects.getClosestObjectPositionByGroupName(markerRecordData.id, player, markerRecordData.itemId, filterDead)

                if pos then
                    table.insert(posData, pos)
                    foundPos = true
                end
            end

            if markerRecordData.positions and (not foundPos or trackAllTypes) then
                local pos, distance = cellLib.getClosestPosition(markerRecordData.positions)

                if pos then
                    table.insert(posData, {dif = distance, object = {position = pos}})
                    foundPos = true
                end
            end
        end

        if not next(posData) then
            return
        end


        table.sort(posData, function (a, b)
            return (a.dif or math.huge) < (b.dif or math.huge)
        end)
        local closest = posData[1]
        resultObject = closest.object
        resultPos = resultObject.position
        if not closest.object.isValid then
            closest.object.isValid = function ()
                return topMarkerRecord.isValid and self.isValid
            end
        end
        self.lastTrackedObject = closest.object
        self.nextUpdate = getNexUpdateTimestamp(timestamp)

    else
        resultObject = self.lastTrackedObject
        resultPos = resultObject.position
    end

    return resultPos, resultObject
end

---@return number? distance3D
---@return number? distance2D
---@return number? zDistance negative if player is below the marker, positive if above
---@return any? targetObject
function activeMarker:getDistancesToPlayer()
    local targetPos, targetObj = self:getClosestPos()
    if not targetPos then return end
    local playerPos = player.position

    local distance3D = (playerPos - targetPos):length()
    local distance2D = math.sqrt((playerPos.x - targetPos.x)^2 + (playerPos.y - targetPos.y)^2)
    local zDistance = playerPos.z - targetPos.z

    return distance3D, distance2D, zDistance, targetObj
end

---@return number
function activeMarker:calcProximityValue()
    local res = -1
    for _, rec in pairs(self.markers) do
        if rec.record.proximity then
            res = math.max(res, rec.record.proximity)
        end
    end
    if res <= 0 then res = 1000 end

    self.proximity = res
    return res
end

---@return number
function activeMarker:calcPriorityValue()
    local res = -math.huge
    for _, rec in pairs(self.markers) do
        res = math.max(res, rec.record.priority or 0)
    end

    self.priority = res
    return res
end

function activeMarker:calcAlphaValue()
    local res = 0
    for _, rec in pairs(self.markers) do
        res = math.max(res, rec.record.alpha or 1)
    end

    self.alpha = res
    return res
end

function activeMarker:calcHiddenFlag()
    local res = true
    for _, rec in pairs(self.markers) do
        if rec.record.hidden ~= true then
            res = false
            break;
        end
    end

    self.hidden = res
    return res
end

function activeMarker:update()
    local foundValid = false
    for id, data in pairs(self.markers) do
        local record = data.record
        local marker = data.marker
        if data.marker.invalid or record.invalid then
            self.markers[id] = nil
        elseif marker.shortTerm and (data.cellWhereRegistered.isExterior ~= player.cell.isExterior
                    or not player.cell.isExterior and data.cellWhereRegistered.id ~= player.cell.id) then
            mapData.removeMarker(marker.id, marker.groupId)
            self.markers[id] = nil
        else
            if marker.positions and cellLib.isContainValidPosition(marker.positions)
                    or marker.objectId and activeObjects.isContainValidRecordId(marker.objectId)
                    or marker.objectIds and activeObjects.isContainValidRecordIds(marker.objectIds)
                    or marker.object and marker.object:isValid()
                    or marker.objects and activeObjects.isCointainValidRefs(marker.objects)
                    or data.type == 16 then
                foundValid = true
            else
                data.isValid = false
                self.markers[id] = nil
            end
        end
    end

    if foundValid then
        self.topMarker, self.topIconMarker = self:getTopPriorityRecord()
        self.proximity = self:calcProximityValue()
        self.priority = self:calcPriorityValue()
        self.alpha = self:calcAlphaValue()
        self.hidden = self:calcHiddenFlag()
        self.isValid = true
    else
        self.isValid = false
    end
end




local function getNameColorHashId(name, colorArr)
    colorArr = colorArr or {}
    return string.format("%s_%d_%d_%d", name or "", (colorArr[1] or 0) * 255, (colorArr[2] or 0) * 255, (colorArr[3] or 0) * 255)
end


---@param params proximityTool.markerData
---@return proximityTool.activeMarker?
---@return boolean? should create ui element for this marker data
function this.register(params)
    if not params then return end
    if not params.record then return end

    local record
    if type(params.record) == "string" then
        ---@diagnostic disable-next-line: param-type-mismatch, cast-local-type
        record = mapData.getRecord(params.record)
    else
        record = params.record
    end

    if not record or record.invalid then
        params.invalid = true
        return
    end

    local activeMarkerId
    local markerId = params.id or uniqueId.get()

    if params.objectId then
        activeMarkerId = params.objectId
    elseif params.object then
        activeMarkerId = params.object.id
    elseif params.objects then
        activeMarkerId = getNameColorHashId(record.name, record.nameColor)
    elseif params.objectIds then
        activeMarkerId = getNameColorHashId(record.name, record.nameColor)
    elseif params.positions then
        activeMarkerId = getNameColorHashId(record.name, record.nameColor)
    else
        activeMarkerId = getNameColorHashId(record.name, record.nameColor)
    end

    if not activeMarkerId then
        activeMarkerId = uniqueId.get()
    end

    if params.groupName then
        activeMarkerId = params.groupName..activeMarkerId
    end

    local marker = this.data[activeMarkerId]
    if marker then
        marker:update()

        if not marker.isValid then
            marker = nil ---@diagnostic disable-line: cast-local-type
        end
    end

    ---@type proximityTool.activeMarkerData
    local activeMarkerData = marker and (marker.markers[markerId] or {}) or {} ---@diagnostic disable-line: missing-fields

    activeMarkerData.id = markerId
    activeMarkerData.marker = params
    activeMarkerData.record = record ---@diagnostic disable-line: assign-type-mismatch
    activeMarkerData.name = record.name or "???"
    record.priority = record.priority or 0
    activeMarkerData.type = 0

    if params.objectId then
        activeMarkerData.type = 1
        local object = getObject(params.objectId)
        if object and object.name then
            activeMarkerData.name = object.name
        end
    end
    if params.object then
        activeMarkerData.type = util.bitOr(activeMarkerData.type, 2)
    end
    if params.positions then
        activeMarkerData.type = util.bitOr(activeMarkerData.type, 4)
    end
    if params.objectIds then
        activeMarkerData.type = util.bitOr(activeMarkerData.type, 8)
    end
    if params.objects then
        activeMarkerData.type = util.bitOr(activeMarkerData.type, 32)
    end
    if not params.objectId and not params.object and not params.positions and not params.objectIds and not params.objects then
        activeMarkerData.type = 16
    end

    activeMarkerData.cellWhereRegistered = player.cell

    activeMarkerData.isValid = true

    local shouldCreateUIElement = false

    if not marker then
        ---@class proximityTool.activeMarker
        marker = setmetatable({}, activeMarker)
        ---@type table<string, proximityTool.activeMarkerData>
        marker.markers = {[activeMarkerData.id] = activeMarkerData}
        ---@type string
        marker.id = activeMarkerId
        ---@type boolean
        marker.isValid = true
        ---@type integer
        marker.type = activeMarkerData.type or 0

        marker.hidden = record.hidden or false

        if params.objectIds then
            activeObjects.registerGroup(markerId, params.objectIds)
        end

        marker.groupName = params.groupName or common.defaultGroupId

        marker.nextUpdate = 0

        shouldCreateUIElement = true
    else
        marker.markers[activeMarkerData.id] = activeMarkerData
    end

    marker.isValid = true

    ---@type proximityTool.activeMarkerData?
    marker.topMarker, marker.topIconMarker = marker:getTopPriorityRecord()
    ---@type number
    marker.proximity = marker:calcProximityValue()
    ---@type number
    marker.priority = marker:calcPriorityValue()
    ---@type number
    marker.alpha = marker:calcAlphaValue()

    marker.hidden = marker:calcHiddenFlag()

    marker.trackAllTypes = marker.topMarker.record.options and marker.topMarker.record.options.trackAllTypesTogether or false

    this.data[activeMarkerId] = marker
    if shouldCreateUIElement then
        player:sendEvent("proximityTool:activeMarkerAdded", activeMarkerId)
    else
        player:sendEvent("proximityTool:activeMarkerUpdated", activeMarkerId)
    end

    return marker, shouldCreateUIElement
end


function this.remove(recordId)
    local marker = this.data[recordId]
    if marker then
        marker.isValid = false

        if marker.topMarker and marker.topMarker.marker.objectIds then
            activeObjects.unregisterGroup(recordId)
        end

        this.data[recordId] = nil
    end
end


---@param recordId string
---@return proximityTool.activeMarker?
function this.get(recordId)
    return this.data[recordId]
end


---@param recordId string?
function this.update(recordId)
    if recordId then
        local actMarker = this.data[recordId]
        if actMarker then
            actMarker:update()

            if not actMarker.isValid then
                this.data[recordId] = nil
            end
        end

        return
    end
    for activeMarkerId, actMarker in pairs(this.data) do
        actMarker:update()
        if not actMarker.isValid then
            this.data[activeMarkerId] = nil
            player:sendEvent("proximityTool:activeMarkerRemoved", activeMarkerId)
        end
    end
end


---@return fun(): string, proximityTool.activeMarker iterator marker id, marker data
function this.iterator()
    local function iterator()
        for id, data in pairs(this.data) do
            coroutine.yield(id, data)
        end
    end
    return coroutine.wrap(iterator)
end


return this