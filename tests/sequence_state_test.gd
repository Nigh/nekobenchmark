extends SceneTree

const Osu := preload("res://scripts/osu_state.gd")
const Sphere := preload("res://scripts/sphere_state.gd")
const SphereAimScr := preload("res://scripts/sphere_aim.gd")
const Scores := preload("res://scripts/score_store.gd")


func _init() -> void:
	_test_osu()
	_test_sphere()
	_test_sphere_separation()
	var result: Dictionary = Scores.statistics([100_000, 200_000, 300_000, 400_000, 500_000])
	assert(is_equal_approx(result.median, 300.0))
	print("sequence_state_test: PASS")
	quit()


func _test_sphere_separation() -> void:
	var min_sep: float = SphereAimScr.SPHERE_RADIUS * 2.0 + 0.45
	assert(is_equal_approx(SphereAimScr.MIN_SEPARATION, min_sep))
	assert(is_equal_approx(SphereAimScr.HIT_RADIUS_SCALE, 1.1))
	assert(SphereAimScr.MIN_SEPARATION > SphereAimScr.SPHERE_RADIUS * 2.0)


func _test_osu() -> void:
	var state = Osu.new()
	state.begin_round()
	assert(state.stage == Osu.Stage.ACTIVE and state.expected == 1)
	state.miss()
	assert(state.stage == Osu.Stage.INVALID and state.reactions_us.is_empty())

	state.reset()
	state.begin_round()
	state.hit_next(1_000_000)
	assert(state.start_us == 1_000_000 and state.expected == 2)
	for _i in Osu.TARGETS - 1:
		state.hit_next(state.start_us + 100_000 * state.expected)
	assert(state.stage == Osu.Stage.NEXT)
	assert(state.reactions_us == [600_000])

	state.begin_round()
	for trial_extra in 4:
		for _i in Osu.TARGETS:
			state.hit_next(10_000_000 + trial_extra * 1_000_000 + _i * 10_000)
		if trial_extra < 3:
			assert(state.stage == Osu.Stage.NEXT)
			state.begin_round()
	assert(state.stage == Osu.Stage.SUMMARY and state.reactions_us.size() == Osu.TRIALS)


func _test_sphere() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var state = Sphere.new()
	state.start_wait(100, rng)
	assert(state.stage == Sphere.Stage.WAITING)
	state.try_fire(200)
	assert(state.stage == Sphere.Stage.INVALID and state.reactions_us.is_empty())

	state.reset()
	state.start_wait(100, rng)
	assert(state.advance(state.deadline_us))
	assert(state.stage == Sphere.Stage.AIMING)
	assert(state.advance(state.target_frame_us + Sphere.TIMEOUT_US + 1))
	assert(state.stage == Sphere.Stage.INVALID)

	state.reset()
	state.start_wait(100, rng)
	state.advance(state.deadline_us)
	assert(state.try_fire(state.target_frame_us + 10_000))
	assert(not state.try_fire(state.target_frame_us + 20_000))
	assert(state.try_fire(state.target_frame_us + 10_000 + Sphere.FIRE_COOLDOWN_US))

	state.reset()
	state.start_wait(100, rng)
	state.advance(state.deadline_us)
	var appear: int = state.target_frame_us
	for index in Sphere.TARGETS:
		assert(state.try_fire(appear + (index + 1) * Sphere.FIRE_COOLDOWN_US))
		state.register_hit(appear + (index + 1) * Sphere.FIRE_COOLDOWN_US)
	assert(state.stage == Sphere.Stage.NEXT)
	assert(state.reactions_us == [Sphere.TARGETS * Sphere.FIRE_COOLDOWN_US])
