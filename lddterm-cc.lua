local lddterm = {}
local scr_x, scr_y

lddterm.alwaysRender = true		-- renders after any and all screen-changing functions.
lddterm.useColors = true			-- normal computers do not allow color, but this variable doesn't do anything yet
lddterm.baseTerm = term.current()	-- will draw to this terminal
lddterm.transformation = nil		-- will modify the current buffer as an NFT image before rendering
lddterm.cursorTransformation = nil	-- will modify the cursor position
lddterm.drawFunction = nil			-- will draw using this function instead of basic NFT drawing
lddterm.adjustX = 0					-- moves entire screen X
lddterm.adjustY = 0					-- moves entire screen Y
lddterm.windows = {}

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
	scr_x, scr_y = term.getSize()
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
	if lddterm.windows[1] then
		if lddterm.cursorTransformation then
			cx, cy = lddterm.cursorTransformation(lddterm.windows[1].cursor[1], lddterm.windows[1].cursor[2])
			lddterm.baseTerm.setCursorPos(
				cx + lddterm.windows[1].x - 1,
				cy + lddterm.windows[1].y - 1
			)
		else
			lddterm.baseTerm.setCursorPos(
				-1 + lddterm.windows[1].cursor[1] + lddterm.windows[1].x,
				lddterm.windows[1].cursor[2] + lddterm.windows[1].y - 1
			)
		end
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
	fixCursorPos()
end

