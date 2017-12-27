default: install

all: carnage.smx botcontrol.smx mvm_coaltown.pop

carnage.smx: carnage.sp randeffects.inc
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp carnage.sp

botcontrol.smx: botcontrol.sp
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp botcontrol.sp

randeffects.inc convars.inc: carnage.sp gen_effects_tables.py
	python3 gen_effects_tables.py

mvm_coaltown.pop: gen_mvm_waves.py
	python3 gen_mvm_waves.py

install: all
	cp *.smx ~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/plugins
	cp *.pop ~/tf2server/steamcmd_linux/tf2/tf/custom/pop/scripts/population
