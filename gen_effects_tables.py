#!/usr/bin/env python3
# Generate the randeffects.inc file for inclusion into carnage.sp
import json # Quickest way to get C-like string encoding
import re

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
		"TFCond_UberchargedOnTakeDamage": "%s's Uber driver just arrived",
		"TFCond_CritOnDamage": "%s is critical of everyone!",
		"TFCond_CritCola": "%s types IDKFA and downs a can of Cola!",
		"TFCond_BulletImmune": "%s is bulletprooooooof!",
		"TFCond_BlastImmune": "%s is bombprooooooof!",
		"TFCond_FireImmune": "%s is inflammable... I mean non-flammable!",
		"TFCond_Stealthed": "Oops... %s seems to have vanished.",
		"TFCond_DefenseBuffed": "%s erects a personal-sized banner and toots a little bugle.",
		"TFCond_SpeedBuffAlly": "Get in, get the job done, and get out. Got it, %s?",
		"TFCond_RegenBuffed": "%s turns into a Time Lord and starts regenerating...",
		"view_as<TFCond>(-1)": "%s becomes as light as a feather!",
		"TFCond_DisguisedAsDispenser": "%s can run, but... well, actually, can hide too.",
		# "TFCond_KingAura": "It's good to be the king, right %s?", # Doesn't seem to work
		"view_as<TFCond>(-7)": "%s eats a radioactive ham sandvich.",
		"view_as<TFCond>(-8)": "%s parties like it's three easy payments of $19.99!", # Class-specific buff
		# "TFCond_FocusBuff": "Focus, %s. Focus.", # Beneficial only to snipers
		# "TFCond_MegaHeal": "%s can't be knocked back.", # Not much on its own but could be good in combination
	}, "detriments": {
		"TFCond_Jarated": "%s just got covered in Jarate. Eww.",
		"TFCond_Milked": "%s just got covered in something that's almost, but not entirely, unlike milk.",
		"TFCond_MarkedForDeathSilent": "%s needs to die. Go! Arrange that for me!",
		"TFCond_HalloweenKartCage": "%s has been naughty and is now imprisoned.", # Likely a death sentence
		"TFCond_Plague": "A rat bites %s and inflicts a non-contagious form of the Bubonic Plague.",
		"TFCond_RestrictToMelee": "Time for %s to start bashing some heads in!",
		"view_as<TFCond>(-2)": "%s becomes as heavy as... well, a Heavy?",
		"view_as<TFCond>(-4)": "Blood clouds %s's vision...",
	}, "weird": {
		"TFCond_HalloweenGhostMode": "%s is pining for the fjords...",
		"view_as<TFCond>(-3)": "Chaotic gravity waves surround %s.",
		"view_as<TFCond>(-5)": "%s goes into a blind rage!!!",
		"view_as<TFCond>(-6)": "%s roars 'YOU SHALL NOT PASS!'",
		"TFCond_Bonked": "%s opens a chilled can of a radioactive energy drink.",
	}
}

# TODO: Make sure none of these have IDs 128 or higher, lest stuff break badly.
# (It's 2018. Why does SourcePawn have to use fixed array sizes?)
notable_kills = {
	# TODO: Put better names on them
	"TF_CUSTOM_TAUNT_HADOUKEN": "Taunt kill! Hadouken!",
	"TF_CUSTOM_FLARE_PELLET": "Taunt kill!",
	"TF_CUSTOM_TAUNT_GRAND_SLAM": "Taunt kill! Knock him out of the park!",
	"TF_CUSTOM_TAUNT_HIGH_NOON": "Taunt kill! This map ain't big enough for both of us...",
	"TF_CUSTOM_TAUNT_FENCING": "Taunt kill!",
	"TF_CUSTOM_TAUNT_GRENADE": "Taunt kill!",
	"TF_CUSTOM_TAUNT_ARROW_STAB": "Taunt kill! Schtab schtab schtab!",
	"TF_CUSTOM_TAUNTATK_GASBLAST": "Taunt kill!",
	"TF_CUSTOM_TAUNT_BARBARIAN_SWING": "Taunt kill!",
	"TF_CUSTOM_TAUNT_UBERSLICE": "Taunt kill! Dem bones got sawed through...",
	"TF_CUSTOM_TAUNT_ENGINEER_SMASH": "Taunt kill! That's one jarring guitar riff...",
	"TF_CUSTOM_TAUNT_ENGINEER_ARM": "Taunt kill!",
	"TF_CUSTOM_TAUNT_ARMAGEDDON": "Taunt kill! Death by rainbows!",
	"TF_CUSTOM_TAUNT_ALLCLASS_GUITAR_RIFF": "Taunt kill!",
	# Some non-taunt kills are also worth bonus points
	"TF_CUSTOM_TELEFRAG": "Telefrag!",
	"TF_CUSTOM_COMBO_PUNCH": "That's four gunslingers in a row!", # Gunslinger
	"TF_CUSTOM_BOOTS_STOMP": "Mantreads stomp!!", # Mantreads
}
# Other kill types to check for: TF_CUSTOM_WRENCH_FIX, TF_CUSTOM_PENETRATE_ALL_PLAYERS,
# TF_CUSTOM_PENETRATE_HEADSHOT, TF_CUSTOM_FLYINGBURN, TF_CUSTOM_AEGIS_ROUND,
# TF_CUSTOM_PRACTICE_STICKY, TF_CUSTOM_THROWABLE, TF_CUSTOM_THROWABLE_KILL

with open("randeffects.inc", "w") as f:
	for name, options in effects.items():
		print("TFCond %s[] = {" % name, file=f)
		for cond in options:
			print("\t%s," % cond, file=f)
		print("};", file=f)
		print("char %s_desc[][] = {" % name, file=f)
		for desc in options.values(): # Will iterate in the same order as options above
			print("\t%s," % json.dumps(desc), file=f)
		print("};\n", file=f)

with open("carnage.sp") as source, open("convars.inc", "w") as cv:
	print("void CreateConVars() {", file=cv)
	for line in source:
		m = re.match(r"^ConVar (sm_ccc_[a-z_]+) = null; //\(([0-9]+)\) (.*)", line)
		if not m: continue
		print("\t{0} = CreateConVar(\"{0}\", \"{1}\", \"{2}\", 0, true, 0.0);".format(*m.groups()), file=cv)
	for killcode, msg in notable_kills.items():
		print("\tnotable_kills[%s] = %s;" % (killcode, json.dumps(msg)), file=cv)
	print("}", file=cv)
