#!/usr/bin/env python3
# Generate the randeffects.inc file for inclusion into carnage.sp
import json # Quickest way to get C-like string encoding
import re
from enum import IntFlag, auto
from collections import defaultdict

# These tables define the effects possible from the !roulette command.
# The "benefits" table is also used by the !gift command. The intention
# is that anything in "benefits" is so rarely detrimental that it would
# be considered strictly better than not having the buff; for instance,
# getting ubercharged could potentially lose you the game since you can't
# capture points while ubered, but that's a corner case, and usually a
# free ubercharge would be considered good. Similarly, the Crit-A-Cola
# from this buff does not include the death-mark effect that the actual
# drink entails.

# The difference between "detriments" and "weird" has no impact other than
# the two-tier probability system. Conceptually, the "weird" category has
# effects that can easily be beneficial or detrimental, whereas the
# "detriments" category should be exclusively bad (to the same extent that
# "benefits" are exclusively good; for instance, becoming heavier can at
# times be useful). Ideally, "weird" effects should simultaneously be BOTH
# good and bad - blind rage being a perfect example of this.

# Most of the keys here are actual TF2 condition flags that get applied for
# the specified duration. A few of them have additional or alternative
# functionality as specified in carnage.sp:apply_effect; custom effects are
# assigned negative numbers, and have their code entirely in apply_effect.

# Every description should have exactly one "%s", which receives the name of
# the recipient of the effect. (In the case of a !gift, the gifting has been
# reported on prior to this message.) It's entirely acceptable for the message
# to be a bit vague about the stranger effects - players can experiment, or of
# course read the source code.
effects = {
	"benefits": {
		"TFCond_UberchargedOnTakeDamage": "%s's Uber driver just arrived.",
		# "TFCond_CritOnDamage": "%s is critical of everyone!", # Subsumed into (-8) below
		"TFCond_CritCola": "%s types IDKFA and downs a can of Cola!",
		"TFCond_BulletImmune": "%s is bulletprooooooof!",
		"TFCond_BlastImmune": "%s is bombprooooooof!",
		"TFCond_FireImmune": "%s is inflammable... I mean non-flammable!",
		"TFCond_Stealthed": "Oops... %s seems to have vanished.",
		"TFCond_DefenseBuffed": "%s erects a personal-sized banner and toots a little bugle.",
		"TFCond_SpeedBuffAlly": "Get in, get the job done, and get out. Got it, %s?",
		"TFCond_RegenBuffed": "%s turns into a Time Lord and starts regenerating...",
		# "view_as<TFCond>(-1)": "%s becomes as light as a feather!",
		# "TFCond_KingAura": "It's good to be the king, right %s?", # Doesn't seem to work
		"TFCond_Unknown2": "%s eats a radioactive ham sandvich.", # Redefined to be Bonkvich
		"view_as<TFCond>(-8)":    "%s parties like it's three easy payments of $19.99!", # Class-specific buff
		"view_as<TFCond>(-8) ":   "%s celebrates the diversity of classes on the team!", # has multiple entries,
		"view_as<TFCond>(-8)  ":  "%s pretends someone just got dominated! Bahahahaha!", # making it more likely
		"view_as<TFCond>(-8)   ": "Ooh yes, %s, celebrate, celebrate, celebrate, KILL!", # to come up.
		# "TFCond_MegaHeal": "%s can't be knocked back.", # Not much on its own but could be good in combination
	}, "detriments": {
		"TFCond_Jarated": "%s just got covered in Jarate. Eww.",
		"TFCond_Milked": "%s just got covered in something that's almost, but not entirely, unlike milk.",
		"TFCond_MarkedForDeathSilent": "%s needs to die. Go! Arrange that for me!",
		"TFCond_HalloweenKartCage": "%s has been naughty and is now imprisoned.", # Likely a death sentence
		"TFCond_Plague": "A rat bites %s and inflicts a non-contagious form of the Bubonic Plague.",
		"TFCond_RestrictToMelee": "Time for %s to start bashing some heads in!",
		# "view_as<TFCond>(-2)": "%s becomes as heavy as... well, a Heavy?",
		"view_as<TFCond>(-4)": "Blood clouds %s's vision...",
	}, "weird": {
		# "view_as<TFCond>(-9)": "%s begins testing stuff for the devs", # Will always be [3,1] when active
		"TFCond_HalloweenGhostMode": "%s is pining for the fjords...",
		# "view_as<TFCond>(-3)": "Chaotic gravity waves surround %s.",
		"view_as<TFCond>(-5)": "%s goes into a blind rage!!!",
		"view_as<TFCond>(-6)": "%s roars 'YOU SHALL NOT PASS!'",
		"TFCond_Bonked": "%s opens a chilled can of a radioactive energy drink.",
		"TFCond_DisguisedAsDispenser": "%s can run, but... well, actually, can hide too.",
		"view_as<TFCond>(-10)": "%s screams 'I am NOT a GLITCH!!'",
	}
}

