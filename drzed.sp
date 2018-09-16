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
ConVar sm_drzed_gate_health_left = null; //(0) If nonzero, one-shots from full health will leave you on this much health
ConVar sm_drzed_gate_overkill = null; //(200) One-shots of at least this much damage (after armor) ignore the health gate
ConVar sm_drzed_hack = null; //(0) Activate some coded hack - actual meaning may change. Used for rapid development.
#include "convars_drzed"

StringMap weapon_names;
ConVar default_weapons[4];
Handle switch_weapon_call = null;

public void OnPluginStart()
{
	RegAdminCmd("sm_hello", Command_Hello, ADMFLAG_SLAY);
	HookEvent("player_say", Event_PlayerChat);
	HookEvent("item_purchase", Event_item_purchase);
	HookEvent("weapon_fire", Event_weapon_fire);
	//HookEvent("cs_intermission", reset_stats); //Seems to fire at the end of a match??
	//HookEvent("announce_phase_end", reset_stats); //Seems to fire at halftime team swap
	//player_falldamage: report whenever anyone falls, esp for a lot of dmg
	//As per carnage.sp, convars are created by the Python script.
	CreateConVars();

	weapon_names = CreateTrie();
	//Weapons not mentioned will be shown by their class names.
	//NOTE: Weapons that have alternates (P2000/USP-S, Deagle/R8) may possibly be
	//distinguished by netprop m_iEntityQuality which appears to be 4 for the
	//non-stock item. There are other qualities, including Strange/Stat-Trak, and
	//I don't know how they interact.
	SetTrieString(weapon_names, "weapon_glock", "Glock");
	SetTrieString(weapon_names, "weapon_hkp2000", "P2000/USP");
	SetTrieString(weapon_names, "weapon_p250", "P250/CZ75a");
	SetTrieString(weapon_names, "weapon_elite", "Dualies");
	SetTrieString(weapon_names, "weapon_fiveseven", "Five-Seven");
	SetTrieString(weapon_names, "weapon_tec9", "Tec-9");
	SetTrieString(weapon_names, "weapon_deagle", "Deagle"); //or R8, but nobody uses that
	SetTrieString(weapon_names, "weapon_ak47", "AK-47");
	SetTrieString(weapon_names, "weapon_galilar", "Galil");
	SetTrieString(weapon_names, "weapon_famas", "FAMAS");
	SetTrieString(weapon_names, "weapon_m4a1", "M4"); //M4A4 or M4A1-S
	SetTrieString(weapon_names, "weapon_ssg08", "Scout");
	SetTrieString(weapon_names, "weapon_aug", "AUG");
	SetTrieString(weapon_names, "weapon_sg556", "SG-553");
	SetTrieString(weapon_names, "weapon_awp", "AWP");
	SetTrieString(weapon_names, "weapon_m249", "M249");
	SetTrieString(weapon_names, "weapon_negev", "Negev");
	SetTrieString(weapon_names, "weapon_scar20", "SCAR-20");
	SetTrieString(weapon_names, "weapon_g3sg1", "G3SG1");
	SetTrieString(weapon_names, "weapon_nova", "Nova");
	SetTrieString(weapon_names, "weapon_xm1014", "XM1014");
	SetTrieString(weapon_names, "weapon_mag7", "MAG-7");
	SetTrieString(weapon_names, "weapon_mac10", "MAC-10");
	SetTrieString(weapon_names, "weapon_mp9", "MP9");
	SetTrieString(weapon_names, "weapon_mp7", "MP5/MP7");
	SetTrieString(weapon_names, "weapon_ump45", "UMP-45");
	SetTrieString(weapon_names, "weapon_p90", "P90");
	SetTrieString(weapon_names, "weapon_bizon", "PP-Bizon");
	SetTrieString(weapon_names, "weapon_taser", "Zeus x27");

	default_weapons[0] = FindConVar("mp_ct_default_primary");
	default_weapons[1] = FindConVar("mp_t_default_primary");
	default_weapons[2] = FindConVar("mp_ct_default_secondary");
	default_weapons[3] = FindConVar("mp_t_default_secondary");

	Handle gamedata = LoadGameConfigFile("sdkhooks.games");
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "Weapon_Switch");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	switch_weapon_call = EndPrepSDKCall();
	delete gamedata;
}

public Action Command_Hello(int client, int args)
{
	PrintToChatAll("Hello, world!");
	PrintToServer("Hello, server!");
	return Plugin_Handled;
}

