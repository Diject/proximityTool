local tableLib = require("scripts.proximityTool.utils.table")

---@diagnostic disable: undefined-doc-name
local this = {}

---@type table<string, proximityTool.activeObject.objectHandler> by record id
this.data = {}

---@type table<string, table<string, string>>
this.groupIdsByObjectRecordId = {}

---@type table<string, table<string, string>>
this.objectRecordIdsByGroupId = {}


---@class proximityTool.activeObject.objectHandler
local objectHandler = {}
objectHandler.__index = objectHandler
---@type table<string, string>
objectHandler.groups = {}

function objectHandler:add(object)
    if not self.objects[object.id] then
        self.count = self.count + 1
    end
    self.objects[object.id] = object
end

function objectHandler:get(refId)
    local ref = self.objects[refId]
    if not ref then return end

    if not ref:isValid() then
        self.objects[refId] = nil
        return
    end

    return ref
end

function objectHandler:remove(object)
    if self.objects[object.id] then
        self.count = self.count - 1
    end
    self.objects[object.id] = nil
end

local function calc2DDistance(obj1, obj2)
    local pos1, pos2 = obj1.position, obj2.position
    return math.sqrt((pos2.x - pos1.x)^2 + (pos2.y - pos1.y)^2)
end

---@return {x: number, y: number, z: number, dif : number?}[]
function objectHandler:positions(refObject)
    local ret = {}
    for id, object in pairs(self.objects) do
        if object:isValid() then
            table.insert(ret, {
                x = object.position.x,
                y = object.position.y,
                z = object.position.z,
                dif = refObject and calc2DDistance(refObject, object)
            })
        else
            self.objects[id] = nil
            self.count = self.count - 1
        end
    end
    return ret
end



function this.add(object)
    local objHandler = this.data[object.recordId]
    if not objHandler then
        ---@class proximityTool.activeObject.objectHandler
        objHandler = setmetatable({}, objectHandler)
        ---@type integer
        objHandler.count = 0
        ---@type string
        objHandler.recordId = object.recordId
        ---@type table<string, any> by object id
        objHandler.objects = {}

        this.data[object.recordId] = objHandler
    end

    local groups = this.groupIdsByObjectRecordId[object.recordId]
    if groups then
        objHandler.groups = groups
    end

    objHandler:add(object)
end


function this.remove(object)
    local objHandler = this.data[object.recordId]
    if not objHandler then return end
    objHandler:remove(object)
    if objHandler.count == 0 then
        this.data[object.recordId] = nil
    end
end


---@param recordId string
---@return {x: number, y: number, z: number, dif : number?}[]?
function this.getObjectPositions(recordId, refToCompare)
    local objHandler = this.data[recordId]
    if not objHandler then return end

    return objHandler:positions(refToCompare)
end


---@param groupName string
---@return {x: number, y: number, z: number, dif : number?}[]?
function this.getObjectPositionsByGroupName(groupName, refToCompare)
    local found = false
    local res = {}
    for _, recordId in pairs(this.objectRecordIdsByGroupId[groupName] or {}) do
        local objHandler = this.data[recordId]
        if not objHandler then goto continue end

        local positions = objHandler:positions(refToCompare)
        tableLib.copy(positions, res)

        found = true

        ::continue::
    end

    return found and res or nil
end


---@param recordId string
---@param refId string
---@return {x: number, y: number, z: number}?
function this.getObjectPosition(recordId, refId)
    local objHandler = this.data[recordId]
    if not objHandler then return end

    local ref = objHandler:get(refId)
    if ref then
        return ref.position
    end
end


---@param recordId string
---@return boolean
function this.isContainValidRecordId(recordId)
    local recordData = this.data[recordId]
    return recordData ~= nil and recordData.count ~= 0
end


---@param recordIds string[]
---@return boolean
function this.isContainValidRecordIds(recordIds)
    for _, id in pairs(recordIds or {}) do
        local recordData = this.data[id]
        if recordData and recordData.count ~= 0 then return true end
    end

    return false
end


---@param recordId string
---@param refId string
---@return boolean
function this.isContainRefId(recordId, refId)
    local data = this.data[recordId]
    if not data then return false end
    local ref = data:get(refId)
    return ref ~= nil
end


---@param name string
---@return boolean
function this.isContainGroup(name)
    local nameData = this.objectRecordIdsByGroupId[name]
    return nameData ~= nil and (tableLib.count(nameData) > 0)
end


---@param groupName string
---@param objects table<string, string>
function this.registerGroup(groupName, objects)
    if this.objectRecordIdsByGroupId[groupName] then return end
    this.objectRecordIdsByGroupId[groupName] = objects
    for _, id in pairs(objects) do
        this.groupIdsByObjectRecordId[id] = this.groupIdsByObjectRecordId[id] or {}
        this.groupIdsByObjectRecordId[id][groupName] = groupName
    end
end


---@param groupName string
function this.unregisterGroup(groupName)
    local objects = this.objectRecordIdsByGroupId[groupName]
    if objects then return end

    for id, _ in pairs(objects) do
        if this.groupIdsByObjectRecordId[id] then
            this.groupIdsByObjectRecordId[id][groupName] = nil
        end
        if this.data[id] then
            this.data[id].groups[groupName] = nil
        end
    end

    this.objectRecordIdsByGroupId[groupName] = nil
end


function this.updateGroups()
    for recId, dt in pairs(this.data) do
        local groups = this.groupIdsByObjectRecordId[recId]
        if not groups then goto continue end

        dt.groups = groups

        ::continue::
    end
end


return this