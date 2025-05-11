local self = require('openmw.self')
local core = require('openmw.core')


local function onInactive()
    core.sendGlobalEvent("proximityTool:objectInactive", self)
end


return {
    engineHandlers = {
        onInactive = onInactive,
    },
    eventHandlers = {

    },
}