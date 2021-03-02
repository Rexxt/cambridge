require 'funcs'

local GameMode = require 'tetris.modes.gamemode'
local Piece = require 'tetris.components.piece'

local History6RollsRandomizer = require 'tetris.randomizers.history_6rolls'

local MarathonA2Game = GameMode:extend()

MarathonA2Game.name = "Big A2"
MarathonA2Game.hash = "BigA2"
MarathonA2Game.tagline = "The points don't matter! Can you reach the invisible roll? Big mode too!"




function MarathonA2Game:new()
	self.super:new()
	self.big_mode = true
	self.roll_frames = 0
	self.combo = 1

	self.grade = 0
	self.grade_points = 0
	self.grade_point_decay_counter = 0
	
	self.randomizer = History6RollsRandomizer()

	self.lock_drop = false
	self.lock_hard_drop = false
	self.enable_hold = false
	self.next_queue_length = 1
end

function MarathonA2Game:getARE()
		if self.level < 700 then return 27
	elseif self.level < 800 then return 18
	else return 14 end
end

function MarathonA2Game:getLineARE()
		if self.level < 600 then return 27
	elseif self.level < 700 then return 18
	elseif self.level < 800 then return 14
	else return 8 end
end

function MarathonA2Game:getDasLimit()
		if self.level < 500 then return 15
	elseif self.level < 900 then return 9
	else return 7 end
end

function MarathonA2Game:getLineClearDelay()
		if self.level < 500 then return 40
	elseif self.level < 600 then return 25
	elseif self.level < 700 then return 16
	elseif self.level < 800 then return 12
	else return 6 end
end

function MarathonA2Game:getLockDelay()
		if self.level < 900 then return 30
	else return 17 end
end

function MarathonA2Game:getGravity()
		if (self.level < 30)  then return 4/256
	elseif (self.level < 35)  then return 6/256
	elseif (self.level < 40)  then return 8/256
	elseif (self.level < 50)  then return 10/256
	elseif (self.level < 60)  then return 12/256
	elseif (self.level < 70)  then return 16/256
	elseif (self.level < 80)  then return 32/256
	elseif (self.level < 90)  then return 48/256
	elseif (self.level < 100) then return 64/256
	elseif (self.level < 120) then return 80/256
	elseif (self.level < 140) then return 96/256
	elseif (self.level < 160) then return 112/256
	elseif (self.level < 170) then return 128/256
	elseif (self.level < 200) then return 144/256
	elseif (self.level < 220) then return 4/256
	elseif (self.level < 230) then return 32/256
	elseif (self.level < 233) then return 64/256
	elseif (self.level < 236) then return 96/256
	elseif (self.level < 239) then return 128/256
	elseif (self.level < 243) then return 160/256
	elseif (self.level < 247) then return 192/256
	elseif (self.level < 251) then return 224/256
	elseif (self.level < 300) then return 1
	elseif (self.level < 330) then return 2
	elseif (self.level < 360) then return 3
	elseif (self.level < 400) then return 4
	elseif (self.level < 420) then return 5
	elseif (self.level < 450) then return 4
	elseif (self.level < 500) then return 3
	else return 20
	end
end

function MarathonA2Game:advanceOneFrame()
	if self.clear then
		self.roll_frames = self.roll_frames + 1
		if self.roll_frames < 0 then return false end
		if self.roll_frames > 3694 then
			self.completed = true
		end
	elseif self.ready_frames == 0 then
		self.frames = self.frames + 1
	end
	return true
end

function MarathonA2Game:onPieceEnter()
	if (self.level % 100 ~= 99 and self.level ~= 998) and not self.clear and self.frames ~= 0 then
		self.level = self.level + 1
	end
end

function MarathonA2Game:onLineClear(cleared_row_count)
	cleared_row_count = cleared_row_count / 2
	self.level = math.min(self.level + cleared_row_count, 999)
	if self.level == 999 and not self.clear then
		self.clear = true
		self.grid:clear()
		self.roll_frames = -150
	end
	self.lock_drop = self.level >= 900
	self.lock_hard_drop = self.level >= 900
end

function MarathonA2Game:updateScore(level, drop_bonus, cleared_lines)
	if not self.clear then
		cleared_lines = cleared_lines / 2
		self:updateGrade(cleared_lines)
		if self.grid:checkForBravo(cleared_lines) then self.bravo = 4 else self.bravo = 1 end
		if cleared_lines > 0 then
			self.combo = self.combo + (cleared_lines - 1) * 2
			self.score = self.score + (
				(math.ceil((level + cleared_lines) / 4) + drop_bonus) *
				cleared_lines * self.combo * self.bravo
			)
		else
			self.combo = 1
		end
		self.drop_bonus = 0
	end
end

