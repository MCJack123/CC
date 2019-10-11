--
-- ##     #####   ######  ######  ######
-- ##     ##  ##  ##   ##   ##   ##   ###
-- ##     ##   ## ##   ##   ##   ###
-- ##     ##   ## ######    ##    ######
-- ##     ##   ## ##   ##   ##        ###
-- ##     ##  ##  ##   ##   ##   ###   ##
-- #####  #####   ##   ## ######  ######
--
-- ComputerCraft port of Tetris
-- by LDDestroier
--
--  Supports wall kicking, holding, fast-dropping,
-- and ghost pieces.
--
-- TO-DO:
--  + Add multiplayer
--  + Add random color pulsation (for effect!)

local scr_x, scr_y = term.getSize()
local keysDown = {}
local game = {
	p = {},				-- stores player information
	paused = false,		-- whether or not game is paused
	canPause = true,	-- if false, cannot pause game (such as in online multiplayer)
	inputDelay = 0.05,	-- amount of time between each input
	control = {
		moveLeft = keys.left,
		moveRight = keys.right,
		moveDown = keys.down,
		rotateLeft = keys.z,
		rotateRight = keys.x,
		fastDrop = keys.up,
		hold = keys.leftShift,
		quit = keys.q
	},
	timers = {},
	timerNo = 1
}

game.startTimer = function(duration)
	game.timers[game.timerNo] = duration
	game.timerNo = game.timerNo + 1
	return game.timerNo - 1
end

game.cancelTimer = function(tID)
	game.timers[tID or 0] = nil
end

local tableCopy
tableCopy = function(tbl)
	local output = {}
	for k,v in pairs(tbl) do
		if type(v) == "table" then
			output[k] = tableCopy(v)
		else
			output[k] = v
		end
	end
	return output
end

-- sets up brown as colors.special, for palette swapping magic(k)
local tColors = tableCopy(colors)

tColors.white = 1
tColors.brown = nil	-- brown is now white
tColors.special = 4096
term.setPaletteColor(tColors.special, 0xf0f0f0)
term.setPaletteColor(tColors.white, 0xf0f0f0)

-- initializes and fixes up a board
-- boards are 2D objects that can display perfectly square graphics
local clearBoard = function(board, xpos, ypos, newXsize, newYsize, newBGcolor)
	board = board or {}
	board.x = board.x or xpos or 1
	board.y = board.y or ypos or 1
	board.xSize = board.xSize or newXsize or 10
	board.ySize = board.ySize or newYsize or 24
	board.BGcolor = board.BGcolor or newBGcolor or "f"
	for y = 1, board.ySize do
		board[y] = board[y] or {}
		for x = 1, board.xSize do
			-- explanation on each space:
			-- {
			--   boolean; if true, the space is solid
			--   string; the hex color of the space
			--   number; the countdown until the space is made non-solid (inactive if 0)
			--   number; the countdown until the space is colored to board.BGcolor (inactive if 0)
			-- }
			board[y][x] = board[y][x] or {false, board.BGcolor, 0, 0}
		end
	end
	return board
end

-- tetramino information
-- don't tamper with this or I'll beat your ass so hard that war veterans would blush
local minos = {
	[1] = {	-- I-piece
		canRotate = true,
		shape = {
			"    ",
			"3333",
			"    ",
			"    ",
		}
	},
	[2] = {	-- L-piece
		canRotate = true,
		shape = {
			"  1",
			"111",
			"   ",
		}
	},
	[3] = {	-- J-piece
		canRotate = true,
		shape = {
			"b  ",
			"bbb",
			"   ",
		}
	},
	[4] = {	-- O-piece
		canRotate = true,
		shape = {
			"44",
			"44",
		}
	},
	[5] = { -- T-piece
		canRotate = true,
		shape = {
			" a ",
			"aaa",
			"   ",
		}
	},
	[6] = { -- Z-piece
		canRotate = true,
		shape = {
			"ee ",
			" ee",
			"   ",
		}
	},
	[7] = {	-- S-piece
		canRotate = true,
		shape = {
			" 55",
			"55 ",
			"   ",
		}
	},
	["gameover"] = {	-- special "mino" for game over
		canRotate = false,
		shape = {
			" ccc   ccc  c   c ccccc    ccc  c   c ccccc  cccc",
			"c     c   c cc cc c       c   c c   c c     c   c",
			"c     c   c cc cc c       c   c c   c c     c   c",
			"c  cc ccccc c c c cccc    c   c  c c  cccc   cccc",
			"c   c c   c c   c c       c   c  c c  c     c   c",
			"c   c c   c c   c c       c   c  c c  c     c   c",
			"c   c c   c c   c c       c   c  c c  c     c   c",
			" ccc  c   c c   c ccccc    ccc    c   ccccc c   c",
		}
	}
}

