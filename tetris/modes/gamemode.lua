local Object = require 'libs.classic'
require 'funcs'

local playedReadySE = false
local playedGoSE = false

local Grid = require 'tetris.components.grid'
local Randomizer = require 'tetris.randomizers.bag7'
local BagRandomizer = require 'tetris.randomizers.bag'

local GameMode = Object:extend()

GameMode.name = ""
GameMode.hash = ""
GameMode.tagline = ""
GameMode.rollOpacityFunction = function(age) return 0 end

function GameMode:new(secret_inputs)
	self.grid = Grid(10, 24)
	self.randomizer = Randomizer()
	self.piece = nil
	self.ready_frames = 100
	self.frames = 0
	self.game_over_frames = 0
	self.score = 0
	self.level = 0
	self.lines = 0
	self.squares = 0
	self.drop_bonus = 0
	self.are = 0
	self.lcd = 0
	self.das = { direction = "none", frames = -1 }
	self.move = "none"
	self.prev_inputs = {}
	self.next_queue = {}
	self.game_over = false
	self.clear = false
	self.completed = false
	-- configurable parameters
	self.lock_drop = false
	self.lock_hard_drop = false
	self.instant_hard_drop = false
	self.instant_soft_drop = true
	self.enable_hold = false
	self.enable_hard_drop = true
	self.next_queue_length = 1
	self.additive_gravity = true
	self.classic_lock = false
	self.draw_section_times = false
	self.draw_secondary_section_times = false
	self.big_mode = false
	self.irs = true
	self.ihs = true
	self.square_mode = false
	self.immobile_spin_bonus = false
	self.rpc_details = "In game"
	self.SGnames = {
		"9", "8", "7", "6", "5", "4", "3", "2", "1",
		"S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9",
		"GM"
	}
	-- variables related to configurable parameters
	self.drop_locked = false
	self.hard_drop_locked = false
	self.lock_on_soft_drop = false
	self.lock_on_hard_drop = false
	self.cleared_block_table = {}
	self.used_randomizer = nil
	self.hold_queue = nil
	self.held = false
	self.section_start_time = 0
	self.section_times = { [0] = 0 }
	self.secondary_section_times = { [0] = 0 }
end

function GameMode:getARR() return 1 end
function GameMode:getDropSpeed() return 1 end
function GameMode:getARE() return 25 end
function GameMode:getLineARE() return 25 end
function GameMode:getLockDelay() return 30 end
function GameMode:getLineClearDelay() return 40 end
function GameMode:getDasLimit() return 15 end
function GameMode:getDasCutDelay() return 0 end
function GameMode:getGravity() return 1/64 end

function GameMode:getNextPiece(ruleset)
	return {
		skin = self:getSkin(),
		shape = self.used_randomizer:nextPiece(),
		orientation = ruleset:getDefaultOrientation(),
	}
end

function GameMode:getSkin()
	return "2tie"
end

function GameMode:initialize(ruleset)
	-- generate next queue
	self.used_randomizer = (
		ruleset.pieces == self.randomizer.possible_pieces and
		self.randomizer or
		(
			ruleset.pieces == 7 and
			Randomizer() or
			BagRandomizer(ruleset.pieces)
		)
	)
	self.ruleset = ruleset
	for i = 1, math.max(self.next_queue_length, 1) do
		table.insert(self.next_queue, self:getNextPiece(ruleset))
	end
	self.lock_on_soft_drop = ({ruleset.softdrop_lock, self.instant_soft_drop, false, true })[config.gamesettings.manlock]
	self.lock_on_hard_drop = ({ruleset.harddrop_lock, self.instant_hard_drop, true,  false})[config.gamesettings.manlock]
end

