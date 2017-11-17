#!/usr/bin/env python3
# Generate the randeffects.inc file for inclusion into buffbot.sp
import json # Quickest way to get C-like string encoding

effects = {
	"benefits": {
		"TFCond_UberchargedOnTakeDamage": "%s's Uber driver just arrived",
		"TFCond_CritOnDamage": "%s is critical of everyone!",
		"TFCond_CritCola": "%s drinks some Crit-A-Cola!",
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

	}, "detriments": {
		"TFCond_Jarated": "%s just got covered in Jarate. Eww.",
		"TFCond_Milked": "%s just got covered in something that's almost, but not entirely, unlike milk.",
		"TFCond_MarkedForDeathSilent": "%s needs to die. Go! Arrange that for me!",
		# Will probably result in death. Thirty seconds unable to move is gonna suck.
		# "TFCond_HalloweenKartCage": "%s has been naughty and is now imprisoned.", # Doesn't seem to work properly
		"TFCond_Plague": "A rat bites %s and inflicts a non-contagious form of the Bubonic Plague.",
		# TFCond_RestrictToMelee, //TODO: If this gets triggered, also force selection of melee weapon
		"view_as<TFCond>(-2)": "%s becomes as heavy as... well, a Heavy?",
		"view_as<TFCond>(-4)": "Blood clouds %s's vision...",
	}, "weird": {
		"TFCond_HalloweenGhostMode": "%s is pining for the fjords...",
		"view_as<TFCond>(-3)": "Chaotic gravity waves surround %s.",
		"view_as<TFCond>(-5)": "%s goes into a blind rage!!!",
	}
}
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

import re
with open("buffbot.sp") as source, open("convars.inc", "w") as cv:
	print("void CreateConVars() {", file=cv)
	for line in source:
		m = re.match(r"^ConVar (sm_buffbot_[a-z_]+) = null; //\(([0-9]+)\) (.*)", line)
		if not m: continue
		print("\t{0} = CreateConVar(\"{0}\", \"{1}\", \"{2}\", 0, true, 0.0);".format(*m.groups()), file=cv)
	print("}", file=cv)
