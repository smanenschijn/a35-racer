class_name EventBus
extends RefCounted
## Tiny typed-by-convention event bus (port of src/core/Events.ts).
## impact {x, y, z, strength, kind: "car"|"rail", a, b}, scrape {x, y, z, intensity, vehicle, nx, nz},
## wreck {victim, attacker}, ram {vehicle, dir}, nearMiss {vehicle, other}, message {text, color, big},
## flash {kmh}, busted {penalty}

var _handlers := {}


func on(type: String, fn: Callable) -> void:
	if not _handlers.has(type):
		_handlers[type] = []
	_handlers[type].append(fn)


func emit(type: String, payload: Dictionary) -> void:
	for fn in _handlers.get(type, []):
		fn.call(payload)