function GameMode:update(inputs, ruleset)
	if self.game_over or self.completed then
		self.game_over_frames = self.game_over_frames + 1
		return
	end

	if config.gamesettings.diagonal_input == 2 then
		if inputs["left"] or inputs["right"] then
			inputs["up"] = false
			inputs["down"] = false
		elseif inputs["up"] or inputs["down"] then
			inputs["left"] = false
			inputs["right"] = false
		end
	end

	-- advance one frame
	if self:advanceOneFrame(inputs, ruleset) == false then return end

	self:chargeDAS(inputs, self:getDasLimit(), self:getARR())

	-- set attempt flags
	if inputs["left"] or inputs["right"] then self:onAttemptPieceMove(self.piece, self.grid) end
	if (
		inputs["rotate_left"] or inputs["rotate_right"] or
		inputs["rotate_left2"] or inputs["rotate_right2"] or
		inputs["rotate_180"]
	) then
		self:onAttemptPieceRotate(self.piece, self.grid)
	end
	
	if self.piece == nil then
		self:processDelays(inputs, ruleset)
	else
		-- perform active frame actions such as fading out the next queue
		self:whilePieceActive()
		local gravity = self:getGravity()

		if self.enable_hold and inputs["hold"] == true and self.held == false and self.prev_inputs["hold"] == false then
			self:hold(inputs, ruleset)
			self.prev_inputs = inputs
			if not self.grid:canPlacePiece(self.piece) then
				self.game_over = true
			end
			return
		end

		if (self.lock_drop or (
			not ruleset.are or self:getARE() == 0
		)) and inputs["down"] ~= true then
			self.drop_locked = false
		end

		if (self.lock_hard_drop or (
			not ruleset.are or self:getARE() == 0
		)) and inputs["up"] ~= true then
			self.hard_drop_locked = false
		end

		-- diff vars to use in checks
		local piece_y = self.piece.position.y
		local piece_x = self.piece.position.x
		local piece_rot = self.piece.rotation

		ruleset:processPiece(
			inputs, self.piece, self.grid, self:getGravity(), self.prev_inputs,
			self.move, self:getLockDelay(), self:getDropSpeed(),
			self.drop_locked, self.hard_drop_locked,
			self.enable_hard_drop, self.additive_gravity, self.classic_lock
		)

		local piece_dy = self.piece.position.y - piece_y
		local piece_dx = self.piece.position.x - piece_x
		local piece_drot = self.piece.rotation - piece_rot

		-- das cut
		if (
			(piece_dy ~= 0 and (inputs.up or inputs.down)) or
			(piece_drot ~= 0 and (
				inputs.rotate_left or inputs.rotate_right or
				inputs.rotate_left2 or inputs.rotate_right2 or
				inputs.rotate_180
			))
		) then
			self:dasCut()
		end

		if (piece_dx ~= 0) then
			self.piece.last_rotated = false
			self:onPieceMove(self.piece, self.grid, piece_dx)
		end
		if (piece_drot ~= 0) then
			self.piece.last_rotated = true
			self:onPieceRotate(self.piece, self.grid, piece_drot)
		end
		if (piece_dy ~= 0) then
			self.piece.last_rotated = false
			self:onPieceDrop(self.piece, self.grid, piece_dy)
		end

		if inputs["up"] == true and
			self.piece:isDropBlocked(self.grid) and
			not self.hard_drop_locked then
			self:onHardDrop(piece_dy)
			if self.lock_on_hard_drop then
				self.piece_hard_dropped = true
				self.piece.locked = true
			end
		end

		if inputs["down"] == true then
			self:onSoftDrop(piece_dy)
			if self.piece:isDropBlocked(self.grid) and
				not self.drop_locked and
				self.lock_on_soft_drop
			then
				self.piece.locked = true
			end
		end

		if self.piece.locked == true then
			-- spin detection, immobile only for now
			if self.immobile_spin_bonus and (
				self.piece:isDropBlocked(self.grid) and
				self.piece:isMoveBlocked(self.grid, { x=-1, y=0 }) and 
				self.piece:isMoveBlocked(self.grid, { x=1, y=0 }) and
				self.piece:isMoveBlocked(self.grid, { x=0, y=-1 })
			) then
				self.piece.spin = true
			end

			self.grid:applyPiece(self.piece)
			
			-- mark squares (can be overridden)
			if self.square_mode then
				self.squares = self.squares + self.grid:markSquares()
			end

			local cleared_row_count = self.grid:getClearedRowCount()
			self:onPieceLock(self.piece, cleared_row_count)
			self:updateScore(self.level, self.drop_bonus, cleared_row_count)

			self.cleared_block_table = self.grid:markClearedRows()
			self.piece = nil
			if self.enable_hold then
				self.held = false
			end

			if cleared_row_count > 0 then
				playSE("erase")
				self.lcd = self:getLineClearDelay()
				self.are = (
					ruleset.are and self:getLineARE() or 0
				)
				if self.lcd == 0 then
					self.grid:clearClearedRows()
					self:afterLineClear(cleared_row_count)
					if self.are == 0 then
						self:initializeOrHold(inputs, ruleset)
					end
				end
				self:onLineClear(cleared_row_count)
			else
				if self:getARE() == 0 or not ruleset.are then
					self:initializeOrHold(inputs, ruleset)
				else
					self.are = self:getARE()
				end
			end
		end
	end
	self.prev_inputs = inputs
