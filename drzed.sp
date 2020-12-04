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

//Note: To regenerate netprops.txt, go into the server and run: sm_dump_netprops netprops.txt
//then excise uninteresting data with: sed -i 's/(offset [0-9]*) //' steamcmd_linux/csgo/csgo/netprops.txt

ConVar sm_drzed_max_hitpoints = null; //(0) Number of hitpoints a normal character has (w/o Assault Suit) - 0 to leave at default
ConVar sm_drzed_heal_max = null; //(0) If nonzero, healing can be bought up to that many hitpoints (100 is normal maximum)
ConVar sm_drzed_heal_price = null; //(0) If nonzero, healing can be bought for that much money
ConVar sm_drzed_heal_freq_flyer = null; //(0) Every successful purchase of healing adds this to your max health
ConVar sm_drzed_heal_cooldown = null; //(15) After buying healing, you can't buy more for this many seconds.
ConVar sm_drzed_heal_damage_cd = null; //(2.5) Healing is available only when you've been out of combat for X seconds (taking no damage).
ConVar sm_drzed_suit_health_bonus = null; //(0) Additional HP gained when you equip the Heavy Assault Suit (also buffs heal_max while worn)
ConVar sm_drzed_gate_health_left = null; //(0) If nonzero, one-shots from full health will leave you on this much health
ConVar sm_drzed_gate_overkill = null; //(200) One-shots of at least this much damage (after armor) ignore the health gate
ConVar sm_drzed_crippled_health = null; //(0) If >0, you get this many hitpoints of extra health during which you're crippled.
ConVar sm_drzed_crippled_revive_count = null; //(4) When someone has been crippled, it takes this many knife slashes to revive them.
ConVar sm_drzed_crippled_speed = null; //(50) A crippled person moves no faster than this (knife = 250, Negev = 150, scoped AWP = 100)
ConVar sm_drzed_max_anarchy = null; //(0) Maximum Anarchy stacks - 0 to disable anarchy
ConVar sm_drzed_anarchy_bonus = null; //(5) Percent bonus to damage per anarchy stack. There's no accuracy penalty though.
ConVar sm_drzed_anarchy_kept_on_death = null; //(0) Percentage of anarchy stacks saved on death (rounded down).
ConVar sm_drzed_anarchy_per_kill = null; //(0) Whether you gain anarchy for getting a kill
ConVar sm_drzed_hack = null; //(0) Activate some coded hack - actual meaning may change. Used for rapid development.
ConVar sm_drzed_allow_recall = null; //(0) Set to 1 to enable !recall and !recall2.
ConVar sm_drzed_admin_chat_name = null; //("") Name of admin for chat purposes
ConVar bot_autobuy_nades = null; //(1) Bots will buy more grenades than they otherwise might
ConVar bots_get_empty_weapon = null; //("") Give bots an ammo-less weapon on startup (eg weapon_glock). Use only if they wouldn't get a weapon in that slot.
ConVar bot_purchase_delay = null; //(0.0) Delay bot primary weapon purchases by this many seconds
ConVar damage_scale_humans = null; //(1.0) Scale all damage dealt by humans
ConVar damage_scale_bots = null; //(1.0) Scale all damage dealt by bots
ConVar learn_smoke = null; //(0) Show information on smoke throws and where they pop
ConVar learn_stutterstep = null; //(0) Show information on each shot fired to help you master stutter-stepping
ConVar bomb_defusal_puzzles = null; //(0) Issue this many puzzles before allowing the bomb to be defused (can't be changed during a round)
ConVar insta_respawn_damage_lag = null; //(0) Instantly respawn on death, with this many seconds of damage immunity and inability to fire
ConVar guardian_underdome_waves = null; //(0) Utilize Underdome rules
ConVar limit_fire_rate = null; //(0) If nonzero, guns cannot fire faster than N rounds/minute; if 1, will show fire rate each shot.
ConVar autosmoke_pitch_min = null; //("0.0") Hold +alt1 to autothrow smokes
ConVar autosmoke_pitch_max = null; //("0.0") Hold +alt1 to autothrow smokes
ConVar autosmoke_pitch_delta = null; //(0.0) Hold +alt1 to autothrow smokes
ConVar autosmoke_yaw_min = null; //("0.0") Hold +alt1 to autothrow smokes
ConVar autosmoke_yaw_max = null; //("0.0") Hold +alt1 to autothrow smokes
ConVar autosmoke_yaw_delta = null; //(0.0) Hold +alt1 to autothrow smokes
ConVar bot_placement = null; //("") Place bots at these exact positions, on map/round start or cvar change
ConVar disable_warmup_arenas = null; //(0) If 1, will disable the 1v1 warmup scripts

ConVar default_weapons[4];
ConVar ammo_grenade_limit_total, mp_guardian_special_weapon_needed, mp_guardian_special_kills_needed;
ConVar weapon_recoil_scale, mp_damage_vampiric_amount;
ConVar mp_damage_scale_ct_head, mp_damage_scale_t_head, mp_damage_scale_ct_body, mp_damage_scale_t_body;
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
StringMap weapon_is_primary;
StringMap weapondata_index; //weapondata_item_name[index] mapped to index
#include "cs_weapons.inc"
Handle switch_weapon_call = null;

//For anything that needs default health, we'll use this. Any time a character spawns,
//we update the default health. To my knowledge, as of 20190117, the only change to a
//player's max health is done by the game mode (Danger Zone has a default health of
//120), and is applied to every player, so it's not going to break things to have a
//single global default (which will be updated on map change once someone spawns).
int default_health = 100;

//Note that the mark is global; one player can mark and another can check pos.
float marked_pos[3];
float marked_pos2[3];
float marked_angle[3];
float marked_angle2[3];
int show_positions[MAXPLAYERS + 1];
int nshowpos = 0;
int last_freeze = -1;
int freeze_started = 0;
int last_money[MAXPLAYERS + 1];

//Crippling is done by reducing your character's max speed. Uncrippling means getting
//you back to "normal" speed. In most situations, it won't matter exactly what this
//speed is, as long as it's no less than your weapon's speed; as of 20190121, the top
//speed available is 260 from having nothing equipped (or Bare Fists in Danger Zone).
//(The highest speed in normally-configured classic modes is 250 with the knife/C4.)
//TODO: Ascertain the actual default speed instead of assuming
#define BASE_SPEED 260.0

public void OnPluginStart()
{
	RegAdminCmd("zed_money", give_all_money, ADMFLAG_SLAY);
	RegAdminCmd("chat", admin_chat, ADMFLAG_SLAY);
	HookEvent("player_say", Event_PlayerChat);
	HookEvent("weapon_fire", Event_weapon_fire);
	HookEvent("round_start", round_started);
	HookEvent("round_end", uncripple_all);
	HookEvent("bomb_planted", record_planter);
	HookEvent("smokegrenade_detonate", smoke_popped);
	HookEvent("grenade_bounce", smoke_bounce);
	HookEvent("player_team", player_team);
	HookEvent("weapon_reload", weapon_reload);
	HookEvent("player_jump", player_jump);
	HookEvent("bomb_begindefuse", puzzle_defuse);
	HookEvent("bomb_defused", show_defuse_time);
	HookEvent("player_use", player_use);
	HookEvent("player_death", player_death);

	//HookEvent("player_hurt", player_hurt);
	//HookEvent("cs_intermission", reset_stats); //Seems to fire at the end of a match??
	//HookEvent("announce_phase_end", reset_stats); //Seems to fire at halftime team swap
	//player_falldamage: report whenever anyone falls, esp for a lot of dmg
	AddCommandListener(player_pinged, "player_ping");
	//As per carnage.sp, convars are created by the Python script.
	CreateConVars();
	HookConVarChange(bot_placement, update_bot_placements);

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
	SetTrieString(weapon_names, "weapon_decoy", "Decoy"); //When wielded
	SetTrieString(weapon_names, "decoy_projectile", "Decoy"); //Beaning and also the tiny boom at the end
	//Other
	SetTrieString(weapon_names, "weapon_m249", "M249");
	SetTrieString(weapon_names, "weapon_negev", "Negev");
	SetTrieString(weapon_names, "weapon_taser", "Zeus x27");
	SetTrieString(weapon_names, "weapon_knife", "Knife");
	SetTrieString(weapon_names, "weapon_knifegg", "Gold Knife"); //Arms Race mode only
	SetTrieString(weapon_names, "weapon_c4", "C4"); //The carried C4
	SetTrieString(weapon_names, "planted_c4", "C4"); //When the bomb goes off.... bladabooooom

	weapon_is_primary = CreateTrie();
	//Weapons not mentioned are not primary weapons. If the mapped value is 2, say "an %s".
	//SMGs
	SetTrieValue(weapon_is_primary, "mp9", 2);
	SetTrieValue(weapon_is_primary, "mp7", 2);
	SetTrieValue(weapon_is_primary, "ump45", 1);
	SetTrieValue(weapon_is_primary, "p90", 1);
	SetTrieValue(weapon_is_primary, "bizon", 1);
	SetTrieValue(weapon_is_primary, "mac10", 1);
	//Assault Rifles
	SetTrieValue(weapon_is_primary, "ak47", 2);
	SetTrieValue(weapon_is_primary, "galilar", 1);
	SetTrieValue(weapon_is_primary, "famas", 1);
	SetTrieValue(weapon_is_primary, "m4a1", 2);
	SetTrieValue(weapon_is_primary, "m4a1_silencer", 2);
	SetTrieValue(weapon_is_primary, "aug", 2);
	SetTrieValue(weapon_is_primary, "sg556", 1);
	//Snipers
	SetTrieValue(weapon_is_primary, "ssg08", 2);
	SetTrieValue(weapon_is_primary, "awp", 2);
	SetTrieValue(weapon_is_primary, "scar20", 1);
	SetTrieValue(weapon_is_primary, "g3sg1", 1);
	//Shotties and LMGs
	SetTrieValue(weapon_is_primary, "nova", 1);
	SetTrieValue(weapon_is_primary, "xm1014", 2);
	SetTrieValue(weapon_is_primary, "mag7", 1);
	SetTrieValue(weapon_is_primary, "m249", 2);
	SetTrieValue(weapon_is_primary, "negev", 1);

	//Build a reverse lookup. Given an item name, find all its other details (price, max speed, etc).
	weapondata_index = CreateTrie();
	for (int i = 0; i < sizeof(weapondata_item_name); ++i) {SetTrieValue(weapondata_index, weapondata_item_name[i], i);}

	//Not handled by the automated system as it's easier if we can loop over these
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

public Action admin_chat(int client, int args)
{
	char text[512]; GetCmdArgString(text, sizeof(text));
	char admin[32]; GetConVarString(sm_drzed_admin_chat_name, admin, sizeof(admin));
	ReplyToCommand(client, "%s: %s", admin, text);
	PrintToChatAll(" \x04%s : \x01%s", admin, text); //Chat is in green, distinct from both team colours
	return Plugin_Handled;
}

//Not quite perfectly uniform. If there's a better way, it can be changed here.
int randrange(int max) {return RoundToFloor(GetURandomFloat() * max);}

int nonrandom_numbers[] = {
	4, //Number of puzzles minus one
	2, //"How many total Shotguns do I have here?" -- just count 'em (7)
	0, 1,
	3, //"Find my largest magazine fully Automatic gun. How many shots till I reload?" -- it's a Galil (35)
	0, 8, 1,
	2, //"How many distinct Pistols do I have here?" -- count unique items (5)
	1, 0,
	0, //"This is my SMG. There are none quite like it. How well does it penetrate armor?" -- it's an MP9 (60)
	2, 2,
	0, //"This is my Shotgun. There are none quite like it. How many shots till I reload?" -- it's a Nova (8)
	1, 0,
};
int next_nonrandom = -1;
int randctrl(int max)
{
	if (next_nonrandom != -1)
	{
		int ret = nonrandom_numbers[next_nonrandom++];
		if (next_nonrandom >= sizeof(nonrandom_numbers)) next_nonrandom = -1;
		if (ret < max) return ret; //If the forced one is out of bounds, ignore it.
	}
	return RoundToFloor(GetURandomFloat() * max);
}

int bomb_planter = -1;
public void record_planter(Event event, const char[] name, bool dontBroadcast)
{
	bomb_planter = GetClientOfUserId(event.GetInt("userid"));
}

public Action give_all_money(int initiator, int args)
{
	bool nobots = false;
	if (args)
	{
		char arg[64]; GetCmdArg(1, arg, sizeof(arg));
		if (!strcmp(arg, "humans")) {nobots = true; PrintToChatAll("Giving money to all humans!");}
	}
	if (!nobots) PrintToChatAll("Giving money to everyone!");
	for (int client = 1; client < MaxClients; ++client)
	{
		if (!IsClientInGame(client)) continue;
		if (nobots && IsFakeClient(client)) continue;
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

int anarchy[66];
int anarchy_available[66];
Action add_anarchy(Handle timer, any client)
{
	ignore(timer);
	//Check if the player (or maybe the weapon) has drawn blood.
	//~ PrintToStream("Potentially adding anarchy: av %d", anarchy_available[client]);
	if (!anarchy_available[client]) return;
	anarchy_available[client] = 0; anarchy[client]++;
	char player[64]; GetClientName(client, player, sizeof(player));
	PrintCenterText(client, "You now have %d anarchy!", anarchy[client]);
}

//Position and orient a bot (technically any client) based on 3-6 floats separated by commas
void place_bot(int bot, const char[] position)
{
	char posstr[7][20];
	int numpos = ExplodeString(position, ",", posstr, sizeof(posstr), sizeof(posstr[]));
	if (numpos < 3) return; //Broken, ignore
	float pos[3], ang[3] = {0.0, 0.0, 0.0};
	int n = 0;
	if (numpos >= 4 && StrEqual(posstr[n], "T" )) {ChangeClientTeam(bot, 2); n++;}
	else if (numpos >= 4 && StrEqual(posstr[n], "CT")) {ChangeClientTeam(bot, 3); n++;}
	else ChangeClientTeam(bot, 2); //Default to T side bots if it's not specified. I think things bug out if there's no team set.
	for (int i = 0; i < 3; ++i) pos[i] = StringToFloat(posstr[n++]);
	for (int i = 0; i < 3 && n < numpos; ++i) ang[i] = StringToFloat(posstr[n++]);
	float not_moving[3] = {0.0, 0.0, 0.0};
	//PrintToStream("Moving bot %d to location %.1f,%.1f,%.1f / %.1f,%.1f,%.1f", bot,
	//	pos[0], pos[1], pos[2], ang[0], ang[1], ang[2]);
	TeleportEntity(bot, pos, ang, not_moving);
}

public void update_bot_placements(ConVar cvar, const char[] previous, const char[] locations)
{
	if (!strlen(locations)) return;
	//PrintToStream("update_bot_placements from '%s' to '%s'", previous, locations);
	//Is there any sscanf-like function in SourcePawn?
	//Absent such, we fracture the string, then fracture each part, then parse.
	//In Pike, this would be (array(array(float)))((locations/" ")[*]/",")
	char spots[MAXPLAYERS + 1][128];
	int numbots = ExplodeString(locations, " ", spots, sizeof(spots), sizeof(spots[]));
	while (numbots && !strlen(spots[numbots - 1])) --numbots; //Trim off any empties at the end
	int p = 0;
	for (int bot = 1; bot < MAXPLAYERS; ++bot)
		if (IsClientInGame(bot) && IsPlayerAlive(bot) && IsFakeClient(bot))
		{
			//Update bot position. If we've run out of numbots, kick the bot,
			//otherwise set its position to the next one.
			if (p >= numbots)
			{
				//PrintToStream("Kicking bot %d, excess to requirements", bot);
				KickClient(bot, "You have been made redundant");
				continue;
			}
			place_bot(bot, spots[p++]);
		}
	while (p < numbots)
	{
		//PrintToStream("Adding a bot %d", p);
		char name[64]; Format(name, sizeof(name), "Target %d", p + 1);
		int bot = CreateFakeClient(name);
		SetEntityFlags(bot, GetEntityFlags(bot) | FL_ATCONTROLS);
		damage_lag_immunify(bot, 1.0);
		place_bot(bot, spots[p++]);
	}
}

public void SmokeLog(const char[] fmt, any ...)
{
	char buffer[4096];
	VFormat(buffer, sizeof(buffer), fmt, 2);
	File fp = OpenFile("learn_smoke.log", "a");
	WriteFileLine(fp, buffer);
	CloseHandle(fp);
}

//Would it be better to have six float cvars to define the box??
#define SMOKE_TARGETS 5
float smoke_targets[SMOKE_TARGETS][2][3] = { //Unfortunately the size has to be specified :(
	//Dust II
	//- Xbox
	{{-400.0, 1350.0, -27.0}, {-257.0, 1475.0, -24.0}},
	//- Long A Corner
	{{1186.0, 1082.0, -4.0}, {1304.0, 1260.0, 3.0}},
	//- B site Window
	{{-1437.0, 2591.0, 108.0}, {-1250.0, 2723.0, 130.0}},
	//- CT spawn (the Mid side, good for pushing into B site)
	{{-251.0, 2090.0, -126.0}, {-115.0, 2175.0, -122.0}},
	//- A site - protects a Long push from Goose, Site, and nearby areas
	{{1064.0, 2300.0, 97.0}, {1284.0, 2625.0, 131.0}},
	//Add others as needed - {{x1,y1,z1},{x2,y2,z2}} where the
	//second coords are all greater than the firsts.
};
char smoke_target_desc[][] = {
	"Xbox smoke! ", "Corner smoke! ", "Window smoke! ", "CT spawn! ", "A site! "
};
/*
* Blue box: From the passageway from backyard into tuns, standing throw between the rafters (middle of opening).
  - Precise position depends how far left/right you stand; optimal is about 75% right.
* Site: From the same passageway, hug the left wall (somewhere near the tuft of grass), and throw through the same hole.
* Car: Same passageway, hug left wall, come all the way to the arch (but not the freestanding pillar). Same hole, aim parallel to the top corrugated iron.
* Alt site: From the ambush nook just in tuns proper, aim into the biggest opening, on the right edge of it.
* Doors: Jump past the AWPer at blue box, get all the way to the corner. Aim into the rectangular gap, in the middle of the long side (left).
  - Alternatively, hug the edge of the ambush nook, aim parallel to main corrugated iron, standing throw.
* Window: No standing throw found. Various moving and jumping throws possible.
  - Get past the AWPer and into the corner. Hug the far wall (not the rear wall towards T spawn). Aim onto the dark spot above the door.
    Then hold a crouch; your crosshair should be just above the corner of the door crease. Jump throw.
    Eye angles -25.54,67.50 will work. It's fairly precise and hard to describe, takes practice.
* Flagstones: Stand btwn white angled box and pillar, aim into opening below stonework (left of ctr for safety)
  - This partly smokes off Window
* Alternate car: Stand ON the white box, up against the pillar, on top of the wood slat. Aim through the hole, about two thirds down, a tad to the right.
*/
#define SMOKE_BOUNCE_TARGETS 1
float smoke_first_bounce[SMOKE_BOUNCE_TARGETS][2][3] = {
	//1: Dust II Xbox
	//NOTE: If the bounce is extremely close to the wall (-265 to -257), the
	//smoke will bounce off the wall and miss. The actual boundary is somewhere
	//between -260 and -265.
	//(-309.23, 1135.53, -84.53) failed. Might be necessary to adjust the boundary.
	{{-321.0, 1130.0, -120.0}, {-265.0, 1275.0, -80.0}},
};

public void smoke_popped(Event event, const char[] name, bool dontBroadcast)
{
	if (!GetConVarInt(learn_smoke)) return;
	float x = event.GetFloat("x"), y = event.GetFloat("y"), z = event.GetFloat("z");
	int client = GetClientOfUserId(event.GetInt("userid"));
	int target = -1;
	//TODO: Look at the map name and pick a block of target boxes. Or maybe
	//not - what are the chances that two maps will have important smoke
	//targets that overlap?
	for (int i = 0; i < SMOKE_TARGETS; ++i)
	{
		//Is there an easier way to ask if a point is inside a cube?
		if (smoke_targets[i][0][0] < x && x < smoke_targets[i][1][0] &&
			smoke_targets[i][0][1] < y && y < smoke_targets[i][1][1] &&
			smoke_targets[i][0][2] < z && z < smoke_targets[i][1][2])
				target = i;
	}
	PrintToChat(client, "%sYour smoke popped at (%.2f, %.2f, %.2f)",
		target >= 0 ? smoke_target_desc[target] : "",
		x, y, z);
	SmokeLog("[%d-E-%d] Pop (%.2f, %.2f, %.2f) - %s", client,
		event.GetInt("entityid"),
		x, y, z, target >= 0 ? "GOOD" : "FAIL");
}

/*
To learn to aim:
1) Record eye positions for weapon_fire if smokegrenade
2) If on_target, print eye positions
3) Can probably dial in a "rectangle" of valid eye positions that have the potential to be on_target

Is it possible to trace a ray through every eye position that succeeds and put a dot on the screen??
Maybe mark that in response to player_ping.
*/

bool smoke_not_bounced[4096];
public void smoke_bounce(Event event, const char[] name, bool dontBroadcast)
{
	if (!GetConVarInt(learn_smoke)) return;
	int client = GetClientOfUserId(event.GetInt("userid"));
	float x = event.GetFloat("x"), y = event.GetFloat("y"), z = event.GetFloat("z"); //Undocumented event parameters!
	//So, this is where things get REALLY stupid
	//I want to know if this is the *first* bounce. Unfortunately, there's no
	//entity ID in the event. So... we search the entire server for any smoke
	//grenade projectiles. (I've no idea how to reliably expand this to other
	//grenade types.) If we find that there's an entity at the exact same pos
	//as the bounce sound just emanated from, then we have found it. Then, we
	//look that up in a table of known grenades, and if we haven't reported a
	//bounce for it yet, we flag it and report it. (TODO on that last bit.)
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "smokegrenade_projectile")) != -1)
	{
		float pos[3]; GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
		if (pos[0] == x && pos[1] == y && pos[2] == z)
		{
			if (smoke_not_bounced[ent])
			{
				smoke_not_bounced[ent] = false;
				bool on_target = false;
				for (int i = 0; i < SMOKE_BOUNCE_TARGETS; ++i)
					if (smoke_first_bounce[i][0][0] < x && x < smoke_first_bounce[i][1][0] &&
						smoke_first_bounce[i][0][1] < y && y < smoke_first_bounce[i][1][1] &&
						smoke_first_bounce[i][0][2] < z && z < smoke_first_bounce[i][1][2])
							on_target = true;
				PrintToChat(client, "%sgrenade_bounce: (%.2f, %.2f, %.2f)",
					on_target ? "Promising! " : "",
					x, y, z);
				SmokeLog("[%d-D-%d] Bounce (%.2f, %.2f, %.2f) - %s", client, ent,
					x, y, z, on_target ? "PROMISING" : "MISSED");
			}
			break;
		}
	}
}

