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
		# "TFCond_KingAura": "It's good to be the king, right %s?", # Doesn't seem to work
		# Sadly, these can be abused by dropping them, which eliminates
		# the time limit :(
		# TFCond_RuneStrength,
		# TFCond_RuneHaste,
		# TFCond_RuneRegen,
		# TFCond_RuneResist,
		# TFCond_RuneVampire,
		# TFCond_RuneWarlock,
		# TFCond_RunePrecision,
		# TFCond_RuneAgility,
		# TFCond_KingRune,
		# TFCond_PlagueRune,
		# TFCond_SupernovaRune,
	}, "detriments": {
		"TFCond_Jarated": "%s just got covered in Jarate. Eww.",
		"TFCond_Milked": "%s just got covered in something that's almost, but not entirely, unlike milk.",
		"TFCond_MarkedForDeathSilent": "%s needs to die. Go! Arrange that for me!",
		# TFCond_RestrictToMelee, //TODO: If this gets triggered, also force selection of melee weapon
	}, "weird": {
		"TFCond_DisguisedAsDispenser": "Something weird just happened to %s.",
	}
}
data = ""
for name, options in effects.items():
	ids = "TFCond %s[] = {\n" % name + "".join("\t%s,\n" % x for x in options) + "}\n"
	descs = "char %s_desc[][] = {\n" % name + "".join("\t%s,\n" % json.dumps(x) for x in options.values()) + "}\n"
	data += ids + descs + "\n"

# TODO: Possibly compare data against what's on disk and update only if necessary
with open("randeffects.inc", "w") as f: f.write(data)

import re
with open("buffbot.sp") as source, open("convars.inc", "w") as cv:
	print("void CreateConVars() {", file=cv)
	for line in source:
		m = re.match(r"^ConVar (sm_buffbot_[a-z_]+) = null; //\(([0-9]+)\) (.*)", line)
		if not m: continue
		print("\t{0} = CreateConVar(\"{0}\", \"{1}\", \"{2}\");".format(*m.groups()), file=cv)
	print("}", file=cv)
