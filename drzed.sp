#include <sourcemod>
#include <sdkhooks>

#pragma newdecls required
#pragma semicolon 1

//By default, calling Debug() does nothing.
public void Debug(const char[] fmt, any ...) { }
//For a full log of carnage score changes, enable this:
//#define Debug PrintToServer

public Plugin myinfo =
{
	name = "Dr Zed",
	author = "Chris Angelico",
	description = "Dr Zed: I maintain the med vendors",
	version = "0.99",
	url = "https://github.com/Rosuav/TF2BuffBot",
};

ConVar sm_drzed_heal_price = null; //(0) If nonzero, healing can be bought for that much money
#include "convars_drzed"

public void OnPluginStart()
{
	RegAdminCmd("sm_hello", Command_Hello, ADMFLAG_SLAY);
	HookEvent("player_say", Event_PlayerChat);
	//As per carnage.sp, convars are created by the Python script.
	CreateConVars();
}

public Action Command_Hello(int client, int args)
{
	PrintToChatAll("Hello, world!");
	PrintToServer("Hello, server!");
	return Plugin_Handled;
}

public void Event_PlayerChat(Event event, const char[] name, bool dontBroadcast)
{
	//if (event.GetBool("teamonly")) return; //Ignore team chat (not working)
	char msg[64];
	event.GetString("text", msg, sizeof(msg));
	if (!strcmp(msg, "!heal"))
	{
		int price = GetConVarInt(sm_drzed_heal_price);
		//TODO: if (!price) healing is disabled. Silent? Noisy?
		PrintToChatAll("Welcome to Dr Zed's Mobile Clinic. Healing costs $%d.", price);
		int target = GetClientOfUserId(event.GetInt("userid"));
		//if (your_money < price) bail;
		//your_money -= price;
		int max_health = 100; //TODO: Should this be queried from somewhere?
		if (GetClientHealth(target) < max_health)
			SetEntityHealth(target, max_health);
	}
}