int assign_flame_owner = -1;
bool report_new_entities = false;
//int nextpitch = 2530, nextyaw = 6740; //Note that pitch is the magnitude of pitch, but we actually negate it for execution.
public void OnEntityCreated(int entity, const char[] cls)
{
	if (GetConVarInt(learn_smoke) && !strcmp(cls, "smokegrenade_projectile"))
	{
		//It's a newly-thrown smoke grenade. Mark it so we'll report its
		//first bounce (if we're reporting grenade bounces).
		smoke_not_bounced[entity] = true;
		CreateTimer(0.01, report_entity, entity, TIMER_FLAG_NO_MAPCHANGE);
		/*
		//These numbers are good for testing B Window; bind a key to "exec next_throw" and
		//alternate that with a jump-throw key. To test Xbox, change or remove the setpos,
		//remove the duck, and probably widen the possible pitch/yaw values quite a bit.
		if (++nextyaw > 6760) {nextyaw = 6740; ++nextpitch;}
		File fp = OpenFile("next_throw.cfg", "w");
		WriteFileLine(fp, "//Created by drzed.sp for smoke aim drilling");
		WriteFileLine(fp, "setpos_exact -2185.968750 1059.031250 39.801247");
		WriteFileLine(fp, "setang -%d.%02d %d.%02d 0.0", nextpitch / 100, nextpitch % 100, nextyaw / 100, nextyaw % 100);
		WriteFileLine(fp, "+duck");
		WriteFileLine(fp, "+attack");
		CloseHandle(fp);
		// */
	}
	if (!strcmp(cls, "entityflame")) SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", assign_flame_owner);
	if (report_new_entities)
		PrintToChatAll("New: %s [%d]", cls, entity);
}

Action report_entity(Handle timer, any entity)
{
	ignore(timer);
	if (!IsValidEntity(entity)) return;
	char cls[64]; GetEdictClassname(entity, cls, sizeof(cls));
	if (!strcmp(cls, "smokegrenade_projectile"))
	{
		int client = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
		if (client != -1) SmokeLog("[%d-C-%d] Spawn", client, entity);
	}
	else if (!strcmp(cls, "info_player_ping"))
	{
		PrintToStream("New ping: %d", entity);
		int target = GetEntPropEnt(entity, Prop_Send, "m_hPingedEntity");
		PrintToStream("Pinged %d Player %d Type %d",
			target,
			GetEntPropEnt(entity, Prop_Send, "m_hPlayer"),
			GetEntProp(entity, Prop_Send, "m_iType")
		);
		PrintToStream("Ent %d render FX %d mode %d",
			target,
			GetEntProp(target, Prop_Send, "m_nRenderFX"),
			GetEntProp(target, Prop_Send, "m_nRenderMode")
		);
	}
}

//Not really public, but not always used, so suppress the warning
public Action unreport_new(Handle timer, any entity)
{
	ignore(timer);
	report_new_entities = false;
}

//Tick number when you last jumped or last threw a smoke grenade
int last_jump[64];
int last_smoke[64];
public void player_jump(Event event, const char[] name, bool dontBroadcast)
{
	if (!GetConVarInt(learn_smoke)) return;
	int client = GetClientOfUserId(event.GetInt("userid"));
	//Record timestamp for the sake of a jump-throw. If you then throw a smoke,
	//or if you just recently did, report it.
	int now = GetGameTickCount();
	if (now < last_smoke[client] + 32 && now >= last_smoke[client])
	{
		if (now == last_smoke[client])
			PrintToChat(client, "You smoked and jumped simultaneously (-0)");
		else
			PrintToChat(client, "You smoked -%d before jumping", now - last_smoke[client]);
		SmokeLog("[%d-B] JumpThrow -%d", client, now - last_smoke[client]);
	}
	last_jump[client] = now;
}

#include "underdome.inc"
int underdome_mode = 0, underdome_flg = 0;
int killsneeded;
float last_guardian_buy_time = 0.0;
Handle underdome_ticker = INVALID_HANDLE;
int spray_count[MAXPLAYERS + 1]; //Number of bullets fired since the last time all attack buttons were released

void keep_firing(int client)
{
	//Increase fire rate based on the length of time you've been firing
	int weap = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weap <= 0) return;
	float clip = 1.0;
	char cls[64]; GetEntityClassname(weap, cls, sizeof(cls));
	int idx;
	if (GetTrieValue(weapondata_index, cls, idx)) clip = weapondata_primary_clip_size[idx];
	if (clip < 1.0) clip = 1.0; //Shouldn't happen
	float delay = GetEntPropFloat(weap, Prop_Send, "m_flNextPrimaryAttack") - GetGameTime();
	//PrintCenterTextAll("Delay: %.3f", delay);
	float scale = 1.0 - 0.5 * spray_count[client] / clip;
	if (scale < 0.25) scale = 0.25; //Max out at four-to-one fire rate boosting (otherwise scale could even go negative in theory)
	SetEntPropFloat(weap, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + delay * scale);
	//Random chance to consume no ammo, based on spray length
	//If clip is full or empty, always consume ammo (to prevent weirdnesses)
	//Cap the chance at 75%, which will mean that you should eventually run out
	int clipleft = GetEntProp(weap, Prop_Send, "m_iClip1");
	int chance = spray_count[client];
	if (clipleft == RoundToFloor(clip) || clipleft == 0) chance = 0;
	else if (chance > 75) chance = 75;
	if (randrange(100) < chance)
		SetEntProp(weap, Prop_Send, "m_iClip1", clipleft + 1);
}

void slow_firing(int client)
{
	int rate = GetConVarInt(limit_fire_rate); //Restrict fire rate to X rounds/min
	int weap = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weap <= 0 || rate <= 0) return;
	float delay = GetEntPropFloat(weap, Prop_Send, "m_flNextPrimaryAttack") - GetGameTime();
	if (rate == 1) //Show, rather than changing, the limit
	{
		PrintCenterText(client, "Calculated fire rate: %.2f", 60.0 / delay);
		return;
	}
	float min_delay = 60.0 / rate; //Seconds between shots (usually a small fraction of one)
	if (delay < min_delay)
		SetEntPropFloat(weap, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + min_delay);
}

int strafe_direction[MAXPLAYERS + 1]; //1 = right, 0 = neither/both, -1 = left. This is your *goal*, not your velocity or acceleration.
int stutterstep_score[MAXPLAYERS + 1][3]; //For each player, ({stationary, accurate, inaccurate}), and is reset on weapon reload
float stutterstep_inaccuracy[MAXPLAYERS + 1]; //For each player, the sum of squares of the inaccuracies, for the third field above.
float current_weapon_speed[MAXPLAYERS + 1]; //For each player, the max speed of the weapon that was last equipped. An optimization.

void show_stutterstep_stats(int client)
{
	char player[64]; GetClientName(client, player, sizeof(player));
	int shots = stutterstep_score[client][1] + stutterstep_score[client][2];
	if (stutterstep_score[client][0] + shots == 0) return; //No stats to show (can happen if you reload two weapons in succession)
	PrintToChatAll("%s: stopped %d, accurate %d, inaccurate %d - spread %.2f", player,
		stutterstep_score[client][0], stutterstep_score[client][1], stutterstep_score[client][2],
		shots ? stutterstep_inaccuracy[client] / shots : 0.0);
	stutterstep_score[client][0] = stutterstep_score[client][1] = stutterstep_score[client][2] = 0;
	stutterstep_inaccuracy[client] = 0.0;
}

public void Event_weapon_fire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	char weapon[64]; event.GetString("weapon", weapon, sizeof(weapon));
	if (GetConVarInt(learn_smoke) && !strcmp(weapon, "weapon_smokegrenade"))
	{
		//If you just fired a smoke, record timestamp for the sake of a jump-throw.
		int now = GetGameTickCount();
		float pos[3]; GetClientEyePosition(client, pos);
		float angle[3]; GetClientEyeAngles(client, angle);
		PrintToChat(client, "Smoked looking (%.2f, %.2f)", angle[0], angle[1]);
		SmokeLog("[%d-A] Smoke (%.2f, %.2f, %.2f) - (%.2f, %.2f)", client,
			pos[0], pos[1], pos[2], angle[0], angle[1]);
		if (now < last_jump[client] + 32 && now >= last_jump[client])
		{
			if (now == last_jump[client])
				PrintToChat(client, "You jumped and smoked simultaneously (+0)");
			else
				PrintToChat(client, "You smoked +%d after jumping", now - last_jump[client]);
			SmokeLog("[%d-B] JumpThrow +%d", client, now - last_jump[client]);
		}
		last_smoke[client] = now;
	}

	spray_count[client]++;

	if (GetConVarInt(learn_stutterstep))
	{
		//Stutter stepping
		//Every time a shot is fired:
		// * Show the total velocity. Should match cl_showpos 1
		// * Get eye angles. Calculate the proportion of velocity which is perpendicular to the horizontal eye angle.
		//   - What about the vertical proportion?
		// * Inspect currently-held buttons. Are you increasing or decreasing velocity?
		// * Summarize with a score number: 0.0 is perfect, positive means too late, negative too soon
		// * Don't bother doing anything about aim synchronization - the pockmarks can teach that.
		// * Show the current keys and the sideways movement as center text
		float vel[3]; //Velocity seems to be three floats, NOT a vector. Why? No clue.
		vel[0] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
		vel[1] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
		vel[2] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[2]");
		float spd = GetVectorLength(vel, false); //Should be equal to what cl_showpos tells you your velocity is
		float angle[3]; GetClientEyeAngles(client, angle);
		float right[3]; GetAngleVectors(angle, NULL_VECTOR, right, NULL_VECTOR); //Unit vector perpendicular to the way you're facing
		float right_vel = GetVectorDotProduct(vel, right); //Magnitude of the velocity projected onto the (unit) right hand vector
		int sidestep = spd > 0.0 ? RoundToNearest(FloatAbs(right_vel) * 100.0 / spd) : 0; //Proportion of your total velocity that is across your screen (and presumably your enemy's)
		float maxspeed = current_weapon_speed[client];
		if (maxspeed == 0.0) maxspeed = 250.0; //Or use the value from sv_maxspeed?
		maxspeed *= 0.34; //Below 34% of a weapon's maximum speed, you are fully accurate.
		int quality = spd == 0.0 && !strafe_direction[client] ? 0 : //Stationary shot.
				spd <= maxspeed ? 1 : //Accurate shot.
				2; //Inaccurate shot.
		stutterstep_score[client][quality]++; 
		if (quality == 2) stutterstep_inaccuracy[client] += Pow(spd / maxspeed, 2.0) - 1.0;
		char quality_desc[][] = {"stopped", "good", "bad"};
		char sync_desc[64] = "";
		if (strafe_direction[client])
		{
			//Ideally your spd should be close to zero. However, it's the right_vel
			//(which is a signed value) that can be usefully compared to your goal
			//(in strafe_direction). By multiplying them, we get a signed velocity
			//relative to your goal direction; a positive number means you're now
			//increasing your velocity (unless at max), negative means decreasing.
			right_vel *= strafe_direction[client];
			int sync = RoundToFloor(spd); if (right_vel < 0) sync = -sync;
			//Why can't I just display a number with %+d ??? sigh.
			Format(sync_desc, sizeof(sync_desc), " SYNC %s%d", sync > 0 ? "+" : "", sync);
		}
		PrintToChat(client, "Stutter: speed %.2f/%.0f side %d%% %s%s", spd, maxspeed, sidestep, quality_desc[quality], sync_desc);
		//If this is the last shot from the magazine, show stats, since the weapon_reload
		//event doesn't fire.
		int weap = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (weap > 0 && GetEntProp(weap, Prop_Send, "m_iClip1") == 1) show_stutterstep_stats(client);
	}

	if (GetConVarInt(limit_fire_rate)) RequestFrame(slow_firing, client);
	else if (underdome_flg & UF_SALLY) RequestFrame(keep_firing, client);

	//If you empty your clip completely, add a stack of Anarchy
	if (anarchy[client] < GetConVarInt(sm_drzed_max_anarchy))
	{
		int weap = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		int clip = GetEntProp(weap, Prop_Send, "m_iClip1");
		int burst = GetEntProp(weap, Prop_Send, "m_bBurstMode");
		if (clip <= (burst  ? 3 : 1)) //As of 20190301, all burst-fire weapons in CS:GO fire three shots.
		{
			//The weapon is about to empty its magazine. In case it's a burst
			//~ PrintToStream("Emptied magazine: av %d", anarchy_available[client]);
			CreateTimer(burst ? 0.2 : 0.01, add_anarchy, client, TIMER_FLAG_NO_MAPCHANGE);
		}
		//~ char player[64]; GetClientName(client, player, sizeof(player));
		//~ char weapname[64]; describe_weapon(weap, weapname, sizeof(weapname));
		//~ PrintToStream("Weapon fire: %s fired %s with %d in clip (burst %d)", player, weapname, clip, burst);
	}
	#if 0
	char buf[128] = "Ammo:";
	for (int off = 0; off < 32; ++off)
		Format(buf, sizeof(buf), "%s %d", buf, GetEntProp(client, Prop_Data, "m_iAmmo", _, off));
	PrintToStream(buf);
	#endif
	#if 0
	int weap = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	PrintToStream("Accuracy: pen %.5f last %.2f idx %.2f",
		GetEntPropFloat(weap, Prop_Send, "m_fAccuracyPenalty"),
		GetEntPropFloat(weap, Prop_Send, "m_fLastShotTime"),
		GetEntPropFloat(weap, Prop_Send, "m_flRecoilIndex")
	);
	//Creating a "reverse recoil pattern" doesn't work. I think what happens is that
	//the recoil for the current index is added onto the weapon's recoil angles and
	//stuff, which means that you can't actually subtract that out.
	//SetEntPropFloat(weap, Prop_Send, "m_flRecoilIndex", GetEntProp(weap, Prop_Send, "m_iClip1") + 0.0);

	//This does work, but doesn't do what you might think. It doesn't keep the weapon
	//at its initial dot, and it also doesn't keep it going straight up; it actually
	//seems to have most weapons go straight out sideways like the Krieg - either
	//left or right, but always the same way for any particular weapon. I think it's
	//normally going to go a little to the left, then a little to the right, etc,
	//so in normal usage, it feels like it goes straight up; but constantly resetting
	//to zero means it goes the same way every time.
	SetEntPropFloat(weap, Prop_Send, "m_flRecoilIndex", 0.0);
	#endif
	//If you throw a grenade and it's the only thing you have, unselect.
	if (GetPlayerWeaponSlot(client, 2) != -1) return; //Normally you'll have a knife, and things are fine.
	int ammo_offset = 0;
	if (!strcmp(weapon, "weapon_hegrenade")) ammo_offset = 14;
	else if (!strcmp(weapon, "weapon_flashbang")) ammo_offset = 15;
	else if (!strcmp(weapon, "weapon_smokegrenade")) ammo_offset = 16;
	else if (!strcmp(weapon, "weapon_molotov") || !strcmp(weapon, "weapon_incgrenade")) ammo_offset = 17;
	else if (!strcmp(weapon, "weapon_decoy")) ammo_offset = 18;
	else if (!strcmp(weapon, "weapon_tagrenade")) ammo_offset = 22; //Mainly in co-op
	else if (!strcmp(weapon, "weapon_snowball")) ammo_offset = 24; //Winter update 2018
	else return; //Wasn't a grenade you just threw.

	//Okay, you threw a grenade, and we know where to check its ammo.
	//Let's see if you have stock of anything else.
	if (GetPlayerWeaponSlot(client, 0) != -1) return; //Got a primary? All good.
	if (GetPlayerWeaponSlot(client, 1) != -1) return; //Got a pistol? All good.
	//Already checked knife above as our fast-abort.
	//Checking for a 'nade gives false positives.
	if (GetPlayerWeaponSlot(client, 5) != -1) return; //Got the C4? All good.

	//Do you have ammo of any other type of grenade?
	for (int offset = 14; offset <= 24; ++offset)
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

public Action add_bonus_health(Handle timer, int client)
{
	//If you now have a suit, give the health bonus. That way, if ANYTHING
	//blocks the purchase, the health bonus won't happen.
	//TODO: If the bonus health has already been added, don't add it again.
	//In theory, it's possible to spam buy commands really fast and get the
	//bonus more than once.
	if (GetEntProp(client, Prop_Send, "m_bHasHeavyArmor"))
	{
		int hp = GetConVarInt(sm_drzed_suit_health_bonus);
		if (hp) SetEntityHealth(client, GetClientHealth(client) + hp);
	}
}
	
Action bot_delayed_purchase(Handle timer, Handle params)
{
	ignore(timer);
	int client = ReadPackCell(params);
	int primary = ReadPackCell(params);
	SetEntityRenderFx(client, RENDERFX_NONE);
	if (GetPlayerWeaponSlot(client, 0) != primary) return;
	char desired[64]; ReadPackString(params, desired, sizeof(desired));
	char command[68]; FormatEx(command, sizeof(command), "buy %s", desired);
	FakeClientCommandEx(client, command);
}

