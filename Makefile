buffbot.smx: buffbot.sp randeffects.inc
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp -i. buffbot.sp

randeffects.inc: buffbot.sp
	python3 gen_effects_tables.py

install: buffbot.smx
	cp buffbot.smx ~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/plugins