-- converts blit colors to colors api, and back
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

-- checks if (x, y) is a valid space on the board
local doesSpaceExist = function(board, x, y)
	return (x >= 1 and x <= board.xSize) and (y >= 1 and y <= board.ySize)
end

-- checks if (x, y) is being occupied by a tetramino (or if it's off-board)
local isSpaceSolid = function(board, _x, _y)
	local x, y = math.floor(_x), math.floor(_y)
	if doesSpaceExist(board, x, y) then
		return board[y][x][1]
	else
		return true
	end
end

-- ticks down a space's timers, which can cause it to become non-solid or background-colored
local ageSpace = function(board, _x, _y)
	local x, y = math.floor(_x), math.floor(_y)
	if doesSpaceExist(board, x, y) then
		-- make space non-solid if timer elapses
		if board[y][x][3] ~= 0 then
			board[y][x][3] = board[y][x][3] - 1
			if board[y][x][3] == 0 then
				board[y][x][1] = false
			end
		end
		-- color space board.BGcolor if timer elapses
		if board[y][x][4] ~= 0 then
			board[y][x][4] = board[y][x][4] - 1
			if board[y][x][4] == 0 then
				board[y][x][2] = board.BGcolor
			end
		end
	end
end

-- generates a "mino" object, which can be drawn and manipulated on a board
local makeNewMino = function(minoType, board, x, y, replaceColor)
	local mino = tableCopy(minos[minoType])
	if replaceColor then
		for yy = 1, #mino.shape do
			mino.shape[yy] = mino.shape[yy]:gsub("[^ ]", replaceColor)
		end
	end
	-- what color the ghost mino will be
	mino.ghostColor = 0x353535

	mino.x = x
	mino.y = y
	mino.lockBreaks = 16	-- anti-infinite measure
	mino.waitingForLock = false
	mino.board = board
	mino.minoType = minoType
	-- checks to see if the mino is currently clipping with a solid board space (with the offset values)
	mino.checkCollision = function(xOffset, yOffset)
		local cx, cy
		for y = 1, #mino.shape do
			for x = 1, #mino.shape[y] do
				cx = mino.x + x + (xOffset or 0)
				cy = mino.y + y + (yOffset or 0)
				if mino.shape[y]:sub(x,x) ~= " " then
					if isSpaceSolid(mino.board, cx, cy) then
						return true
					end
				end
			end
		end
		return false
	end
	-- rotates a mino, and kicks it off a wall if need be
	mino.rotate = function(direction)
		local output = {}
		local oldShape = tableCopy(mino.shape)
		local origX, origY = mino.x, mino.y
		for y = 1, #mino.shape do
			output[y] = {}
			for x = 1, #mino.shape[y] do
				if direction == 1 then
					output[y][x] = mino.shape[#mino.shape - (x - 1)]:sub(y,y)
				elseif direction == -1 then
					output[y][x] = mino.shape[x]:sub(-y, -y)
				else
					error("invalid rotation direction (must be 1 or -1)")
				end
			end
			output[y] = table.concat(output[y])
		end
		mino.shape = output
		-- try to kick off wall/floor
		if mino.checkCollision(0, 0) then
			-- kick off floor
			for y = 1, math.floor(#mino.shape) do
				if not mino.checkCollision(0, -y) then
					mino.y = mino.y - y
					return true
				end
			end
			-- kick off right wall
			for x = 0, -math.floor(#mino.shape[1] / 2), -1 do
				if not mino.checkCollision(x, 0) then
					mino.x = mino.x + x
					return true
				end
				-- try diagonal-down
				if not mino.checkCollision(x, 1) then
					mino.x = mino.x + x
					mino.y = mino.y + 1
					return true
				end
			end
			-- kick off left wall
			for x = 0, math.floor(#mino.shape[1] / 2) do
				if not mino.checkCollision(x, 0) then
					mino.x = mino.x + x
					return true
				end
				-- try diagonal-down
				if not mino.checkCollision(x, 1) then
					mino.x = mino.x + x
					mino.y = mino.y + 1
					return true
				end
			end
			mino.shape = oldShape
			return false
		else
			return true
		end
	end
	-- draws a mino onto a board; you'll still need to render the board, though
	mino.draw = function(isSolid)
		for y = 1, #mino.shape do
			for x = 1, #mino.shape[y] do
				if mino.shape[y]:sub(x,x) ~= " " then
					if doesSpaceExist(mino.board, x + math.floor(mino.x), y + math.floor(mino.y)) then
						mino.board[y + math.floor(mino.y)][x + math.floor(mino.x)] = {
							isSolid or false,
							mino.shape[y]:sub(x,x),
							isSolid and 0 or 0,
							isSolid and 0 or 1
						}
					end
				end
			end
		end
	end
	-- moves a mino, making sure not to clip with solid board spaces
	mino.move = function(x, y, doSlam)
		if not mino.checkCollision(x, y) then
			mino.x = mino.x + x
			mino.y = mino.y + y
			return true
		elseif doSlam then
			for sx = 0, x, math.abs(x) / x do
				if mino.checkCollision(sx, 0) then
					mino.x = mino.x + sx - math.abs(x) / x
					break
				end
			end
			for sy = 0, y, math.abs(y) / y do
				if mino.checkCollision(0, sy) then
					mino.y = mino.y + sy - math.abs(y) / y
					break
				end
			end
		else
			return false
		end
	end

	return mino
end

-- generates a random number, excluding those listed in the _psExclude table
local pseudoRandom = function(randomPieces)
	if #randomPieces == 0 then
		for i = 1, #minos do
			randomPieces[i] = i
		end
	end
	local rand = math.random(1, #randomPieces)
	local num = randomPieces[rand]
	table.remove(randomPieces, rand)
	return num
end

-- initialize players
local initializePlayers = function()
	game.p[1] = {
		board = clearBoard({}, 2, 2, 10, 24, "f"),
		holdBoard = clearBoard({}, 13, 14, 4, 3, "f"),
		queueBoard = clearBoard({}, 13, 2, 4, 14, "f"),
		randomPieces = {},	-- list of all minos for pseudo-random selection
		hold = 0,			-- current piece being held
		canHold = true,		-- whether or not player can hold (can't hold twice in a row)
		queue = {},			-- current queue of minos to use
		lines = 0,			-- amount of lines cleared, "points"
		combo = 0,			-- amount of consequative line clears
		lastLinesClear = 0,	-- previous amount of simultaneous line clears (does not reset if miss)
		level = 1,			-- level determines speed of mino drop
		fallSteps = 0.1,		-- amount of spaces the mino will draw each drop
	}
	game.p[2] = {
		board = clearBoard({}, 18, 2, 10, 24, "f"),
		holdBoard = clearBoard({}, 29, 14, 4, 3, "f"),
		queueBoard = clearBoard({}, 29, 2, 4, 14, "f"),
		randomPieces = {},
		hold = 0,
		canHold = true,
		queue = {},
		lines = 0,
		combo = 0,
		lastLinesClear = 0,
		level = 1,
		fallSteps = 0.1,
	}
	-- generates the initial queue of minos per player
	for p = 1, #game.p do
		for i = 1, #minos do
			game.p[p].queue[i] = pseudoRandom(game.p[p].randomPieces)
		end
	end
end

-- actually renders a board to the screen
local renderBoard = function(board, bx, by, doAgeSpaces, blankColor)
	local char, line
	local tY = board.y + (by or 0)
	for y = 1, board.ySize, 3 do
		line = {("\143"):rep(board.xSize),"",""}
		term.setCursorPos(board.x + (bx or 0), tY)
		for x = 1, board.xSize do
			line[2] = line[2] .. (blankColor or board[y][x][2])
			if board[y + 1] then
				line[3] = line[3] .. (blankColor or board[y + 1][x][2])
			else
				line[3] = line[3] .. board.BGcolor
			end
		end
		term.blit(line[1], line[2], line[3])
		line = {("\131"):rep(board.xSize),"",""}
		term.setCursorPos(board.x + (bx or 0), tY + 1)
		for x = 1, board.xSize do
			if board[y + 2] then
				line[2] = line[2] .. (blankColor or board[y + 1][x][2])
				line[3] = line[3] .. (blankColor or board[y + 2][x][2])
			elseif board[y + 1] then
				line[2] = line[2] .. (blankColor or board[y + 1][x][2])
				line[3] = line[3] .. board.BGcolor
			else
				line[2] = line[2] .. board.BGcolor
				line[3] = line[3] .. board.BGcolor
			end
		end
		term.blit(line[1], line[2], line[3])
		tY = tY + 2
	end
	if doAgeSpaces then
		for y = 1, board.ySize do
			for x = 1, board.xSize do
				ageSpace(board, x, y)
			end
		end
	end
end

-- checks if you've done the one thing in tetris that you need to be doing
local checkIfLineCleared = function(board, y)
	for x = 1, board.xSize do
		if not board[y][x][1] then
			return false
		end
	end
	return true
end

-- draws the score of a player, and clears the space where the combo text is drawn
local drawScore = function(player)
	term.setCursorPos(2, 18)
	term.setTextColor(tColors.white)
	term.write((" "):rep(16))
	term.setCursorPos(2, 18)
	term.write("Lines: " .. player.lines)
	term.setCursorPos(2, 19)
	term.write((" "):rep(16))
end

local drawLevel = function(player)
	term.setCursorPos(13, 17)
	term.write("Lv" .. player.level .. "  ")
end

-- draws the player's simultaneous line clear after clearing one or more lines
-- also tells the player's combo, which is nice
local drawComboMessage = function(player, lines)
	term.setCursorPos(2, 18)
	term.setTextColor(tColors.white)
	term.write((" "):rep(16))
	local msgs = {
		"SINGLE",
		"DOUBLE",
		"TRIPLE",
		"TETRIS"
	}
	term.setCursorPos(2, 18)
	if lines == player.lastLinesCleared then
		if lines == 3 then
			term.write("OH BABY A ")
		else
			term.write("ANOTHER ")
		end
	end
	term.write(msgs[lines])
	if player.combo >= 2 then
		term.setCursorPos(2, 19)
		term.setTextColor(tColors.white)
		term.write((" "):rep(16))
		term.setCursorPos(2, 19)
		term.write(player.combo .. "x COMBO")
	end

end

-- god damn it you've fucked up
local gameOver = function(player)
	local mino = makeNewMino("gameover", player.board, 12, 3)
	local color = 0
	for i = 1, 130 do
		if i % 2 == 0 then
			mino.x = mino.x - 1
		end
		mino.draw()
		renderBoard(player.board, 0, 0, true)
		for i = 1, 20 do
			color = color + 0.01
			term.setPaletteColor(4096, math.sin(color) / 2 + 0.5, math.sin(color) / 2, math.sin(color) / 2)
		end
		sleep(0.05)
	end
	return
end

-- initiates a game as a specific player (takes a number)
local startGame = function(playerNumber)
	term.setBackgroundColor(tColors.gray)
	term.clear()

	initializePlayers()

	local mino, ghostMino
	local dropTimer, inputTimer, lockTimer, tickTimer
	local evt, board, player
	local clearedLines = {}

	player = game.p[playerNumber]
	board = player.board

	local draw = function(isSolid)
		term.setPaletteColor(4096, mino.ghostColor)
		ghostMino.x = mino.x
		ghostMino.y = mino.y
		ghostMino.move(0, board.ySize, true)
		ghostMino.draw(false)
		mino.draw(isSolid)
		renderBoard(board, 0, 0, true)
	end

	local currentMinoType
	local takeFromQueue = true

	term.setCursorPos(13, 13)
	term.write("HOLD")
	renderBoard(player.holdBoard, 0, 0, true)

	while true do

		player.level = math.ceil((1 + player.lines) / 10)
		player.fallSteps = 0.075 * (1.33 ^ player.level)

		drawLevel(player)

		if takeFromQueue then
			currentMinoType = player.queue[1]
		end

		mino = makeNewMino(
			currentMinoType,
			board,
			math.floor(board.xSize / 2) - 2,
			0
		)

		ghostMino = makeNewMino(
			currentMinoType,
			board,
			math.floor(board.xSize / 2) - 2,
			0,
			"c"
		)

		if takeFromQueue then
			table.remove(player.queue, 1)
			table.insert(player.queue, pseudoRandom(player.randomPieces))
		end

		-- draw queue
		for i = 1, math.min(#player.queue, 4) do
			local m = makeNewMino(
				player.queue[i],
				player.queueBoard,
				#minos[player.queue[i]].shape[1] == 2 and 1 or 0,
				1 + (3 * (i - 1)) + (i > 1 and 2 or 0)
			)
			m.draw()
		end
		renderBoard(player.queueBoard, 0, 0, true)

		-- draw held piece
		if player.hold ~= 0 then
			local m = makeNewMino(
				player.hold,
				player.holdBoard,
				#minos[player.hold].shape[1] == 2 and 1 or 0,
				0
			)
		end

		takeFromQueue = true

		drawScore(player)

		-- check to see if you've lost
		if mino.checkCollision() then
			gameOver(player)
			return
		end

		draw()

		dropTimer = game.startTimer(0)
		inputTimer = game.startTimer(game.inputDelay)
		game.cancelTimer(lockTimer or 0)

		tickTimer = os.startTimer(0.05)

		-- drop a piece
		while true do

			evt = {os.pullEvent()}

			-- tick down internal game timer system
			if evt[1] == "timer" and evt[2] == tickTimer then
				--local delKeys = {}
				for k,v in pairs(game.timers) do
					game.timers[k] = v - 0.05
					if v <= 0 then
						os.queueEvent("gameTimer", k)
						game.timers[k] = nil
					end
				end
				tickTimer = os.startTimer(0.05)
			end

			if player.paused then
				if evt[1] == "key" then
					if evt[2] == game.control.pause then
						game.paused = false
					end
				end
			else
				if evt[1] == "key" then
					if evt[2] == game.control.quit then
						return
					elseif evt[2] == game.control.pause then
						game.paused = true
					elseif evt[2] == game.control.rotateRight then
						if mino.rotate(1) then
							ghostMino.y = mino.y
							ghostMino.rotate(1)
							game.cancelTimer(lockTimer or 0)
							mino.waitingForLock = false
							draw()
						end
					elseif evt[2] == game.control.rotateLeft then
						if mino.rotate(-1) then
							ghostMino.y = mino.y
							ghostMino.rotate(-1)
							game.cancelTimer(lockTimer or 0)
							mino.waitingForLock = false
							draw()
						end
					end
					if evt[3] == false then
						if evt[2] == game.control.moveLeft then
							mino.move(-1, 0)
							game.cancelTimer(lockTimer or 0)
							mino.waitingForLock = false
							draw()
							game.cancelTimer(inputTimer or 0)
							inputTimer = game.startTimer(game.inputDelay)
						elseif evt[2] == game.control.moveRight then
							mino.move(1, 0)
							game.cancelTimer(lockTimer or 0)
							mino.waitingForLock = false
							draw()
							game.cancelTimer(inputTimer or 0)
							inputTimer = game.startTimer(game.inputDelay)
						elseif evt[2] == game.control.fastDrop then
							mino.move(0, board.ySize, true)
							draw(true)
							player.canHold = true
							break
						elseif evt[2] == game.control.hold then
							if player.canHold then
								if player.hold == 0 then
									takeFromQueue = true
								else
									takeFromQueue = false
								end
								player.hold, currentMinoType = currentMinoType, player.hold
								player.canHold = false
								makeNewMino(
									player.hold,
									player.holdBoard,
									#minos[player.hold].shape[1] == 2 and 1 or 0,
									0
								).draw()
								renderBoard(player.holdBoard, 0, 0, true)
								break
							end
						end
					end
				elseif evt[1] == "gameTimer" then
					if evt[2] == inputTimer then
						inputTimer = game.startTimer(game.inputDelay)
						if not game.paused then
							if keysDown[game.control.moveLeft] == 2 then
								if mino.move(-1, 0) then
									game.cancelTimer(lockTimer or 0)
									mino.waitingForLock = false
									draw()
								end
							end
							if keysDown[game.control.moveRight] == 2 then
								if mino.move(1, 0) then
									game.cancelTimer(lockTimer or 0)
									mino.waitingForLock = false
									draw()
								end
							end
							if keysDown[game.control.moveDown] then
								game.cancelTimer(lockTimer or 0)
								mino.waitingForLock = false
								if mino.move(0, 1) then
									draw()
								else
									draw(true)
									break
								end
							end
						end
					elseif evt[2] == dropTimer then
						dropTimer = game.startTimer(0)
						if not game.paused then
							if mino.checkCollision(0, 1) then
								if mino.lockBreaks == 0 then
									draw(true)
									player.canHold = true
									break
								elseif not mino.waitingForLock then
									mino.lockBreaks = mino.lockBreaks - 1
									lockTimer = game.startTimer(math.max(0.2 / player.fallSteps, 0.25))
									mino.waitingForLock = true
								end
							else
								mino.move(0, player.fallSteps, true)
								draw()
							end
						end
					elseif evt[2] == lockTimer then
						if not game.paused then
							player.canHold = true
							draw(true)
							break
						end
					end
				end
			end
		end

		clearedLines = {}
		for y = 1, board.ySize do
			if checkIfLineCleared(board, y) then
				table.insert(clearedLines, y)
			end
		end
		if #clearedLines == 0 then
			if player.canHold then
				player.combo = 0
			end
		else
			player.combo = player.combo + 1
			player.lines = player.lines + #clearedLines
			drawComboMessage(player, #clearedLines)
			player.lastLinesCleared = #clearedLines
			for i = 1, 0, -0.12 do
				term.setPaletteColor(4096, i,i,i)
				for l = 1, #clearedLines do
					for x = 1, board.xSize do
						board[clearedLines[l]][x][2] = "c"
					end
				end
				renderBoard(board, 0, 0, true)
				sleep(0.05)
			end
			for i = #clearedLines, 1, -1 do
				table.remove(board, clearedLines[i])
			end
			for i = 1, #clearedLines do
				table.insert(board, 1, false)
			end
			board = clearBoard(board)
		end
	end
end

-- records all key input
local getInput = function()
	local evt
	local keyTimer = {}
	local timerKey = {}
	while true do
		evt = {os.pullEvent()}
		if evt[1] == "key" and evt[3] == false then
			keysDown[evt[2]] = 1
			timerKey[evt[2]] = os.startTimer(0.2)
			keyTimer[timerKey[evt[2]]] = evt[2]
		elseif evt[1] == "timer" then
			if keysDown[keyTimer[evt[2]]] then
				keysDown[keyTimer[evt[2]]] = 2
			end
		elseif evt[1] == "key_up" then
			keysDown[evt[2]] = nil
			os.cancelTimer(timerKey[evt[2]] or 0)
			keyTimer[timerKey[evt[2]] or 0] = nil
			timerKey[evt[2]] = nil
		end
	end
end

local main = function()
	startGame(1)
end

parallel.waitForAny(main, getInput)

-- reset palette to back from whence it came
for k,v in pairs(colors) do
	if type(v) == "number" then
		term.setPaletteColor(v, term.nativePaletteColor(v))
	end
end

print(colors.white)

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)

for i = 1, 5 do
	term.scroll(1)
	if i == 3 then
		term.setCursorPos(1, scr_y)
		term.write("Thanks for playing!")
	end
	sleep(0.05)
end
term.setCursorPos(1, scr_y)
