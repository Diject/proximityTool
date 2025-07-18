local I = require('openmw.interfaces')

local tableLib = require("scripts.proximityTool.utils.table")

local common = require("scripts.proximityTool.common")
local activeObjects = require("scripts.proximityTool.activeObjects")
local mapData = require("scripts.proximityTool.data.mapDataHandler")

local hudm

local this = {}

this.version = -1

this.initialized = false


---@type table<string, any[]> by mod name
this.activeData = {}


---@type table<string, table<string, {object : any, modName : string, marker : proximityTool.HUDMarker}>> by ref.id; by marker id
this.activeByObject = {}


---@return boolean
function this.init()
    if this.initialized then return true end
    if not I.HUDMarkers then return false end

    hudm = I.HUDMarkers
    this.version = hudm.version
    this.initialized = true

    return true
end


local function getHashVal(refId, markerId)
    return refId..markerId
end


---@param modName string
---@param objectData table[]
local function setMarkers(modName, objectData)
    hudm.setMarkers(modName, objectData)
end


function this.update()
    if not this.init() then return end

    for refId, dt in pairs(this.activeByObject) do
        for markerId, data in pairs(dt) do
            local activeData = this.activeData[data.modName]
            if not activeData then goto continue end

            if data.marker.invalid or not data.object:isValid() then
                activeData[getHashVal(refId, markerId)] = nil

                dt[markerId] = nil

            elseif data.marker.hidden then
                activeData[getHashVal(refId, markerId)] = nil

            elseif not data.marker.hidden and not activeData[getHashVal(refId, markerId)] then
                local params = tableLib.deepcopy(data.marker.params)
                params.object = data.object

                activeData[getHashVal(refId, markerId)] = params

            end

            ::continue::
        end
    end

end


---@param marker proximityTool.HUDMarker
---@param ref any
---@return boolean?
local function addMarkers(marker, ref)
    if (marker.version or 0) > this.version or marker.invalid then return end

    if this.activeByObject[ref.id] and this.activeByObject[ref.id][marker.id] then return end

    local modName = marker.modName
    local modData = this.activeData[modName]
    if not modData then
        modData = {}
        setMarkers(modName, modData)
    end

    if not marker.hidden then
        local params = tableLib.deepcopy(marker.params)
        params.object = ref

        -- table.insert(modData, params)
        modData[getHashVal(ref.id, marker.id)] = params

        this.activeData[modName] = modData
    end

    this.activeByObject[ref.id] = this.activeByObject[ref.id] or {}
    this.activeByObject[ref.id][marker.id] = {object = ref, modName = modName, marker = marker}

    return true
end


---@return boolean?
function this.addObject(ref)
    if not this.init() or not ref or not ref:isValid() then return end

    local res = false

    local markersByRecordId = mapData.getHUDMarkers(ref.recordId)
    if markersByRecordId then
        for id, marker in pairs(markersByRecordId) do
            res = addMarkers(marker, ref) or res
        end
    end

    local markersByObjectID = mapData.getHUDMarkers(ref.id)
    if markersByObjectID then
        for id, marker in pairs(markersByObjectID) do
            res = addMarkers(marker, ref) or res
        end
    end

    return res
end


function this.removeObject(ref)
    if not this.init() or not ref then return end

    local found = false
    for id, data in pairs(this.activeByObject[ref.id] or {}) do
        local hudmData = this.activeData[data.modName]

        if hudmData then
            hudmData[getHashVal(ref.id, id)] = nil
        end

        if data.marker.shortTerm then
            data.marker.invalid = true
            local markerMain = (mapData.getHUDMarkers(data.marker.id) or {})[data.marker.id]
            if markerMain then
                markerMain.invalid = true
            end
        end

        this.activeByObject[ref.id][id] = nil

        found = true
    end

    return found
end


return this