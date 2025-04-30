---@diagnostic disable: undefined-doc-name
local this = {}

---@type table<string, objectTrackingBD.activeObject.objectHandler> by record id
this.data = {}


---@class objectTrackingBD.activeObject.objectHandler
local objectHandler = {}
objectHandler.__index = objectHandler

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
        ---@class objectTrackingBD.activeObject.objectHandler
        objHandler = setmetatable({}, objectHandler)
        ---@type integer
        objHandler.count = 0
        ---@type string
        objHandler.recordId = object.recordId
        ---@type table<string, any> by object id
        objHandler.objects = {}

        this.data[object.recordId] = objHandler
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


---@param recordId string
---@param refId string
---@return boolean
function this.isContainRefId(recordId, refId)
    local data = this.data[recordId]
    if not data then return false end
    local ref = data:get(refId)
    return ref ~= nil
end


return this