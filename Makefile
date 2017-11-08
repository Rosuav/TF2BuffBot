buffbot.smx: buffbot.sp
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp buffbot.sp

install: buffbot.smx
	cp buffbot.smx ~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/plugins
