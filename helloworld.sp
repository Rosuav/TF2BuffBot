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
	PrintToServer("Hello world!");
}
