-- MaxCarRig test scene: a London hotel street at real-world size.
-- Makes a cambered road with a round-top hump, pavements with dropped-kerb crossovers,
-- a forecourt and drop-off, a hotel with an oval canopy, street furniture, a test car
-- (named BODY / FRONT_LEFT ... for Auto detect) and two paths.
-- Run: 3ds Max > Scripting > Run Script. It resets the scene (asks to save first).
-- Then open Car Rig, press Auto detect by name, Create at car bottom, Build rig.
-- Metres: X along the road, +Y towards the building, Z up. Every size goes through k,
-- so it is right in any system unit. System units are not changed.
(
	local k, i
	local northX = #(-50, -25, 25, 50), southX = #(-37, 0, 37), shrubX = #(-12, -7, 7, 12)
	local tyre, rim, gFL, gFR, gBL, gBR, lower, cabin, wx, wy
	local wheelNames = #("FRONT_LEFT", "FRONT_RIGHT", "BACK_LEFT", "BACK_RIGHT")
	local wheelX = #(1.45, 1.45, -1.45, -1.45), wheelY = #(0.8, -0.8, 0.8, -0.8)
	local wheelGroups = #()
	local pathPts, kerbPts, canopy

	-- Box: width is X and length is Y in Max. Size args are x, y, z in metres; pos is the base centre.
	fn mkBox nm sx sy sz px py pz col k = (
		local b = box name:nm width:(sx * k) length:(sy * k) height:(sz * k) pos:[px * k, py * k, pz * k]
		b.wirecolor = col
		b
	)

	fn mkCyl nm r h px py pz col k = (
		local c1 = cylinder name:nm radius:(r * k) height:(h * k) pos:[px * k, py * k, pz * k] sides:24
		c1.wirecolor = col
		c1
	)

	fn mkSph nm r px py pz col k = (
		local s1 = sphere name:nm radius:(r * k) pos:[px * k, py * k, pz * k] segs:16
		s1.wirecolor = col
		s1
	)

	-- Height-field mesh. zfn takes (x y) in metres and returns a height in metres.
	-- A skirt down to z=0 round the edge makes kerbs show as vertical faces.
	fn gridMesh nm x0 x1 nx y0 y1 ny zfn col k = (
		local verts = #(), faces = #(), ring = #()
		local i, j, p, q, x, y, z, ta, tb, tc, td, ba, bb, nTop, nTopFaces, m
		for j = 0 to ny do (
			y = y0 + (y1 - y0) * (j as float) / ny
			for i = 0 to nx do (
				x = x0 + (x1 - x0) * (i as float) / nx
				z = zfn x y
				append verts [x * k, y * k, z * k]
			)
		)
		-- Counter-clockwise from above, so the normals point up.
		for j = 0 to ny - 1 do (
			for i = 0 to nx - 1 do (
				ta = j * (nx + 1) + i + 1
				tb = ta + 1
				td = ta + nx + 1
				tc = td + 1
				append faces [ta, tb, tc]
				append faces [ta, tc, td]
			)
		)
		nTop = verts.count
		nTopFaces = faces.count
		-- Edge ring, counter-clockwise from above, starting at the corner (x0, y0).
		for i = 0 to nx - 1 do append ring (i + 1)
		for j = 0 to ny - 1 do append ring (j * (nx + 1) + nx + 1)
		for i = nx to 1 by -1 do append ring (ny * (nx + 1) + i + 1)
		for j = ny to 1 by -1 do append ring (j * (nx + 1) + 1)
		for p = 1 to ring.count do append verts [verts[ring[p]].x, verts[ring[p]].y, 0.0]
		for p = 1 to ring.count do (
			q = if p == ring.count then 1 else p + 1
			ta = ring[p]
			tb = ring[q]
			ba = nTop + p
			bb = nTop + q
			append faces [ta, ba, bb]
			append faces [ta, bb, tb]
		)
		m = mesh vertices:verts faces:faces
		m.name = nm
		for p = 1 to faces.count do setFaceSmoothGroup m p (if p <= nTopFaces then 1 else 2)
		update m
		m.wirecolor = col
		m
	)

	-- Road: 2.5% crossfall from the crown, plus a 3.7 m long, 75 mm round-top hump at x=-40.
	fn zRoad x y = (
		local z, d
		z = 0.09 * (1.0 - (abs y) / 3.65)
		d = x + 40.0
		if (abs d) < 1.85 do z += 0.075 * cos (d / 1.85 * 90.0)
		z
	)

	-- Near pavement: 125 mm kerb, dropped to 25 mm at two crossovers (4 m wide, 1 m transitions).
	-- The footway slopes from the kerb height down to 125 mm at the back.
	fn zPavN x y = (
		local kerb = 0.125, d, t, h
		for c in #(-12.0, 12.0) do (
			d = abs (x - c)
			t = (d - 2.0) / 1.0
			if t < 0.0 do t = 0.0
			if t > 1.0 do t = 1.0
			h = 0.025 + 0.1 * t
			if h < kerb do kerb = h
		)
		kerb + (0.125 - kerb) * (y - 3.65) / 2.0
	)

	fn zFlat125 x y = 0.125
	fn zFlat250 x y = 0.25

	-- Spline through the points, z=0, smooth knots.
	fn mkPath nm pts col k = (
		local ss, i
		ss = SplineShape name:nm
		addNewSpline ss
		for i = 1 to pts.count do addKnot ss 1 #smooth #curve [pts[i].x * k, pts[i].y * k, 0.0]
		updateShape ss
		ss.wirecolor = col
		ss
	)

	if checkForSave() do (
		resetMaxFile #noPrompt
		units.DisplayType = #Metric
		units.MetricType = #Meters
		k = units.decodeValue "1m"

		-- Ground (every name starts with CAR SURFACE, so Auto detect finds them all)
		gridMesh "CAR SURFACE Road" (-70.0) 70.0 700 (-3.65) 3.65 4 zRoad (color 55 55 58) k
		gridMesh "CAR SURFACE Pavement North" (-70.0) 70.0 700 3.65 5.65 4 zPavN (color 175 175 172) k
		gridMesh "CAR SURFACE Pavement South" (-70.0) 70.0 700 (-5.65) (-3.65) 4 zFlat125 (color 175 175 172) k
		gridMesh "CAR SURFACE Forecourt" (-22.0) 22.0 44 5.65 19.6 14 zFlat125 (color 185 180 170) k
		gridMesh "CAR SURFACE Dropoff Kerb" (-15.0) 15.0 30 19.6 24.0 4 zFlat250 (color 195 190 180) k

		-- Island in the loop and its tree (not ground)
		mkCyl "Island" 4.5 0.15 0.0 10.0 0.125 (color 80 130 70) k
		mkCyl "Tree Trunk" 0.2 3.0 0.0 10.0 0.275 (color 90 60 40) k
		mkSph "Tree Crown" 1.8 0.0 10.0 4.1 (color 60 115 55) k

		-- Hotel, oval canopy and columns. The canopy is a cylinder squashed to 13 x 5.5 m radii.
		mkBox "Hotel" 50.0 20.0 18.0 0.0 34.0 0.0 (color 205 190 160) k
		canopy = mkCyl "Canopy" 1.0 0.45 0.0 19.5 4.5 (color 240 240 240) k
		canopy.scale = [13.0, 5.5, 1.0]
		mkCyl "Column Left" 0.4 4.375 (-11.0) 17.0 0.125 (color 235 235 235) k
		mkCyl "Column Right" 0.4 4.375 11.0 17.0 0.125 (color 235 235 235) k
		for i = 1 to shrubX.count do (
			mkCyl ("Shrub Pot " + (i as string)) 0.35 0.6 shrubX[i] 23.0 0.25 (color 110 80 60) k
			mkSph ("Shrub " + (i as string)) 0.55 shrubX[i] 23.0 1.2 (color 60 115 55) k
		)

		-- Street furniture: lamp posts on both pavements, dashed centre line (lifted by the 90 mm camber)
		for i = 1 to northX.count do (
			mkCyl ("Lamp North Post " + (i as string)) 0.06 5.0 northX[i] 5.3 0.125 (color 50 50 50) k
			mkSph ("Lamp North Head " + (i as string)) 0.2 northX[i] 5.3 5.2 (color 255 240 190) k
		)
		for i = 1 to southX.count do (
			mkCyl ("Lamp South Post " + (i as string)) 0.06 5.0 southX[i] (-5.3) 0.125 (color 50 50 50) k
			mkSph ("Lamp South Head " + (i as string)) 0.2 southX[i] (-5.3) 5.2 (color 255 240 190) k
		)
		for i = 0 to 14 do mkBox ("Centre Line " + (i as string)) 3.0 0.1 0.003 (-63.0 + 9.0 * i) 0.0 0.09 (color 240 240 240) k

		-- Test car at the origin, facing +X, wheels on z=0
		lower = mkBox "Car Lower Box" 4.7 1.85 0.75 0.0 0.0 0.2 (color 12 12 12) k
		cabin = mkBox "Car Cabin Box" 2.6 1.6 0.5 (-0.3) 0.0 0.95 (color 12 12 12) k
		for i = 1 to 4 do (
			wx = wheelX[i]
			wy = wheelY[i]
			-- Cylinders stand along Z; turned 90 degrees about X the axle runs along Y. Each is then moved so
			-- its box centre is the wheel centre, whichever way the turn went.
			tyre = mkCyl ("Tyre " + wheelNames[i]) 0.34 0.235 wx wy 0.34 (color 20 20 20) k
			tyre.rotation = eulerAngles 90 0 0
			tyre.pos += [wx * k, wy * k, 0.34 * k] - tyre.center
			rim = mkCyl ("Rim " + wheelNames[i]) 0.24 0.26 wx wy 0.34 (color 90 90 95) k
			rim.rotation = eulerAngles 90 0 0
			rim.pos += [wx * k, wy * k, 0.34 * k] - rim.center
			append wheelGroups (group #(tyre, rim) name:(wheelNames[i]))
		)
		group #(lower, cabin, wheelGroups[1], wheelGroups[2], wheelGroups[3], wheelGroups[4]) name:"BODY"

		-- Paths. Nearside lane centre is y=+1.83 when driving +X (UK, drive on the left).
		pathPts = #([-60, 1.83, 0], [-25, 1.83, 0], [-16, 2.5, 0], [-12, 6, 0], [-9.5, 11, 0], [-5, 15.5, 0], [0, 17.5, 0], [5, 15.5, 0], [9.5, 11, 0], [12, 6, 0], [16, 2.5, 0], [25, 1.83, 0], [60, 1.83, 0])
		mkPath "CAR PATH" pathPts (color 255 220 0) k
		-- Not named for Auto detect on purpose: mounts the full 125 mm kerb and comes back down.
		kerbPts = #([-60, 1.83, 0], [20, 1.83, 0], [28, 2.4, 0], [32, 4.6, 0], [40, 4.6, 0], [44, 2.4, 0], [52, 1.83, 0], [65, 1.83, 0])
		mkPath "KERB TEST PATH" kerbPts (color 255 140 0) k

		animationRange = interval 0 600
		clearSelection()
		max zoomext sel all
		format "Built. Open Car Rig, press Auto detect by name, Create at car bottom, Build rig.\n"
	)
)
