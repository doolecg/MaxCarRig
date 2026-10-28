-- MaxCarRig: a simple car rig for 3ds Max.
-- The car follows a spline. Simple mode keeps it on the spline; Body mode sits it on
-- ground geometry under one BOTTOM helper; Per wheel mode fits it to four wheel contacts.
-- Front wheels steer towards an aim null further along the spline, and the body banks.
-- Run this file once (Scripting > Run Script, or drop it on a viewport). It opens the
-- tool and adds the "SCR" action under category "V1_Scripts" for toolbars and hotkeys.

macroScript V1_SimpleCarRig
category:"V1_Scripts"
toolTip:"V1 - Simple Car Rig"
buttonText:"SCR"
(
	global MaxCarRig_UI

	rollout MaxCarRig_UI "V1 Simple Car Rig 0.22.1" width:540
	(
		local carNodes = #(), groundList = #(), wheelNodes = #(undefined, undefined, undefined, undefined)
		-- Tyre collision shapes as the user left them (place, Radius, Height per wheel), handed from a rebuild
		-- to buildRig so hand-fitted shapes survive Refresh / Update.
		local tyreEdits = undefined
		local wheelTags = #( \
			#("FRONT_LEFT", "FL", "LEFT_FRONT", "WHEEL_FL", "FRONT_LEFT_WHEEL"), \
			#("FRONT_RIGHT", "FR", "RIGHT_FRONT", "WHEEL_FR", "FRONT_RIGHT_WHEEL"), \
			#("BACK_LEFT", "REAR_LEFT", "RL", "BL", "LEFT_REAR", "LEFT_BACK", "WHEEL_RL", "BACK_LEFT_WHEEL", "REAR_LEFT_WHEEL"), \
			#("BACK_RIGHT", "REAR_RIGHT", "RR", "BR", "RIGHT_REAR", "RIGHT_BACK", "WHEEL_RR", "BACK_RIGHT_WHEEL", "REAR_RIGHT_WHEEL"))
		local pathShape = undefined, bottomNode = undefined
		-- RadioButtons cannot read their labels back, so the log uses these.
		local modeNames = #("Simple", "Body", "Per wheel"), groundNames = #("Include list", "Exclude list")

		-- The controller scripts below live in the scene file, so a rigged scene keeps
		-- working on a PC without this tool.

		-- Spline lookup functions shared by the rig scripts (pasted in when the tool opens).
		local splineFns = @"-- Spline lookups from a table: the spline is sampled once into points with running lengths and kept in
	-- a global. lengthInterp re-measures the whole spline on every call (about 100 ms on a long road), and
	-- the rig asked several times a frame. The table is rebuilt when the spline moves, its knot count changes,
	-- or its shape changes: a sum of its knots and handles is re-checked at most every 0.2 seconds.
	global MaxCarRig_splines4
	fn splinePrint sp =
	(
		local fp = [0,0,0], i
		try (for i = 1 to numKnots sp 1 do fp += (getKnotPoint sp 1 i) + 0.5 * (getInVec sp 1 i) + 0.25 * (getOutVec sp 1 i)) catch ()
		fp
	)
	fn splineTable sp =
	(
		local tab, key1, key2, e, pts, lens, tans, ns, i, j, total, steps = 24, fp, turns, a, b
		if MaxCarRig_splines4 == undefined do MaxCarRig_splines4 = #()
		key1 = sp.transform as string
		key2 = numKnots sp 1
		for i = MaxCarRig_splines4.count to 1 by -1 do
		(
			e = MaxCarRig_splines4[i]
			if not isValidNode e[1] then deleteItem MaxCarRig_splines4 i
			else if e[1] == sp do
			(
				if e[2] == key1 and e[3] == key2 then
				(
					if abs (timeStamp() - e[5]) < 200 then tab = e[4]
					else
					(
						fp = splinePrint sp
						if distance fp e[6] < 0.0001 then (e[5] = timeStamp(); tab = e[4])
						else deleteItem MaxCarRig_splines4 i
					)
				)
				else deleteItem MaxCarRig_splines4 i
			)
		)
		if tab == undefined do
		(
			pts = #()
			ns = numSegments sp 1
			for i = 1 to ns do
				for j = (if i == 1 then 0 else 1) to steps do
					append pts (in coordsys world interpBezier3D sp 1 i ((j as float) / steps))
			lens = #(0.0)
			total = 0.0
			for i = 2 to pts.count do
			(
				total += distance pts[i] pts[i - 1]
				append lens total
			)
			-- A smooth direction at every point (from its two neighbours), blended between points,
			-- so the car turns smoothly instead of snapping at each sample.
			tans = for i = 1 to pts.count collect normalize (pts[amin pts.count (i + 1)] - pts[amax 1 (i - 1)])
			-- How far the road has turned (radians, left positive) from its start to every point.
			turns = #(0.0)
			for i = 2 to pts.count do
			(
				a = [tans[i - 1].x, tans[i - 1].y, 0.0]
				b = [tans[i].x, tans[i].y, 0.0]
				append turns (turns[i - 1] + (if (length a) < 0.0001 or (length b) < 0.0001 then 0.0 else (atan2 ((cross a b).z) (dot a b)) * pi / 180.0))
			)
			tab = #(pts, lens, amax 0.001 total, tans, turns)
			append MaxCarRig_splines4 #(sp, key1, key2, tab, timeStamp(), splinePrint sp)
		)
		tab
	)
	-- Ease in / out: the car speeds up from rest over the first part of the run and slows to rest over the
	-- last (a and b are those parts as shares of the run). Speed rises and falls in a straight line, so the
	-- car brakes evenly into the stop; the middle runs a little faster so start and finish stay on the keys.
	fn rampQ q a b =
	(
		local k, v, r
		if q <= 0.0 or q >= 1.0 then q
		else
		(
			a = amax 0.0 a
			b = amax 0.0 b
			if a + b > 1.0 do
			(
				k = 1.0 / (a + b)
				a = a * k
				b = b * k
			)
			v = 1.0 / (1.0 - a / 2.0 - b / 2.0)
			r = if q < a then v * q * q / (2.0 * a) else if q <= 1.0 - b then v * (a / 2.0 + (q - a)) else 1.0 - v * (1.0 - q) * (1.0 - q) / (2.0 * b)
			r
		)
	)
	-- Length of the run in frames: from the first to the last Progress key.
	fn progFrames ca =
	(
		local c, n
		c = try (getPropertyController ca #progress) catch (undefined)
		n = if c == undefined then 0 else c.keys.count
		if n >= 2 then (c.keys[n].time - c.keys[1].time).frame else (animationRange.end - animationRange.start).frame
	)
	-- Corner speed. With Slow on corners on, the car is driven by a simple speed planner instead of by the
	-- Progress keys directly: it pulls away from rest (Start frames), cruises at the top speed of the Progress
	-- keys, never goes faster than each bend allows, brakes for bends at Braking g, and stops at the end of the
	-- spline (Stop frames). Corner speed is the limit for a bend of Tight radius; gentler bends allow more
	-- (the same sideways grip). If the car is already slow enough for a bend it keeps its speed.
	-- The plan (distance travelled at each frame) is built once per setting and kept in a global.
	global MaxCarRig_plans
	fn progAt ca f =
	(
		local c = try (getPropertyController ca #progress) catch (undefined)
		if c == undefined then ca.progress / 100.0 else (at time (f as time) c.value) / 100.0
	)
	fn planTable sp ca =
	(
		local tab, c, key, e, plan, i, n, pts, lens, tans, kap, cap, a, b, d, len, t0, t1, f, s, v, vCruise
		local qPrev, q, aAcc, aStop, aLat, aBrake, vC, lo, hi, mid, capS, pos, guard, bumps, vb, sb, j
		tab = splineTable sp
		c = try (getPropertyController ca #progress) catch (undefined)
		key = (if c == undefined then #() else (for k in c.keys collect #(k.time, k.value))) as string
		key += (#(tab[3], tab[1].count, ca.easeOn, ca.easeStart, ca.easeStop, ca.cornerSpeed, ca.speedUnit, ca.cornerRadius, ca.brakeG, ca.reverse, frameRate, ca.metre, ca.cornerSlow)) as string
		bumps = try (if ca.kerbSlow then #(ca.bumpU as array, ca.bumpH as array) else #(#(), #())) catch (#(#(), #()))
		key += bumps as string
		if MaxCarRig_plans == undefined do MaxCarRig_plans = #()
		for e in MaxCarRig_plans where e[1] == sp and e[2] == key do plan = e[3]
		if plan == undefined do
		(
			pts = tab[1]
			lens = tab[2]
			tans = tab[4]
			n = pts.count
			len = tab[3]
			-- how sharp the bend is at every sample, in 1 / scene units
			kap = #()
			for i = 1 to n do
			(
				a = tans[amax 1 (i - 1)] * [1, 1, 0]
				b = tans[amin n (i + 1)] * [1, 1, 0]
				d = lens[amin n (i + 1)] - lens[amax 1 (i - 1)]
				append kap (if d < 0.0001 or (length a) < 0.0001 or (length b) < 0.0001 then 0.0 else (acos (amax (-1.0) (amin 1.0 (dot (normalize a) (normalize b))))) * pi / 180.0 / d)
			)
			-- speeds in scene units per frame
			vC = (if ca.speedUnit == 2 then ca.cornerSpeed / 2.23694 else ca.cornerSpeed / 3.6) * ca.metre / frameRate
			aLat = vC * vC / (amax 0.001 ca.cornerRadius)
			aBrake = ca.brakeG * 9.81 * ca.metre / (frameRate * frameRate)
			cap = for i = 1 to n collect (if not ca.cornerSlow or kap[i] < 0.0000001 then 1e12 else sqrt (aLat / kap[i]))
			-- Kerbs and bumps: the car crosses each one slowly, the taller the slower (about 8 km/h for a
			-- 125 mm kerb, 10 km/h for a road hump, 18 km/h for a dropped kerb), from 3 m before to 3 m after
			-- so both axles are over it at that speed.
			for j = 1 to bumps[1].count do
			(
				vb = 2.5 * (sqrt (0.1 / (amax 0.005 (bumps[2][j] / ca.metre)))) * ca.metre / frameRate
				sb = bumps[1][j] * len
				for i = 1 to n where (abs (lens[i] - sb)) <= 3.0 * ca.metre do cap[i] = amin cap[i] vb
			)
			-- brake before bends: a bend's limit reaches back along the road at Braking g
			for i = n - 1 to 1 by -1 do cap[i] = amin cap[i] (sqrt (cap[i + 1] * cap[i + 1] + 2.0 * aBrake * (lens[i + 1] - lens[i])))
			-- run timing from the Progress keys
			t0 = if c != undefined and c.keys.count >= 1 then c.keys[1].time.frame else animationRange.start.frame
			t1 = if c != undefined and c.keys.count >= 2 then c.keys[c.keys.count].time.frame else animationRange.end.frame
			vCruise = 0.0
			qPrev = progAt ca t0
			for f = t0 + 1 to t1 do
			(
				q = progAt ca f
				vCruise = amax vCruise ((q - qPrev) * len)
				qPrev = q
			)
			vCruise = amax 0.001 vCruise
			aAcc = if ca.easeOn and ca.easeStart > 0.0 then vCruise / ca.easeStart else 1e12
			-- Pull away from a kerb or bend gently (0.3 g at most), not in one frame.
			aAcc = amin aAcc (0.3 * 9.81 * ca.metre / (frameRate * frameRate))
			aStop = if ca.easeOn and ca.easeStop > 0.0 then vCruise / ca.easeStop else 1e12
			plan = #(t0, #(0.0))
			s = 0.0
			v = 0.0
			guard = 0
			while s < len and guard < 200000 do
			(
				-- the limit for the bend where the car is now (reverse drives the spline from its far end)
				pos = if ca.reverse then len - s else s
				lo = 1
				hi = n
				while hi - lo > 1 do
				(
					mid = (lo + hi) / 2
					if lens[mid] <= pos then lo = mid else hi = mid
				)
				capS = amin cap[lo] cap[hi]
				v = amin (amin (v + aAcc) vCruise) (amin capS (sqrt (2.0 * aStop * (amax 0.0 (len - s)))))
				v = amax v (0.0005 * vCruise)
				s = amin len (s + v)
				append plan[2] s
				guard += 1
			)
			append MaxCarRig_plans #(sp, key, plan)
			if MaxCarRig_plans.count > 8 do deleteItem MaxCarRig_plans 1
		)
		plan
	)
	-- Travelled fraction (0 to 1) at frame f, with ease in / out, and the corner speed planner when on.
	fn travelAt sp f ca =
	(
		local q, total, plan, k, i, a
		if ca.cornerSlow or (try (ca.kerbSlow and ca.bumpU.count > 0) catch (false)) then
		(
			plan = planTable sp ca
			k = f - plan[1]
			if k <= 0 then 0.0
			else
			(
				i = (floor k) as integer
				a = k - i
				if i + 2 > plan[2].count then 1.0 else (plan[2][i + 1] * (1.0 - a) + plan[2][i + 2] * a) / (splineTable sp)[3]
			)
		)
		else
		(
			q = progAt ca f
			total = progFrames ca
			if ca.easeOn and total > 0.0 do q = rampQ q (ca.easeStart / total) (ca.easeStop / total)
			q
		)
	)
	fn splineAt sp f =
	(
		local tab, pts, lens, target, lo, hi, mid, a
		tab = splineTable sp
		pts = tab[1]
		lens = tab[2]
		target = f * tab[3]
		lo = 1
		hi = pts.count
		while hi - lo > 1 do
		(
			mid = (lo + hi) / 2
			if lens[mid] <= target then lo = mid else hi = mid
		)
		a = if lens[hi] > lens[lo] then (target - lens[lo]) / (lens[hi] - lens[lo]) else 0.0
		#(pts[lo] + (pts[hi] - pts[lo]) * a, normalize (tab[4][lo] * (1.0 - a) + tab[4][hi] * a))
	)
	-- How far the road has turned (radians, left positive) from its start to fraction f.
	fn turnAt sp f =
	(
		local tab, lens, target, lo, hi, mid, a
		tab = splineTable sp
		lens = tab[2]
		target = f * tab[3]
		lo = 1
		hi = lens.count
		while hi - lo > 1 do
		(
			mid = (lo + hi) / 2
			if lens[mid] <= target then lo = mid else hi = mid
		)
		a = if lens[hi] > lens[lo] then (target - lens[lo]) / (lens[hi] - lens[lo]) else 0.0
		tab[5][lo] * (1.0 - a) + tab[5][hi] * a
	)"

		-- Ground ray functions shared by the rig root and the suspension scripts (pasted in at build).
		local rayFns = @"-- Ray tests use a voxel grid per ground object (RayMeshGridIntersect), built once and kept
	-- in a global; plain intersectRay tests every face on every frame and makes playback lag.
	-- A grid is rebuilt when its object moves or its face count changes.
	global MaxCarRig_grids
	fn gridFor g =
	(
		local rm, key, i
		if MaxCarRig_grids == undefined do MaxCarRig_grids = #()
		key = #(g.transform as string, (getPolygonCount g)[1])
		for i = MaxCarRig_grids.count to 1 by -1 do
		(
			if not isValidNode MaxCarRig_grids[i][1] then deleteItem MaxCarRig_grids i
			else if MaxCarRig_grids[i][1] == g do
			(
				if MaxCarRig_grids[i][2] == key[1] and MaxCarRig_grids[i][3] == key[2] then rm = MaxCarRig_grids[i][4]
				else deleteItem MaxCarRig_grids i
			)
		)
		if rm == undefined do
		(
			rm = RayMeshGridIntersect()
			rm.Initialize 40
			rm.addNode g
			rm.buildGrid()
			append MaxCarRig_grids #(g, key[1], key[2], rm)
		)
		rm
	)
	fn castDown grounds p rayUp =
	(
		local best = undefined, o, rm, n, i, d, tries, lift
		-- If nothing is hit (the spline dips under the road there), try again from 100 times higher.
		for tries = 1 to 2 while best == undefined do
		(
			lift = if tries == 1 then rayUp else (amax 1.0 rayUp) * 100.0
			o = p + [0, 0, lift]
			for g in grounds where isValidNode g and p.x >= g.min.x and p.x <= g.max.x and p.y >= g.min.y and p.y <= g.max.y do
			(
				rm = gridFor g
				-- Both sides of every face count: imported or built ground often has faces pointing down, and
				-- one-sided rays went straight through it. The closest hit from above is still the top surface.
				n = rm.intersectRay o [0,0,-1] true
				if n > 0 do
				(
					i = rm.getClosestHit()
					d = rm.getHitDist i
					if best == undefined or (o.z - d) > best.pos.z do best = ray (o - [0,0,d]) (rm.getHitNormal i)
				)
			)
		)
		best
	)
	-- A tyre is round and has width, so it meets a kerb or bump before its centre is over it and rolls up the
	-- edge instead of sinking into it. Ground is sampled along both tyre edges at points fixed in the world (a
	-- grid along the direction of travel, half a radius apart), so the lift grows smoothly as the tyre moves
	-- instead of jumping when one ray crosses an edge. Returns the contact as a ray (point lifted to where
	-- the tyre rests, ground normal under the centre), or undefined if there is no ground.
	fn tyreDown grounds p fwd r hw rayUp steps soft =
	(
		local mid, fh, side, re, st, u, k0, k1, k, x, q, h, best = undefined, lines, ln, xs, zs, i, xa, xb, za, zb, m, xm, cand, c, z
		mid = castDown grounds p rayUp
		if r <= 0.0 or (length [fwd.x, fwd.y, 0.0]) < 0.0001 then mid
		else
		(
			fh = normalize [fwd.x, fwd.y, 0.0]
			side = [-fh.y, fh.x, 0.0]
			-- Lift smoothing makes the shape that meets the ground a larger, softer circle (like a tyre that
			-- gives a little), so the wheel starts to rise earlier and climbs more gently. Flat ground is unchanged.
			re = r * (1.0 + (amax 0.0 soft))
			st = 2.0 * re / (amax 2 steps)
			u = dot p fh
			k0 = (floor ((u - re) / st)) as integer
			k1 = (ceil ((u + re) / st)) as integer
			lines = if hw > 0.0 then #(-hw, hw) else #(0.0)
			-- The ground between two samples is taken as a straight slope, and the circle is rolled over those
			-- slopes: the highest the tyre must sit on each slope is found exactly (where the slope touches the
			-- circle), so the lift changes smoothly as the tyre moves instead of stepping from sample to sample.
			for ln in lines do
			(
				xs = #()
				zs = #()
				for k = k0 to k1 do
				(
					x = k * st - u
					h = castDown grounds (p + fh * x + side * ln) rayUp
					append xs x
					append zs (if h == undefined then undefined else h.pos.z)
				)
				for i = 1 to xs.count - 1 where zs[i] != undefined and zs[i + 1] != undefined do
				(
					m = (zs[i + 1] - zs[i]) / (xs[i + 1] - xs[i])
					xa = amax (-re) xs[i]
					xb = amin re xs[i + 1]
					if xa < xb do
					(
						xm = m * re / (sqrt (1.0 + m * m))
						cand = #(xa, xb)
						if xm > xa and xm < xb do append cand xm
						for c in cand do
						(
							z = zs[i] + m * (c - xs[i]) - (re - sqrt (amax 0.0 (re * re - c * c)))
							if best == undefined or z > best do best = z
						)
					)
				)
			)
			if best == undefined then mid else ray [p.x, p.y, best] (if mid != undefined then mid.dir else [0, 0, 1])
		)
	)"

		-- Rig root (Transform Script). Mode 1 = simple, 2 = body, 3 = per wheel.
		-- sp is the spline; progress and rayUp come from the Car Rig modifier.
		local rootScript = @"(
	local mode = %MODE%
	local grounds = #(%GROUNDS%)
	local wb = %WB%, rearD = %REAR%, dS, len
	local offs = #(%OFFSETS%)
	local tyres = #(%TYRES%)
	-- All locals up front: Max throws a Bad free thunk error for locals declared in a nested block and read in a loop.
	local u, p, fwd, y, h, up, guess, hits, w, x, tm, mid, offMid, sa, missed, nh, zs, i
	%RAYFNS%
	%SPLINEFNS%
	fn frameFrom x z pos =
	(
		local y = normalize (cross z x)
		matrix3 (cross y z) y z pos
	)
	fn wrapU sp x = if isClosed sp 1 then (mod ((mod x 1.0) + 1.0) 1.0) else (amax 0.0 (amin 1.0 x))
	u = travelAt sp F rigCA
	if rigCA.reverse do u = 1.0 - u
	u = if isClosed sp 1 then (mod ((mod u 1.0) + 1.0) 1.0) else (amax 0.0 (amin 1.0 u))
	sa = splineAt sp u
	p = sa[1]
	fwd = sa[2]
	if rigCA.reverse do fwd = -fwd
	-- Grip: a real car's rear wheels roll along their line and never slide sideways, so the rear axle sits
	-- on the spline and the car points along the spline there. The front swings slightly wide in a bend and
	-- the front wheels steer to match (see the steering script), as on the road. Rigs without rear wheels keep
	-- the car centred on the spline.
	if wb > 0.0 do
	(
		dS = if rigCA.reverse then -1.0 else 1.0
		len = (splineTable sp)[3]
		sa = splineAt sp (wrapU sp (u - dS * rearD / len))
		fwd = dS * sa[2]
		p = sa[1] + fwd * rearD
	)
	case mode of
	(
		1:
		(
			y = normalize (cross [0,0,1] fwd)
			matrix3 fwd y (cross fwd y) p
		)
		2:
		(
			h = tyreDown grounds p fwd rigCA.wheelR 0.0 rayUp (rigCA.tyreSteps / 2) rigCA.liftSmooth
			if h == undefined then frameFrom fwd [0,0,1] p
			else
			(
				up = normalize h.dir
				if up.z < 0 do up = -up
				frameFrom fwd up h.pos
			)
		)
		default:
		(
			guess = frameFrom (normalize [fwd.x, fwd.y, 0]) [0,0,1] p
			hits = #()
			missed = #()
			for i = 1 to offs.count do
			(
				w = offs[i] * guess
				h = tyreDown grounds w fwd tyres[i].radius 0.0 rayUp (rigCA.tyreSteps / 2) rigCA.liftSmooth
				append hits (if h == undefined then w else h.pos)
				append missed (h == undefined)
			)
			-- A wheel over a gap (no ground under it) takes the average height of the wheels that did find
			-- ground, so the car stays level instead of tipping towards the spline height.
			nh = 0
			zs = 0.0
			for i = 1 to hits.count where not missed[i] do (zs += hits[i].z; nh += 1)
			if nh > 0 do for i = 1 to hits.count where missed[i] do hits[i] = [hits[i].x, hits[i].y, zs / nh]
			-- Wheel order is FL, FR, RL, RR: front minus rear is forward, left minus right is left.
			x = (hits[1] + hits[2]) - (hits[3] + hits[4])
			y = (hits[1] + hits[3]) - (hits[2] + hits[4])
			tm = frameFrom (normalize x) (normalize (cross x y)) [0,0,0]
			mid = (hits[1] + hits[2] + hits[3] + hits[4]) / 4
			offMid = (offs[1] + offs[2] + offs[3] + offs[4]) / 4
			tm.row4 = mid - offMid * tm
			tm
		)
	)
)"

		-- Aim null (Position Script): Look ahead units further along the spline than the car.
		local aimScript = @"(
	%SPLINEFNS%
	local len = (splineTable sp)[3]
	local a = if len < 0.001 then 0.0 else ahead / len
	local u = travelAt sp F rigCA
	u = if rigCA.reverse then 1.0 - u - a else u + a
	u = if isClosed sp 1 then (mod ((mod u 1.0) + 1.0) 1.0) else (amax 0.0 (amin 1.0 u))
	(splineAt sp u)[1]
)"

		-- Steering (Rotation Script). One instance drives both front wheels, so they always turn together.
		-- The angle comes only from the spline: the travel direction at the car versus the line from the
		-- front axle to the look-ahead point. No rig, world or car-front axes are involved, so it cannot
		-- be thrown off by which way the car or its pivots face. Positive = turn left, about the car up axis.
		local steerScript = @"(
	local len, u, s, uf, ua, t, v, ang, k, ur, rad, dn, kap
	local wb = %WB%, rearD = %REAR%, side = %SIDE%
	%SPLINEFNS%
	fn wrapU sp x = if isClosed sp 1 then (mod ((mod x 1.0) + 1.0) 1.0) else (amax 0.0 (amin 1.0 x))
	len = (splineTable sp)[3]
	s = if rigCA.reverse then -1.0 else 1.0
	u = travelAt sp F rigCA
	if rigCA.reverse do u = 1.0 - u
	if wb > 0.0 then
	(
		-- The rear axle follows the spline (as the rig root does), so the car turns about a point on the rear
		-- axle line at the bend's radius there. Each front wheel points at right angles to the line from that
		-- point, so it rolls without sliding, and the inner wheel turns a little more (Ackermann). side is this
		-- wheel's offset to the left of the centre line; how sharp the bend is comes from the road's turn
		-- over half a metre either side of the rear axle.
		ur = wrapU sp (u - s * rearD / len)
		k = 0.5 * rigCA.metre / len
		kap = ((turnAt sp (wrapU sp (ur + s * k))) - (turnAt sp (wrapU sp (ur - s * k)))) / (2.0 * k * len)
		ang = 0.0
		if (abs kap) > 0.0000001 do
		(
			rad = 1.0 / kap
			dn = rad - side
			ang = if (abs dn) < 0.001 then (if kap > 0.0 then 90.0 else -90.0) else atan (wb / dn)
			if ang * kap < 0.0 do ang = if kap > 0.0 then 90.0 else -90.0
		)
	)
	else
	(
		uf = wrapU sp (u + s * %FRONTDIST% / len)
		ua = wrapU sp (u + s * ahead / len)
		t = s * (splineAt sp (wrapU sp u))[2]
		v = (splineAt sp ua)[1] - (splineAt sp uf)[1]
		t.z = 0.0
		v.z = 0.0
		ang = if (length v) < 0.001 or (length t) < 0.001 then 0.0 else atan2 ((cross t v).z) (dot t v)
	)
	(eulerAngles 0 0 (amax (-steerMax) (amin steerMax ang))) as quat
)"

		-- Body (Transform Script, parent-relative). Bank and dive/squat come from smooth sources, not the rig's
		-- own position (its ground fit is bumpy, and measuring acceleration from it doubled the bumps):
		--   cornering = speed (from the Progress keys) squared x how sharp the bend is (from the spline);
		--   starting and stopping = the change of speed (from the Progress keys).
		-- Each is averaged over a window of frames before and after (Bank ease, Stop/start ease), so the body
		-- eases into and out of a lean. Sharper turns, faster cornering and harder stops lean more.
		-- With Realistic body motion on, the body also follows the ground's rise, pitch and roll late (Body lag).
		local bankScript = @"(
	%SPLINEFNS%
	local rest = %REST%
	local metre = %METRE%
	local dh = 0.0, dp = 0.0, dr = 0.0, n, i, k, j, w, wsum, tk, uk, pk, hh, pp, rr, h0, p0, r0, out
	local len, dirS, toG, sigB, sigP, sigS, nB, nP, nS, nMax, prog = #(), idx, d0, d1, d2, v, q, ua, ub, ta, tb, kap, lon, lat
	local sumB = 0.0, sumP = 0.0, sumS = 0.0, wbs = 0.0, wps = 0.0, wss = 0.0, ax = 0.0, ay = 0.0, delta, mats = #(), realistic, roll, pitch
	local hs = #(), ps = #(), rs = #(), wn, wd, zeta, e, st, fade, half, c, ts, tf
	fn wrapU sp x = if isClosed sp 1 then (mod ((mod x 1.0) + 1.0) 1.0) else (amax 0.0 (amin 1.0 x))
	len = (splineTable sp)[3]
	dirS = if rigCA.reverse then -1.0 else 1.0
	toG = frameRate * frameRate / (metre * 9.81)
	sigB = amax 0.5 (rigCA.bankTime / 2.0)
	sigP = amax 0.5 (rigCA.pitchTime / 2.0)
	sigS = amax 0.5 (rigCA.startTime / 2.0)
	nB = (amin 30 (ceil (2.0 * sigB))) as integer
	nP = (amin 30 (ceil (2.0 * sigP))) as integer
	nS = (amin 30 (ceil (2.0 * sigS))) as integer
	nMax = amax nB (amax nP nS)
	-- prog[k + nMax + 2] is the travelled fraction at frame F + k
	for k = -(nMax + 1) to nMax + 1 do append prog (travelAt sp (F + k) rigCA)
	-- bends are measured over 1 m either side
	delta = metre / len
	for k = -nMax to nMax do
	(
		idx = k + nMax + 2
		d0 = prog[idx - 1] * len
		d1 = prog[idx] * len
		d2 = prog[idx + 1] * len
		lon = (d2 - 2.0 * d1 + d0) * toG
		-- Braking is eased over Stop ease, speeding up over Start ease.
		if (abs k) <= nP do
		(
			w = exp (-((k * k) / (sigP * sigP)))
			sumP += w * lon
			wps += w
		)
		if (abs k) <= nS do
		(
			w = exp (-((k * k) / (sigS * sigS)))
			sumS += w * lon
			wss += w
		)
		if (abs k) <= nB do
		(
			v = (d2 - d0) / 2.0
			q = prog[idx]
			ua = wrapU sp (if rigCA.reverse then 1.0 - (q + delta) else q + delta)
			ub = wrapU sp (if rigCA.reverse then 1.0 - (q - delta) else q - delta)
			ta = dirS * (splineAt sp ua)[2]
			tb = dirS * (splineAt sp ub)[2]
			ta.z = 0.0
			tb.z = 0.0
			kap = if (length ta) < 0.001 or (length tb) < 0.001 then 0.0 else (atan2 ((cross tb ta).z) (dot tb ta)) * pi / 180.0 / (2.0 * metre)
			lat = v * v * kap * toG
			w = exp (-((k * k) / (sigB * sigB)))
			sumB += w * lat
			wbs += w
		)
	)
	ax = (amax 0.0 (sumS / wss)) + (amin 0.0 (sumP / wps))
	ay = sumB / wbs
	realistic = rigCA.realistic and rigCA.bodyLag > 0.0 and rigCA.bodyFollow > 0.0
	if realistic do
	(
		-- The body rides on a damped spring: when the ground under the rig steps (a kerb, a bump) the body
		-- catches up a little late, goes slightly past and settles, without wobbling on. Each past frame's change
		-- in height, pitch and roll is weighed by how far a spring would still be from it now (step response
		-- minus 1). Damping 0.6 gives about a tenth of overshoot and one soft bounce. Body lag sets the
		-- spring's speed: about 2 pi x Body lag frames per bounce. The oldest frames fade out of the window
		-- so a change leaving it never pops.
		zeta = 0.6
		wn = 1.0 / rigCA.bodyLag
		wd = wn * sqrt (1.0 - zeta * zeta)
		n = (amin 20 (ceil (rigCA.bodyLag * 8.0))) as integer
		half = n / 2.0
		-- Every other earlier frame is enough for a smooth spring and halves the cost (each needs the rig's
		-- ground fit again). They are the even frames, fixed in time, so a kerb is not seen on alternate frames
		-- (sampling at fixed steps back from F made the body move in two-frame stairs).
		ts = #(F)
		for tf = 2.0 * ((ceil (F / 2.0)) - 1.0) to F - n - 2 by -2 do append ts tf
		for i = 1 to ts.count do
		(
			tk = ts[i] as time
			j = at time tk rig.transform
			uk = travelAt sp ts[i] rigCA
			if rigCA.reverse do uk = 1.0 - uk
			pk = (splineAt sp (wrapU sp uk))[1]
			append hs (j.row4.z - pk.z)
			append ps (asin (amax (-1.0) (amin 1.0 (normalize j.row1).z)))
			append rs (asin (amax (-1.0) (amin 1.0 (normalize j.row2).z)))
		)
		for k = 1 to hs.count - 1 do
		(
			-- the change between two samples happened around the middle of the pair, i frames ago
			i = F - (ts[k] + ts[k + 1]) / 2.0
			e = exp (-zeta * wn * i)
			st = 1.0 - e * ((cos (wd * i * 180.0 / pi)) + zeta / (sqrt (1.0 - zeta * zeta)) * (sin (wd * i * 180.0 / pi)))
			fade = if i <= half then 1.0 else 0.5 + 0.5 * (cos (180.0 * (amin 1.0 ((i - half) / (n + 2 - half)))))
			c = (st - 1.0) * fade
			dh += c * (hs[k] - hs[k + 1])
			dp += c * (ps[k] - ps[k + 1])
			dr += c * (rs[k] - rs[k + 1])
		)
		dh *= rigCA.bodyFollow
		-- The springs bottom out: the body can lag below the wheels only as far as the suspension travel.
		dh = amax dh (-rigCA.travel)
		dp *= rigCA.bodyFollow
		dr *= rigCA.bodyFollow
	)
	-- Turning left pulls the car left (ay above 0): the body leans right, left side up = positive roll.
	-- Speeding up (ax above 0) lifts the nose; braking dips it. Capped so nothing can flip the car.
	-- Soft limits: the lean eases towards Max bank / Max dive-squat instead of hitting a hard stop.
	roll = (amax 0.01 rigCA.maxBank) * (tanh ((bank * ay) / (amax 0.01 rigCA.maxBank))) + dr
	pitch = (amax 0.01 rigCA.maxPitch) * (tanh ((rigCA.diveSquat * ax) / (amax 0.01 rigCA.maxPitch))) + dp
	global MaxCarRig_lastBody
	MaxCarRig_lastBody = #(F, ax, ay, roll, pitch, dh, dp, dr)
	-- Roll about X, pitch about Y (nose up is negative about Y).
	out = (rotateXMatrix roll) * (rotateYMatrix (-pitch))
	out.row4 = rest + [0, 0, dh]
	out
)"

		-- Suspension (Position Script, one per wheel): the tyre's contact (round and wide, see tyreDown); the
		-- wheel moves along the rig's up axis by how far the ground there is above or below the body's plane,
		-- up to Travel, scaled by Suspension (0 = off, 1 = full).
		local suspScript = @"(
	local grounds = #(%GROUNDS%)
	local rest = %REST%
	local contact = %CONTACT%
	local tm, c, h, dz
	%RAYFNS%
	tm = rig.transform
	c = contact * tm
	h = tyreDown grounds c tm.row1 tyreShape.radius (tyreShape.height / 2.0) rayUp rigCA.tyreSteps rigCA.liftSmooth
	dz = 0.0
	if h != undefined do dz = dot (h.pos - c) (normalize tm.row3)
	dz = suspension * (amax (-travel) (amin travel dz))
	rest + [0, 0, dz]
)"

		-- Tyre spin (Rotation Script, one per wheel): distance travelled / radius, so the tyre rolls
		-- without sliding. spin scales it: 1 = rolling, 0 = stopped, more = wheelspin.
		-- The helper carries the wheel pivot's own orientation (%BASE%) and spins about the pivot axis
		-- that points across the car (%AXIS%), so a wheel spins about its own axle.
		local spinScript = @"(
	%SPLINEFNS%
	local q = travelAt sp F rigCA, dist, turn
	-- Differential: in a bend the outer wheels roll further than the inner ones. Each wheel rolls the road's
	-- length less its offset to the left times how far the car has turned (left turns positive), so the
	-- outside wheels spin faster.
	dist = q * (splineTable sp)[3]
	turn = if rigCA.reverse then (turnAt sp (1.0 - q)) - (turnAt sp 1.0) else (turnAt sp q) - (turnAt sp 0.0)
	dist -= %SIDE% * turn
	((%AXIS% (%SIGN% * spin * dist / %RADIUS% * 180.0 / pi)) * %BASE%) as quat
)"

		-- The controls on the rig's "Car Rig" modifier. All are animatable.
		-- The Car Rig modifier. Each parameter block has its own panel in the command panel, so the settings sit
		-- in short folding panels instead of one long column. Scripts read values as rigCA.<name>; the tool
		-- reaches animated values with getPropertyController, which works whichever block they are in.
		fn paramsCA = attributes MaxCarRigParams attribID:#(0x5a1c3e01, 0x2b7d4fa2)
		(
			parameters pPresets rollout:rPresets
			(
				carType type:#integer ui:ddCarType default:1
				suspType type:#integer ui:ddSusp default:1
				lookType type:#integer ui:ddLook default:2
			)
			parameters main rollout:rDrive
			(
				progress type:#float ui:spProgress default:0.0
				lookAhead type:#worldUnits ui:spAhead default:4000.0
				steerMax type:#float ui:spSteer default:35.0
				reverse type:#boolean ui:cbReverse default:false
				easeOn type:#boolean ui:cbEase default:true
				easeStart type:#float ui:spEaseStart default:40.0
				easeStop type:#float ui:spEaseStop default:40.0
				speedSet type:#float ui:spSpeedSet default:30.0
				speedUnit type:#integer ui:ddUnit default:2
				speedLocked type:#boolean ui:cbKeepSpeed default:false
				-- Set at build: one metre in scene units, and the spline, for the speed tools.
				metre type:#float default:1000.0
				pathHandle type:#integer default:0
			)
			parameters pBank rollout:rBank
			(
				bank type:#float ui:spBank default:70.0
				bankTime type:#float ui:spBankTime default:60.0
				maxBank type:#float ui:spMaxBank default:45.0
				diveSquat type:#float ui:spDive default:42.0
				startTime type:#float ui:spStartTime default:8.0
				pitchTime type:#float ui:spPitchTime default:8.0
				maxPitch type:#float ui:spMaxPitch default:4.0
			)
			parameters pWheels rollout:rWheels
			(
				spin type:#float ui:spSpin default:1.0
				suspension type:#float ui:spSusp default:1.0
				travel type:#worldUnits ui:spTravel default:100.0
				rayUp type:#worldUnits ui:spRay default:200.0
				-- The tyre radius, set at build; suspension presets set Travel as a share of it.
				wheelR type:#worldUnits default:350.0
				tyreSteps type:#integer ui:spSteps default:12
				liftSmooth type:#float ui:spSmooth default:0.3
			)
			parameters pBody rollout:rBody
			(
				realistic type:#boolean ui:cbRealistic default:true
				bodyFollow type:#float ui:spFollow default:1.0
				bodyLag type:#float ui:spLag default:3.0
			)
			parameters pChange rollout:rChange
			(
				showHelpers type:#boolean ui:cbHelpers default:true
			)
			parameters pCorner rollout:rCorner
			(
				cornerSlow type:#boolean ui:cbCorner default:false
				cornerSpeed type:#float ui:spCornerSpeed default:10.0
				cornerRadius type:#worldUnits ui:spCornerRad default:20000.0
				brakeG type:#float ui:spBrakeG default:0.5
				kerbSlow type:#boolean ui:cbKerb default:true
				bumpU type:#floatTab tabSizeVariable:true
				bumpH type:#floatTab tabSizeVariable:true
			)

			-- Presets stay showing what was picked. Changing a value afterwards keeps the preset name shown.
			rollout rPresets "Car Rig: presets"
			(
				-- Suspension feel. Values: suspension, travel (share of tyre radius), body follow, body lag,
				-- bank ease, start ease, stop ease. Soft settles slowly and moves a lot; hard is quick and tight.
				fn applySuspension k =
				(
					local p
					p = case k of
					(
						1: #(1.0, 0.7, 1.0, 5.0, 40.0, 12.0, 10.0)
						2: #(1.0, 0.5, 0.8, 3.0, 25.0, 8.0, 6.0)
						default: #(0.8, 0.25, 0.5, 2.0, 12.0, 5.0, 3.0)
					)
					this.suspension = p[1]
					this.travel = this.wheelR * p[2]
					this.bodyFollow = p[3]
					this.bodyLag = p[4]
					this.bankTime = p[5]
					this.startTime = p[6]
					this.pitchTime = p[7]
					this.realistic = true
				)
				-- How car types usually handle. Values: bank per g, max bank, dive per g, max dive, max steer,
				-- suspension feel (1 soft, 2 mid, 3 hard), corner speed in mph (0 = leave corners as they are).
				dropdownlist ddCarType "Car type" items:#("Custom", "Saloon", "Hatchback", "Sports car", "Supercar", "Muscle car", "SUV / 4x4", "Van", "Truck / lorry", "Off-road buggy", "Classic car")
				dropdownlist ddSusp "Suspension" items:#("Custom", "Soft", "Mid", "Hard")
				-- Body look: bank, bank ease, max bank, dive, start ease, stop ease, max dive, follow, lag,
				-- realistic. V1 default is the studio's approved look.
				dropdownlist ddLook "Body look" items:#("Custom", "V1 default", "Subtle", "Sporty", "Exaggerated", "Off (no body motion)")
				on ddSusp selected i do if i > 1 do applySuspension (i - 1)
				on ddCarType selected i do
				(
					local c
					c = case i of
					(
						2: #(30.0, 15.0, 18.0, 4.0, 35.0, 2, 0.0)
						3: #(28.0, 14.0, 15.0, 4.0, 38.0, 2, 0.0)
						4: #(14.0, 8.0, 8.0, 2.5, 32.0, 3, 0.0)
						5: #(9.0, 6.0, 6.0, 2.0, 30.0, 3, 0.0)
						6: #(40.0, 18.0, 25.0, 6.0, 33.0, 1, 0.0)
						7: #(50.0, 22.0, 25.0, 6.0, 36.0, 1, 0.0)
						8: #(55.0, 25.0, 22.0, 5.0, 38.0, 1, 15.0)
						9: #(60.0, 28.0, 15.0, 4.0, 40.0, 2, 10.0)
						10: #(25.0, 16.0, 20.0, 6.0, 35.0, 1, 0.0)
						11: #(55.0, 25.0, 30.0, 6.0, 38.0, 1, 0.0)
						default: undefined
					)
					if c != undefined do
					(
						applySuspension c[6]
						this.suspType = c[6] + 1
						this.bank = c[1]
						this.maxBank = c[2]
						this.diveSquat = c[3]
						this.maxPitch = c[4]
						this.steerMax = c[5]
						if c[7] > 0.0 do
						(
							this.cornerSlow = true
							this.cornerSpeed = if this.speedUnit == 2 then c[7] else c[7] * 1.60934
						)
					)
				)
				on ddLook selected i do
				(
					local p = case i of
					(
						2: #(70.0, 60.0, 45.0, 42.0, 8.0, 8.0, 4.0, 1.0, 3.0, true)
						3: #(6.0, 12.0, 8.0, 3.0, 10.0, 6.0, 3.0, 0.5, 4.0, true)
						4: #(25.0, 20.0, 20.0, 10.0, 8.0, 5.0, 6.0, 0.8, 3.0, true)
						5: #(120.0, 40.0, 70.0, 60.0, 6.0, 4.0, 15.0, 1.0, 2.0, true)
						6: #(0.0, 10.0, 0.0, 0.0, 8.0, 8.0, 0.0, 0.0, 4.0, false)
						default: undefined
					)
					if p != undefined do
					(
						this.bank = p[1]
						this.bankTime = p[2]
						this.maxBank = p[3]
						this.diveSquat = p[4]
						this.startTime = p[5]
						this.pitchTime = p[6]
						this.maxPitch = p[7]
						this.bodyFollow = p[8]
						this.bodyLag = p[9]
						this.realistic = p[10]
					)
				)
			)

			-- Drive and speed. The speed readout measures the rig's real motion (ease, corners and all) and turns
			-- it into km/h and mph from the scene units. Set run from speed moves only the last Progress key so the
			-- car cruises at that speed along this spline, allowing for the ease in and out. The first key stays where
			-- it is (frame 0 if there are no keys yet).
			rollout rDrive "Car Rig: drive and speed"
			(
				local readSpeed
				fn rigNode =
				(
					local m = custAttributes.getOwner this
					if m == undefined then undefined else (for n in refs.dependentNodes m where isValidNode n collect n)[1]
				)
				fn speedAt n t =
				(
					local mps = (distance (at time (t + 1) n.transform).row4 (at time (t - 1) n.transform).row4) / 2.0 * frameRate / (amax 0.0001 this.metre)
					#(mps * 3.6, mps * 2.23694)
				)
				fn showSpeed =
				(
					local n = rigNode(), v
					if n != undefined and readSpeed != undefined do
					(
						v = speedAt n sliderTime
						readSpeed.text = "Speed now: " + (formattedPrint v[1] format:".0f") + " km/h  (" + (formattedPrint v[2] format:".0f") + " mph)"
					)
				)
				spinner spProgress "Progress %" range:[-1e6, 1e6, 0] fieldwidth:64
				spinner spAhead "Look ahead" type:#worldunits range:[0, 1e6, 4000] fieldwidth:64
				spinner spSteer "Max steer" range:[0, 89, 35] fieldwidth:64
				checkbox cbReverse "Reverse along spline"
				checkbox cbEase "Ease in / out"
				spinner spEaseStart "Start frames" range:[0, 1000, 40] fieldwidth:64
				spinner spEaseStop "Stop frames" range:[0, 1000, 40] fieldwidth:64
				group "Speed"
				(
					label lblSpeed "Speed now: -" align:#left
					button btnTop "Measure speed" width:130
					label lblTop "" align:#left
					spinner spSpeedSet "Cruise speed" range:[1, 1000, 30] fieldwidth:64
					dropdownlist ddUnit "Unit" items:#("km/h", "mph") width:70 align:#right
					button btnSetSpeed "Set run from speed" width:130
					checkbox cbKeepSpeed "Keep speed if spline changes"
				)
				on rDrive open do readSpeed = lblSpeed
				on rDrive close do readSpeed = undefined
				on btnTop pressed do
				(
					local n = rigNode(), c, t0, t1, best = #(0.0, 0.0), v
					showSpeed()
					if n != undefined do
					(
						c = getPropertyController this "progress"
						t0 = if c != undefined and c.keys.count >= 2 then c.keys[1].time else animationRange.start
						t1 = if c != undefined and c.keys.count >= 2 then c.keys[c.keys.count].time else animationRange.end
						for t = t0 to t1 do
						(
							v = speedAt n t
							if v[1] > best[1] do best = v
						)
						lblTop.text = "Top: " + (formattedPrint best[1] format:".0f") + " km/h  (" + (formattedPrint best[2] format:".0f") + " mph)"
					)
				)
				on btnSetSpeed pressed do
				(
					local sp, len, mps, frames, c, t0, v0, n, k, i
					sp = maxOps.getNodeByHandle this.pathHandle
					if not isValidNode sp then messageBox "The rig's spline is missing. Build the rig again." title:"Car Rig"
					else
					(
						c = getPropertyController this "progress"
						n = if c == undefined then 0 else c.keys.count
						t0 = if n >= 2 then c.keys[1].time else 0f
						v0 = if n >= 2 then c.keys[1].value else 0.0
						-- Only the part of the spline still to drive counts when the first key is not at 0%.
						len = (curveLength sp 1) / (amax 0.0001 this.metre) * (100.0 - v0) / 100.0
						mps = if this.speedUnit == 2 then this.speedSet / 2.23694 else this.speedSet / 3.6
						-- Cruise time, plus half of each ease (speeding up and slowing down average half speed).
						frames = len / (amax 0.01 mps) * frameRate + (if this.easeOn then (this.easeStart + this.easeStop) / 2.0 else 0.0)
						undo "Set run from speed" on
						(
							if n >= 2 then
							(
								-- keys between the first and last that would land on or after the new end are dropped
								for i = n - 1 to 2 by -1 where c.keys[i].time >= t0 + frames as time do deleteKey c i
								k = c.keys[c.keys.count]
								k.time = t0 + frames as time
								k.value = 100.0
								k.inTangentType = #linear
								k.outTangentType = #linear
							)
							else
							(
								if c != undefined do deleteKeys c #allKeys
								with animate on
								(
									at time t0 this.progress = 0.0
									at time (t0 + frames as time) this.progress = 100.0
								)
								c = getPropertyController this "progress"
								if c != undefined do for k in c.keys do (k.inTangentType = #linear; k.outTangentType = #linear)
							)
							if t0 + frames as time > animationRange.end do animationRange = interval (amin animationRange.start t0) (t0 + frames as time)
							this.speedLocked = true
							global MaxCarRig_rigCAs
							if MaxCarRig_rigCAs != undefined do for e in MaxCarRig_rigCAs where e[1] == this do e[2] = undefined
						)
						showSpeed()
					)
				)
			)

			rollout rBank "Car Rig: bank and dive"
			(
				group "Bank (turns)"
				(
					spinner spBank "Deg per g" range:[-500, 500, 70] fieldwidth:64
					spinner spBankTime "Ease frames" range:[1, 120, 60] fieldwidth:64
					spinner spMaxBank "Max deg" range:[0, 90, 45] fieldwidth:64
				)
				group "Dive / squat (stop, start)"
				(
					spinner spDive "Deg per g" range:[-500, 500, 42] fieldwidth:64
					spinner spStartTime "Start ease" range:[1, 120, 8] fieldwidth:64
					spinner spPitchTime "Stop ease" range:[1, 120, 8] fieldwidth:64
					spinner spMaxPitch "Max deg" range:[0, 90, 4] fieldwidth:64
				)
			)

			-- Change this rig's ground and spline. The rebuild is done by the Car Rig tool, which opens if needed.
			rollout rChange "Car Rig: ground and spline"
			(
				fn isShape o = superClassOf o == Shape
				listbox lbGround "Ground" height:4
				pickbutton pbAdd "Pick ground to add" width:140
				button btnDel "Remove from list" width:140
				button btnSurf "Add CAR SURFACE" width:140
				pickbutton pbPath "Pick new spline" filter:isShape width:140
				checkbox cbHelpers "Show helpers"
				-- After moving or resizing a tyre shape (..._CarRig_Tyre..) or moving BOTTOM, rebuild the rig from them.
				button btnUpdate "Update rig from helpers" width:140
				fn rigNode =
				(
					local m = custAttributes.getOwner this
					if m == undefined then undefined else (for n in refs.dependentNodes m where isValidNode n collect n)[1]
				)
				fn listGrounds =
				(
					local r = rigNode(), txt
					txt = if r == undefined then undefined else getUserProp r "MaxCarRig_inGrounds"
					lbGround.items = if txt == undefined then #() else \
						for h in filterString (txt as string) "n_" where isValidNode (maxOps.getNodeByHandle (h as integer)) collect (maxOps.getNodeByHandle (h as integer)).name
				)
				fn ask action arg =
				(
					global MaxCarRig_UI, MaxCarRig_changeLater
					if MaxCarRig_UI == undefined or not MaxCarRig_UI.open do (try (macros.run "V1_Scripts" "V1_SimpleCarRig") catch ())
					if MaxCarRig_changeLater == undefined then messageBox "Install the Car Rig tool (V1_SimpleCarRig.mzp) to change the ground or spline." title:"Car Rig"
					else MaxCarRig_changeLater (rigNode()) action arg
				)
				on rChange open do listGrounds()
				-- Hides or shows every rig helper (steer, bank, suspension, spin, tyre shapes, aim); the green rig
				-- rectangle stays so the rig can still be selected.
				on cbHelpers changed state do
				(
					local r = rigNode(), all, h, i
					if r != undefined do
					(
						all = #(r)
						i = 1
						while i <= all.count do (join all (for c in all[i].children collect c); i += 1)
						h = getUserProp r "MaxCarRig_aim"
						if h != undefined do append all (maxOps.getNodeByHandle h)
						for n in all where isValidNode n and getUserProp n "MaxCarRig_helper" == true do n.isHidden = not state
					)
				)
				on pbAdd picked o do ask #add #(o)
				on btnDel pressed do if lbGround.selection > 0 do ask #remove lbGround.selection
				on btnSurf pressed do ask #surface undefined
				on pbPath picked o do ask #path o
				on btnUpdate pressed do ask #refresh undefined
			)

			rollout rWheels "Car Rig: wheels"
			(
				spinner spSpin "Tyre spin x" range:[-100, 100, 1] fieldwidth:64
				spinner spSusp "Suspension" range:[0, 1, 1] fieldwidth:64
				spinner spTravel "Travel" type:#worldunits range:[0, 1e6, 100] fieldwidth:64
				spinner spRay "Ray height" type:#worldunits range:[0, 1e6, 200] fieldwidth:64
				-- Ground samples along each tyre (more is more exact over kerbs, but slower to play back).
				spinner spSteps "Collision detail" type:#integer range:[4, 48, 12] fieldwidth:64
				-- How soft the tyre meets kerbs and bumps: 0 is the true tyre size, higher rises earlier and gentler.
				spinner spSmooth "Lift smoothing" range:[0, 2, 0.3] fieldwidth:64
			)

			rollout rBody "Car Rig: body"
			(
				checkbox cbRealistic "Realistic motion"
				spinner spFollow "Follow" range:[0, 1, 1] fieldwidth:64
				spinner spLag "Lag frames" range:[0, 12, 3] fieldwidth:64
			)

			rollout rCorner "Car Rig: corner slowdown"
			(
				checkbox cbCorner "Slow on corners"
				spinner spCornerSpeed "Corner speed" range:[1, 500, 10] fieldwidth:64
				label lblCornerUnit "(unit as in Drive panel)" align:#right
				spinner spCornerRad "Tight radius" type:#worldunits range:[0, 1e9, 20000] fieldwidth:64
				spinner spBrakeG "Braking g" range:[0.05, 2, 0.5] fieldwidth:64
				checkbox cbKerb "Slow for kerbs and bumps"
			)
		)

		local toolVersion = "0.22.1"
		-- The V1 header is drawn in Max's own UI colours so it reads in any theme. V1's typeface
		-- (ABC Arizona) is not free to ship, so it uses Georgia, a serif on every Windows PC.
		fn uiColour key = (
			local p = (colorMan.getColor key) * 255
			(dotNetClass "System.Drawing.Color").FromArgb (p.x as integer) (p.y as integer) (p.z as integer)
		)

		fn shapeFilt o = superClassOf o == Shape
		fn geoFilt o = superClassOf o == GeometryClass

		fn listText items = (
			local s = ""
			for i = 1 to items.count do s += (if i > 1 then ", " else "") + (items[i] as string)
			s
		)

		-- Every step goes to the MAXScript Listener and to this file, for bug reports.
		local logPath = (getDir #temp) + "\\V1_SimpleCarRig.log"
		fn logLine msg = (
			local line = (localTime as string) + "  " + msg
			format "[SCR] %\n" line
			local f = if doesFileExist logPath then openFile logPath mode:"a" else createFile logPath
			if f != undefined do (
				format "%\n" line to:f
				close f
			)
		)
		fn names nodes = (
			local s = listText (for n in nodes collect (if isValidNode n then n.name else "-"))
			"(" + nodes.count as string + ") " + s
		)

		fn bboxOf nodes = (
			local bmin = nodes[1].min, bmax = nodes[1].max
			for n in nodes do (
				bmin = [amin bmin.x n.min.x, amin bmin.y n.min.y, amin bmin.z n.min.z]
				bmax = [amax bmax.x n.max.x, amax bmax.y n.max.y, amax bmax.z n.max.z]
			)
			#(bmin, bmax)
		)

		fn topLevel nodes = for n in nodes where findItem nodes n.parent == 0 collect n

		fn withDescendants nodes = (
			local all = for n in nodes collect n
			local i = 1
			while i <= all.count do (
				for c in all[i].children where findItem all c == 0 do append all c
				i += 1
			)
			all
		)

		fn makeBottom cars = (
			local bb = bboxOf cars
			local c = (bb[1] + bb[2]) / 2
			Point name:(uniqueName "CarRig_BOTTOM") pos:[c.x, c.y, bb[1].z] \
				size:((amin (bb[2].x - bb[1].x) (bb[2].y - bb[1].y)) * 0.3) \
				box:true cross:true axisTripod:false centerMarker:false wirecolor:yellow
		)

		-- Rig root starts at BOTTOM, local X = car front, local Y = car left, Z = world up.
		fn startFrame bottom fwdIndex = (
			local fronts = #([1,0,0], [-1,0,0], [0,1,0], [0,-1,0])
			local x = fronts[fwdIndex]
			local z = [0,0,1]
			matrix3 x (cross z x) z bottom.pos
		)

		fn isBrake n = matchPattern n.name pattern:"*brake*" or matchPattern n.name pattern:"*calip*" or matchPattern n.name pattern:"*callip*"
		-- The tyre is the tallest mesh in a wheel group, so its box gives the true axle centre and radius.
		-- Picking by height (not overall size) and skipping brakes matters: one brake mesh can span
		-- the whole axle, and its centre is the middle of the car.
		fn tyreOf w = (
			local best = w, size = -1.0, sz
			for n in withDescendants #(w) where superClassOf n == GeometryClass and not isGroupHead n and not isBrake n do (
				sz = n.max.z - n.min.z
				if sz > size do (size = sz; best = n)
			)
			best
		)
		fn wheelCentre w usePivot = if usePivot then w.pos else (local t = tyreOf w; (t.min + t.max) / 2)
		fn wheelRadius w = (local t = tyreOf w; (t.max.z - t.min.z) / 2)
		-- Half the tyre's width, measured across the car (side is the car's left).
		fn tyreHalfWidth w side = (local t = tyreOf w; abs (dot (t.max - t.min) (normalize side)) / 2)

		-- Kerbs and bumps along the path, found once at build: the ground height every 10 cm under the spline,
		-- and a bump wherever a point stands out from the average of the ground 1 m before and after it by more
		-- than 12 mm (a slope alone does not count). Returns #(positions along the spline 0..1, heights).
		fn findBumps path grounds = (
			local len, stp, n, i, j, p, r, top, hs = #(), us = #(), hts = #(), b, inRun = false, peak, peakI, lo, hi, w
			if grounds.count == 0 or not isValidNode path do return #(#(), #())
			len = curveLength path 1
			stp = units.decodeValue "0.1m"
			n = (amax 2 (len / stp)) as integer
			w = 10
			for i = 0 to n do (
				p = lengthInterp path 1 ((i as float) / n)
				top = undefined
				for g in grounds where isValidNode g do (
					r = intersectRay g (ray (p + [0, 0, units.decodeValue "100m"]) [0, 0, -1])
					if r != undefined and (top == undefined or r.pos.z > top) do top = r.pos.z
				)
				append hs top
			)
			for i = w + 1 to hs.count - w do (
				b = if hs[i] == undefined or hs[i - w] == undefined or hs[i + w] == undefined then 0.0 \
					else abs (hs[i] - (hs[i - w] + hs[i + w]) / 2.0)
				if b > units.decodeValue "0.012m" then (
					if not inRun or b > peak do (peak = b; peakI = i)
					inRun = true
				) else if inRun do (
					lo = 1e12
					hi = -1e12
					for j = peakI - w to peakI + w where hs[j] != undefined do (lo = amin lo hs[j]; hi = amax hi hs[j])
					append us (((peakI - 1) as float) / n)
					append hts (hi - lo)
					inRun = false
				)
			)
			#(us, hts)
		)

		fn linkTo n parent = (
			setUserProp n "MaxCarRig_oldParent" (if n.parent == undefined then 0 else n.parent.handle)
			setUserProp n "MaxCarRig_oldTM" (n.transform as string)
			-- A group member must leave its group before it can follow a rig helper; Remove puts it back.
			setUserProp n "MaxCarRig_wasGroupMember" (isGroupMember n)
			-- detachNodesFromGroup refuses some nested members ("invalid input"); clearing the flag does the same job.
			if isGroupMember n do (try (detachNodesFromGroup #(n)) catch (setGroupMember n false))
			n.parent = parent
		)

		-- A part picked inside a closed group stands for that whole group (a wheel group: rim, tyre, brake).
		-- Nested groups are climbed, but never up to the car's own top group, so a wheel group inside a
		-- grouped car stays the wheel.
		fn partOf o = (
			local tops = topLevel (for n in carNodes where isValidNode n collect n)
			while isGroupMember o and not isOpenGroupMember o and o.parent != undefined and isGroupHead o.parent and findItem tops o.parent == 0 do o = o.parent
			o
		)

		fn addSteerInputs ctrl path ca = (
			ctrl.AddNode "sp" path
			ctrl.AddTarget "progress" (getPropertyController ca "progress")
			ctrl.AddTarget "ahead" (getPropertyController ca "lookAhead")
			ctrl.AddTarget "steerMax" (getPropertyController ca "steerMax")
			ctrl.AddObject "rigCA" ca
		)

		fn rigHelper nm tm sz col isBox = (
			local h = Point name:(uniqueName nm) transform:tm size:sz box:isBox cross:(not isBox) \
				axisTripod:false centerMarker:false wirecolor:col
			setUserProp h "MaxCarRig_helper" true
			h
		)

		-- mode: 1 simple, 2 body, 3 per wheel. wheels: #(FL, FR, RL, RR), entries may be undefined.
		-- Every local is declared at the top: Max 2026 throws "Bad free thunk" for locals
		-- declared inside if/else blocks and then read in a for-loop.
		fn buildRig cars path grounds bottom fwdIndex mode rayUp wheels usePivot lookAhead steerMax bank = (
			local picked, base, tm, inv, bb, carLen, carWid, carSize, wheelSize, root, m, ca, offs, lenText, suspH, psc, cw, rest, bankRest, b, tyreCyls = #(), later = #(), wb = 0.0, rearD = 0.0, rearC
			-- The spline length is measured once here and written into the scripts: measuring it every frame
			-- in every script was a large share of the playback cost. Rebuild the rig after editing the spline.
			lenText = (amax 0.001 (curveLength path 1)) as string
			local aim, ac, fl, fr, steering, front, axleZ, bankTm, bankH, bc, sc, st, sh, wheelParts, bodyNodes, c, s, ctrl, spinH, spc, wheelHolder, wt, axisK, axisSign, baseRot, cyl, axle, tw
			local steerHs = #(undefined, undefined), corners = #("FL", "FR", "RL", "RR"), axisNames = #("rotateXMatrix", "rotateYMatrix", "rotateZMatrix")

			picked = for w in wheels where w != undefined collect w
			base = (topLevel cars)[1].name
			tm = startFrame bottom fwdIndex
			inv = inverse tm

			-- Sizes come from the car and wheels so the helpers are readable at any scale.
			bb = bboxOf (cars + picked)
			carLen = if fwdIndex <= 2 then bb[2].x - bb[1].x else bb[2].y - bb[1].y
			carWid = if fwdIndex <= 2 then bb[2].y - bb[1].y else bb[2].x - bb[1].x
			carSize = amax carLen carWid
			wheelSize = carSize * 0.15
			if picked.count > 0 do (
				wheelSize = 0.0
				for w in picked do wheelSize += wheelRadius w * 2 / picked.count
			)

			-- The root is a rectangle round the car's footprint: helpers cannot hold modifiers, shapes can.
			root = Rectangle name:(uniqueName (base + "_CarRig")) transform:tm \
				width:(carLen * 1.15) length:(carWid * 1.25) wirecolor:(color 210 200 185)
			setUserProp root "MaxCarRig" true
			m = EmptyModifier name:"Car Rig"
			addModifier root m
			custAttributes.add m (paramsCA())
			ca = custAttributes.get m 1
			for p in #(#progress, #lookAhead, #steerMax, #bank, #rayUp, #spin, #suspension, #travel) do setPropertyController ca (p as string) (bezier_float())
			-- Wheels may move up or down by half a wheel radius by default.
			ca.travel = if picked.count > 0 then wheelRadius picked[1] * 0.5 else carSize * 0.03
			ca.lookAhead = lookAhead
			ca.steerMax = steerMax
			ca.bank = bank
			ca.rayUp = rayUp
			ca.cornerRadius = units.decodeValue "20m"
ca.metre = units.decodeValue "1m"
			ca.pathHandle = path.handle
			ca.wheelR = if picked.count > 0 then wheelRadius picked[1] else carSize * 0.06
			b = findBumps path grounds
			ca.bumpU = b[1]
			ca.bumpH = b[2]
			-- Progress runs 0 to 100 over the active time range on linear keys, so the speed is constant.
			with animate on (
				at time animationRange.start ca.progress = 0.0
				at time animationRange.end ca.progress = 100.0
			)
			for k in (getPropertyController ca "progress").keys do (
				k.inTangentType = #linear
				k.outTangentType = #linear
			)

			offs = #()
			if mode == 1 then (
				for n in topLevel cars do linkTo n root
			) else (
				aim = rigHelper (base + "_CarRig_Aim") (matrix3 1) (wheelSize * 0.8) (color 243 240 237) true
				ac = position_script()
				aim.position.controller = ac
				ac.AddNode "sp" path
				ac.AddTarget "progress" (getPropertyController ca "progress")
				ac.AddTarget "ahead" (getPropertyController ca "lookAhead")
				ac.AddObject "rigCA" ca
				ac.script = substituteString aimScript "%LEN%" lenText
				setUserProp root "MaxCarRig_aim" aim.handle

				fl = wheels[1]
				fr = wheels[2]
				steering = isValidNode fl and isValidNode fr
				front = if steering then ((wheelCentre fl usePivot + wheelCentre fr usePivot) / 2) * inv else [0,0,0]
				-- Steer from the car centre line: the aim sits on the spline, which is the root X axis,
				-- so a straight spline gives exactly zero steer even if the two wheels are not symmetric.
				front.y = 0.0
				-- Wheelbase and where the rear axle sits behind the rig root, for rear-axle tracking and steering.
				if steering and isValidNode wheels[3] and isValidNode wheels[4] do (
					rearC = ((wheelCentre wheels[3] usePivot + wheelCentre wheels[4] usePivot) / 2) * inv
					wb = front.x - rearC.x
					rearD = -rearC.x
					if wb <= 0.0 do (wb = 0.0; rearD = 0.0)
				)

				-- Bank pivots at wheel centre height so the body rolls about its axle line, not the ground.
				axleZ = 0.0
				for w in picked do axleZ += ((wheelCentre w usePivot) * inv).z / picked.count
				bankTm = copy tm
				bankTm.row4 = tm.pos + [0, 0, axleZ]
				bankH = rigHelper (base + "_CarRig_Bank") bankTm (carSize * 0.4) (color 150 138 122) false
				bankH.parent = root
				bankRest = bankH.position.controller.value
				bc = transform_script()
				addSteerInputs bc path ca
				bc.AddTarget "bank" (getPropertyController ca "bank")
				bc.AddNode "rig" root
				bc.AddObject "progCtrl" (getPropertyController ca "progress")
				bc.script = substituteString (substituteString bankScript "%METRE%" ((units.decodeValue "1m") as string)) "%REST%" (bankRest as string)
				append later #(bankH, #transform, bc)

				if steering do (
					for i = 1 to 2 do (
						-- One script per front wheel: the inner wheel steers a little more (Ackermann).
						sc = rotation_script()
						addSteerInputs sc path ca
						s = substituteString (substituteString steerScript "%FRONTDIST%" (front.x as string)) "%LEN%" lenText
						s = substituteString (substituteString s "%WB%" (wb as string)) "%REAR%" (rearD as string)
						sc.script = substituteString s "%SIDE%" ((((wheelCentre wheels[i] usePivot) * inv).y) as string)
						st = copy tm
						st.row4 = wheelCentre wheels[i] usePivot
						sh = rigHelper (base + (if i == 1 then "_CarRig_SteerFL" else "_CarRig_SteerFR")) st (wheelSize * 1.3) (color 196 120 90) true
						sh.parent = root
						append later #(sh, #rotation, sc)
						steerHs[i] = sh
					)
				)
				-- Each wheel hangs from a spin helper at its centre, under its steer helper (front) or the root.
				for i = 1 to 4 where isValidNode wheels[i] do (
					wheelHolder = if i <= 2 and steering then steerHs[i] else root
					-- Start from the wheel pivot rotation (scale removed) so the spin axis is the wheel own axle.
					wt = wheels[i].transform
					st = matrix3 (normalize wt.row1) (normalize wt.row2) (normalize wt.row3) (wheelCentre wheels[i] usePivot)
					axisK = 1
					for k = 2 to 3 do if abs (dot st[k] tm.row2) > abs (dot st[axisK] tm.row2) do axisK = k
					axisSign = if (dot st[axisK] tm.row2) < 0 then -1 else 1
					spinH = rigHelper (base + "_CarRig_Spin" + corners[i]) st (wheelSize * 1.1) (color 225 214 198) false
					-- Suspension helper at the wheel centre, in the rig's orientation, between the holder and the spin.
					cw = copy tm
					cw.row4 = wheelCentre wheels[i] usePivot
					suspH = rigHelper (base + "_CarRig_Susp" + corners[i]) cw (wheelSize * 0.9) (color 170 160 150) false
					suspH.parent = wheelHolder
					rest = suspH.position.controller.value
					-- The tyre's collision shape: a cylinder gizmo (outline only, never renders) the size of the tyre
					-- that steers and rises with the wheel (it does not spin). The ground scripts read its Radius and
					-- Height, so editing those changes how the tyre meets kerbs and bumps.
					axle = normalize tm.row2
					tw = 2.0 * (amax 0.001 (tyreHalfWidth wheels[i] tm.row2))
					-- Placed on the tyre mesh itself (not the wheel pivot), and centred by its own box so it sits on
					-- the tyre whichever end of the gizmo its pivot is.
					c = wheelCentre wheels[i] false
					if tyreEdits != undefined and tyreEdits[i] != undefined then (
						cyl = CylGizmo name:(uniqueName (base + "_CarRig_Tyre" + corners[i])) radius:tyreEdits[i][2] height:tyreEdits[i][3]
						cyl.transform = tyreEdits[i][1] * cw
					) else (
						cyl = CylGizmo name:(uniqueName (base + "_CarRig_Tyre" + corners[i])) radius:(wheelRadius wheels[i]) height:tw
						cyl.transform = matrix3 (normalize tm.row1) (cross axle (normalize tm.row1)) axle c
						cyl.pos += c - (cyl.min + cyl.max) / 2.0
					)
					setUserProp cyl "MaxCarRig_tyre" i
					cyl.wirecolor = color 120 200 255
					setUserProp cyl "MaxCarRig_helper" true
					cyl.parent = suspH
					tyreCyls[i] = cyl
					psc = position_script()
					psc.AddNode "rig" root
					for g = 1 to grounds.count do psc.AddNode ("g" + g as string) grounds[g]
					psc.AddTarget "rayUp" (getPropertyController ca "rayUp")
					psc.AddTarget "suspension" (getPropertyController ca "suspension")
					psc.AddTarget "travel" (getPropertyController ca "travel")
					psc.AddObject "tyreShape" cyl.baseObject
					psc.AddObject "rigCA" ca
					s = substituteString suspScript "%RAYFNS%" rayFns
					s = substituteString s "%GROUNDS%" (listText (for g = 1 to grounds.count collect ("g" + g as string)))
					s = substituteString s "%REST%" (rest as string)
					-- The contact is the bottom of the tyre collision shape (its box centre less its radius), so a
					-- wheel pivot off the tyre's centre cannot push the tyre into the ground, and a hand-fitted
					-- shape is where the tyre meets the ground.
					c = (cyl.min + cyl.max) / 2.0
					s = substituteString s "%CONTACT%" (([c.x, c.y, c.z - cyl.radius] * inv) as string)
					psc.script = s
					append later #(suspH, #position, psc)
					spinH.parent = suspH
					baseRot = (spinH.rotation.controller.value) as matrix3
					spc = rotation_script()
					spc.AddNode "sp" path
					spc.AddTarget "progress" (getPropertyController ca "progress")
					spc.AddTarget "spin" (getPropertyController ca "spin")
					spc.AddObject "rigCA" ca
					s = substituteString spinScript "%RADIUS%" ((amax 0.001 (wheelRadius wheels[i])) as string)
					s = substituteString s "%SIDE%" ((((wheelCentre wheels[i] usePivot) * inv).y) as string)
					s = substituteString s "%AXIS%" axisNames[axisK]
					s = substituteString s "%SIGN%" (axisSign as string)
					spc.script = substituteString (substituteString s "%BASE%" ("(" + baseRot as string + ")")) "%LEN%" lenText
					append later #(spinH, #rotation, spc)
					linkTo wheels[i] spinH
					-- Brakes and callipers steer with the wheel but must not spin with it.
					for n in withDescendants #(wheels[i]) where n != wheels[i] and isBrake n do linkTo n wheelHolder
				)
				-- Anything under a picked wheel (hubcaps, brakes) stays with that wheel.
				wheelParts = withDescendants picked
				bodyNodes = for n in cars where findItem wheelParts n == 0 collect n
				for n in topLevel bodyNodes do linkTo n bankH

				if mode == 3 do (
					for i = 1 to 4 do (
						c = (tyreCyls[i].min + tyreCyls[i].max) / 2.0
						append offs ([c.x, c.y, c.z - tyreCyls[i].radius] * inv)
					)
				)
			)
			linkTo bottom root

			s = substituteString (substituteString rootScript "%RAYFNS%" rayFns) "%MODE%" (mode as string)
			s = substituteString s "%GROUNDS%" (listText (for i = 1 to grounds.count collect ("g" + i as string)))
			s = substituteString s "%OFFSETS%" (listText offs)
			s = substituteString (substituteString s "%WB%" (wb as string)) "%REAR%" (rearD as string)
			s = substituteString s "%TYRES%" (if mode == 3 then "tyre1, tyre2, tyre3, tyre4" else "")
			-- The helper scripts go on only now, with every wheel and body part linked. A script put on earlier
			-- moved its helper at once (the suspension to the ground under the car, steering to the bend), and
			-- whatever was linked to it afterwards kept that as a fixed offset: wheels sat 5 cm into the road.
			for e in later do case e[2] of (
				#position: e[1].position.controller = e[3]
				#rotation: e[1].rotation.controller = e[3]
				#transform: e[1].transform.controller = e[3]
			)
			ctrl = transform_script()
			root.transform.controller = ctrl
			ctrl.AddNode "sp" path
			ctrl.AddTarget "progress" (getPropertyController ca "progress")
			ctrl.AddTarget "rayUp" (getPropertyController ca "rayUp")
			ctrl.AddObject "rigCA" ca
			if mode == 3 do for i = 1 to 4 do ctrl.AddObject ("tyre" + i as string) tyreCyls[i].baseObject
			for i = 1 to grounds.count do ctrl.AddNode ("g" + i as string) grounds[i]
			ctrl.script = s
			root
		)

		-- Puts the rig, its helpers, the aim and every car part on one layer named after the rig, and
		-- remembers each node's old layer so Remove can put it back.
		fn moveToRigLayer root = (
			local lay, nodes, h
			lay = LayerManager.getLayerFromName root.name
			if lay == undefined do lay = LayerManager.newLayerFromName root.name
			nodes = withDescendants #(root)
			h = getUserProp root "MaxCarRig_aim"
			if h != undefined do append nodes (maxOps.getNodeByHandle h)
			for n in nodes where isValidNode n do (
				setUserProp n "MaxCarRig_oldLayer" n.layer.name
				lay.addNode n
			)
		)

		fn removeRig root = (
			local all, h, extras, oldLayer, lay, rigLayerName, moved, depths, d, p, i
			all = withDescendants #(root)
			rigLayerName = root.name
			-- Back to the layers they came from (a layer called 0 reads back as a number, hence as string).
			h = getUserProp root "MaxCarRig_aim"
			for n in all + (if h == undefined then #() else #(maxOps.getNodeByHandle h)) where isValidNode n do (
				oldLayer = getUserProp n "MaxCarRig_oldLayer"
				if oldLayer != undefined do (
					lay = LayerManager.getLayerFromName (oldLayer as string)
					if lay != undefined do lay.addNode n
				)
			)
			for n in all where getUserProp n "MaxCarRig_oldParent" != undefined and getUserProp n "MaxCarRig_helper" != true do (
				h = getUserProp n "MaxCarRig_oldParent"
				n.parent = if h == 0 then undefined else maxOps.getNodeByHandle h
				-- Parts taken out of a group at build time go back into it.
				if getUserProp n "MaxCarRig_wasGroupMember" == true and n.parent != undefined and isGroupHead n.parent do
					(try (attachNodesToGroup #(n) n.parent) catch (setGroupMember n true))
			)
			-- Every part goes back to where it was before the rig (the car's own spot, usually 0,0,0), parents
			-- first so children are not moved twice. Rigs built before 0.13.1 have no record and stay put.
			moved = for n in all where isValidNode n and getUserProp n "MaxCarRig_oldTM" != undefined collect n
			depths = for n in moved collect (d = 0; p = n.parent; while p != undefined do (d += 1; p = p.parent); d)
			with animate off for d = 0 to (if depths.count == 0 then -1 else amax depths) do
				for i = 1 to moved.count where depths[i] == d do moved[i].transform = execute ((getUserProp moved[i] "MaxCarRig_oldTM") as string)
			-- Delete the scripted nodes before the nodes their scripts read (aim, old path helper),
			-- or Max re-evaluates a script whose target has gone and throws errors.
			extras = #()
			for k in #("MaxCarRig_aim", "MaxCarRig_path") do (
				h = getUserProp root k
				if h != undefined do append extras (maxOps.getNodeByHandle h)
			)
			clearSelection()
			delete (for n in all where isValidNode n and getUserProp n "MaxCarRig_helper" == true collect n)
			delete root
			for n in extras where isValidNode n do delete n
			LayerManager.deleteLayerByName rigLayerName
		)

		dotNetControl lblBrand "System.Windows.Forms.Label" width:514 height:20
		dotNetControl lblTitle "System.Windows.Forms.Label" width:514 height:30 offset:[0,-5]
		button btnGuide "Setup guide" width:514
		group "Car and path"
		(
			button btnAuto "Auto detect by name" width:250 across:2
			button btnCar "Use selection as car" width:250
			label lblCar "No car set" align:#left across:2
			pickbutton pbPath "Pick spline" filter:shapeFilt autoDisplay:true width:250
		)
		group "Mode"
		(
			radiobuttons rbMode labels:#("Simple (spline only)", "Body (BOTTOM)", "Per wheel (4 wheels)") columns:3 align:#left default:2
		)
		group "Ground"
		(
			radiobuttons rbGround labels:#("Include list", "Exclude list") columns:2 align:#left across:2
			spinner spRay "Ray start above spline" range:[0, 1e6, 200] type:#worldunits
			listbox lbGround height:3 width:514
			button btnGroundAdd "Add selected" across:3 width:165
			button btnGroundDel "Remove" width:165
			button btnGroundClear "Clear" width:165
		)
		group "BOTTOM"
		(
			button btnBottomMake "Create at car bottom" width:250 across:2
			pickbutton pbBottom "Or pick BOTTOM" autoDisplay:true width:250
		)
		group "Wheels (front pair steers)"
		(
			dropdownlist ddCentre "Wheel centre" items:#("Pivot point", "Tyre centre") width:250 across:2
			dropdownlist ddFwd "Car front faces (world)" items:#("+X", "-X", "+Y", "-Y") width:250
			pickbutton pbFL "Front left wheel" autoDisplay:true width:250 across:2
			pickbutton pbFR "Front right wheel" autoDisplay:true width:250
			pickbutton pbRL "Rear left wheel" autoDisplay:true width:250 across:2
			pickbutton pbRR "Rear right wheel" autoDisplay:true width:250
		)
		group "Options"
		(
			spinner spAhead "Look ahead" range:[0, 1e6, 100] type:#worldunits across:3
			spinner spSteer "Max steer (deg)" range:[0, 89, 35]
			spinner spBank "Bank (deg per g)" range:[-500, 500, 70]
		)
		checkbox cbRigLayer "Put the rig and car on their own layer (untick to leave them where they are)" checked:true
		button btnBuild "Build rig" width:165 height:28 across:3
		button btnRefresh "Refresh selected rig" width:165 height:28
		button btnRemove "Remove selected rig" width:165 height:28
		group "Change a built rig (select its rig rectangle first)"
		(
			label lblEdit "No rig selected" align:#left
			listbox lbEditGround height:3 width:514
			button btnEditAdd "Add selected" width:122 across:4
			button btnEditDel "Remove" width:122
			button btnEditSurf "Add CAR SURFACE" width:122
			pickbutton pbEditPath "Pick new spline" filter:shapeFilt width:122
		)
		group "Bake"
		(
			radiobuttons rbBakeRange labels:#("Timeline", "Custom range") columns:2 align:#left across:3
			spinner spBakeFrom "From frame" type:#integer range:[-100000, 100000, 0] enabled:false
			spinner spBakeTo "To" type:#integer range:[-100000, 100000, 100] enabled:false
			button btnBake "Bake a copy of the selected rig" width:514
		)
		button btnCheck "Check steering (selected rig)" width:165 across:3
		button btnSpeed "Speed test (selected rig)" width:165
		button btnLog "Open log" width:165
		group "About"
		(
			label lblA0 "(c) 2026 Visualisation One. All rights reserved." align:#left
			label lblA1 "Provided \"as is\", without warranty. To the extent permitted by law, the authors are" align:#left
			label lblA2 "not liable for any loss or damage from using it. Back up your work." align:#left
		)

		-- Build stores what each rig was built from on the rig itself, so Refresh can rebuild it the same way.
		-- Handles are written as "n12_15_0" (a leading letter keeps getUserProp from reading it as a number).
		fn handlesText nodes = (
			local s = "n"
			for i = 1 to nodes.count do s += (if i > 1 then "_" else "") + (if isValidNode nodes[i] then nodes[i].handle else 0) as string
			s
		)
		fn nodesFrom txt = (
			local parts = filterString ((txt as string) + "") "n_"
			for h in parts collect maxOps.getNodeByHandle (h as integer)
		)
		-- Reads a user property as raw text (getUserProp would try to turn "n12_15" into a value).
		fn rawProp node key = (
			local hit = undefined, p
			for l in filterString (getUserPropBuffer node) "\r\n" where hit == undefined do (
				p = findString l "="
				if p != undefined and trimRight (trimLeft (substring l 1 (p - 1))) == key do hit = trimLeft (substring l (p + 1) -1)
			)
			hit
		)
		fn saveBuildInfo root cars path grounds bottom fwdIndex mode wheels usePivot useLayer = (
			setUserProp root "MaxCarRig_inCars" (handlesText cars)
			setUserProp root "MaxCarRig_inPath" (handlesText #(path))
			setUserProp root "MaxCarRig_inGrounds" (handlesText grounds)
			setUserProp root "MaxCarRig_inBottom" (handlesText #(bottom))
			setUserProp root "MaxCarRig_inWheels" (handlesText wheels)
			setUserProp root "MaxCarRig_inMode" mode
			setUserProp root "MaxCarRig_inFwd" fwdIndex
			setUserProp root "MaxCarRig_inPivot" usePivot
			setUserProp root "MaxCarRig_inLayer" useLayer
		)
		fn rigParams root = (
			local m = (for x in root.modifiers where classOf x == EmptyModifier collect x)[1]
			if m == undefined then undefined else custAttributes.get m 1
		)

		-- Keep speed: when a spline's length changes, the rig's Progress keys are stretched by the same amount, so
		-- the speed stays the same and any keys edited in the Curve Editor keep their shape. Max also fires change
		-- events when nothing really changed (selecting things, opening panels), so the length is compared first.
		-- Editing the Progress keys by hand (Curve Editor, Auto Key) turns Keep speed off, so a later spline edit
		-- cannot change them, and says so on the status bar. Each redraw compares every Keep speed rig's keys with
		-- a snapshot; the rig's own re-timing updates the snapshot so it is not taken for a hand edit.
		fn progressSig ca = (
			local c = getPropertyController ca "progress"
			if c == undefined then "" else (for k in c.keys collect #(k.time, k.value)) as string
		)
		fn checkSpeedKeys = (
			local s
			global MaxCarRig_rigCAs
			if MaxCarRig_rigCAs != undefined do for e in MaxCarRig_rigCAs do try (
				if not e[1].speedLocked then e[2] = undefined
				else (
					s = progressSig e[1]
					if e[2] == undefined then e[2] = s
					else if s != e[2] do (
						e[2] = undefined
						undo off e[1].speedLocked = false
						displayTempPrompt "Car Rig: Progress keys edited by hand, so Keep speed is now off. Press Set run from speed to turn it back on." 10000
					)
				)
			) catch ()
		)
		fn stretchProgress ca ratio = (
			local c, n, t0, i, k
			c = getPropertyController ca "progress"
			n = if c == undefined then 0 else c.keys.count
			if n >= 2 do (
				t0 = c.keys[1].time
				-- move keys from the far end when stretching and from the near end when shrinking, so none pass another
				for i in (if ratio > 1.0 then (for j = n to 2 by -1 collect j) else (for j = 2 to n collect j)) do (
					k = c.keys[i]
					k.time = t0 + (k.time - t0) * ratio
				)
				if c.keys[n].time > animationRange.end do animationRange = interval animationRange.start c.keys[n].time
			)
		)

		-- Edits to a rig's spline or ground are picked up at once: the stored spline table, speed plan and
		-- ground grid for that object are dropped (rebuilt on the next frame), and rigs with Keep speed on get
		-- their Progress keys stretched to the new spline length. Watchers are set up for every rig in the scene
		-- when the tool opens and when a rig is built or refreshed.
		fn onSplineChanged sp = (
			local i, ca, len, oldLen
			global MaxCarRig_splines4, MaxCarRig_plans, MaxCarRig_lens, MaxCarRig_rigCAs
			if MaxCarRig_splines4 != undefined do for i = MaxCarRig_splines4.count to 1 by -1 where MaxCarRig_splines4[i][1] == sp do deleteItem MaxCarRig_splines4 i
			if MaxCarRig_plans != undefined do for i = MaxCarRig_plans.count to 1 by -1 where MaxCarRig_plans[i][1] == sp do deleteItem MaxCarRig_plans i
			if MaxCarRig_lens == undefined do MaxCarRig_lens = #()
			len = curveLength sp 1
			for e in MaxCarRig_lens where e[1] == sp do (oldLen = e[2]; e[2] = len)
			if oldLen == undefined then append MaxCarRig_lens #(sp, len)
			else if oldLen > 0.0 and abs (len - oldLen) > oldLen * 1e-6 do
				for r in objects where getUserProp r "MaxCarRig" == true do (
					ca = rigParams r
					if ca != undefined and ca.pathHandle == sp.handle and (try (ca.speedLocked) catch (false)) do (
						stretchProgress ca (len / oldLen)
						if MaxCarRig_rigCAs != undefined do for e in MaxCarRig_rigCAs where e[1] == ca do e[2] = progressSig ca
					)
				)
		)
		fn onGroundChanged g = (
			local i
			global MaxCarRig_grids
			if MaxCarRig_grids != undefined do for i = MaxCarRig_grids.count to 1 by -1 where MaxCarRig_grids[i][1] == g do deleteItem MaxCarRig_grids i
		)
		fn watchRigs = (
			local splines = #(), grounds = #(), h, ca
			global MaxCarRig_onSpline, MaxCarRig_onGround, MaxCarRig_lens, MaxCarRig_rigCAs, MaxCarRig_onRedraw
			MaxCarRig_onSpline = onSplineChanged
			MaxCarRig_onGround = onGroundChanged
			deleteAllChangeHandlers id:#MaxCarRigWatch
			for r in objects where getUserProp r "MaxCarRig" == true do (
				h = rawProp r "MaxCarRig_inPath"
				if h != undefined do for n in nodesFrom h where isValidNode n and findItem splines n == 0 do append splines n
				h = rawProp r "MaxCarRig_inGrounds"
				if h != undefined do for n in nodesFrom h where isValidNode n and findItem grounds n == 0 do append grounds n
			)
			MaxCarRig_lens = for sp in splines collect #(sp, curveLength sp 1)
			MaxCarRig_rigCAs = for r in objects where getUserProp r "MaxCarRig" == true and (ca = rigParams r) != undefined collect #(ca, undefined)
			if MaxCarRig_onRedraw != undefined do unRegisterRedrawViewsCallback MaxCarRig_onRedraw
			MaxCarRig_onRedraw = checkSpeedKeys
			registerRedrawViewsCallback MaxCarRig_onRedraw
			if splines.count > 0 do (
				when geometry splines changes id:#MaxCarRigWatch handleAt:#redrawViews sp do MaxCarRig_onSpline sp
				when transform splines changes id:#MaxCarRigWatch handleAt:#redrawViews sp do MaxCarRig_onSpline sp
			)
			if grounds.count > 0 do
				when geometry grounds changes id:#MaxCarRigWatch handleAt:#redrawViews g do MaxCarRig_onGround g
		)

		fn refreshUI = (
			local full = rbMode.state > 1
			for c in #(rbGround, lbGround, btnGroundAdd, btnGroundDel, btnGroundClear, spRay, ddCentre, \
				pbFL, pbFR, pbRL, pbRR, spAhead, spSteer, spBank) do c.enabled = full
			lbGround.items = for g in groundList where isValidNode g collect g.name
		)
		fn showEditRig = (
			global MaxCarRig_editRoot
			local r = MaxCarRig_editRoot
			if isValidNode r and getUserProp r "MaxCarRig" == true and rawProp r "MaxCarRig_inCars" != undefined then (
				lblEdit.text = "Changing: " + r.name + (if getUserProp r "MaxCarRig_inMode" == 1 then "  (Simple mode does not use ground)" else "")
				lbEditGround.items = for n in nodesFrom (rawProp r "MaxCarRig_inGrounds") where isValidNode n collect n.name
			) else (
				MaxCarRig_editRoot = undefined
				lblEdit.text = "No rig selected"
				lbEditGround.items = #()
			)
		)
		fn onSelChanged = (
			global MaxCarRig_editRoot
			local r = (for o in selection where getUserProp o "MaxCarRig" == true collect o)[1]
			if r != undefined do MaxCarRig_editRoot = r
			showEditRig()
		)

		on MaxCarRig_UI open do (
			local fontStyle = dotNetClass "System.Drawing.FontStyle"
			-- Rays start 2 m above the spline whatever the scene units (200 units was only 20 cm in a mm scene).
			spRay.value = units.decodeValue "2m"
			watchRigs()
			-- Re-reading the modifier definition brings rigs built with older versions up to date (new panels).
			paramsCA()
			global MaxCarRig_onSel
			MaxCarRig_onSel = onSelChanged
			callbacks.removeScripts id:#MaxCarRigSel
			callbacks.addScript #selectionSetChanged "MaxCarRig_onSel()" id:#MaxCarRigSel
			onSelChanged()
			for t in #(#root, #aim, #steer, #bank, #spin) do case t of (
				#root: rootScript = substituteString rootScript "%SPLINEFNS%" splineFns
				#aim: aimScript = substituteString aimScript "%SPLINEFNS%" splineFns
				#steer: steerScript = substituteString steerScript "%SPLINEFNS%" splineFns
				#bank: bankScript = substituteString bankScript "%SPLINEFNS%" splineFns
				#spin: spinScript = substituteString spinScript "%SPLINEFNS%" splineFns
			)
			for l in #(lblBrand, lblTitle) do (
				l.BackColor = uiColour #background
				l.ForeColor = uiColour #text
			)
			lblBrand.Font = dotNetObject "System.Drawing.Font" "Georgia" 8 fontStyle.Regular
			lblBrand.Text = "VISUALISATION ONE      v" + toolVersion
			lblTitle.Font = dotNetObject "System.Drawing.Font" "Georgia" 15 fontStyle.Regular
			lblTitle.Text = "Simple Car Rig"
			spAhead.value = units.decodeValue "4m"
			logLine ("Opened tool v" + toolVersion + ". Max version " + ((maxVersion())[1] as string) + ", log: " + logPath)
			refreshUI()
		)
		on rbMode changed s do (
			logLine ("Mode " + modeNames[s])
			refreshUI()
		)
		on rbGround changed s do logLine ("Ground " + groundNames[s])
		on rbBakeRange changed s do (
			spBakeFrom.enabled = (s == 2)
			spBakeTo.enabled = (s == 2)
			if s == 2 do (
				spBakeFrom.value = animationRange.start.frame as integer
				spBakeTo.value = animationRange.end.frame as integer
			)
		)

		-- Auto detect finds the parts by name: FRONT_LEFT, FRONT_RIGHT, BACK_LEFT, BACK_RIGHT (or REAR_),
		-- BODY, CAR PATH and CAR SURFACE. Spaces, dashes and upper or lower case do not matter.
		fn tagOf n = toUpper (substituteString (substituteString n.name " " "_") "-" "_")
		fn findTagged tags = (
			local hit = undefined
			for n in objects where hit == undefined and findItem tags (tagOf n) != 0 do hit = n
			hit
		)

		on btnGuide pressed do messageBox ( \
			"1. Name your parts:\n" + \
			"    BODY = the car body (a group is fine)\n" + \
			"    FRONT_LEFT, FRONT_RIGHT, BACK_LEFT, BACK_RIGHT = the wheels\n" + \
			"    CAR PATH = the spline to drive along\n" + \
			"    CAR SURFACE = the road or ground\n\n" + \
			"2. Put each wheel's pivot in its centre:\n" + \
			"    Hierarchy > Affect Pivot Only > Center to Object.\n\n" + \
			"3. Press Auto detect by name. Check what it found.\n\n" + \
			"4. Pick a mode. Per wheel follows bumps best.\n\n" + \
			"5. Press Build rig.\n\n" + \
			"6. Select the rig rectangle. The Car Rig modifier sets\n" + \
			"    Progress, steering, Bank, Tyre spin, Suspension and Realistic body motion.\n\n" + \
			"7. For smooth playback, press Bake a copy of the selected rig.\n" + \
			"    The copy gets its own layer and the rig is hidden. Esc cancels.\n\n" + \
			"8. To take the rig off, select it and press Remove selected rig.\n\n" + \
			"Something wrong? Press Open log and send the log.") title:("V1 Simple Car Rig " + toolVersion + " - Setup guide")

		on btnAuto pressed do (
			local body, w, surf, surfs, found = #(), missing = #(), i
			local pbs = #(pbFL, pbFR, pbRL, pbRR), cornerNames = #("FL", "FR", "RL", "RR")

			body = findTagged #("BODY", "CAR_BODY")
			if body != undefined then (
				carNodes = withDescendants #(body)
				lblCar.text = carNodes.count as string + " object(s): " + body.name
				append found ("car " + body.name + " (" + carNodes.count as string + " parts)")
			) else append missing "BODY"

			for i = 1 to 4 do (
				w = findTagged wheelTags[i]
				if w != undefined then (
					wheelNodes[i] = w
					pbs[i].object = w
					append found (cornerNames[i] + " " + w.name)
				) else append missing wheelTags[i][1]
			)

			w = findTagged #("CAR_PATH", "PATH")
			if w != undefined and shapeFilt w then (
				pathShape = w
				pbPath.object = w
				append found ("path " + w.name)
			) else append missing "CAR PATH"

			-- Every object named CAR SURFACE..., CAR SURFACE001, CAR SURFACE_02 and so on, plus everything inside them.
			surfs = for n in objects where matchPattern (tagOf n) pattern:"CAR_SURFACE*" or tagOf n == "SURFACE" collect n
			if surfs.count > 0 then (
				groundList = #()
				for g in withDescendants surfs where geoFilt g and findItem groundList g == 0 do append groundList g
				rbGround.state = 1
				append found ("ground " + names surfs + " (" + groundList.count as string + " meshes)")
			) else append missing "CAR SURFACE"

			-- BOTTOM is looked up by the tool's own helper name only: cars often have a mesh called "bottom".
			w = undefined
			for n in objects where w == undefined and matchPattern n.name pattern:"CarRig_BOTTOM*" and findItem carNodes n == 0 do w = n
			if w == undefined and carNodes.count > 0 do undo "Create BOTTOM" on (w = makeBottom carNodes)
			if w != undefined do (
				bottomNode = w
				pbBottom.object = w
				append found ("BOTTOM " + w.name)
			)

			if (for x in wheelNodes where isValidNode x collect x).count == 4 and groundList.count > 0 do rbMode.state = 3
			refreshUI()
			logLine ("Auto detect. Found: " + listText found + " | missing: " + listText missing)
			messageBox ("Found:\n" + listText found + (if missing.count > 0 then ("\n\nNot found: " + listText missing) else "")) title:"Car Rig"
		)

		-- Bakes a copy: instance copies of every car part (geometry shared, so they stay light), keyed on every
		-- frame of the range, on their own layer. The live rig is left as it was and hidden, so its scripts cost
		-- nothing during playback. Unhide it to change things and bake again.
		on btnBake pressed do (
			local root, all, parts, srcs, copies, depths, order, d, maxD, i, k, f, frames, cancelled, fromT, toT, lay, layerName, h, aimH, n
			root = (for o in selection where getUserProp o "MaxCarRig" == true collect o)[1]
			if root == undefined then messageBox "Select a rig first (the ..._CarRig rectangle)." title:"Car Rig"
			else if queryBox "Bake a copy of this car to keys on every frame?\n\nThe copy goes on its own layer and the live rig is hidden. Unhide the rig to change it and bake again." title:"Car Rig" do (
				all = withDescendants #(root)
				h = getUserProp root "MaxCarRig_aim"
				aimH = if h == undefined then undefined else maxOps.getNodeByHandle h
				-- Car parts only: no rig root, rig helpers or BOTTOM marker.
				parts = for n in all where n != root and getUserProp n "MaxCarRig_helper" != true and not matchPattern n.name pattern:"CarRig_BOTTOM*" collect n
				-- Outside a custom range the copy holds its first and last baked positions.
				fromT = if rbBakeRange.state == 2 then (amin spBakeFrom.value spBakeTo.value) as time else animationRange.start
				toT = if rbBakeRange.state == 2 then (amax spBakeFrom.value spBakeTo.value) as time else animationRange.end
				frames = #()
				for f = fromT to toT do append frames f

				cancelled = false
				-- Esc cancels like the Cancel button. Max's own Esc interrupt is off meanwhile: it would stop the
				-- script mid-bake and skip the clean-up below, leaving a half-made copy.
				escapeEnable = false
				progressStart "Baking car copy (Esc or Cancel to stop)"
				undo "Bake car copy" on (
					srcs = #()
					copies = #()
					maxOps.cloneNodes parts cloneType:#instance actualNodeList:&srcs newNodes:&copies
					layerName = root.name + "_Baked"
					lay = LayerManager.getLayerFromName layerName
					if lay == undefined do lay = LayerManager.newLayerFromName layerName
					for i = 1 to copies.count do (
						copies[i].name = uniqueName (srcs[i].name + "_baked")
						-- A copy whose parent was not copied (a rig helper) would still follow the rig: unlink it.
						if copies[i].parent != undefined and findItem copies copies[i].parent == 0 do copies[i].parent = undefined
						copies[i].transform.controller = prs()
						lay.addNode copies[i]
					)
					-- Key parents before children, so each child's key lands relative to an already-keyed parent.
					depths = for c in copies collect (
						d = 0
						n = c.parent
						while n != undefined do (d += 1; n = n.parent)
						d
					)
					maxD = 0
					for d in depths do maxD = amax maxD d
					order = #()
					for d = 0 to maxD do for i = 1 to copies.count where depths[i] == d do append order i
					with animate on (
						for k = 1 to frames.count while not cancelled do (
							for i in order do at time frames[k] copies[i].transform = (at time frames[k] srcs[i].transform)
							if not (progressUpdate (100.0 * k / frames.count)) or keyboard.escPressed do cancelled = true
						)
					)
					if not cancelled do (
						for n in all do n.isHidden = true
						if isValidNode aimH do aimH.isHidden = true
					)
				)
				if cancelled do max undo
				progressEnd()
				escapeEnable = true
				if cancelled then logLine ("Bake of " + root.name + " cancelled; nothing changed")
				else logLine ("Baked a copy of " + root.name + ": " + copies.count as string + " parts on layer " + layerName + ", frames " + fromT as string + " to " + toT as string + ". Live rig hidden.")
			)
		)

		on btnCar pressed do (
			local inside, w, i, pbs = #(pbFL, pbFR, pbRL, pbRR)
			carNodes = for o in selection collect o
			inside = withDescendants carNodes
			for i = 1 to 4 do (
				w = (for n in inside where findItem wheelTags[i] (tagOf n) != 0 collect n)[1]
				if w != undefined do (
					wheelNodes[i] = w
					pbs[i].object = w
					logLine ("Wheel " + i as string + " found inside the car: " + w.name)
				)
			)
			lblCar.text = if carNodes.count == 0 then "No car set" else (carNodes.count as string + " object(s): " + carNodes[1].name)
			logLine ("Car set: " + names carNodes)
		)
		on pbPath picked o do (
			pathShape = o
			logLine ("Path: " + o.name)
		)
		on btnGroundAdd pressed do (
			-- The car is usually still selected here; skip its parts so it never becomes its own ground.
			local carAll = withDescendants (for n in carNodes where isValidNode n collect n)
			local sel = for o in selection collect o
			local added = #(), skipped = #(), why
			for o in sel do (
				-- Group heads are skipped quietly: their member meshes in the same selection are the ground.
				why = case of (
					(findItem groundList o != 0): undefined
					(findItem carAll o != 0): "part of the car"
					(isGroupHead o): undefined
					(not geoFilt o): "not geometry (" + (classOf o) as string + ")"
					default: undefined
				)
				if why != undefined then append skipped (o.name + ": " + why)
				else if findItem groundList o == 0 and not isGroupHead o do append added o
			)
			join groundList added
			logLine ("Ground add. Selected: " + names sel + " | added: " + names added + " | skipped: " + listText skipped + " | list now: " + names groundList)
			refreshUI()
			if sel.count == 0 then messageBox "Select the ground objects in the viewport first, then press Add selected." title:"Car Rig"
			else if added.count == 0 and skipped.count > 0 do
				messageBox ("Nothing added.\n\n" + listText skipped + "\n\nIf a ground object shows as part of the car, press Use selection as car again with only the car selected.") title:"Car Rig"
		)
		on btnGroundDel pressed do (
			local valid = for g in groundList where isValidNode g collect g
			if lbGround.selection > 0 do deleteItem valid lbGround.selection
			groundList = valid
			logLine ("Ground remove. List now: " + names groundList)
			refreshUI()
		)
		on btnGroundClear pressed do (
			groundList = #()
			logLine "Ground list cleared"
			refreshUI()
		)
		-- Quick speed test: times the rig root, the aim and one helper of each kind over 3 frames, then the
		-- viewport redraw with the car shown and hidden. Esc or Cancel stops it; what was measured is kept.
		on btnSpeed pressed do (
			local root, all, carParts, wasHidden, aimH, h, t0, tNow, frames = 3, start, span, probes, kinds, hit, i, k, stopped, timeAt
			root = (for o in selection where getUserProp o "MaxCarRig" == true collect o)[1]
			if root == undefined then messageBox "Select a rig first (the ..._CarRig rectangle)." title:"Car Rig"
			else (
				all = withDescendants #(root)
				carParts = for n in all where n != root and getUserProp n "MaxCarRig_helper" != true collect n
				h = getUserProp root "MaxCarRig_aim"
				aimH = if h == undefined then undefined else maxOps.getNodeByHandle h
				start = animationRange.start
				span = animationRange.end - animationRange.start
				tNow = sliderTime
				probes = #(#("rig root (ground rays)", root))
				if isValidNode aimH do append probes #("aim null", aimH)
				kinds = #(#("body", "*_CarRig_Bank*"), #("steering", "*_CarRig_Steer*"), #("suspension", "*_CarRig_Susp*"), #("tyre spin", "*_CarRig_Spin*"))
				for k in kinds do (
					hit = undefined
					for n in all where hit == undefined and matchPattern n.name pattern:k[2] do hit = n
					if hit != undefined do append probes #(k[1], hit)
				)
				logLine ("Speed test on " + root.name + ": " + frames as string + " frames, " + carParts.count as string + " car parts")
				stopped = false
				escapeEnable = false
				progressStart "Speed test (Esc or Cancel to stop)"
				for k = 1 to probes.count while not stopped do (
					t0 = timeStamp()
					for i = 1 to frames do at time (start + span * i / frames) probes[k][2].transform
					logLine ("  " + probes[k][1] + ": " + ((timeStamp() - t0) / frames as float) as string + " ms per frame")
					if not (progressUpdate (100.0 * k / (probes.count + 2))) or keyboard.escPressed do stopped = true
				)
				if not stopped do (
					t0 = timeStamp()
					for i = 1 to frames do (sliderTime = start + span * i / frames; completeRedraw())
					logLine ("  viewport redraw, car shown: " + ((timeStamp() - t0) / frames as float) as string + " ms per frame")
					if not (progressUpdate (100.0 * (probes.count + 1) / (probes.count + 2))) or keyboard.escPressed do stopped = true
				)
				if not stopped do (
					wasHidden = for n in carParts collect n.isHidden
					for n in carParts do n.isHidden = true
					t0 = timeStamp()
					for i = 1 to frames do (sliderTime = start + span * i / frames; completeRedraw())
					logLine ("  viewport redraw, car hidden: " + ((timeStamp() - t0) / frames as float) as string + " ms per frame")
					for i = 1 to carParts.count do carParts[i].isHidden = wasHidden[i]
				)
				progressEnd()
				escapeEnable = true
				sliderTime = tNow
				if stopped do logLine "  speed test stopped early"
				messageBox ("Speed test done. Press Open log and send me the Speed test lines.") title:"Car Rig"
			)
		)
		-- Writes the real numbers behind the steering at the current frame, for bug reports.
		on btnCheck pressed do (
			local root, tm, h, aimH, a, all, rel
			root = (for o in selection where getUserProp o "MaxCarRig" == true collect o)[1]
			if root == undefined then messageBox "Select a rig first (the ..._CarRig rectangle)." title:"Car Rig"
			else (
				tm = root.transform
				all = withDescendants #(root)
				h = getUserProp root "MaxCarRig_aim"
				aimH = if h == undefined then undefined else maxOps.getNodeByHandle h
				logLine ("Check steering on " + root.name + " at frame " + sliderTime as string)
				logLine ("  rig pos " + tm.row4 as string + ", X " + tm.row1 as string + ", Y " + tm.row2 as string + ", Z " + tm.row3 as string)
				if isValidNode aimH do (
					a = aimH.pos * inverse tm
					logLine ("  aim world " + aimH.pos as string + ", aim in rig space " + a as string)
				)
				for n in all where matchPattern n.name pattern:"*_CarRig_Steer*" do (
					logLine ("  " + n.name + ": local rotation " + (n.rotation.controller.value as eulerAngles) as string + ", world X " + n.transform.row1 as string)
					logLine ("    script: " + substituteString (substituteString n.rotation.controller.script "\n" " ") "\t" "")
				)
				for n in all where matchPattern n.name pattern:"*_CarRig_Susp*" do
					logLine ("  " + n.name + ": local position " + n.position.controller.value as string + " (z is the suspension height)")
				for n in all where matchPattern n.name pattern:"*_CarRig_Bank*" do (
					rel = n.transform * inverse n.parent.transform
					logLine ("  " + n.name + ": body tilt " + (rel.rotationpart as eulerAngles) as string + ", offset " + rel.row4 as string)
				)
				if MaxCarRig_lastBody != undefined do
					logLine ("  body maths at frame " + MaxCarRig_lastBody[1] as string + ": forward g " + MaxCarRig_lastBody[2] as string + ", sideways g " + MaxCarRig_lastBody[3] as string + ", roll " + MaxCarRig_lastBody[4] as string + ", pitch " + MaxCarRig_lastBody[5] as string + ", ground lag rise/pitch/roll " + MaxCarRig_lastBody[6] as string + " / " + MaxCarRig_lastBody[7] as string + " / " + MaxCarRig_lastBody[8] as string)
				for n in all where matchPattern n.name pattern:"*_CarRig_Spin*" do
					logLine ("  " + n.name + ": world X " + n.transform.row1 as string + ", Y " + n.transform.row2 as string + ", Z " + n.transform.row3 as string)
				messageBox "Steering check written. Press Open log and send me the Check steering lines." title:"Car Rig"
			)
		)
		on btnLog pressed do (
			if doesFileExist logPath then shellLaunch logPath "" else messageBox ("No log yet: " + logPath) title:"Car Rig"
		)
		on btnBottomMake pressed do (
			carNodes = for n in carNodes where isValidNode n collect n
			if carNodes.count == 0 then messageBox "Set the car first." title:"Car Rig"
			else (
				undo "Create BOTTOM" on (bottomNode = makeBottom carNodes)
				pbBottom.object = bottomNode
				select bottomNode
				logLine ("BOTTOM created: " + bottomNode.name + " at " + bottomNode.pos as string)
			)
		)
		on pbBottom picked o do (
			bottomNode = o
			logLine ("BOTTOM picked: " + o.name)
		)
		on pbFL picked o do (wheelNodes[1] = partOf o; pbFL.object = wheelNodes[1]; logLine ("Wheel FL: picked " + o.name + ", using " + wheelNodes[1].name))
		on pbFR picked o do (wheelNodes[2] = partOf o; pbFR.object = wheelNodes[2]; logLine ("Wheel FR: picked " + o.name + ", using " + wheelNodes[2].name))
		on pbRL picked o do (wheelNodes[3] = partOf o; pbRL.object = wheelNodes[3]; logLine ("Wheel RL: picked " + o.name + ", using " + wheelNodes[3].name))
		on pbRR picked o do (wheelNodes[4] = partOf o; pbRR.object = wheelNodes[4]; logLine ("Wheel RR: picked " + o.name + ", using " + wheelNodes[4].name))

		on btnBuild pressed do (
			local pivotGap, fc, rc, dirv, fwdUse, tyre
			local mode = rbMode.state
			carNodes = for n in carNodes where isValidNode n collect n
			groundList = for n in groundList where isValidNode n collect n
			local wheels = if mode == 1 then #(undefined, undefined, undefined, undefined) \
				else for w in wheelNodes collect (if isValidNode w then w else undefined)
			local picked = for w in wheels where w != undefined collect w
			local carAll = if carNodes.count == 0 then #() else withDescendants (carNodes + picked)

			-- Exclude mode takes a snapshot of every visible geometry object that is not the car or on the list.
			local grounds = case of (
				(mode == 1): #()
				(rbGround.state == 1): groundList
				default: for g in geometry where not g.isHidden and findItem groundList g == 0 and findItem carAll g == 0 collect g
			)

			local err = case of (
				(carNodes.count == 0): "Set the car first: select it and press Use selection as car."
				(not isValidNode bottomNode): "Create or pick the BOTTOM helper."
				(findItem carAll bottomNode != 0): "BOTTOM must not be part of the car."
				((for n in carAll where n.parent != undefined and (getUserProp n.parent "MaxCarRig" == true or getUserProp n.parent "MaxCarRig_helper" == true) collect n).count > 0): "This car is already rigged. Remove the rig first."
				((for g in grounds where findItem carAll g != 0 collect g).count > 0): \
					("These are both car and ground: " + listText (for g in grounds where findItem carAll g != 0 collect g.name) + \
					". Take them off the ground list, or press Use selection as car again with only the car selected.")
				((wheels[1] == undefined) != (wheels[2] == undefined)): "Pick both front wheels, or neither."
				(mode == 3 and picked.count < 4): "Per wheel mode needs all four wheels."
				default: undefined
			)
			logLine ("Build pressed. Mode " + modeNames[mode] + ", ground " + groundNames[rbGround.state] + \
				", front " + ddFwd.selected + ", centre " + ddCentre.selected + ", ray " + spRay.value as string + \
				", ahead " + spAhead.value as string + ", steer " + spSteer.value as string + ", bank " + spBank.value as string)
			logLine ("  car: " + names carNodes)
			logLine ("  car with children and wheels: " + names carAll)
			logLine ("  ground list: " + names groundList)
			logLine ("  grounds used: " + names grounds)
			logLine ("  path: " + (if isValidNode pathShape then pathShape.name else "-") + ", BOTTOM: " + (if isValidNode bottomNode then bottomNode.name else "-"))
			logLine ("  wheels FL FR RL RR: " + names wheels)
			for w in wheels where isValidNode w do (
				tyre = tyreOf w
				logLine ("  " + w.name + ": tyre mesh " + tyre.name + ", tyre centre " + (wheelCentre w false) as string + ", radius " + (wheelRadius w) as string + 					", pivot " + w.pos as string + ", parts " + names (withDescendants #(w)))
			)
			for w in wheels where isValidNode w do (
				pivotGap = distance w.pos ((w.min + w.max) / 2)
				if pivotGap > (w.max.z - w.min.z) * 0.25 do
					logLine ("  warning: " + w.name + " pivot is " + pivotGap as string + " units from its centre. Use Wheel centre: Tyre centre, or fix the pivot.")
			)
			-- With both front wheels picked, the wheels say where the front is; the dropdown is only a fallback.
			-- A wrong dropdown made the rig face backwards in Per wheel mode, so the steering went to full lock.
			fwdUse = ddFwd.selection
			if mode > 1 and isValidNode wheels[1] and isValidNode wheels[2] and isValidNode bottomNode do (
				fc = (wheelCentre wheels[1] false + wheelCentre wheels[2] false) / 2
				rc = if isValidNode wheels[3] and isValidNode wheels[4] then (wheelCentre wheels[3] false + wheelCentre wheels[4] false) / 2 else bottomNode.pos
				dirv = fc - rc
				fwdUse = if (abs dirv.x) >= (abs dirv.y) then (if dirv.x > 0 then 1 else 2) else (if dirv.y > 0 then 3 else 4)
				if fwdUse != ddFwd.selection do
					logLine ("  front taken from the front wheels: " + ddFwd.items[fwdUse] + " (dropdown said " + ddFwd.selected + ")")
			)
			if err != undefined then (
				logLine ("  stopped: " + err)
				messageBox err title:"Car Rig"
			)
			else (
				undo "Build car rig" on (
					try (
						-- No spline yet: a straight 30 m one from the car forwards, so the rig can be built now and
						-- given its real spline (and ground) later from its modifier. With no ground the car rides
						-- on the spline.
						if not isValidNode pathShape do (
							local fwdTm = startFrame bottomNode fwdUse
							pathShape = SplineShape name:(uniqueName ((topLevel carNodes)[1].name + "_Path")) wirecolor:yellow
							addNewSpline pathShape
							addKnot pathShape 1 #corner #line fwdTm.row4
							addKnot pathShape 1 #corner #line (fwdTm.row4 + fwdTm.row1 * (units.decodeValue "30m"))
							updateShape pathShape
							pbPath.object = pathShape
							logLine ("  no spline picked: made " + pathShape.name)
						)
						if grounds.count == 0 do logLine "  no ground: the car rides on the spline until ground is added"
						local root = buildRig carNodes pathShape grounds bottomNode fwdUse mode spRay.value \
							wheels (ddCentre.selection == 1) spAhead.value spSteer.value spBank.value
						if cbRigLayer.checked do moveToRigLayer root
						saveBuildInfo root carNodes pathShape grounds bottomNode fwdUse mode wheels (ddCentre.selection == 1) cbRigLayer.checked
						watchRigs()
						select root
						logLine ("  built: " + root.name + ", children: " + names (withDescendants #(root)))
					)
					catch (
						logLine ("  build failed: " + getCurrentException())
						messageBox ("Build failed:\n" + getCurrentException() + "\n\nLog: " + logPath) title:"Car Rig"
					)
				)
			)
		)

		-- Rebuilds a rig with the given spline and ground, keeping every Car Rig modifier setting and the Progress
		-- keys. The spline and ground are read fresh, so edits to them are picked up. If the spline is swapped and
		-- Keep speed is on, the Progress keys are stretched to the new spline's length.
		fn rebuildRig root path grounds = (
			local ca, saved, keep, cars, oldPath, bottom, wheels, mode, fwdIndex, usePivot, useLayer, newRoot, newCa, c, v
			local edits = #(undefined, undefined, undefined, undefined), bottomLocal, loc, sc, k
			global MaxCarRig_grids, MaxCarRig_splines4
			cars = for n in nodesFrom (rawProp root "MaxCarRig_inCars") where isValidNode n collect n
			oldPath = (nodesFrom (rawProp root "MaxCarRig_inPath"))[1]
			bottom = (nodesFrom (rawProp root "MaxCarRig_inBottom"))[1]
			wheels = for n in nodesFrom (rawProp root "MaxCarRig_inWheels") collect (if isValidNode n then n else undefined)
			mode = getUserProp root "MaxCarRig_inMode"
			fwdIndex = getUserProp root "MaxCarRig_inFwd"
			usePivot = getUserProp root "MaxCarRig_inPivot" == true
			useLayer = getUserProp root "MaxCarRig_inLayer" == true
			if not isValidNode path or not isValidNode bottom or cars.count == 0 then
				messageBox "The spline, the BOTTOM helper or the car of this rig no longer exists. Build it again." title:"Car Rig"
			else (
				-- Keep every modifier setting: animated ones as a copy of their controller (keys included).
				ca = rigParams root
				keep = #(#progress, #lookAhead, #steerMax, #bank, #rayUp, #spin, #suspension, #travel, #diveSquat, #bankTime, #pitchTime, #startTime, #bodyFollow, #bodyLag, #reverse, #realistic, #maxBank, #maxPitch, #cornerSlow, #cornerSpeed, #cornerRadius, #brakeG, #easeOn, #easeStart, #easeStop, #speedSet, #speedUnit, #carType, #suspType, #lookType, #speedLocked, #kerbSlow, #tyreSteps, #liftSmooth)
				saved = #()
				for n in keep do (
					c = try (getPropertyController ca (n as string)) catch (undefined)
					v = try (getProperty ca n) catch (undefined)
					append saved #(n, (if c != undefined then copy c else undefined), v)
				)
				logLine ("Rebuild " + root.name + ": mode " + mode as string + ", " + cars.count as string + " car parts, path " + path.name + ", grounds " + names grounds)
				-- Hand-fitted helpers are kept: each tyre shape's place on its wheel and its size (a scaled gizmo
				-- has the scale folded into Radius and Height), and where BOTTOM sits on the rig.
				for n in withDescendants #(root) where classOf n == CylGizmo and isValidNode n.parent do (
					k = getUserProp n "MaxCarRig_tyre"
					if k == undefined do for j = 1 to 4 where findString n.name (#("_CarRig_TyreFL", "_CarRig_TyreFR", "_CarRig_TyreRL", "_CarRig_TyreRR")[j]) != undefined do k = j
					if k != undefined do (
						loc = n.transform * inverse n.parent.transform
						sc = loc.scale
						loc = matrix3 (normalize loc.row1) (normalize loc.row2) (normalize loc.row3) loc.row4
						edits[k] = #(loc, n.radius * (amax sc.x sc.y), n.height * sc.z)
					)
				)
				bottomLocal = bottom.transform * inverse root.transform
				undo "Refresh car rig" on (
					try (
						removeRig root
						-- BOTTOM goes where it was moved to on the rig (relative to the car's rest place).
						bottom.transform = bottomLocal * (startFrame bottom fwdIndex)
						-- Fresh spline and ground lookups.
						MaxCarRig_grids = undefined
						MaxCarRig_splines4 = undefined
						tyreEdits = edits
						newRoot = buildRig cars path grounds bottom fwdIndex mode spRay.value wheels usePivot spAhead.value spSteer.value spBank.value
						tyreEdits = undefined
						newCa = rigParams newRoot
						for e in saved where e[3] != undefined do (
							if e[2] != undefined then (try (setPropertyController newCa (e[1] as string) e[2]) catch ())
							else (try (setProperty newCa e[1] e[3]) catch ())
						)
						if path != oldPath and isValidNode oldPath and newCa.speedLocked and curveLength oldPath 1 > 0.0 do
							stretchProgress newCa ((curveLength path 1) / (curveLength oldPath 1))
						if useLayer do moveToRigLayer newRoot
						saveBuildInfo newRoot cars path grounds bottom fwdIndex mode wheels usePivot useLayer
						watchRigs()
						select newRoot
						logLine ("  rebuilt: " + newRoot.name)
					)
					catch (
						newRoot = undefined
						tyreEdits = undefined
						logLine ("  rebuild failed: " + getCurrentException())
						messageBox ("Refresh failed:\n" + getCurrentException() + "\n\nLog: " + logPath) title:"Car Rig"
					)
				)
			)
			newRoot
		)

		on btnRefresh pressed do (
			local root = (for o in selection where getUserProp o "MaxCarRig" == true collect o)[1]
			if root == undefined then messageBox "Select a rig first (the ..._CarRig rectangle)." title:"Car Rig"
			else if rawProp root "MaxCarRig_inCars" == undefined then messageBox "This rig was built with an older version. Remove it and build it once more; after that Refresh works." title:"Car Rig"
			else rebuildRig root (nodesFrom (rawProp root "MaxCarRig_inPath"))[1] (for n in nodesFrom (rawProp root "MaxCarRig_inGrounds") where isValidNode n collect n)
		)

		-- Change a built rig: the panel follows the last rig selected, so ground objects can then be selected and
		-- added without losing it. Each change rebuilds the rig at once (as Refresh does) with the new spline or
		-- ground list.
		fn rigGrounds r = for n in nodesFrom (rawProp r "MaxCarRig_inGrounds") where isValidNode n collect n
		fn changeRig r path grounds = (
			global MaxCarRig_editRoot
			local newRoot = rebuildRig r path grounds
			if newRoot != undefined do MaxCarRig_editRoot = newRoot
			showEditRig()
		)
		-- One change to a built rig. action: #add (arg = nodes; groups count as their meshes), #remove (arg = list
		-- index), #surface (every CAR SURFACE object not yet in the list), #path (arg = the new spline).
		fn doChange r action arg = (
			local grounds, path, carAll, surfs, added = #()
			if not isValidNode r then messageBox "Select a rig first (the ..._CarRig rectangle)." title:"Car Rig"
			else if action == #refresh and rawProp r "MaxCarRig_inCars" != undefined then
				changeRig r (nodesFrom (rawProp r "MaxCarRig_inPath"))[1] (rigGrounds r)
			else if rawProp r "MaxCarRig_inCars" == undefined then messageBox "This rig was built with an older version. Remove it and build it once more; after that it can be changed." title:"Car Rig"
			else if action != #path and getUserProp r "MaxCarRig_inMode" == 1 then messageBox "This rig is in Simple mode, which does not use ground." title:"Car Rig"
			else (
				grounds = rigGrounds r
				path = (nodesFrom (rawProp r "MaxCarRig_inPath"))[1]
				carAll = withDescendants (for n in nodesFrom (rawProp r "MaxCarRig_inCars") where isValidNode n collect n)
				case action of (
					#add: added = for o in withDescendants arg where geoFilt o and not isGroupHead o and findItem grounds o == 0 and findItem carAll o == 0 and getUserProp o "MaxCarRig" != true collect o
					#surface: (
						surfs = for n in objects where matchPattern (tagOf n) pattern:"CAR_SURFACE*" or tagOf n == "SURFACE" collect n
						added = for g in withDescendants surfs where geoFilt g and findItem grounds g == 0 collect g
					)
					#remove: if arg >= 1 and arg <= grounds.count do (deleteItem grounds arg; added = undefined)
					#path: (path = arg; added = undefined)
				)
				case of (
					(added == undefined): changeRig r path grounds
					(added.count > 0): changeRig r path (grounds + added)
					(action == #add): messageBox "Nothing to add. Pick ground objects that are not the car, the rig or already in the list." title:"Car Rig"
					(action == #surface): messageBox "No new CAR SURFACE objects found. Every one is already in this rig's ground list." title:"Car Rig"
				)
			)
		)
		-- The rig's own modifier panel asks for changes through here. The rebuild deletes that modifier, so it
		-- waits for the button click to finish (a short timer) instead of running inside it.
		fn runQueued s e = (
			global MaxCarRig_job
			local j = MaxCarRig_job
			s.Stop()
			MaxCarRig_job = undefined
			if j != undefined do doChange j[1] j[2] j[3]
		)
		fn queueChange r action arg = (
			global MaxCarRig_job, MaxCarRig_jobTimer
			MaxCarRig_job = #(r, action, arg)
			if MaxCarRig_jobTimer == undefined do (
				MaxCarRig_jobTimer = dotNetObject "System.Windows.Forms.Timer"
				MaxCarRig_jobTimer.Interval = 50
				dotNet.addEventHandler MaxCarRig_jobTimer "Tick" runQueued
				dotNet.setLifetimeControl MaxCarRig_jobTimer #mxs
			)
			MaxCarRig_jobTimer.Start()
		)
		on btnEditAdd pressed do (
			global MaxCarRig_editRoot
			if selection.count == 0 then messageBox "Select the new ground objects in the viewport first, then press Add selected." title:"Car Rig"
			else doChange MaxCarRig_editRoot #add (for o in selection collect o)
		)
		on btnEditDel pressed do (
			global MaxCarRig_editRoot
			if lbEditGround.selection > 0 do doChange MaxCarRig_editRoot #remove lbEditGround.selection
		)
		on btnEditSurf pressed do (
			global MaxCarRig_editRoot
			doChange MaxCarRig_editRoot #surface undefined
		)
		on pbEditPath picked o do (
			global MaxCarRig_editRoot
			doChange MaxCarRig_editRoot #path o
		)
		on MaxCarRig_UI close do callbacks.removeScripts id:#MaxCarRigSel

		on btnRemove pressed do (
			local roots = for o in selection where getUserProp o "MaxCarRig" == true collect o
			if roots.count == 0 then messageBox "Select a rig first (the green ..._CarRig rectangle)." title:"Car Rig"
			else if queryBox ("Remove " + roots.count as string + " rig(s)? The car stays where it is on the current frame and the rig helpers are deleted.") title:"Car Rig" do
				undo "Remove car rig" on (for r in roots do (logLine ("Remove rig: " + r.name); removeRig r))
		)
	)

	on execute do (
		try (destroyDialog MaxCarRig_UI) catch ()
		createDialog MaxCarRig_UI
		global MaxCarRig_changeLater
		MaxCarRig_changeLater = MaxCarRig_UI.queueChange
	)
)

macros.run "V1_Scripts" "V1_SimpleCarRig"
