# Music-Reactive Boids Neural System

## Goal

Implement a flock of bird-like boids whose trajectories progressively adapt to the
current song. The runtime side stays in Lua. Audio analysis is computed offline by a
Python script and loaded at demo startup, then sampled in real time from the current
song clock.

The first visual target is intentionally simple: each bird is a quad oriented along its
velocity vector. Shape design, wing animation and species styling are out of scope for
the first pass.

## References

- Craig Reynolds style boids: local separation, alignment and cohesion forces.
- Michel Bret / Anyflo as a conceptual reference: procedural animation, trajectory
  definitions, process-first behavior, and interactive visual feedback.
- The existing project style in [`coding_style.md`](coding_style.md): plain Lua
  functions, explicit dependencies, caller-owned state and English comments.

## Core Idea

Each boid is still driven by classic flocking forces, but the weights and steering
intentions are modulated by a tiny neural controller of roughly ten neurons. The neural
state evolves slowly over time from perceived musical features rather than reacting as a
raw oscilloscope.

The system has four layers:

1. Offline Python audio analysis creates a compact time-indexed table per song.
2. Lua samples the current song analysis using `song_player_get_elapsed_seconds`.
3. A small recurrent neural network updates a global flock mood and optional per-boid
   variation.
4. Boids use the neural outputs to adjust steering, speed, altitude, grouping and
   turbulence.

The result should read as a flock listening to the music: dense and nervous on intense
sections, loose and gliding on ambient sections, with gradual behavioral transitions.

## Resolved Design Decisions

- The flock is global to the demo, not attached to a single scene section.
- The flock volume is derived from the particle bounding box. It keeps the particle
  box center, uses `4.0x` X span, `2.0x` Z span, and shifts its Y floor upward by
  `50%` of the particle box height before doubling the Y height toward `Y+` only.
- Learned and evolved neural weights are kept after each song ends. When a song is
  replayed during the same demo session, it resumes from its last evolved controller
  profile.
- Neural visualization is a debug-only Dear ImGui overlay, toggled on and off with the
  `TAB` key.
- The Python analysis script writes Lua directly. There is no JSON intermediary in the
  runtime path.

## Audio Analysis

### Runtime Synchronization

The demo already maintains a global song clock in `walkman.lua`. Runtime sampling should
use:

```lua
local song_time = song_player_get_elapsed_seconds(song_player)
local current_song = song_player_get_current_song(song_player)
local audio_frame = music_analysis_sample(music_analysis, current_song.id, song_time)
```

The playback code advances the clock using a capped frame step, so the analysis sampler
should interpolate between precomputed frames instead of assuming exact frame hits.

### Python Output

Add a new script such as:

```text
src/bin/tools/build_music_analysis.py
```

Suggested output:

```text
src/music_analysis.lua
```

The script writes this Lua file directly. The file should be generated and required at
runtime:

```lua
local music_analysis = require("music_analysis")
```

Proposed generated shape:

```lua
-- this file is generated, do not edit manually

local music_analysis = {
    sample_rate_hz = 20,
    features = {
        "energy",
        "onset",
        "brightness",
        "bass",
        "mid",
        "treble",
        "flatness",
        "zcr",
        "tempo_phase",
        "chroma_flux",
    },
    songs = {
        cosmowave_chaosnet_willbe = {
            duration_sec = 124.718095,
            frames = {
                {0.18, 0.00, 0.45, 0.55, 0.33, 0.21, 0.09, 0.12, 0.00, 0.03},
                {0.19, 0.04, 0.46, 0.54, 0.35, 0.23, 0.10, 0.13, 0.08, 0.05},
            },
        },
    },
}

return music_analysis
```

All feature values should be normalized to `0..1` by the Python script. Store the feature
order once and keep each frame as a packed numeric array to reduce Lua table overhead.

### Feature Candidates

SoX is already bundled and useful for build-time probing, format conversion and coarse
statistics. The local SoX 14.4.2 binary exposes:

