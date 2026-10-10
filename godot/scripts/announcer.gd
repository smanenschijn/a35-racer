class_name Announcer
extends RefCounted
## Race announcer through the system's text-to-speech with a Dutch voice (when available).
## Lines are short and rate-limited so it never talks over itself. Port of src/core/Announcer.ts.

var muted := false
var _voice := ""
var _last := -9999


func _init() -> void:
	# (No speech-dispatcher on most Linux boxes: skip there.)
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false) or OS.has_feature("linuxbsd"):
		return
	var voices := DisplayServer.tts_get_voices_for_language("nl")
	if not voices.is_empty():
		_voice = voices[0]


## priority lines interrupt whatever is being said.
func say(text: String, priority := false, rate := 1.15, pitch := 0.9) -> void:
	if _voice == "" or muted:
		return
	var now := Time.get_ticks_msec()
	if not priority and (DisplayServer.tts_is_speaking() or now - _last < 1200):
		return
	DisplayServer.tts_speak(text, _voice, 100, pitch, rate, 0, priority)
	_last = now


func stop() -> void:
	if _voice != "":
		DisplayServer.tts_stop()