//Silence the warning "unused parameter"
any ignore(any ignoreme) {return ignoreme;}

/* Some of this would be better done by redefining the way bots buy gear; I
can't currently do this, so it's all done as chat commands.

In a real competitive match, you buy equipment *as a team*. You wait to see
what your teammates need before dropping all your money on stuff. But alas,
the bots are not such team players, and will barge ahead and make purchases
based solely on their own needs. While I can't make the bots truly act like
humans, I can at least (well, in theory, anyhow) make them a bit chattier -
make them tell you what they've already decided to do. That means the human
players don't spend valuable time panning around, trying to figure out what
the bots have done. This comes in a few varieties:

1) When a bot drops a weapon during freeze time, he will announce it unless
   it is a basic pistol. "BOT Opie: I'm dropping my AK-47".
2) "Someone drop me a weapon pls?" - the wealthiest bot, if any have enough
   to help, drops his current primary then buys either an M4A1 or an AK-47.
3) "Bots, buy nades" - all bots attempt to buy HE, Flash, Smoke, Molotov. A
   bot normally will buy only one nade per round. This is stupid.
*/
int dropped_weapon[MAXPLAYERS + 1];
public Action CS_OnCSWeaponDrop(int client, int weapon)
{
	if (client > MAXPLAYERS) return;
	if (!GameRules_GetProp("m_bFreezePeriod")) return; //Announce only during freeze time.
	if (!IsFakeClient(client)) return; //Don't force actual players to speak - it violates expectations.
	//Delay the actual message to allow a replacement weapon to be collected
	dropped_weapon[client] = weapon;
	CreateTimer(0.01, announce_weapon_drop, client, TIMER_FLAG_NO_MAPCHANGE);
	//DEBUG: For some reason, not all weapon drops are getting properly announced. Not sure why.
	//Code duplicated from the timer below.
	char player[64]; GetClientName(client, player, sizeof(player));
	char cls[64]; GetEntityClassname(weapon, cls, sizeof(cls));
	//This line *is* happening even when stuff is breaking.
	PrintToServer("BOT %s (%s) dropped a %s", player, GetClientTeam(client) == CS_TEAM_T ? "T" : "CT", cls);
}
Action announce_weapon_drop(Handle timer, any client)
{
	ignore(timer);
	if (!IsValidEntity(dropped_weapon[client])) return;
	char player[64]; GetClientName(client, player, sizeof(player));
	char cls[64]; GetEntityClassname(dropped_weapon[client], cls, sizeof(cls));
	if (!strcmp(cls, "weapon_c4")) return; //TODO: Once the slot check is implemented, ignore if not primary/secondary
	for (int i = 0; i < sizeof(default_weapons); ++i)
	{
		char ignoreme[64]; GetConVarString(default_weapons[i], ignoreme, sizeof(ignoreme));
		if (ignoreme[0] && !strcmp(cls, ignoreme)) return; //It's a default weapon.
	}
	GetTrieString(weapon_names, cls, cls, sizeof(cls)); //Transform and put back in the same buffer
	PrintToServer("==> BOT %s dropped a %s", player, cls);
	//TODO: Check which weapon slot this goes in. If it's not a primary weapon, ignore it.
	//Or alternatively: check the appropriate slot, rather than hard-coding Primary.
	int newweap = GetPlayerWeaponSlot(client, 0); //Whatcha got as your primary now?
	char newcls[64] = "(nothing)";
	char command[256];
	if (newweap != -1)
	{
		//Normal case: the weapon was dropped because another was bought.
		GetEntityClassname(newweap, newcls, sizeof(newcls));
		GetTrieString(weapon_names, newcls, newcls, sizeof(newcls));
		Format(command, sizeof(command), "say_team I'm dropping my %s in favour of this %s", cls, newcls);
	}
	else Format(command, sizeof(command), "say_team I'm dropping my %s", cls); //Theoretically they might not get a new weapon.
	FakeClientCommandEx(client, command);
	File fp = OpenFile("bot_weapon_drops.log", "a");
	char time[64]; FormatTime(time, sizeof(time), "%Y-%m-%d %H:%M:%S", GetTime());
	WriteFileLine(fp, "[%s] BOT %s dropped %s for %s", time, player, cls, newcls);
	CloseHandle(fp);
}

