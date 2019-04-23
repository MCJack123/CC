-- Workspaces for ComputerCraft
-- by LDDestroier

local tArg = {...}

-- higher number means faster workspace movement animation, caps at 1
local workspaceMoveSpeed = 0.1

-- amount of time (seconds) until workspace indicator disappears
local workspaceIndicatorDuration = 0.6

-- if held down while moving workspace, will swap positions
local swapKey = keys.tab

-- x,y size of workspace grid
local gridWidth = math.max(1, tonumber(tArg[1]) or 3)
local gridHeight = math.max(1, tonumber(tArg[2]) or 3)

local scr_x, scr_y = term.getSize()
local windowWidth = scr_x
local windowHeight = scr_y
local doDrawWorkspaceIndicator = false

-- program that will start up for workspaces
local defaultProgram = "rom/programs/shell.lua"

local scroll = {0,0}		-- change this value when scrolling
local realScroll = {0,0}	-- this value changes depending on scroll for smoothness purposes
local focus = {1,1}			-- currently focused instance
local instances = {}

if _G.currentlyRunningWorkspace then
	print("Workspace is already running.")
	return
else
	_G.currentlyRunningWorkspace = true
end
local isRunning = true

local cwrite = function(text, y, terminal)
	terminal = terminal or term.current()
	local cx, cy = terminal.getCursorPos()
	local sx, sy = terminal.getSize()
	terminal.setCursorPos(sx / 2 - #text / 2, y or (sy / 2))
	terminal.write(text)
end

-- start up lddterm
local lddterm = {}
lddterm.alwaysRender = false		-- renders after any and all screen-changing functions.
lddterm.useColors = true		-- normal computers do not allow color, but this variable doesn't do anything yet
lddterm.baseTerm = term.current()	-- will draw to this terminal
lddterm.transformation = nil		-- will modify the current buffer as an NFT image before rendering
lddterm.cursorTransformation = nil	-- will modify the cursor position
lddterm.drawFunction = nil		-- will draw using this function instead of basic NFT drawing
lddterm.adjustX = 0			-- moves entire screen X
lddterm.adjustY = 0			-- moves entire screen Y
lddterm.selectedWindow = 1		-- determines which window controls the cursor
lddterm.windows = {}

local drawWorkspaceIndicator = function(terminal)
	terminal = terminal or lddterm.baseTerm
	for y = 0, gridHeight + 1 do
		for x = 0, gridWidth + 1 do
			term.setCursorPos(x + scr_x / 2 - gridWidth / 2, y + scr_y / 2 - gridHeight / 2)
			if instances[y] then
				if instances[y][x] then
					if focus[1] == x and focus[2] == y then
						term.blit(" ", "8", "8")
					elseif instances[y][x].active then
						term.blit(" ", "7", "7")
					else
						term.blit(" ", "f", "f")
					end
				else
					term.blit(" ", "0", "0")
				end
			else
				term.blit(" ", "0", "0")
			end
		end
	end
end

-- converts hex colors to colors api, and back
local to_colors, to_blit = {
	[' '] = 0,
	['0'] = 1,
	['1'] = 2,
	['2'] = 4,
	['3'] = 8,
	['4'] = 16,
	['5'] = 32,
	['6'] = 64,
	['7'] = 128,
	['8'] = 256,
	['9'] = 512,
	['a'] = 1024,
	['b'] = 2048,
	['c'] = 4096,
	['d'] = 8192,
	['e'] = 16384,
	['f'] = 32768,
}, {}
for k,v in pairs(to_colors) do
	to_blit[v] = k
end

-- separates string into table based on divider
local explode = function(div, str, replstr, includeDiv)
	if (div == '') then
		return false
	end
	local pos, arr = 0, {}
	for st, sp in function() return string.find(str, div, pos, false) end do
		table.insert(arr, string.sub(replstr or str, pos, st - 1 + (includeDiv and #div or 0)))
		pos = sp + 1
	end
	table.insert(arr, string.sub(replstr or str, pos))
	return arr
end

-- determines the size of the terminal before rendering always
local determineScreenSize = function()
	scr_x, scr_y = lddterm.baseTerm.getSize()
	lddterm.screenWidth = scr_x
	lddterm.screenHeight = scr_y
end

determineScreenSize()

-- takes two or more windows and checks if the first of them overlap the other(s)
lddterm.checkWindowOverlap = function(window, ...)
	if #lddterm.windows < 2 then
		return false
	end
	local list, win = {...}
	for i = 1, #list do
		win = list[i]
		if win ~= window then

			if (
				window.x < win.x + win.width and
				win.x < window.x + window.width and
				window.y < win.y + win.height and
				win.y < window.y + window.height
			) then
				return true
			end

		end
	end
	return false
end

local fixCursorPos = function()
	local cx, cy
	if lddterm.windows[lddterm.selectedWindow] then
		if lddterm.cursorTransformation then
			cx, cy = lddterm.cursorTransformation(
				lddterm.windows[lddterm.selectedWindow].cursor[1],
				lddterm.windows[lddterm.selectedWindow].cursor[2]
			)
			lddterm.baseTerm.setCursorPos(
				cx + lddterm.windows[lddterm.selectedWindow].x - 1,
				cy + lddterm.windows[lddterm.selectedWindow].y - 1
			)
		else
			lddterm.baseTerm.setCursorPos(
				-1 + lddterm.windows[lddterm.selectedWindow].cursor[1] + lddterm.windows[lddterm.selectedWindow].x,
				lddterm.windows[lddterm.selectedWindow].cursor[2] + lddterm.windows[lddterm.selectedWindow].y - 1
			)
		end
		lddterm.baseTerm.setCursorBlink(lddterm.windows[lddterm.selectedWindow].blink)
	end
end

-- renders the screen with optional transformation function
lddterm.render = function(transformation, drawFunction)
	-- determine new screen size and change lddterm screen to fit
	old_scr_x, old_scr_y = scr_x, scr_y
	determineScreenSize()
	if old_scr_x ~= scr_x or old_scr_y ~= scr_y then
		lddterm.baseTerm.clear()
	end
	local image = lddterm.screenshot()
	if type(transformation) == "function" then
		image = transformation(image)
	end
	if drawFunction then
		drawFunction(image, lddterm.baseTerm)
	else
		for y = 1, #image[1] do
			lddterm.baseTerm.setCursorPos(1 + lddterm.adjustX, y + lddterm.adjustY)
			lddterm.baseTerm.blit(image[1][y], image[2][y], image[3][y])
		end
	end
	if doDrawWorkspaceIndicator then
		drawWorkspaceIndicator()
	end
	fixCursorPos()
end

lddterm.newWindow = function(width, height, x, y, meta)
	meta = meta or {}
	local window = {
		width = math.floor(width),
		height = math.floor(height),
		blink = true,
		cursor = meta.cursor or {1, 1},
		colors = meta.colors or {"0", "f"},
		clearChar = meta.clearChar or " ",
		visible = meta.visible or true,
		x = math.floor(x) or 1,
		y = math.floor(y) or 1,
		buffer = {{},{},{}},
	}
	for y = 1, height do
		window.buffer[1][y] = {}
		window.buffer[2][y] = {}
		window.buffer[3][y] = {}
		for x = 1, width do
			window.buffer[1][y][x] = window.clearChar
			window.buffer[2][y][x] = window.colors[1]
			window.buffer[3][y][x] = window.colors[2]
		end
	end

	window.handle = {}
	window.handle.setCursorPos = function(x, y)
		window.cursor = {x, y}
		fixCursorPos()
	end
	window.handle.getCursorPos = function()
		return window.cursor[1], window.cursor[2]
	end
	window.handle.setCursorBlink = function(blink)
		window.blink = blink or false
	end
	window.handle.getCursorBlink = function()
		return window.blink
	end
	window.handle.scroll = function(amount)
		if amount > 0 then
			for i = 1, amount do
				for c = 1, 3 do
					table.remove(window.buffer[c], 1)
					window.buffer[c][window.height] = {}
					for xx = 1, width do
						window.buffer[c][window.height][xx] = (
							c == 1 and window.clearChar or
							c == 2 and window.colors[1] or
							c == 3 and window.colors[2]
						)
					end
				end
			end
		elseif amount < 0 then
			for i = 1, -amount do
				for c = 1, 3 do
					window.buffer[c][window.height] = nil
					table.insert(window.buffer[c], 1, {})
					for xx = 1, width do
						window.buffer[c][1][xx] = (
							c == 1 and window.clearChar or
							c == 2 and window.colors[1] or
							c == 3 and window.colors[2]
						)
					end
				end
			end
		end
		if lddterm.alwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
	end
	window.handle.scrollX = function(amount)
		if amount > 0 then
			for i = 1, amount do
				for c = 1, 3 do
					for y = 1, window.height do
						table.remove(window.buffer[c][y], 1)
						window.buffer[c][y][window.width] = (
							c == 1 and window.clearChar or
							c == 2 and window.colors[1] or
							c == 3 and window.colors[2]
						)
					end
				end
			end
		elseif amount < 0 then
			for i = 1, -amount do
				for c = 1, 3 do
					for y = 1, window.height do
						window.buffer[c][y][window.width] = nil
						table.insert(window.buffer[c][y], 1, (
							c == 1 and window.clearChar or
							c == 2 and window.colors[1] or
							c == 3 and window.colors[2]
						))
					end
				end
			end
		end
		if lddterm.alwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
	end
	window.handle.write = function(text, x, y, ignoreAlwaysRender)
		assert(text ~= nil, "expected string 'text'")
		text = tostring(text)
		local cx = math.floor(tonumber(x) or window.cursor[1])
		local cy = math.floor(tonumber(y) or window.cursor[2])
		text = text:sub(math.max(0, -cx - 1))
		for i = 1, #text do
			if cx >= 1 and cx <= window.width and cy >= 1 and cy <= window.height then
				window.buffer[1][cy][cx] = text:sub(i,i)
				window.buffer[2][cy][cx] = window.colors[1]
				window.buffer[3][cy][cx] = window.colors[2]
			end
			cx = math.min(cx + 1, window.width + 1)
		end
		window.cursor = {cx, cy}
		if lddterm.alwaysRender and not ignoreAlwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
	end
	window.handle.writeWrap = function(text, x, y, ignoreAlwaysRender)
		local words = explode(" ", text, nil, true)
		local cx, cy = x or window.cursor[1], y or window.cursor[2]
		for i = 1, #words do
			if cx + #words[i] > window.width + 1 then
				cx = 1
				if cy >= window.height then
					window.handle.scroll(1)
					cy = window.height
				else
					cy = cy + 1
				end
			end
			window.handle.write(words[i], cx, cy, true)
			cx = cx + #words[i]
		end
		if lddterm.alwaysRender and not ignoreAlwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
	end
	window.handle.blit = function(char, textCol, backCol, x, y)
		if type(char) == "number" then
			char = tostring(char)
		end
		if type(textCol) == "number" then
			textCol = tostring(textCol)
		end
		if type(backCol) == "number" then
			backCol = tostring(backCol)
		end
		assert(char ~= nil, "expected string 'char'")
		local cx = math.floor(tonumber(x) or window.cursor[1])
		local cy = math.floor(tonumber(y) or window.cursor[2])
		char = char:sub(math.max(0, -cx - 1))
		for i = 1, #char do
			if cx >= 1 and cx <= window.width and cy >= 1 and cy <= window.height then
				window.buffer[1][cy][cx] = char:sub(i,i)
				window.buffer[2][cy][cx] = textCol:sub(i,i)
				window.buffer[3][cy][cx] = backCol:sub(i,i)
			end
			cx = cx + 1
		end
		window.cursor = {cx, cy}
		if lddterm.alwaysRender and not ignoreAlwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
	end
	window.handle.print = function(text, x, y)
		text = text and tostring(text)
		window.handle.write(text, x, y, true)
		window.cursor[1] = 1
		if window.cursor[2] >= window.height then
			window.handle.scroll(1)
		else
			window.cursor[2] = window.cursor[2] + 1
			if lddterm.alwaysRender then
				lddterm.render(lddterm.transformation, lddterm.drawFunction)
			end
		end
	end
	window.handle.clear = function(char, ignoreAlwaysRender)
		local cx = 1
		for y = 1, window.height do
			for x = 1, window.width do
				if char then
					cx = (x % #char) + 1
				end
				window.buffer[1][y][x] = char and char:sub(cx, cx) or window.clearChar
				window.buffer[2][y][x] = window.colors[1]
				window.buffer[3][y][x] = window.colors[2]
			end
		end
		if lddterm.alwaysRender and not ignoreAlwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
	end
	window.handle.clearLine = function(cy, char, ignoreAlwaysRender)
		cy = math.floor(cy or window.cursor[2])
		local cx = 1
		for x = 1, window.width do
			if char then
				cx = (x % #char) + 1
			end
			window.buffer[1][cy or window.cursor[2]][x] = char and char:sub(cx, cx) or window.clearChar
			window.buffer[2][cy or window.cursor[2]][x] = window.colors[1]
			window.buffer[3][cy or window.cursor[2]][x] = window.colors[2]
		end
		if lddterm.alwaysRender and not ignoreAlwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
	end
	window.handle.clearColumn = function(cx, char, ignoreAlwaysRender)
		cx = math.floor(cx)
		char = char and char:sub(1,1)
		for y = 1, window.height do
			window.buffer[1][y][cx or window.cursor[1]] = char and char or window.clearChar
			window.buffer[2][y][cx or window.cursor[1]] = window.colors[1]
			window.buffer[3][y][cx or window.cursor[1]] = window.colors[2]
		end
		if lddterm.alwaysRender and not ignoreAlwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
	end
	window.handle.getSize = function()
		return window.width, window.height
	end
	window.handle.isColor = function()
		return lddterm.useColors
	end
	window.handle.isColour = window.handle.isColor
	window.handle.setTextColor = function(color)
		if to_blit[color] then
			window.colors[1] = to_blit[color]
		end
	end
	window.handle.setTextColour = window.handle.setTextColor
	window.handle.setBackgroundColor = function(color)
		if to_blit[color] then
			window.colors[2] = to_blit[color]
		end
	end
	window.handle.setBackgroundColour = window.handle.setBackgroundColor
	window.handle.getTextColor = function()
		return to_colors[window.colors[1]] or colors.white
	end
	window.handle.getTextColour = window.handle.getTextColor
	window.handle.getBackgroundColor = function()
		return to_colors[window.colors[2]] or colors.black
	end
	window.handle.getBackgroundColour = window.handle.getBackgroundColor
	window.handle.reposition = function(x, y)
		window.x = math.floor(x or window.x)
		window.y = math.floor(y or window.y)
		if lddterm.alwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
	end
	window.handle.setPaletteColor = function(...)
		return lddterm.baseTerm.setPaletteColor(...)
	end
	window.handle.setPaletteColour = window.handle.setPaletteColor
	window.handle.getPaletteColor = function(...)
		return lddterm.baseTerm.getPaletteColor(...)
	end
	window.handle.getPaletteColour = window.handle.getPaletteColor
	window.handle.getPosition = function()
		return window.x, window.y
	end
	window.handle.restoreCursor = function()
		lddterm.baseTerm.setCursorPos(
			-1 + window.cursor[1] + window.x,
			window.cursor[2] + window.y - 1
		)
	end
	window.handle.setVisible = function(visible)
		window.visible = visible or false
	end

	window.handle.redraw = lddterm.render
	window.handle.current = window.handle

	window.layer = #lddterm.windows + 1
	lddterm.windows[window.layer] = window

	return window, window.layer
end

lddterm.setLayer = function(window, _layer)
	local layer = math.max(1, math.min(#lddterm.windows, _layer))

	local win = window
	table.remove(lddterm.windows, win.layer)
	table.insert(lddterm.windows, layer, win)

	if lddterm.alwaysRender then
		lddterm.render(lddterm.transformation, lddterm.drawFunction)
	end
	return true
end

local old_scr_x, old_scr_y

-- gets screenshot of whole lddterm desktop, OR a single window
lddterm.screenshot = function(window)
	local output = {{},{},{}}
	local line
	if window then
		for y = 1, #window.buffer do
			line = {"","",""}
			for x = 1, #window.buffer do
				line = {
					line[1] .. window.buffer[1][y][x],
					line[2] .. window.buffer[2][y][x],
					line[3] .. window.buffer[3][y][x]
				}
			end
			output[1][y] = line[1]
			output[2][y] = line[2]
			output[3][y] = line[3]
		end
	else
		for y = 1, scr_y do
			line = {"","",""}
			for x = 1, scr_x do

				c = "."
				lt, lb = t, b
				t, b = "0", "f"
				for l = 1, #lddterm.windows do
					if lddterm.windows[l].visible then
						sx = 1 + x - lddterm.windows[l].x
						sy = 1 + y - lddterm.windows[l].y
						if lddterm.windows[l].buffer[1][sy] then
							if lddterm.windows[l].buffer[1][sy][sx] then
								c = lddterm.windows[l].buffer[1][sy][sx] or c
								t = lddterm.windows[l].buffer[2][sy][sx] or t
								b = lddterm.windows[l].buffer[3][sy][sx] or b
								break
							end
						end
					end
				end
				line = {
					line[1] .. c,
					line[2] .. t,
					line[3] .. b
				}
			end
			output[1][y] = line[1]
			output[2][y] = line[2]
			output[3][y] = line[3]
		end
	end
	return output
end

local keysDown = {}

local defaultProgram = "rom/programs/shell.lua"
local newInstance = function(x, y, program, initialStart)
	x, y = math.floor(x), math.floor(y)
	for yy = 1, y do
		instances[yy] = instances[yy] or {}
	end
	for xx = 1, x do
		instances[y][xx] = instances[y][xx] or false
	end
	local window = lddterm.newWindow(windowWidth, windowHeight, 1, 1)
	instances[y][x] = {
		x = x,
		y = y,
		active = initialStart,
		co = coroutine.create(function()
			term.redirect(window.handle)
			local evt
			while true do

				if initialStart then
					if not program or type(program) == "string" then
						shell.run(program or defaultProgram)
					elseif type(program) == "function" then
						program()
					end
				end

				instances[y][x].active = false
				term.clear()
				term.setCursorBlink(false)
				cwrite("This workspace is inactive.", 0 + scr_y / 2)
				cwrite("Press SPACE to start the workspace.", 1 + scr_y / 2)
				repeat
					evt = {os.pullEventRaw()}
				until (evt[1] == "key" and evt[2] == keys.space) or evt[1] == "terminate"
				sleep(0)
				if evt[1] == "terminate" then
					isRunning = false
					return
				end

				term.setCursorPos(1,1)
				term.clear()
				term.setCursorBlink(true)

				instances[y][x].active = true

				if not initialStart then
					if not program or type(program) == "string" then
						shell.run(program or defaultProgram)
					elseif type(program) == "function" then
						program()
					end
				end

			end
		end),
		window = window
	}
end

-- prevents wiseassed-ness
workspaceMoveSpeed = math.min(math.max(workspaceMoveSpeed, 0.01), 1)

local scrollWindows = function()
	local changed = false
	if realScroll[1] < scroll[1] then
		realScroll[1] = math.min(realScroll[1] + workspaceMoveSpeed, scroll[1])
		changed = true
	elseif realScroll[1] > scroll[1] then
		realScroll[1] = math.max(realScroll[1] - workspaceMoveSpeed, scroll[1])
		changed = true
	end
	if realScroll[2] < scroll[2] then
		realScroll[2] = math.min(realScroll[2] + workspaceMoveSpeed, scroll[2])
		changed = true
	elseif realScroll[2] > scroll[2] then
		realScroll[2] = math.max(realScroll[2] - workspaceMoveSpeed, scroll[2])
		changed = true
	end
	for y = 1, #instances do
		if instances[y] then
			for x = 1, #instances[y] do
				if instances[y][x] then
					instances[y][x].window.x = math.floor(1 + (instances[y][x].x + realScroll[1] - 1) * scr_x)
					instances[y][x].window.y = math.floor(1 + (instances[y][x].y + realScroll[2] - 1) * scr_y)
				end
			end
		end
	end
	return changed
end

for y = 1, gridHeight do
	for x = 1, gridWidth do
		newInstance(x, y, defaultProgram, x == focus[1] and y == focus[2])
	end
end

scrollWindows()

local swapInstances = function(xmod, ymod)
	instances[focus[2]][focus[1]].co, 		instances[focus[2] + ymod][focus[1] + xmod].co 	= instances[focus[2] + ymod][focus[1] + xmod].co, 			instances[focus[2]][focus[1]].co
	instances[focus[2]][focus[1]].window, 	instances[focus[2] + ymod][focus[1] + xmod].window = instances[focus[2] + ymod][focus[1] + xmod].window, 	instances[focus[2]][focus[1]].window
end

local inputEvt = {
	key = true,
	key_up = true,
	char = true,
	mouse_click = true,
	mouse_scroll = true,
	mouse_drag = true,
	mouse_up = true,
	paste = true,
	terminate = true
}

local main = function()
	local enteringCommand
	local justStarted = true
	local tID, wID
	while isRunning do
		local evt = {os.pullEventRaw()}
		enteringCommand = false
		if evt[1] == "key" then
			keysDown[evt[2]] = true
		elseif evt[1] == "key_up" then
			keysDown[evt[2]] = nil
		elseif evt[1] == "timer" then
			if evt[2] == wID then
				enteringCommand = true
				doDrawWorkspaceIndicator = false
			elseif evt[2] == tID then
				enteringCommand = true
			end
		end

		if scrollWindows() then
			tID = os.startTimer(0.05)
		end

		if (keysDown[keys.leftCtrl] or keysDown[keys.rightCtrl]) and (keysDown[keys.leftShift] or keysDown[keys.rightShift]) then
			if keysDown[keys.left] then
				if instances[focus[2]][focus[1] - 1] then
					if keysDown[swapKey] then
						swapInstances(-1, 0)
					end
					focus[1] = focus[1] - 1
					scroll[1] = scroll[1] + 1
					keysDown[keys.left] = false
					enteringCommand = true
					doDrawWorkspaceIndicator = true
					wID = os.startTimer(workspaceIndicatorDuration)
				end
			end
			if keysDown[keys.right] then
				if instances[focus[2]][focus[1] + 1] then
					if keysDown[swapKey] then
						swapInstances(1, 0)
					end
					focus[1] = focus[1] + 1
					scroll[1] = scroll[1] - 1
					keysDown[keys.right] = false
					enteringCommand = true
					doDrawWorkspaceIndicator = true
					wID = os.startTimer(workspaceIndicatorDuration)
				end
			end
			if keysDown[keys.up] then
				if instances[focus[2] - 1] then
					if instances[focus[2] - 1][focus[1]] then
						if keysDown[swapKey] then
							swapInstances(0, -1)
						end
						focus[2] = focus[2] - 1
						scroll[2] = scroll[2] + 1
						keysDown[keys.up] = false
						enteringCommand = true
						doDrawWorkspaceIndicator = true
						wID = os.startTimer(workspaceIndicatorDuration)
					end
				end
			end
			if keysDown[keys.down] then
				if instances[focus[2] + 1] then
					if instances[focus[2] + 1][focus[1]] then
						if keysDown[swapKey] then
							swapInstances(0, 1)
						end
						focus[2] = focus[2] + 1
						scroll[2] = scroll[2] - 1
						keysDown[keys.down] = false
						enteringCommand = true
						doDrawWorkspaceIndicator = true
						wID = os.startTimer(workspaceIndicatorDuration)
					end
				end
			end
		end

		if not enteringCommand then
			for y = 1, #instances do
				if instances[y] then
					for x = 1, #instances[y] do
						if instances[y][x] then

							if justStarted or (not inputEvt[evt[1]]) or (x == focus[1] and y == focus[2]) then
								local previousTerm = term.redirect(instances[y][x].window.handle)
								coroutine.resume(instances[y][x].co, table.unpack(evt))
								term.redirect(previousTerm)
							end

						end
					end
				end
			end
		end

		lddterm.selectedWindow = instances[focus[2]][focus[1]].window.layer
		lddterm.render()
		justStarted = false

	end
end

term.clear()
cwrite("Use CTRL+SHIFT+ARROW to switch workspace.",		0 + scr_y / 2)
cwrite("Terminate on an inactive workspace to exit.",	1 + scr_y / 2)
sleep(0.1)
os.pullEvent("key")

os.queueEvent("mouse_click", 0, 0, 0)

local result, message = pcall(main)

_G.currentlyRunningWorkspace = false

term.clear()
term.setCursorPos(1,1)
if result then
	print("Thanks for using Workspace!")
else
	print("There was an error, and Workspace had to stop.")
	print("The error goes as follows:\n")
	print(message)
end
