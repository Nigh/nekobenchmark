extends SceneTree

const Reaction := preload("res://scripts/reaction_state.gd")
const Scores := preload("res://scripts/score_store.gd")


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var state = Reaction.new()
	state.start_wait(100, rng)
	state.respond(200)
	assert(state.stage == Reaction.Stage.INVALID and state.reactions_us.is_empty())

	state.reset()
	state.start_wait(100, rng)
	assert(state.advance(state.deadline_us))
	state.respond(state.target_frame_us + 275_000)
	assert(state.stage == Reaction.Stage.NEXT and state.reactions_us == [275_000])

	state.reset()
	state.start_wait(100, rng)
	state.advance(state.deadline_us)
	state.advance(state.target_frame_us + Reaction.TIMEOUT_US + 1)
	assert(state.stage == Reaction.Stage.INVALID and state.reactions_us.is_empty())

	state.reset()
	for trial in Reaction.TRIALS:
		state.start_wait(trial * 2_000_000, rng)
		state.advance(state.deadline_us)
		state.respond(state.target_frame_us + 200_000)
	assert(state.stage == Reaction.Stage.SUMMARY and state.reactions_us.size() == Reaction.TRIALS)

	state.reset()
	state.start_wait(100, rng)
	state.advance(state.deadline_us)
	assert(is_equal_approx(state.target_progress(state.target_frame_us), 0.0))
	assert(is_equal_approx(state.target_progress(state.target_frame_us + Reaction.TIMEOUT_US), 1.0))

	var result: Dictionary = Scores.statistics([100_000, 200_000, 300_000, 400_000, 500_000])
	assert(is_equal_approx(result.median, 300.0))
	assert(Scores.is_new_best(0.0, 300.0))
	assert(Scores.is_new_best(400.0, 300.0))
	assert(not Scores.is_new_best(200.0, 300.0))
	print("reaction_state_test: PASS")
	quit()