public Action CS_OnBuyCommand(int buyer, const char[] weap)
{
	if (!IsClientInGame(buyer) || !IsPlayerAlive(buyer)) return Plugin_Continue;
	//If a bot buys a primary weapon, announce it to team chat, wait a cvar-controlled time, and then:
	//1) If the bot's state has not changed, repeat the buy
	//2) If the bot now has a primary weapon that he did not previously have, do nothing.
	//3) If a command has been entered to stop bots buying at all, do nothing.
	//4) If, subsequently, the bot-don't-buy command is re-entered, redo the buy. Maybe.
	//NOTE: The bot_autobuy_nades check must be done after this delay, and be disabled if
	//the command is entered.
	float time_since_freeze = (GetGameTickCount() - freeze_started) * GetTickInterval();
	//char name[64]; GetClientName(buyer, name, sizeof(name));
	//PrintToStream("[%.2f] %s%s attempted to buy %s", time_since_freeze, IsFakeClient(buyer) ? "BOT " : "", name, weap);
	//Disallow defusers during warmup (they're useless anyway)
	if (StrEqual(weap, "defuser") && GameRules_GetProp("m_bWarmupPeriod")) return Plugin_Stop;
	//Make bots wait before buying, if they're buying within the first few seconds of freeze
	float delay = GetConVarFloat(bot_purchase_delay) - time_since_freeze;
	if (!GameRules_GetProp("m_bWarmupPeriod") && IsFakeClient(buyer) && delay > 0.0)
	{
		//See if the weapon is a primary
		int use_a_or_an = 0;
		if (!GetTrieValue(weapon_is_primary, weap, use_a_or_an)) return Plugin_Continue;
		//If you're already waiting on a purchase, deny without deferring.
		if (GetEntityRenderFx(buyer) != RENDERFX_NONE) return Plugin_Stop;
		//Announce in team chat "I'm going to buy a/an " + weap
		char command[100]; FormatEx(command, sizeof(command), "say_team I was going to buy %s %s",
			use_a_or_an == 1 ? "a" : "an", weap);
		FakeClientCommandEx(buyer, command);
		SetEntityRenderFx(buyer, RENDERFX_STROBE_FASTER);
		Handle params;
		CreateDataTimer(delay, bot_delayed_purchase, params, TIMER_FLAG_NO_MAPCHANGE);
		WritePackCell(params, buyer);
		//See what primary, if any, the bot has
		int primary = GetPlayerWeaponSlot(buyer, 0);
		WritePackCell(params, primary);
		WritePackString(params, weap);
		ResetPack(params);
		return Plugin_Stop; //Don't buy it yet
	}
	if (StrEqual(weap, "heavyassaultsuit"))
	{
		//Crippling mode uses the suit, so when that's happening, you can't buy the suit.
		//TODO: This is no longer the case - can this check be removed?
		if (GetConVarInt(sm_drzed_crippled_health)) return Plugin_Stop;
		//If this purchase succeeds, grant a health bonus.
		if (!GetEntProp(buyer, Prop_Send, "m_bHasHeavyArmor"))
			CreateTimer(0.05, add_bonus_health, buyer, TIMER_FLAG_NO_MAPCHANGE);
	}
	#if 0
	//POC, untested.
	if (StrEqual(weap, "tagrenade") || StrEqual(weap, "snowball")) //Sometimes, "buy tagrenade" comes through as "snowball" (?????)
	{
		//Replace the Tactical Advisory Grenade with a health shot
		//(since we can't, to my knowledge, create entirely new buyables)
		int money = GetEntProp(buyer, Prop_Send, "m_iAccount");
		int current = GetEntProp(buyer, Prop_Data, "m_iAmmo", _, 25); //Ammo of health shots
		if (money >= 1000) // && current < some cvar
		{
			SetEntProp(buyer, Prop_Send, "m_iAccount", money - 1000);
			PrintToStream("%s bought a health shot", name);
			GivePlayerItem(buyer, "weapon_healthshot");
			return Plugin_Stop;
		}
	}
	#endif
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
		int have_ta = GetEntProp(client, Prop_Data, "m_iAmmo", _, 22);
		int total_nades = have_he + have_flash + have_smoke + have_molly + have_decoy + have_ta;
		int max_nades = GetConVarInt(ammo_grenade_limit_total);
		//TODO: Respect per-type maximums that might be higher than 1
		int molly_price = team == 2 ? 400 : 600; //Incendiary grenades are overpriced for CTs
		money -= 1000; //Ensure that the bots don't spend below $1000 this way (just in case).
		int bought = 0;
		int which = -1;
		char nade_desc[][] = {"an HE", "a Flash", "a Smoke", "a Molly"};
		for (int i = 0; i < 7; ++i)
		{
			if (total_nades + bought >= max_nades) break;
			switch (randrange(7))
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

int puzzles_solved[65];
#define MAX_PUZZLES 16
#define MAX_PUZZLE_SOLUTION 256
int num_puzzles; //Normally equal to GetConVarInt(bomb_defusal_puzzles) as of round start
int puzzle_endgame = 0;
char puzzle_clue[MAX_PUZZLES][MAX_PUZZLE_SOLUTION];
float puzzle_value[MAX_PUZZLES]; //If -1, use puzzle_solution instead (which must start "!solve ").
char puzzle_solution[MAX_PUZZLES][MAX_PUZZLE_SOLUTION];
public void puzzle_defuse(Event event, const char[] name, bool dontBroadcast)
{
	if (!num_puzzles) return;
	int client = GetClientOfUserId(event.GetInt("userid"));
	//See how many puzzles the attempting defuser has solved
	//If >= puzzles, permit the defusal. Otherwise, show hint for puzzle N,
	//and teleport the bomb away briefly.
	if (puzzle_endgame == 2) PrintToChat(client, "Go go go! Stick the defuse!");
	if (puzzle_endgame) return;
	int bomb = FindEntityByClassname(-1, "planted_c4");
	if (bomb == -1) return;

	float tm = GetEntPropFloat(bomb, Prop_Send, "m_flC4Blow") - GetGameTime();
	int min = RoundToFloor(tm / 60);
	int sec = RoundToCeil(tm - min * 60);
	PrintToChat(client, "You have %02d:%02d on the clock and have solved %d/%d puzzles.",
		min, sec, puzzles_solved[client], num_puzzles);
	PrintToChat(client, "%s", puzzle_clue[puzzles_solved[client]]);
	PrintCenterText(client, "%s", puzzle_clue[puzzles_solved[client]]);

	//Attempting to cancel the defusal seems to be really unreliable, but
	//simply moving the bomb away appears to work every time.
	float pos[3]; GetEntPropVector(bomb, Prop_Send, "m_vecOrigin", pos);
	//For the most part, moving the bomb a long way away should break the
	//defuse and force a reset. We move it a crazy long way because it's
	//supposed to be inaccessible, and deep deep down into the earth in
	//case of a nuke - specifically, de_nuke and its multi-level style.
	pos[0] -= 2000.0;
	pos[1] -= 2000.0;
	pos[2] -= 2000.0;
	TeleportEntity(bomb, pos, NULL_VECTOR, NULL_VECTOR);
	CreateTimer(5.0, return_bomb, bomb, TIMER_FLAG_NO_MAPCHANGE);
}

public void show_defuse_time(Event event, const char[] name, bool dontBroadcast)
{
	int bomb = FindEntityByClassname(-1, "planted_c4");
	if (bomb == -1) return;
	float tm = GetEntPropFloat(bomb, Prop_Send, "m_flC4Blow") - GetGameTime();
	if (tm < 1.0) PrintToChatAll("Bomb defused with %.3f seconds remaining!", tm);
	else if (tm < 10.0) PrintToChatAll("Bomb defused with %.1f seconds remaining!", tm);
	else if (tm < 60.0) PrintToChatAll("Bomb defused with %.0f seconds remaining.", tm);
	else
	{
		//Won't happen in competitive modes, as the bomb timer starts at
		//under a minute. But in puzzle mode, the bomb is ticking for the
		//entire round, potentially several minutes.
		int min = RoundToFloor(tm / 60);
		int sec = RoundToCeil(tm - min * 60);
		PrintToChatAll("Bomb defused with %02d:%02d on the clock.", min, sec);
	}
}

public Action return_bomb(Handle timer, any bomb)
{
	ignore(timer);
	if (!IsValidEntity(bomb)) return;
	float pos[3]; GetEntPropVector(bomb, Prop_Send, "m_vecOrigin", pos);
	pos[0] += 2000.0;
	pos[1] += 2000.0;
	pos[2] += 2000.0;
	TeleportEntity(bomb, pos, NULL_VECTOR, NULL_VECTOR);
}

#define MAX_CLUES_PER_CAT 10
int puzzle_clues[MAX_CLUES_PER_CAT * WEAPON_TYPE_CATEGORIES];
int num_puzzle_clues = 0;

bool puzzle_is_highlighted(int entity)
{
	int r,g,b,a;
	GetEntityRenderColor(entity, r, g, b, a);
	return a < 255;
}
Action stabilize_weapon(Handle timer, any entity)
{
	if (IsValidEntity(entity) && puzzle_is_highlighted(entity))
		SetEntityRenderFx(entity, RENDERFX_HOLOGRAM);
}
//Highlight or unhighlight a clue
//state: 1 => highlight, 0 => unhighlight, -1 => toggle
//Returns true if now highlighted, false if not
//The weapon flickers briefly, then stabilizes with semitransparency.
bool puzzle_highlight(int entity, int state)
{
	if (state == -1) state = puzzle_is_highlighted(entity) ? 0 : randrange(2) + 1;
	if (!state)
	{
		SetEntityRenderColor(entity, 255, 255, 255, 255);
		SetEntityRenderFx(entity, RENDERFX_NONE);
		return false;
	}
	if (state == 2) SetEntityRenderColor(entity, 128, 255, 255, 224); //Bubblegum
	else SetEntityRenderColor(entity, 255, 192, 255, 224); //Blackcurrant
	SetEntityRenderFx(entity, RENDERFX_EXPLODE);
	CreateTimer(0.6, stabilize_weapon, entity, TIMER_FLAG_NO_MAPCHANGE);
	return true;
}

void adjust_underdome_gravity()
{
	for (int client = 1; client < MaxClients; ++client)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client)) continue;
		float grav = 1.0;
		int ct = GetClientTeam(client) == 3;
		if (underdome_flg & (ct ? UF_CT_LOW_GRAVITY : UF_T_LOW_GRAVITY)) grav = 0.5;
		if (underdome_flg & (ct ? UF_CT_HIGH_GRAVITY : UF_T_HIGH_GRAVITY)) grav = 1.75;
		SetEntityGravity(client, grav);
	}
}

void reset_underdome_config()
{
	//Clear out anything that's set up specifically for Underdome mode
	//Must be idempotent - can be called when we've never had any Underdoming.
	if (underdome_ticker != INVALID_HANDLE)
	{
		KillTimer(underdome_ticker);
		underdome_ticker = INVALID_HANDLE;
	}
	SetConVarFloat(weapon_recoil_scale, 2.0);
	SetConVarFloat(mp_damage_vampiric_amount, 0.0);
	SetConVarFloat(mp_damage_scale_ct_head, 1.0);
	SetConVarFloat(mp_damage_scale_t_head, 1.0);
	SetConVarFloat(mp_damage_scale_ct_body, 1.0);
	SetConVarFloat(mp_damage_scale_t_body, 1.0);
	underdome_mode = 0;
	adjust_underdome_gravity();
}

Action check_wave_end(Handle timer, int victim)
{
	int killsnowneeded = GameRules_GetProp("m_nGuardianModeSpecialKillsRemaining");
	if (underdome_mode && IsClientInGame(victim) && GetClientTeam(victim) == 2) //No messages when a CT dies or someone disconnects
	{
		if (killsneeded != killsnowneeded) //Good kill, counted on the score
			PrintToChatAll(underdome_killok[underdome_mode - 1]);
		else //Didn't count to the score. Optionally give a message explaining why.
			PrintToChatAll(underdome_killbad[underdome_mode - 1]);
	}
	killsneeded = killsnowneeded;
	float buytime = GameRules_GetPropFloat("m_flGuardianBuyUntilTime");
	if (buytime != last_guardian_buy_time && !GameRules_GetProp("m_bWarmupPeriod"))
	{
		last_guardian_buy_time = buytime;
		//See if any bots are currently alive. If there aren't, it's a new wave!
		//(Although, if all bots die simultaneously in warmup, that ISN'T a new wave.)
		for (int client = 1; client < MAXPLAYERS; ++client)
			if (IsClientInGame(client) && IsPlayerAlive(client) && IsFakeClient(client))
				return; //There's a living bot. Don't redo rules.
		devise_underdome_rules();
	}
}
public void player_death(Event event, const char[] name, bool dontBroadcast)
{
	//What happens if I change mp_guardian_special_weapon_needed in here?
	//Can I set it to a self-contradiction (aka "never") or back to its default?
	if (GetConVarInt(guardian_underdome_waves))
	{
		if (underdome_mode) //This can never happen during the warmup wave - ALL kills count.
		{
			bool deny = false;
			int assister = event.GetInt("assister");
			if ((underdome_flg & UF_ASSISTED_ONLY) && !assister) deny = true;
			if ((underdome_flg & UF_NO_TEAM_ASSISTS) && assister &&
				//Ahem. *cough* *cough*
				GetClientTeam(GetClientOfUserId(event.GetInt("userid"))) == GetClientTeam(GetClientOfUserId(assister))
			) deny = true;
			if ((underdome_flg & UF_NO_FLASH_ASSISTS) && event.GetInt("assistedflash")) deny = true;
			if ((underdome_flg & UF_NO_NONFLASH_ASSISTS) && !event.GetInt("assistedflash")) deny = true;
			if ((underdome_flg & UF_PENETRATION_ONLY) && !event.GetInt("penetrated")) deny = true;
			if (deny)
				//Use the exact counterpart of the tautology used for "always true" in gen_effects_tables
				SetConVarString(mp_guardian_special_weapon_needed, "%cond_player_zoomed% && !%cond_player_zoomed%");
			else
				SetConVarString(mp_guardian_special_weapon_needed, underdome_needed[underdome_mode - 1]);
		}
		CreateTimer(0.0, check_wave_end, GetClientOfUserId(event.GetInt("userid")), TIMER_FLAG_NO_MAPCHANGE);
	}
	else reset_underdome_config();
}

public void player_use(Event event, const char[] name, bool dontBroadcast)
{
	if (num_puzzles)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		int entity = event.GetInt("entity");
		//If this entity is a registered clue, highlight it.
		for (int i = 0; i < num_puzzle_clues; ++i) if (puzzle_clues[i] == entity)
		{
			bool state = puzzle_highlight(entity, -1);
			char player[64]; GetClientName(client, player, sizeof player);
			char weap[64]; describe_weapon(entity, weap, sizeof weap);
			PrintToChatAll("%s %s a %s", player, state ? "marked" : "unmarked", weap);
			break;
		}
	}
}

