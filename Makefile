default: install

all: buffbot.smx botcontrol.smx

buffbot.smx: buffbot.sp randeffects.inc
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp buffbot.sp

botcontrol.smx: botcontrol.sp
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp botcontrol.sp

randeffects.inc convars.inc: buffbot.sp gen_effects_tables.py
	python3 gen_effects_tables.py

install: all
	cp *.smx ~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/plugins
