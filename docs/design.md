# MaxCarRig: design notes

The why behind decisions, and the results of any tests that informed them. The bible says what was decided; this says why. Newest first.

## Rig maths in a Transform Script controller (2026-10-27)
- **Decision:** the rig root gets a Transform Script controller holding all the ground-fit code, with the path helper and ground objects added as script nodes.
- **Why:** the scene keeps working on any PC without the tool installed, and it updates live while scrubbing. A scripted plugin or a callback would need the tool loaded.
- **Evidence:** wheel-mode plane fit checked numerically on a tilted plane: up vector matched the plane normal exactly and all four contacts landed on it.

## Rays cast down from above the spline (2026-10-27)
- **Decision:** each ray starts "Ray start above spline" units above the path point and goes straight down; the highest hit across all ground objects wins.
- **Why:** the spline sets the rough height, so bridges and tunnels work by keeping the spline on the right level. Casting from very high up would hit the bridge deck when driving underneath.