//If you throw a grenade and it's the only thing you have, unselect.
public void Event_weapon_fire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (GetPlayerWeaponSlot(client, 2) != -1) return; //Normally you'll have a knife, and things are fine.
	char weapon[64]; event.GetString("weapon", weapon, sizeof(weapon));
	int ammo_offset = 0;
	if (!strcmp(weapon, "weapon_hegrenade")) ammo_offset = 14;
	else if (!strcmp(weapon, "weapon_flashbang")) ammo_offset = 15;
	else if (!strcmp(weapon, "weapon_smokegrenade")) ammo_offset = 16;
	else if (!strcmp(weapon, "weapon_molotov") || !strcmp(weapon, "weapon_incgrenade")) ammo_offset = 17;
	else if (!strcmp(weapon, "weapon_decoy")) ammo_offset = 18;
	else return; //Wasn't a grenade you just threw.

	//Okay, you threw a grenade, and we know where to check its ammo.
	//Let's see if you have stock of anything else.
	if (GetPlayerWeaponSlot(client, 0) != -1) return; //Got a primary? All good.
	if (GetPlayerWeaponSlot(client, 1) != -1) return; //Got a pistol? All good.
	//Already checked knife above as our fast-abort.
	//Checking for a 'nade gives false positives.
	if (GetPlayerWeaponSlot(client, 5) != -1) return; //Got the C4? All good.

	//Do you have ammo of any other type of grenade?
	for (int offset = 14; offset <= 18; ++offset)
		if (offset != ammo_offset && GetEntProp(client, Prop_Data, "m_iAmmo", _, offset) > 0)
			//You have some other 'nade. Default behaviour is fine.
			return;

	//You don't have anything else. Unselect the current weapon, allowing you
	//to reselect your one and only grenade.
	CreateTimer(0.25, deselect_weapon, client, TIMER_FLAG_NO_MAPCHANGE);
}
Action deselect_weapon(Handle timer, any client)
{
	ignore(timer);
	SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", -1);
	//Ideally, I would like to now say "and select slot 4", but that doesn't seem
	//to work. It might also be possible to pick by a different slot (eg "slot7"
	//for flashbang), but I can't get that to work either.
	//ClientCommand(client, "use weapon_flashbang"); //This isn't reliable
	//ClientCommand(client, "slot4"); //This isn't reliable either but it miiiight work.
	//The below technique (supported by some setup code in OnPluginStart)
	//is courtesy of SHUFEN.jp on alliedmods.net forums. It appears to be
	//more reliable than ClientCommand. Validate it with usage, then nuke
	//all the other variants.
	int weapon = GetPlayerWeaponSlot(client, 3);
	if (weapon == -1) return;
	SDKCall(switch_weapon_call, client, weapon, 0);
	SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
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
}

void jayne(int team)
{
	if (!GameRules_GetProp("m_bFreezePeriod")) return; //Can only be done during freeze
	for (int client = 1; client < MaxClients; ++client)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || !IsFakeClient(client) || (team && GetClientTeam(client) != team)) continue;
		int money = GetEntProp(client, Prop_Send, "m_iAccount");
		int have_he = GetEntProp(client, Prop_Data, "m_iAmmo", _, 14);
		int have_flash = GetEntProp(client, Prop_Data, "m_iAmmo", _, 15);
		int have_smoke = GetEntProp(client, Prop_Data, "m_iAmmo", _, 16);
		int have_molly = GetEntProp(client, Prop_Data, "m_iAmmo", _, 17);
		//And decoys are in array position 18. TODO: Check for total grenades,
		//to avoid having the bots claim to have bought 3 nades when they had
		//2 already (will need to include decoys in that count).
		int molly_price = team == 2 ? 400 : 600; //Incendiary grenades are overpriced for CTs
		money -= 1000; //Ensure that the bots don't spend below $1000 this way (just in case).
		int bought = 0;
		int which = -1;
		char nade_desc[][] = {"HE", "Flash", "Smoke", "Molly"};
		for (int i = 0; i < 7; ++i)
		{
			switch (RoundToFloor(7*GetURandomFloat()))
			{
				//case 0: buy HE - handled by 'default' below
				case 1: if (!have_flash && money >= 200)
				{
					FakeClientCommandEx(client, "buy flashbang");
					money -= 200;
					++bought; ++have_flash;
					which = 1;
				}
				case 2: if (!have_smoke && money >= 300)
				{
					FakeClientCommandEx(client, "buy smoke");
					money -= 300;
					++bought; ++have_smoke;
					which = 2;
				}
				case 3: if (!have_molly && money >= molly_price)
				{
					FakeClientCommandEx(client, "buy molotov");
					money -= molly_price;
					++bought; ++have_molly;
					which = 3;
				}
				default: if (!have_he && money >= 300) //Higher chance of buying an HE
				{
					FakeClientCommandEx(client, "buy hegrenade");
					money -= 300;
					++bought; ++have_he;
					which = 0;
				}
			}
		}
		char botname[64]; GetClientName(client, botname, sizeof(botname));
		if (bought == 1) FakeClientCommandEx(client, "say_team Buying %s.", nade_desc[which]); //If only buying one, say which
		else if (bought) FakeClientCommandEx(client, "say_team Buying %d grenades.", bought);
	}
}
public Action buy_nades(Handle timer, any ignore) {jayne(0);}

