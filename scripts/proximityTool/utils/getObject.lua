local common = require("scripts.proximityTool.common")

return function(id)
    for tp, _ in pairs(common.supportedObjectTypes) do
        local rec = tp.record(id)
        if rec then return rec end
    end
    return nil
end