char weapon_attribute_question[][] = {
	"How many shots till I reload?",
	"What does it cost to buy?",
	"How well does it penetrate armor?",
	"How fast can I move?",
};
char weapon_comparison_question[][] = {
	"Which lets me fire more bullets before reloading",
	"Which is more expensive",
	"Which takes less notice of armor",
	"Which lets me move faster",
};
char weapon_attribute_superlative[][] = {
	"smallest magazine", "largest magazine",
	"cheapest", "most expensive",
	"least penetrating", "most penetrating",
	"heaviest", "lightest",
};
float weapon_attribute(int idx, int attr)
{
	switch (attr)
	{
		case 0: return weapondata_primary_clip_size[idx];
		case 1: return weapondata_in_game_price[idx];
		case 2: return weapondata_armor_pen[idx];
		case 3: return weapondata_max_player_speed[idx];
		case -1: return weapondata_kill_award[idx]; //Not currently used
		case -2: return weapondata_primary_reserve_ammo_max[idx]; //Not currently used
		default: return 0.0;
	}
}
public void OnGameFrame()
{
	int freeze = GameRules_GetProp("m_bFreezePeriod");
	if (freeze && !last_freeze)
	{
		freeze_started = GetGameTickCount();
		//When we go into freeze time, wait half a second, then get the bots to buy nades.
		//Note that they won't buy nades if we're out of freeze time, so you need at least
		//one full second of freeze in order to do this reliably.
		if (GetConVarInt(bot_autobuy_nades)) CreateTimer(0.5, buy_nades, 0, TIMER_FLAG_NO_MAPCHANGE);
		num_puzzle_clues = 0; //TODO: Instead of doing it here, do it when those clue items get destroyed.
	}
	if (!freeze && last_freeze)
	{
		int puzzles = GameRules_GetProp("m_bWarmupPeriod") ? 0 : GetConVarInt(bomb_defusal_puzzles);
		num_puzzle_clues = puzzle_endgame = 0;
		if (puzzles)
		{
			plant_bomb();
			bool demo_mode = puzzles == 7355608;
			bool hack_mode = puzzles == 12345;
			if (puzzles > MAX_PUZZLES) puzzles = MAX_PUZZLES;
			//Find some random spawn points
			//Note that we're shuffling the list of entities, not the actual locations;
			//we assume that the entities are sufficiently spaced that we don't have to
			//worry about actual collisions, but this does still mean we can't make any
			//deductions about proximity. Still, it's a LOT easier in SourcePawn to use
			//integers for most of the work, and then find vectors only at the end.
			#define MAX_CLUE_SPAWNS 64
			int spawnpoints[MAX_CLUE_SPAWNS];
			int numspawns = 0;
			//Variant of Fisher-Yates shuffle, building a randomized array one by one as
			//we find entities to add to it
			int ent = -1;
			while ((ent = FindEntityByClassname(ent, "info_deathmatch_spawn")) != -1)
			{
				//Maybe skip this one if there's a player there? Not a big deal.
				int pos = randrange(++numspawns);
				spawnpoints[numspawns - 1] = spawnpoints[pos];
				spawnpoints[pos] = ent;
				if (numspawns == MAX_CLUE_SPAWNS) break;
			}
			if (!numspawns) {puzzles = 0; spawnpoints[0] = -1;} //If there aren't any deathmatch spawn locations, we can't do puzzles.
			if (hack_mode)
			{
				for (int i = 0; i < numspawns; ++i)
				{
					float pos[3];
					GetEntPropVector(spawnpoints[i], Prop_Data, "m_vecOrigin", pos);
					int clue = CreateEntityByName(weapondata_item_name[i % sizeof(weapondata_item_name)]);
					DispatchSpawn(clue);
					TeleportEntity(clue, pos, NULL_VECTOR, NULL_VECTOR);
					//puzzle_highlight(clue, i + 1);
					puzzle_clues[num_puzzle_clues++] = clue;
				}
				PrintToChatAll("Created %d weapons.", numspawns);
				puzzles = 0;
			}
			int clues[sizeof(weapondata_categories)][MAX_CLUE_SPAWNS]; //Larger array than the max-placed
			int nclues[sizeof(weapondata_categories)] = {0};
			//unique_clue[cat] is -1 for "no weapons in category", -2 for
			//"weapons but no unique", -3 for "weapons and multiple uniques",
			//or the index into weapondata_* arrays.
			int unique_clue[sizeof(weapondata_categories)];
			for (int i=0; i<sizeof(unique_clue); ++i) unique_clue[i] = -1; //crude initializer :(
			int nextspawn = 0;
			if (puzzles) for (int cat = 0; cat < WEAPON_TYPE_CATEGORIES; ++cat)
			{
				int options[sizeof(weapondata_category)];
				int nopt = 0;
				for (int i = 0; i < sizeof(weapondata_category); ++i)
					if (weapondata_category[i] & (1<<cat))
						options[nopt++] = i;
				if (!nopt) continue; //No items in that category - probably unimplemented
				int unique = -1;
				if (GetURandomFloat() < 0.75) unique = randrange(nopt); //Often pick one in the category to be the unique
				int cl = 0;
				for (int i = 0; i < nopt; ++i)
				{
					//50% chance of zero, 25% chance of 1, 12.5% chance of 2, etc
					int n = RoundToFloor(-Logarithm(GetURandomFloat(), 2.0));
					//Since the above formula has a slim chance of a VERY high number, cap it.
					if (n > 4) n = 4;
					//Enforce uniqueness (or the lack of it) if we're doing that
					if (unique == i) n = 1;
					else if (unique != -1 && n == 1) n = 2;
					//And after all that work being random, if we're actually in demo mode, ignore it
					//and just use the number we've been given.
					if (demo_mode)
					{
						int qty = weapondata_demo_quantity[options[i]];
						if (qty >= 0) n = qty; //Enforced quantity
						else if (qty == -2 && n == 1) n = 2; //Anything non-unique
						else if (qty == -3 && n == 0) n = 1; //Anything non-zero
						//Else it's okay to be anything.
					}
					if (!n) continue;
					//If we've run out of array space (ugh I hate that problem),
					//reserve one for the unique (if necessary) and just stop
					//generating.
					int need = cl + n;
					if (unique != -1 && unique > i) ++need;
					if (need >= MAX_CLUES_PER_CAT) continue;
					cl += n;
					if (n > 1 && unique_clue[cat] == -1)
						unique_clue[cat] = -2;
					else if (n == 1)
						unique_clue[cat] = (unique_clue[cat] == -1 || unique_clue[cat] == -2) ? options[i] : -3;
					for (int x=0; x<n; ++x) clues[cat][nclues[cat]++] = options[i];
					for (int c = WEAPON_TYPE_CATEGORIES; c < sizeof(weapondata_categories); ++c)
						if (weapondata_category[options[i]] & (1<<c))
						{
							//Assign this clue to its appropriate other categories
							if (n > 1 && unique_clue[c] == -1)
								unique_clue[c] = -2;
							else if (n == 1)
								unique_clue[c] = (unique_clue[c] == -1 || unique_clue[c] == -2) ? options[i] : -3;
							for (int x=0; x<n; ++x) clues[c][nclues[c]++] = options[i];
						}
					//And generate that many of this item
					while (n--)
					{
						float pos[3];
						GetEntPropVector(spawnpoints[nextspawn++], Prop_Data, "m_vecOrigin", pos);
						if (nextspawn == numspawns) nextspawn = 0;
						int clue = CreateEntityByName(weapondata_item_name[options[i]]);
						DispatchSpawn(clue);
						TeleportEntity(clue, pos, NULL_VECTOR, NULL_VECTOR);
						puzzle_clues[num_puzzle_clues++] = clue;
					}
				}
			}
			if (demo_mode)
			{
				next_nonrandom = 0;
				puzzles = randctrl(MAX_PUZZLES - 1) + 1;
			}
			else next_nonrandom = -1;
			for (int puz = 0; puz < puzzles; ++puz)
			{
				//Pick a random puzzle type (or a nonrandom one for demo)
				switch (randctrl(4))
				{
					case 0: //"This is my X"
					{
						//Pick a random category. If it has no unique, reroll completely.
						//(It's entirely possible that there are NO categories with uniques,
						//so don't risk getting stuck in an infinite loop spinning for one.
						//We can always go for a different puzzle type.)
						int cat = randctrl(sizeof(weapondata_categories));
						if (unique_clue[cat] < 0) {--puz; continue;}
						int attr = randctrl(sizeof(weapon_attribute_question));
						Format(puzzle_clue[puz], MAX_PUZZLE_SOLUTION,
							"This is my %s. There are none quite like it. %s",
							weapondata_category_descr[cat], weapon_attribute_question[attr]);
						puzzle_value[puz] = weapon_attribute(unique_clue[cat], attr);
					}
					case 1: //Comparisons
					{
						//Pick two random categories that have at least one weapon each
						//(so unique_clue[cat] is not -1) and an attribute.
						//Sigh. Can I deduplicate any of this at all?
						int attr = randctrl(sizeof(weapon_attribute_question));
						int cat1, cat2;
						do {cat1 = randctrl(sizeof(weapondata_categories));} while (!nclues[cat1]);
						do {cat2 = randctrl(sizeof(weapondata_categories));} while (!nclues[cat2] || cat2 == cat1);
						//Find the min and max of that attr for each category
						//NOTE: It's okay if there are duplicates, we just need the value.
						float minmax1[2], minmax2[2]; //[min,max] for each
						minmax1[0] = minmax1[1] = weapon_attribute(clues[cat1][0], attr);
						for (int cl=1; cl<nclues[cat1]; ++cl)
						{
							float a = weapon_attribute(clues[cat1][cl], attr);
							if (a < minmax1[0]) minmax1[0] = a;
							if (a > minmax1[1]) minmax1[1] = a;
						}
						minmax2[0] = minmax2[1] = weapon_attribute(clues[cat2][0], attr);
						for (int cl=1; cl<nclues[cat2]; ++cl)
						{
							float a = weapon_attribute(clues[cat2][cl], attr);
							if (a < minmax2[0]) minmax2[0] = a;
							if (a > minmax2[1]) minmax2[1] = a;
						}
						//Pick one from each pair - say, min1,max2
						int bound1 = randctrl(2), bound2 = randctrl(2);
						if (minmax1[bound1] > minmax2[bound2])
							Format(puzzle_solution[puz], MAX_PUZZLE_SOLUTION, "!solve %s", weapondata_categories[cat1]);
						else if (minmax2[bound2] > minmax1[bound1])
							Format(puzzle_solution[puz], MAX_PUZZLE_SOLUTION, "!solve %s", weapondata_categories[cat2]);
						else {--puz; continue;} //It's a tie. Forbid that.
						puzzle_value[puz] = -1.0;
						Format(puzzle_clue[puz], MAX_PUZZLE_SOLUTION,
							"%s - my %s %s or my %s %s?",
							weapon_comparison_question[attr],
							weapon_attribute_superlative[attr * 2 + bound1],
							weapondata_category_descr[cat1],
							weapon_attribute_superlative[attr * 2 + bound2],
							weapondata_category_descr[cat2]
						);
					}
					case 2: //Simple counting
					{
						int distinct = randctrl(2);
						int cat;
						do {cat = randctrl(sizeof(weapondata_categories));} while (!nclues[cat]);
						int n = nclues[cat];
						if (distinct)
						{
							//We can assume that duplicate clues are always placed as a
							//block, because clue items are always generated uniquely.
							for (int z = 1; z < nclues[cat]; ++z) if (clues[cat][z] == clues[cat][z-1]) --n;
						}
						puzzle_value[puz] = n + 0.0;
						Format(puzzle_clue[puz], MAX_PUZZLE_SOLUTION,
							"How many %s %ss do I have here?",
							distinct ? "distinct" : "total",
							weapondata_category_descr[cat]);
					}
					case 3: //Min/max
					{
						//Optionally pick a lookup attribute and question attribute separately
						//If so, ensure that the value of the question attribute isn't ambiguous.
						//(It's okay if multiple have the same min or max on the lookup, but
						//only if they also have the same on the question too.)
						int attr = randctrl(sizeof(weapon_attribute_question));
						int cat;
						do {cat = randctrl(sizeof(weapondata_categories));} while (!nclues[cat]);
						float minmax[2]; //Can this go into a function?
						minmax[0] = minmax[1] = weapon_attribute(clues[cat][0], attr);
						for (int cl=1; cl<nclues[cat]; ++cl)
						{
							float a = weapon_attribute(clues[cat][cl], attr);
							if (a < minmax[0]) minmax[0] = a;
							if (a > minmax[1]) minmax[1] = a;
						}
						if (minmax[0] == minmax[1]) {--puz; continue;} //Make sure it's not completely trivial.
						int bound = randctrl(2);
						puzzle_value[puz] = minmax[bound];
						Format(puzzle_clue[puz], MAX_PUZZLE_SOLUTION,
							"Find my %s %s. %s",
							weapon_attribute_superlative[attr * 2 + bound],
							weapondata_category_descr[cat],
							weapon_attribute_question[attr]);
					}
					default: PrintToChatAll("ASSERTION FAILED, puzzle type invalid");
				}
				//if (demo_mode) {PrintToChatAll(puzzle_clue[puz]); PrintToChatAll("--> %.0f", puzzle_value[puz]);}
			}
			//if (demo_mode) PrintToChatAll("Next nonrandom: %d", next_nonrandom);
			if (hack_mode) puzzles = 1;
		}
		num_puzzles = puzzles; //Record the number of puzzles we actually got
	}
	last_freeze = freeze;

	for (int i = 0; i < nshowpos; ++i) if (IsClientInGame(show_positions[i]))
	{
		int money = GetEntProp(show_positions[i], Prop_Send, "m_iAccount");
		//Define this to show positions in chat rather than as a hint message
		//#define POS_ONLY_WHEN_MONEY
		#if defined(POS_ONLY_WHEN_MONEY)
		if (last_money[show_positions[i]] == money) continue;
		#endif
		float pos[3]; GetClientAbsOrigin(show_positions[i], pos);
		float dist = GetVectorDistance(marked_pos, pos, false);
		float dist2 = GetVectorDistance(marked_pos2, pos, false);
		char distances[64];
		if (marked_pos2[0] || marked_pos2[1] || marked_pos2[2])
			Format(distances, sizeof(distances), "%.2f / %.2f", dist, dist2);
		else Format(distances, sizeof(distances), "%.2f", dist);
		if (last_money[show_positions[i]] == -1)
			PrintHintText(show_positions[i], "Distance from marked pos: %s", distances);
		else
			PrintToChat(show_positions[i], "Gained $ %d. Distance from marked pos: %s",
				money - last_money[show_positions[i]], distances);
		#if defined(POS_ONLY_WHEN_MONEY)
		last_money[show_positions[i]] = money;
		#endif
	}
	if (underdome_flg & UF_LOW_ACCURACY)
	{
		//NOTE: This produces a flicker as the server repeatedly corrects the client's
		//expectation of accuracy recovery. For the Underdome, this isn't a bad thing -
		//it makes your display go fuzzy and flickery to indicate inaccuracy. For other
		//use-cases, this might be a bit ugly :)
		for (int client = 1; client < MaxClients; ++client)
		{
			if (!IsClientInGame(client) || !IsPlayerAlive(client)) continue;
			float min_penalty = IsFakeClient(client) ? 0.125 : 0.0625; //The AI cheats a bit (but still has a penalty)
			int weap = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			if (weap <= 0) continue;
			float penalty = GetEntPropFloat(weap, Prop_Send, "m_fAccuracyPenalty");
			if (penalty < min_penalty) SetEntPropFloat(weap, Prop_Send, "m_fAccuracyPenalty", min_penalty);
		}
	}
}

//Create a cloud of smoke, visible to this client, at this pos
void blow_smoke(int client, float pos[3])
{
	TE_Start("EffectDispatch");
	TE_WriteNum("m_iEffectName", FindStringIndex(FindStringTable("EffectDispatch"), "ParticleEffect"));
	TE_WriteNum("m_nHitBox", FindStringIndex(FindStringTable("ParticleEffectNames"), "explosion_smokegrenade"));
	TE_WriteFloat("m_vOrigin.x", pos[0]);
	TE_WriteFloat("m_vOrigin.y", pos[1]);
	TE_WriteFloat("m_vOrigin.z", pos[2]);
	TE_SendToClient(client);
}

int phaseping_cookie[MAXPLAYERS+1];
//Avoid counting the player's own model when testing for collisions
bool collision_check(int entity, int mask, int client)
{
	ignore(mask);
	return entity != client;
}
Action reset_phaseping(Handle timer, any client)
{
	phaseping_cookie[client] = 0;
	//Reset any visual effects from phasewalking
}
Action phase_ping(Handle timer, Handle params)
{
	ignore(timer);
	int client = ReadPackCell(params);
	int cookie = ReadPackCell(params);
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) return; //Map changed, player left, or something like that
	if (cookie != phaseping_cookie[client]) return; //Wrong cookie - player has repinged, just use the new one.
	int ping = GetEntPropEnt(client, Prop_Send, "m_hPlayerPing");
	if (ping == -1) return; //No ping? Shouldn't happen.

	//Mark that you can't phaseping for a bit, nor can you fire any gun. Go ahead and throw nades though!
	phaseping_cookie[client] = -1;
	CreateTimer(1.5, reset_phaseping, client, TIMER_FLAG_NO_MAPCHANGE);
	for (int slot = 0; slot < 2; ++slot)
	{
		int weap = GetPlayerWeaponSlot(client, slot);
		if (weap != -1) SetEntPropFloat(weap, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + 1.5);
	}

	float pos[3]; GetClientAbsOrigin(client, pos);
	float mins[3]; GetClientMins(client, mins);
	float maxs[3]; GetClientMaxs(client, maxs);
	float dest[3]; GetEntPropVector(ping, Prop_Data, "m_vecOrigin", dest);
	//Since terrain is VERY likely to get in the way here, we try a few different traces and pick
	//the most effective (the one that gets us furthest).

	//First, a vanilla hull trace. Since this is first, guarantee to set its end position as the target.
	Handle trace = TR_TraceHullFilterEx(pos, dest, mins, maxs, MASK_PLAYERSOLID, collision_check, client);
	float target[3]; TR_GetEndPosition(target, trace);
	float delta = GetVectorDistance(target, dest, true);
	CloseHandle(trace);

	//Second, a "levitating" trace. Trace to waist height at the destination, then from there to the ground.
	//Advantages: Not blocked by uneven terrain. Disadvantages: Blocked by anything overhead.
	float waist = (maxs[2] + mins[2]) / 2;
	pos[2] += waist; dest[2] += waist;
	trace = TR_TraceHullFilterEx(pos, dest, mins, maxs, MASK_PLAYERSOLID, collision_check, client);
	float levitate[3]; TR_GetEndPosition(levitate, trace);
	CloseHandle(trace);
	pos[2] -= waist; dest[2] -= waist;
	//Take the X and Y from where we traced to, and then trace down as far as we can (but not TOO far).
	float ground[3]; ground[0] = levitate[0]; ground[1] = levitate[1]; ground[2] = levitate[2] - 100.0;
	trace = TR_TraceHullFilterEx(levitate, ground, mins, maxs, MASK_PLAYERSOLID, collision_check, client);
	TR_GetEndPosition(ground, trace);
	CloseHandle(trace);
	float howclose = GetVectorDistance(ground, dest, true);
	if (howclose < delta) {delta = howclose; target[0] = ground[0]; target[1] = ground[1]; target[2] = ground[2];} //New best!

	//Any other options?

	/*PrintToStream("From (%.0f,%.0f,%.0f) to (%.0f,%.0f,%.0f): stop at (%.0f,%.0f,%.0f)",
		pos[0], pos[1], pos[2],
		dest[0], dest[1], dest[2],
		target[0], target[1], target[2]);*/
	RemoveEntity(ping);
	TeleportEntity(client, target, NULL_VECTOR, NULL_VECTOR);

	assign_flame_owner = client;
	int team = GetClientTeam(client);
	for (int bot = 1; bot < MAXPLAYERS; ++bot)
		if (IsClientInGame(bot) && IsPlayerAlive(bot) && GetClientTeam(bot) != team)
		{
			//Living bot. (Technically "living enemy".) If within 200 HU, ignite 'em.
			float botpos[3]; GetClientAbsOrigin(bot, botpos);
			float dist = GetVectorDistance(target, botpos, true); //distance-squared
			if (dist < 40000.0) IgniteEntity(bot, 1.0);
		}
	assign_flame_owner = -1;
}

public Action player_pinged(int client, const char[] command, int argc)
{
	//Put code here to be able to easily trigger it from the client
	//By default, "player_ping" is bound to mouse3, and anyone who
	//plays Danger Zone will have it accessible somewhere.
	//PrintCenterText(client, "You pinged!");
	int entity = GetEntPropEnt(client, Prop_Send, "m_hPlayerPing");
	//PrintToStream("Client %d pinged [ping = %d]", client, entity);
	//if (entity != -1) CreateTimer(0.01, report_entity, entity, TIMER_FLAG_NO_MAPCHANGE);
	//report_new_entities = true; CreateTimer(1.0, unreport_new, 0, TIMER_FLAG_NO_MAPCHANGE);
	if (underdome_flg & UF_PHASEPING) //ENABLED by game mode
	{
		//If entity isn't -1, you're already phasepinging. This needs to cancel
		//the current phaseping and start a new one. Since cancelling timers is
		//a bit fiddly, needs a properly-initialized and properly-reset array,
		//and isn't any easier than this ultimately, we instead just carry a
		//validation cookie with us; there's actually no code to check here.
		//On the other hand, if you just recently phasepinged, then we'll let
		//the ping happen, but not do any phasing.
		if (phaseping_cookie[client] < 0) return;
		Handle params;
		CreateDataTimer(1.5, phase_ping, params, TIMER_FLAG_NO_MAPCHANGE);
		WritePackCell(params, client);
		WritePackCell(params, ++phaseping_cookie[client]);
		ResetPack(params);
		//PrintToStream("Client %d phasepinged [cookie = %d]", client, phaseping_cookie[client]);
		//TODO: Flicker or highlight the player in a really obvious way (reset when the phase expires)
	}
	if (entity == -12) //Currently disabled
	{
		float pos[3]; GetClientEyePosition(client, pos);
		float angle[3]; GetClientEyeAngles(client, angle);
		TR_TraceRayFilter(pos, angle, MASK_PLAYERSOLID, RayType_Infinite, filter_notself, client);
		if (!TR_DidHit(INVALID_HANDLE)) {PrintToChat(client, "-- didn't hit --"); return;}
		char surface[128]; TR_GetSurfaceName(INVALID_HANDLE, surface, sizeof(surface));
		int ent = TR_GetEntityIndex(INVALID_HANDLE);
		char entdesc[64]; describe_weapon(ent, entdesc, sizeof(entdesc));
		PrintToChat(client, "You're looking at: %s / %s", surface, entdesc);
	}
	if (entity == -11) //Currently disabled
	{
		int next = GameRules_GetProp("m_nGuardianModeSpecialWeaponNeeded") + 1;
		GameRules_SetProp("m_nGuardianModeSpecialWeaponNeeded", next);
		PrintToChatAll("Setting special weapon code to %d", next);
	}
	if (num_puzzles && entity == -10) //Currently disabled
	{
		//In puzzle mode, allow people to ping weapons as they see them.
		//Not currently working. Needs research.
		float pos[3];
		GetClientEyePosition(client, pos);
		//TODO: Trace out and find a nearby weapon (not just a ray trace, be generous)
		PrintToChatAll("Pinging at (%.2f,%.2f,%.2f)", pos[0], pos[1], pos[2]);
		int ping = CreateEntityByName("info_player_ping");
		DispatchSpawn(ping);
		//SetEntPropEnt(ping, Prop_Send, "m_hOwnerEntity", client);
		//SetEntProp(ping, Prop_Send, "m_hPlayer", client);
		SetEntPropEnt(client, Prop_Send, "m_hPlayerPing", ping);
		SetEntProp(ping, Prop_Send, "m_iTeamNum", 3);
		//SetEntProp(ping, Prop_Send, "m_iType", 0);
		TeleportEntity(ping, pos, NULL_VECTOR, NULL_VECTOR);
	}
	if (entity == -9) //Currently disabled
	{
		float pos[3]; GetClientAbsOrigin(client, pos);
		for (int cl = 1; cl < MaxClients; ++cl) if (IsClientInGame(cl)) blow_smoke(cl, pos);
	}
	if (entity == -8) //Currently disabled
	{
		char buf[128] = "Ammo:";
		for (int off = 0; off < 32; ++off)
			Format(buf, sizeof(buf), "%s %d", buf, GetEntProp(client, Prop_Data, "m_iAmmo", _, off));
		PrintToChatAll(buf);
	}
	if (entity == -7) //Currently disabled
	{
		char name[64]; GetClientName(client, name, sizeof(name));
		PrintToChatAll("%s just acquired a TA Grenade", name);
		GivePlayerItem(client, "weapon_tagrenade");
	}
	if (entity == -6) //Currently disabled
	{
		char name[64]; GetClientName(client, name, sizeof(name));
		float pos[3]; GetClientAbsOrigin(client, pos);
		//TODO: Ping the crosshair (trace out through eye angles until
		//impact) as well as the current position.
		PrintToStream("%s pinged at %.2f, %.2f, %.2f", name, pos[0], pos[1], pos[2]);
	}
}