- `stats [-b bits|-x bits|-s scale] [-w window-time]` for windowed signal statistics.
- `stat [ -s N ] [ -rms ] [-freq] [ -v ] [ -d ]` for older summary statistics and rough
  frequency information.
- `spectrogram` for PNG inspection and debug images, with control over windowing,
  frequency axis, dynamic range and output size.

Librosa is better suited for the per-frame control data because it returns arrays that
can be normalized and exported directly. The project already uses librosa in
`src/bin/tools/propose_song_sequence.py` for global embeddings, including MFCC, chroma,
spectral contrast, tonnetz, spectral centroid, bandwidth, rolloff, flatness, zero
crossing rate, RMS and tempo.

Recommended first-pass features:

- `energy`: RMS loudness, smoothed and normalized per track.
- `onset`: onset strength envelope, used for bursts and quick turns.
- `brightness`: spectral centroid or rolloff.
- `bass`, `mid`, `treble`: log-frequency band energies.
- `flatness`: noisy versus tonal texture.
- `zcr`: noisiness and percussive edge.
- `tempo_phase`: beat phase accumulator derived from beat tracking.
- `chroma_flux`: harmonic movement between adjacent chroma frames.

Avoid sending too many raw features to Lua. The Python script should reduce them to a
small, stable perceptual vector that has obvious motion meaning.

## Boids Model

### State

Each boid keeps plain numeric state:

```lua
{
    pos = hg.Vec3(),
    vel = hg.Vec3(),
    acc = hg.Vec3(),
    seed = hg.Vec3(),
    wing_phase = 0.0,
    neural_bias = 0.0,
}
```

Flock state:

```lua
{
    bounds = {min = hg.Vec3(), max = hg.Vec3()},
    center = hg.Vec3(),
    target = hg.Vec3(),
    neurons = {},
    neuron_links = {},
    debug = false,
}
```

The boid bounds are computed from `particles.boundaries`:

```lua
local particle_height = particle_bounds.max.y - particle_bounds.min.y
local y_offset = particle_height * 0.5
local boid_min_y = particle_bounds.min.y + y_offset
local boid_max_y = boid_min_y + particle_height * 2.0
local particle_center_x = (particle_bounds.min.x + particle_bounds.max.x) * 0.5
local particle_half_x = (particle_bounds.max.x - particle_bounds.min.x) * 0.5
local boid_half_x = particle_half_x * 4.0
local particle_center_z = (particle_bounds.min.z + particle_bounds.max.z) * 0.5
local particle_half_z = (particle_bounds.max.z - particle_bounds.min.z) * 0.5
local boid_half_z = particle_half_z * 2.0
local boid_bounds = {
    min = hg.Vec3(particle_center_x - boid_half_x, boid_min_y, particle_center_z - boid_half_z),
    max = hg.Vec3(particle_center_x + boid_half_x, boid_max_y, particle_center_z + boid_half_z),
}
```

With the current dirt particle bounds `X = -30..30`, `Y = 0..20` and `Z = -20..100`,
the boid volume becomes `X = -120..120`, `Y = 10..50` and `Z = -80..160`.

The first implementation should stay around `64..96` boids. Neighbor lookup uses a
uniform 3D spatial grid rebuilt each frame. The grid cell size follows the active
neighbor radius, and each boid only scans nearby cells instead of testing itself against
the whole flock. This keeps separation complete in the local neighborhood while avoiding
global O(n^2) behavior as the flock grows.

The grid should avoid string keys. Use integer cell indices derived from clamped
`x/y/z` cell coordinates:

```lua
local cell_index = ix + iy * dim_x + iz * dim_x * dim_y + 1
```

Cells are reused and cleared in place each frame to limit Lua allocation pressure.

### Forces

Classic forces:

