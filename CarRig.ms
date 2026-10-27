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

	rollout MaxCarRig_UI "V1 Simple Car Rig 0.1.0" width:260
	(
		local carNodes = #(), groundList = #(), wheelNodes = #(undefined, undefined, undefined, undefined)
		local pathShape = undefined, bottomNode = undefined
		-- RadioButtons cannot read their labels back, so the log uses these.
		local modeNames = #("Simple", "Body", "Per wheel"), groundNames = #("Include list", "Exclude list")

		-- The controller scripts below live in the scene file, so a rigged scene keeps
		-- working on a PC without this tool.

		-- Rig root (Transform Script). Mode 1 = simple, 2 = body, 3 = per wheel.
		-- sp is the spline; progress and rayUp come from the Car Rig modifier.
		local rootScript = @"(
	local mode = %MODE%
	local grounds = #(%GROUNDS%)
	local offs = #(%OFFSETS%)
	-- All locals up front: Max throws a Bad free thunk error for locals declared in a nested block and read in a loop.
	local u, p, fwd, y, h, up, guess, hits, w, x, tm, mid, offMid
	-- Ray tests use a voxel grid per ground object (RayMeshGridIntersect), built once and kept
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
		local best = undefined, o, rm, n, i, d
		o = p + [0,0,rayUp]
		for g in grounds where isValidNode g and p.x >= g.min.x and p.x <= g.max.x and p.y >= g.min.y and p.y <= g.max.y do
		(
			rm = gridFor g
			n = rm.intersectRay o [0,0,-1] false
			if n > 0 do
			(
				i = rm.getClosestHit()
				d = rm.getHitDist i
				if best == undefined or (o.z - d) > best.pos.z do best = ray (o - [0,0,d]) (rm.getHitNormal i)
			)
		)
		best
	)
	fn frameFrom x z pos =
	(
		local y = normalize (cross z x)
		matrix3 (cross y z) y z pos
	)
	u = progress / 100.0
	if rigCA.reverse do u = 1.0 - u
	u = if isClosed sp 1 then (mod ((mod u 1.0) + 1.0) 1.0) else (amax 0.0 (amin 1.0 u))
	p = in coordsys world lengthInterp sp 1 u
	fwd = normalize (in coordsys world lengthTangent sp 1 u)
	if rigCA.reverse do fwd = -fwd
	case mode of
	(
		1:
		(
			y = normalize (cross [0,0,1] fwd)
			matrix3 fwd y (cross fwd y) p
		)
		2:
		(
			h = castDown grounds p rayUp
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
			for o in offs do
			(
				w = o * guess
				h = castDown grounds w rayUp
				append hits (if h == undefined then w else h.pos)
			)
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
	local len = %LEN%
	local a = if len < 0.001 then 0.0 else ahead / len
	local u = if rigCA.reverse then 1.0 - progress / 100.0 - a else progress / 100.0 + a
	u = if isClosed sp 1 then (mod ((mod u 1.0) + 1.0) 1.0) else (amax 0.0 (amin 1.0 u))
	in coordsys world lengthInterp sp 1 u
)"

		-- Steering (Rotation Script). One instance drives both front wheels, so they always turn together.
		-- The angle comes only from the spline: the travel direction at the car versus the line from the
		-- front axle to the look-ahead point. No rig, world or car-front axes are involved, so it cannot
		-- be thrown off by which way the car or its pivots face. Positive = turn left, about the car up axis.
		local steerScript = @"(
	local len, u, s, uf, ua, t, v, ang, k
	fn wrapU sp x = if isClosed sp 1 then (mod ((mod x 1.0) + 1.0) 1.0) else (amax 0.0 (amin 1.0 x))
	len = %LEN%
	s = if rigCA.reverse then -1.0 else 1.0
	u = progress / 100.0
	if rigCA.reverse do u = 1.0 - u
	uf = wrapU sp (u + s * %FRONTDIST% / len)
	ua = wrapU sp (u + s * ahead / len)
	t = s * (in coordsys world lengthTangent sp 1 (wrapU sp u))
	v = (in coordsys world lengthInterp sp 1 ua) - (in coordsys world lengthInterp sp 1 uf)
	t.z = 0.0
	v.z = 0.0
	ang = if (length v) < 0.001 or (length t) < 0.001 then 0.0 else atan2 ((cross t v).z) (dot t v)
	(eulerAngles 0 0 (amax (-steerMax) (amin steerMax ang))) as quat
)"

		-- Body bank (Rotation Script): roll follows the same steer angle. Positive Bank leans out of the turn.
		local bankScript = @"(
	local len, u, s, uf, ua, t, v, ang, k
	fn wrapU sp x = if isClosed sp 1 then (mod ((mod x 1.0) + 1.0) 1.0) else (amax 0.0 (amin 1.0 x))
	len = %LEN%
	s = if rigCA.reverse then -1.0 else 1.0
	u = progress / 100.0
	if rigCA.reverse do u = 1.0 - u
	uf = wrapU sp (u + s * %FRONTDIST% / len)
	ua = wrapU sp (u + s * ahead / len)
	t = s * (in coordsys world lengthTangent sp 1 (wrapU sp u))
	v = (in coordsys world lengthInterp sp 1 ua) - (in coordsys world lengthInterp sp 1 uf)
	t.z = 0.0
	v.z = 0.0
	ang = if (length v) < 0.001 or (length t) < 0.001 then 0.0 else atan2 ((cross t v).z) (dot t v)
	k = if steerMax < 0.001 then 0.0 else amax (-1.0) (amin 1.0 (ang / steerMax))
	(eulerAngles (bank * k) 0 0) as quat
)"

		-- Tyre spin (Rotation Script, one per wheel): distance travelled / radius, so the tyre rolls
		-- without sliding. spin scales it: 1 = rolling, 0 = stopped, more = wheelspin.
		-- The helper carries the wheel pivot's own orientation (%BASE%) and spins about the pivot axis
		-- that points across the car (%AXIS%), so a wheel spins about its own axle.
		local spinScript = @"(
	local dist = progress / 100.0 * %LEN%
	((%AXIS% (%SIGN% * spin * dist / %RADIUS% * 180.0 / pi)) * %BASE%) as quat
)"

		-- The controls on the rig's "Car Rig" modifier. All are animatable.
		fn paramsCA = attributes MaxCarRigParams attribID:#(0x5a1c3e01, 0x2b7d4f93)
		(
			parameters main rollout:params
			(
				progress type:#float ui:spProgress default:0.0
				lookAhead type:#worldUnits ui:spAhead default:100.0
				steerMax type:#float ui:spSteer default:35.0
				bank type:#float ui:spBank default:3.0
				rayUp type:#worldUnits ui:spRay default:200.0
				reverse type:#boolean ui:cbReverse default:false
				spin type:#float ui:spSpin default:1.0
			)
			rollout params "Car Rig"
			(
				spinner spProgress "Progress %" range:[-1e6, 1e6, 0]
				spinner spAhead "Look ahead" type:#worldunits range:[0, 1e6, 100]
				spinner spSteer "Max steer (deg)" range:[0, 89, 35]
				spinner spBank "Bank (deg)" range:[-45, 45, 3]
				spinner spRay "Ray start height" type:#worldunits range:[0, 1e6, 200]
				checkbox cbReverse "Reverse along spline"
				spinner spSpin "Tyre spin x" range:[-100, 100, 1]
			)
		)

		local toolVersion = "0.1.0"
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

		fn linkTo n parent = (
			setUserProp n "MaxCarRig_oldParent" (if n.parent == undefined then 0 else n.parent.handle)
			-- A group member must leave its group before it can follow a rig helper; Remove puts it back.
			setUserProp n "MaxCarRig_wasGroupMember" (isGroupMember n)
			-- detachNodesFromGroup refuses some nested members ("invalid input"); clearing the flag does the same job.
			if isGroupMember n do (try (detachNodesFromGroup #(n)) catch (setGroupMember n false))
			n.parent = parent
		)

		-- A part picked inside a closed group stands for that whole group (a wheel group: rim, tyre, brake).
		fn partOf o = if isGroupMember o and not isOpenGroupMember o and o.parent != undefined and isGroupHead o.parent then o.parent else o

		fn addSteerInputs ctrl path ca = (
			ctrl.AddNode "sp" path
			ctrl.AddTarget "progress" ca[#progress].controller
			ctrl.AddTarget "ahead" ca[#lookAhead].controller
			ctrl.AddTarget "steerMax" ca[#steerMax].controller
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
			local picked, base, tm, inv, bb, carLen, carWid, carSize, wheelSize, root, m, ca, offs, lenText
			-- The spline length is measured once here and written into the scripts: measuring it every frame
			-- in every script was a large share of the playback cost. Rebuild the rig after editing the spline.
			lenText = (amax 0.001 (curveLength path 1)) as string
			local aim, ac, fl, fr, steering, front, axleZ, bankTm, bankH, bc, sc, st, sh, wheelParts, bodyNodes, c, s, ctrl, spinH, spc, wheelHolder, wt, axisK, axisSign, baseRot
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
			for p in #(#progress, #lookAhead, #steerMax, #bank, #rayUp, #spin) do ca[p].controller = bezier_float()
			ca.lookAhead = lookAhead
			ca.steerMax = steerMax
			ca.bank = bank
			ca.rayUp = rayUp
			-- Progress runs 0 to 100 over the active time range on linear keys, so the speed is constant.
			with animate on (
				at time animationRange.start ca.progress = 0.0
				at time animationRange.end ca.progress = 100.0
			)
			for k in ca[#progress].controller.keys do (
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
				ac.AddTarget "progress" ca[#progress].controller
				ac.AddTarget "ahead" ca[#lookAhead].controller
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

				-- Bank pivots at wheel centre height so the body rolls about its axle line, not the ground.
				axleZ = 0.0
				for w in picked do axleZ += ((wheelCentre w usePivot) * inv).z / picked.count
				bankTm = copy tm
				bankTm.row4 = tm.pos + [0, 0, axleZ]
				bankH = rigHelper (base + "_CarRig_Bank") bankTm (carSize * 0.4) (color 150 138 122) false
				bankH.parent = root
				bc = rotation_script()
				bankH.rotation.controller = bc
				addSteerInputs bc path ca
				bc.AddTarget "bank" ca[#bank].controller
				bc.script = substituteString (substituteString bankScript "%FRONTDIST%" (front.x as string)) "%LEN%" lenText

				if steering do (
					sc = rotation_script()
					addSteerInputs sc path ca
					sc.script = substituteString (substituteString steerScript "%FRONTDIST%" (front.x as string)) "%LEN%" lenText
					for i = 1 to 2 do (
						st = copy tm
						st.row4 = wheelCentre wheels[i] usePivot
						sh = rigHelper (base + (if i == 1 then "_CarRig_SteerFL" else "_CarRig_SteerFR")) st (wheelSize * 1.3) (color 196 120 90) true
						sh.parent = root
						sh.rotation.controller = sc
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
					spinH.parent = wheelHolder
					baseRot = (spinH.rotation.controller.value) as matrix3
					spc = rotation_script()
					spc.AddNode "sp" path
					spc.AddTarget "progress" ca[#progress].controller
					spc.AddTarget "spin" ca[#spin].controller
					s = substituteString spinScript "%RADIUS%" ((amax 0.001 (wheelRadius wheels[i])) as string)
					s = substituteString s "%AXIS%" axisNames[axisK]
					s = substituteString s "%SIGN%" (axisSign as string)
					spc.script = substituteString (substituteString s "%BASE%" ("(" + baseRot as string + ")")) "%LEN%" lenText
					spinH.rotation.controller = spc
					linkTo wheels[i] spinH
					-- Brakes and callipers steer with the wheel but must not spin with it.
					for n in withDescendants #(wheels[i]) where n != wheels[i] and isBrake n do linkTo n wheelHolder
				)
				-- Anything under a picked wheel (hubcaps, brakes) stays with that wheel.
				wheelParts = withDescendants picked
				bodyNodes = for n in cars where findItem wheelParts n == 0 collect n
				for n in topLevel bodyNodes do linkTo n bankH

				if mode == 3 do (
					for w in wheels do (
						c = wheelCentre w usePivot
						append offs ([c.x, c.y, c.z - wheelRadius w] * inv)
					)
				)
			)
			linkTo bottom root

			s = substituteString rootScript "%MODE%" (mode as string)
			s = substituteString s "%GROUNDS%" (listText (for i = 1 to grounds.count collect ("g" + i as string)))
			s = substituteString s "%OFFSETS%" (listText offs)
			ctrl = transform_script()
			root.transform.controller = ctrl
			ctrl.AddNode "sp" path
			ctrl.AddTarget "progress" ca[#progress].controller
			ctrl.AddTarget "rayUp" ca[#rayUp].controller
			ctrl.AddObject "rigCA" ca
			for i = 1 to grounds.count do ctrl.AddNode ("g" + i as string) grounds[i]
			ctrl.script = s
			root
		)

		fn removeRig root = (
			local all, h, extras
			all = withDescendants #(root)
			for n in all where getUserProp n "MaxCarRig_oldParent" != undefined and getUserProp n "MaxCarRig_helper" != true do (
				h = getUserProp n "MaxCarRig_oldParent"
				n.parent = if h == 0 then undefined else maxOps.getNodeByHandle h
				-- Parts taken out of a group at build time go back into it.
				if getUserProp n "MaxCarRig_wasGroupMember" == true and n.parent != undefined and isGroupHead n.parent do
					(try (attachNodesToGroup #(n) n.parent) catch (setGroupMember n true))
			)
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
		)

		dotNetControl lblBrand "System.Windows.Forms.Label" width:234 height:20
		dotNetControl lblTitle "System.Windows.Forms.Label" width:234 height:30 offset:[0,-5]
		group "Car"
		(
		button btnAuto "Auto detect by name" width:230
			button btnCar "Use selection as car" width:230
			label lblCar "No car set" align:#left
		)
		group "Path"
		(
			pickbutton pbPath "Pick spline" filter:shapeFilt autoDisplay:true width:230
		)
		group "Mode"
		(
			radiobuttons rbMode labels:#("Simple: stick to spline", "Body: BOTTOM on ground", "Per wheel: fit to 4 wheels") columns:1 align:#left default:2
		)
		group "Ground"
		(
			radiobuttons rbGround labels:#("Include list", "Exclude list") columns:2 align:#left
			listbox lbGround height:4
			button btnGroundAdd "Add selected" across:3 width:72
			button btnGroundDel "Remove" width:72
			button btnGroundClear "Clear" width:72
			spinner spRay "Ray start above spline" range:[0, 1e6, 200] type:#worldunits
		)
		group "BOTTOM"
		(
			button btnBottomMake "Create at car bottom" width:230
			pickbutton pbBottom "Or pick BOTTOM" autoDisplay:true width:230
		)
		group "Wheels (front pair steers)"
		(
			dropdownlist ddCentre "Wheel centre" items:#("Pivot point", "Tyre centre")
			pickbutton pbFL "Front left wheel" autoDisplay:true width:230
			pickbutton pbFR "Front right wheel" autoDisplay:true width:230
			pickbutton pbRL "Rear left wheel" autoDisplay:true width:230
			pickbutton pbRR "Rear right wheel" autoDisplay:true width:230
		)
		group "Options"
		(
			dropdownlist ddFwd "Car front faces (world)" items:#("+X", "-X", "+Y", "-Y")
			spinner spAhead "Look ahead" range:[0, 1e6, 100] type:#worldunits
			spinner spSteer "Max steer (deg)" range:[0, 89, 35]
			spinner spBank "Bank (deg)" range:[-45, 45, 3]
		)
		button btnBuild "Build rig" width:230 height:28
		button btnRemove "Remove selected rig" width:230
		button btnBake "Bake selected rig to keys" width:230
		button btnCheck "Check steering (selected rig)" width:230
		button btnSpeed "Speed test (selected rig)" width:230
		button btnLog "Open log" width:230
		group "About"
		(
			label lblA1 "Provided \"as is\", without warranty, under" align:#left
			label lblA2 "the MIT licence. To the extent permitted" align:#left
			label lblA3 "by law, the authors are not liable for" align:#left
			label lblA4 "any loss or damage from using it." align:#left
			label lblA5 "Back up your work." align:#left
		)

		fn refreshUI = (
			local full = rbMode.state > 1
			for c in #(rbGround, lbGround, btnGroundAdd, btnGroundDel, btnGroundClear, spRay, ddCentre, \
				pbFL, pbFR, pbRL, pbRR, spAhead, spSteer, spBank) do c.enabled = full
			lbGround.items = for g in groundList where isValidNode g collect g.name
		)

		on MaxCarRig_UI open do (
			local fontStyle = dotNetClass "System.Drawing.FontStyle"
			for l in #(lblBrand, lblTitle) do (
				l.BackColor = uiColour #background
				l.ForeColor = uiColour #text
			)
			lblBrand.Font = dotNetObject "System.Drawing.Font" "Georgia" 8 fontStyle.Regular
			lblBrand.Text = "VISUALISATION ONE      v" + toolVersion
			lblTitle.Font = dotNetObject "System.Drawing.Font" "Georgia" 15 fontStyle.Regular
			lblTitle.Text = "Simple Car Rig"
			spAhead.value = units.decodeValue "8m"
			logLine ("Opened tool v" + toolVersion + ". Max version " + ((maxVersion())[1] as string) + ", log: " + logPath)
			refreshUI()
		)
		on rbMode changed s do (
			logLine ("Mode " + modeNames[s])
			refreshUI()
		)
		on rbGround changed s do logLine ("Ground " + groundNames[s])

		-- Auto detect finds the parts by name: FRONT_LEFT, FRONT_RIGHT, BACK_LEFT, BACK_RIGHT (or REAR_),
		-- BODY, CAR PATH and CAR SURFACE. Spaces, dashes and upper or lower case do not matter.
		fn tagOf n = toUpper (substituteString (substituteString n.name " " "_") "-" "_")
		fn findTagged tags = (
			local hit = undefined
			for n in objects where hit == undefined and findItem tags (tagOf n) != 0 do hit = n
			hit
		)

		on btnAuto pressed do (
			local body, w, surf, found = #(), missing = #(), i
			local pbs = #(pbFL, pbFR, pbRL, pbRR), cornerNames = #("FL", "FR", "RL", "RR")
			local wheelTags = #( \
				#("FRONT_LEFT", "FL", "LEFT_FRONT", "WHEEL_FL", "FRONT_LEFT_WHEEL"), \
				#("FRONT_RIGHT", "FR", "RIGHT_FRONT", "WHEEL_FR", "FRONT_RIGHT_WHEEL"), \
				#("BACK_LEFT", "REAR_LEFT", "RL", "BL", "LEFT_REAR", "LEFT_BACK", "WHEEL_RL", "BACK_LEFT_WHEEL", "REAR_LEFT_WHEEL"), \
				#("BACK_RIGHT", "REAR_RIGHT", "RR", "BR", "RIGHT_REAR", "RIGHT_BACK", "WHEEL_RR", "BACK_RIGHT_WHEEL", "REAR_RIGHT_WHEEL"))

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

			surf = findTagged #("CAR_SURFACE", "SURFACE")
			if surf != undefined then (
				groundList = for g in withDescendants #(surf) where geoFilt g collect g
				rbGround.state = 1
				append found ("ground " + surf.name + " (" + groundList.count as string + " objects)")
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

		-- Records every scripted rig node as plain keys on every frame and removes the scripts, so playback
		-- costs nothing. The Car Rig modifier stops driving the car after this; build again to change it.
		on btnBake pressed do (
			local root, all, nodes, h, aimH, samples, row, i, k, f, frames
			root = (for o in selection where getUserProp o "MaxCarRig" == true collect o)[1]
			if root == undefined then messageBox "Select a rig first (the ..._CarRig rectangle)." title:"Car Rig"
			else if queryBox "Bake this rig to keys on every frame?\n\nPlayback gets fast, but the Car Rig modifier controls stop working. Undo, or build again, to go back." title:"Car Rig" do (
				all = withDescendants #(root)
				h = getUserProp root "MaxCarRig_aim"
				aimH = if h == undefined then undefined else maxOps.getNodeByHandle h
				-- Parents before children (withDescendants is breadth first), so each key lands in the right space.
				nodes = #(root)
				if isValidNode aimH do append nodes aimH
				for n in all where getUserProp n "MaxCarRig_helper" == true do append nodes n
				frames = #()
				for f = animationRange.start to animationRange.end do append frames f
				samples = #()
				for i = 1 to nodes.count do (
					row = #()
					for k = 1 to frames.count do append row (at time frames[k] nodes[i].transform)
					append samples row
				)
				undo "Bake car rig" on (
					for i = 1 to nodes.count do nodes[i].transform.controller = prs()
					with animate on (
						for i = 1 to nodes.count do
							for k = 1 to frames.count do at time frames[k] nodes[i].transform = samples[i][k]
					)
				)
				setUserProp root "MaxCarRig_baked" true
				logLine ("Baked " + root.name + ": " + nodes.count as string + " nodes over " + frames.count as string + " frames")
			)
		)

		on btnCar pressed do (
			carNodes = for o in selection collect o
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
		-- Times each part of the selected rig over 30 frames, then the viewport redraw with the car
		-- shown and hidden, so the log says what is slow instead of guessing.
		on btnSpeed pressed do (
			local root, all, helpers, carParts, wasHidden, aimH, h, t0, ms, tNow, frames = 30, start, span
			root = (for o in selection where getUserProp o "MaxCarRig" == true collect o)[1]
			if root == undefined then messageBox "Select a rig first (the green ..._CarRig rectangle)." title:"Car Rig"
			else (
				all = withDescendants #(root)
				helpers = for n in all where getUserProp n "MaxCarRig_helper" == true collect n
				carParts = for n in all where n != root and getUserProp n "MaxCarRig_helper" != true collect n
				h = getUserProp root "MaxCarRig_aim"
				aimH = if h == undefined then undefined else maxOps.getNodeByHandle h
				start = animationRange.start
				span = animationRange.end - animationRange.start
				tNow = sliderTime
				logLine ("Speed test on " + root.name + ": " + frames as string + " frames, " + helpers.count as string + " helpers, " + carParts.count as string + " car parts")

				t0 = timeStamp()
				for i = 1 to frames do at time (start + span * i / frames) root.transform
				logLine ("  rig root (ground rays): " + ((timeStamp() - t0) / frames as float) as string + " ms per frame")

				if isValidNode aimH do (
					t0 = timeStamp()
					for i = 1 to frames do at time (start + span * i / frames) aimH.transform
					logLine ("  aim null: " + ((timeStamp() - t0) / frames as float) as string + " ms per frame")
				)
				for n in helpers do (
					t0 = timeStamp()
					for i = 1 to frames do at time (start + span * i / frames) n.transform
					logLine ("  " + n.name + ": " + ((timeStamp() - t0) / frames as float) as string + " ms per frame")
				)

				t0 = timeStamp()
				for i = 1 to frames do (sliderTime = start + span * i / frames; completeRedraw())
				ms = (timeStamp() - t0) / frames as float
				logLine ("  viewport redraw, car shown: " + ms as string + " ms per frame")
				wasHidden = for n in carParts collect n.isHidden
				for n in carParts do n.isHidden = true
				t0 = timeStamp()
				for i = 1 to frames do (sliderTime = start + span * i / frames; completeRedraw())
				logLine ("  viewport redraw, car hidden: " + ((timeStamp() - t0) / frames as float) as string + " ms per frame")
				for i = 1 to carParts.count do carParts[i].isHidden = wasHidden[i]
				sliderTime = tNow
				messageBox ("Speed test done. Press Open log and send me the Speed test lines.") title:"Car Rig"
			)
		)
		-- Writes the real numbers behind the steering at the current frame, for bug reports.
		on btnCheck pressed do (
			local root, tm, h, aimH, a, all
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
				(not isValidNode pathShape): "Pick the spline."
				(not isValidNode bottomNode): "Create or pick the BOTTOM helper."
				(findItem carAll bottomNode != 0): "BOTTOM must not be part of the car."
				((for n in carAll where n.parent != undefined and (getUserProp n.parent "MaxCarRig" == true or getUserProp n.parent "MaxCarRig_helper" == true) collect n).count > 0): "This car is already rigged. Remove the rig first."
				(mode > 1 and grounds.count == 0): "No ground to sit on: add ground objects to the include list."
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
						local root = buildRig carNodes pathShape grounds bottomNode fwdUse mode spRay.value \
							wheels (ddCentre.selection == 1) spAhead.value spSteer.value spBank.value
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
	)
)

macros.run "V1_Scripts" "V1_SimpleCarRig"
