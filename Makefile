default: install

all: carnage.smx botcontrol.smx mvm_coaltown.pop drzed.smx

carnage.smx: carnage.sp gen_effects_tables.py
	python3 gen_effects_tables.py
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp carnage.sp

botcontrol.smx: botcontrol.sp
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp botcontrol.sp

drzed.smx: drzed.sp cs_weapons.inc
	python3 gen_effects_tables.py
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp drzed.sp

mvm_coaltown.pop: gen_mvm_waves.py
	python3 gen_mvm_waves.py

cs_weapons.inc: parse_csgo_cfg.py ~/tf2server/steamcmd_linux/csgo/csgo/scripts/items/items_game.txt
	python3 $^ $@

install: all
	cp *.smx ~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/plugins
	cp *.pop ~/tf2server/steamcmd_linux/tf2/tf/custom/pop/scripts/population
