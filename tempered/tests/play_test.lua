local game = require("game")
local setup = io.open(os.getenv("TC_SETUP"), "rb"):read("a")
local steps = dofile(os.getenv("TC_STEPS"))

-- TC_NEW_GAME is where the new game state is saved. With TC_NEW_GAME_SAVE,
-- play a new game and save its initial state there during `game.run`.
local newGame = os.getenv("TC_NEW_GAME")

game.run(function()
	if os.getenv("TC_NEW_GAME_SAVE") then
		game.newGame()
		return game.saveState(newGame)
	end
	game.loadState(newGame)
	game.runScript(setup)
	if os.getenv("TC_SAVE") then
		return game.save(os.getenv("TC_SAVE"))
	end
	for i, step in ipairs(steps) do
		local desc = "step " .. i
		if step.walk then
			for dir, n in step.walk:gmatch("(%u+) (%d+)") do
				game.walk(dir, tonumber(n), desc .. " " .. dir .. " " .. n)
			end
		elseif step.face then
			game.face(step.face, desc)
		elseif step.press and step.until_text then
			game.pressUntil(step.press, desc .. " until " .. step.until_text, function()
				return game.screenHas(step.until_text)
			end)
		elseif step.press then
			game.press(step.press, desc .. " " .. step.press)
		end
	end
	game.wait(30)
	game.screenshot("screenshot")
end)
