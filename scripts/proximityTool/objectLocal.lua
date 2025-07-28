local self = require('openmw.self')
local core = require('openmw.core')


local function onInactive()
    core.sendGlobalEvent("proximityTool:objectInactive", self)
end

local function onActivated()
    core.sendGlobalEvent("proximityTool:objectInactive", self)
end


return {
    engineHandlers = {
        onInactive = onInactive,
        onActivated = onActivated,
    },
    eventHandlers = {

    },
}