# TODO: Make sure none of these have IDs 128 or higher, lest stuff break badly.
# (It's 2018. Why does SourcePawn have to use fixed array sizes?)
notable_kills = {
	# TODO: Put better names on them
	"TF_CUSTOM_TAUNT_HADOUKEN": "Taunt kill! Hadouken!",
	"TF_CUSTOM_FLARE_PELLET": "Taunt kill! [FLARE_PELLET]", # Scorch Shot "Execution" taunt kill
	"TF_CUSTOM_TAUNT_GRAND_SLAM": "Taunt kill! Knock him out of the park!",
	"TF_CUSTOM_TAUNT_HIGH_NOON": "Taunt kill! This map ain't big enough for both of us...",
	"TF_CUSTOM_TAUNT_FENCING": "Taunt kill! Someone just got turned into a Cornish game hen.",
	"TF_CUSTOM_TAUNT_GRENADE": "Taunt kill! KAMIKAZE!", # Escape Plan / Equalizer
	"TF_CUSTOM_TAUNT_ARROW_STAB": "Taunt kill! Schtab schtab schtab!",
	"TF_CUSTOM_TAUNTATK_GASBLAST": "Taunt kill! [GASBLAST]", # Thermal Thruster
	"TF_CUSTOM_TAUNT_BARBARIAN_SWING": "Taunt kill! [BARBARIAN]", # Eyelander etc
	"TF_CUSTOM_TAUNT_UBERSLICE": "Taunt kill! Dem bones got sawed through...",
	"TF_CUSTOM_TAUNT_ENGINEER_SMASH": "Taunt kill! That's one jarring guitar riff...",
	"TF_CUSTOM_TAUNT_ENGINEER_ARM": "Taunt kill! You got killed by a lawnmower...",
	"TF_CUSTOM_TAUNT_ARMAGEDDON": "Taunt kill! Death by rainbows!",
	"TF_CUSTOM_TAUNT_ALLCLASS_GUITAR_RIFF": "Taunt kill! [GUITAR_RIFF]",
	# Some non-taunt kills are also worth bonus points
	"TF_CUSTOM_TELEFRAG": "Telefrag!",
	"TF_CUSTOM_COMBO_PUNCH": "That's three gunslingers in a row!", # Gunslinger. Applies only if the third hit kills.
	"TF_CUSTOM_BOOTS_STOMP": "Mantreads stomp!!", # Mantreads or Thermal Thruster
}
# Other kill types to check for: TF_CUSTOM_WRENCH_FIX, TF_CUSTOM_PENETRATE_ALL_PLAYERS,
# TF_CUSTOM_PENETRATE_HEADSHOT, TF_CUSTOM_FLYINGBURN, TF_CUSTOM_AEGIS_ROUND,
# TF_CUSTOM_PRACTICE_STICKY, TF_CUSTOM_THROWABLE, TF_CUSTOM_THROWABLE_KILL

