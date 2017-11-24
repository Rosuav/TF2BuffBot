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
	}, "detriments": {
		"TFCond_Jarated": "%s just got covered in Jarate. Eww.",
		"TFCond_Milked": "%s just got covered in something that's almost, but not entirely, unlike milk.",
		"TFCond_MarkedForDeathSilent": "%s needs to die. Go! Arrange that for me!",
		"TFCond_HalloweenKartCage": "%s has been naughty and is now imprisoned.", # Likely a death sentence
		"TFCond_Plague": "A rat bites %s and inflicts a non-contagious form of the Bubonic Plague.",
		# TFCond_RestrictToMelee, //TODO: If this gets triggered, also force selection of melee weapon
		"view_as<TFCond>(-2)": "%s becomes as heavy as... well, a Heavy?",
		"view_as<TFCond>(-4)": "Blood clouds %s's vision...",
	}, "weird": {
		"TFCond_HalloweenGhostMode": "%s is pining for the fjords...",
		"view_as<TFCond>(-3)": "Chaotic gravity waves surround %s.",
		"view_as<TFCond>(-5)": "%s goes into a blind rage!!!",
		"view_as<TFCond>(-6)": "%s roars 'YOU SHALL NOT PASS!'",
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

with open("carnage.sp") as source, open("convars.inc", "w") as cv:
	print("void CreateConVars() {", file=cv)
	for line in source:
		m = re.match(r"^ConVar (sm_ccc_[a-z_]+) = null; //\(([0-9]+)\) (.*)", line)
		if not m: continue
		print("\t{0} = CreateConVar(\"{0}\", \"{1}\", \"{2}\", 0, true, 0.0);".format(*m.groups()), file=cv)
	print("}", file=cv)
