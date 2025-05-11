local async = require('openmw.async')
local types = require('openmw.types')
local world = require('openmw.world')

local common = require("scripts.proximityTool.common")


local function onObjectActive(object)
    if common.supportedObjectTypes[object.type] and object.enabled then
        object:addScript("scripts/proximityTool/objectLocal.lua")
        world.players[1]:sendEvent("proximityTool:addActiveObject", object)
    end
end

local function objectInactive(object)
    world.players[1]:sendEvent("proximityTool:removeActiveObject", object)
end


return {
    engineHandlers = {
        onObjectActive = async:callback(onObjectActive),
    },
    eventHandlers = {
        ["proximityTool:objectInactive"] = async:callback(objectInactive),
    },
}