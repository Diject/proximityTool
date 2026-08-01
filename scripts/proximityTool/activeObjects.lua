local Actor = require("openmw.types").Actor
local tableLib = require("scripts.proximityTool.utils.table")
local inventoryLib = require("scripts.proximityTool.utils.inventory")
local config = require("scripts.proximityTool.config")
local playerRef = require("openmw.self")
local core = require("openmw.core")

local getHealth = Actor.stats.dynamic.health


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
---@type table<string, any>
objectHandler.objects = {}



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

function objectHandler:remove(refId)
    if self.objects[refId] then
        self.count = self.count - 1
    end
    self.objects[refId] = nil
end

local function calcDistance(obj1, obj2)
    return (obj1.position - obj2.position):length()
end

---@return {object: any, position : any, dif : number?}[]
function objectHandler:positions(refObject, itemId, withoutDead)
    local ret = {}
    for id, object in pairs(self.objects) do
        if object:isValid() then
            if not withoutDead or (Actor.objectIsInstance(object) and getHealth(object).current > 0) then
                local posData = this.getObjectPositionData(object, refObject, itemId)
                if posData then
                    table.insert(ret, posData)
                end
            end
        else
            self.objects[id] = nil
            self.count = self.count - 1
        end
    end
    return ret
end


---@return {object: any, position : any, dif : number?}?
function objectHandler:closestPosition(refObject, itemId, withoutDead)

    local position, dif, obj = self:closestPositionOpt(refObject, itemId, withoutDead)
    if not position then return end

    return {object = obj, position = position, dif = dif}
end


---@return any? position
---@return number? distance
---@return any? object
function objectHandler:closestPositionOpt(refObject, itemId, withoutDead)
    local position
    local dist = math.huge
    local obj

    for id, object in pairs(self.objects) do
        if object:isValid() then
            if not withoutDead or (Actor.objectIsInstance(object) and getHealth(object).current > 0) then
                local _, pos, dif = this.getObjectPositionDataUnpacked(object, refObject, itemId)
                if pos and (dif or math.huge) < dist then
                    position = pos
                    dist = dif ---@diagnostic disable-line: cast-local-type
                    obj = object
                end
            end
        else
            self.objects[id] = nil
            self.count = self.count - 1
        end
    end

    return position, dist, obj
end


---@return {object: any, position : any, dif : number?}?
function this.getObjectPositionData(object, refObject, itemId, withoutDead)
    if not object then return end
    if object:isValid() and object.enabled and object.cell
            and playerRef.cell:isInSameSpace(object)
            and (not withoutDead or (Actor.objectIsInstance(object) and getHealth(object).current > 0)) then

        if not itemId or inventoryLib.countOf(object, itemId, true, 1) > 0 then
            return {
                object = object,
                position = object.position,
                dif = refObject and calcDistance(refObject, object)
            }
        end

    end
end


---@return any? object
---@return any? position
---@return number? dif
function this.getObjectPositionDataUnpacked(object, refObject, itemId, withoutDead)
    if not object then return end
    if object:isValid() and object.enabled and object.cell
            and playerRef.cell:isInSameSpace(object)
            and (not withoutDead or (Actor.objectIsInstance(object) and getHealth(object).current > 0)) then

        if not itemId or inventoryLib.countOf(object, itemId, true, 1) > 0 then
            return object, object.position, refObject and calcDistance(refObject, object) or nil
        end

    end
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


function this.remove(refId, recordId)
    local objHandler = this.data[recordId]
    if not objHandler then return end
    objHandler:remove(refId)
    if objHandler.count == 0 then
        this.data[recordId] = nil
    end
end


---@param recordId string
---@return {object: any, position : any, dif : number?}[]?
function this.getObjectPositions(recordId, refToCompare, itemId, withoutDead)
    local objHandler = this.data[recordId]
    if not objHandler then return end

    return objHandler:positions(refToCompare, itemId, withoutDead)