int last_attacker[MAXPLAYERS+1], last_inflictor[MAXPLAYERS+1], last_weapon[MAXPLAYERS+1], crippled_status[MAXPLAYERS+1];
int is_crippled(int client)
{
	if (!GetConVarInt(sm_drzed_crippled_health)) return 0; //Crippling isn't active, so you aren't crippled.
	return GetEntPropFloat(client, Prop_Send, "m_flMaxspeed") < BASE_SPEED;
}
void kill_crippled_player(int client)
{
	//Finally kill the player (for any reason)
	int inflictor = last_inflictor[client], attacker = last_attacker[client], weapon = last_weapon[client];
	//If the attacker is no longer in the game, treat it as suicide. This
	//follows the precedent of a molly thrown by a ragequitter.
	if (attacker && !IsClientInGame(attacker)) attacker = client;
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
	float spd = GetConVarFloat(sm_drzed_crippled_speed);
	if (spd >= BASE_SPEED) spd = 50.0;
	if (spd < 1.0) spd = 10.0;
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", spd);
	//SetEntProp(client, Prop_Send, "m_ArmorValue", 0); //If needed, remove armor from crippled people
	//Switch to knife. If you have no knife, you switch to a non-weapon.
	SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", GetPlayerWeaponSlot(client, 2));
	if (GetEntProp(client, Prop_Send, "m_bIsScoped"))
	{
		SetEntProp(client, Prop_Send, "m_iFOV", 90);
		SetEntProp(client, Prop_Send, "m_bIsScoped", 0);
		SetEntProp(client, Prop_Send, "m_bResumeZoom", 0);
	}
	CreateTimer(0.2, crippled_health_drain, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	crippled_status[client] = -1; //Damage protection active.
	CreateTimer(1.0, remove_cripple_prot, client, TIMER_FLAG_NO_MAPCHANGE);
}
void uncripple(int client)
{
	if (!GetConVarInt(sm_drzed_crippled_health)) return;
	SetEntityHealth(client, GetConVarInt(sm_drzed_crippled_health) + 50);
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", BASE_SPEED);
	//SetEntProp(client, Prop_Send, "m_ArmorValue", 5); //Optionally give armor back (if it's removed on crippling)
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

bool was_jumping[MAXPLAYERS + 1];
int strafing_max[MAXPLAYERS + 1]; //Number of ticks strafing at max speed (for that weapon)
int strafing_fast[MAXPLAYERS + 1]; //Number of ticks strafing above 34% but not at max
int strafing_slow[MAXPLAYERS + 1]; //Below 34% but not zero
int strafing_stopped[MAXPLAYERS + 1]; //At zero speed
float autosmoke_pitch = 1024.0, autosmoke_yaw; //Invalid value as sentinel
int autosmoke_lasttick = -1, autosmoke_needjump = 0;
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float desiredvelocity[3], float angles[3],
	int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	//IN_ALT1 comes from the commands "+alt1" in client, and appears to have no effect
	//IN_ZOOM appears to have the same effect as ATTACK2 on weapons with scopes, and also
	//on the knife. Yes, "+zoom" will backstab with a knife. But it won't light a molly.
	//IN_LEFT/IN_RIGHT rotate you, like a 90s video game. Still active but nobody uses
	//(other than the old "+right and go AFK" trick).
	//Holding Shift will activate IN_SPEED, not IN_WALK or IN_RUN.
	//IN_GRENADE1/2 correspond to "+grenade1/2" but have no visible effect.
	/*PrintCenterText(client, "Buttons: %s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s",
		buttons & IN_ATTACK ? "IN_ATTACK " : "",
		buttons & IN_JUMP ? "IN_JUMP " : "",
		buttons & IN_DUCK ? "IN_DUCK " : "",
		buttons & IN_FORWARD ? "IN_FORWARD " : "",
		buttons & IN_BACK ? "IN_BACK " : "",
		buttons & IN_USE ? "IN_USE " : "",
		buttons & IN_CANCEL ? "IN_CANCEL " : "",
		buttons & IN_LEFT ? "IN_LEFT " : "",
		buttons & IN_RIGHT ? "IN_RIGHT " : "",
		buttons & IN_MOVELEFT ? "IN_MOVELEFT " : "",
		buttons & IN_MOVERIGHT ? "IN_MOVERIGHT " : "",
		buttons & IN_ATTACK2 ? "IN_ATTACK2 " : "",
		buttons & IN_RUN ? "IN_RUN " : "",
		buttons & IN_RELOAD ? "IN_RELOAD " : "",
		buttons & IN_ALT1 ? "IN_ALT1 " : "",
		buttons & IN_ALT2 ? "IN_ALT2 " : "",
		buttons & IN_SCORE ? "IN_SCORE " : "",
		buttons & IN_SPEED ? "IN_SPEED " : "",
		buttons & IN_WALK ? "IN_WALK " : "",
		buttons & IN_ZOOM ? "IN_ZOOM " : "",
		buttons & IN_WEAPON1 ? "IN_WEAPON1 " : "",
		buttons & IN_WEAPON2 ? "IN_WEAPON2 " : "",
		buttons & IN_BULLRUSH ? "IN_BULLRUSH " : "",
		buttons & IN_GRENADE1 ? "IN_GRENADE1 " : "",
		buttons & IN_GRENADE2 ? "IN_GRENADE2 " : "",
		buttons & IN_ATTACK3 ? "IN_ATTACK3 " : ""
	);*/
	if (GetConVarInt(insta_respawn_damage_lag)
		&& (buttons & (IN_ATTACK | IN_ATTACK2 | IN_ATTACK3 | IN_USE))
		&& damage_lag_is_immune(client))
	{
		PrintCenterText(client, "-- You are dead --");
		buttons &= ~(IN_ATTACK | IN_ATTACK2 | IN_ATTACK3 | IN_USE);
		return Plugin_Changed;
	}
	if (buttons & IN_JUMP)
	{
		/* TODO: Govern this with a cvar to permit double jump

		if (!was_jumping[client] && !(GetEntityFlags(client) & FL_ONGROUND))
		{
			//SetEntityGravity(client, -GetEntityGravity(client)); //For the lulz.
			float velo[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velo);
			//Is it okay for the total vector magnitude to be higher than total speed?
			if (velo[2] >= 0.0) velo[2] = 240.0;
			else velo[2] += 240.0;
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velo);
		}
		*/
		was_jumping[client] = true;
	}
	else was_jumping[client] = false;

	//When you're not firing, reset your spray count for Sally, Semi-Auto, etc
	if ((buttons & (IN_ATTACK | IN_ATTACK2 | IN_ATTACK3)) == 0) spray_count[client] = 0;

	if (IsPlayerAlive(client) && is_crippled(client))
	{
		//While you're crippled, you can't do certain things. There may be more restrictions to add.
		//You can't defuse or pick up weapons (IN_USE). You can't change speed (walk mode, IN_SPEED).
		//Should you be prevented from jumping (IN_JUMP)?
		//What's IN_CANCEL?
		//Can the game force you to drop a carried hostage?
		int invalid = IN_USE | IN_SPEED;
		//Should you be forced to crouch (IN_DUCK)? Looks good to others, but the client simulates
		//it and keeps on uncrouching you, which looks ugly.
		int mandatory = 0;
		int btn = (buttons & ~invalid) | mandatory;
		if (btn != buttons)
		{
			buttons = btn;
			return Plugin_Changed;
		}
	}
	int st = GetConVarInt(learn_stutterstep);
	if (st)
	{
		//Set learn_stutterstep to 2 to alert your current strafe direction while strafing, or to 3 to show it always.
		if (st == 2 || st == 3)
		{
			if ((buttons & (IN_MOVELEFT|IN_MOVERIGHT)) || st >= 3)
				PrintCenterText(client, "Strafing %s%s", buttons & IN_MOVELEFT ? " Left" : "", buttons & IN_MOVERIGHT ? " Right" : "");
			else
				PrintCenterText(client, "");
		}
		int dir = (buttons & IN_MOVELEFT ? -1 : 0) + (buttons & IN_MOVERIGHT ? 1 : 0); //Why doesn't && work for these??
		if (st == 4)
		{
			//Set learn_stutterstep to 4 to get some metrics on acceleration.
			//Whenever you change strafe direction, it shows the number of ticks
			//that were spent stopped, <34%, >34%, and at max speed.
			//It takes just as long to accelerate to max speed regardless of your
			//weapon, meaning that acceleration is faster with a knife than with
			//a Negev. If you set sv_maxspeed to 150, a knife will top out at 150
			//before a Negev does.
			if (strafe_direction[client] != dir)
			{
				PrintToChat(client, "Now strafing %s%s; max %d, fast %d, slow %d, stopped %d",
					buttons & IN_MOVELEFT ? " Left" : "", buttons & IN_MOVERIGHT ? " Right" : "",
					strafing_max[client], strafing_fast[client], strafing_slow[client], strafing_stopped[client]
				);
				strafing_max[client] = strafing_fast[client] = strafing_slow[client] = strafing_stopped[client] = 0;
			}
			float vel[3];
			vel[0] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
			vel[1] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
			vel[2] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[2]");
			float spd = GetVectorLength(vel, false); //Should be equal to what cl_showpos tells you your velocity is
			float maxspeed = current_weapon_speed[client];
			if (maxspeed == 0.0) maxspeed = 250.0; //Or use the value from sv_maxspeed?
			if (spd == 0.0) ++strafing_stopped[client];
			else if (spd <= maxspeed * 0.34) ++strafing_slow[client];
			else if (spd <= maxspeed - 1.0) ++strafing_fast[client];
			else ++strafing_max[client];
		}
		strafe_direction[client] = dir;
	}
	if (underdome_flg & UF_DISABLE_SCOPING)
	{
		//If you're holding a sniper rifle or scoped rifle, disallow zooming
		int weap = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (weap > 0)
		{
			char cls[64]; GetEntityClassname(weap, cls, sizeof(cls));
			if (!strcmp(cls, "weapon_awp") || !strcmp(cls, "weapon_ssg08") || !strcmp(cls, "weapon_scar20")
				|| !strcmp(cls, "weapon_g3sg1") || !strcmp(cls, "weapon_aug") || !strcmp(cls, "weapon_sg556"))
			{
				buttons &= ~(IN_ZOOM | IN_ATTACK2);
				return Plugin_Changed;
			}
		}
	}
	if ((underdome_flg & UF_DISABLE_AUTOMATIC_FIRE) && spray_count[client])
	{
		int weap = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (weap > 0)
		{
			//If you've fired without letting up the mouse button, delay the next shot.
			//So long as you keep the button held, this will keep delaying shots.
			//TODO: Save the *actual* next attack time, and when you release the button,
			//reinstate it. That way, we can set this to a crazy-high value like "now + 1.0"
			//and it should get rid of the client-side "oops I think I fired a shot" problem.
			float next = GetEntPropFloat(weap, Prop_Send, "m_flNextPrimaryAttack");
			float wait = GetGameTime() + 0.1;
			if (next < wait) SetEntPropFloat(weap, Prop_Send, "m_flNextPrimaryAttack", wait);
		}
	}
	#if 0
	if ((buttons & IN_ALT1) && GetConVarInt(sm_drzed_hack) >= 10)
	{
		//Lag out the server to see what happens. This pretends to be a really badly written aimbot.
		//Coding style heavily inspired by posts on TheDailyWTF. This is overelaborate and just bad.
		//(How many atrocious examples can you find here?)
		float base[3]; GetClientEyePosition(client, base);
		int nearest = -1, tries = 0;
		char message[256]; Format(message, sizeof(message), "Distances: ");
		for (int cl = 1; cl < MAXPLAYERS; ++cl) if (IsClientInGame(cl))
		{
			PrintCenterText(cl, "You are client %d, and client %d is lagging the server.", cl, client);
			if (cl == client || !IsPlayerAlive(cl)) continue;
			for (int i = 0; i < GetConVarInt(sm_drzed_hack); ++i) //Lag scale factor
			{
				++tries;
				float pos[3]; GetClientEyePosition(cl, pos);
				float dist = GetVectorDistance(base, pos, false); //Inefficiently demand the actual distance, not d^2
				char tmp[256]; Format(tmp, sizeof(tmp), "%s", message);
				Format(message, sizeof(message), "%s%.0f, ", tmp, dist);
				//Also inefficiently: Track the client ID of the nearest client, but don't cache the distance.
				if (nearest != -1)
				{
					float otherpos[3]; GetClientEyePosition(nearest, otherpos);
					float otherdist = GetVectorDistance(base, otherpos, false);
					if (otherdist < dist) continue;
				}
				nearest = cl;
			}
		}
		if (nearest != -1)
		{
			char name[64]; GetClientName(nearest, name, sizeof(name));
			float otherpos[3]; GetClientEyePosition(nearest, otherpos);
			float otherdist = GetVectorDistance(base, otherpos, false);
			PrintCenterText(client, "[%d tries] The nearest player to you is %s%s, %.0f away",
				tries, IsFakeClient(nearest) ? "BOT " : "", name, otherdist);
			//Remove the last two characters from the message
			char fmt[256]; Format(fmt, sizeof(fmt), "%%%d.%ds", strlen(message) - 2, strlen(message) - 2);
			char msg[256]; Format(msg, sizeof(msg), fmt, message);
			//PrintCenterText(client, msg);
		}
	}
	#endif
	if ((buttons & IN_ALT1) && GetConVarInt(learn_smoke))
	{
		//Autofire smokes while +alt1 is active
		//Go somewhere and !mark. Set the six cvars to define a box.
		//Have nothing but a smoke in hand. Activate alt1, and watch the smokes fly!
		int tick = GetGameTickCount();
		int since = tick - autosmoke_lasttick;
		if (autosmoke_pitch != 2048.0 && since > 88) //96 works, 64 doesn't, 80 is unreliable
		{
			//Throw a smoke - max one per second
			float angle[3] = {0.0, 0.0, 0.0};
			if (autosmoke_pitch == 1024.0)
			{
				autosmoke_pitch = GetConVarFloat(autosmoke_pitch_min);
				autosmoke_yaw = GetConVarFloat(autosmoke_yaw_min);
			}
			angle[0] = autosmoke_pitch; angle[1] = autosmoke_yaw;
			autosmoke_yaw += GetConVarFloat(autosmoke_yaw_delta);
			if (autosmoke_yaw > GetConVarFloat(autosmoke_yaw_max))
			{
				autosmoke_yaw = GetConVarFloat(autosmoke_yaw_min);
				autosmoke_pitch += GetConVarFloat(autosmoke_pitch_delta);
				if (autosmoke_pitch > GetConVarFloat(autosmoke_pitch_max)) autosmoke_pitch = 2048.0; //All done!
			}
			float not_moving[3] = {0.0, 0.0, 0.0};
			TeleportEntity(client, marked_pos, angle, not_moving);
			PrintToChat(client, "Attacking b/c lasttick %d tick %d since %d - %.2f,%.2f", autosmoke_lasttick, tick, since, angle[0], angle[1]);
			buttons |= IN_ATTACK;
			autosmoke_lasttick = tick; autosmoke_needjump = 1;
			return Plugin_Changed;
		}
		if (autosmoke_needjump && since > 0)
		{
			//One tick (or thereabouts) after throwing a smoke, release attack and hit jump.
			PrintToChat(client, "Jumping - lasttick %d tick %d since %d", autosmoke_lasttick, tick, since);
			//FIXME: Should this be &=~ ? And correspondingly below. Check intent here.
			buttons &= IN_ATTACK;
			buttons |= IN_JUMP;
			autosmoke_needjump = 0;
			return Plugin_Changed;
		}
		//PrintToChat(client, "Neither b/c lasttick %d tick %d since %d", autosmoke_lasttick, tick, since);
		buttons &= IN_JUMP | IN_ATTACK;
		return Plugin_Changed;
	}
	if (IsFakeClient(client) && (GetEntityFlags(client) & FL_ATCONTROLS))
	{
		//Bots placed in specific locations have the "at controls" flag to stop
		//them from moving. We'll also stop them from attacking.
		buttons &= ~(IN_ATTACK | IN_ATTACK2 | IN_ATTACK3);
		return Plugin_Changed;
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

Action show_underdome_mode(Handle timer, any entity) {PrintCenterTextAll(underdome_intro[underdome_mode - 1]);}

Action underdome_tick(Handle timer, any data)
{
	if (!underdome_mode) {underdome_ticker = INVALID_HANDLE; return Plugin_Stop;}
	if (underdome_flg & UF_FREEBIES)
	{
		int max_nades = GetConVarInt(ammo_grenade_limit_total);
		for (int client = 1; client < MaxClients; ++client)
		{
			if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client)) continue;
			int have_he = GetEntProp(client, Prop_Data, "m_iAmmo", _, 14);
			int have_flash = GetEntProp(client, Prop_Data, "m_iAmmo", _, 15);
			int have_smoke = GetEntProp(client, Prop_Data, "m_iAmmo", _, 16);
			int have_molly = GetEntProp(client, Prop_Data, "m_iAmmo", _, 17);
			int have_decoy = GetEntProp(client, Prop_Data, "m_iAmmo", _, 18);
			int have_ta = GetEntProp(client, Prop_Data, "m_iAmmo", _, 22);
			int total_nades = have_he + have_flash + have_smoke + have_molly + have_decoy + have_ta;
			if ((underdome_flg & UF_FREE_HEGRENADE) && !have_he && total_nades < max_nades)
				GivePlayerItem(client, "weapon_hegrenade");
			if ((underdome_flg & UF_FREE_FLASHBANG) && !have_flash && total_nades < max_nades)
				GivePlayerItem(client, "weapon_flashbang");
			if ((underdome_flg & UF_FREE_MOLLY) && !have_molly && total_nades < max_nades)
				GivePlayerItem(client, "weapon_molotov");
			if ((underdome_flg & UF_FREE_TAGRENADE) && !have_ta && total_nades < max_nades)
				GivePlayerItem(client, "weapon_tagrenade");
		}
	}
	if (underdome_flg & UF_VAMPIRIC)
	{
		//Give all the bots a bit more health. You have to kill 'em fast.
		for (int client = 1; client < MaxClients; ++client)
		{
			if (!IsClientInGame(client) || !IsPlayerAlive(client) || !IsFakeClient(client)) continue;
			int hp = GetClientHealth(client);
			if (hp < 200) SetEntityHealth(client, hp < 190 ? hp + 10 : 200);
		}
	}
	adjust_underdome_gravity(); //Just in case
	return Plugin_Continue;
}

void devise_underdome_rules()
{
	int m = randrange(sizeof(underdome_flags) - 1) + 1;
	killsneeded = GameRules_GetProp("m_nGuardianModeSpecialKillsRemaining");
	//First wave? Force it to the warmup settings.
	if (killsneeded == GetConVarInt(mp_guardian_special_kills_needed)) m = 0;
	//Finished? Don't do anything.
	else if (killsneeded <= 0) {reset_underdome_config(); return;}
	int cfg = GetConVarInt(guardian_underdome_waves);
	if (cfg > sizeof(underdome_flags))
	{
		//Tried to set it to an invalid value. Dump a list of values to the console.
		PrintToServer("guardian_underdome_waves too high, use either 1 or 2..%d", sizeof(underdome_flags));
		for (int i = 1; i < sizeof(underdome_flags); ++i)
			PrintToServer("guardian_underdome_waves %d // %s", i + 1, underdome_intro[i]);
		SetConVarInt(guardian_underdome_waves, 1);
		//And don't change m (ie it'll stay randomized)
	}
	else if (cfg > 1) m = cfg - 1;
	//GameRules_SetProp("m_nGuardianModeSpecialWeaponNeeded", ???); //Change the gun displayed on the middle left of the screen
	underdome_mode = m + 1;
	int flg = underdome_flg = underdome_flags[m];
	PrintToChatAll(underdome_intro[m]);
	CreateTimer(0.25, show_underdome_mode, 0, TIMER_FLAG_NO_MAPCHANGE);
	if ((underdome_flags[m] & UF_NEED_TIMER) && underdome_ticker == INVALID_HANDLE)
		underdome_ticker = CreateTimer(7.0, underdome_tick, 0, TIMER_REPEAT);
	SetConVarString(mp_guardian_special_weapon_needed, underdome_needed[m]);

	if (flg & UF_LOW_ACCURACY) SetConVarFloat(weapon_recoil_scale, 3.0);
	else if (flg & UF_HIGH_ACCURACY) SetConVarFloat(weapon_recoil_scale, 0.5); //Maybe "weapon_accuracy_nospread 1" as well?
	else SetConVarFloat(weapon_recoil_scale, 2.0);

	if (flg & UF_VAMPIRIC) SetConVarFloat(mp_damage_vampiric_amount, 0.25);
	else SetConVarFloat(mp_damage_vampiric_amount, 0.0);

	float knife = (flg & UF_KNIFE_FOCUS) ? 0.125 : 1.0;
	SetConVarFloat(mp_damage_scale_ct_head, ((flg & UF_NO_HEADSHOTS) ? 0.25 : 1.0) * knife);
	SetConVarFloat(mp_damage_scale_t_head, ((flg & UF_NO_HEADSHOTS) ? 0.25 : 1.0) * knife);
	SetConVarFloat(mp_damage_scale_ct_body, ((flg & UF_HEADSHOTS_ONLY) ? 0.0 : 1.0) * knife);
	SetConVarFloat(mp_damage_scale_t_body, ((flg & UF_HEADSHOTS_ONLY) ? 0.25 : 1.0) * knife); //The AI cheats.

	adjust_underdome_gravity();
}

float armory_positions[][3] = {
	{-242.552642, -841.306030, 266.671295},
	{-340.010864, -1103.308471, 88.031250},
	{-1302.787597, -888.107421, 92.031250},
	{-427.399749, -286.893615, 72.031250},
	{-1478.015991, -82.491691, 37.631965},
};
char armory_weapons[][] = {
	"weapon_usp_silencer",
	"weapon_mp5sd",
};
public void round_started(Event event, const char[] name, bool dontBroadcast)
{
	if (GetConVarInt(disable_warmup_arenas) && GameRules_GetProp("m_bWarmupPeriod"))
	{
		//Attempt to disable the 1v1 warmup arenas by removing the logic scripts
		//that activate them. Unfortunately this doesn't really work cleanly, and
		//will result in a noisy spam on the console as the script (which already
		//got loaded) crashes out trying to do things. But it DOES allow us to use
		//warmup the way we always have: as a way to explore the map and do things
		//without worrying about respawns, rounds, people joining late, etc.
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, "logic_script")) != -1)
		{
			char entname[64]; GetEntPropString(ent, Prop_Send, "m_iName", entname, sizeof(entname));
			if (!strncmp(entname, "arena", 5) && !strcmp(entname[6], "-script")) //eg arena1-script
				AcceptEntityInput(ent, "Kill");
			//else PrintToServer("logic_script %d: %s (%s)", ent, entname, entname[6]);
		}
		//SetConVarInt(FindConVar("sv_disable_radar"), 0); //The script disables radar but this doesn't reenable it
	}
	char placements[1024]; GetConVarString(bot_placement, placements, sizeof(placements));
	update_bot_placements(bot_placement, "", placements);
	if (GetConVarInt(guardian_underdome_waves) && !GameRules_GetProp("m_bWarmupPeriod"))
	{
		for (int i = 0; i < 2; ++i)
		{
			//Spawn weapons in a little cache at one of several randomly-selected locations.
			int a = randrange(5);
			for (int w = 0; w < sizeof(armory_weapons); ++w)
			{
				int weap = CreateEntityByName(armory_weapons[w]);
				DispatchSpawn(weap);
				TeleportEntity(weap, armory_positions[a], NULL_VECTOR, NULL_VECTOR);
			}
		}
		devise_underdome_rules();
	}
	else reset_underdome_config();
}

