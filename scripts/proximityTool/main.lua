local async = require('openmw.async')
local types = require('openmw.types')
local world = require('openmw.world')

local common = require("scripts.proximityTool.common")


local function onObjectActive(object)
    if common.supportedObjectTypes[object.type] and object.enabled then
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