end

function GameMode:updateScore() end

function GameMode:advanceOneFrame()
	if self.clear then
		self.completed = true
	elseif self.ready_frames == 0 then
		self.frames = self.frames + 1
	end
end

-- event functions
function GameMode:whilePieceActive() end
function GameMode:onAttemptPieceMove(piece, grid) end
function GameMode:onAttemptPieceRotate(piece, grid) end
function GameMode:onPieceMove(piece, grid, dx) end
function GameMode:onPieceRotate(piece, grid, drot) end
function GameMode:onPieceDrop(piece, grid, dy) end
function GameMode:onPieceLock(piece, cleared_row_count) 
	playSE("lock")
end

function GameMode:onLineClear(cleared_row_count) end
function GameMode:afterLineClear(cleared_row_count) end

function GameMode:onPieceEnter() end
function GameMode:onHold() end

function GameMode:onSoftDrop(dropped_row_count)
	self.drop_bonus = self.drop_bonus + 1 * dropped_row_count
end

function GameMode:onHardDrop(dropped_row_count)
	self.drop_bonus = self.drop_bonus + 2 * dropped_row_count
end

function GameMode:onGameOver()
	switchBGM(nil)
	love.graphics.setColor(0, 0, 0, 1 - 2 ^ (-self.game_over_frames / 30))
	love.graphics.rectangle(
		"fill", 64, 80,
		16 * self.grid.width, 16 * (self.grid.height - 4)
	)
end

function GameMode:onGameComplete()
	self:onGameOver()
end

function GameMode:onExit() end

-- DAS functions

function GameMode:startRightDAS()
	self.move = "right"
	self.das = { direction = "right", frames = 0 }
	if self:getDasLimit() == 0 then
		self:continueDAS()
	end
end

function GameMode:startLeftDAS()
	self.move = "left"
	self.das = { direction = "left", frames = 0 }
	if self:getDasLimit() == 0 then
		self:continueDAS()
	end
end

function GameMode:continueDAS()
	local das_frames = self.das.frames + 1
	if das_frames >= self:getDasLimit() then
		if self.das.direction == "left" then
			self.move = (self:getARR() == 0 and "speed" or "") .. "left"
			self.das.frames = self:getDasLimit() - self:getARR()
		elseif self.das.direction == "right" then
			self.move = (self:getARR() == 0 and "speed" or "") .. "right"
			self.das.frames = self:getDasLimit() - self:getARR()
		end
	else
		self.move = "none"
		self.das.frames = das_frames
	end
end

function GameMode:stopDAS()
	self.move = "none"
	self.das = { direction = "none", frames = -1 }
end

function GameMode:chargeDAS(inputs)
	if config.gamesettings.das_last_key == 2 then
		if inputs["right"] == true and self.das.direction ~= "right" and not self.prev_inputs["right"] then
			self:startRightDAS()
		elseif inputs["left"] == true and self.das.direction ~= "left" and not self.prev_inputs["left"] then
			self:startLeftDAS()
		elseif inputs[self.das.direction] == true then
			self:continueDAS()
		else
			self:stopDAS()
		end
	else  -- default behaviour, das first key pressed
		if inputs[self.das.direction] == true then
			self:continueDAS()
		elseif inputs["right"] == true then
			self:startRightDAS()
		elseif inputs["left"] == true then
			self:startLeftDAS()
		else
			self:stopDAS()
		end
	end
end

function GameMode:dasCut()
	self.das.frames = math.max(
		self.das.frames - self:getDasCutDelay(),
		-(self:getDasCutDelay() + 1)
	)
end

