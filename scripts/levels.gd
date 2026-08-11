class_name Levels
extends RefCounted
## Static campaign data for prototype v2 "Network Planner" (see docs/v2-spec.md).

const PTYPES := {
	"visitor": {"slots": 1, "patience": 90.0},
	"patient": {"slots": 1, "patience": 75.0},
	"gurney": {"slots": 2, "patience": 60.0},
	"emergency": {"slots": 1, "patience": 30.0},
}

const CARDS := {
	"standard": {"cap": 4, "speed": 300.0},
	"large": {"cap": 8, "speed": 210.0},
	"express": {"cap": 4, "speed": 540.0},
}

const STARTING_INVENTORY := ["standard", "standard"]

const DATA := [
	{
		"id": "H-1",
		"quota": 15,
		"max_lost": 5,
		"spawn": 6.0,
		"mix": {"visitor": 0.4, "patient": 0.6},
		"transfers": [0, 5],
		"flavor": "First shift at the hospital. Design the elevator network;\nthe cars run themselves.",
		"whats_new": "Tap a card below, then tap an empty shaft to install it.\nTap an installed car to select it, then tap floors in its\ncolumn to toggle doors on/off (min 2).\nFloors 0 and 5 are TRANSFER floors: passengers can\nswitch shafts there.",
		"rewards": ["large", "express"],
	},
	{
		"id": "H-2",
		"quota": 25,
		"max_lost": 5,
		"spawn": 4.5,
		"mix": {"visitor": 0.3, "patient": 0.5, "gurney": 0.2},
		"transfers": [0, 5],
		"flavor": "Word got out. More traffic, and the orderlies are\nwheeling gurneys around.",
		"whats_new": "GURNEYS (wide orange) take 2 elevator slots.",
		"rewards": ["express", "standard"],
	},
	{
		"id": "H-3",
		"quota": 35,
		"max_lost": 5,
		"spawn": 4.0,
		"mix": {"visitor": 0.25, "patient": 0.45, "gurney": 0.15, "emergency": 0.15},
		"transfers": [0, 5, 7],
		"flavor": "The ER is slammed. Emergency surgeries are coming in.",
		"whats_new": "EMERGENCY patients (red, pulsing) have only 30 s of\npatience and always need floor 7 (SURGERY).\nFloor 7 is now also a transfer floor.",
		"rewards": [],
	},
]


static func card_label(card_type: String) -> String:
	match card_type:
		"standard":
			return "STANDARD\n4 slots"
		"large":
			return "LARGE\n8 slots, slow"
		"express":
			return "EXPRESS >>\n4 slots, fast"
	return card_type


static func card_color(card_type: String) -> Color:
	match card_type:
		"standard":
			return Color(0.42, 0.52, 0.68)
		"large":
			return Color(0.36, 0.46, 0.55)
		"express":
			return Color(0.93, 0.58, 0.16)
	return Color.GRAY
