#include <sourcemod>
#include <sdkhooks>
#include <cstrike>

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
		int target = GetClientOfUserId(event.GetInt("userid"));
		if (!IsClientInGame(target) || !IsPlayerAlive(target)) return;
		int price = GetConVarInt(sm_drzed_heal_price);
		if (!price) return; //Healing not available on this map/game mode/etc
		int max_health = 100; //TODO: Should this be queried from somewhere? Increase it if wearing hvy suit?
		if (GetClientHealth(target) >= max_health)
		{
			//Healing not needed. (Don't waste the player's money.)
			PrintToChat(target, "Next time you're bleeding to death, just think: !heal");
			return;
		}
		int money = GetEntProp(target, Prop_Send, "m_iAccount");
		if (money < price)
		{
			//Can't afford any healing. Awww.
			PrintToChat(target, "Welcome to Dr Zed's Mobile Clinic. Healing costs $%d.", price);
			return;
		}
		SetEntProp(target, Prop_Send, "m_iAccount", money - price);
		SetEntityHealth(target, max_health);
		PrintToChat(target, "Now go kill some enemies for me!"); //TODO: Different messages T and CT?
	}
}

#if 0
public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_GetMaxHealth, maxhealthcheck);
}
public Action maxhealthcheck(int entity, int &maxhealth)
{
	if (entity > MaxClients || !IsClientInGame(entity) || !IsPlayerAlive(entity) || IsFakeClient(entity)) return Plugin_Continue;
	//TODO: If you're wearing the Heavy Assault Suit, your max health is increased
	//(probably according to a cvar, which will default to 100). Also TODO: When
	//you *buy* the suit, your health is instantly filled to its new maximum.
	//maxhealth = 200;
	return Plugin_Changed;
}
#endif