function GameMode:areCancel(inputs, ruleset)
	if ruleset.are_cancel and self.piece_hard_dropped and
	not self.prev_inputs.up and
	strTrueValues(inputs) ~= "" then
		self.lcd = 0
		self.are = 0
	end
end

function GameMode:processDelays(inputs, ruleset, drop_speed)
	if self.ready_frames == 100 then
		playedReadySE = false
		playedGoSE = false
	end
	if self.ready_frames > 0 then
		if not self.prev_inputs["up"] and inputs["up"] and self.enable_hard_drop then
			self.buffer_hard_drop = true
		end
		if not self.prev_inputs["down"] and inputs["down"] then
			self.buffer_soft_drop = true
		end
		if not playedReadySE then
			playedReadySE = true
			playSEOnce("ready")
		end
		self.ready_frames = self.ready_frames - 1
		if self.ready_frames == 50 and not playedGoSE then
			playedGoSE = true
			playSEOnce("go")
		end
		if self.ready_frames == 0 then
			self:initializeOrHold(inputs, ruleset)
		end
	elseif self.lcd > 0 then
		if not self.prev_inputs["up"] and inputs["up"] and self.enable_hard_drop then
			self.buffer_hard_drop = true
		end
		if not self.prev_inputs["down"] and inputs["down"] then
			self.buffer_soft_drop = true
		end
		self.lcd = self.lcd - 1
		self:areCancel(inputs, ruleset)
		if self.lcd == 0 then
			local cleared_row_count = self.grid:getClearedRowCount()
			self.grid:clearClearedRows()
			self:afterLineClear(cleared_row_count)
			playSE("fall")
			if self.are == 0 then
				self:initializeOrHold(inputs, ruleset)
			end
		end
	elseif self.are > 0 then
		if not self.prev_inputs["up"] and inputs["up"] and self.enable_hard_drop then
			self.buffer_hard_drop = true
		end
		if not self.prev_inputs["down"] and inputs["down"] then
			self.buffer_soft_drop = true
		end
		self.are = self.are - 1
		self:areCancel(inputs, ruleset)
		if self.are == 0 then
			self:initializeOrHold(inputs, ruleset)
		end
	end
end

function GameMode:initializeOrHold(inputs, ruleset)
	if (
		self.frames == 0 or (ruleset.are and self:getARE() ~= 0) and self.ihs or false
	) and self.enable_hold and inputs["hold"] == true then
		self:hold(inputs, ruleset, true)
	else
		self:initializeNextPiece(inputs, ruleset, self.next_queue[1])
	end
	self:onPieceEnter()
	if not self.grid:canPlacePiece(self.piece) then
		self.game_over = true
	end
end

function GameMode:hold(inputs, ruleset, ihs)
	local data = copy(self.hold_queue)
	if self.piece == nil then
		self.hold_queue = self.next_queue[1]
		table.remove(self.next_queue, 1)
		table.insert(self.next_queue, self:getNextPiece(ruleset))
	else
		self.hold_queue = {
			skin = self.piece.skin,
			shape = self.piece.shape,
			orientation = ruleset:getDefaultOrientation(),
		}
	end
	if data == nil then
		self:initializeNextPiece(inputs, ruleset, self.next_queue[1])
	else
		self:initializeNextPiece(inputs, ruleset, data, false)
	end
	self.held = true
	if ihs then playSE("ihs")
	else playSE("hold") end
	self:onHold()
end

function GameMode:initializeNextPiece(inputs, ruleset, piece_data, generate_next_piece)
	self.piece_hard_dropped = false
	local gravity = self:getGravity()
	self.piece = ruleset:initializePiece(
		inputs, piece_data, self.grid, gravity,
		self.prev_inputs, self.move,
		self:getLockDelay(), self:getDropSpeed(),
		self.lock_drop, self.lock_hard_drop, self.big_mode,
		(
			self.frames == 0 or (ruleset.are and self:getARE() ~= 0)
		) and self.irs or false,
		self.buffer_hard_drop, self.buffer_soft_drop,
		self.lock_on_hard_drop, self.lock_on_soft_drop
	)
	if self.piece:isDropBlocked(self.grid) and
	   self.grid:canPlacePiece(self.piece) then
		playSE("bottom")
	end
	if self.buffer_hard_drop then
		self.buffer_hard_drop = false
		self:onHardDrop(self.piece.position.y - (
			self.big_mode and
			ruleset.big_spawn_positions[self.piece.shape].y or
			ruleset.spawn_positions[self.piece.shape].y)
		)
	end
	if self.buffer_soft_drop then
		self.buffer_soft_drop = false
	end
	if self.lock_drop or (
		not ruleset.are or self:getARE() == 0
	) then
		self.drop_locked = true
	end
	if self.lock_hard_drop or (
		not ruleset.are or self:getARE() == 0
	) then
		self.hard_drop_locked = true
	end
	if generate_next_piece == nil then
		table.remove(self.next_queue, 1)
		table.insert(self.next_queue, self:getNextPiece(ruleset))
	end
	self:playNextSound(ruleset)
