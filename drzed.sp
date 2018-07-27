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

ConVar sm_drzed_max_hitpoints = null; //(0) Number of hitpoints a normal character has (w/o Assault Suit) - 0 to leave at default
ConVar sm_drzed_heal_max = null; //(0) If nonzero, healing can be bought up to that many hitpoints (100 is normal maximum)
ConVar sm_drzed_heal_price = null; //(0) If nonzero, healing can be bought for that much money
ConVar sm_drzed_suit_health_bonus = null; //(0) Additional HP gained when you equip the Heavy Assault Suit (also buffs heal_max while worn)
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
	//This code doesn't really work properly, so I'm disabling it.
	//SetTrieValue(interesting_weapons, "weapon_ak47", i, false); seen_weapon[i] = false; weapon_msgs[i++] = "There's an AK in the game!";
	num_interesting_weapons = i;
}

public Action Command_Hello(int client, int args)
{
	PrintToChatAll("Hello, world!");
	PrintToServer("Hello, server!");
	return Plugin_Handled;
}

/* I have some plans here, but they're a fair way from fruition, so here are
some notes instead.

In a real competitive match, you buy equipment *as a team*. You wait to see
what your teammates need before dropping all your money on stuff. But alas,
the bots are not such team players, and will barge ahead and make purchases
based solely on their own needs. While I can't make the bots truly act like
humans, I can at least (well, in theory, anyhow) make them a bit chattier -
make them tell you what they've already decided to do. That means the human
players don't spend valuable time panning around, trying to figure out what
the bots have done. This comes in a few varieties:

1) The first time any "notable" weapon is purchased, announce it. Actually,
   this could be a cool thing to announce to the opposite team too; let the
   team brag "we have an AWPer among us".
2) Any time a weapon is dropped during the buy period (or maybe the freeze)
   by anyone on your team, announce it. "BOT Opie just dropped an AK-47".
3) "Someone drop me a weapon pls?" - the bot with the most money would drop
   the current primary, then buy a replacement according to his own rules.
4) "Bots, buy nades" - all bots attempt to buy HE, Flash, Smoke, Molotov. A
   bot normally will buy only one nade per round. This is stupid. TODO: See
   if the bots will actually use more nades if they have them.

The chat MUST be per-team. (Except maybe the "notable weapon" part.)
*/

public Action CS_OnCSWeaponDrop(int client, int weapon)
{
	if (!GameRules_GetProp("m_bFreezePeriod")) return; //Announce only during freeze time.
	char player[64]; GetClientName(client, player, sizeof(player));
	char cls[64]; GetEntityClassname(weapon, cls, sizeof(cls));
	char netcls[64]; GetEntityNetClass(weapon, netcls, sizeof(netcls));
	char edict[64]; GetEdictClassname(weapon, edict, sizeof(edict));
	PrintToServer("%s dropped weapon %d / %s / %s / %s", player, weapon, cls, netcls, edict);
	if (!IsFakeClient(client)) return;
	//TODO: Translate weapon IDs ("weapon_ak47") into names ("AK-47")
	//more intelligently than just ignoring the first seven characters
	//(esp since some things aren't "weapon_*"). Might also have some
	//items unannounced - we don't care when someone drops a Glock.
	char command[256]; Format(command, sizeof(command), "say_team I'm dropping my %s", cls[7]);
	FakeClientCommandEx(client, command);
}

public void reset_stats(Event event, const char[] name, bool dontBroadcast)
{
	//PrintToServer("PURCHASE: Resetting stats");
	for (int i = 0; i < num_interesting_weapons; ++i) seen_weapon[i] = false;
}

public void Event_item_purchase(Event event, const char[] name, bool dontBroadcast)
{
	int buyer = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientInGame(buyer) || !IsPlayerAlive(buyer)) return;
	char weap[64]; event.GetString("weapon", weap, sizeof(weap));
	if (StrEqual(weap, "item_heavyassaultsuit"))
	{
		int hp = GetConVarInt(sm_drzed_suit_health_bonus);
		if (hp) SetEntityHealth(buyer, GetClientHealth(buyer) + hp);
	}

	if (GameRules_GetProp("m_bWarmupPeriod")) return; //Other than the suit, ignore purchases made during warmup
	int idx;
	if (!GetTrieValue(interesting_weapons, weap, idx)) return;

	char player[64]; GetClientName(buyer, player, sizeof(player));
	PrintToServer("PURCHASE <%d>: %s bought %s [%s]",
		event.GetInt("team"), player, weap,
		seen_weapon[idx] ? "seen" : "new"
	);

	if (seen_weapon[idx]) return;
	seen_weapon[idx] = true;
	PrintToChatAll(weapon_msgs[idx]);
}

