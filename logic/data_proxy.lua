local M = {}

local db = nil
local sheets = {} -- map of sheet_name -> dict(id -> entry)

-- Utility to resolve enums
local function decode_enum(type_str, value)
    if not type_str then return tostring(value) end
    local _, _, variants_str = string.find(type_str, ":(.*)")
    if not variants_str then return tostring(value) end
    local variants = {}
    for variant in string.gmatch(variants_str, "([^,]+)") do
        table.insert(variants, variant)
    end
    -- In Lua, arrays are 1-indexed, but CastleDB enum value is 0-indexed
    return variants[value + 1] or tostring(value)
end

-- Custom AST decoding
local function decode_custom_ast(type_name, value)
    if type(value) ~= "table" then
        error("Expected custom " .. type_name .. " as array")
    end

    local custom
    for _, t in ipairs(db.customTypes) do
        if t.name == type_name then
            custom = t
            break
        end
    end

    if not custom then
        error("Unknown custom type: " .. type_name)
    end

    -- In Lua, first element of array is at index 1, but CastleDB's JSON arrays might be 0-indexed in JS.
    -- sys.load_resource JSON decode parses arrays to 1-indexed tables. So value[1] is the case index.
    local case_index = value[1] -- 0-based in CastleDB
    local c = custom.cases[case_index + 1]
    
    if not c then
        error("Invalid case index " .. tostring(case_index) .. " for custom " .. type_name)
    end

    local args = {}
    for i, arg_meta in ipairs(c.args) do
        args[arg_meta.name] = value[i + 1]
    end

    return { type = type_name, case = c.name, args = args }
end

local function duration_to_seconds(ast)
    if ast.type ~= "Duration" then
        error("duration_to_seconds expects Duration")
    end
    local v = ast.args.v
    if ast.case == "sec" then return v
    elseif ast.case == "min" then return v * 60
    elseif ast.case == "hour" then return v * 3600
    elseif ast.case == "day" then return v * 86400
    else return v
    end
end

local function decode_amount(type_name, raw)
    local ast = decode_custom_ast(type_name, raw)
    if ast.case == "fixed" then
        return { kind = "fixed", value = ast.args.v }
    elseif ast.case == "range" then
        return { kind = "range", min = ast.args.min, max = ast.args.max }
    end
    error("Unknown " .. type_name .. " case: " .. tostring(ast.case))
end

local function decode_res_amount_i(raw)
    local ast = decode_custom_ast("ResAmountI", raw)
    return {
        resourceId = ast.args.resource,
        amount = decode_amount("AmountI", ast.args.amount)
    }
end

local function decode_booster_effect(line)
    local ast = decode_custom_ast("BoosterEffect", line.effect)
    if ast.case == "timeReduce" then
        return { kind = "timeReduce", deltaSec = duration_to_seconds(decode_custom_ast("Duration", ast.args.delta)) }
    elseif ast.case == "speed" then
        return { kind = "speed", mult = ast.args.mult, durationSec = duration_to_seconds(decode_custom_ast("Duration", ast.args.duration)) }
    elseif ast.case == "resourcePack" then
        local contents = {}
        for _, pack in ipairs(line.pack_contents or {}) do
            table.insert(contents, decode_res_amount_i(pack.content))
        end
        return { kind = "resourcePack", contents = contents }
    end
    error("Unknown BoosterEffect case: " .. tostring(ast.case))
end

local function decode_audio_type(raw)
    local ast = decode_custom_ast("AudioType", raw)
    if ast.case == "SFX" then return { kind = "SFX", var = ast.args["var"] }
    elseif ast.case == "BGM" then return { kind = "BGM" }
    end
    error("Unknown AudioType case: " .. tostring(ast.case))
end

local function decode_unit_kind(raw)
    local ast = decode_custom_ast("UnitKind", raw)
    if ast.case == "Villager" or ast.case == "Enemy" or ast.case == "Neutral" then
        return ast.case
    end
    error("Unknown UnitKind case: " .. tostring(ast.case))
end

local function decode_sfx_trigger_mode(raw)
    local ast = decode_custom_ast("SFXTriggerMode", raw)
    if ast.case == "Always" then return { kind = "Always" }
    elseif ast.case == "Random" then return { kind = "Random", chance = ast.args.chance }
    end
    error("Unknown SFXTriggerMode case: " .. tostring(ast.case))
end