- `separation`: avoid crowding.
- `alignment`: match nearby velocity.
- `cohesion`: move toward local center.
- `bounds`: keep the flock inside a loose 3D volume.
- `wander`: low-frequency procedural noise.
- `music_target`: steer toward a song-driven attractor.

Music-modulated parameters:

- High `energy` increases max speed and acceleration.
- High `onset` briefly increases turn sharpness and separation.
- High `brightness` raises altitude and expands the flock.
- Strong `bass` increases cohesion and mass-like inertia.
- Strong `treble` increases small lateral jitter.
- High `flatness` increases turbulence and reduces clean alignment.
- Strong `chroma_flux` moves the attractor along wider curved trajectories.

### Orientation And Drawing

Draw each bird as a quad aligned to velocity:

```lua
local forward = safe_normalize(boid.vel, hg.Vec3(0, 0, 1))
local yaw = math.atan(forward.x, forward.z)
local pitch = -math.asin(clamp(forward.y, -1.0, 1.0))
local rot = hg.Vec3(pitch, yaw, 0.0)
hg.DrawModel(vid, quad_model, shader, uniforms, textures,
             hg.TransformationMat4(boid.pos, rot, scale), render_state)
```

If the quads disappear because they are seen edge-on, use two crossed quads for the
first visibility pass. The current visual pass keeps that crossed shape but scales its
width to roughly one fifth of the previous placeholder width, without changing length,
so the flock reads more like moving luminous sticks. The stick thickness is constant:
the former thickest side is used as the reference width for both crossed quads along the
whole length.

## Neural Controller

### Why A Small Network

The neural layer should not classify music. It should behave like a compact evolving
control organism: a small number of internal values remember recent musical pressure and
turn that memory into steering parameters.

This matches the Anyflo-inspired direction: the interesting object is the process that
generates motion, not a fixed motion path.

### Network Size

Use around ten neurons:

```text
Inputs:
  1 energy
  2 onset
  3 brightness
  4 bass
  5 treble

Recurrent/internal:
  6 excitation
  7 calm
  8 spread

Outputs:
  9 turn
 10 cohesion
```

Alternative mapping if more outputs are needed:

```text
8 spread
9 altitude
10 turbulence
```

The implementation can keep all ten neurons in one array and a separate list of weighted
links. Some neurons receive direct audio input each frame; all neurons also receive
decayed recurrent influence from the previous frame.

### Update Rule

Simple recurrent update:

```lua
function neural_update(neurons, links, inputs, dt)
    local decay = math.exp(-dt * 1.8)

    for i = 1, #neurons do
        neurons[i].next = neurons[i].value * decay + neurons[i].bias
    end

    for i = 1, #links do
        local link = links[i]
        neurons[link.to].next = neurons[link.to].next + neurons[link.from].value * link.weight
    end

    neurons[1].next = neurons[1].next + inputs.energy
    neurons[2].next = neurons[2].next + inputs.onset
    neurons[3].next = neurons[3].next + inputs.brightness
    neurons[4].next = neurons[4].next + inputs.bass
    neurons[5].next = neurons[5].next + inputs.treble

    for i = 1, #neurons do
        neurons[i].value = math.tanh(neurons[i].next)
    end

    return neurons
end
```

In Lua without `math.tanh`, use:

```lua
local function tanh(x)
    local e = math.exp(-2.0 * x)
    return (1.0 - e) / (1.0 + e)
end
```

### Evolution

"Evolution" should be gradual adaptation during playback, not random mutation every
frame. Keep it deterministic enough for a demo.

Proposed mechanism:

- Each song owns a `controller_profile` initialized from its global metrics.
- Every few seconds, evaluate a simple fitness proxy:
  `fitness = smooth_energy_match + flock_stability - boundary_penalty`.
- Slightly adjust a few link weights toward the current musical pressure.
- Clamp weights to a small range such as `-1.5..1.5`.
- Smoothly blend active weights so trajectories drift instead of snapping.
- Store evolved weights in a `controller_profiles[song_id]` table so every song keeps
  its learned state after it ends.