/* So, uhh.... this is one of those cases where I have NO idea what's wrong.
Apparently, the healthbonus_for_warmup flag is getting reset unexpectedly.
Having a few shims appears to prevent this. Cannot find any bug in my code,
but if anyone else does, PLEASE let me know. */
int healthbonus_for_warmup; //Bonuses gained in warmup deathmatch don't carry over
public int shim1;
public int shim2;
public int shim3;
int healthbonus[66]; //Has to be a bit bigger than MAXPLAYERS
int heal_cooldown_tick[66];
void reset_health_bonuses() {for (int i = 0; i < sizeof(healthbonus); ++i) healthbonus[i] = heal_cooldown_tick[i] = 0;}
public void OnMapStart() {reset_health_bonuses();}

bool filter_notself(int entity, int flags, int self) {/*PrintToServer("filter: %d/%x/%d", entity, flags, self);*/ return entity != self;}
public void player_hurt(Event event, const char[] name, bool dontBroadcast)
{
	/*
	short	userid		player index who was hurt
	short	attacker	player index who attacked
	byte	health		remaining health points
	byte	armor		remaining armor points
	string	weapon		weapon name attacker used, if not the world
	short	dmg_health	damage done to health
	byte	dmg_armor	damage done to armor
	byte	hitgroup	hitgroup that was damaged
	*/
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	char vicname[64]; GetClientName(victim, vicname, sizeof(vicname));
	char atkname[64]; GetClientName(attacker, atkname, sizeof(atkname));
	char weapon[64]; event.GetString("weapon", weapon, sizeof(weapon));
	//Regions: Head = 1, Chest, Stomach, Left Arm, Right Arm, Left Leg, Right Leg = 7
	char region[][] = {"unknown", "head", "chest", "stomach",
		"left arm", "right arm", "left leg", "right leg"};
	//Multipliers: [1.0, 4.0, 1.0, 1.25, 1.0, 1.0, 0.75, 0.75]
	//Dealing X damage to a particular region will actually cost X * multiplier
	//hitpoints. That's why you want dem headshots! (Legs are unarmored. Other
	//than that, legshots suck. You knew that.)
	//Reciprocals: [60, 15, 60, 48, 60, 60, 80, 80]
	//Multiplying the actual damage done by the reciprocal of the multiplier
	//will get back to a consistent value. These reciprocals are, in effect,
	//fractions of sixty; to get back to "base damage", you would need to then
	//divide by 60. As with many calculations, though, we don't need the pure
	//base value, just something consistent (cf "distance squared" calcs).
	int scaling[] = {60, 15, 60, 48, 60, 60, 80, 80};
	int location = event.GetInt("hitgroup");
	int mindamage = event.GetInt("dmg_health") + event.GetInt("dmg_armor") * 2;
	int maxdamage = mindamage;
	if (event.GetInt("dmg_armor"))
	{
		//Armor takes off half the damage, and the damage to armor is half
		//what it prevented. That introduces more rounding error, but the
		//damages are ALWAYS rounded down, so we can cap it.
		maxdamage += 2;
		if (maxdamage > event.GetInt("dmg_health") * 2) maxdamage = event.GetInt("dmg_health") * 2;
	}
	maxdamage++; //There could be up to 1hp of rounding in the base damage.
	PrintToStream("%s hit %s in %s with %s: %dhp+%dac: %d-%d",
		atkname, vicname, region[location], weapon,
		event.GetInt("dmg_health"), event.GetInt("dmg_armor"),
		mindamage * scaling[location], maxdamage * scaling[location]
	);

	//-- the below is broken, don't trust it --
	//Calculate the distance the shot travelled before landing:
	//1) Get attacker eye position and angles
	float pos[3]; GetClientEyePosition(attacker, pos);
	float angle[3]; GetClientEyeAngles(attacker, angle);
	//2) Trace from there, RayType_Infinite
	TR_TraceRayFilter(pos, angle, MASK_SHOT, RayType_EndPoint, filter_notself, attacker);
	if (!TR_DidHit(INVALID_HANDLE)) {PrintToStream("-- didn't hit --"); return;}
	//3) TR_GetFraction for distance
	float target[3]; TR_GetEndPosition(target, INVALID_HANDLE);
	float len = GetVectorDistance(pos, target, false);
	//4) Validate TR_GetHitGroup and TR_GetEntityIndex
	PrintToStream("Shot range: %.2f --- Hit %d/%d in the %d/%d", len,
		TR_GetEntityIndex(INVALID_HANDLE), victim, TR_GetHitGroup(INVALID_HANDLE), location);
}

public void weapon_reload(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	//This event happens only if you press R (not if you fully empty your clip),
	//and only if you didn't have a full mag already - unless you're running a
	//shotgun, in which case pressing R will spam a few spurious events - unless
	//you're using a MAG-7, which behaves like other magazinned weapons. It's
	//like figuring out if it's a leap year.
	//So if you're running a Sawed-Off, Nova, or XM1014, don't tap R.
	if (anarchy[client]) PrintCenterText(client, "You reloaded prematurely, wasting %d anarchy!", anarchy[client]);
	anarchy[client] = 0; anarchy_available[client] = 0;
	if (GetConVarInt(learn_stutterstep)) show_stutterstep_stats(client);
}

public void player_team(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	healthbonus[client] = heal_cooldown_tick[client] = 0;
}

int plant_bomb()
{
	int bomb = CreateEntityByName("planted_c4");
	DispatchSpawn(bomb);
	float site[3];
	//Pick a bomb site at random, assuming we have two
	//NOTE: Not all sites work on all maps. By moving up 100 HU before scanning
	//down to find ground, we make a good few work that otherwise wouldn't (eg
	//both sites on de_train), but it's also possible that this would break some
	//sites that have a low ceiling. Have tested de_dust2, de_inferno, de_mirage,
	//de_cache, all fine. On de_nuke, site A is inaccessible; on de_vertigo, both
	//sites have some sort of strange problem; de_overpass site A requires a two
	//man boost or a strafe jump. Any map with only a single bomb site won't work;
	//any map with spawn locations that can't be reached from elsewhere won't work.
	GetEntPropVector(FindEntityByClassname(-1, "cs_player_manager"), Prop_Send,
		GetURandomFloat() < 0.5 ? "m_bombsiteCenterA" : "m_bombsiteCenterB", site);
	float down[3] = {90.0, 0.0, 0.0}; //No, it's not (0,0,-1); this is actually a direction, not a delta-position.
	site[2] += 100.0;
	TR_TraceRay(site, down, MASK_SOLID, RayType_Infinite);
	if (TR_DidHit(INVALID_HANDLE)) TR_GetEndPosition(site, INVALID_HANDLE);
	TeleportEntity(bomb, site, NULL_VECTOR, NULL_VECTOR);
	SetEntProp(bomb, Prop_Send, "m_bBombTicking", 1);
	return bomb;
}

public void Event_PlayerChat(Event event, const char[] name, bool dontBroadcast)
{
	//if (!event.GetBool("teamonly")) return; //Require team chat (not working - there's no "teamonly" so it always returns 0)
	int self = GetClientOfUserId(event.GetInt("userid"));
	char msg[64];
	event.GetString("text", msg, sizeof(msg));
	//TODO some time: Break out all these handlers into functions, and build a
	//hashtable of "!heal" ==> function. Split the message on the first space,
	//look it up in the misnamed "trie", and then call the function.
	if (0 && !strcmp(msg, "!hack"))
	{
		int max = GetMaxEntities();
		StringMap entcount = CreateTrie();
		for (int ent = 0; ent < max; ++ent) if (IsValidEntity(ent))
		{
			char cls[64]; GetEntityClassname(ent, cls, sizeof(cls));
			int count = 0;
			if (!GetTrieValue(entcount, cls, count)) count = 0;
			SetTrieValue(entcount, cls, count + 1);
		}
		//Iterate over the trie, reporting the counts.
		//It'd be really nice to use collections.Counter and report them in frequency order.
		Handle snap = CreateTrieSnapshot(entcount);
		for (int i = 0; i < TrieSnapshotLength(snap); ++i)
		{
			char cls[64]; GetTrieSnapshotKey(snap, i, cls, sizeof(cls));
			int count = 0; GetTrieValue(entcount, cls, count);
			PrintToServer("[%4d] %s", count, cls);
		}
		CloseHandle(snap);
		CloseHandle(entcount);
		return;
	}
	if (0 && !strcmp(msg, "!hack"))
	{
		int ent = CreateEntityByName("game_player_equip");
		DispatchKeyValue(ent, "spawnflags", "5"); //or 3 to strip ALL weapons away - even the knife (unless explicitly granted)
		DispatchKeyValue(ent, "weapon_mac10", "0"); //You'll get skinned weapons (only) if they're equipped for the team you're on
		DispatchKeyValue(ent, "weapon_tagrenade", "0"); //Grenades can be given too
		DispatchKeyValue(ent, "item_kevlar", "0"); //Armor w/o helmet
		//DispatchKeyValue(ent, "weapon_fists", "0"); //Doesn't seem to work though. Oh well.
		AcceptEntityInput(ent, "Use", self, -1, 0);
		PrintToChatAll("Equipment delivered.");
	}
	if (num_puzzles && !strcmp(msg, "!solve"))
	{
		PrintToChat(self, "Unsure how to solve the puzzle? Attempt to defuse the bomb for a clue!");
		return;
	}
	if (puzzles_solved[self] < num_puzzles && !strncmp(msg, "!solve ", 7) && !puzzle_endgame)
	{
		if (puzzle_value[puzzles_solved[self]] == -1.0)
		{
			//Keyword solution mode. The clue will give a small set of options, and
			//exactly one of them is right; the others will kill you.
			if (!strcmp(msg, puzzle_solution[puzzles_solved[self]], false))
			{
				//Will only happen if puzzle_solution[n] is a valid string (not "!solve"),
				//and therefore that puzzle_value[n] is -1.
				if (++puzzles_solved[self] == num_puzzles)
				{
					PrintToChatAll("That's it! All puzzles solved! Someone, hurry, use your defuse kit!");
					puzzle_endgame = 2;
				}
				else PrintToChat(self, "You've solved puzzle %d! Go tap the bomb again!", puzzles_solved[self]);
				return;
			}
			PrintToChatAll("BOOOOOOM!");
			int bomb = FindEntityByClassname(-1, "planted_c4");
			if (bomb == -1) return;
			puzzle_endgame = 1;
			SetEntPropFloat(bomb, Prop_Send, "m_flC4Blow", GetGameTime() + 4.0);
			return;
		}
		//It's a numeric challenge. Expect a value that's accurate to two decimal places.
		//For the most part, the values given will either be integers (which will be
		//completely accurate) or shown to two decimals eg armor penetration.
		float attempt = StringToFloat(msg[7]);
		if (!attempt)
		{
			//The solution will never be zero. Typing "!solve $3300" will trigger this.
			PrintToChat(self, "Just type '!solve' and the number, no punctuation.");
			return;
		}
		if (FloatAbs(attempt - puzzle_value[puzzles_solved[self]]) < 0.001)
		{
			if (++puzzles_solved[self] == num_puzzles)
			{
				PrintToChatAll("The code has been completed! Someone, hurry, use your defuse kit!");
				puzzle_endgame = 2;
			}
			else PrintToChat(self, "Correct! That was the next part of the code. Go tap the bomb again!");
			return;
		}
		//PrintToChat(self, "You entered: %f", attempt);
		//Open question: Should an error in a numerical challenge trigger the bomb?
		//Currently "yes" but this decision can be reversed.
		//Or should it cost you some seconds off the clock and let you keep going?
		int bomb = FindEntityByClassname(-1, "planted_c4");
		if (bomb == -1) return;
		puzzle_endgame = 1;
		SetEntPropFloat(bomb, Prop_Send, "m_flC4Blow", GetGameTime() + 4.0);
		return;
	}
	if (!strcmp(msg, "!noclue"))
	{
		for (int i = 0; i < num_puzzle_clues; ++i) puzzle_highlight(puzzle_clues[i], 0);
		PrintToChatAll("All clues have been unhighlighted.");
		return;
	}
	if (!strcmp(msg, "!allclue") && GetConVarInt(sm_drzed_allow_recall)) //Not really related to !recall, but it'll be used similarly.
	{
		PrintToChatAll("Total clues: %d", num_puzzle_clues);
		for (int i = 0; i < num_puzzle_clues; ++i) puzzle_highlight(puzzle_clues[i], 1);
		return;
	}
	if (!strcmp(msg, "!gotoclue") && GetConVarInt(sm_drzed_allow_recall))
	{
		for (int i = 0; i < num_puzzle_clues; ++i) if (puzzle_is_highlighted(puzzle_clues[i]))
		{
			float pos[3];
			GetEntPropVector(puzzle_clues[i], Prop_Data, "m_vecOrigin", pos);
			char player[64]; GetClientName(self, player, sizeof player);
			float lookdown[3] = {90.0, 0.0, 0.0};
			TeleportEntity(self, pos, lookdown, NULL_VECTOR);
			PrintToChatAll("Teleported %s to next highlighted clue.", player);
			return;
		}
		PrintToChat(self, "No highlighted clues.");
		return;
	}
	if (!strcmp(msg, "!entities"))
	{
		File fp = OpenFile("entities.log", "w");
		int ent = -1;
		char entnames[][] = {"trigger_survival_playarea", "info_map_region", "point_dz_weaponspawn", "func_hostage_rescue"};
		char mapname[64]; GetCurrentMap(mapname, sizeof(mapname));
		WriteFileLine(fp, "Searching %s for interesting entities...", mapname);
		for (int i = 0; i < sizeof(entnames); ++i)
		{
			int entcount = 0;
			while ((ent = FindEntityByClassname(ent, entnames[i])) != -1)
			{
				float pos[3]; GetEntPropVector(ent, Prop_Data, "m_vecOrigin", pos);
				float min[3]; GetEntPropVector(ent, Prop_Data, "m_vecMins", min);
				float max[3]; GetEntPropVector(ent, Prop_Data, "m_vecMaxs", max);
				//Hack! Only info_map_region has a location token.
				char location[64] = "";
				if (i == 1) GetEntPropString(ent, Prop_Send, "m_szLocToken", location, sizeof(location));
				WriteFileLine(fp, "%s: %.2f,%.2f,%.2f [%.2f,%.2f,%.2f - %.2f,%.2f,%.2f] %s", entnames[i],
					pos[0], pos[1], pos[2],
					min[0], min[1], min[2],
					max[0], max[1], max[2],
					location
				);
				++entcount;
			}
			WriteFileLine(fp, "== %d entities of class %s.", entcount, entnames[i]);
			PrintToChatAll("Found %d entities of class %s.", entcount, entnames[i]);
		}
		CloseHandle(fp);
		return;
	}
	if (0 && !strcmp(msg, "!moarentities"))
	{
		//23 named locations, want 200ish more spawns. So add 10 per location.
		//From each location, go up a few hundred HU, and out a random distance
		//with drop-off. Roll d20, and on a nat 20, reroll and add 20. Multiply
		//the result by 100 HU, pick a random angle 0-360, and plot that. Scan
		//down from that point until you hit ground. If you hit ground instantly
		//or you fail to hit ground after 1000 HU, abort and rerandomize. If you
		//hit water, find shore? Or put it there anyway? Or abort?
		//For first try, just place item_cash there. For the real thing, create a
		//new point_dz_weaponspawn.
		//Alas, creating more entities doesn't make the game use them - even if
		//they're created on map start :( Maybe they need to be activated in some
		//way? Or maybe there's just an array of them, stored internally, and
		//that's what the game ACTUALLY uses.
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, "info_map_region")) != -1)
		{
			char location[64] = ""; GetEntPropString(ent, Prop_Send, "m_szLocToken", location, sizeof(location));
			float pos[3]; GetEntPropVector(ent, Prop_Data, "m_vecOrigin", pos);
			PrintToStream("%s: %.2f,%.2f,%.2f", location, pos[0], pos[1], pos[2]);
			int placed = 0;
			for (int tries = 0; tries < 100 && placed < 10; ++tries)
			{
				int d = 0, dist = 0;
				while ((d = randrange(20) + 1) == 20) dist += 20;
				dist += d;
				float ang[3] = {0.0, 0.0, 0.0}; ang[1] = randrange(360) + 0.0;
				float dir[3]; GetAngleVectors(ang, dir, NULL_VECTOR, NULL_VECTOR);
				ScaleVector(dir, dist * 100.0);
				float loc[3]; AddVectors(pos, dir, loc);
				loc[2] += 400; //Give us a bit of altitude to make sure we don't run into terrain
				//Trace down till we hit terrain.
				float down[3] = {90.0, 0.0, 0.0}; //No, it's not (0,0,-1); this is actually a direction, not a delta-position.
				TR_TraceRay(loc, down, MASK_SOLID, RayType_Infinite);
				if (!TR_DidHit(INVALID_HANDLE)) continue;
				float ground[3]; TR_GetEndPosition(ground, INVALID_HANDLE);
				float fell = loc[2] - ground[2];
				if (fell < 20.0 || fell > 1000.0) continue;
				ground[2] += 20.0; //Lift us a bit above the ground for safety.
				int spawn = CreateEntityByName("point_dz_weaponspawn");
				DispatchSpawn(spawn);
				TeleportEntity(spawn, ground, NULL_VECTOR, NULL_VECTOR);
				++placed;
			}
		}
		return;
	}
	if (0 && !strcmp(msg, "!bomb"))
	{
		int bomb = plant_bomb();
		PrintToChatAll("Planted. Blow %.2f timer %.2f now %.2f",
			GetEntPropFloat(bomb, Prop_Send, "m_flC4Blow"),
			GetEntPropFloat(bomb, Prop_Send, "m_flTimerLength"),
			GetGameTime());
		return;
	}
	if (!strcmp(msg, "!mark"))
	{
		GetClientAbsOrigin(self, marked_pos);
		GetClientEyeAngles(self, marked_angle);
		//Locate an instance of some class and mark that position instead
		//int ent = FindEntityByClassname(-1, "weapon_zone_repulsor");
		//if (ent != -1) GetEntPropVector(ent, Prop_Send, "m_vecOrigin", marked_pos);
		PrintToChat(self, "Marked position: %f, %f, %f", marked_pos[0], marked_pos[1], marked_pos[2]);
		char placements[1024]; GetConVarString(bot_placement, placements, sizeof(placements));
		if (strlen(placements)) PrintToServer("bot_placement \"%s %f,%f,%f,%f,%f\"",
			placements, marked_pos[0], marked_pos[1], marked_pos[2], marked_angle[0], marked_angle[1]);
		return;
	}
	if (!strcmp(msg, "!mark2"))
	{
		GetClientAbsOrigin(self, marked_pos2);
		GetClientEyeAngles(self, marked_angle2);
		PrintToChat(self, "Marked position #2: %f, %f, %f", marked_pos2[0], marked_pos2[1], marked_pos2[2]);
		return;
	}
	if (!strcmp(msg, "!recall") && GetConVarInt(sm_drzed_allow_recall))
	{
		PrintToChat(self, "Returning to %f, %f, %f", marked_pos[0], marked_pos[1], marked_pos[2]);
		float not_moving[3] = {0.0, 0.0, 0.0};
		TeleportEntity(self, marked_pos, marked_angle, not_moving);
		return;
	}
	if (!strcmp(msg, "!recall2") && GetConVarInt(sm_drzed_allow_recall))
	{
		PrintToChat(self, "Returning to %f, %f, %f", marked_pos2[0], marked_pos2[1], marked_pos2[2]);
		float not_moving[3] = {0.0, 0.0, 0.0};
		TeleportEntity(self, marked_pos2, marked_angle2, not_moving);
		return;
	}
	if (!strcmp(msg, "!swap") && GetConVarInt(sm_drzed_allow_recall))
	{
		float tmp_pos[3], tmp_ang[3];
		GetClientAbsOrigin(self, tmp_pos);
		GetClientEyeAngles(self, tmp_ang);
		PrintToChat(self, "Swapping %f, %f, %f with %f, %f, %f",
			tmp_pos[0], tmp_pos[1], tmp_pos[2],
			marked_pos[0], marked_pos[1], marked_pos[2]);
		float not_moving[3] = {0.0, 0.0, 0.0};
		TeleportEntity(self, marked_pos, marked_angle, not_moving);
		marked_pos[0] = tmp_pos[0]; marked_pos[1] = tmp_pos[1]; marked_pos[2] = tmp_pos[2];
		marked_angle[0] = tmp_ang[0]; marked_angle[1] = tmp_ang[1]; marked_angle[2] = tmp_ang[2];
		return;
	}
	if (!strcmp(msg, "!swap2") && GetConVarInt(sm_drzed_allow_recall))
	{
		float tmp_pos[3], tmp_ang[3];
		GetClientAbsOrigin(self, tmp_pos);
		GetClientEyeAngles(self, tmp_ang);
		PrintToChat(self, "Swapping %f, %f, %f with %f, %f, %f",
			tmp_pos[0], tmp_pos[1], tmp_pos[2],
			marked_pos2[0], marked_pos2[1], marked_pos2[2]);
		float not_moving[3] = {0.0, 0.0, 0.0};
		TeleportEntity(self, marked_pos2, marked_angle2, not_moving);
		marked_pos2[0] = tmp_pos[0]; marked_pos2[1] = tmp_pos[1]; marked_pos2[2] = tmp_pos[2];
		marked_angle2[0] = tmp_ang[0]; marked_angle2[1] = tmp_ang[1]; marked_angle2[2] = tmp_ang[2];
		return;
	}
	#if 0
	if (!strcmp(msg, "!slow"))
	{
		SetEntPropFloat(self, Prop_Send, "m_flMaxspeed", 150.0);
		PrintToChat(self, "Now slow (150)");
	}
	if (!strcmp(msg, "!normal"))
	{
		SetEntPropFloat(self, Prop_Send, "m_flMaxspeed", BASE_SPEED);
		PrintToChat(self, "Now normal (%.0f)", BASE_SPEED);
	}
	if (!strcmp(msg, "!fast"))
	{
		SetEntPropFloat(self, Prop_Send, "m_flMaxspeed", 300.0);
		PrintToChat(self, "Now fast (300)");
	}
	#endif
	if (!strcmp(msg, "!showpos"))
	{
		for (int i = 0; i < nshowpos; ++i) if (show_positions[i] == self)
		{
			PrintToChat(self, "Already showing pos each frame.");
			return;
		}
		show_positions[nshowpos++] = self;
		last_money[self] = -1;
		#if defined(POS_ONLY_WHEN_MONEY)
		PrintToChat(self, "Will show pos each time money changes.");
		#else
		PrintToChat(self, "Will show pos each frame.");
		#endif
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
		//TODO maybe: If the wealthiest bot is carrying an SMG and can afford another,
		//drop and buy a UMP? Would allow !drop to work on SMG rounds. Might not be worth
		//it though.
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
		//TODO: Buy different weapons, esp now the AUG/SG are so cheap
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
		#if 0
		int drone = -1;
		while ((drone = FindEntityByClassname(drone, "drone")) != -1)
		{
			char carrying[64] = "";
			int load = GetEntPropEnt(drone, Prop_Send, "m_hDeliveryCargo");
			if (load != -1)
			{
				describe_weapon(load, carrying, sizeof(carrying));
				Format(carrying, sizeof(carrying), ", carrying %s", carrying);
			}
			else if ((load = GetEntPropEnt(drone, Prop_Send, "m_hPotentialCargo")) != -1)
			{
				describe_weapon(load, carrying, sizeof(carrying));
				Format(carrying, sizeof(carrying), ", could get %s", carrying);
			}
			char dest[64] = "";
			int target = GetEntPropEnt(drone, Prop_Send, "m_hMoveToThisEntity");
			if (target != -1)
			{
				int owner = GetEntPropEnt(target, Prop_Send, "m_hOwner");
				if (owner == -1) Format(dest, sizeof(dest), ", moving to unowned tablet %d", target);
				else if (owner <= MAXPLAYERS)
				{
					GetClientName(owner, dest, sizeof(dest));
					Format(dest, sizeof(dest), ", moving to %s", dest);
				}
				else Format(dest, sizeof(dest), ", moving to tablet %d owned by %d", target, owner); //Shouldn't happen? I think?
			}
			char piloted[64] = "unpiloted drone";
			int pilot = GetEntPropEnt(drone, Prop_Send, "m_hCurrentPilot");
			if (pilot == -1)
			{
				if (GetEntProp(drone, Prop_Send, "m_bPilotTakeoverAllowed"))
					piloted = "claimable drone";
			}
			else if (pilot <= MAXPLAYERS)
			{
				GetClientName(pilot, piloted, sizeof(piloted));
				Format(piloted, sizeof(piloted), "drone piloted by %s", piloted);
				dest = "";
			}
			else Format(piloted, sizeof(piloted), "drone piloted by %d", pilot);
			PrintToChat(self, "Found a %s%s%s", piloted, dest, carrying);
		}
		if (self) return;
		#endif

		int target = self; //Should players be able to request healing for each other? For now, no.
		if (!IsClientInGame(target) || !IsPlayerAlive(target)) return;
		if (GameRules_GetProp("m_iRoundWinStatus")) return; //Can't heal when the round is over.
		int price = GetConVarInt(sm_drzed_heal_price);
		if (!price) return; //Healing not available on this map/game mode/etc
		//In theory, free healing could be a thing (since "no healing available" is best signalled
		//by setting heal_max to zero). Would have to figure out an alternate cost (score? earned
		//every time you get N kills?), but it's not fundamentally illogical on non-money modes.
		//Or possibly it could all be done with sm_drzed_heal_cooldown; that would give everyone
		//one free heal, but then it's on a really long cooldown (maybe 5 minutes). That might
		//demand some sort of cooldown-is-ending report to prevent massive spam. (Can I create a
		//progress bar?)
		int max_healing = GetConVarInt(sm_drzed_heal_max);
		int max_health = GetConVarInt(sm_drzed_max_hitpoints); if (!max_health) max_health = default_health;
		if (max_healing < max_health) max_health = max_healing;
		if (GetEntProp(target, Prop_Send, "m_bHasHeavyArmor"))
			max_health += GetConVarInt(sm_drzed_suit_health_bonus);

		//When you're controlling a bot, most info is available under your
		//client (eg money, health), but for anything we track ourselves,
		//use the client index of the bot you're controlling instead.
		int real_client = target;
		if (GetEntProp(target, Prop_Send, "m_bIsControllingBot"))
			real_client = GetEntProp(target, Prop_Send, "m_iControlledBotEntIndex");
		//PrintToStream("Healing requested - max health %d+%d, current %d", max_health, healthbonus[real_client], GetClientHealth(target));
		max_health += healthbonus[real_client];
		if (max_health <= 0) return; //Healing not available on this map/game mode/etc
		int tick = GetGameTickCount();
		if (tick < heal_cooldown_tick[real_client])
		{
			//TODO: Show a twirling cooldown?
			PrintToChat(target, "Slow down, get out of danger, and I'll come help!");
			return;
		}
		int cd = RoundToFloor(GetConVarFloat(sm_drzed_heal_cooldown) / GetTickInterval());
		heal_cooldown_tick[real_client] = tick + cd;
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
		healthbonus[real_client] += increment; max_health += increment;
		//char playername[64]; GetClientName(target, playername, sizeof(playername));
		//PrintToStream("Healing %s up to %d (bonus %d)", playername, max_health, healthbonus[target]);
		SetEntProp(target, Prop_Send, "m_iAccount", money - price);
		SetEntityHealth(target, max_health);
		PrintToChat(target, "Now go kill some enemies for me!"); //TODO: Different messages T and CT? Diff again in Danger Zone?
	}
}

