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
ConVar bot_autobuy_nades = null; //(1) Bots will buy more grenades than they otherwise might
ConVar bots_get_empty_weapon = null; //("") Give bots an ammo-less weapon on startup (eg weapon_glock). Use only if they wouldn't get a weapon in that slot.
ConVar bot_purchase_delay = null; //(0.0) Delay bot primary weapon purchases by this many seconds
ConVar damage_scale_humans = null; //(1.0) Scale all damage dealt by humans
ConVar damage_scale_bots = null; //(1.0) Scale all damage dealt by bots
ConVar learn_smoke = null; //(0) Set things up to learn a particular smoke (1 = Dust II Xbox)
ConVar bomb_defusal_puzzles = null; //(0) Issue this many puzzles before allowing the bomb to be defused (can't be changed during a round)
ConVar insta_respawn_damage_lag = null; //(0) Instantly respawn on death, with this many seconds of damage immunity and inability to fire
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
ConVar default_weapons[4];
ConVar ammo_grenade_limit_total;
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
	HookEvent("player_say", Event_PlayerChat);
	HookEvent("weapon_fire", Event_weapon_fire);
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
	//HookEvent("player_hurt", player_hurt);
	//HookEvent("cs_intermission", reset_stats); //Seems to fire at the end of a match??
	//HookEvent("announce_phase_end", reset_stats); //Seems to fire at halftime team swap
	//player_falldamage: report whenever anyone falls, esp for a lot of dmg
	AddCommandListener(player_pinged, "player_ping");
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

public void SmokeLog(const char[] fmt, any ...)
{
	char buffer[4096];
	VFormat(buffer, sizeof(buffer), fmt, 2);
	File fp = OpenFile("learn_smoke.log", "a");
	WriteFileLine(fp, buffer);
	CloseHandle(fp);
}

//Would it be better to have six float cvars to define the box??
float smoke_targets[1][2][3] = { //Unfortunately the size has to be specified :(
	//1: Dust II Xbox
	{{-400.0, 1350.0, -27.0}, {-257.0, 1475.0, -24.0}},
	//Add others as needed - {{x1,y1,z1},{x2,y2,z2}} where the
	//second coords are all greater than the firsts.
};
float smoke_first_bounce[1][2][3] = {
	//1: Dust II Xbox
	//NOTE: If the bounce is extremely close to the wall (-265 to -257), the
	//smoke will bounce off the wall and miss. The actual boundary is somewhere
	//between -260 and -265.
	{{-321.0, 1130.0, -120.0}, {-265.0, 1275.0, -80.0}},
	//As above.
};

public void smoke_popped(Event event, const char[] name, bool dontBroadcast)
{
	int learn = GetConVarInt(learn_smoke);
	if (!learn) return;
	float x = event.GetFloat("x"), y = event.GetFloat("y"), z = event.GetFloat("z");
	int client = GetClientOfUserId(event.GetInt("userid"));
	bool on_target = false;
	if (learn <= sizeof(smoke_targets))
	{
		//Is there an easier way to ask if a point is inside a cube?
		if (smoke_targets[learn - 1][0][0] < x && x < smoke_targets[learn - 1][1][0] &&
			smoke_targets[learn - 1][0][1] < y && y < smoke_targets[learn - 1][1][1] &&
			smoke_targets[learn - 1][0][2] < z && z < smoke_targets[learn - 1][1][2])
				on_target = true;
	}
	PrintToChat(client, "%sYour smoke popped at (%.2f, %.2f, %.2f)",
		on_target ? "Nailed it! " : "",
		x, y, z);
	SmokeLog("[%d-E-%d] Pop (%.2f, %.2f, %.2f) - %s", client,
		event.GetInt("entityid"),
		x, y, z, on_target ? "GOOD" : "FAIL");
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
	int learn = GetConVarInt(learn_smoke);
	if (!learn) return;
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
				if (smoke_first_bounce[learn - 1][0][0] < x && x < smoke_first_bounce[learn - 1][1][0] &&
					smoke_first_bounce[learn - 1][0][1] < y && y < smoke_first_bounce[learn - 1][1][1] &&
					smoke_first_bounce[learn - 1][0][2] < z && z < smoke_first_bounce[learn - 1][1][2])
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

bool report_new_entities = false;
public void OnEntityCreated(int entity, const char[] cls)
{
	if (GetConVarInt(learn_smoke) && !strcmp(cls, "smokegrenade_projectile"))
	{
		//It's a newly-thrown smoke grenade. Mark it so we'll report its
		//first bounce (if we're reporting grenade bounces).
		smoke_not_bounced[entity] = true;
		CreateTimer(0.01, report_entity, entity, TIMER_FLAG_NO_MAPCHANGE);
	}
	//if (!strcmp(cls, "info_player_ping")) CreateTimer(0.01, report_entity, entity, TIMER_FLAG_NO_MAPCHANGE);
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
	int learn = GetConVarInt(learn_smoke);
	if (!learn) return;
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

//If you throw a grenade and it's the only thing you have, unselect.
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
		int total_nades = have_he + have_flash + have_smoke + have_molly + have_decoy;
		int max_nades = GetConVarInt(ammo_grenade_limit_total);
		//TODO: Respect per-type maximums that might be higher than 1
		int molly_price = team == 2 ? 400 : 600; //Incendiary grenades are overpriced for CTs
		money -= 1000; //Ensure that the bots don't spend below $1000 this way (just in case).
		int bought = 0;
		int which = -1;
		char nade_desc[][] = {"HE", "Flash", "Smoke", "Molly"};
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

#include "cs_weapons.inc"
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
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3],
	int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	//IN_ALT1 comes from the commands "+alt1" in client, and appears to have no effect
	//IN_ZOOM appears to have the same effect as ATTACK2 on weapons with scopes, and also
	//on the knife. Yes, "+zoom" will backstab with a knife. But it won't light a molly.
	//IN_LEFT/IN_RIGHT rotate you, like a 90s video game. Still active but nobody uses.
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
		&& GetEntProp(client, Prop_Send, "m_bGunGameImmunity")
		&& GetEntPropFloat(client, Prop_Send, "m_fImmuneToGunGameDamageTime") > GetGameTime())
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

