local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')


local this = {}

---@type table<string, objectTrackingBD.elementSafeContainer>
this.containers = {}
---@type table<string, objectTrackingBD.elementSafeContainer>
this.destroyedContainers = {}


this.commandType = {
    create = 1,
    update = 2,
    destroy = 3,
    func = 4,
}


---@class objectTrackingBD.elementSafeContainer
local containerStruct = {}

containerStruct.__index = containerStruct

containerStruct.element = nil
containerStruct.id = nil

---@type {type : integer, data : any}[] 1 - create, 2 - update, 3 - destroy()
containerStruct.commandQueue = nil

containerStruct.valid = true

---@return boolean?
function containerStruct:updateState()
    if #self.commandQueue == 0 then return end

    local commandData = self.commandQueue[1]
    if commandData.type == this.commandType.create then
        self.commandQueue = {}

        if commandData.data then
            self.element = ui.create(commandData.data)
        end

        return true
    elseif commandData.type == this.commandType.destroy then
        self:forceDestroy()
    elseif commandData.type == this.commandType.update then
        if self.element then
            self.element:update()
        end
    elseif commandData.type == this.commandType.func then
        commandData.data(self.element)
    end
    table.remove(self.commandQueue, 1)
    return true
end


function containerStruct:create(layout)
    if not layout then return end
    if self.element then
        self:addCommand(this.commandType.destroy)
    end
    self:addCommand(this.commandType.create, layout)
end


function containerStruct:update()
    self:addCommand(this.commandType.update)
end


function containerStruct:destroy()
    table.insert(this.destroyedContainers, self)
    self.valid = false
end


function containerStruct:forceDestroy()
    if self.element then
        self.element:destroy()
        self.element = nil
    end
    self.valid = false
end

function containerStruct:addCommand(commandType, data)
    table.insert(self.commandQueue, {type = commandType, data = data})
end





---@param id string
---@return objectTrackingBD.elementSafeContainer
function this.new(id)
    local container = this.containers[id]
    if container then
        container:destroy()
    end

    container = setmetatable({}, containerStruct)
    container.id = id
    container.valid = true
    container.commandQueue = {}

    this.containers[id] = container

    return container
end


function this.update()
    for _, container in pairs(this.destroyedContainers) do
        container:forceDestroy()
    end
    this.destroyedContainers = {}

    for id, container in pairs(this.containers) do
        container:updateState()
    end
end


return this