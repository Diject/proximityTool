local ui = require('openmw.ui')

local this = {}


function this.convertAlign(str, default)
    return ui.ALIGNMENT[str] or (default or ui.ALIGNMENT.End)
end


return this