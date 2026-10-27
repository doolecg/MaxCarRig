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

	rollout MaxCarRig_UI "Car Rig" width:260
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
	fn castDown grounds p rayUp =
	(
		local best = undefined, hit
		local r = ray (p + [0,0,rayUp]) [0,0,-1]
		for g in grounds where isValidNode g and p.x >= g.min.x and p.x <= g.max.x and p.y >= g.min.y and p.y <= g.max.y do
		(
			hit = intersectRay g r
			if hit != undefined and (best == undefined or hit.pos.z > best.pos.z) do best = hit
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
	local len = curveLength sp 1
	local a = if len < 0.001 then 0.0 else ahead / len
	local u = if rigCA.reverse then 1.0 - progress / 100.0 - a else progress / 100.0 + a
	u = if isClosed sp 1 then (mod ((mod u 1.0) + 1.0) 1.0) else (amax 0.0 (amin 1.0 u))
	in coordsys world lengthInterp sp 1 u
)"

		-- Steering (Rotation Script). One instance drives both front wheels, so they always turn together.
		local steerScript = @"(
	local d = (aimNode.pos * inverse rig.transform) - %FRONT%
	local ang = if ((abs d.x) + (abs d.y)) < 0.001 then 0.0 else atan2 d.y d.x
	(eulerAngles 0 0 (amax (-steerMax) (amin steerMax ang))) as quat
)"

		-- Body bank (Rotation Script): roll follows the steer angle. Positive Bank leans out of the turn.
		local bankScript = @"(
	local d = (aimNode.pos * inverse rig.transform) - %FRONT%
	local ang = if ((abs d.x) + (abs d.y)) < 0.001 then 0.0 else atan2 d.y d.x
	local t = if steerMax < 0.001 then 0.0 else amax (-1.0) (amin 1.0 (ang / steerMax))
	(eulerAngles (bank * t) 0 0) as quat
)"

		-- The controls on the rig's "Car Rig" modifier. All are animatable.
		fn paramsCA = attributes MaxCarRigParams attribID:#(0x5a1c3e01, 0x2b7d4f92)
		(
			parameters main rollout:params
			(
				progress type:#float ui:spProgress default:0.0
				lookAhead type:#worldUnits ui:spAhead default:100.0
				steerMax type:#float ui:spSteer default:35.0
				bank type:#float ui:spBank default:3.0
				rayUp type:#worldUnits ui:spRay default:200.0
				reverse type:#boolean ui:cbReverse default:false
			)
			rollout params "Car Rig"
			(
				spinner spProgress "Progress %" range:[-1e6, 1e6, 0]
				spinner spAhead "Look ahead" type:#worldunits range:[0, 1e6, 100]
				spinner spSteer "Max steer (deg)" range:[0, 89, 35]
				spinner spBank "Bank (deg)" range:[-45, 45, 3]
				spinner spRay "Ray start height" type:#worldunits range:[0, 1e6, 200]
				checkbox cbReverse "Reverse along spline"
			)
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

		fn wheelCentre w usePivot = if usePivot then w.pos else (w.min + w.max) / 2
		fn wheelRadius w = (w.max.z - w.min.z) / 2

		fn linkTo n parent = (
			setUserProp n "MaxCarRig_oldParent" (if n.parent == undefined then 0 else n.parent.handle)
			-- A group member must leave its group before it can follow a rig helper; Remove puts it back.
			setUserProp n "MaxCarRig_wasGroupMember" (isGroupMember n)
			if isGroupMember n do detachNodesFromGroup #(n)
			n.parent = parent
		)

		-- A part picked inside a closed group stands for that whole group (a wheel group: rim, tyre, brake).
		fn partOf o = if isGroupMember o and not isOpenGroupMember o and o.parent != undefined and isGroupHead o.parent then o.parent else o

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
			local picked, base, tm, inv, bb, carLen, carWid, carSize, wheelSize, root, m, ca, offs
			local aim, ac, fl, fr, steering, front, axleZ, bankTm, bankH, bc, sc, st, sh, wheelParts, bodyNodes, c, s, ctrl

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
				width:(carLen * 1.15) length:(carWid * 1.25) wirecolor:green
			setUserProp root "MaxCarRig" true
			m = EmptyModifier name:"Car Rig"
			addModifier root m
			custAttributes.add m (paramsCA())
			ca = custAttributes.get m 1
			for p in #(#progress, #lookAhead, #steerMax, #bank, #rayUp) do ca[p].controller = bezier_float()
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
				aim = rigHelper (base + "_CarRig_Aim") (matrix3 1) (wheelSize * 0.8) orange true
				ac = position_script()
				aim.position.controller = ac
				ac.AddNode "sp" path
				ac.AddTarget "progress" ca[#progress].controller
				ac.AddTarget "ahead" ca[#lookAhead].controller
				ac.AddObject "rigCA" ca
				ac.script = aimScript
				setUserProp root "MaxCarRig_aim" aim.handle

				fl = wheels[1]
				fr = wheels[2]
				steering = isValidNode fl and isValidNode fr
				front = if steering then ((wheelCentre fl usePivot + wheelCentre fr usePivot) / 2) * inv else [0,0,0]

				-- Bank pivots at wheel centre height so the body rolls about its axle line, not the ground.
				axleZ = 0.0
				for w in picked do axleZ += ((wheelCentre w usePivot) * inv).z / picked.count
				bankTm = copy tm
				bankTm.row4 = tm.pos + [0, 0, axleZ]
				bankH = rigHelper (base + "_CarRig_Bank") bankTm (carSize * 0.4) (color 150 60 200) false
				bankH.parent = root
				bc = rotation_script()
				bankH.rotation.controller = bc
				bc.AddNode "rig" root
				bc.AddNode "aimNode" aim
				bc.AddTarget "steerMax" ca[#steerMax].controller
				bc.AddTarget "bank" ca[#bank].controller
				bc.script = substituteString bankScript "%FRONT%" (front as string)

				if steering do (
					sc = rotation_script()
					sc.AddNode "rig" root
					sc.AddNode "aimNode" aim
					sc.AddTarget "steerMax" ca[#steerMax].controller
					sc.script = substituteString steerScript "%FRONT%" (front as string)
					for i = 1 to 2 do (
						st = copy tm
						st.row4 = wheelCentre wheels[i] usePivot
						sh = rigHelper (base + (if i == 1 then "_CarRig_SteerFL" else "_CarRig_SteerFR")) st (wheelSize * 1.3) red true
						sh.parent = root
						sh.rotation.controller = sc
						linkTo wheels[i] sh
					)
				)
				for i = 3 to 4 where isValidNode wheels[i] do linkTo wheels[i] root
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
					attachNodesToGroup #(n) n.parent
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

		group "1. Car"
		(
			button btnCar "Use selection as car" width:230
			label lblCar "No car set" align:#left
		)
		group "2. Path"
		(
			pickbutton pbPath "Pick spline" filter:shapeFilt autoDisplay:true width:230
		)
		group "3. Mode"
		(
			radiobuttons rbMode labels:#("Simple: stick to spline", "Body: BOTTOM on ground", "Per wheel: fit to 4 wheels") columns:1 align:#left default:2
		)
		group "4. Ground"
		(
			radiobuttons rbGround labels:#("Include list", "Exclude list") columns:2 align:#left
			listbox lbGround height:4
			button btnGroundAdd "Add selected" across:3 width:72
			button btnGroundDel "Remove" width:72
			button btnGroundClear "Clear" width:72
			spinner spRay "Ray start above spline" range:[0, 1e6, 200] type:#worldunits
		)
		group "5. BOTTOM"
		(
			button btnBottomMake "Create at car bottom" width:230
			pickbutton pbBottom "Or pick BOTTOM" autoDisplay:true width:230
		)
		group "6. Wheels (front pair steers)"
		(
			dropdownlist ddCentre "Wheel centre" items:#("Pivot point", "Bounding box centre")
			pickbutton pbFL "Front left wheel" autoDisplay:true width:230
			pickbutton pbFR "Front right wheel" autoDisplay:true width:230
			pickbutton pbRL "Rear left wheel" autoDisplay:true width:230
			pickbutton pbRR "Rear right wheel" autoDisplay:true width:230
		)
		group "7. Options"
		(
			dropdownlist ddFwd "Car front faces (world)" items:#("+X", "-X", "+Y", "-Y")
			spinner spAhead "Look ahead" range:[0, 1e6, 100] type:#worldunits
			spinner spSteer "Max steer (deg)" range:[0, 89, 35]
			spinner spBank "Bank (deg)" range:[-45, 45, 3]
		)
		button btnBuild "Build rig" width:230 height:28
		button btnRemove "Remove selected rig" width:230
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
			logLine ("Opened. Max version " + ((maxVersion())[1] as string) + ", log: " + logPath)
			refreshUI()
		)
		on rbMode changed s do (
			logLine ("Mode " + modeNames[s])
			refreshUI()
		)
		on rbGround changed s do logLine ("Ground " + groundNames[s])

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
			if err != undefined then (
				logLine ("  stopped: " + err)
				messageBox err title:"Car Rig"
			)
			else (
				undo "Build car rig" on (
					try (
						local root = buildRig carNodes pathShape grounds bottomNode ddFwd.selection mode spRay.value \
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
