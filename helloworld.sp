#include <sourcemod>

public Plugin myinfo =
{
	name = "Hello World",
	author = "Chris Angelico",
	description = "Basic test plugin",
	version = "0.1",
	url = "http://www.rosuav.com/",
};

public void OnPluginStart()
{
	RegAdminCmd("sm_critboost", Command_CritBoost, 0);
}

public Action Command_CritBoost(int client, int args)
{
	PrintToServer("Hello world!");
	return Plugin_Handled;
}