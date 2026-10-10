class_name Config
## Central tuning values, cars, AI personalities, traffic and the road cross-section (port of src/config.ts).
## Coordinates are the same as in the web version: Y up, a heading of 0 faces +Z.

static var T := {
	# Handling
	"engineAccel": 11.0, # m/s² at standstill
	"brakeDecel": 18.0,
	"dragCoef": 0.0016, # aerodynamic drag factor (per m)
	"rollingDecel": 0.6,
	"grip": 7.5, # lateral velocity damping (1/s)
	"handbrakeGrip": 2.1, # less of a cliff from normal grip, so a drift can be dosed
	"driftGripFactor": 0.65, # grip multiplier while already sliding (keeps drifts alive)
	"steerRateLow": 1.4, # max yaw rate (rad/s) at low speed
	"steerRateHigh": 0.52, # max yaw rate (rad/s) at top speed
	"yawResponse": 4.0, # how fast yaw rate follows steering (1/s)
	"handbrakeYawBoost": 1.55,
	"driftSpeedReturn": 0.1, # share of the bled-off slide that turns into forward speed

	# Nitro
	"nitroAccel": 9.0,
	"nitroTopSpeedFactor": 1.22,
	"nitroDrain": 0.28, # per second
	"nitroFillPerDamage": 0.006,
	"nitroFillTakedown": 0.35,
	"nitroFillNearMiss": 0.08,
	"nitroFillDriftPerSec": 0.11,
	"driftNitroDelay": 0.6, # seconds a drift must last before it fills nitro

	# Ram attack
	"ramSideSpeed": 12.0, # m/s lateral velocity during ram
	"ramDuration": 0.32,
	"ramCooldown": 2.0,
	"ramMassFactor": 2.5, # rammer counts as this much heavier during a hit
	"aggressorRecoil": 0.65, # share of the impulse the aggressor does NOT feel (keeps its line)
	"ramDamageFactor": 1.4,
	"ramShoveSpeed": 11.0, # m/s sideways a rammed car gets launched with
	"ramDamage": 30.0, # damage points a landed ram deals to the victim

	# Collisions & damage
	"carRestitution": 0.1,
	"carFriction": 0.35,
	"railRestitution": 0.06,
	"railGlide": 8.0, # how fast the car straightens along a rail it touches (1/s)
	"railFriction": 0.25, # fraction of tangential speed lost per hard hit
	"damagePerImpulse": 0.0008, # damage points per N·s of impulse
	"railDamagePerSpeed": 1.8, # damage points per m/s of normal impact speed
	"railScrapeDamage": 0.03, # damage points per m/s per second while scraping
	"takedownWindow": 2.0, # seconds a hit counts as cause for a rail wreck
	"takedownRailBonus": 1.2, # rail damage multiplier when recently rammed by someone
	"playerDamageFactor": 0.7,
	"aiDamageFactor": 1.0,
	"aiSingleDamage": 0.35, # rivals on the two-lane N35 (their own pile-ups only)
	"stunTime": 0.45, # seconds of reduced control after a hard hit
	"wreckTotal": 45.0, # average damage over all zones that also means total loss

	# AI
	"aiCornerLatAccel": 13.0,
	"aiAggression": 1.0,
	"rubberBandBehind": 1.07, # power factor for a rival far behind the player
	"rubberBandAhead": 0.82, # power factor for a rival far ahead of the player (eases in over rubberBandRange)
	"rubberBandRange": 420.0, # metres ahead over which a rival backs off to rubberBandAhead
	"playerCatchUp": 0.1, # extra power for the player when far behind the leader
	"draftBonus": 0.07, # extra power while tucked in behind another car (slipstream)
	"draftCharge": 1.2, # seconds in the slipstream before the slingshot is ready
	"slingshotBonus": 0.16, # extra power when you pull out of a charged slipstream
	"slingshotTime": 1.8, # seconds the slingshot lasts
	"bulletScale": 0.3, # speed of the world in bullet time
	"bulletSeconds": 4.0, # real seconds a full meter lasts
	"bulletRecharge": 30.0, # real seconds to refill an empty meter

	# Traffic & police
	"trafficCount": 44,
	"oncomingCount": 18,
	"heatDecayDelay": 6.0, # seconds without trouble before the wanted level starts dropping
	"heatDecay": 0.09, # stars per second
	"speedCameraKmh": 140.0,
	"bustSeconds": 1.4, # how long the police must pin you down
	"bustPenalty": 3, # seconds per wanted star

	# Camera
	"camDistance": 7.2,
	"camHeight": 2.6,
	"camFov": 68.0,
	"camFovNitro": 84.0,
}


