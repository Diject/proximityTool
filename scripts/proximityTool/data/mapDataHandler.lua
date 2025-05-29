local storage = require('openmw.storage')
local common = require("scripts.proximityTool.common")
local tableLib = require("scripts.proximityTool.utils.table")

local version = 0

local this = {}

---@type table<string, table<string, proximityTool.markerData>> by groupId or recordId, by id
this.markers = {}

---@type table<string, proximityTool.markerRecord> by record id
this.records = {}

this.version = 0


local storageSection = storage.playerSection(common.playerStorageId)
if storageSection then
    this.markers = storageSection:getCopy(common.mapMarkersKey) or this.markers
    this.records = storageSection:getCopy(common.mapRecordsKey) or this.records
    this.version = storageSection:getCopy(common.mapDataVersion) or this.version
end


function this.save()
    ---@type table<string, proximityTool.markerRecord>
    local records = tableLib.deepcopy(this.records)
    for id, data in pairs(records) do
        if data.invalid or data.temporary then
            records[id] = nil
        elseif data.events then
            data.events = nil
        end
    end

    local foundRecordIds = {}

    ---@type table<string, table<string, proximityTool.markerData>>
    local markers = tableLib.deepcopy(this.markers)

    for groupId, cellData in pairs(markers) do
        for id, data in pairs(cellData) do
            if not data.record or
                    (type(data.record) == "string" and not records[data.record]) or
                    data.temporary or data.shortTerm or data.object or data.invalid then
                cellData[id] = nil
            else
                foundRecordIds[data.record] = true
            end
        end
    end

    for recordId, _ in pairs(records) do
        if not foundRecordIds[recordId] then
            records[recordId] = nil
        end
    end

    storageSection:set(common.mapMarkersKey, markers)
    storageSection:set(common.mapRecordsKey, records)
    storageSection:set(common.mapDataVersion, version)
end


---@param id string
---@param groupId string
---@return proximityTool.markerData?
function this.getMarker(id, groupId)
    if not id or not groupId then return end

    local cellDt = this.markers[groupId]
    if not cellDt then return end
    return cellDt[id]
end


---@param id string
---@return proximityTool.markerRecord?
function this.getRecord(id)
    if not id then return end
    return this.records[id]
end


---@param id string
---@param data proximityTool.markerRecord
function this.addRecord(id, data)
    if not id then return end
    local record = this.records[id]
    if record then
        tableLib.clear(record)
        tableLib.copy(data, record)
    else
        this.records[id] = data
    end
end


---@param id string
---@param groupId string
---@param data proximityTool.markerData
function this.addMarker(id, groupId, data)
    if not id or not groupId then return end

    this.markers[groupId] = this.markers[groupId] or {}
    this.markers[groupId][id] = data
end


---@param id string
---@return boolean
function this.removeRecord(id)
    if not id then return false end
    local record = this.records[id]
    if not record then return false end

    record.invalid = true
    this.records[id] = nil

    return true
end


---@param id string
---@param groupId string
---@return boolean?
function this.removeMarker(id, groupId)
    local marker = this.getMarker(id, groupId)
    if not marker then return false end

    marker.invalid = true
    this.markers[groupId][id] = nil

    return true
end


---@param groupId string
---@return fun(): string, proximityTool.markerData iterator marker id, marker data
function this.iterMarkerGroup(groupId)
    local function iterator()
        for id, data in pairs(this.markers[groupId] or {}) do
            coroutine.yield(id, data)
        end
    end
    return coroutine.wrap(iterator)
end


return this