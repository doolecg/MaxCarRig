# MaxCarRig: systems

What each system is, where it lives and how it connects to the others. Update when a system is added or changes.

## Dialog (macroScript)
- **What it does:** collects car, spline, ground, BOTTOM, mode and wheels, then builds or removes a rig.
- **Where:** `CarRig.ms`, rollout `MaxCarRig_UI`.
- **Talks to:** the scene, by creating the rig nodes below.
- **Saved:** nothing; settings are per session.

## Rig nodes (in the scene)
- **What it does:** `<car>_CarRig_Path` rides the spline with a Path Constraint (Follow, constant velocity). `<car>_CarRig` is the root the car is linked to; its Transform Script reads the path helper and casts rays at the ground objects to place and tilt the car.
- **Where:** built by `buildRig` in `CarRig.ms`; controller code is `rigScript`.
- **Talks to:** path helper and ground objects through script controller node variables (`pathNode`, `g1`, `g2`...).
- **Saved:** in the .max file. User props `MaxCarRig`, `MaxCarRig_path` on the root, `MaxCarRig_oldParent` on linked nodes so Remove can restore parents.