//Max health doesn't seem very significant in CS:GO, since there's basically nothing that heals you.
//(CJA 20181210: Well well well... now there is.)
//But we set the health on spawn too, so it ends up applying.
public void OnClientPutInServer(int client)
{
	healthbonus[client] = 0; anarchy[client] = 0; anarchy_available[client] = 0; puzzles_solved[client] = 0;
	phaseping_cookie[client] = 0; //Shouldn't be necessary but if something leaves it stuck, this can reset it
	SDKHookEx(client, SDKHook_GetMaxHealth, maxhealthcheck);
	SDKHookEx(client, SDKHook_SpawnPost, spawncheck);
	SDKHookEx(client, SDKHook_OnTakeDamageAlive, healthgate);
	SDKHookEx(client, SDKHook_WeaponCanSwitchTo, weaponlock);
	SDKHookEx(client, SDKHook_WeaponCanUse, weaponusecheck);
	SDKHookEx(client, SDKHook_WeaponSwitchPost, getweaponstats);
}
public Action maxhealthcheck(int entity, int &maxhealth)
{
	if (entity > MaxClients || !IsClientInGame(entity) || !IsPlayerAlive(entity)) return Plugin_Continue;
	int maxhp = GetConVarInt(sm_drzed_max_hitpoints);
	if (!maxhp) maxhp = maxhealth;
	maxhp += GetConVarInt(sm_drzed_crippled_health) + healthbonus[entity];
	//PrintToStream("Entity %d max health default %d now %d", entity, maxhealth, maxhp);
	if (maxhp != maxhealth) {maxhealth = maxhp; return Plugin_Changed;}
	return Plugin_Continue;
}

void spawncheck(int entity)
{
	//I do not understand why I can't just compare GetProp to the stored value.
	//It's probably something to do with the almost-but-not-quite-sane type
	//system ("tags") in SourcePawn.
	int now_warmup = 0;
	if (GameRules_GetProp("m_bWarmupPeriod")) now_warmup = 1;
	if (now_warmup != healthbonus_for_warmup)
	{
		//PrintToStream("warmup %d => %d, resetting", healthbonus_for_warmup, now_warmup);
		//Reset everything as we go into or out of warmup
		healthbonus_for_warmup = now_warmup; //This line appears to trample on one of the shims. HUH??
		reset_health_bonuses();
	}
	if (entity > MaxClients || !IsClientInGame(entity) || !IsPlayerAlive(entity)) return;

	puzzles_solved[entity] = 0;
	anarchy_available[entity] = 0;
	if (anarchy[entity])
	{
		int keep = anarchy[entity] * GetConVarInt(sm_drzed_anarchy_kept_on_death) / 100;
		if (keep < anarchy[entity]) //No, setting kept_on_death higher than 100 will NOT increase anarchy stacks LUL
		{
			if (!keep) PrintToChat(entity, "You died, and lost your %d Anarchy.", anarchy[entity] - keep);
			else PrintToChat(entity, "You died, and lost %d Anarchy (now %d).", anarchy[entity] - keep, keep);
			anarchy[entity] = keep;
		}
	}

	default_health = GetClientHealth(entity); //This happens only on spawn; we assume you're at full health right as you spawn.
	int health = GetConVarInt(sm_drzed_max_hitpoints);
	if (!health) health = default_health;
	health += GetConVarInt(sm_drzed_crippled_health);
	//char name[64]; GetClientName(entity, name, sizeof(name));
	//PrintToStream("Spawn %s (%d): %d + %d = %d hp (was %d)", name, entity, health, healthbonus[entity], health + healthbonus[entity], GetClientHealth(entity));
	SetEntityHealth(entity, health + healthbonus[entity]);

	//Bots in Danger Zone need weapons. At least, I think that's why they get stuck.
	//Part of the problem is that they need a better nav mesh, though.
	char weap[64]; GetConVarString(bots_get_empty_weapon, weap, sizeof(weap));
	if (IsFakeClient(entity) && strlen(weap))
	{
		int weapon = GivePlayerItem(entity, weap);
		SetEntProp(weapon, Prop_Send, "m_iClip1", 0);
		SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);
	}
}

void fade_screen(int target, int time)
{
	if (!IsClientInGame(target) || !IsPlayerAlive(target)) return;
	int duration = 256, holdtime = 512 * time; //16-bit fixed point, not sure how many bits are the fraction (guessing 9)
	int color[4] = { 32, 32, 32, 128 }; //RGBA
	int flags = 17; //s/be fade in and purge - or try 10 instead
	//See https://wiki.alliedmods.net/User_messages
	//Borrowed from funcommands::blind.sp
	//This code is governed by the terms of the GPL. (The rest of this file
	//is under even more free terms.)
	
	int targets[2]; targets[0] = target; targets[1] = 0;
	Handle message = StartMessageEx(GetUserMessageId("Fade"), targets, 1);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", duration);
		pb.SetInt("hold_time", holdtime);
		pb.SetInt("flags", flags);
		pb.SetColor("clr", color);
	}
	else
	{
		BfWrite bf = UserMessageToBfWrite(message);
		bf.WriteShort(duration);
		bf.WriteShort(holdtime);
		bf.WriteShort(flags);		
		bf.WriteByte(color[0]);
		bf.WriteByte(color[1]);
		bf.WriteByte(color[2]);
		bf.WriteByte(color[3]);
	}
	
	EndMessage();
	//End code governed by the GPL.
}

Action damage_lag_unimmunify(Handle timer, any victim)
{
	if (!IsClientInGame(victim)) return;
	SetEntProp(victim, Prop_Data, "m_takedamage", 2);
	SetEntityRenderColor(victim, 255, 255, 255, 255);
}
void damage_lag_immunify(int victim, float time)
{
	SetEntProp(victim, Prop_Data, "m_takedamage", 0);
	SetEntityRenderColor(victim, 32, 32, 32, 255); //Wile E Coyote, super genius.
	fade_screen(victim, RoundToFloor(time));
	CreateTimer(time, damage_lag_unimmunify, victim, TIMER_FLAG_NO_MAPCHANGE);
}
bool damage_lag_is_immune(int victim)
{
	return GetEntProp(victim, Prop_Data, "m_takedamage") == 0;
}