class UF(IntFlag):
	# Headshots deal 1.0 damage instead of 4.0
	NO_HEADSHOTS = auto()
	# Non-headshots deal 0.0 damage. Can technically be combined with NO_HEADSHOTS but it'd be annoying.
	HEADSHOTS_ONLY = auto()
	# Note that cond_damage_headshot can be used (directly or inverted) to permit all damage but only
	# count the kill if it was/wasn't a headshot.
	FREE_HEGRENADE = auto()
	FREE_FLASHBANG = auto()
	FREE_MOLLY = auto()
	FREE_TAGRENADE = auto()
	# World manipulation
	T_LOW_GRAVITY = auto()
	CT_LOW_GRAVITY = auto()
	T_HIGH_GRAVITY = auto() # High gravity isn't very interesting tbh
	CT_HIGH_GRAVITY = auto()
	LOW_ACCURACY = auto() # Reduce all accuracy
	HIGH_ACCURACY = auto() # Improve all accuracy
	SALLY = auto() # The longer you keep firing, the more your fire rate increases.
	VAMPIRIC = auto() # Damage is vampiric, and bots gain health periodically
	PHASEPING = auto() # Ping, wait 1.5 seconds, and then you will teleport to that location.
	KNIFE_FOCUS = auto() # Guns deal fractional damage. TODO: Make knife slashes deal 200, and reduce tagging.
	MORE_RANGE_PENALTY = auto() # Increase damage at close range but drastically increase the range penalty
	# Extra conditions: Kill doesn't count if...
	ASSISTED_ONLY = auto() # ... there's no assister; combine with the below to narrow it down
	NO_TEAM_ASSISTS = auto() # ... assister is on same team as victim
	NO_FLASH_ASSISTS = auto() # ... it was a flash assist
	NO_NONFLASH_ASSISTS = auto() # ... it was not a flash assist
	PENETRATION_ONLY = auto() # ... it wasn't a penetration shot
	# Player restrictions
	DISABLE_SCOPING = auto() # If anyone scopes in, automatically unscope them. Will confuse the bots, probably!
	DISABLE_AUTOMATIC_FIRE = auto() # After you fire a bullet, your gun will stop firing.
	# Unimplemented
	FLYING = auto() # Damage only has effect if you are in the air
	BETTER_ARMOR = auto() # All weapons have their armor penetration (armor ratio) reduced
	# TODO: Low movement speed, high movement speed - separate flags for Ts and CTs
	# These flags give free items to all CTs and are handled with a single block of code.
	FREEBIES = FREE_HEGRENADE | FREE_FLASHBANG | FREE_MOLLY | FREE_TAGRENADE
	# These flags require the ticking timer. As soon as one is seen, the timer will be started.
	NEED_TIMER = FREEBIES | VAMPIRIC # Note: has to be different from FREEBIES (add a shim if necessary)

# Tautology for "always true" because other methods failed. Used for warmup, and for
# any wave where the actual conditions are defined by flags.
ANYTHING = "%cond_player_zoomed% || !%cond_player_zoomed%"