-- paintutils is a set of art functions for loading and drawing images and drawing lines and boxes.
local makePaintutilsAPI = function(term)
	local paintutils = {}

	local function drawPixelInternal( xPos, yPos )
		term.setCursorPos( xPos, yPos )
		term.write(" ")
	end

	local tColourLookup = {}
	for n=1,16 do
		tColourLookup[ string.byte( "0123456789abcdef",n,n ) ] = 2^(n-1)
	end

	local function parseLine( tImageArg, sLine )
		local tLine = {}
		for x=1,sLine:len() do
			tLine[x] = tColourLookup[ string.byte(sLine,x,x) ] or 0
		end
		table.insert( tImageArg, tLine )
	end

	function paintutils.parseImage( sRawData )
		if type( sRawData ) ~= "string" then
			error( "bad argument #1 (expected string, got " .. type( sRawData ) .. ")" )
		end
		local tImage = {}
		for sLine in ( sRawData .. "\n" ):gmatch( "(.-)\n" ) do -- read each line like original file handling did
			parseLine( tImage, sLine )
		end
		return tImage
	end

	function paintutils.loadImage( sPath )
		if type( sPath ) ~= "string" then
			error( "bad argument #1 (expected string, got " .. type( sPath ) .. ")", 2 )
		end

		local file = io.open( sPath, "r" )
		if file then
			local sContent = file:read("*a")
			file:close()
			return paintutils.parseImage( sContent ) -- delegate image parse to parseImage
		end
		return nil
	end

	function paintutils.drawPixel( xPos, yPos, nColour )
		if type( xPos ) ~= "number" then error( "bad argument #1 (expected number, got " .. type( xPos ) .. ")", 2 ) end
		if type( yPos ) ~= "number" then error( "bad argument #2 (expected number, got " .. type( yPos ) .. ")", 2 ) end
		if nColour ~= nil and type( nColour ) ~= "number" then error( "bad argument #3 (expected number, got " .. type( nColour ) .. ")", 2 ) end
		if nColour then
			term.setBackgroundColor( nColour )
		end
		drawPixelInternal( xPos, yPos )
	end

	function paintutils.drawLine( startX, startY, endX, endY, nColour )
		if type( startX ) ~= "number" then error( "bad argument #1 (expected number, got " .. type( startX ) .. ")", 2 ) end
		if type( startY ) ~= "number" then error( "bad argument #2 (expected number, got " .. type( startY ) .. ")", 2 ) end
		if type( endX ) ~= "number" then error( "bad argument #3 (expected number, got " .. type( endX ) .. ")", 2 ) end
		if type( endY ) ~= "number" then error( "bad argument #4 (expected number, got " .. type( endY ) .. ")", 2 ) end
		if nColour ~= nil and type( nColour ) ~= "number" then error( "bad argument #5 (expected number, got " .. type( nColour ) .. ")", 2 ) end

		local alwaysRender = lddterm.alwaysRender
		lddterm.alwaysRender = false

		startX = math.floor(startX)
		startY = math.floor(startY)
		endX = math.floor(endX)
		endY = math.floor(endY)

		if nColour then
			term.setBackgroundColor( nColour )
		end
		if startX == endX and startY == endY then
			drawPixelInternal( startX, startY )
			if alwaysRender then lddterm.render(lddterm.transformation, lddterm.drawFunction) end
			lddterm.alwaysRender = alwaysRender
			return
		end

		local minX = math.min( startX, endX )
		local maxX, minY, maxY
		if minX == startX then
			minY = startY
			maxX = endX
			maxY = endY
		else
			minY = endY
			maxX = startX
			maxY = startY
		end

		local xDiff = maxX - minX
		local yDiff = maxY - minY

		if xDiff > math.abs(yDiff) then
			local y = minY
			local dy = yDiff / xDiff
			for x=minX,maxX do
				drawPixelInternal( x, math.floor( y + 0.5 ) )
				y = y + dy
			end
		else
			local x = minX
			local dx = xDiff / yDiff
			if maxY >= minY then
				for y=minY,maxY do
					drawPixelInternal( math.floor( x + 0.5 ), y )
					x = x + dx
				end
			else
				for y=minY,maxY,-1 do
					drawPixelInternal( math.floor( x + 0.5 ), y )
					x = x - dx
				end
			end
		end
		if alwaysRender then lddterm.render(lddterm.transformation, lddterm.drawFunction) end
		lddterm.alwaysRender = alwaysRender
	end

	function paintutils.drawBox( startX, startY, endX, endY, nColour )
		if type( startX ) ~= "number" then error( "bad argument #1 (expected number, got " .. type( startX ) .. ")", 2 ) end
		if type( startY ) ~= "number" then error( "bad argument #2 (expected number, got " .. type( startY ) .. ")", 2 ) end
		if type( endX ) ~= "number" then error( "bad argument #3 (expected number, got " .. type( endX ) .. ")", 2 ) end
		if type( endY ) ~= "number" then error( "bad argument #4 (expected number, got " .. type( endY ) .. ")", 2 ) end
		if nColour ~= nil and type( nColour ) ~= "number" then error( "bad argument #5 (expected number, got " .. type( nColour ) .. ")", 2 ) end

		local alwaysRender = lddterm.alwaysRender
		lddterm.alwaysRender = false

		startX = math.floor(startX)
		startY = math.floor(startY)
		endX = math.floor(endX)
		endY = math.floor(endY)

		if nColour then
			term.setBackgroundColor( nColour )
		end
		if startX == endX and startY == endY then
			drawPixelInternal( startX, startY )
			if alwaysRender then lddterm.render(lddterm.transformation, lddterm.drawFunction) end
			lddterm.alwaysRender = alwaysRender
			return
		end

		local minX = math.min( startX, endX )
		local maxX, minY, maxY
		if minX == startX then
			minY = startY
			maxX = endX
			maxY = endY
		else
			minY = endY
			maxX = startX
			maxY = startY
		end

		for x=minX,maxX do
			drawPixelInternal( x, minY )
			drawPixelInternal( x, maxY )
		end

		if (maxY - minY) >= 2 then
			for y=(minY+1),(maxY-1) do
				drawPixelInternal( minX, y )
				drawPixelInternal( maxX, y )
			end
		end
		if alwaysRender then lddterm.render(lddterm.transformation, lddterm.drawFunction) end
		lddterm.alwaysRender = alwaysRender
	end

	function paintutils.drawFilledBox( startX, startY, endX, endY, nColour )
		if type( startX ) ~= "number" then error( "bad argument #1 (expected number, got " .. type( startX ) .. ")", 2 ) end
		if type( startY ) ~= "number" then error( "bad argument #2 (expected number, got " .. type( startY ) .. ")", 2 ) end
		if type( endX ) ~= "number" then error( "bad argument #3 (expected number, got " .. type( endX ) .. ")", 2 ) end
		if type( endY ) ~= "number" then error( "bad argument #4 (expected number, got " .. type( endY ) .. ")", 2 ) end
		if nColour ~= nil and type( nColour ) ~= "number" then error( "bad argument #5 (expected number, got " .. type( nColour ) .. ")", 2 ) end

		local alwaysRender = lddterm.alwaysRender
		lddterm.alwaysRender = false

		startX = math.floor(startX)
		startY = math.floor(startY)
		endX = math.floor(endX)
		endY = math.floor(endY)

		if nColour then
			term.setBackgroundColor( nColour )
		end
		if startX == endX and startY == endY then
			drawPixelInternal( startX, startY )
			return
		end

		local minX = math.min( startX, endX )
		local maxX, minY, maxY
		if minX == startX then
			minY = startY
			maxX = endX
			maxY = endY
		else
			minY = endY
			maxX = startX
			maxY = startY
		end

		for x=minX,maxX do
			for y=minY,maxY do
				drawPixelInternal( x, y )
			end
		end
		if alwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
		lddterm.alwaysRender = alwaysRender
	end

	function paintutils.drawImage( tImage, xPos, yPos )
		if type( tImage ) ~= "table" then error( "bad argument #1 (expected table, got " .. type( tImage ) .. ")", 2 ) end
		if type( xPos ) ~= "number" then error( "bad argument #2 (expected number, got " .. type( xPos ) .. ")", 2 ) end
		if type( yPos ) ~= "number" then error( "bad argument #3 (expected number, got " .. type( yPos ) .. ")", 2 ) end

		local alwaysRender = lddterm.alwaysRender
		lddterm.alwaysRender = false

		for y=1,#tImage do
			local tLine = tImage[y]
			for x=1,#tLine do
				if tLine[x] > 0 then
					term.setBackgroundColor( tLine[x] )
					drawPixelInternal( x + xPos - 1, y + yPos - 1 )
				end
			end
		end
		if alwaysRender then
			lddterm.render(lddterm.transformation, lddterm.drawFunction)
		end
		lddterm.alwaysRender = alwaysRender
	end

	return paintutils
	end

lddterm.newWindow = function(width, height, x, y, meta)
	meta = meta or {}
	local window = {
		width = math.floor(width),
		height = math.floor(height),
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
		return lddterm.baseTerm.setCursorBlink(blink)
	end
	window.handle.getCursorBlink = function()
		return lddterm.baseTerm.getCursorBlink(blink)
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
			if cx >= window.width or cy < 1 then
				cx = 1
				if cy >= window.height then
					window.handle.scroll(1)
				else
					cy = cy + 1
				end
			else
				cx = cx + 1
			end
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

	window.ccapi = {
		colors = colors,
		paintutils = makePaintutilsAPI(window.handle)
	}

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

-- if the screen changes size, the effect is broken
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

				c = " "
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

return lddterm
