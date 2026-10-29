# V1 Simple Car Rig: full guide

This guide takes you from a car model to a finished, baked drive. It covers every button in the tool and every setting on the rig. Version 0.25.1.

Read this first:

1. Name your parts (section 2) and Auto detect does most of the set-up for you.
2. Every setting you will want to change after building is on the rig's Car Rig modifier (section 6), not in the tool window.
3. For smooth playback, bake a copy (section 9).
4. Something wrong? Press Open log in the tool and send the log.

## 1. Install

1. Drag `dist/V1_SimpleCarRig.mzp` onto any 3ds Max viewport. The tool window opens.
2. To open it again later, add the SCR button to a toolbar: Customize > Customize User Interface > Toolbars, category V1_Scripts, drag "V1 - Simple Car Rig" onto a toolbar. You can give it a hotkey on the Keyboard tab in the same way.

You can also run `CarRig.ms` with Scripting > Run Script. To update, drag the new .mzp onto a viewport. Rigs already in your scenes keep working as they are, and you can open and play them on a PC without the tool.

## 2. Get your car ready

### Name the parts

Auto detect finds parts by name. Spaces, dashes and upper or lower case do not matter, so `Front Left`, `front-left` and `FRONT_LEFT` all work.

- BODY: the car body. The whole car can be one group, with the wheel groups inside it.
- FRONT_LEFT, FRONT_RIGHT, BACK_LEFT, BACK_RIGHT: the wheels. REAR_LEFT, FL, RR and similar short names work too. A wheel can be a group (rim, tyre, brake).
- CAR PATH: the spline to drive along.
- CAR SURFACE: the road or ground. Every object whose name starts with CAR SURFACE counts (CAR SURFACE001, CAR SURFACE Kerb and so on), and so does everything inside them.

### Wheel pivots

Put each wheel's pivot in its centre: select the wheel, Hierarchy panel > Affect Pivot Only > Center to Object. If you would rather not move pivots, set Wheel centre to Tyre centre in the tool (section 3).

### Which way the car faces

The car can face any world direction. With both front wheels picked, the tool works out which way the car faces from them. Without them, set Car front faces (world) to the axis the nose points along.

## 3. The tool window, top to bottom

### Setup guide

A short version of this guide in a pop-up.

### Car and path

- Auto detect by name: finds BODY, the wheels, CAR PATH and CAR SURFACE, makes a BOTTOM helper if there is none, and picks Per wheel mode when it finds four wheels and ground. It tells you what it found and what is missing.
- Use selection as car: uses the selected objects as the car instead. Wheels inside a grouped car are still found by name.
- Pick spline: the spline to drive along.

### Mode

- Simple (spline only): the car rides the spline at the BOTTOM height, pitched along it. No ground, steering or bank.
- Body (BOTTOM): the car sits on the ground under the BOTTOM helper, tilted to the surface.
- Per wheel (4 wheels): each tyre finds the ground under it, as a round, wide tyre, so it rolls up kerbs instead of jumping. This gives the best result over kerbs and bumps.

### Ground

- Include list: only the objects in the list are ground.
- Exclude list: every visible mesh except the list and the car is ground (the tool takes the list when you press Build).
- Ray start above spline: how far above the spline the tool looks down for ground. Keep it above the highest bump but below any bridge the car drives under.
- Add selected, Remove, Clear: change the list.

### BOTTOM

The BOTTOM helper marks the point of the car that sits on the road. Create at car bottom puts one under the middle of the car, on its lowest point. Or pick BOTTOM uses a helper you made. Move it up or down if the car sits too low or high.

### Wheels (front pair steers)

