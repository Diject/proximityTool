local async = require('openmw.async')
local types = require('openmw.types')
local world = require('openmw.world')

local supportedObjectTypes = require("scripts.proximityTool.supportedObjectTypes")


local function onObjectActive(object)
    if supportedObjectTypes[object.type] and object.enabled then
        world.players[1]:sendEvent("proximityTool:addActiveObject", object)
    end
end

local function objectInactive(object)
    world.players[1]:sendEvent("proximityTool:removeActiveObject", object)
end


return {
    engineHandlers = {
        onObjectActive = async:callback(onObjectActive),
        onItemActive = async:callback(onObjectActive),
    },
    eventHandlers = {
        ["proximityTool:objectInactive"] = async:callback(objectInactive),
    },
}