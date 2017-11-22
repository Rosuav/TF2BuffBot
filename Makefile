default: install

all: carnage.smx botcontrol.smx

carnage.smx: carnage.sp randeffects.inc
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp carnage.sp

botcontrol.smx: botcontrol.sp
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp botcontrol.sp

randeffects.inc convars.inc: carnage.sp gen_effects_tables.py
	python3 gen_effects_tables.py

install: all
	cp *.smx ~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/plugins
