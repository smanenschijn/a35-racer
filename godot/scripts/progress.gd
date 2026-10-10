class_name Progress
## Campaign progress, car unlocks, lifetime statistics and the highscores per stage, saved in
## user:// (port of src/core/Progress.ts and src/core/Highscores.ts).

const FILE := "user://progress.cfg"
const MAX_SCORES := 5
## Cars you start with; the others unlock by clearing a stage.
const UNLOCKS := {"rx": 0, "golv": 0, "corso": 0, "civik": 1, "volvi": 2, "spacewagen": 3, "calibro": 4, "supremo": 5}
const EMPTY_STATS := {"races": 0, "wins": 0, "stagesCleared": 0, "takedowns": 0, "nearMisses": 0, "topSpeed": 0.0,
	"biggestHit": 0.0, "busted": 0, "wrecks": 0, "km": 0.0}


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	return cfg


static func cleared_stages() -> Array:
	return _cfg().get_value("progress", "cleared", [])


static func lifetime() -> Dictionary:
	var s: Dictionary = EMPTY_STATS.duplicate()
	s.merge(_cfg().get_value("progress", "stats", {}), true)
	return s


static func is_unlocked(car_id: String) -> bool:
	var need: int = UNLOCKS.get(car_id, 0)
	return need == 0 or cleared_stages().has(need)


static func _unlocked(cleared: Array) -> Array:
	var out := []
	for c in UNLOCKS:
		if UNLOCKS[c] == 0 or cleared.has(UNLOCKS[c]):
			out.append(c)
	return out


## Record a race; returns the car ids that just got unlocked.
static func record_race(stage_id: int, position: int, qualified: bool, takedowns: int, r: Dictionary) -> Array:
	var cfg := _cfg()
	var cleared: Array = cfg.get_value("progress", "cleared", [])
	var before := _unlocked(cleared)
	var st := lifetime()
	st.races += 1
	if position == 1 and qualified:
		st.wins += 1
	if qualified and not cleared.has(stage_id):
		cleared.append(stage_id)
		st.stagesCleared = cleared.size()
	st.takedowns += takedowns
	st.nearMisses += r.nearMisses
	st.topSpeed = maxf(st.topSpeed, r.topSpeed)
	st.biggestHit = maxf(st.biggestHit, r.biggestHit)
	st.busted += r.busted
	st.wrecks += r.wrecks
	st.km += r.distance / 1000.0
	cfg.set_value("progress", "cleared", cleared)
	cfg.set_value("progress", "stats", st)
	cfg.save(FILE)
	var out := []
	for c in _unlocked(cleared):
		if not before.has(c):
			out.append(c)
	return out


## Highscore table per stage (stage 5 keeps the web version's key).
static func score_key(stage_id: int) -> String:
	return "hengelo-enschede" if stage_id == 5 else "etappe-%d" % stage_id


static func get_scores(stage: String) -> Array:
	return _cfg().get_value("scores", stage, [])


## Would this time make the top list?
static func qualifies(stage: String, time: float) -> bool:
	var list := get_scores(stage)
	return list.size() < MAX_SCORES or time < list[list.size() - 1].time


## Adds a score {initials, time, takedowns, car, date} and returns its rank (1-based), or 0.
static func add_score(stage: String, score: Dictionary) -> int:
	var cfg := _cfg()
	var list: Array = cfg.get_value("scores", stage, [])
	list.append(score)
	list.sort_custom(func(a, b): return a.time < b.time)
	list = list.slice(0, MAX_SCORES)
	cfg.set_value("scores", stage, list)
	cfg.save(FILE)
	return list.find(score) + 1


static func last_initials() -> String:
	return _cfg().get_value("scores", "initials", "AAA")


static func remember_initials(i: String) -> void:
	var cfg := _cfg()
	cfg.set_value("scores", "initials", i)
	cfg.save(FILE)