local grade_point_bonuses = {
	{10, 20, 40, 50},
	{10, 20, 30, 40},
	{10, 20, 30, 40},
	{10, 15, 30, 40},
	{10, 15, 20, 40},
	{5, 15, 20, 30},
	{5, 10, 20, 30},
	{5, 10, 15, 30},
	{5, 10, 15, 30},
	{5, 10, 15, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
	{2, 12, 13, 30},
}

local grade_point_decays = {
	125, 80, 80, 50, 45, 45, 45,
	40, 40, 40, 40, 40, 30, 30, 30,
	20, 20, 20, 20, 20,
	15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
	10, 10
}

local combo_multipliers = {
	{1.0, 1.0, 1.0, 1.0},
	{1.2, 1.4, 1.5, 1.0},
	{1.2, 1.5, 1.8, 1.0},
	{1.4, 1.6, 2.0, 1.0},
	{1.4, 1.7, 2.2, 1.0},
	{1.4, 1.8, 2.3, 1.0},
	{1.4, 1.9, 2.4, 1.0},
	{1.5, 2.0, 2.5, 1.0},
	{1.5, 2.1, 2.6, 1.0},
	{2.0, 2.5, 3.0, 1.0},
}

local grade_conversion = {
	[0] = 0,
	1, 2, 3, 4, 5, 5, 6, 6, 7, 7,
	7, 8, 8, 8, 9, 9, 9, 10, 11, 12,
	12, 12, 13, 13, 14, 14, 15, 15, 16, 16,
	17
}

function MarathonA2Game:updateGrade(cleared_lines)
	if self.clear then return end
	if cleared_lines == 0 then
		self.grade_point_decay_counter = self.grade_point_decay_counter + 1
		if self.grade_point_decay_counter >= grade_point_decays[self.grade + 1] then
			self.grade_point_decay_counter = 0
			self.grade_points = math.max(0, self.grade_points - 1)
		end
	else
		self.grade_points = self.grade_points + (
			math.ceil(
				grade_point_bonuses[self.grade + 1][cleared_lines] *
				combo_multipliers[math.min(self.combo, 10)][cleared_lines]
			) * (1 + math.floor(self.level / 250))
		)
		if self.grade_points >= 100 and self.grade < 31 then
			self.grade_points = 0
			self.grade = self.grade + 1
		end
	end
end

function MarathonA2Game:getLetterGrade()
	local grade = grade_conversion[self.grade]
	if grade < 9 then
		return tostring(9 - grade)
	elseif grade < 18 then
		return "S" .. tostring(grade - 8)
	end
end

MarathonA2Game.rollOpacityFunction = function(age)
	if age < 240 then return 1
	elseif age > 300 then return 0
	else return 1 - (age - 240) / 60 end
end

function MarathonA2Game:drawGrid(ruleset)
	if self.clear and not (self.completed or self.game_over) then
		self.grid:drawInvisible(self.rollOpacityFunction, nil, false)
	else
		self.grid:draw()
		if self.piece ~= nil and self.level < 100 then
			self:drawGhostPiece(ruleset)
		end
	end
end

function MarathonA2Game:drawScoringInfo()
	love.graphics.setColor(1, 1, 1, 1)

	love.graphics.setFont(font_3x5_2)
	love.graphics.print(
		self.das.direction .. " " ..
		self.das.frames .. " " ..
		strTrueValues(self.prev_inputs)
	)
	love.graphics.printf("NEXT", 64, 40, 40, "left")
	love.graphics.printf("GRADE", 240, 120, 40, "left")
	love.graphics.printf("SCORE", 240, 200, 40, "left")
	love.graphics.printf("LEVEL", 240, 320, 40, "left")

	love.graphics.setFont(font_3x5_3)
	if self.roll_frames > 3694 then love.graphics.setColor(1, 0.5, 0, 1)
	elseif self.clear then love.graphics.setColor(0, 1, 0, 1) end
	love.graphics.printf(self:getLetterGrade(), 240, 140, 90, "left")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.printf(self.score, 240, 220, 90, "left")
	love.graphics.printf(self.level, 240, 340, 40, "right")
	love.graphics.printf(self:getSectionEndLevel(), 240, 370, 40, "right")

	love.graphics.setFont(font_8x11)
	love.graphics.printf(formatTime(self.frames), 64, 420, 160, "center")
end

function MarathonA2Game:getHighscoreData()
	return {
		grade = grade_conversion[self.grade],
		score = self.score,
		level = self.level,
		frames = self.frames,
	}
end

function MarathonA2Game:getSectionEndLevel()
	if self.level >= 900 then return 999
	else return math.floor(self.level / 100 + 1) * 100 end
end

function MarathonA2Game:getBackground()
	return math.floor(self.level / 100)
end

return MarathonA2Game