underdome_modes = [
	# Warmup wave - always the first entry. If you start a wave with 0 kills, it'll use this rather than randomizing.
	{
		"intro": "Warmup wave! Any kill's a kill!",
		"needed": ANYTHING,
		"flags": 0,
		"killok": "",
		"killbad": "",
	},
	{
		"intro": "GOAL: Snipers. Zoomed kills only.",
		"needed": "%cond_player_zoomed%",
		"flags": 0,
		"killok": "",
		"killbad": "Kills only count if you're scoped in!",
	},
	{
		"intro": "GOAL: Baroness",
		"needed": "%weapon_deagle% || %weapon_p90% || %weapon_xm1014% || %weapon_scar20% || %weapon_g3sg1% || %weapon_m249% || %weapon_knife%",
		"flags": 0,
		"killok": "",
		"killbad": "Weapon too cheap, doesn't count!",
	},
	{
		"intro": "GOAL: Flash 'em and Smash 'em!",
		"needed": "%cond_victim_blind%",
		"flags": UF.FREE_FLASHBANG,
		"killok": "",
		"killbad": "No good, he saw that coming!",
	},
	{
		"intro": "I'm sending you some of my old bottles of wine. Bomb those bandits from the air!",
		"needed": "%cond_damage_burn%",
		"flags": UF.FREE_MOLLY | UF.CT_LOW_GRAVITY | UF.T_LOW_GRAVITY | UF.FLYING,
		"killok": "Sick burn, bro...",
		"killbad": "",
	},
	{
		"intro": "GOAL: Team up! Swap weapons with your buddy!",
		"needed": "%cond_item_borrowed_teammate%",
		"flags": 0,
		"killok": "",
		"killbad": "",
	},
	{
		"intro": "GOAL: Team up! Get assists with your teammate!",
		"needed": ANYTHING,
		"flags": UF.ASSISTED_ONLY | UF.NO_TEAM_ASSISTS,
		"killok": "",
		"killbad": "You can't do this as a lone wolf - buddy up!",
	},
	{
		"intro": "GOAL: Go Vanilla!",
		"needed": "%weapon_hkp2000% || %weapon_usp_silencer% || %weapon_glock% || !%cond_item_nondefault%",
		"flags": 0,
		"killok": "",
		"killbad": "Try an unskinned weapon or your starting pistol",
	},
	{
		"intro": "GOAL: Keep the n0ise down", # :)
		"needed": "%weapon_usp_silencer% || %weapon_m4a1_silencer% || %weapon_mp5sd%",
		"flags": 0,
		"killok": "",
		"killbad": "The true world revealed - noises are now known to me - time to silence your gun.",
	},
	{
		"intro": "GOAL: I'm totally not walling",
		"needed": ANYTHING,
		"flags": UF.FREE_TAGRENADE | UF.PENETRATION_ONLY,
		"killok": "",
		"killbad": "Go on, shoot 'em through the wall already",
	},
	{
		"intro": "GOAL: Shotgun challenge. Go for center of mass.",
		"needed": "%weapon_nova% || %weapon_sawedoff% || %weapon_mag7% || %weapon_xm1014%",
		"flags": UF.NO_HEADSHOTS,
		"killok": "",
		"killbad": "",
	},
	{
		"intro": "GOAL: Anarchy! Close the distance for high damage!",
		"needed": ANYTHING,
		# Note that MORE_RANGE_PENALTY seems to be be largely bypassed by scoping in with
		# an AUG/SG, so disallow scopes to stop that from being cheesed.
		"flags": UF.LOW_ACCURACY | UF.MORE_RANGE_PENALTY | UF.DISABLE_SCOPING,
		"killok": "",
		"killbad": "",
	},
	{
		"intro": "GOAL: Use your sidearm",
		"needed": "%weapon_deagle% || %weapon_revolver% || %weapon_elite% || %weapon_fiveseven% || %weapon_cz75a% || %weapon_usp_silencer% || %weapon_hkp2000% || %weapon_p250% || %weapon_glock% || %weapon_tec9%",
		"flags": UF.BETTER_ARMOR,
		"killok": "",
		"killbad": "",
	},
	{
		"intro": "GOAL: LMG time - spray 'em down! Scopes are useless here.",
		"needed": "%weapon_m249% || %weapon_negev%",
		"flags": UF.DISABLE_SCOPING | UF.SALLY,
		"killok": "",
		"killbad": "",
	},
	{
		"intro": "GOAL: Semi-Automatics",
		"needed": "%weapon_deagle% || %weapon_revolver% || %weapon_elite% || %weapon_fiveseven% || %weapon_usp_silencer% || %weapon_glock% || %weapon_hkp2000% || %weapon_p250% || %weapon_tec9% || %weapon_mag7% || %weapon_sawedoff% || %weapon_nova% || %weapon_awp% || %weapon_ssg08%",
		"flags": UF.DISABLE_AUTOMATIC_FIRE,
		"killok": "",
		"killbad": "",
	},
	{
		"intro": "GOAL: Go for the head.",
		"needed": ANYTHING,
		"flags": UF.HEADSHOTS_ONLY,
		"killok": "",
		"killbad": "",
	},
	{
		"intro": "GOAL: Phasewalk your SMG to Victory",
		# Lilith loves fire, so even though it isn't said in the description, burn kills count too.
		"needed": "%weapon_mac10% || %weapon_mp9% || %weapon_ump45% || %weapon_bizon% || %weapon_mp7% || %weapon_mp5sd% || %weapon_p90% || %cond_damage_burn%",
		"flags": UF.PHASEPING,
		"killok": "",
		"killbad": "",
	},
	{
		"intro": "GOAL: Brick, have fun",
		"needed": "%weapon_knife% || %weapon_hegrenade%",
		"flags": UF.KNIFE_FOCUS | UF.FREE_HEGRENADE,
		"killok": "",
		"killbad": "",
	},
	{
		"intro": "GOAL: Transfusion Grenades",
		# TODO: Figure out why Decoys don't count
		"needed": "%weapon_hegrenade% || %weapon_molotov% || %weapon_incgrenade% || %weapon_flashbang% || %weapon_decoy% || %decoy_projectile% || %weapon_smokegrenade%",
		"flags": UF.VAMPIRIC | UF.FREE_HEGRENADE,
		"killok": "",
		"killbad": "G button.",
	},
]

flashbang_targets = """
1309.3 1238.4 65.03 Long Corner
"""

