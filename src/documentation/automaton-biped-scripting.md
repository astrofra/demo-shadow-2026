# Automaton Biped Scripting Guide

## Overview

This document describes how to script the procedural automaton biped driven by `automaton_controller.lua`.

The controller combines several orthogonal subsystems:

- locomotion on the XZ plane
- in-place rotation by discrete turning steps
- independent arm lock and unlock blending
- object grabbing and releasing per hand
- persistent head and neck look-at
- a blocking action sequence runner

The goal is staged character choreography.
This is not a generic AI system and it is not a physics-driven character controller.

## Module Setup

Create the controller from Lua like this:

```lua
local automaton_controller_lib = require("automaton_controller")

local ctrl = automaton_controller_lib.CreateAutomatonController(scene, "automaton-rig-tpose")
```

Update it once per frame:

```lua
ctrl:Update(dt_sec)
```

Typical integration:

```lua
local automaton_controller_lib = require("automaton_controller")
local ctrl = automaton_controller_lib.CreateAutomatonController(scene, "automaton-rig-tpose")

while running do
	scene:Update(dt)
	ctrl:Update(dt_sec)
end
```

## Node Reference Rules

Most scripting calls use string node references.

The controller resolves references in this order:

1. `Scene.GetNodeEx(path)`
2. the automaton instance `SceneView` by short internal name
3. `Scene.GetNode(name)`

This means the following styles are all supported:

- host scene nodes such as `path_A`
- host scene nodes such as `telephone_receiver`
- absolute scene paths compatible with `Scene.GetNodeEx`
- instance paths such as `automaton-rig-tpose:phone_ear_anchor`
- short internal automaton node names such as `hand_target_A`

Practical recommendation:
use `Scene.GetNodeEx`-style paths whenever possible, especially for authored anchors in the host scene.

## Public API

The controller currently exposes these methods.

### Movement

```lua
ctrl:MoveToNode(target_name)
ctrl:MoveFromNodeToNode(start_name, target_name)

ctrl:RotateToNode(target_name)
ctrl:RotateFromNodeToNode(start_name, target_name)

ctrl:IsMoving()
ctrl:IsAtTarget()
ctrl:IsRotationDone()
ctrl:GetCurrentTargetNodeName()
```

Behavior:

- `MoveToNode` moves the biped toward a target node on the world XZ plane.
- `MoveFromNodeToNode` first places the biped at `start_name`, then starts the move.
- `RotateToNode` rotates in place until the biped faces the target node.
- `RotateFromNodeToNode` first places the biped at `start_name`, then starts the rotation.
- `IsMoving()` only reports movement state, not rotation state.
- `IsAtTarget()` only reports movement completion.
- `IsRotationDone()` reports rotation completion.
- `GetCurrentTargetNodeName()` returns the currently active move or rotate target, or `nil`.

### Arm Locking

```lua
ctrl:PlaceLeftHandOnNode(target_name)
ctrl:PlaceRightHandOnNode(target_name)
ctrl:UnlockLeftHand()
ctrl:UnlockRightHand()
```

Behavior:

- locking a hand blends from free swing to IK hand placement over `1.0` second
- unlocking blends back to procedural walk swing over `1.0` second
- left and right hands are fully independent
- a locked hand keeps following its target until it is explicitly unlocked

### Object Grabbing

```lua
ctrl:GrabNodeWithLeftHand(node_ref)
ctrl:GrabNodeWithRightHand(node_ref)
ctrl:ReleaseLeftHandObject()
ctrl:ReleaseRightHandObject()
```

Behavior:

- one held object maximum per hand
- grab has no distance check
- grab may teleport the object to the hand
- the object snaps immediately to the hand and is then parented to it
- if the hand already holds something, that object is released first
- release restores the current world transform, then reparents to the original parent if still valid
- if the original parent is gone, release detaches the object to world space

Implementation note:
the controller first tries to parent directly to the internal hand node.
If cross-instance parenting does not hold at runtime, it falls back to a host-scene proxy node that follows the hand every frame.

### Look-At

```lua
ctrl:LookAtNode(node_ref)
ctrl:ClearLookAt()
```

Behavior:

- `LookAtNode` blends into a persistent tracking state over `1.0` second
- the target is the target node position, not its orientation
- after the blend, the neck and head keep tracking the target until `ClearLookAt()` is called
- `ClearLookAt()` blends back to the captured rest pose over `1.0` second

Current look distribution:

- neck: `40%`
- head: `60%`

Current angular limits:

- yaw: `+-70 degrees`
- pitch up: `+35 degrees`
- pitch down: `-45 degrees`
- roll: none

The rest pose is captured from the automaton rig when the controller is created.

### Sequence Runner

```lua
ctrl:RunActionSequence(actions)
ctrl:StopActionSequence()
ctrl:IsActionSequenceRunning()
```

Behavior:

- actions are blocking
- the next action starts only when the current one is considered complete
- `StopActionSequence()` only stops the sequence runner itself
- persistent subsystem states are not automatically reset on stop

Examples:

- a locked arm stays locked after the sequence stops
- a held object stays held after the sequence stops
- a look-at target stays active after the sequence stops
- a movement or rotation already started is not cancelled by `StopActionSequence()`

## Action Sequence Format

Canonical action types:

- `move`
- `rotate`
- `lock_arm`
- `unlock_arm`
- `grab`
- `release`
- `look_at`
- `clear_look_at`

The action type normalizer also accepts spaces and hyphens.
For example, `lock arm` and `lock-arm` will be interpreted as `lock_arm`.

### Supported Action Fields

`move`