- On replay, reuse the stored profile instead of rebuilding the controller from scratch.

Mutation example:

```lua
local pressure = inputs.energy * 0.6 + inputs.onset * 0.4
link.weight = clamp(link.weight + (pressure - 0.5) * link.plasticity * dt,
                    -1.5, 1.5)
```

For reproducibility, seed any random initialization from `current_song.id`.

## Mapping Neural Outputs To Boids

The network should output parameter deltas, not direct positions.

```lua
local boid_params = {
    max_speed = map01(excitation, 2.0, 7.0) * 4.0,
    max_force = map01(turn, 0.8, 4.0) * 3.0,
    separation_weight = 1.4 + onset * 2.2,
    alignment_weight = 1.0 + calm * 1.5,
    cohesion_weight = (0.35 + cohesion * 1.35) * cohesion_pulse,
    wander_weight = 0.2 + turbulence * 1.6,
    target_weight = 0.3 + chroma_flux * 1.2,
    altitude = map01(brightness, 8.0, 45.0),
    flock_radius = map01(spread, 10.0, 70.0),
}
```

The runtime currently uses `4.0x` spread amplitude for the moving music target, while
using `0.25x` target orbit speed and visible roll speed for the crossed sticks. This
gives much wider flock excursions without making the flock spin too quickly.

`cohesion_pulse` is an oscillating multiplier driven by song time and audio features.
It combines `energy`, `onset`, `flatness`, `chroma_flux` and `tempo_phase` so cohesion
can periodically collapse and release in a more chaotic, music-dependent way.

The boids then integrate normally:

```lua
boid.acc = separation + alignment + cohesion + bounds + wander + music_target
boid.vel = limit_vec3(boid.vel + boid.acc * dts, boid_params.max_speed)
boid.pos = boid.pos + boid.vel * dts
```

This keeps flock behavior physically coherent even when the music is active.

## Neural Visualization

Add a small debug-only Dear ImGui overlay. It is not part of the final visual language.
Toggle it on and off with the `TAB` key.

Display:

- Ten nodes arranged in input, internal and output columns.
- Node fill intensity from current neuron value.
- Link color or alpha from signed link weight.
- A small strip chart for recent `energy`, `onset` and `brightness`.
- Current sampled song time and analysis frame index.

Implementation notes:

- Use the existing Dear ImGui path rather than drawing the network in the 3D scene.
- Keep a `boids_debug_visible` boolean in caller-owned runtime state.
- Flip that boolean on `TAB` key press, not while the key is held down.
- Draw only when the overlay is visible so the normal demo path stays cheap.

## Lua Integration Plan

### New Runtime Files

Add:

```text
src/music_analysis.lua       generated data
src/music_analysis_runtime.lua
src/boids.lua
src/neural_controller.lua
```

Responsibilities:

- `music_analysis_runtime.lua`: sample and interpolate generated analysis frames.
- `neural_controller.lua`: create, update, evolve, store per-song profiles and expose
  neural outputs.
- `boids.lua`: initialize, update and draw the global flock.

The flock is initialized once and kept alive across the whole demo. Scene-specific code
may adjust targets or bounds, but boid state and evolved neural profiles should not be
destroyed when the music changes.

Keep the call site in `main.lua` explicit:

```lua
local music_analysis = require("music_analysis")
require("music_analysis_runtime")
require("neural_controller")
require("boids")

boids, neural_state = boids_update_draw(
    transparent_view_id,
    dt,
    boids,
    neural_state,
    music_analysis,
    song_player,
    bird_model,
    bird_shader,
    bird_uniforms,
    bird_render_state
)
```

### Generated Data Hook

`build_music_analysis.py` should be run from the song build pipeline after audio files
are available. It can either:

- read source WAV files in `works/audio`, matching `songs_manifest.lua`, or
- read generated OGG files in `src/assets/audio`.