//For some reason, attacker is -1 at all times. Why? Did something change?
//Can I use inflictor instead?? It gets entity IDs for things like utility damage.
public Action healthgate(int victim, int &atk, int &inflictor, float &damage, int &damagetype,
	int &weapon, float damageForce[3], float damagePosition[3])
{
	int attacker = atk; //Disconnect from the mutable
	if (attacker == -1)
	{
		//Attempt to figure out the "real" attacker from the inflictor
		if (inflictor > 0 && inflictor < MAXPLAYERS) attacker = inflictor;
		else
		{
			//Can I be sure this won't bomb out?
			int owner = GetEntPropEnt(inflictor, Prop_Send, "m_hOwnerEntity");
			if (owner > 0 && owner < MAXPLAYERS) attacker = owner;
		}
		//else... I dunno who the attacker is. Leave it at -1 and don't do any player-based effects.
		//char cls[64]; GetEntityClassname(inflictor, cls, sizeof(cls));
		//PrintToChatAll("Attacker is now %d, inflictor is %d (%s), dmg %.2f type %x", attacker, inflictor, cls, damage, damagetype);
	}
	//If the attacking weapon is one you're currently wielding (ie not a grenade etc)
	//in one of your first two slots (no knife etc), flag the user (or maybe gun) as
	//being anarchy-ready. TODO: De-flag if the gun is changed?
	if (attacker >= 0 && attacker < MAXPLAYERS && weapon == GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon"))
	{
		if (weapon == GetPlayerWeaponSlot(attacker, 0)) anarchy_available[attacker] |= 1; //Primary weapon
		else if (weapon == GetPlayerWeaponSlot(attacker, 1)) anarchy_available[attacker] |= 2; //Secondary weapon
		if (damage >= GetClientHealth(victim) && GetConVarInt(sm_drzed_anarchy_per_kill))
		{
			anarchy[attacker]++;
			char player[64]; GetClientName(attacker, player, sizeof(player));
			PrintCenterText(attacker, "You now have %d anarchy!", anarchy[attacker]);
		}
	}
	int vicweap = GetEntPropEnt(victim, Prop_Send, "m_hActiveWeapon");
	char atkcls[64]; describe_weapon(weapon > 0 ? weapon : inflictor, atkcls, sizeof(atkcls));
	char viccls[64]; describe_weapon(vicweap, viccls, sizeof(viccls));
	int teamdmg = 0;
	if (attacker >= 0 && attacker < MAXPLAYERS)
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
	/*
	//Log all damage to a file that gets processed by a Python script
	int cap = GetClientHealth(victim);
	int score = RoundToFloor(damage);
	if (score >= cap) score = cap + 100; //100 bonus points for the kill, but the actual damage caps out at the health taken.
	File fp = OpenFile("weapon_scores.log", "a");
	WriteFileLine(fp, "%s %sdamaged %s for %d (%.0fhp)",
		atkcls, victim == attacker ? "self" : teamdmg ? "team" : "",
		viccls, score, damage);
	CloseHandle(fp);
	*/

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

	int tick = GetGameTickCount();
	int cd = RoundToFloor(GetConVarFloat(sm_drzed_heal_damage_cd) / GetTickInterval());
	if (heal_cooldown_tick[victim] < tick + cd) heal_cooldown_tick[victim] = tick + cd;

	//Scale damage according to who's dealing with it (non-hackily)
	Action ret = Plugin_Continue;
	if (attacker >= 0 && attacker < MAXPLAYERS)
	{
		float proportion;
		if (IsFakeClient(attacker)) proportion = GetConVarFloat(damage_scale_bots);
		else proportion = GetConVarFloat(damage_scale_humans);
		//PrintToServer("Damage proportion: %.2f", proportion);
		if (proportion != 1.0) {ret = Plugin_Changed; damage *= proportion;}
		if ((underdome_flg & UF_MORE_RANGE_PENALTY) && weapon > 0)
		{
			float atkpos[3]; GetClientAbsOrigin(attacker, atkpos);
			float dist = GetVectorDistance(atkpos, damagePosition, false);
			//Normally damage is scaled by rangefactor**(dist/500)
			//This means that point blank shots deal 100% damage, and it falls off quadratically.
			//We're going to change that so that at 500 HU you deal 100% damage, and it ramps UP
			//if you're closer. Also, ramp up and down are way way faster.
			float rangemod = 1.0; //For anything that isn't a weapon, don't rescale.
			int idx;
			char cls[64]; GetEntityClassname(weapon, cls, sizeof(cls));
			if (GetTrieValue(weapondata_index, cls, idx)) rangemod = weapondata_range_modifier[idx];
			if (rangemod < 1.0)
			{
				//float orig = damage;
				damage /= Pow(rangemod, dist / 500.0); //Undo the range modification already done
				//float base = damage;
				if (dist > 500.0 && rangemod < 0.80) rangemod = 0.80; //Mandate a minimum of 20% damage falloff
				damage *= Pow(rangemod, (dist - 500.0) / 100.0); //Apply our new range modifier.
				//PrintToChatAll("Range %.2f; would have dealt %.2f from base %.2f, now %.2f", dist, orig, base, damage);
				ret = Plugin_Changed;
			}
		}
	}

	//If you just phasewalked, you're immune to damage but also can't shoot.
	if (phaseping_cookie[victim] < 0) {damage = 0.0; ret = Plugin_Changed;}
	if (attacker >= 0 && attacker < MAXPLAYERS && phaseping_cookie[attacker] < 0)
	{
		//Damage from other entities (mainly grenades) is permitted. Knife attacks are permitted.
		if (attacker == inflictor && strcmp(atkcls, "Knife")) damage = 0.0;
		else damage *= 2.0; //TODO: Figure out a proper damage bonus factor. Maybe 1.5?
		ret = Plugin_Changed;
	}

	//Increase the damage done by igniting someone
	if ((damagetype & 8) && attacker >= 0 && attacker < MAXPLAYERS && damage <= 2.0)
	{
		char cls[64]; GetEntityClassname(inflictor, cls, sizeof(cls));
		if (!strcmp(cls, "entityflame")) {damage *= 2.5; atk = attacker; ret = Plugin_Changed;}
	}

	int hack = GetConVarInt(sm_drzed_hack);
	if (hack && attacker >= 0 && attacker < MAXPLAYERS)
	{
		//Mess with damage based on who's dealing it. This is a total hack, and
		//can change at any time while I play around with testing stuff.
		if (hack == 4 || hack == 5)
		{
			//Don't deal any damage, just log how much WOULD have been dealt
			PrintToChat(attacker, "That would have dealt %.0f damage.", damage);
			damage = 0.0;
			return Plugin_Changed;
		}
		if (hack == 3)
		{
			//Damage only while flashed
			float flashtm = GetEntPropFloat(attacker, Prop_Send, "m_flFlashDuration");
			if (flashtm == 0.0)
			{
				//You're not flashed, so you deal fractional damage.
				damage /= 10.0;
				return Plugin_Changed;
			}
			return ret;
		}
		if (hack == 2 && IsFakeClient(attacker)) return ret; //Example: Bots are unaffected
		if (hack == 1)
		{
			//Example: Scale the damage according to how hurt you are
			//Like the TF2 Equalizer, but done as a simple scaling of all damage.
			int health = GetClientHealth(attacker) * 2;
			int max = GetConVarInt(sm_drzed_max_hitpoints); if (!max) max = default_health;
			float factor = 2.0; //At max health, divide by this; at zero health, multiply by this.
			if (health > max) damage /= factor * (health - max) / max;
			else if (health < max) damage *= factor * health / max;
			return Plugin_Changed;
		}
	}

	if (!strcmp(atkcls, "C4") && GetClientTeam(victim) == 3)
	{
		//If the bomb kills a CT, credit the kill to the bomb planter.
		//(Don't penalize for team kills or suicide though.)
		if (bomb_planter > 0 && IsClientInGame(bomb_planter)) atk = bomb_planter;
		return Plugin_Changed;
	}

	if (attacker >= 0 && attacker < MAXPLAYERS)
	{
		int anarchy_bonus = GetConVarInt(sm_drzed_anarchy_bonus) * anarchy[attacker];
		float newdmg = damage * (100 + anarchy_bonus) / 100.0;
		if (newdmg >= damage + 1.0) //Unless you gain at least 1 whole point of damage, don't log anything.
		{
			//PrintToStream("Damage increased from %.0f to %.0f", damage, newdmg);
			damage = newdmg;
			return Plugin_Changed;
		}
	}

	//
	if (cripplepoint)
	{
		//Note that crippling, as a feature, is disabled once the
		//round is over. Insta-kill for exit frags.
		int oldhealth = GetClientHealth(victim);
		int newhealth = oldhealth - RoundToFloor(damage);
		if (oldhealth > cripplepoint && newhealth <= cripplepoint)
		{
			if (GameRules_GetProp("m_iRoundWinStatus") || GameRules_GetProp("m_bWarmupPeriod"))
			{
				//During warmup and end-of-round, crippled people just instadie
				SetEntityHealth(victim, GetClientHealth(victim) - cripplepoint);
				return ret; //and then the normal damage goes through
			}
			last_attacker[victim] = attacker; last_inflictor[victim] = inflictor; last_weapon[victim] = weapon;
			cripple(victim);
			return Plugin_Stop; //Returning Plugin_Stop doesn't seem to stop the damage event in all cases. Not sure why.
		}
	}
	//
	int full = GetConVarInt(sm_drzed_max_hitpoints); if (!full) full = default_health;
	full += GetConVarInt(sm_drzed_crippled_health);
	int health = GetClientHealth(victim);
	int dmg = RoundToFloor(damage);
	//
	int respawn_lag = GetConVarInt(insta_respawn_damage_lag);
	if (respawn_lag && dmg >= health)
	{
		//This is a form of instant respawn. You stay in the same place, you keep
		//all your gear, and you just reset and try again.
		char name[64]; GetClientName(victim, name, sizeof(name));
		PrintToChatAll("%s would have died (%d dmg on %d hp).", name, dmg, health);
		SetEntityHealth(victim, full);
		//Give back armor if you still have any. Assumes 100 max armor.
		if (GetEntProp(victim, Prop_Send, "m_ArmorValue") > 0)
			SetEntProp(victim, Prop_Send, "m_ArmorValue", 100);
		damage_lag_immunify(victim, respawn_lag + 0.01);
		//Update the scoreboard. TODO: Register assists. That might require
		//manually tracking all damage, which would be stupid, since the game
		//already tracks it. But I can't find that info anywhere.
		//TODO: Figure out when and why these stats get reset.
		if (attacker >= 0 && attacker < MAXPLAYERS)
			SetEntProp(attacker, Prop_Data, "m_iFrags", GetClientFrags(attacker) + 1);
		SetEntProp(victim, Prop_Data, "m_iDeaths", GetClientDeaths(victim) + 1);
		damage = 0.0;
		return Plugin_Changed;
	}
	//
	int gate = GetConVarInt(sm_drzed_gate_health_left);
	if (!gate) return ret; //Health gate not active
	if (health < full) return ret; //Below the health gate
	if (dmg < health) return ret; //Wouldn't kill you
	char cls[64]; describe_weapon(weapon, cls, sizeof(cls));
	if (!strcmp(cls, "Knife")) return ret; //No health-gating knife backstabs
	char name[64]; GetClientName(attacker, name, sizeof(name));
	int overkill = GetConVarInt(sm_drzed_gate_overkill);
	if (dmg >= overkill)
	{
		PrintToChat(victim, "BEWM! %s overkilled you with his %s (%d damage).", name, cls, dmg);
		return ret;
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
Action weaponusecheck(int client, int weapon)
{
	ignore(weapon);
	//When we're doing puzzle games, you don't use weapons normally.
	if (num_puzzles) return Plugin_Stop;
	return Plugin_Continue;
}
void getweaponstats(int client, int weap)
{
	if (GetConVarInt(learn_stutterstep))
	{
		show_stutterstep_stats(client);
		current_weapon_speed[client] = 250.0;
		if (weap > 0)
		{
			//Try to figure out the weapon's maximum speed
			//Since this is (ultimately) a lookup into items_game.txt, its validity depends on
			//keeping the data tables up to date. Also, this doesn't have entries for non-weapons,
			//so (for instance) grenades show up at the default of 250, even though their actual
			//max speed is 245. It also doesn't take scoping into account, which drops max speed
			//to 150, 120, or 100, depending on the weapon. None of this impacts the primary goal
			//of this code, which is to learn stutter stepping; just be aware if you copy/paste it.
			char cls[64]; GetEntityClassname(weap, cls, sizeof(cls));
			int idx;
			if (GetTrieValue(weapondata_index, cls, idx)) current_weapon_speed[client] = weapondata_max_player_speed[idx];
			describe_weapon(weap, cls, sizeof(cls));
			PrintToChat(client, "With %s, max %.0f, 34%% %.0f", cls,
				current_weapon_speed[client], current_weapon_speed[client] * 0.34);
		}
	}
}
/*
Revival of Teammates mode:
* Everyone starts with 200 hp.
* If you have > 100 hp, any damage that would reduce you below 100 sets you to 100.
* While you have <= 100 hp, you are crippled, and lose 1hp every 0.1 seconds.
* Teammates can heal crippled players by knifing them. Once > 100 hp, no longer crippled.
* A crippled player is unable to fire any weapons, and is reduced to crawling speed.

TODO: Is it okay for a crippled person to revive another crippled person?

TODO: When you pick up a bot, you get set to primary weapon for some reason.
Why? Weird. May be able to use bot_takeover event to detect, and then force to
knife again. Or just disallow taking over a crippled bot.

TODO: Make sure you can't !heal while crippled

TODO: Use Plugin_Handled rather than Plugin_Stop to disable damage??

m_iBlockingUseActionInProgress -- can that be used to manage crippledness??
*/


/*
Gaige-inspired deathmatch
* sv_infinite_ammo 2 (so you don't run out awkwardly)
* If you reload your weapon that isn't completely empty, you lose all Anarchy
* Dealing damage to an enemy with a gun flags that gun as bonus-worthy
* Reloading a bonus-worthy empty gun adds one Anarchy
* Each Anarchy you have grants an additive percentage bonus to your damage

Differences from the BL2 inspiration:
* Killing an enemy doesn't give you the bonus. This is subject to review, but I worry that it'd create a "win-more" situation.
* Engaging in battle, then backing off, and emptying your gun into the air DOES get you the bonus.
* Emptying your gun into static targets does NOT get you the bonus.
* Dying doesn't lose ALL your Anarchy. Controlled by cvar.

A bonus-worthy gun remains so only while it's equipped. So if you draw blood, then toss that gun down and get
another, it's been reset. So effectively, it can be seen as two flags on the player (primary and secondary),
which get cleared if you change what's in that slot. (Selecting a different weapon changes nothing; if you
draw blood with an AWP, then switch to your pistol, empty the clip at nothing, then switch back, and empty
the AWP, you get the bonus for the AWP but not the pistol.)
*/

/*
Will bots ever upgrade weapons?
- Basically no. They won't see weapon upgrades as goals.
- If he would roll over a weapon, he'll get it. That's about it.

Danger Zone AI proposal:
- Stateless
- Potential goal: if weapon nearby better than currently-equipped, fetch it
- Potential goal: if identical weapon nearby, extract ammo
- Potential goal: if openable case nearby, open it (lower prio than killing enemies, but otherwise just do it)
- Potential goal: if ammo box nearby, approach it
- Required handling: if ammo box in reach, select whichever weapon has fewer spare mags and fill it
  - If equal mag count (esp zero), split it two and two btwn primary and secondary
- Required nav: Perform standard tour of any lootable region (eg "Alpha and surrounds" could be one region)
- Optional nav: After performing one standard tour, find another
- Never buy weapons from the tablet (for simplicity)
- Optional: Maybe buy ammo from tablet, but only on higher difficulties
- If not at all under threat or near enemy, check tablet for nearest cell with enemy and go hunting
  - Otherwise ignore the tablet and just explore with eyeballs
*/

/* Player attributes to inspect:
m_fOnTarget
m_iAmmo[32] - what do they all mean?
14-18 are grenades - HE/frag, flash, smoke, molly/inc, decoy/diversion
21: Health Shot
22: Tactical Awareness
24: Snowball
Bump mines, exojump, and parachute do not show up.

Also, a "drone" (CDrone, DT_Drone) gained a few attributes as of Sirocco:
+ Member: m_bPilotTakeoverAllowed (offset 1896) (type integer) (bits 1) (Unsigned)
+ Member: m_hPotentialCargo (offset 1900) (type integer) (bits 21) (Unsigned|NoScale)
+ Member: m_hCurrentPilot (offset 1904) (type integer) (bits 21) (Unsigned|NoScale)
+ Member: m_vecTagPositions (offset 1908) (type vector) (bits 0) (NoScale|InsideArray)
+ Member: m_vecTagPositions (offset 0) (type array) (bits 0) ()
+ Member: m_vecTagIncrements (offset 2196) (type integer) (bits 32) (NoScale|InsideArray)
+ Member: m_vecTagIncrements (offset 0) (type array) (bits 0) ()

The takeover bit seems to be zero before the drone has made a delivery and one after. Not
sure what that actually means, since the preview on the web site shows the drone carrying
something. OTOH, maybe that's just an easy way to recognize whether it's incoming or outgoing.
- 20190708: Of course, we now understand exactly what's going on here: you cannot take control
- of a drone that's doing a delivery. The aforementioned preview requires that you grab an
- empty drone, then pick something up. Turns out, the prerelease info was pretty accurate.

At the same time, players lost m_bHasParachute and instead gained a four-element m_passiveItems
They correspond to Parachute, Exojump, Bonus Explore Money, Bonus Wave Money

Is tablet_dronepilot visible anywhere? Can't find it. But then, I also can't find any
evidence of the other tablet upgrades (drones, zone predic, high res), and they clearly
DO function correctly, and are associated with the tablet somehow.

Note that m_hPotentialCargo isn't always the thing you'd grab if you click. It will show a
highlight marker for an object that's *forward* of where you are - ie it's the thing you're
looking at. If there's no such thing, it will usually show what you'd be capable of grabbing,
but this isn't guaranteed (it's possible for hPotentialCargo to be -1 but clicking still does
get something). Of course, m_hDeliveryCargo always accurately records carried items.
*/

/*
TODO: Allow multijump. Each player has a jump counter that is reset whenever on ground, including jumping when on ground. Attempting to jump
while in mid-air (defined as transitioning from "not jumping" to "jumping" while not on the ground) will increment this counter. A cvar caps
the counter; possibly have a separate cap for if you have an exojump equipped. When multijumping, create a "psssshhht" sound as per exojump.

Hmm. Would be incompatible with a parachute, but that's probably not a critical problem. Or maybe this can take over the parachute's hook
somehow? Call it an "Aperture Science Active Parachute" or something?
*/

/*
Phylactery mode - Danger Zone
* For every new human, add a bot (can I do that? test)
* Team them up
* Have to kill human and phylactery at once
*/

/*
Scavenger hunt.

The bomb has been planted, there are no terrorists, but it's not a standard bomb. Your bomb defusal kit isn't enough.
Search the map (as a team) for clues to the bomb's defusal code. Enter the code (via chat) to defuse the bomb. Pressing
E on the bomb will show some information, but then someone needs to locate an item somewhere on the map to help you
understand the next part of the code!

* Set bomb timer to something long, or use the round timer and trigger a bomb detonation when it expires.
* Attempting to defuse the bomb creates a chat message to the defuser only. Until the code is entered, the exact same
  message will be produced for every attempt.
  - "The code is the magazine size of my SMG", so you have to find a SMG somewhere on the map and call its clip size
  - Or for the demo...
    - "How many total Shotguns do I have here?" -- just count 'em (7)
    - "Find my largest magazine fully Automatic gun. How many shots till I reload?" -- it's a Galil (35)
    - "How many distinct Pistols do I have here?" -- count unique items (5)
    - "This is my SMG. There are none quite like it. How well does it penetrate armor?" -- it's an MP9 (60)
    - "This is my Shotgun. There are none quite like it. How many shots till I reload?" -- it's a Nova (8)
  - Prevent items from being picked up. People don't need any items (not even knives).
* Spawn the corresponding item at a random location.
  - Can I use the deathmatch spawns?
  - The info_deathmatch_spawn entities don't exist when not in deathmatch - cvar controlled?
* Difficulty can be increased by having more actions to be done.
* Teamwork will be essential. You can't run all over the map solo in time. Someone should defuse, the rest explore.
* Yes, of course it's KTANE inspired, got a problem with that? :)
* If a "three strikes and you're out" mode is offered, then rather than changing the bomb timer, just
  start dropping smokes randomly. After one strike, there'll be a random smoke every 10 seconds; after
  two, three random smokes every 8 seconds. Use the same deathmatch spawn points that are used for the
  clues, so there's a high chance that a clue will be smoked over.
  - Start by AddTempEntHook("EffectDispatch", show_lots_of_info)
  - Then TE_Start("EffectDispatch") and do the work to create a new one.
* Possibly grant people weapon_fists rather than knives?
* Can TA grenades be granted (awarded maybe?) and made able to reveal nearby weapons?
*/

/*
Messing with people
- Flag the person as floating. Constantly keep the person out of the FL_ONGROUND state,
  which will (I think) keep their accuracy in "jump" state. May end up not triggering
  until their first jump though.
- Where are the attributes that carry recoil and its corresponding recovery?
  - m_flRecoilIndex, m_fAccuracyPenalty, maybe m_fLastShotTime?
  - These are on the weapon, not the player, so there'd need to be a check on weapon switch.
- float pos[3]; GetClientAbsOrigin(client, pos); blow_smoke(client, pos);
*/

/*
Research the TA Grenade with a view to using it in an alternate mode
Can I get triggers from it and use it to highlight things in puzzle mode???
The "buy tagrenade" command doesn't work, so there'll need to be some other way
to distribute them. Possibly GivePlayerItem as soon as you spawn?
Is there a way to switch to it?
*/

/* Explore:
m_iBlockingUseActionInProgress

Does that mean "there's a blocking action in progress, disallow movement"? Could be useful.
Or does it mean "block the Use action"?

cl_showevents 1
-- show some event dumps. Could reveal handy info.
*/

/*
Territory control team deathmatch.

Claimable territory is defined by deathmatch spawn points.
If you can see a spawn location, you increase your team's control of it.
Control fades over time, and builds fairly quickly but not instantly.
Non-spectators can only see their own team's control, as a heat map. Interpret lack of control as
enemy. You can't see if something's contested.
Team scores increase according to the number of points that they have better than 66% control of.
*/


/*
TODO: CS:GO Guardian with every wave having a different attribute, from Moxxi's Underdome
* Can we get an event on wave end? Worst case, try to use death status and see if any fake clients are alive
* Change the mp_guardian_special_weapon_needed cvar on the fly
* Would be awesome to actually lift Moxxi's voice lines, but that's beyond me
* Disable bomb planting. Yes, this theoretically means players can cheese it by hiding until the bots suicide. Just don't do that.
* Maybe provide an armory as well. Provide a small number of cheap weapons eg USP-S and MP5. These would be available for people who don't have them equipped.
  - Possibly have 4-5 locations, and randomly select 1-2 of them to have the weapons spawn.
* First round is a warmup - any weapon, any kill, bots maybe only get pistols. Then pick one from this list, and after X rounds, pick two:
  - Headshot kills only. If the death blow wasn't a HS, it doesn't tick up the counter.
  - No headshots. If you shoot someone in the head, it does same as a chest shot.
  - Shotguns only; SMGs only; Snipers and LMGs only. Counter only increments if the right weapon class used.
    - Other weapons DO still deal damage. It just won't count to the goal unless the killing blow is correct.
  - Pocket AWP. Your sidearm deals double damage.
  - Low gravity??
  - Low accuracy??
  - Enemies get 150 HP (or in a later round, 200 HP)
  - Players have no armor ("naked")
  - Enemies and players all move faster??
  - Enemies and players all move slower??
  - Horde wave! Spawn 2-3 times as many bots but they only have knives.
  - Vampiric weapons
  - Suppressed weapons
* Can we permit bomb plants and defuses? If the bots plant, then the objective is disabled until it's defused (upon which the bots spawn a new bomb).
  - Spawn infinite enemies while the bomb is lit. Defuse under pressure!


act_kill_human
act_kill_chicken
act_win_match
act_flashbang_enemy
act_pick_up_hostage
act_rescue_hostage
act_defuse_bomb
act_plant_bomb
act_damage
act_win_round
act_dm_bonus_points
act_income
act_cash
act_spend
cond_damage_headshot
cond_damage_burn
cond_match_unique_weapon
cond_roundstate_pistolround
cond_roundstate_finalround
cond_roundstate_matchpoint
cond_roundstate_bomb_planted
cond_item_own
cond_item_borrowed
cond_item_borrowed_enemy
cond_item_borrowed_teammate
cond_item_borrowed_victim
cond_item_nondefault
cond_bullet_since_spawn
cond_player_rescuing
cond_player_zoomed
cond_player_blind
cond_player_terrorist
cond_player_ct
cond_life_killstreak_human
cond_life_killstreak_chicken
cond_match_rounds_won
cond_match_rounds_played
cond_victim_blind
cond_victim_zoomed
cond_victim_rescuing
cond_victim_terrorist
cond_victim_ct
cond_victim_reloading
*/