```lua
{type = "move", target = "path_B"}
{type = "move", start = "path_A", target = "path_B"}
```

`rotate`

```lua
{type = "rotate", target = "path_B"}
{type = "rotate", start = "path_A", target = "path_B"}
```

`lock_arm`

```lua
{type = "lock_arm", side = "left", target = "automaton-rig-tpose:watering_anchor"}
```

`unlock_arm`

```lua
{type = "unlock_arm", side = "left"}
```

`grab`

```lua
{type = "grab", side = "right", target = "telephone_receiver"}
```

`release`

```lua
{type = "release", side = "right"}
```

`look_at`

```lua
{type = "look_at", target = "path_C"}
```

`clear_look_at`

```lua
{type = "clear_look_at"}
```

`side` accepts `left` or `right`.
The implementation lowercases the input, so `Left` and `RIGHT` are also accepted.

### Action Completion Semantics

- `move`: completes when `IsAtTarget()` becomes true
- `rotate`: completes when `IsRotationDone()` becomes true
- `lock_arm`: completes when the blend reaches `1.0`
- `unlock_arm`: completes when the blend reaches `0.0`
- `grab`: completes immediately after the parenting operation
- `release`: completes immediately after the reparenting operation
- `look_at`: completes when the look blend reaches `1.0`
- `clear_look_at`: completes when the look blend reaches `0.0`

## Movement and Rotation Semantics

### Move

`move` is standard locomotion.

Important traits:

- translation happens on the XZ plane only
- the character can turn before stepping forward
- if heading error is large enough, the controller enters a turn-in-place locomotion state
- feet are procedurally planted and swung through the existing leg IK system
- free arms swing automatically while walking unless they are locked

### Rotate

`rotate` is a dedicated in-place turning mode designed for staged motion.

Current implementation details:

- the biped rotates in discrete `10 degree` steps
- each turning step swaps the support foot
- the planted support foot acts as the pivot
- the swing foot is relocated on the ground plane
- there is a short pause between turning steps
- rotation ends when the remaining yaw error is within `1 degree`

This produces a simple robotic compromise:
clear orientation control, visible footwork, and low implementation complexity.

## Persistence Rules

Subsystems are persistent by design.

- movement persists until the current target is reached or another movement command overrides it
- rotation persists until the facing target is reached or another locomotion command overrides it
- a hand lock persists until that hand is unlocked
- a held object persists until that hand releases it
- look-at persists until `ClearLookAt()` is called

This is important when building sequences.
You do not need to repeat persistent commands every frame.

## Direct Calls vs. Sequence Runner

Both styles are valid.

Use direct calls when:

- you are prototyping interactively
- you want manual control from debug keys
- you need immediate one-off reactions

Use `RunActionSequence()` when:

- you want authored choreography
- you want blocking order without hand-written state code
- you are building narrative scenes

Practical recommendation:
avoid mixing ad-hoc direct calls with an active sequence unless you are intentionally overriding the current staged action.

## Example: Simple Direct Scripting

```lua
local automaton_controller_lib = require("automaton_controller")
local ctrl = automaton_controller_lib.CreateAutomatonController(scene, "automaton-rig-tpose")

ctrl:MoveFromNodeToNode("path_A", "path_B")

if ctrl:IsAtTarget() then
	ctrl:RotateToNode("telephone_receiver")
end

if ctrl:IsRotationDone() then
	ctrl:PlaceRightHandOnNode("automaton-rig-tpose:phone_ear_anchor")
end
```

## Example: Narrative Sequence

```lua
local actions = {
	{type = "move", start = "path_A", target = "watering_can_pickup"},
	{type = "rotate", target = "watering_can_pickup"},
	{type = "grab", side = "right", target = "watering_can"},
	{type = "move", target = "plants_A"},
	{type = "lock_arm", side = "right", target = "automaton-rig-tpose:watering_anchor"},
	{type = "look_at", target = "plants_A"},
	{type = "clear_look_at"},
	{type = "unlock_arm", side = "right"},
	{type = "release", side = "right"},
	{type = "move", target = "telephone_area"},
	{type = "rotate", target = "telephone_receiver"},
	{type = "grab", side = "right", target = "telephone_receiver"},
	{type = "lock_arm", side = "right", target = "automaton-rig-tpose:phone_ear_anchor"},
	{type = "look_at", target = "caller_focus_A"}
}

ctrl:RunActionSequence(actions)
```

## Debug State

The controller exposes a compact runtime snapshot through:

```lua
local debug_state = ctrl:GetDebugState()
```

Current fields:

- `state`
- `target`
- `distance_to_target`
- `yaw_error_deg`
- `rotation_target_active`
- `current_speed`
- `gait_drive`
- `support_side`
- `step_progress`
- `step_pause_timer`
- `locomotion_speed`
- `left_hand`
- `right_hand`
- `held_left`
- `held_right`
- `look_target`
- `look_blend`
- `current_action_type`
- `action_index`

This is mainly intended for in-game debug UI and staging.

## Current Constraints

This controller is intentionally simple.

- no pathfinding
- no obstacle avoidance
- no grasp distance validation
- no finger animation
- no drop physics
- no authored animation blending
- no callback system inside the action runner
- no concurrent multi-action scheduling inside one sequence

## Recommended Scene Authoring Workflow

- create clear host-scene path markers for travel points
- create explicit look targets as separate nodes when you want clean gaze control
- create explicit hand anchors near props or body landmarks
- expose detachable props such as the phone receiver as separate nodes
- prefer stable, named anchors over hardcoded offsets in Lua

The controller works best when the scene provides intentional staging nodes.