bool filter_notself(int entity, int flags, int self) {PrintToServer("filter: %d/%d/%d", entity, flags, self); return entity != self;}
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
		//For first try, just place a money there. For the real thing, create a
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
		PrintToChat(self, "Marked position: %f, %f, %f", marked_pos[0], marked_pos[1], marked_pos[2]);
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
	SDKHookEx(client, SDKHook_GetMaxHealth, maxhealthcheck);
	SDKHookEx(client, SDKHook_SpawnPost, spawncheck);
	SDKHookEx(client, SDKHook_OnTakeDamageAlive, healthgate);
	SDKHookEx(client, SDKHook_WeaponCanSwitchTo, weaponlock);
	SDKHookEx(client, SDKHook_WeaponCanUse, weaponusecheck);
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

public Action healthgate(int victim, int &attacker, int &inflictor, float &damage, int &damagetype,
	int &weapon, float damageForce[3], float damagePosition[3])
{
	//If the attacking weapon is one you're currently wielding (ie not a grenade etc)
	//in one of your first two slots (no knife etc), flag the user (or maybe gun) as
	//being anarchy-ready. TODO: De-flag if the gun is changed?
	if (attacker && attacker < MAXPLAYERS && weapon == GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon"))
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

	int tick = GetGameTickCount();
	int cd = RoundToFloor(GetConVarFloat(sm_drzed_heal_damage_cd) / GetTickInterval());
	if (heal_cooldown_tick[victim] < tick + cd) heal_cooldown_tick[victim] = tick + cd;

	//Scale damage according to who's dealing with it (non-hackily)
	Action ret = Plugin_Continue;
	if (attacker && attacker < MAXPLAYERS)
	{
		float proportion;
		if (IsFakeClient(attacker)) proportion = GetConVarFloat(damage_scale_bots);
		else proportion = GetConVarFloat(damage_scale_humans);
		if (proportion != 1.0) {ret = Plugin_Changed; damage *= proportion;}
	}

	int hack = GetConVarInt(sm_drzed_hack);
	if (hack && attacker && attacker < MAXPLAYERS)
	{
		//Mess with damage based on who's dealing it. This is a total hack, and
		//can change at any time while I play around with testing stuff.
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
		if (IsFakeClient(attacker)) return ret; //Example: Bots are unaffected
		//Example: Scale the damage according to how hurt you are
		//Like the TF2 Equalizer, but done as a simple scaling of all damage.
		int health = GetClientHealth(attacker) * 2;
		int max = GetConVarInt(sm_drzed_max_hitpoints); if (!max) max = default_health;
		float factor = 2.0; //At max health, divide by this; at zero health, multiply by this.
		if (health > max) damage /= factor * (health - max) / max;
		else if (health < max) damage *= factor * health / max;
		return Plugin_Changed;
	}

	if (!strcmp(atkcls, "C4") && GetClientTeam(victim) == 3)
	{
		//If the bomb kills a CT, credit the kill to the bomb planter.
		//(Don't penalize for team kills or suicide though.)
		if (bomb_planter > 0 && IsClientInGame(bomb_planter)) attacker = bomb_planter;
		return Plugin_Changed;
	}

	if (attacker && attacker < MAXPLAYERS)
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
		//NOTE: For some bizarre reason, immunity time is capped at one second
		//during warmup. I have been unable to find a reason for this, nor any
		//way to control it. Weird weird.
		SetEntProp(victim, Prop_Send, "m_bGunGameImmunity", 1);
		SetEntPropFloat(victim, Prop_Send, "m_fImmuneToGunGameDamageTime", GetGameTime() + respawn_lag);
		//Update the scoreboard. TODO: Register assists. That might require
		//manually tracking all damage, which would be stupid, since the game
		//already tracks it. But I can't find that info anywhere.
		//TODO: Figure out when and why these stats get reset.
		if (attacker && attacker < MAXPLAYERS)
			SetEntProp(attacker, Prop_Data, "m_iFrags", GetClientFrags(attacker) + 1);
		SetEntProp(victim, Prop_Data, "m_iDeaths", GetClientDeaths(victim) + 1);
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
