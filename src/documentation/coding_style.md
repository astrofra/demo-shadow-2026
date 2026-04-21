# Coding Style

## Functional over OOP

Prefer plain global functions over Lua OOP (module tables with methods).
State is held in local variables declared in `main.lua` alongside the other scene state.

**Preferred**
```lua
function aurora_draw(view_id, dt, aurora_model, aurora_shader, aurora_uniforms, aurora_render_state, aurora_time)
    -- ...
    return aurora_time
end
```

**Avoided**
```lua
local M = {}
function M:draw(view_id, dt) ... end
return M
```

## Long signatures, explicit dependencies

All dependencies (models, shaders, uniforms, render states, time accumulators) are passed
explicitly as function arguments. Nothing is hidden in upvalues or module-level state.
This makes the data flow visible from the call site in `main.lua`.

## Return tuples for mutable state

Value-type state that changes each frame (timers, counters) is returned from the update/draw
function so the caller owns it. Reference-type state (uniforms tables, particle tables) is
mutated in place and the same reference is returned for consistency.

```lua
aurora_time = aurora_draw(view_id, dt, aurora_model, shader_for_aurora,
                          aurora_uniforms, aurora_render_state, aurora_time)
```

## Comments

All comments are written in English.