- Wheel centre: Pivot point, or Tyre centre (the middle of the tyre's box, if your pivots are not centred).
- Car front faces (world): only used when the front wheels are not picked.
- Front left, Front right, Rear left, Rear right: pick each wheel. Picking one part of a closed group picks the whole wheel group.

### Options

- Look ahead: how far ahead along the spline the steering aims.
- Max steer (deg): the furthest the front wheels turn.
- Bank (deg per g): how far the body leans in a turn.
- Put the rig and car on their own layer: on by default. Untick it to leave them on their own layers.

### Build, Refresh, Remove

- Build rig: builds the rig. Undo works.
- Refresh selected rig: rebuilds the selected rig from the same car, spline and ground, keeping every setting and your Progress keys. Use it after editing the car.
- Remove selected rig: takes the rig off and puts the car back where it was, in its old groups and on its old layers. Cameras you added stay.

### Change a built rig

Select the rig's green rectangle first. The group then follows that rig, so you can select ground objects without losing it.

- Add selected, Remove, Add CAR SURFACE: change the rig's ground. Each change rebuilds the rig at once.
- Pick new spline: move the rig to another spline.

### Bake

- Timeline or Custom range: which frames to bake.
- Bake a copy of the selected rig: see section 9.

### Checks

- Check steering and Speed test: write measurements to the log for fault-finding.
- Open log: opens `V1_SimpleCarRig.log` from 3ds Max's temp folder.

## 4. What Build makes

- `<car>_CarRig`: the green rectangle round the car. This is the rig root. Select it to change settings.
- `<car>_CarRig_Aim`: the orange point the front wheels steer at, riding the spline ahead of the car.
- Steering, spin and suspension helpers for each wheel, and a light-blue outline for each tyre (`..._CarRig_Tyre..`).
- A layer named after the rig, holding the rig and the car (unless you unticked it).

The car runs from the start to the end of the spline over the timeline. Scrub the time slider to check it.

## 5. Fitting the tyres

In Per wheel mode, the tyre outlines are what touch the ground. If a wheel sinks into the road or floats above it:

1. Select the rig and tick Show helpers on the "ground and spline" panel of its Car Rig modifier.
2. Move or resize each light-blue tyre outline so it hugs its tyre.
3. Move BOTTOM if the whole car sits too high or low.
4. Press Update rig from helpers. Your fitted outlines are kept on every later Refresh.

## 6. The Car Rig modifier

Select the rig rectangle and open the Modify panel. Every setting here can be animated with Auto Key.

### Presets

- Car type: saloon, hatchback, sports car, supercar, muscle car, SUV / 4x4, van, truck / lorry, off-road buggy or classic car. Sets suspension and body motion to suit.
- Suspension: soft, mid or hard.
- Body look: V1 default, subtle, sporty, exaggerated, or off (no body motion).

The chosen preset stays showing. You can change any value after.

### Drive and speed

- Progress %: where the car is along the spline, keyed 0 to 100 over the timeline. Move or add keys to change the timing.
- Look ahead and Max steer: as in the tool window.
- Reverse along spline: drive from the last vertex to the first, nose first.
- Path smoothing %: takes a smoother line through bends, cutting them a little like a real driver. 0 follows the spline exactly.
- Ease in / out, Start frames, Stop frames: the car pulls away from rest and brakes to a stop, still leaving and arriving on your Progress keys.
- Speed now: the car's speed at the current frame, in km/h and mph.
- Measure speed: finds the top speed over the run.
- Cruise speed, Unit, Set run from speed: re-times the Progress keys so the car cruises at that speed.
- Keep speed if spline changes: when you edit the spline, the Progress keys are stretched so the speed stays the same. Editing the Progress keys by hand turns this off, and the status bar tells you.

### Bank and dive

- Bank (turns): Deg per g, Ease frames and Max deg. How far the body leans out of a turn, how quickly, and the most it can lean.
- Dive / squat: Deg per g, Start ease, Stop ease and Max deg. The nose lifts when the car speeds up and dips when it brakes.

### Ground and spline

The same ground and spline controls as Change a built rig, plus Show helpers and Update rig from helpers (section 5).

### Wheels

- Tyre spin x: 1 is real rolling, 0 stops the wheels, above 1 gives wheelspin.
- Suspension: 0 to 1, how much each wheel follows the ground under it.
- Travel: how far a wheel can move up and down.
- Ray height: the same as Ray start above spline in the tool window.
- Collision detail: how many points each tyre is tested at. Higher is smoother over sharp kerbs, but slower.
- Lift smoothing: softens the wheels rising and falling. Raise it if wheels jitter.

### Body

- Realistic motion: the body rides on springs, rising, falling, pitching and rolling a few frames after the ground. Untick for a stiff body.
- Follow: 0 to 1, how much of the ground's movement the body takes.
- Lag frames: how late the body follows.

### Camera

- New camera type: Standard, V-Ray Physical or Physical (3ds Max).
- Add camera: puts a camera behind and above the car, looking at it. Move it anywhere; it rides with the car.
- Attach a camera: pick a camera you already have. It rides with the car from where it stands.
- Stabiliser: 0 to 1, smooths out shakes from kerbs and bumps.
- Keep horizon level: stops the camera rolling and pitching with the body.

### Corner slowdown

- Slow on corners: the car never goes faster than each bend allows, and brakes before tight bends.
- Corner speed: the speed for a bend of Tight radius. Gentler bends allow more.
- Braking g: how hard the car brakes for a bend.
- Slow for kerbs and bumps: the car crosses each kerb or bump slowly; the taller it is, the slower.

With these on, the car can arrive later than your last Progress key.

## 7. Changing the timing

- Move the last Progress key to make the whole run faster or slower.
- Add keys in between to speed up or slow down part of the run.
- Or type a speed into Cruise speed and press Set run from speed. Only the last Progress key moves.

## 8. Building without a spline or ground

You can build first and choose later. With no spline, the tool makes a straight 30 m spline and the car rides on it. With no ground, the car rides on the spline. Set the real ones on the rig's ground and spline panel.

## 9. Baking for smooth playback

A live rig works out every frame as you play, so a long road or a detailed ground can play slowly. Baking makes a plain keyed copy:

1. Select the rig rectangle.
2. Choose Timeline or Custom range.
3. Press Bake a copy of the selected rig. Esc cancels.

The copy goes on its own `<rig>_Baked` layer and the live rig is hidden. To change the drive, unhide the rig, change it, and bake again. Outside a custom range, the copy holds its first and last positions.

## 10. Removing a rig

Select the rig rectangle and press Remove selected rig. The car goes back to where it was before the rig, with its old parents, groups and layers. Cameras you added stay in the scene.

## 11. Problems and fixes

- The car sits sideways or drives backwards: the front direction was wrong. Pick both front wheels, or set Car front faces (world), then Remove and Build again. To drive the other way along the spline, tick Reverse along spline.
- The car floats or sinks: move BOTTOM, or fit the tyre outlines (section 5).
- A wheel sits in the road: fit its tyre outline and press Update rig from helpers.
- The car falls through the road in places: the spline dips under the road there. Raise Ray start above spline, or lift the spline.
- The car jumps onto a bridge above it: lower Ray start above spline so the rays start under the bridge.
- Wheels jitter: raise Lift smoothing, or raise Collision detail.
- Playback is slow: bake a copy (section 9).
- The rig says it was built with an older version: Remove it and build it again.
- Anything else: press Open log and send the log.