with open("randeffects.inc", "w") as f:
	for name, options in effects.items():
		print("TFCond %s[] = {" % name, file=f)
		for cond in options:
			print("\t%s," % cond, file=f)
		print("};", file=f)
		print("char %s_desc[][] = {" % name, file=f)
		for desc in options.values(): # Will iterate in the same order as options above
			# Color codes work only if there's a color code right at the start of the
			# message. For something that starts "%s", that's fine, but for others,
			# toss in a null color code just to make color codes work. Thaaaaanks.
			desc = json.dumps(desc)
			if not desc.startswith('"%s'): desc = r'"\x079ACDFF\x01' + desc[1:]
			print("\t%s," % desc, file=f)
		print("};\n", file=f)

with open("underdome.inc", "w") as f:
	for flag in UF:
		print("#define UF_%s %d" % (flag.name, int(flag)), file=f)
	for block, example in underdome_modes[0].items():
		# For each key in the dict, create a dedicated data block
		if isinstance(example, int):
			# Print it all out on one line for simplicity
			print("int underdome_%s[] = {%s};" % (block, ",".join(str(int(mode[block])) for mode in underdome_modes)), file=f)
			continue
		print("char underdome_%s[][] = {" % block, file=f)
		for mode in underdome_modes:
			print("\t%s," % json.dumps(mode[block]), file=f)
		print("};", file=f);

with open("flashbang.inc", "w") as f:
	# First, group the targets by description.
	groups = defaultdict(list)
	for line in flashbang_targets.split("\n"):
		if not line: continue
		x, y, z, desc = line.split(" ", 3)
		groups[desc].append((x, y, z)) # Keeps the coords as strings for simplicity
	print("float flash_targets[][3] = {", file=f)
	regions, counts = [], []
	for i, (desc, targets) in enumerate(groups.items()):
		regions.append(desc)
		counts.append(len(targets))
		for t in targets:
			print("\t{%s, %s, %s}," % t, file=f)
	print("};", file=f)
	print("char flash_target_regions[][] = {%s};" % json.dumps(regions).strip("[]"), file=f)
	print("int flash_region_targets[] = {%s};" % json.dumps(counts).strip("[]"), file=f)

def parse_convars(fn, **mappings):
	"""Parse out cvar definitions and create an include file

	parse_convars("X") parses X.sp and creates convars_X.inc; any
	keyword arguments will become mappings mapped into arrays.
	"""
	with open(fn + ".sp") as source, open("convars_%s.inc" % fn, "w") as cv:
		print("void CreateConVars() {", file=cv)
		for line in source:
			m = re.match(r"^ConVar ([a-z_]+) = null; //\(([0-9.]+)\) (.*)", line)
			if m: # Numeric cvar
				print("\t{0} = CreateConVar(\"{0}\", \"{1}\", \"{2}\", 0, true, 0.0);".format(*m.groups()), file=cv)
			m = re.match(r'^ConVar ([a-z_]+) = null; //\("([^"]*)"\) (.*)', line)
			if m: # String cvar (default value may not contain nested quotes)
				print("\t{0} = CreateConVar(\"{0}\", \"{1}\", \"{2}\", 0);".format(*m.groups()), file=cv)
			m = re.match(r'^ConVar ([a-z_, ]+);$', line)
			if m: # References to other cvars - may be multiple, separated by ", "
				for cvar in m.group(1).split(", "):
					print("\t{0} = FindConVar(\"{0}\");".format(cvar), file=cv)
		for name, values in mappings.items():
			for code, value in values.items():
				print("\t%s[%s] = %s;" % (name, code, json.dumps(value)), file=cv)
		print("}", file=cv)
parse_convars("carnage", notable_kills=notable_kills)
parse_convars("drzed")

# TODO: Migrate all gravity shifts into Weird.
# This requires that each of them be potentially both good and bad, or else
# so bizarre that you can't declare it clearly either of the above. "Chaotic
# Gravity" already counts. All else being equal, lower grav is better than
# higher grav, as you can jump higher and (I think) will take less falling
# damage. So increased grav + knockback prevention would be a perfect Weird
# effect - it makes sense, and is simultaneously good and bad. What would be
# a corresponding effect to go with reduced grav? Has to be minorly annoying
# or detrimental, and has to "feel right" (yes, that's fuzzy) with low grav.
