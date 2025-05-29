local types = require('openmw.types')

local typesWithInventory = {
    [types.NPC] = true,
    [types.Creature] = true,
    [types.Container] = true,
}

local this = {}


---@param object any
---@param itemId string
---@param countUnresolved boolean?
---@return integer?
function this.countOf(object, itemId, countUnresolved, defaultVal)
    if object.recordId == itemId then return object.count or defaultVal end
    if not typesWithInventory[object.type] then return defaultVal end

    local inventory = object.type == types.Container and object.type.inventory(object) or types.Actor.inventory(object)
    if countUnresolved and not inventory:isResolved() then return 1 end

    return inventory:countOf(itemId)
end


return this