# Astronaut Wandering Animations

## The main idea

Tiny cosmonaut, big night forest, harvesting radio waves, slow ritual movement.

The goal is not "NPC AI". The goal is staged wandering:
the little astronaut drifts around a home point, traces a star-like pattern,
always comes back to center, then picks another branch and goes again.

So this is a choreography system first, and a behavior system second.

The story is that he's chasing radio waves from space, as told in the original "Cosmowave" demo trailer : 

> My job? To capture emissions.
> Signals from outer space.

## Core idea

We give the astronaut:

- one center point (node name: `path_origin`)
- four or five branch points around it (`path_0` ... `path_4`)
- a finite state machine
- a clean separation between turning and walking
- no animation blending (not available in the engine)

Loop shape:

`center -> turn -> walk to branch -> idle -> turn back -> walk to center -> idle -> pick another branch`

Important rule:
the character never turns and walks at the same time.

## Scene setup

Author the motion path directly in the scene with locator nodes.

The setup is already live in `assets/main_scenery.scn`:

- animated actor node: `astronaut`
- center point: `path_origin`
- branch points: `path_0` ... `path_4`

So the implementation does not need to invent a path system anymore.
It just needs to read the scene and use what is there.

Why scene nodes?
Because this keeps the choreography editable without opening Lua every time we want to move the star pattern around.

Astronaut & path nodes system coordinates:
- Astronaut's left arm is +X
- Astronaut's back is +Z
- Path nodes orientation does not matter, it is defined by the direction of the vector (`origin -> path_n`)

## Runtime controller

Make a dedicated controller for the astronaut.
Something in the spirit of `AstronautWanderController`.

It should own:

- the astronaut node
- the center anchor
- the list of branch anchors
- the current target anchor
- the previous branch index
- the current FSM state
- the current playing animation ref
- movement speed
- turn speed or turn step
- facing tolerance
- arrival tolerance
- optional small idle timers

Useful extra bits for the real setup:

- a cached table of branch node names
- a tiny mapping between FSM states and animation names

The controller gets updated once per frame from the main loop.

## FSM

### `IdleAtCenter`

The astronaut is parked at the center point and plays `idle`.

After a short pause, switch to `ChooseNextBranch`.

### `ChooseNextBranch`

Pick one branch point randomly.

Rule:
do not pick the same branch twice in a row.

Then switch to `TurnToBranch`.

### `TurnToBranch`

Rotate in place until the astronaut faces the chosen branch.

Play:
- `turn_left` if the shortest turn is left
- `turn_right` if the shortest turn is right

No translation here.
Pure turn state.

When the facing error is small enough, switch to `WalkToBranch`.

### `WalkToBranch`

Move toward the chosen branch.

Play:
- `walk`

No turning while walking in v1.
The heading should already be valid when entering the state.

When close enough to the branch, snap cleanly if needed and switch to `IdleAtBranch`.

### `IdleAtBranch`

Small beat at destination.
Play:
- `idle`

Then switch to `TurnToCenter`.

### `TurnToCenter`

Same logic as `TurnToBranch`, but target is now the center anchor.

Play:
- `turn_left` or `turn_right`

When aligned, switch to `WalkToCenter`.

### `WalkToCenter`

Move back to center.

Play:
- `walk`

When close enough, finish cleanly and switch back to `IdleAtCenter`.

And the loop lives forever.

## Motion rules

This should be gameplay-driven motion, not root-motion-driven motion.

That means:

- turning changes rotation only
- walking changes position only
- state transitions decide when one stops and the other starts

This keeps the logic readable and avoids weird overlap between clip motion and scripted motion.

For v1, use:

- a facing tolerance so we do not over-rotate forever
- an arrival tolerance so we do not jitter near the target
- a clean snap when the target is basically reached

The turn clips already represent a fixed turning step visually.
That is fine for now.
We do not need clip-perfect angular quantization in the first pass.

## Animation mapping

Actual animation names to use on the `astronaut` node instance:

- `idle`
- `walk`
- `turn_left`
- `turn_right`
- `crouch_walk` (reserved for later)

Important detail:
the source files on disk are still things like `assets/anims/rifle_walk/rifle_walk.scn`
and `assets/anims/cosmonaut_master.scn`, but when driving the instance animation from the
main scene we should use the logical animation names exposed on the node:
`idle`, `walk`, `turn_left`, `turn_right`, `crouch_walk`.

V1 mapping is simple:

- idle states -> `idle`
- walk states -> `walk`
- left turn states -> `turn_left`
- right turn states -> `turn_right`

No blending required for the first implementation.
Just stop the current anim and play the one that matches the new state.

That keeps the system easy to debug before adding polish.

## Integration notes

Hook the controller after the scene is loaded and all nodes are available.

Expected flow:

- find node `astronaut`
- find `path_origin`
- find `path_0` ... `path_4`
- create controller
- call `controller:Update(scene, dt)` every frame

Keep it isolated from:

- walkman interaction
- camera logic
- DOF logic
- environment effects

This is a self-contained actor system.

## Validation checklist

The feature is good when:

- the astronaut starts at center and idles correctly
- it picks one branch and reaches it reliably
- it always returns to center before picking another branch
- branch choice feels random, but never repeats immediately
- it never rotates and walks at the same time
- animation always matches the active state
- there is no visible jitter at arrival
- there is no weird micro-turn spam near the target direction
- missing anchors fail clearly
- missing anim names fail clearly

Also test with:

- 4 branch points
- 5 branch points
- very small turns
- very large turns
- missing `path_4`, to make sure the system still works with only 4 branches

## Known risks / boring but important stuff

Keep this implementation lean.

No hardcoded fallback path system.
No giant defensive wrapper around scene lookup.
No "maybe this is missing, maybe that is missing, maybe we should recover anyway" maze.

If the scene is authored correctly, the controller runs.
If the scene is authored incorrectly, we fix the scene.

The only thing worth keeping in code is a minimal amount of clarity:
- use the real node names
- use the real animation names
- keep the control flow readable

## Later upgrades

Not for v1, but easy to imagine next:

- animation crossfades
- weighted branch choice
- per-anchor idle duration
- crouch-walk variant
- exact turn-step quantization based on clip timing
- little head or body offsets for extra life
- obstacle avoidance if the choreography ever needs it

For now, keep it simple, readable, and rock solid.
