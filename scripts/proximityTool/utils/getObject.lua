local types = require('openmw.types')

local typeList = {
    types.NPC,
    types.Creature,
    types.Apparatus,
    types.Armor,
    types.Book,
    types.Clothing,
    types.Container,
    types.Door,
    types.Ingredient,
    types.Light,
    types.Lockpick,
    types.Miscellaneous,
    types.Potion,
    types.Probe,
    types.Repair,
    types.Weapon,
    types.Static,
}

return function(id)
    for _, tp in pairs(typeList) do
        local rec = tp.record(id)
        if rec then return rec end
    end
    return nil
end