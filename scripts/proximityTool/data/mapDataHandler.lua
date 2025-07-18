local common = require("scripts.proximityTool.common")
local tableLib = require("scripts.proximityTool.utils.table")

local version = 0

local this = {}

---@type table<string, table<string, proximityTool.markerData>> by groupId or recordId, by id
this.markers = {}

---@type table<string, table<string, proximityTool.HUDMarker>> by id or objectId or object recordId; by id
this.hudm = {}

---@type table<string, proximityTool.markerRecord> by record id
this.records = {}

this.version = 0



function this.load(dataTable)
    if not dataTable then return end
    this.markers = dataTable[common.mapMarkersKey] or {}
    this.records = dataTable[common.mapRecordsKey] or {}
    this.hudm = dataTable[common.hudmMarkersKey] or {}
    this.version = dataTable[common.mapDataVersionKey] or version
end


function this.save(dataTable)
    ---@type table<string, proximityTool.markerRecord>
    local records = tableLib.deepcopy(this.records)
    for id, data in pairs(records) do
        if data.invalid or data.temporary then
            records[id] = nil
        elseif data.events then
            (records[id]  or {}).events = nil
        end
    end

    ---@type table<string, table<string, proximityTool.markerData>>
    local markers = tableLib.deepcopy(this.markers)

    for groupId, cellData in pairs(markers) do
        for id, data in pairs(cellData) do
            if not data.record or
                    (type(data.record) == "string" and not records[data.record]) or
                    data.temporary or data.shortTerm or data.object or data.invalid then
                (markers[groupId] or {})[id] = nil
            end
        end
    end

    ---@type table<string, table<string, proximityTool.HUDMarker>>
    local hudm = tableLib.deepcopy(this.hudm)
    for markerId, hudMarkers in pairs(hudm) do
        for id, data in pairs(hudMarkers) do
            if data.objects or data.invalid or data.temporary or data.shortTerm then
                hudm[markerId][id] = nil
            end
        end
    end

    dataTable[common.mapMarkersKey] = markers
    dataTable[common.mapRecordsKey] = records
    dataTable[common.hudmMarkersKey] = hudm
    dataTable[common.mapDataVersionKey] = version
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

    if marker.positions then
        for _, posData in pairs(marker.positions) do
            local grId = posData.cell.isExterior and common.worldCellLabel or posData.cell.id
            if grId and this.markers[grId] and this.markers[grId][id] then
                this.markers[grId][id].invalid = true
                this.markers[grId][id] = nil
            end
        end
        if groupId ~= common.positionsLabel then
            local mk = this.getMarker(id, common.positionsLabel)
            if not mk then return false end

            mk.invalid = true
            this.markers[common.positionsLabel][id] = nil
        end
    elseif marker.objects then
        for _, objId in pairs(marker.objects) do
            if this.markers[objId] and this.markers[objId][id] then
                this.markers[objId][id].invalid = true
                this.markers[objId][id] = nil
            end
        end
        if groupId ~= common.objectsLabel then
            local mk = this.getMarker(id, common.objectsLabel)
            if not mk then return false end

            mk.invalid = true
            this.markers[common.objectsLabel][id] = nil
        end
    else
        marker.invalid = true
        this.markers[groupId][id] = nil
    end

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


---@param id string
---@param data proximityTool.HUDMarker
function this.addHUDMarker(id, data)
    if not id then return end
    local hudMarker = this.hudm[id]
    if hudMarker then
        local dt = hudMarker[data.id]
        if dt then
            tableLib.clear(dt)
            tableLib.copy(data, dt)
        else
            hudMarker[data.id] = data
        end
    else
        this.hudm[id] = {[id] = data}
    end
end


---@param id string
---@return boolean
function this.removeHUDMarker(id)
    if not id then return false end
    local markers = this.hudm[id]
    if not markers then return false end

    for markerId, marker in pairs(markers) do
        if marker.objects then
            for _, object in pairs(marker.objects) do
                local objectMarkers = this.hudm[object.id]
                if objectMarkers and objectMarkers[id] then
                    objectMarkers[id].invalid = true
                    this.hudm[object.id][id] = nil
                end
            end
        end
        if marker.objectIds then
            for _ ,objId in pairs(marker.objectIds) do
                local objectMarkers = this.hudm[objId]
                if objectMarkers and objectMarkers[id] then
                    objectMarkers[id].invalid = true
                    this.hudm[objId][id] = nil
                end
            end
        end
    end

    if markers[id] then
        markers[id].invalid = true
        markers[id] = nil
        if not next(markers) then
            this.hudm[id] = nil
        end
    end

    return true
end


---@param id string
---@return table<string, proximityTool.HUDMarker>?
function this.getHUDMarkers(id)
    if not id then return end
    return this.hudm[id]
end


return this