//Note that the mark is global; one player can mark and another can check pos.
float marked_pos[3];
int show_positions[MAXPLAYERS + 1];
int nshowpos = 0;
int last_freeze = -1;
public void OnGameFrame()
{
	int freeze = GameRules_GetProp("m_bFreezePeriod");
	if (freeze && !last_freeze)
	{
		//When we go into freeze time, wait half a second, then get the bots to buy nades.
		//Note that they won't buy nades if we're out of freeze time, so you need at least
		//one full second of freeze in order to do this reliably.
		CreateTimer(0.5, buy_nades, 0, TIMER_FLAG_NO_MAPCHANGE);
	}
	last_freeze = freeze;

	for (int i = 0; i < nshowpos; ++i)
	{
		float pos[3]; GetClientAbsOrigin(show_positions[i], pos);
		float dist = GetVectorDistance(marked_pos, pos, false);
		PrintCenterText(show_positions[i], "Distance from marked pos: %.2f", dist);
	}
}

public void Event_PlayerChat(Event event, const char[] name, bool dontBroadcast)
{
	//if (!event.GetBool("teamonly")) return; //Require team chat (not working - there's no "teamonly" so it always returns 0)
	int self = GetClientOfUserId(event.GetInt("userid"));
	char msg[64];
	event.GetString("text", msg, sizeof(msg));
	if (!strcmp(msg, "!mark"))
	{
		GetClientAbsOrigin(self, marked_pos);
		PrintToChat(self, "Marked position: %f, %f, %f", marked_pos[0], marked_pos[1], marked_pos[2]);
		return;
	}
	if (!strcmp(msg, "!showpos"))
	{
		for (int i = 0; i < nshowpos; ++i) if (show_positions[i] == self)
		{
			PrintToChat(self, "Already showing pos each frame.");
			return;
		}
		show_positions[nshowpos++] = self;
		PrintToChat(self, "Will show pos each frame.");
		return;
	}
	if (!strcmp(msg, "!unshowpos"))
	{
		for (int i = 0; i < nshowpos; ++i) if (show_positions[i] == self)
		{
			show_positions[i] = show_positions[--nshowpos];
			PrintToChat(self, "Will no longer show pos each frame.");
			return;
		}
		PrintToChat(self, "Was not showing pos.");
		return;
	}
	if (!strcmp(msg, "!pos"))
	{
		float pos[3]; GetClientAbsOrigin(self, pos);
		float dist = GetVectorDistance(marked_pos, pos, false);
		PrintToChat(self, "Distance from marked pos: %.2f", dist);
		return;
	}
	if (!strcmp(msg, "!drop"))
	{
		//The wealthiest bot on your team will (1) drop primary weapon, then (2) buy M4A1.
		if (!GameRules_GetProp("m_bFreezePeriod")) return; //Can only be done during freeze
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
			PrintToChat(self, "No bots on your team have enough money to help");
			return;
		}
		char botname[64]; GetClientName(bot, botname, sizeof(botname));
		int weap = GetPlayerWeaponSlot(bot, 0);
		if (weap == -1)
		{
			//This can happen in bizarre situations such as playing a classic mode
			//on a map designed for a progressive mode (and thus having no buy area
			//but the bot does get money). Not a normal situation!
			PrintToChat(self, "BOT %s doesn't have a weapon to drop (????)", botname);
			return;
		}
		CS_DropWeapon(bot, weap, true, true);
		FakeClientCommandEx(bot, "buy m4a1");

		char cls[64]; GetEntityClassname(weap, cls, sizeof(cls));
		//Transform the class name to a human-readable name. Note that
		//the "boring" weapons in terms of regular drops aren't going
		//to happen this way, as they're just pistols.
		GetTrieString(weapon_names, cls, cls, sizeof(cls));
		FakeClientCommandEx(bot, "say_team Here, I'll drop this %s", cls);
		return;
	}
	if (!strcmp(msg, "!jayne"))
	{
		//It'd sure be nice if we had more grenades on the team!
		jayne(GetClientTeam(self));
		return;
	}
	if (!strcmp(msg, "!heal"))
	{
		int target = self; //Should players be able to request healing for each other? For now, no.
		if (!IsClientInGame(target) || !IsPlayerAlive(target)) return;
		int price = GetConVarInt(sm_drzed_heal_price);
		if (!price) return; //Healing not available on this map/game mode/etc
		//In theory, free healing could be a thing (since "no healing available" is best signalled
		//by setting heal_max to zero). Would have to figure out an alternate cost (score? earned
		//every time you get N kills?), but it's not fundamentally illogical on non-money modes.
		int max_health = GetConVarInt(sm_drzed_heal_max);
		if (GetEntProp(target, Prop_Send, "m_bHasHeavyArmor"))
			max_health += GetConVarInt(sm_drzed_suit_health_bonus);
		if (max_health <= 0) return; //Healing not available on this map/game mode/etc
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
	SDKHook(client, SDKHook_OnTakeDamageAlive, healthgate);
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

public Action healthgate(int victim, int &attacker, int &inflictor, float &damage, int &damagetype,
	int &weapon, float damageForce[3], float damagePosition[3])
{
	#if 0
	//(CLUB damage doesn't seem all that significant after all)
	if (damagetype & DMG_CLUB)
	{
		//Looks like someone got beaned with a 'nade.
		//NOTE: Not all grenade impacts have the CLUB type. I'm not sure how else
		//to recognize them; they have a type of zero and no weapon.
		if (IsValidEntity(weapon))
		{
			char cls[64]; GetEntityClassname(weapon, cls, sizeof(cls));
			PrintToChatAll("Attacker %d clubbed %d for %.0f \"<%X>\" damage with %s", attacker, victim, damage, damagetype, cls);
		}
		else PrintToChatAll("Attacker %d clubbed %d for %.0f \"<%X>\" damage without a weapon", attacker, victim, damage, damagetype);
	}
	#endif
	int hack = GetConVarInt(sm_drzed_hack);
	if (hack && attacker && attacker < MAXPLAYERS)
	{
		//Mess with damage based on who's dealing it. This is a total hack, and
		//can change at any time while I play around with testing stuff.
		if (hack == 2)
		{
			//Quickly prove that stuff is working
			if (IsFakeClient(attacker)) damage = 0.0; else damage = 100.0;
			return Plugin_Changed;
		}
		if (IsFakeClient(attacker)) return Plugin_Continue; //Example: Bots are unaffected
		//Example: Scale the damage according to how hurt you are
		//Like the TF2 Equalizer, but done as a simple scaling of all damage.
		int health = GetClientHealth(attacker) * 2;
		int max = GetConVarInt(sm_drzed_max_hitpoints); if (!max) max = 100; //TODO
		float factor = 2.0; //At max health, divide by this; at zero health, multiply by this.
		if (health > max) damage /= factor * (health - max) / max;
		else if (health < max) damage *= factor * health / max;
		return Plugin_Changed;
	}
	int gate = GetConVarInt(sm_drzed_gate_health_left);
	if (!gate) return Plugin_Continue; //Health gate not active
	int full = GetConVarInt(sm_drzed_max_hitpoints); if (!full) full = 100;
	int health = GetClientHealth(victim);
	if (health < full) return Plugin_Continue; //Below the health gate
	int dmg = RoundToFloor(damage);
	if (dmg < health) return Plugin_Continue; //Wouldn't kill you
	char cls[64]; GetEntityClassname(weapon, cls, sizeof(cls));
	if (!strcmp(cls, "weapon_knife")) return Plugin_Continue; //No health-gating knife backstabs
	GetTrieString(weapon_names, cls, cls, sizeof(cls));
	char name[64]; GetClientName(attacker, name, sizeof(name));
	int overkill = GetConVarInt(sm_drzed_gate_overkill);
	if (dmg >= overkill)
	{
		PrintToChat(victim, "BEWM! %s overkilled you with his %s (%d damage).", name, cls, dmg);
		return Plugin_Continue;
	}
	damage = 0.0 + health - gate; //Leave you on the health gate
	//NOTE: This won't change the denting of the armor. Probably doesn't matter; anything
	//that would be health gated is generally going to have high armor pen.
	PrintToChat(victim, "%s dealt %d with his %s, but you gated", name, dmg, cls);
	return Plugin_Changed;
}