static func color(hex: int) -> Color:
	return Color.hex((hex << 8) | 0xff)


## Physics length including a towed caravan.
static func total_length(s: Dictionary) -> float:
	var t: float = s.get("trailerLength", 0.0)
	return s.length + (t + 0.9 if t > 0.0 else 0.0)


const COUPE := {"bodyHeight": 0.52, "cabinLength": 1.8, "cabinOffset": -0.25, "cabinHeight": 0.46, "hatch": false, "spoiler": true}

static var CARS := {
	"rx": _merge({
		"id": "rx", "name": "Mazdo RX-Zeven", "driver": "Jij", "color": 0xd81e1e,
		"mass": 1250.0, "length": 4.3, "width": 1.78, "topSpeed": 69.0, "accelFactor": 1.0, "gripFactor": 1.0,
		"plate": "A35-RX-7", "model": "rx7",
	}, COUPE),
	"supremo": {
		"id": "supremo", "name": "Toyoda Supremo", "driver": "Sanne", "color": 0xf2c014,
		"mass": 1400.0, "length": 4.52, "width": 1.82, "topSpeed": 70.0, "accelFactor": 1.03, "gripFactor": 1.05,
		"bodyHeight": 0.5, "cabinLength": 1.9, "cabinOffset": -0.3, "cabinHeight": 0.44, "hatch": false, "spoiler": true, "model": "supremo", "plate": "SN-53-NE",
	},
	"golv": {
		"id": "golv", "name": "Wolfsburg Golv G60", "driver": "Henk-Jan", "color": 0x1d4fd8,
		"mass": 1150.0, "length": 4.0, "width": 1.72, "topSpeed": 67.0, "accelFactor": 1.05, "gripFactor": 1.0,
		"bodyHeight": 0.6, "cabinLength": 2.0, "cabinOffset": -0.45, "cabinHeight": 0.55, "hatch": true, "spoiler": false, "model": "golv", "plate": "HJ-60-G",
	},
	"civik": {
		"id": "civik", "name": "Hondo Civik", "driver": "Joost", "color": 0x8fd3ff,
		"mass": 1080.0, "length": 4.1, "width": 1.7, "topSpeed": 68.0, "accelFactor": 1.08, "gripFactor": 0.98,
		"bodyHeight": 0.54, "cabinLength": 1.9, "cabinOffset": -0.35, "cabinHeight": 0.48, "hatch": true, "spoiler": true, "model": "civik", "plate": "UT-01-JO",
	},
	"corso": {
		"id": "corso", "name": "Opal Corso", "driver": "Mehmet", "color": 0xff6a00,
		"mass": 1050.0, "length": 3.9, "width": 1.66, "topSpeed": 66.0, "accelFactor": 1.06, "gripFactor": 1.0,
		"bodyHeight": 0.58, "cabinLength": 1.9, "cabinOffset": -0.4, "cabinHeight": 0.52, "hatch": true, "spoiler": false, "model": "corso", "plate": "TB-24-7",
		"livery": "delivery",
	},
	"spacewagen": {
		"id": "spacewagen", "name": "Mitsubushi Space Wagen", "driver": "Tante Riek", "color": 0xb03a7a,
		"mass": 1450.0, "length": 4.6, "width": 1.74, "topSpeed": 64.0, "accelFactor": 0.95, "gripFactor": 0.93,
		"bodyHeight": 0.8, "cabinLength": 3.0, "cabinOffset": -0.2, "cabinHeight": 0.62, "hatch": true, "spoiler": false, "model": "spacewagen", "plate": "RK-19-AL",
	},
	"calibro": {
		"id": "calibro", "name": "Opal Calibro", "driver": "Bennie", "color": 0x111111,
		"mass": 1300.0, "length": 4.5, "width": 1.77, "topSpeed": 68.0, "accelFactor": 1.0, "gripFactor": 1.0,
		"bodyHeight": 0.5, "cabinLength": 1.9, "cabinOffset": -0.3, "cabinHeight": 0.45, "hatch": false, "spoiler": false, "model": "calibro", "plate": "HE-18-AC",
		"stripeColor": 0xf5f5f5,
	},
	"volvi": {
		"id": "volvi", "name": "Volvi 240 Kombi", "driver": "Gerrit", "color": 0x24563a,
		"mass": 1650.0, "length": 4.8, "width": 1.75, "topSpeed": 64.0, "accelFactor": 0.9, "gripFactor": 0.95,
		"bodyHeight": 0.66, "cabinLength": 2.7, "cabinOffset": -0.55, "cabinHeight": 0.6, "hatch": true, "spoiler": false, "model": "volvi", "plate": "GR-24-OE",
		"armor": 0.85,
	},
}

