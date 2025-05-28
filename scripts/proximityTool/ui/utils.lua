local ui = require('openmw.ui')

local this = {}


function this.convertAlign(str, default)
    return ui.ALIGNMENT[str] or (default or ui.ALIGNMENT.End)
end


function this.removeFromContent(content, index)
    local removedEl = table.remove(content, index)
    if not removedEl then return end

    if removedEl.name then
        content.__nameIndex[removedEl.name] = nil
    end

    for i = index, #content do
        local elem = content[i]

        if elem.name then
            content.__nameIndex[elem.name] = i
        end
    end

    return removedEl
end


return this