end

function GameMode:playNextSound(ruleset)
	playSE("blocks", ruleset.next_sounds[self.next_queue[1].shape])
end

function GameMode:getHighScoreData()
	return {
		score = self.score
	}
end

function GameMode:animation(x, y, skin, colour)
	return {
		1, 1, 1,
		-0.25 + 1.25 * (self.lcd / self:getLineClearDelay()),
		skin, colour,
		48 + x * 16, y * 16
	}
end

function GameMode:drawLineClearAnimation()
	-- animation function
	-- params: block x, y, skin, colour
	-- returns: table with RGBA, skin, colour, x, y
	
	-- Fadeout (default)
	--[[
	function animation(x, y, skin, colour)
		return {
			1, 1, 1,
			-0.25 + 1.25 * (self.lcd / self:getLineClearDelay()),
			skin, colour,
			48 + x * 16, y * 16
		}
	end
	--]]

	-- Flash
	--[[
	function animation(x, y, skin, colour)
		return {
			1, 1, 1,
			self.lcd % 6 < 3 and 1 or 0.25,
			skin, colour,
			48 + x * 16, y * 16
		}
	end
	--]]

	-- TGM1 pop-out
	--[[
	function animation(x, y, skin, colour)
		local p = 0.5
		local l = (
			(self:getLineClearDelay() - self.lcd) / self:getLineClearDelay()
		)
		local dx = l * (x - (1 + self.grid.width) / 2)
		local dy = l * (y - (1 + self.grid.height) / 2)
		return {
			1, 1, 1, 1, skin, colour,
			48 + (x + dx) * 16,
			(y + dy) * 16 + (464 / (p - 1)) * l * (p - l)
		}
	end
	--]]

	for y, row in pairs(self.cleared_block_table) do
		for x, block in pairs(row) do
			local animation_table = self:animation(x, y, block.skin, block.colour)
			love.graphics.setColor(
				animation_table[1], animation_table[2],
				animation_table[3], animation_table[4]
			)
			love.graphics.draw(
				blocks[animation_table[5]][animation_table[6]],
				animation_table[7], animation_table[8]
			)
		end
	end
end

function GameMode:drawPiece()
	if self.piece ~= nil then
		local b = (
			self.classic_lock and
			(
				self.piece:isDropBlocked(self.grid) and
				1 - self.piece.gravity or 1
			) or
			1 - (self.piece.lock_delay / self:getLockDelay())
		)
		self.piece:draw(1, 0.25 + 0.75 * b, self.grid)
	end
end

function GameMode:drawGhostPiece(ruleset)
	if self.piece == nil then return end
	local ghost_piece = self.piece:withOffset({x=0, y=0})
	ghost_piece.ghost = true
	ghost_piece:dropToBottom(self.grid)
	ghost_piece:draw(0.5)
end

