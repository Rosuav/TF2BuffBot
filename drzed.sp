#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <sdktools>

#pragma newdecls required
#pragma semicolon 1

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
ConVar sm_drzed_heal_freq_flyer = null; //(0) Every successful purchase of healing adds this to your max health
ConVar sm_drzed_suit_health_bonus = null; //(0) Additional HP gained when you equip the Heavy Assault Suit (also buffs heal_max while worn)
ConVar sm_drzed_gate_health_left = null; //(0) If nonzero, one-shots from full health will leave you on this much health
ConVar sm_drzed_gate_overkill = null; //(200) One-shots of at least this much damage (after armor) ignore the health gate
ConVar sm_drzed_crippled_health = null; //(0) If >0, you get this many hitpoints of extra health during which you're crippled.
ConVar sm_drzed_crippled_revive_count = null; //(4) When someone has been crippled, it takes this many knife slashes to revive them.
ConVar sm_drzed_hack = null; //(0) Activate some coded hack - actual meaning may change. Used for rapid development.
ConVar bot_autobuy_nades = null; //(1) Bots will buy more grenades than they otherwise might
#include "convars_drzed"

//Write something to the server console and also the live-stream display (if applicable)
//tail -f steamcmd_linux/csgo/csgo/server_chat.log
public void PrintToStream(const char[] fmt, any ...)
{
	char buffer[4096];
	VFormat(buffer, sizeof(buffer), fmt, 2);
	PrintToServer(buffer);
	File fp = OpenFile("server_chat.log", "a");
	WriteFileLine(fp, buffer);
	CloseHandle(fp);
}

StringMap weapon_names;
ConVar default_weapons[4];
ConVar ammo_grenade_limit_total;
Handle switch_weapon_call = null;

