local async = require('openmw.async')
local types = require('openmw.types')
local world = require('openmw.world')


local function onObjectActive(object)
    if object.type == types.NPC and object.enabled then
        object:addScript("scripts/proximityTool/objectLocal.lua")
        world.players[1]:sendEvent("addActiveObject", object)
    end
end

local function objectInactive(object)
    world.players[1]:sendEvent("removeActiveObject", object)
end


return {
    engineHandlers = {
        onObjectActive = async:callback(onObjectActive),
    },
    eventHandlers = {
        objectInactive = async:callback(objectInactive),
    },
}