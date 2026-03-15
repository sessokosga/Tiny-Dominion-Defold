# Session State

## Current Context
- **Project**: Tiny Dominion
- **Engine**: Defold (migrating from Construct 3)
- **Current Focus**: Base Architecture and Data Management.

## Completed Tasks
- [x] **Data Layer Migration**: Migrated the TypeScript CastleDB parser to Lua (`logic/data_proxy.lua`).
  - Added support for custom AST decoding (`Duration`, `AmountI`, `ResAmountI`, etc.).
  - Added fast lookups for `buildings`, `resources`, `units`, `boosters`, etc.
  - Adapted the `get_sfx_rule` composite key logic to match CSS-like specificity.
  - Verified logic using tests in `scripts/main.script` and injected `custom_resources = /data/res/` into `game.project`.
- [x] **State Managers Migration**: Migrated `ResourceManager` and `PlayerManager` to Lua (`logic/resource_manager.lua`, `logic/player_manager.lua`).
  - Replaced callback system with a publish/subscribe system using `msg.post` for UI synchronization (`sync_ui`).
  - Integrated `sys.save` and `sys.load` for persistent cross-session state.
  - Linked logically with `data_proxy.lua` to enforce capacities (e.g., `stack_max`).

## Next Steps / Pending
- [ ] Migrate core game loops or rendering logic (to be defined).
- [ ] Set up the UI pipeline (Druid integration noted in `game.project` dependencies).
- [ ] Port the input handling logic.