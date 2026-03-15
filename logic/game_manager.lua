local M = {}

M.entities = {
    villager = {},
    building = {},
    resource = {},
    tree = {}
}

-- Fonction pour centraliser la création et l'enregistrement
function M.create_entity(factory_url, position, rotation, properties, scale, entity_type)
    local id = factory.create(factory_url, position, rotation, properties, scale)
    if entity_type then
        M.register_entity(entity_type, id)
    end
    return id
end

-- Enregistre une entité (appelé dans le init() des scripts)
function M.register_entity(entity_type, id)
    if not M.entities[entity_type] then
        M.entities[entity_type] = {}
    end
    -- Utilisation de l'ID comme clé pour un accès rapide
    M.entities[entity_type][id] = true
end

-- Désenregistre une entité (appelé dans le final() des scripts)
function M.unregister_entity(entity_type, id)
    if M.entities[entity_type] then
        M.entities[entity_type][id] = nil
    end
end

-- Callback global pour un bâtiment terminé
function M.on_building_completed(building_id)
    print("[GameManager] Building finished: " .. tostring(building_id))
    
    -- Notifier les villageois de l'achèvement d'un bâtiment
    for villager_id, _ in pairs(M.entities.villager) do
        msg.post(villager_id, "building_completed", { building_id = building_id })
    end
end

-- Pour usage futur : trouver la ressource la plus proche
function M.get_nearest_resource(pos, resource_type_id, exclude_id)
    -- Logique à implémenter plus tard
    return nil
end

-- Pour usage futur : trouver l'arbre le plus proche
function M.get_nearest_tree(pos, resource_type_id)
    -- Logique à implémenter plus tard
    return nil
end

return M