## The seven rivals, in grid order (front to back). The player starts last.
const RIVALS := ["supremo", "golv", "civik", "corso", "calibro", "volvi", "spacewagen"]

const POLICE_CAR := {
	"id": "police", "name": "Politie Volvi V70", "driver": "Politie", "color": 0xf4f6f8,
	"mass": 1700.0, "length": 4.8, "width": 1.8, "topSpeed": 73.0, "accelFactor": 1.1, "gripFactor": 1.05,
	"bodyHeight": 0.64, "cabinLength": 2.6, "cabinOffset": -0.5, "cabinHeight": 0.56, "hatch": true, "spoiler": false, "plate": "POL-112",
	"livery": "police", "armor": 0.7, "model": "police",
}

const PERSONALITY_BASE := {"playerFocus": 0.5, "laneChangeDelay": 1.5, "awareness": 30.0, "erratic": 0.0, "shunter": false}

static var AI_PERSONALITIES := {
	"supremo": _merge({"skill": 1.0, "aggression": 0.15, "awareness": 40.0, "taunts": ["Gas geaven!", "Tot in Enschede!"]}, PERSONALITY_BASE),
	"golv": _merge({"skill": 0.85, "aggression": 0.9, "playerFocus": 1.0, "taunts": ["Ik zal di wal kriegen!", "Wat mot dat noe?"]}, PERSONALITY_BASE),
	"civik": _merge({"skill": 0.8, "aggression": 0.5, "awareness": 14.0, "laneChangeDelay": 1.0, "taunts": ["Tentamen gehaald, nu racen!", "Yolo!"]}, PERSONALITY_BASE),
	"corso": _merge({"skill": 0.8, "aggression": 0.75, "laneChangeDelay": 0.5, "awareness": 26.0, "taunts": ["Bestelling onderweg!", "Opzij, eten wordt koud!"]}, PERSONALITY_BASE),
	"calibro": _merge({"skill": 0.8, "aggression": 0.7, "playerFocus": 0.3, "shunter": true, "taunts": ["Heraklus!", "Van achteren is ook raak!"]}, PERSONALITY_BASE),
	"volvi": _merge({"skill": 0.7, "aggression": 0.6, "taunts": ["Aan de kaante, noaber!", "Kump wal goed!"]}, PERSONALITY_BASE),
	"spacewagen": _merge({"skill": 0.65, "aggression": 0.35, "erratic": 1.0, "taunts": ["Oh, was dat rood?", "Ik moet nog naar de Jumbo!"]}, PERSONALITY_BASE),
}

