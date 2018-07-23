#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <sdktools>

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

StringMap interesting_weapons;
char weapon_msgs[][64];
bool seen_weapon[64];
int num_interesting_weapons;

public void OnPluginStart()
{
	RegAdminCmd("sm_hello", Command_Hello, ADMFLAG_SLAY);
	HookEvent("player_say", Event_PlayerChat);
	HookEvent("item_purchase", Event_item_purchase);
	HookEvent("cs_intermission", reset_stats); //Seems to fire at the end of a match??
	HookEvent("announce_phase_end", reset_stats); //Seems to fire at halftime team swap
	//player_falldamage: report whenever anyone falls, esp for a lot of dmg
	//As per carnage.sp, convars are created by the Python script.
	CreateConVars();

	interesting_weapons = CreateTrie();
	int i = 0;
	SetTrieValue(interesting_weapons, "weapon_ak47", i, false); weapon_msgs[i++] = "There's an AK in the game!";
	num_interesting_weapons = i;
}

public Action Command_Hello(int client, int args)
{
	PrintToChatAll("Hello, world!");
	PrintToServer("Hello, server!");
	return Plugin_Handled;
}

public Action CS_OnCSWeaponDrop(int client, int weapon)
{
	char player[64]; GetClientName(client, player, sizeof(player));
	char cls[64]; GetEntityClassname(weapon, cls, sizeof(cls));
	char netcls[64]; GetEntityNetClass(weapon, netcls, sizeof(netcls));
	char edict[64]; GetEdictClassname(weapon, edict, sizeof(edict));
	PrintToServer("%s dropped weapon %d / %s / %s / %s", player, weapon, cls, netcls, edict);
}

public void reset_stats(Event event, const char[] name, bool dontBroadcast)
{
	PrintToServer("PURCHASE: Resetting stats");
	for (int i = 0; i < num_interesting_weapons; ++i) seen_weapon[i] = false;
}

public void Event_item_purchase(Event event, const char[] name, bool dontBroadcast)
{
	if (GameRules_GetProp("m_bWarmupPeriod")) return; //Ignore purchases made during warmup
	char weap[64]; event.GetString("weapon", weap, sizeof(weap));
	int idx;
	if (!GetTrieValue(interesting_weapons, weap, idx)) return;

	int buyer = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientInGame(buyer) || !IsPlayerAlive(buyer)) return;
	char player[64]; GetClientName(buyer, player, sizeof(player));
	PrintToServer("PURCHASE <%d>: %s bought %s [%s]",
		event.GetInt("team"), player, weap,
		seen_weapon[idx] ? "seen" : "new"
	);

	if (seen_weapon[idx]) return;
	seen_weapon[idx] = true;
	PrintToChatAll(weapon_msgs[idx]);
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