--- Initializes the data proxy by loading and parsing the data.cdb file
function M.init()
    local cdb_data = sys.load_resource("/data/res/data.cdb")
    if not cdb_data then
        print("[data_proxy] Failed to load /data/res/data.cdb")
        return false
    end
    
    db = json.decode(cdb_data)
    sheets = {}

    for _, sheet in ipairs(db.sheets) do
        local sheet_dict = {}
        
        -- Create column lookup
        local col_map = {}
        for _, col in ipairs(sheet.columns) do
            col_map[col.name] = col
        end

        for _, line in ipairs(sheet.lines) do
            if sheet.name == "resources" then
                sheet_dict[line.id] = {
                    id = line.id,
                    name = line.name,
                    category = decode_enum(col_map["category"] and col_map["category"].typeStr, line.category),
                    icon = line.icon or "",
                    stack_max = line.stack_max or 9999
                }
            elseif sheet.name == "buildings" then
                local costs = {}
                if line.costs then
                    for _, c in ipairs(line.costs) do
                        table.insert(costs, decode_res_amount_i(c.cost))
                    end
                end
                
                sheet_dict[line.id] = {
                    id = line.id,
                    name = line.name,
                    desc = line.desc or "",
                    type = decode_enum(col_map["type"] and col_map["type"].typeStr, line.type),
                    footprint_w = line.footprint_w,
                    footprint_h = line.footprint_h,
                    allowed_ground = decode_enum(col_map["allowed_ground"] and col_map["allowed_ground"].typeStr, line.allowed_ground),
                    costs = costs,
                    buildTimeSec = duration_to_seconds(decode_custom_ast("Duration", line.build_time)),
                    workersMax = line.workers_max or 0,
                    buildersMax = line.builders_max or 2,
                    production = line.production or "wood",
                    sprite_anim = line.sprite_anim,
                    ui_icon = line.ui_icon or ""
                }
            elseif sheet.name == "trees" then
                sheet_dict[line.id] = {
                    id = line.id,
                    name = line.name,
                    resource_yield = line.resource_yield,
                    amount_per_harvest = line.amount_per_harvest,
                    harvest_time_sec = duration_to_seconds(decode_custom_ast("Duration", line.harvest_time_sec)),
                    total_harvests = line.total_harvests,
                    regrow_time = duration_to_seconds(decode_custom_ast("Duration", line.regrow_time)),
                    sprite_frame = line.sprite_frame,
                    destroy_after_yield = line.destroy_after_yield ~= false
                }
            elseif sheet.name == "boosters" then
                local buy_cost = {}
                if line.buy_cost then
                    for _, c in ipairs(line.buy_cost) do
                        table.insert(buy_cost, decode_res_amount_i(c.cost))
                    end
                end
                
                sheet_dict[line.id] = {
                    id = line.id,
                    name = line.name,
                    effect = decode_booster_effect(line),
                    stack_max = line.stack_max or 99,
                    rarity = decode_enum(col_map["rarity"] and col_map["rarity"].typeStr, line.rarity),
                    buy_cost = buy_cost
                }
            elseif sheet.name == "audio" then
                sheet_dict[line.id] = {
                    id = line.id,
                    file = line.file,
                    name = line.name,
                    type = decode_audio_type(line.type),
                    volume = line.volume or 0.8
                }
            elseif sheet.name == "playlist" then
                local tracks = {}
                if line.tracks then
                    for _, track in ipairs(line.tracks) do
                        table.insert(tracks, track.id)
                    end
                end
                sheet_dict[line.id] = {
                    id = line.id,
                    name = line.name,
                    tracks = tracks
                }
            elseif sheet.name == "unit" then
                sheet_dict[line.id] = {
                    id = line.id,
                    name = line.name,
                    kind = decode_unit_kind(line.kind),
                    max_hp = line.max_hp or 10,
                    max_speed = line.max_speed or 50
                }
            elseif sheet.name == "sfx" then
                if line.enabled ~= false then
                    local target = decode_enum(col_map["target"] and col_map["target"].typeStr, line.target)
                    local rule = {
                        id = line.id,
                        unitId = line.unit or nil,
                        anim = line.anim,
                        frame = line.frame or 0,
                        soundId = line.sound,
                        target = target,
                        mode = decode_sfx_trigger_mode(line.mode)
                    }
                    local unit_key = rule.unitId or "*"
                    local key = string.format("%s|%s|%d|%s", unit_key, rule.anim, rule.frame, target)
                    sheet_dict[key] = rule
                end
            else
                -- Generic processing for other sheets to index by id if possible
                if line.id then
                    sheet_dict[line.id] = line
                end
            end
        end
        sheets[sheet.name] = sheet_dict
    end

    print("[data_proxy] Initialized.")
    return true
end

--- Get a specific entry from a sheet by its ID
-- @param sheet_name The name of the sheet
-- @param id The ID of the entry to get
-- @return The entry table, or nil if not found
function M.get_entry(sheet_name, id)
    if not sheets[sheet_name] then return nil end
    return sheets[sheet_name][id]
end

--- Get all entries of a sheet
-- @param sheet_name The name of the sheet
-- @return The sheet dictionary table
function M.get_sheet(sheet_name)
    return sheets[sheet_name] or {}
end

--- Helper specifically for SFX rules since their keys are composite
function M.get_sfx_rule(unitId, animationName, frame, targetType)
    local sfx_sheet = sheets["sfx"]
    if not sfx_sheet then return nil end
    
    local parts = {}
    for part in string.gmatch(animationName, "[^_]+") do
        table.insert(parts, part)
    end
    
    local targets_to_try = {targetType, "Any"}
    
    for _, t in ipairs(targets_to_try) do
        for _, part in ipairs(parts) do
            local preciseKey = string.format("%s|%s|%d|%s", unitId, part, frame, t)
            if sfx_sheet[preciseKey] then return sfx_sheet[preciseKey] end
        end
    end
    
    for _, t in ipairs(targets_to_try) do
        for _, part in ipairs(parts) do
            local genericKey = string.format("*|%s|%d|%s", part, frame, t)
            if sfx_sheet[genericKey] then return sfx_sheet[genericKey] end
        end
    end
    
    return nil
end

return M