end


---@param recordId string
---@return {object: any, position : any, dif : number?}?
function this.getClosestObjectPosition(recordId, refToCompare, itemId, withoutDead)
    local objHandler = this.data[recordId]
    if not objHandler then return end

    return objHandler:closestPosition(refToCompare, itemId, withoutDead)
end


---@param groupName string
---@return {object: any, x: number, y: number, z: number, dif : number?}[]?
function this.getObjectPositionsByGroupName(groupName, refToCompare, itemId, withoutDead)
    local found = false
    local res = {}
    for _, recordId in pairs(this.objectRecordIdsByGroupId[groupName] or {}) do
        local objHandler = this.data[recordId]
        if not objHandler or objHandler.count == 0 then goto continue end

        local positions = objHandler:positions(refToCompare, itemId, withoutDead)
        tableLib.add(positions, res)

        found = true

        ::continue::
    end

    return found and res or nil
end


---@param groupName string
---@return {object: any, position : any, dif : number?}[]
function this.getClosestObjectPositionsByGroupName(groupName, refToCompare, itemId, withoutDead)
    local res = {}
    for _, recordId in pairs(this.objectRecordIdsByGroupId[groupName] or {}) do
        local objHandler = this.data[recordId]
        if not objHandler or objHandler.count == 0 then goto continue end

        local position = objHandler:closestPosition(refToCompare, itemId, withoutDead)
        if position then
            table.insert(res, position)
        end

        ::continue::
    end

    return res
end


---@param groupName string
---@return {object: any, position : any, dif : number?}?
function this.getClosestObjectPositionByGroupName(groupName, refToCompare, itemId, withoutDead)
    local position
    local dist = math.huge
    local object
    for _, recordId in pairs(this.objectRecordIdsByGroupId[groupName] or {}) do
        local objHandler = this.data[recordId]
        if not objHandler or objHandler.count == 0 then goto continue end

        local pos, d, obj = objHandler:closestPositionOpt(refToCompare, itemId, withoutDead)
        if pos and (d or math.huge) < dist then
            position = pos
            dist = d ---@diagnostic disable-line: cast-local-type
            object = obj
        end

        ::continue::
    end

    if position then
        return {object = object, position = position, dif = dist}
    end
end


---@param referenceList any[]
---@return {object: any, position : any, dif : number?}?
function this.getClosestReferencePosition(referenceList, refObject, itemId, withoutDead)
    local position
    local dist = math.huge
    local object

    for id, ref in pairs(referenceList) do
        if ref:isValid() then
            if not withoutDead or (Actor.objectIsInstance(ref) and getHealth(ref).current > 0) then
                local obj, pos, d = this.getObjectPositionDataUnpacked(ref, refObject, itemId)
                if pos and (d or math.huge) < dist then
                    position = pos
                    dist = d ---@diagnostic disable-line: cast-local-type
                    object = obj
                end
            end
        end
    end

    if position then
        return {object = object, position = position, dif = dist}
    end
end


---@param recordId string
---@param refId string
---@return {x: number, y: number, z: number}?
function this.getObjectPosition(recordId, refId)
    local objHandler = this.data[recordId]
    if not objHandler then return end

    local ref = objHandler:get(refId)
    if ref and ref.enabled and ref.cell and playerRef.cell:isInSameSpace(ref) then
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


---@param refs any[]
---@return boolean
function this.isCointainValidRefs(refs)
    for _, ref in pairs(refs) do
        local res = this.isContainRefId(ref.recordId, ref.id)
        if res then return true end
    end
    return false
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


---@params recordId string
---@return any[]?
function this.getValidObjects(recordId)
    local data = this.data[recordId]
    if not data then return end

    local out = {}
    for _, obj in pairs(data.objects) do
        if obj:isValid() and obj.enabled and obj.cell and playerRef.cell:isInSameSpace(obj) then
            table.insert(out, obj)
        end
    end

    return out
end


return this