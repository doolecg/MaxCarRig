# MaxCarRig: systems

What each system is, where it lives and how it connects to the others. Update when a system is added or changes.

## Dialog (macroScript)
- **What it does:** collects car, spline, ground, BOTTOM, mode and wheels, then builds or removes a rig.
- **Where:** `CarRig.ms`, rollout `MaxCarRig_UI`.
- **Talks to:** the scene, by creating the rig nodes below.
- **Saved:** nothing; settings are per session.
- **Change a built rig:** a panel follows the last rig selected and rebuilds it (as Refresh does, keeping modifier settings and Progress keys) with added or removed ground objects, new CAR SURFACE objects, or a new spline. The inputs are read from and written back to the rig's `MaxCarRig_in*` user props.

## Rig nodes (in the scene)
- **What it does:** `<car>_CarRig` is a rectangle round the car, holding a Car Rig modifier (Attribute Holder with custom attribute `MaxCarRigParams`: progress, lookAhead, steerMax, bank, rayUp). Its Transform Script places it on the spline at `progress` with `lengthInterp`/`lengthTangent` and casts rays at the ground objects to place and tilt the car.
- **Where:** built by `buildRig` in `CarRig.ms`; controller code is `rigScript`.
- **Talks to:** path helper and ground objects through script controller node variables (`sp`, `g1`, `g2`...) and modifier targets (`progress`, `rayUp`).
- **Steering and bank (Body and Per wheel modes):** `<car>_CarRig_Aim` has a Position Script that sits `lookAhead` further along the spline than `progress`. `_CarRig_SteerFL/FR` (front wheels linked under them) share one Rotation Script that turns towards the aim, clamped to `steerMax`. `_CarRig_Bank` (body linked under it) rolls by `bank` times the steer ratio.
- **Saved:** in the .max file. User props `MaxCarRig`, `MaxCarRig_aim` on the root, `MaxCarRig_helper` on bank and steer helpers, `MaxCarRig_oldParent` on linked nodes so Remove can restore parents.