function GameMode:drawNextQueue(ruleset)
	local colourscheme = ({ruleset.colourscheme, ColourSchemes.Arika, ColourSchemes.TTC})[config.gamesettings.piece_colour]
	function drawPiece(piece, skin, offsets, pos_x, pos_y)
		for index, offset in pairs(offsets) do
			local x = offset.x + ruleset:getDrawOffset(piece, rotation).x + ruleset.spawn_positions[piece].x
			local y = offset.y + ruleset:getDrawOffset(piece, rotation).y + 4.7
			love.graphics.draw(blocks[skin][colourscheme[piece]], pos_x+x*16, pos_y+y*16)
		end
	end
	for i = 1, self.next_queue_length do
		self:setNextOpacity(i)
		local next_piece = self.next_queue[i].shape
		local skin = self.next_queue[i].skin
		local rotation = self.next_queue[i].orientation
		if config.side_next then -- next at side
			drawPiece(next_piece, skin, ruleset.block_offsets[next_piece][rotation], 192, -16+i*48)
		else -- next at top
			drawPiece(next_piece, skin, ruleset.block_offsets[next_piece][rotation], -16+i*80, -32)
		end
	end
	if self.hold_queue ~= nil and self.enable_hold then
		self:setHoldOpacity()
		drawPiece(
			self.hold_queue.shape, 
			self.hold_queue.skin, 
			ruleset.block_offsets[self.hold_queue.shape][self.hold_queue.orientation],
			-16, -32
		)
	end
	return false
end

function GameMode:setNextOpacity(i)
	love.graphics.setColor(1, 1, 1, 1)
end

function GameMode:setHoldOpacity()
	local colour = self.held and 0.6 or 1
	love.graphics.setColor(colour, colour, colour, 1)
end

function GameMode:getBackground()
	return 0
end

function GameMode:getHighscoreData()
	return {}
end

function GameMode:drawGrid()
	self.grid:draw()
end

function GameMode:drawScoringInfo()
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setFont(font_3x5_2)

	if config["side_next"] then
		love.graphics.printf("NEXT", 240, 72, 40, "left")
	else
		love.graphics.printf("NEXT", 64, 40, 40, "left")
	end

	love.graphics.print(
		self.das.direction .. " " ..
		self.das.frames .. " " ..
		strTrueValues(self.prev_inputs) ..
		self.drop_bonus
	)

	love.graphics.setFont(font_8x11)
	love.graphics.printf(formatTime(self.frames), 64, 420, 160, "center")
end

function GameMode:drawSectionTimes(current_section)
	local section_x = 530

	for section, time in pairs(self.section_times) do
		if section > 0 then
			love.graphics.printf(formatTime(time), section_x, 40 + 20 * section, 90, "left")
		end
	end

	love.graphics.printf(formatTime(self.frames - self.section_start_time), section_x, 40 + 20 * current_section, 90, "left")
end

function GameMode:sectionColourFunction(section)
	return { 1, 1, 1, 1 }
end

function GameMode:drawSectionTimesWithSecondary(current_section, section_limit)
	section_limit = section_limit or math.huge
	local section_x = 530
	local section_secondary_x = 440

	for section, time in pairs(self.section_times) do
		if section > 0 then
			love.graphics.printf(formatTime(time), section_x, 40 + 20 * section, 90, "left")
		end
	end

	for section, time in pairs(self.secondary_section_times) do
		love.graphics.setColor(self:sectionColourFunction(section))
		if section > 0 then
			love.graphics.printf(formatTime(time), section_secondary_x, 40 + 20 * section, 90, "left")
		end
		love.graphics.setColor(1, 1, 1, 1)
	end

	local current_x
	if table.getn(self.section_times) < table.getn(self.secondary_section_times) then
		current_x = section_x
	else
		current_x = section_secondary_x
	end

	if current_section <= section_limit then
		love.graphics.printf(formatTime(self.frames - self.section_start_time), current_x, 40 + 20 * current_section, 90, "left")
	end
end

function GameMode:drawSectionTimesWithSplits(current_section, section_limit)
	section_limit = section_limit or math.huge
	
	local section_x = 440
	local split_x = 530

	local split_time = 0

	for section, time in pairs(self.section_times) do
		if section > 0 then
			love.graphics.setColor(self:sectionColourFunction(section))
			love.graphics.printf(formatTime(time), section_x, 40 + 20 * section, 90, "left")
			love.graphics.setColor(1, 1, 1, 1)
			split_time = split_time + time
			love.graphics.printf(formatTime(split_time), split_x, 40 + 20 * section, 90, "left")
		end
	end
	
	if (current_section <= section_limit) then
		love.graphics.printf(formatTime(self.frames - self.section_start_time), section_x, 40 + 20 * current_section, 90, "left")
		love.graphics.printf(formatTime(self.frames), split_x, 40 + 20 * current_section, 90, "left")
	end
end

function GameMode:drawCustom() end

return GameMode