//Note that the mark is global; one player can mark and another can check pos.
float marked_pos[3];
public void Event_PlayerChat(Event event, const char[] name, bool dontBroadcast)
{
	//if (!event.GetBool("teamonly")) return; //Require team chat (not working)
	char msg[64];
	event.GetString("text", msg, sizeof(msg));
	if (!strcmp(msg, "!mark"))
	{
		int self = GetClientOfUserId(event.GetInt("userid"));
		GetClientAbsOrigin(self, marked_pos);
		PrintToChat(self, "Marked position: %f, %f, %f", marked_pos[0], marked_pos[1], marked_pos[2]);
		return;
	}
	if (!strcmp(msg, "!pos"))
	{
		int self = GetClientOfUserId(event.GetInt("userid"));
		float pos[3]; GetClientAbsOrigin(self, pos);
		float dist = GetVectorDistance(marked_pos, pos, false);
		PrintToChat(self, "Distance from marked pos: %.2f", dist);
		return;
	}
	if (!strcmp(msg, "!drop"))
	{
		//The wealthiest bot on your team will (1) drop primary weapon, then (2) buy M4A1.
		if (!GameRules_GetProp("m_bFreezePeriod")) return; //Can only be done during freeze
		int self = GetClientOfUserId(event.GetInt("userid"));
		int team = GetClientTeam(self);
		int bot = -1, topmoney = team == 2 ? 2700 : 3100; //Ensure that the bot can buy a replacement M4/AK
		for (int client = 1; client < MaxClients; ++client)
		{
			if (!IsClientInGame(client) || !IsPlayerAlive(client) || !IsFakeClient(client) || GetClientTeam(client) != team) continue;
			int money = GetEntProp(client, Prop_Send, "m_iAccount");
			if (money >= topmoney) {topmoney = money; bot = client;}
		}
		if (bot == -1)
		{
			//TODO: PrintToChatTeam (which doesn't exist)
			PrintToChatAll("No bots on your team have enough money to help");
			return;
		}
		char botname[64]; GetClientName(bot, botname, sizeof(botname));
		int weap = GetPlayerWeaponSlot(bot, 0);
		if (weap == -1)
		{
			//This can happen in bizarre situations such as playing a classic mode
			//on a map designed for a progressive mode (and thus having no buy area
			//but the bot does get money). Not a normal situation!
			PrintToChatAll("BOT %s doesn't have a weapon to drop (????)", botname);
			return;
		}
		char cls[64]; GetEntityClassname(weap, cls, sizeof(cls));
		CS_DropWeapon(bot, weap, true);
		FakeClientCommandEx(bot, "buy m4a1");
		PrintToChatAll("BOT %s dropped his %s", botname, cls[7]);
		return;
	}
	if (!strcmp(msg, "!jayne"))
	{
		//It'd sure be nice if we had more grenades on the team!
		if (!GameRules_GetProp("m_bFreezePeriod")) return; //Can only be done during freeze
		int self = GetClientOfUserId(event.GetInt("userid"));
		int team = GetClientTeam(self);
		for (int client = 1; client < MaxClients; ++client)
		{
			if (!IsClientInGame(client) || !IsPlayerAlive(client) || !IsFakeClient(client) || GetClientTeam(client) != team) continue;
			int money = GetEntProp(client, Prop_Send, "m_iAccount");
			int have_he = GetEntProp(client, Prop_Data, "m_iAmmo", _, 14);
			int have_flash = GetEntProp(client, Prop_Data, "m_iAmmo", _, 15);
			int have_smoke = GetEntProp(client, Prop_Data, "m_iAmmo", _, 16);
			int have_molly = GetEntProp(client, Prop_Data, "m_iAmmo", _, 17);
			//And decoys are in array position 18, but we don't care about them
			int molly_price = team == 2 ? 400 : 600; //Incendiary grenades are overpriced for CTs
			money -= 1000; //Ensure that the bots don't spend below $1000 this way (just in case).
			int bought = 0;
			for (int i = 0; i < 7; ++i)
			{
				switch (RoundToFloor(7*GetURandomFloat()))
				{
					case 0: i = 10; //Chance to end purchases immediately
					case 1: if (!have_flash && money >= 200)
					{
						FakeClientCommandEx(client, "buy flashbang");
						money -= 200;
						++bought; ++have_flash;
					}
					case 2: if (!have_smoke && money >= 300)
					{
						FakeClientCommandEx(client, "buy smoke");
						money -= 300;
						++bought; ++have_smoke;
					}
					case 3: if (!have_molly && money >= molly_price)
					{
						FakeClientCommandEx(client, "buy molotov");
						money -= molly_price;
						++bought; ++have_molly;
					}
					default: if (!have_he && money >= 300) //Higher chance of buying an HE
					{
						FakeClientCommandEx(client, "buy hegrenade");
						money -= 300;
						++bought; ++have_he;
					}
				}
			}
			char botname[64]; GetClientName(client, botname, sizeof(botname));
			if (bought) PrintToChatAll("BOT %s bought %d grenades.", botname, bought);
		}
		return;
	}
	if (!strcmp(msg, "!heal"))
	{
		int target = GetClientOfUserId(event.GetInt("userid"));
		if (!IsClientInGame(target) || !IsPlayerAlive(target)) return;
		int price = GetConVarInt(sm_drzed_heal_price);
		if (!price) return; //Healing not available on this map/game mode/etc
		//In theory, free healing could be a thing (since "no healing available" is best signalled
		//by setting heal_max to zero). Would have to figure out an alternate cost (score? earned
		//every time you get N kills?), but it's not fundamentally illogical on non-money modes.
		int max_health = GetConVarInt(sm_drzed_heal_max);
		if (GetEntProp(target, Prop_Send, "m_bHasHeavyArmor"))
			max_health += GetConVarInt(sm_drzed_suit_health_bonus);
		if (!max_health) return; //Healing not available on this map/game mode/etc
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

//Max health doesn't seem very significant in CS:GO, since there's basically nothing that heals you.
//But we set the health on spawn too, so it ends up applying.
public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_GetMaxHealth, maxhealthcheck);
	SDKHook(client, SDKHook_SpawnPost, sethealth);
}
public Action maxhealthcheck(int entity, int &maxhealth)
{
	if (entity > MaxClients || !IsClientInGame(entity) || !IsPlayerAlive(entity)) return Plugin_Continue;
	maxhealth = GetConVarInt(sm_drzed_max_hitpoints);
	return Plugin_Changed;
}
void sethealth(int entity)
{
	if (entity > MaxClients || !IsClientInGame(entity) || !IsPlayerAlive(entity)) return;
	int health = GetConVarInt(sm_drzed_max_hitpoints);
	if (health) SetEntityHealth(entity, health);
}
