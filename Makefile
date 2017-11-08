buffbot.smx: buffbot.sp randeffects.inc
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp buffbot.sp

randeffects.inc convars.inc: buffbot.sp gen_effects_tables.py
	python3 gen_effects_tables.py

install: buffbot.smx
	cp buffbot.smx ~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/plugins