## Traffic vehicle templates; colours are randomised per spawn.
const TRAFFIC := [
	{
		"weight": 6, "lane": "any", "speed": [29.0, 35.0],
		"spec": {
			"id": "sedan", "name": "Personenauto", "driver": "Verkeer", "color": 0x888888, "mass": 1300.0, "length": 4.5, "width": 1.77,
			"topSpeed": 40.0, "accelFactor": 0.7, "gripFactor": 1.0, "bodyHeight": 0.6, "cabinLength": 2.2, "cabinOffset": -0.2, "cabinHeight": 0.5,
			"hatch": false, "spoiler": false, "plate": "12-ABC-3", "model": "tr_sedan",
		},
	},
	{
		"weight": 5, "lane": "any", "speed": [28.0, 34.0],
		"spec": {
			"id": "hatch", "name": "Hatchback", "driver": "Verkeer", "color": 0x888888, "mass": 1100.0, "length": 4.0, "width": 1.70,
			"topSpeed": 38.0, "accelFactor": 0.7, "gripFactor": 1.0, "bodyHeight": 0.62, "cabinLength": 2.0, "cabinOffset": -0.4, "cabinHeight": 0.52,
			"hatch": true, "spoiler": false, "plate": "45-XYZ-6", "model": "tr_hatch",
		},
	},
	{
		"weight": 3, "lane": "right", "speed": [25.0, 30.0],
		"spec": {
			"id": "van", "name": "Bestelbus", "driver": "Verkeer", "color": 0xf0f0f0, "mass": 2400.0, "length": 5.3, "width": 1.96,
			"topSpeed": 33.0, "accelFactor": 0.6, "gripFactor": 0.9, "bodyHeight": 1.0, "cabinLength": 1.2, "cabinOffset": 1.5, "cabinHeight": 0.9,
			"hatch": true, "spoiler": false, "plate": "VB-123-K", "kind": "van", "armor": 0.6, "model": "tr_van",
		},
	},
	{
		"weight": 3, "lane": "right", "speed": [22.0, 24.0],
		"spec": {
			"id": "truck", "name": "Vrachtwagen", "driver": "Verkeer", "color": 0x2255aa, "mass": 14000.0, "length": 16.5, "width": 2.55,
			"topSpeed": 25.0, "accelFactor": 0.3, "gripFactor": 0.8, "bodyHeight": 1.2, "cabinLength": 2.3, "cabinOffset": 0.0, "cabinHeight": 1.6,
			"hatch": false, "spoiler": false, "plate": "BX-12-TT", "kind": "truck", "armor": 0.15,
		},
	},
	{
		"weight": 2, "lane": "right", "speed": [23.0, 26.0],
		"spec": {
			"id": "caravan", "name": "Auto met caravan", "driver": "Verkeer", "color": 0x888888, "mass": 2700.0, "length": 4.7, "width": 1.78,
			"topSpeed": 28.0, "accelFactor": 0.5, "gripFactor": 0.85, "bodyHeight": 0.64, "cabinLength": 2.6, "cabinOffset": -0.5, "cabinHeight": 0.56,
			"hatch": true, "spoiler": false, "plate": "DE-77-NL", "trailerLength": 5.2, "armor": 0.7, "model": "tr_estate",
		},
	},
]

const TRUCK_COMPANIES := ["Tukker Transport", "Van Salland Logistiek", "Twentse Melk", "Boekelo Bier", "Hengelose Koek"]
const TRUCK_COLORS := [0x2255aa, 0xaa2222, 0xeeeeee, 0x226633, 0xf0b400]
const TRAFFIC_COLORS := [0xc9c9c9, 0x2b2b2b, 0xf2f2f2, 0x7a1f1f, 0x1f3f7a, 0x3f5f3f, 0x9a8a6a, 0x5a5a66, 0xb5b5b5, 0x223344]

## Road cross-section (meters). d is the lateral offset, positive to the right of travel.
const ROAD_HALF_WIDTH := 5.5 # our carriageway: railing at ±5.5
const LANE_CENTERS := [-2.75, 0.75] # left lane, right lane (vluchtstrook ≈ 4.0)
const SHOULDER := 4.0
## Lane centres of the opposite carriageway (traffic coming towards us).
const ONCOMING_LANES := [-11.75, -15.25]
const SAMPLE_SPACING := 1.0 # meters between track samples


static func _merge(a: Dictionary, defaults: Dictionary) -> Dictionary:
	var out := defaults.duplicate(true)
	out.merge(a, true)
	return out


## Phones and tablets get the on-screen controls.
static func is_touch() -> bool:
	if OS.get_cmdline_user_args().has("--touch"):
		return true
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	return DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")
