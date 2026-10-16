-- Learned action catalog for the editor. Does not alter the casting path or
-- the indicator rank API. Ambiguous spell families are deliberately separate.
local GRF = GlassRaidFrames
local API = GRF.API
local catalog, byID

function API.ResetClickCastCatalog() catalog, byID = nil, nil end

local function qualifiedID(name, sub)
    local spells = rawget(_G, "C_Spell")
    if not (spells and spells.GetSpellInfo and sub and sub ~= "") then return nil end
    local ok, info = pcall(spells.GetSpellInfo, name .. "(" .. sub .. ")")
    if ok and type(info) == "table" and not API.IsSecret(info.spellID) then return info.spellID end
end

function API.ClickCastCatalog()
    if catalog then return catalog, byID end
    catalog, byID = {}, {}
    local knownFamilies = {}
    for first, ranks in pairs(GRF.IndicatorDefaults.FAMILIES) do
        for order, id in ipairs(ranks) do knownFamilies[id] = { first, order } end
    end
    local groups = {}
    for order, spell in ipairs(API.SpellBookSpells()) do
        local id = spell.spellID
        if not byID[id] and API.SpellKnown(id) then
            local sub, icon = API.SpellSubtext(id), API.SpellTexture(id)
            local family = knownFamilies[id]
            local verified = qualifiedID(spell.name, sub) == id
            -- The name is only a candidate key: every member must also round
            -- trip its distinct localized rank to its exact learned ID.
            local key = family and ("id:" .. family[1]) or (verified and
                ("rank:" .. tostring(spell.skillLine or "") .. ":" .. spell.name .. ":" .. tostring(icon)))
            key = key or ("spell:" .. id)
            local group = groups[key]
            if group and sub and group.subs[sub] then
                key, group = "spell:" .. id, nil -- same-name, same-rank collision
            end
            if not group then
                group = { name = spell.name, icon = icon, ranks = {}, subs = {}, orders = {}, verified = family ~= nil or verified }
                groups[key] = group
                catalog[#catalog + 1] = group
            end
            group.ranks[#group.ranks + 1] = id
            group.orders[id] = family and family[2] or order
            if sub then group.subs[sub] = true end
            byID[id] = group
        end
    end
    for _, group in ipairs(catalog) do
        table.sort(group.ranks, function(a, b) return group.orders[a] < group.orders[b] end)
        group.spell = group.ranks[#group.ranks]
    end
    table.sort(catalog, function(a, b)
        if a.name == b.name then return a.spell < b.spell end
        return a.name < b.name
    end)
    return catalog, byID
end

function API.ClickCastRanks(id)
    local _, map = API.ClickCastCatalog()
    local family = map[id]
    return family and family.ranks or {}, family and family.verified or false
end