public void OnPluginStart()
{
	RegAdminCmd("zed_money", give_all_money, ADMFLAG_SLAY);
	HookEvent("player_say", Event_PlayerChat);
	HookEvent("weapon_fire", Event_weapon_fire);
	HookEvent("round_end", uncripple_all);
	//HookEvent("cs_intermission", reset_stats); //Seems to fire at the end of a match??
	//HookEvent("announce_phase_end", reset_stats); //Seems to fire at halftime team swap
	//player_falldamage: report whenever anyone falls, esp for a lot of dmg
	//As per carnage.sp, convars are created by the Python script.
	CreateConVars();

	weapon_names = CreateTrie();
	//Weapons not mentioned will be shown by their class names.
	//NOTE: Weapons that have alternates (P2000/USP-S, Deagle/R8) may be
	//distinguished by netprop m_iItemDefinitionIndex - see describe_weapon().
	//There are other qualities, including Strange/Stat-Trak, which can be
	//seen in netprop m_iEntityQuality.
	SetTrieString(weapon_names, "weapon_glock", "Glock");
	SetTrieString(weapon_names, "weapon_hkp2000", "*P2000/USP*");
	SetTrieString(weapon_names, "*P2000/USP*32", "P2000");
	SetTrieString(weapon_names, "*P2000/USP*61", "USP-S");
	SetTrieString(weapon_names, "weapon_p250", "*P250/CZ75a*");
	SetTrieString(weapon_names, "*P250/CZ75a*36", "P250");
	SetTrieString(weapon_names, "*P250/CZ75a*63", "CZ75a");
	SetTrieString(weapon_names, "weapon_elite", "Dualies");
	SetTrieString(weapon_names, "weapon_fiveseven", "Five-Seven");
	SetTrieString(weapon_names, "weapon_tec9", "Tec-9");
	SetTrieString(weapon_names, "weapon_deagle", "*Deagle/R8*");
	SetTrieString(weapon_names, "*Deagle/R8*1", "Deagle");
	SetTrieString(weapon_names, "*Deagle/R8*64", "R8");
	//SMGs
	SetTrieString(weapon_names, "weapon_mp9", "MP9");
	SetTrieString(weapon_names, "weapon_mp7", "*MP5/MP7*");
	SetTrieString(weapon_names, "*MP5/MP7*23", "MP5-SD");
	SetTrieString(weapon_names, "*MP5/MP7*33", "MP7");
	SetTrieString(weapon_names, "weapon_ump45", "UMP-45");
	SetTrieString(weapon_names, "weapon_p90", "P90");
	SetTrieString(weapon_names, "weapon_bizon", "PP-Bizon");
	SetTrieString(weapon_names, "weapon_mac10", "MAC-10");
	//Assault Rifles
	SetTrieString(weapon_names, "weapon_ak47", "AK-47");
	SetTrieString(weapon_names, "weapon_galilar", "Galil");
	SetTrieString(weapon_names, "weapon_famas", "FAMAS");
	SetTrieString(weapon_names, "weapon_m4a1", "*M4*");
	SetTrieString(weapon_names, "*M4*16", "M4A4");
	SetTrieString(weapon_names, "*M4*60", "M4A1-S");
	SetTrieString(weapon_names, "weapon_aug", "AUG");
	SetTrieString(weapon_names, "weapon_sg556", "SG-553");
	//Snipers
	SetTrieString(weapon_names, "weapon_ssg08", "Scout");
	SetTrieString(weapon_names, "weapon_awp", "AWP");
	SetTrieString(weapon_names, "weapon_scar20", "SCAR-20");
	SetTrieString(weapon_names, "weapon_g3sg1", "G3SG1");
	//Shotties
	SetTrieString(weapon_names, "weapon_nova", "Nova");
	SetTrieString(weapon_names, "weapon_xm1014", "XM1014");
	SetTrieString(weapon_names, "weapon_mag7", "MAG-7");
	SetTrieString(weapon_names, "weapon_sawedoff", "Sawed-Off");
	//Grenades
	SetTrieString(weapon_names, "weapon_hegrenade", "HE");
	SetTrieString(weapon_names, "hegrenade_projectile", "HE"); //The thrown grenade is a separate entity class from the wielded grenade
	SetTrieString(weapon_names, "weapon_molotov", "Molly"); //T-side
	SetTrieString(weapon_names, "weapon_incgrenade", "Molly"); //CT-side
	SetTrieString(weapon_names, "molotov_projectile", "Molly"); //Getting beaned with EITHER fire 'nade
	SetTrieString(weapon_names, "inferno", "Molly"); //The actual flames
	SetTrieString(weapon_names, "weapon_flashbang", "Flash"); //Non-damaging but you can still get beaned
	SetTrieString(weapon_names, "flashbang_projectile", "Flash");
	SetTrieString(weapon_names, "weapon_smokegrenade", "Smoke"); //Ditto
	SetTrieString(weapon_names, "smokegrenade_projectile", "Smoke");
	SetTrieString(weapon_names, "weapon_decoy", "Smoke"); //When wielded
	SetTrieString(weapon_names, "decoy_projectile", "Smoke"); //Beaning and also the tiny boom at the end
	//Other
	SetTrieString(weapon_names, "weapon_m249", "M249");
	SetTrieString(weapon_names, "weapon_negev", "Negev");
	SetTrieString(weapon_names, "weapon_taser", "Zeus x27");
	SetTrieString(weapon_names, "weapon_knife", "Knife");
	SetTrieString(weapon_names, "weapon_knifegg", "Gold Knife"); //Arms Race mode only
	SetTrieString(weapon_names, "weapon_c4", "C4"); //The carried C4
	SetTrieString(weapon_names, "planted_c4", "C4"); //When the bomb goes off.... bladabooooom

	default_weapons[0] = FindConVar("mp_ct_default_primary");
	default_weapons[1] = FindConVar("mp_t_default_primary");
	default_weapons[2] = FindConVar("mp_ct_default_secondary");
	default_weapons[3] = FindConVar("mp_t_default_secondary");
	ammo_grenade_limit_total = FindConVar("ammo_grenade_limit_total");

	Handle gamedata = LoadGameConfigFile("sdkhooks.games");
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "Weapon_Switch");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	switch_weapon_call = EndPrepSDKCall();
	delete gamedata;
}

public Action give_all_money(int initiator, int args)
{
	PrintToChatAll("Giving money to everyone!");
	for (int client = 1; client < MaxClients; ++client)
	{
		if (!IsClientInGame(client)) continue;
		int money = GetEntProp(client, Prop_Send, "m_iAccount") + 1000;
		PrintToChat(client, "You now have $%d", money);
		SetEntProp(client, Prop_Send, "m_iAccount", money);
	}
}