Prefer source WAV for analysis quality and generated OGG only as fallback.

The script should emit `src/music_analysis.lua` directly, using the same generated-file
style as `src/songs.lua`.

### Sampling Function

```lua
function music_analysis_sample(analysis, song_id, elapsed_sec)
    local song = analysis.songs[song_id]
    if song == nil or song.frames == nil or #song.frames == 0 then
        return nil
    end

    local frame_pos = elapsed_sec * analysis.sample_rate_hz
    local i0 = clamp(math.floor(frame_pos) + 1, 1, #song.frames)
    local i1 = clamp(i0 + 1, 1, #song.frames)
    local t = frame_pos - math.floor(frame_pos)

    return lerp_feature_frame(song.frames[i0], song.frames[i1], t)
end
```

For performance, reuse a scratch frame table instead of allocating a new table every
frame.

## Implementation Steps

1. Create `build_music_analysis.py` and generate `src/music_analysis.lua`.
2. Add `music_analysis_runtime.lua` with frame interpolation and fallback neutral values.
3. Add `neural_controller.lua` with ten neurons, fixed links and deterministic seeding.
4. Add `boids.lua` with classic separation, alignment, cohesion and bounds steering.
5. Draw boids as oriented quads with the existing Harfang model drawing pattern.
6. Wire `boids_update_draw` into `main.lua` after song-player update.
7. Add a `TAB`-toggled Dear ImGui debug overlay for neuron values and link weights.
8. Tune feature normalization in Python, then tune Lua mapping constants per scene scale.
9. Add an evolution pass that slowly modifies and stores per-song link weights during
   playback.

## Milestones

### Milestone 1: Static Flock

- Boids move inside bounds.
- Quads orient along velocity.
- No audio or neural control yet.

### Milestone 2: Audio-Driven Parameters

- Python generates per-song analysis frames.
- Lua samples current song frame using elapsed playback time.
- Energy, onset and brightness drive flock speed, spread and altitude.

### Milestone 3: Neural Mediation

- Ten-neuron controller sits between audio and boid parameters.
- Neural outputs are visible in debug mode.
- Behavior transitions smoothly between song sections.

### Milestone 4: Progressive Evolution

- Link weights adapt slowly from recent musical pressure and flock stability.
- Evolution is deterministic per song seed and persists per song during the demo
  session.
- Debug overlay shows the active weights changing.

## Risks And Constraints

- Real-time audio analysis should be avoided. The runtime must only sample loaded tables.
- Per-frame allocations in Lua should be minimized; reuse tables for audio frames,
  neighbor accumulators and neural state.
- The current runtime experiment calls a full Lua `collectgarbage("collect")` every
  frame. If this is too expensive, switch back to incremental steps after the flock
  allocation pattern has been tuned.
- Use the spatial grid for neighbor lookup. Full global boid-to-boid checks should stay
  out of the runtime path.
- Neural mutation can easily become noisy. Keep evolution slow, clamped and smoothed.
- Generated `music_analysis.lua` may become large. Start at `20 Hz`; raise only if the
  music feels undersampled.
- The song clock loops the audio source, while transport moves to the next song using
  duration checks. Sampling should clamp or wrap defensively.

## External Documentation

- Librosa feature documentation: https://librosa.org/doc/latest/feature.html
- Librosa RMS: https://librosa.org/doc/latest/generated/librosa.feature.rms.html
- Librosa spectral centroid: https://librosa.org/doc/latest/generated/librosa.feature.spectral_centroid.html
- Librosa chroma STFT: https://librosa.org/doc/latest/generated/librosa.feature.chroma_stft.html
- Librosa onset strength: https://librosa.org/doc/latest/generated/librosa.onset.onset_strength.html
- Librosa beat tracking: https://librosa.org/doc/latest/generated/librosa.beat.beat_track.html
- Michel Bret, Anyflo: https://www.anyflo.com/bret/art/1986/Anyflo.htm
