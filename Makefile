helloworld.smx: helloworld.sp
	~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/scripting/spcomp helloworld.sp

install: helloworld.smx
	cp helloworld.smx ~/tf2server/steamcmd_linux/tf2/tf/addons/sourcemod/plugins