void describe_weapon(int weapon, char[] buffer, int bufsz)
{
	if (weapon == -1) {strcopy(buffer, bufsz, "(none)"); return;}
	GetEntityClassname(weapon, buffer, bufsz);
	GetTrieString(weapon_names, buffer, buffer, bufsz);
	if (buffer[0] == '*')
	{
		//It's a thing with variants. Get the variant descriptor and use
		//that instead/as well.
		Format(buffer[strlen(buffer)], bufsz - strlen(buffer), "%d",
			GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"));
		//If the variant is listed in the trie, transform it (again)
		GetTrieString(weapon_names, buffer, buffer, bufsz);
	}
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
   it is a default one (starter pistol). "BOT Opie: I'm dropping my AK-47".
2) "Someone drop me a weapon pls?" - the wealthiest bot, if any have enough
   to help, drops his current primary then buys either an M4A1 or an AK-47.
3) "Bots, buy nades" - all bots attempt to buy HE, Flash, Smoke, Molotov. A
   bot normally will buy only one nade per round. This is stupid. On freeze
   time start, all bots will automatically buy more nades; any human on the
   team can also request that bots have another shot at buying nades.
*/
public Action CS_OnCSWeaponDrop(int client, int weapon)
{
	if (client > MAXPLAYERS) return;
	if (!GameRules_GetProp("m_bFreezePeriod")) return; //Announce only during freeze time.
	if (!IsFakeClient(client)) return; //Don't force actual players to speak - it violates expectations.
	//Delay the actual message to allow a replacement weapon to be collected
	Handle params;
	CreateDataTimer(0.01, announce_weapon_drop, params, TIMER_FLAG_NO_MAPCHANGE);
	WritePackCell(params, client);
	WritePackCell(params, weapon);
	//Detect the slot that this weapon goes in by looking for it pre-drop.
	//This hook is executed prior to the drop actually happening, so the weapon should
	//still be in the character's inventory somewhere.
	for (int slot = 0; slot < 10; ++slot)
		if (GetPlayerWeaponSlot(client, slot) == weapon)
			WritePackCell(params, slot);
	WritePackCell(params, -1); //Should really only do this if the previous line never hit, but whatevs. An extra pack integer in the weird case.
	ResetPack(params);
}
Action announce_weapon_drop(Handle timer, Handle params)
{
	ignore(timer);
	int client = ReadPackCell(params);
	int weapon = ReadPackCell(params);
	int slot = ReadPackCell(params);
	if (!IsClientInGame(client) || !IsValidEntity(weapon)) return; //Map changed, player left, or something like that
	int newweap = GetPlayerWeaponSlot(client, slot); //Whatcha got now?
	if (newweap == weapon) return; //Dropped a weapon and instantly picked it up again (seems to happen in Short Demolition mode a lot)
	char player[64]; GetClientName(client, player, sizeof(player));
	char cls[64]; GetEntityClassname(weapon, cls, sizeof(cls));
	if (slot != 0 && slot != 1) return; //Ignore if not primary/secondary
	for (int i = 0; i < sizeof(default_weapons); ++i)
	{
		char ignoreme[64]; GetConVarString(default_weapons[i], ignoreme, sizeof(ignoreme));
		if (ignoreme[0] && !strcmp(cls, ignoreme)) return; //It's a default weapon.
	}
	describe_weapon(weapon, cls, sizeof(cls));
	char newcls[64] = "(nothing)";
	char command[256];
	if (newweap != -1)
	{
		//Normal case: the weapon was dropped because another was bought.
		describe_weapon(newweap, newcls, sizeof(newcls));
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

public Action CS_OnBuyCommand(int buyer, const char[] weap)
{
	if (!IsClientInGame(buyer) || !IsPlayerAlive(buyer)) return Plugin_Continue;
	//Disallow defusers during warmup (they're useless anyway)
	if (StrEqual(weap, "defuser") && GameRules_GetProp("m_bWarmupPeriod")) {PrintToServer("denied"); return Plugin_Stop;}
	if (StrEqual(weap, "heavyassaultsuit"))
	{
		//Crippling mode uses the suit, so when that's happening, you can't buy the suit.
		if (GetConVarInt(sm_drzed_crippled_health)) return Plugin_Stop;
		int hp = GetConVarInt(sm_drzed_suit_health_bonus);
		if (hp) SetEntityHealth(buyer, GetClientHealth(buyer) + hp);
	}
	return Plugin_Continue;
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
		int have_decoy = GetEntProp(client, Prop_Data, "m_iAmmo", _, 18);
		int total_nades = have_he + have_flash + have_smoke + have_molly + have_decoy;
		int max_nades = GetConVarInt(ammo_grenade_limit_total);
		int molly_price = team == 2 ? 400 : 600; //Incendiary grenades are overpriced for CTs
		money -= 1000; //Ensure that the bots don't spend below $1000 this way (just in case).
		int bought = 0;
		int which = -1;
		char nade_desc[][] = {"HE", "Flash", "Smoke", "Molly"};
		for (int i = 0; i < 7; ++i)
		{
			if (total_nades + bought >= max_nades) break;
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
		//TODO maybe: Delay a frame or two, then count total nades again.
		//Give the "Buying N grenades" message based on the difference
		//between that figure and total_nades from above.
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
	if (freeze && !last_freeze && GetConVarInt(bot_autobuy_nades))
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

int last_attacker[MAXPLAYERS+1], last_inflictor[MAXPLAYERS+1], last_weapon[MAXPLAYERS+1], crippled_status[MAXPLAYERS+1];
int is_crippled(int client)
{
	if (!GetConVarInt(sm_drzed_crippled_health)) return 0; //Crippling isn't active, so you aren't crippled.
	return GetEntProp(client, Prop_Send, "m_bHasHeavyArmor");
}
void kill_crippled_player(int client)
{
	//Finally kill the player (for any reason)
	int inflictor = last_inflictor[client], attacker = last_attacker[client], weapon = last_weapon[client];
	//If the attacker is no longer in the game, treat it as suicide. This
	//follows the precedent of a molly thrown by a ragequitter.
	if (!IsClientInGame(attacker)) attacker = client;
	//If the weapon is no longer in the game, sometimes you'll get credited
	//with the kill using a weird weapon. Most commonly, it'll say you killed
	//someone with your currently-wielded weapon, but you might sometimes see
	//"X killed Y with worldspawn" :)
	if (!IsValidEntity(inflictor)) inflictor = attacker;
	if (!IsValidEntity(weapon)) weapon = -1;
	SDKHooks_TakeDamage(client, inflictor, attacker, GetClientHealth(client) + 0.0, 0, weapon);
}
public Action remove_cripple_prot(Handle timer, int client) {crippled_status[client] = 0;}
public Action crippled_health_drain(Handle timer, int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || !is_crippled(client)) return Plugin_Stop;
	int health = GetClientHealth(client) - 1;
	if (health) SetEntityHealth(client, health); else kill_crippled_player(client);
	return Plugin_Continue;
}
void cripple(int client)
{
	if (!GetConVarInt(sm_drzed_crippled_health)) return;
	SetEntityHealth(client, GetConVarInt(sm_drzed_crippled_health));
	SetEntProp(client, Prop_Send, "m_bHasHeavyArmor", 1);
	SetEntProp(client, Prop_Send, "m_ArmorValue", 0);
	//Switch to knife. If you have no knife, you switch to a non-weapon.
	SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", GetPlayerWeaponSlot(client, 2));
	CreateTimer(0.2, crippled_health_drain, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	crippled_status[client] = -1; //Damage protection active.
	CreateTimer(1.0, remove_cripple_prot, client, TIMER_FLAG_NO_MAPCHANGE);
}
void uncripple(int client)
{
	if (!GetConVarInt(sm_drzed_crippled_health)) return;
	SetEntityHealth(client, GetConVarInt(sm_drzed_crippled_health) + 50);
	SetEntProp(client, Prop_Send, "m_bHasHeavyArmor", 0);
	SetEntProp(client, Prop_Send, "m_ArmorValue", 5);
	crippled_status[client] = -1; //Give damage protection again on revive
	CreateTimer(1.0, remove_cripple_prot, client, TIMER_FLAG_NO_MAPCHANGE);
	//In case you have no weapon, try to switch back.
	if (GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon")) for (int slot = 0; slot < 5; ++slot)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (weapon == -1) continue;
		SDKCall(switch_weapon_call, client, weapon, 0);
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
		break;
	}
}
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3],
	int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (is_crippled(client))
	{
		//While you're crippled, you can't do certain things. There may be more restrictions to add.
		if (buttons & IN_USE)
		{
			//Can't defuse the bomb or pick up weapons
			buttons &= ~IN_USE;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}
public void uncripple_all(Event event, const char[] name, bool dontBroadcast)
{
	//When the round ends, uncripple everyone. Winners get up, losers die.
	int winner = event.GetInt("winner");
	if (!winner) return;
	//NOTE: Crashes on startup if it looks at the very last player. So we don't.
	//No idea what's going on here - maybe the GOTV pseudo-player is bombing??
	for (int client = 1; client < MAXPLAYERS; ++client) if (IsClientInGame(client) && IsPlayerAlive(client) && is_crippled(client))
	{
		if (GetClientTeam(client) == winner) uncripple(client); else kill_crippled_player(client);
	}
}

int healthbonus[MAXPLAYERS + 1];
public void OnMapStart() {for (int i = 0; i <= MAXPLAYERS; ++i) healthbonus[i] = 0;}

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

		char cls[64]; describe_weapon(weap, cls, sizeof(cls));
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
		max_health += healthbonus[target];
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
		int increment = GetConVarInt(sm_drzed_heal_freq_flyer);
		healthbonus[target] += increment; max_health += increment;
		SetEntProp(target, Prop_Send, "m_iAccount", money - price);
		SetEntityHealth(target, max_health);
		PrintToChat(target, "Now go kill some enemies for me!"); //TODO: Different messages T and CT?
	}
}

//Max health doesn't seem very significant in CS:GO, since there's basically nothing that heals you.
//But we set the health on spawn too, so it ends up applying.
public void OnClientPutInServer(int client)
{
	healthbonus[client] = 0;
	SDKHook(client, SDKHook_GetMaxHealth, maxhealthcheck);
	SDKHook(client, SDKHook_SpawnPost, sethealth);
	SDKHook(client, SDKHook_OnTakeDamageAlive, healthgate);
	SDKHook(client, SDKHook_WeaponCanSwitchTo, weaponlock);
}
public Action maxhealthcheck(int entity, int &maxhealth)
{
	if (entity > MaxClients || !IsClientInGame(entity) || !IsPlayerAlive(entity)) return Plugin_Continue;
	maxhealth = GetConVarInt(sm_drzed_max_hitpoints) + GetConVarInt(sm_drzed_crippled_health);
	return Plugin_Changed;
}
void sethealth(int entity)
{
	if (entity > MaxClients || !IsClientInGame(entity) || !IsPlayerAlive(entity)) return;
	int health = GetConVarInt(sm_drzed_max_hitpoints);
	if (!health) health = 100; //TODO: Find out what the default would otherwise have been
	health += GetConVarInt(sm_drzed_crippled_health);
	SetEntityHealth(entity, health + healthbonus[entity]);
}

public Action healthgate(int victim, int &attacker, int &inflictor, float &damage, int &damagetype,
	int &weapon, float damageForce[3], float damagePosition[3])
{
	//Log all damage to a file that gets processed by a Python script
	int vicweap = GetEntPropEnt(victim, Prop_Send, "m_hActiveWeapon");
	char atkcls[64]; describe_weapon(weapon > 0 ? weapon : inflictor, atkcls, sizeof(atkcls));
	char viccls[64]; describe_weapon(vicweap, viccls, sizeof(viccls));
	int cap = GetClientHealth(victim);
	int score = RoundToFloor(damage);
	if (score >= cap) score = cap + 100; //100 bonus points for the kill, but the actual damage caps out at the health taken.
	int teamdmg = 0;
	if (attacker && attacker < MAXPLAYERS)
	{
		teamdmg = GetClientTeam(victim) == GetClientTeam(attacker);
		if (is_crippled(attacker) && !teamdmg)
		{
			//If you knife someone while you're crippled, you get a second wind.
			//Only applies to knife damage. You can't get a free second wind off
			//a molly or other delayed damage.
			if (!strcmp(atkcls, "Knife")) uncripple(attacker);
		}
		if (is_crippled(victim) && !teamdmg)
		{
			//If you take damage from an enemy while crippled, it can change
			//who gets the credit for finishing you off.
			last_attacker[victim] = attacker; last_inflictor[victim] = inflictor; last_weapon[victim] = weapon;
		}
	}
	File fp = OpenFile("weapon_scores.log", "a");
	WriteFileLine(fp, "%s %sdamaged %s for %d (%.0fhp)",
		atkcls, victim == attacker ? "self" : teamdmg ? "team" : "",
		viccls, score, damage);
	CloseHandle(fp);

	int cripplepoint = GetConVarInt(sm_drzed_crippled_health);
	//For one second after being crippled, you get damage immunity.
	if (cripplepoint && crippled_status[victim] == -1) {damage = 0.0; return Plugin_Changed;}
	if (teamdmg && attacker != victim && is_crippled(victim) && !strcmp(atkcls, "Knife"))
	{
		//Revival attempt - a teammate slashing you with a knife.
		//Yeah, let's call it surgical or something. Whatever.
		int revivecount = GetConVarInt(sm_drzed_crippled_revive_count);
		if (++crippled_status[victim] >= revivecount) {uncripple(victim); return Plugin_Stop;}
		//Even if it doesn't revive you, it'll give you some additional health
		//so you don't bleed out.
		int health = GetClientHealth(victim);
		int missing = cripplepoint - health;
		int gain = cripplepoint / revivecount;
		//Gain the lesser of half the missing health and a quarter of crippled health.
		if (gain > missing / 2) gain = missing / 2;
		SetEntityHealth(victim, health + gain);
		return Plugin_Stop;
	}

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
	//
	if (cripplepoint && !GameRules_GetProp("m_iRoundWinStatus"))
	{
		//Note that crippling, as a feature, is disabled once the
		//round is over. Insta-kill for exit frags.
		int oldhealth = GetClientHealth(victim);
		int newhealth = oldhealth - RoundToFloor(damage);
		if (oldhealth > cripplepoint && newhealth <= cripplepoint)
		{
			last_attacker[victim] = attacker; last_inflictor[victim] = inflictor; last_weapon[victim] = weapon;
			cripple(victim);
			return Plugin_Stop; //Returning Plugin_Stop doesn't seem to stop the damage event in all cases. Not sure why.
		}
	}
	//
	int gate = GetConVarInt(sm_drzed_gate_health_left);
	if (!gate) return Plugin_Continue; //Health gate not active
	int full = GetConVarInt(sm_drzed_max_hitpoints); if (!full) full = 100;
	full += GetConVarInt(sm_drzed_crippled_health);
	int health = GetClientHealth(victim);
	if (health < full) return Plugin_Continue; //Below the health gate
	int dmg = RoundToFloor(damage);
	if (dmg < health) return Plugin_Continue; //Wouldn't kill you
	char cls[64]; describe_weapon(weapon, cls, sizeof(cls));
	if (!strcmp(cls, "Knife")) return Plugin_Continue; //No health-gating knife backstabs
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
Action weaponlock(int client, int weapon)
{
	ignore(weapon);
	if (is_crippled(client)) return Plugin_Stop;
	return Plugin_Continue;
}
/*
Revival of Teammates mode:
* Everyone starts with 200 hp.
* If you have > 100 hp, any damage that would reduce you below 100 sets you to 100.
* While you have <= 100 hp, you are crippled, and lose 1hp every 0.1 seconds.
* Teammates can heal crippled players by knifing them. Once > 100 hp, no longer crippled.
* A crippled player is unable to fire any weapons, and is reduced to crawling speed.

NOTE: There can be weirdnesses if you toggle the heavy suit and you have some armor.
So don't do that. When you toggle on the suit, also wipe the armor to zero, and don't
allow the player to buy armor while in that state. In fact, don't allow buying any
equipment or weapons (nor picking them up).

NOTE: Incompatible with game modes using the heavy assault suit. If crippling is a
thing, heavyarmor purchases will simply be denied. Recommend setting the cvar
mp_weapons_allow_heavyassaultsuit to 1 to force the game to precache the appropriate
models and textures.

TODO: Test interaction btwn health gate and crippling.

TODO: Is it okay for a crippled person to revive another crippled person?

TODO: Unscope when crippled. It looks weird to be scoped with a knife.

TODO: When you pick up a bot, you get to primary for some reason. Why? Weird.
*/
