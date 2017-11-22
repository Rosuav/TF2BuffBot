#include <sourcemod>
#include <tf2_stocks>

#pragma newdecls required
#pragma semicolon 1

//By default, calling Debug() does nothing.
public void Debug(const char[] fmt, any ...) { }
//For a full log of carnage score changes, enable this:
//#define Debug PrintToServer

#include "randeffects"

public Plugin myinfo =
{
	name = "Carnage Collection and Compensation",
	author = "Chris Angelico",
	description = "SourceMod extension to encourage carnage by rewarding those who engage in it",
	version = "0.99",
	url = "https://github.com/Rosuav/TF2BuffBot",
};

//Before you can use !roulette or !gift, you must fill your (invisible) carnage counter.
ConVar sm_buffbot_carnage_initial = null; //(0) Carnage points a player has on first joining or changing team
ConVar sm_buffbot_carnage_per_solo_kill = null; //(2) Carnage points gained for each unassisted kill
ConVar sm_buffbot_carnage_per_kill = null; //(2) Carnage points gained for each kill
ConVar sm_buffbot_carnage_per_assist = null; //(1) Carnage points gained for each assist
ConVar sm_buffbot_carnage_per_death = null; //(3) Carnage points gained when you die
ConVar sm_buffbot_carnage_per_building = null; //(1) Carnage points gained when you destroy a non-gun building (assists ignored here)
ConVar sm_buffbot_carnage_per_sentry = null; //(2) Carnage points gained when you destroy a sentry gun
ConVar sm_buffbot_carnage_per_ubercharge = null; //(0) Carnage points gained by a medic who deploys Uber
ConVar sm_buffbot_carnage_per_upgrade = null; //(0) Carnage points gained by an engineer who upgrades a building
//No carnage points are granted for achieving map goals (capturing the flag, taking a control point, moving the
//payload, etc). Such actions may help you win, but they don't create death and destruction.
ConVar sm_buffbot_carnage_required = null; //(10) Carnage points required to use !roulette or !gift
ConVar sm_buffbot_buff_duration = null; //(30) Length of time that each buff/debuff lasts
//When you spin the !roulette wheel, you have these odds of getting different buff categories.
//There will always be exactly one chance that you will die, so scale these numbers accordingly.
ConVar sm_buffbot_roulette_chance_good = null; //(64) Chance that a roulette spin will give a beneficial effect
ConVar sm_buffbot_roulette_chance_bad = null; //(30) Chance that a roulette spin will give a detrimental effect
ConVar sm_buffbot_roulette_chance_weird = null; //(5) Chance that a roulette spin will give a weird effect
//When you grant a !gift, players (other than yourself) will have this many chances each.
ConVar sm_buffbot_gift_chance_friendly_human = null; //(20) Chance that each friendly human has of receiving a !gift
ConVar sm_buffbot_gift_chance_friendly_bot = null; //(2) Chance that each friendly bot has of receiving a !gift
ConVar sm_buffbot_gift_chance_enemy_human = null; //(10) Chance that each enemy human has of receiving a !gift
ConVar sm_buffbot_gift_chance_enemy_bot = null; //(1) Chance that each enemy bot has of receiving a !gift
//Debug assistants. Not generally useful for server admins who aren't also coding the buff bot itself.
ConVar sm_buffbot_debug_force_category = null; //(0) Debug - force roulette to give good (1), bad (2), weird (3), or death (4)
ConVar sm_buffbot_debug_force_effect = null; //(0) Debug - force roulette/gift to give the Nth effect in that category (ignored if out of bounds)
//More knobs
ConVar sm_buffbot_gravity_modifier = null; //(3) Ratio used for gravity effects - either multiply by this or divide by it
//Not directly triggered by chat, but other ways to encourage carnage
ConVar sm_buffbot_crits_on_domination = null; //(5) Number of seconds to crit-boost everyone (both teams) after a domination - 0 to disable
ConVar sm_buffbot_ignite_chance_on_capture = null; //(25) Percentage chance that a point/flag capture will set everyone on fire.
ConVar sm_buffbot_ignite_chance_on_start_capture = null; //(5) Chance that STARTING a point capture will set everyone on fire.
#include "convars"

//Rolling array of carnage points per user id. If a user connects, then this many other
//users connect and disconnect, there will be a collision, and they'll share the slot. I
//rather doubt that this will happen often, but it might with bots - I don't know. Given
//that bots all get kicked once there are no humans online, there'd have to be a strong
//level of activity all the time for this to wrap and collide (wrapping itself is going
//to be rare, and on its own isn't a problem).
int carnage_points[16384];

int BeamSprite, HaloSprite;
public void OnPluginStart()
{
	RegAdminCmd("sm_critboost", Command_CritBoost, ADMFLAG_SLAY);
	HookEvent("player_say", Event_PlayerChat);
	HookEvent("player_team", InitializePlayer);
	HookEvent("player_death", PlayerDied);
	HookEvent("object_destroyed", BuildingBlownUp);
	HookEvent("player_chargedeployed", Ubered);
	HookEvent("player_upgradedobject", Upgraded);
	HookEvent("ctf_flag_captured", Captured);
	HookEvent("teamplay_point_captured", Captured);
	HookEvent("teamplay_point_startcapture", StartCapture);
	//The actual code to create convars convars is built by the Python script,
	//and yes, I'm aware that I now have two problems.
	CreateConVars();
	//Load up some sprites from funcommands. This is GPL'd, so the following section
	//of code is also GPL'd.
	char buffer[PLATFORM_MAX_PATH];
	Handle gameConfig = LoadGameConfigFile("funcommands.games");
	GameConfGetKeyValue(gameConfig, "SpriteBeam", buffer, sizeof(buffer));
	BeamSprite = PrecacheModel(buffer);
	GameConfGetKeyValue(gameConfig, "SpriteHalo", buffer, sizeof(buffer));
	HaloSprite = PrecacheModel(buffer);
	//End GPL code. (The rest of this file is even more freely usable.)
}

public Action Command_CritBoost(int client, int args)
{
	char player[32];
	/* Try and find a matching player */
	GetCmdArg(1, player, sizeof(player));
	int target = FindTarget(client, player);
	if (target == -1) return Plugin_Handled;

	//Demo: Add one condition permanently, and one temporarily
	//Other ideas: Pick one of the Rune powerups at random
	TF2_AddCondition(target, TFCond_CritOnDamage, TFCondDuration_Infinite, 0);
	TF2_AddCondition(target, TFCond_UberchargedOnTakeDamage, 5.0, 0);

	char name[MAX_NAME_LENGTH];
	GetClientName(target, name, sizeof(name));
	ReplyToCommand(client, "[SM] You crit-boosted %s [%d]!", name, target);

	return Plugin_Handled;
}

public void InitializePlayer(Event event, const char[] name, bool dontBroadcast)
{
	if (!event.GetInt("team")) return; //Player is leaving the game
	char playername[MAX_NAME_LENGTH]; event.GetString("name", playername, sizeof(playername));
	Debug("Player initialized: uid %d team %d was %d name %s",
		event.GetInt("userid"),
		event.GetInt("team"),
		event.GetInt("oldteam"),
		playername);
	carnage_points[event.GetInt("userid") % sizeof(carnage_points)] = GetConVarInt(sm_buffbot_carnage_initial);
}

void add_score(int userid, int score)
{
	if (userid <= 0 || score <= 0) return;
	int new_score = carnage_points[userid % sizeof(carnage_points)] += score;
	Debug("Score: uid %d +%d now %d points", userid, score, new_score);
}

public void PlayerDied(Event event, const char[] name, bool dontBroadcast)
{
	//Is this the best (only?) way to get the name of the person who just died?
	int player = GetClientOfUserId(event.GetInt("userid"));
	char playername[MAX_NAME_LENGTH]; GetClientName(player, playername, sizeof(playername));
	if (event.GetInt("userid") == event.GetInt("attacker"))
	{
		//You killed yourself. Good job.
		//This happens if you use the 'kill' or 'explode' commands, or if
		//you blow yourself up with rockets or similar - but only if nobody
		//else dealt you damage. If an enemy hurts you and THEN you kill
		//yourself, the enemy gets the credit (as a "finished off", but that
		//doesn't affect our calculations here). So if you destroy yourself,
		//award no points. And to maximize the humiliation, we'll announce
		//this to everyone in chat. Muahahaha.
		PrintToChatAll("%s is awarded no points for self-destruction. May God have mercy on your soul.", playername);
		return;
	}
	if (event.GetInt("userid") == event.GetInt("assister"))
	{
		//You helped someone kill you. Impressive!
		//The only way I've found to trigger this is for you to heal an
		//enemy Spy while he kills you. Congrats. We'll let you have the
		//points... as a consolation prize.
		PrintToChatAll("%s needs to learn to spy check. Well done assisting in your own death.", playername);
	}
	//TODO: It's possible to assist in a kill on your own teammate (same way as the above).
	//Would be nice to give a cool message for that too.
	Debug("That's a kill! %s died (uid %d) by %d, assist %d",
		playername, event.GetInt("userid"), event.GetInt("attacker"), event.GetInt("assister"));
	if (event.GetInt("assister") == -1)
	{
		//Solo kill - might be given more points than an assisted one
		add_score(event.GetInt("attacker"), GetConVarInt(sm_buffbot_carnage_per_solo_kill));
	}
	else
	{
		//Assisted kill - award points to both attacker and assister
		add_score(event.GetInt("attacker"), GetConVarInt(sm_buffbot_carnage_per_kill));
		add_score(event.GetInt("assister"), GetConVarInt(sm_buffbot_carnage_per_assist));
	}
	add_score(event.GetInt("userid"), GetConVarInt(sm_buffbot_carnage_per_death));
	int deathflags = event.GetInt("death_flags");
	if (deathflags & (TF_DEATHFLAG_KILLERDOMINATION | TF_DEATHFLAG_ASSISTERDOMINATION))
	{
		//Someone got a domination. Give everyone crits for a few seconds!
		//Of course, someone's dead right now. Sucks to be you. :)
		int duration = GetConVarInt(sm_buffbot_crits_on_domination);
		if (duration)
			for (int target = 1; target <= MaxClients; ++target)
				if (IsClientConnected(target) && IsClientInGame(target) && IsPlayerAlive(target))
					TF2_AddCondition(target, TFCond_CritOnDamage, duration + 0.0, 0);
		if (deathflags & TF_DEATHFLAG_GIBBED)
			PrintToChatAll("Pieces of %s splatter all over everyone. Muahahaha, such happy carnage!", playername);
		else
			PrintToChatAll("The lifeless corpse of %s flies around the map. Muahahaha, such happy carnage!", playername);
	}
	//Revenge doesn't have any in-game effect, but we put a message up about it.
	if (deathflags & (TF_DEATHFLAG_KILLERREVENGE | TF_DEATHFLAG_ASSISTERREVENGE))
	{
		int killer = GetClientOfUserId(event.GetInt("attacker"));
		char killername[MAX_NAME_LENGTH]; GetClientName(killer, killername, sizeof(killername));
		int assister = GetClientOfUserId(event.GetInt("assister"));
		char assistername[MAX_NAME_LENGTH]; GetClientName(assister, assistername, sizeof(assistername));
		int gibbed = deathflags & TF_DEATHFLAG_GIBBED;
		//ugh the verbosity
		if ((deathflags & (TF_DEATHFLAG_KILLERREVENGE | TF_DEATHFLAG_ASSISTERREVENGE)) == (TF_DEATHFLAG_KILLERREVENGE | TF_DEATHFLAG_ASSISTERREVENGE))
		{
			//Double revenge!
			if (gibbed)
				PrintToChatAll("Bwahahahaha! Ooh that feels good. %s and %s splatter %s everywhere!!", killername, assistername, playername);
			else
				PrintToChatAll("Double revenge by %s and %s on the dominating %s!!", killername, assistername, playername);
		}
		else if (deathflags & TF_DEATHFLAG_KILLERREVENGE)
		{
			if (gibbed)
				PrintToChatAll("Takedown! %s splatters %s all over everyone. Feels good.", killername, playername);
			else
				PrintToChatAll("Takedown! %s kicks the lifeless corpse of %s. Feels good.", killername, playername);
		}
		else
		{
			if (gibbed)
				PrintToChatAll("%s helps %s to splatter %s all over everyone. Kaboom!", assistername, killername, playername);
			else
				PrintToChatAll("%s helps %s to kick the corpse of %s. That felt good.", assistername, killername, playername);
		}
	}
}

public void BuildingBlownUp(Event event, const char[] name, bool dontBroadcast)
{
	if (event.GetInt("userid") == event.GetInt("attacker"))
	{
		//You blew up your own building. Not sure if this can happen, but if it
		//does, make sure we award no points. (But there's no need to humiliate.)
		return;
	}
	Debug("Object blown up! uid %d destroyed %d's building.",
		event.GetInt("attacker"), event.GetInt("userid"));
	if (event.GetInt("objecttype") == 2) //TFObject_Sentry
		add_score(event.GetInt("attacker"), GetConVarInt(sm_buffbot_carnage_per_sentry));
	else
		add_score(event.GetInt("attacker"), GetConVarInt(sm_buffbot_carnage_per_building));
}

public void Ubered(Event event, const char[] name, bool dontBroadcast)
{
	Debug("Ubercharge deployed!");
	add_score(event.GetInt("userid"), GetConVarInt(sm_buffbot_carnage_per_ubercharge));
}
public void Upgraded(Event event, const char[] name, bool dontBroadcast)
{
	if (GetConVarInt(sm_buffbot_carnage_per_upgrade)) Debug("Object upgraded!");
	add_score(event.GetInt("userid"), GetConVarInt(sm_buffbot_carnage_per_upgrade));
}

public void Captured(Event event, const char[] name, bool dontBroadcast)
{
	int chance = GetConVarInt(sm_buffbot_ignite_chance_on_capture);
	if (100 * GetURandomFloat() >= chance) return; //Percentage chance
	PrintToChatAll("The air opens with fire and everyone is caught in it!");
	for (int target = 1; target <= MaxClients; ++target)
		if (IsClientConnected(target) && IsClientInGame(target) && IsPlayerAlive(target))
			TF2_IgnitePlayer(target, target);
}

public void StartCapture(Event event, const char[] name, bool dontBroadcast)
{
	int chance = GetConVarInt(sm_buffbot_ignite_chance_on_start_capture);
	if (100 * GetURandomFloat() >= chance) return; //Percentage chance
	PrintToChatAll("The volatility of capture point air sets EVERYONE on fire!");
	for (int target = 1; target <= MaxClients; ++target)
		if (IsClientConnected(target) && IsClientInGame(target) && IsPlayerAlive(target))
			TF2_IgnitePlayer(target, target);
}

public void Event_PlayerChat(Event event, const char[] name, bool dontBroadcast)
{
	//if (event.GetBool("teamonly")) return; //Ignore team chat (not working)
	char msg[64];
	event.GetString("text", msg, sizeof(msg));
	if (!strcmp(msg, "!roulette"))
	{
		int target = GetClientOfUserId(event.GetInt("userid"));
		if (!IsClientInGame(target) || !IsPlayerAlive(target)) return;
		int slot = event.GetInt("userid") % sizeof(carnage_points);
		if (carnage_points[slot] < GetConVarInt(sm_buffbot_carnage_required))
		{
			PrintToChat(target, "You'll have to wreak more havoc before you can do that, sorry.");
			return;
		}
		//Give a random effect to self, more of which are beneficial than not
		//There's a small chance of death (since this is Russian Roulette after all).
		TFCond condition;
		char targetname[MAX_NAME_LENGTH];
		GetClientName(target, targetname, sizeof(targetname));
		int prob_good = GetConVarInt(sm_buffbot_roulette_chance_good);
		int prob_bad = GetConVarInt(sm_buffbot_roulette_chance_bad);
		int prob_weird = GetConVarInt(sm_buffbot_roulette_chance_weird);
		int category = RoundToFloor((prob_good + prob_bad + prob_weird + 1) * GetURandomFloat());
		int sel = GetConVarInt(sm_buffbot_debug_force_effect);
		switch (GetConVarInt(sm_buffbot_debug_force_category))
		{
			case 1: category = 0; //Force to Good
			case 2: category = prob_good; //Force to Bad
			case 3: category = prob_good + prob_bad; //Force to Weird
			case 4: category = prob_good + prob_bad + prob_weird; //Force to death
		}
		if ((category -= prob_good) < 0)
		{
			if (sel > 0 && sel <= sizeof(benefits)) --sel; //Forced selection (1-based)
			else sel = RoundToFloor(sizeof(benefits)*GetURandomFloat());
			condition = benefits[sel];
			PrintToChatAll(benefits_desc[sel], targetname);
		}
		else if ((category -= prob_bad) < 0)
		{
			if (sel > 0 && sel <= sizeof(detriments)) --sel; //Forced selection (1-based)
			else sel = RoundToFloor(sizeof(detriments)*GetURandomFloat());
			condition = detriments[sel];
			PrintToChatAll(detriments_desc[sel], targetname);
		}
		else if ((category -= prob_weird) < 0)
		{
			if (sel > 0 && sel <= sizeof(weird)) --sel; //Forced selection (1-based)
			else sel = RoundToFloor(sizeof(weird)*GetURandomFloat());
			condition = weird[sel];
			PrintToChatAll(weird_desc[sel], targetname);
		}
		else //One chance of death, always.
		{
			//Super-secret super buff: if you would get the death effect
			//but you had ten times the required carnage points, grant a
			//Mannpower pickup instead of killing the player.
			if (carnage_points[slot] > 10 * GetConVarInt(sm_buffbot_carnage_required))
			{
				TFCond runes[] = {
					TFCond_RuneStrength,
					TFCond_RuneHaste,
					TFCond_RuneRegen,
					TFCond_RuneResist,
					TFCond_RuneWarlock,
					TFCond_RunePrecision,
					TFCond_RuneAgility,
					TFCond_KingRune,
				};
				TFCond rune = runes[RoundToFloor(sizeof(runes)*GetURandomFloat())];
				TF2_AddCondition(target, rune, TFCondDuration_Infinite, 0);
				PrintToChatAll("%s now carries something special...", targetname);
			}
			else
			{
				//Kill the person. Slap! Bam!
				//TODO: Remove any invulnerabilities first, just in case.
				PrintToChatAll("%s begs for something amazing...", targetname);
				SlapPlayer(target, 1000); //1000hp of damage should kill anyone.
			}
			carnage_points[slot] = 0;
			return;
		}

		apply_effect(target, condition);
		carnage_points[slot] = 0;
	}
	if (!strcmp(msg, "!gift"))
	{
		//Pick a random target OTHER THAN the one who said it
		//Give a random effect, guaranteed beneficial
		int self = GetClientOfUserId(event.GetInt("userid"));
		if (!IsClientInGame(self) || !IsPlayerAlive(self)) return;
		int slot = event.GetInt("userid") % sizeof(carnage_points);
		if (carnage_points[slot] < GetConVarInt(sm_buffbot_carnage_required))
		{
			PrintToChat(self, "You'll have to wreak more havoc before you can do that, sorry.");
			return;
		}
		carnage_points[slot] = 0;
		int myteam = GetClientTeam(self);
		int client_weight[100]; //Assumes MaxClients never exceeds 99. Dynamic arrays don't seem to work as documented.
		if (MaxClients >= sizeof(client_weight)) {PrintToServer("oops, >99 clients"); return;}
		int tot_weight = 0;
		char selfname[MAX_NAME_LENGTH];
		GetClientName(self, selfname, sizeof(selfname));
		for (int i = 1; i <= MaxClients; ++i) if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			int weight;
			if (i == self) weight = 0; //You never receive your own gift.
			else if (GetClientTeam(i) == myteam)
			{
				//Is there any way to play TF2 without a Steam account connected? VAC-unsecured
				//servers? If so, those not Steamy will be considered bots, as I haven't found
				//a better way to recognize bots.
				if (GetSteamAccountID(i)) weight = GetConVarInt(sm_buffbot_gift_chance_friendly_human);
				else weight = GetConVarInt(sm_buffbot_gift_chance_friendly_bot);
			}
			else
			{
				if (GetSteamAccountID(i)) weight = GetConVarInt(sm_buffbot_gift_chance_enemy_human);
				else weight = GetConVarInt(sm_buffbot_gift_chance_enemy_bot);
			}
			client_weight[i] = weight;
			tot_weight += weight;
		}
		else client_weight[i] = 0;
		if (!tot_weight)
		{
			//This can happen if all eligible players are currently dead, as a
			//dead player won't be given a buff. And that situation can happen
			//fairly easily if the weighting cvars are set restrictively (eg
			//preventing all bots from getting buffs). The price is that your
			//carnage points get wasted.
			PrintToChatAll("%s offered a gift, but nobody took it :(", selfname);
			return;
		}
		Debug("Total gift chance pool: %d", tot_weight);
		int sel = RoundToFloor(GetURandomFloat() * tot_weight);
		for (int i = 1; i <= MaxClients; ++i)
		{
			if (sel < client_weight[i])
			{
				char targetname[MAX_NAME_LENGTH];
				GetClientName(i, targetname, sizeof(targetname));
				if (GetClientTeam(i) == myteam)
					PrintToChatAll("%s offered a random gift, which was gratefully accepted by %s!", selfname, targetname);
				else
					PrintToChatAll("%s offered a random gift, which was gleefully accepted by %s!", selfname, targetname);
				sel = RoundToFloor(sizeof(benefits)*GetURandomFloat());
				PrintToChatAll(benefits_desc[sel], targetname);
				apply_effect(i, benefits[sel]);
				break;
			}
			sel -= client_weight[i];
		}
	}
}

//Silence the warning "unused parameter"
any ignore(any ignoreme) {return ignoreme;}

int ticking_down[MAXPLAYERS + 1]; //Any effect that's managed by a timer will tick down in this.
Action regenerate(Handle timer, any target)
{
	ignore(timer);
	//When you die, you stop regenerating.
	if (!IsClientInGame(target) || !IsPlayerAlive(target)) return Plugin_Stop;
	//Debug("Regenerating %d", target);
	TF2_RegeneratePlayer(target);
	//After thirty regens (approx 30 seconds, but maybe +/- a second or so),
	//we stop regenerating.
	if (--ticking_down[target] <= 0) return Plugin_Stop;
	return Plugin_Handled;
}

//NOTE: If you get multiple gravity-changing effects, they will
//overwrite each other, AND the end of any gravity change results
//in your gravity resetting to normal.
Action reset_gravity(Handle timer, any target)
{
	if (!IsClientInGame(target) || !IsPlayerAlive(target)) return Plugin_Stop;
	char targetname[MAX_NAME_LENGTH];
	GetClientName(target, targetname, sizeof(targetname));
	PrintToChatAll("%s returns to normal gravity.", targetname);
	ignore(timer);
	SetEntityGravity(target, 1.0);
	return Plugin_Stop;
}

Action weird_gravity(Handle timer, any target)
{
	//If you're dead, reset to normal.
	if (!IsClientInGame(target) || !IsPlayerAlive(target)) return reset_gravity(timer, target);
	char targetname[MAX_NAME_LENGTH];
	GetClientName(target, targetname, sizeof(targetname));
	float max_gravity_factor = GetConVarFloat(sm_buffbot_gravity_modifier);
	float gravity_factor = GetEntityGravity(target);
	//Debug("Current gravity_factor: %f", gravity_factor);
	//To simplify some of the calculations, we always work with values >1.
	//That way, "2" means either half or double, and we can never hit 0.0 gravity.
	bool reduced = gravity_factor < 1.0;
	if (reduced) gravity_factor = 1.0 / gravity_factor;
	if (gravity_factor == 1.0) reduced = (GetURandomFloat() < 0.5); //Initially, pick heavier/lighter at random
	if (GetURandomFloat() < 0.1) reduced = !reduced; //Sometimes, we flip from heavier to lighter or vice versa.
	if (GetURandomFloat() < (gravity_factor - 0.9) / max_gravity_factor)
	{
		//Reduce effect or invert
		if (gravity_factor <= 1.0 + max_gravity_factor / 10.0)
			reduced = !reduced;
		else
			gravity_factor -= max_gravity_factor / 10.0;
		Debug("%s gets closer to normal: %f %s", targetname, gravity_factor, reduced ? "lighter" : "heavier");
	}
	else
	{
		//Increase effect (if possible)
		gravity_factor += max_gravity_factor / 10.0;
		if (gravity_factor > max_gravity_factor)
			gravity_factor = max_gravity_factor;
		Debug("%s gets more abnormal: %f %s", targetname, gravity_factor, reduced ? "lighter" : "heavier");
	}
	ignore(timer);
	if (reduced) gravity_factor = 1.0 / gravity_factor;
	SetEntityGravity(target, gravity_factor);
	if (--ticking_down[target] <= 0) return Plugin_Stop;
	return Plugin_Handled;
}

Action beacon(Handle timer, int target)
{
	ignore(timer);
	if (!IsClientInGame(target) || !IsPlayerAlive(target)) return Plugin_Stop;
	if (!TF2_IsPlayerInCondition(target, TFCond_MarkedForDeathSilent)) return Plugin_Stop;
	float vec[3];
	GetClientAbsOrigin(target, vec);
	vec[2] += 10;
	TE_SetupBeamRingPoint(vec, 10.0, 375.0, BeamSprite, HaloSprite, 0, 15, 0.5, 5.0, 0.0, {255, 255, 0, 255}, 10, 0);
	TE_SendToAll();
	return Plugin_Handled;
}

int blinded[MAXPLAYERS + 1];
void blind(int target, int amount)
{
	if (!IsClientInGame(target) || !IsPlayerAlive(target)) return;
	//Borrowed from funcommands::blind.sp
	//This code is governed by the terms of the GPL. (The rest of this file
	//is under even more free terms.)
	int duration = 1536;
	int holdtime = 1536;
	//Magic numbers. I've no idea what these flags do/mean.
	int flags = amount ? 10 : 17;
	int color[4] = { 128, 0, 0, 0 };
	color[3] = amount;
	
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

Action unblind(Handle timer, any target)
{
	if (--blinded[target]) return Plugin_Stop; //Still blinded by something else
	char targetname[MAX_NAME_LENGTH];
	GetClientName(target, targetname, sizeof(targetname));
	PrintToChatAll("%s's vision returns to normal.", targetname);
	ignore(timer);
	blind(target, 0);
	return Plugin_Stop;
}

void apply_effect(int target, TFCond condition)
{
	int duration = GetConVarInt(sm_buffbot_buff_duration);
	//Special-case some effects (or pseudo-effects) that we handle
	//ourselves with a timer, rather than pushing through AddCondition.
	//Since all of these (all one of these) use the same ticking_down array,
	//applying a second such effect during another's duration will extend
	//the first one, but then BOTH timers will be decrementing the clock.
	if (condition == TFCond_RegenBuffed)
	{
		ticking_down[target] = duration;
		CreateTimer(1.0, regenerate, target, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		Debug("Applied effect Regeneration to %d", target);
		return;
	}
	else if (condition == view_as<TFCond>(-1))
	{
		float gravity_factor = GetConVarFloat(sm_buffbot_gravity_modifier);
		SetEntityGravity(target, 1/gravity_factor);
		CreateTimer(duration + 0.0, reset_gravity, target);
		Debug("Applied effect Low Gravity to %d", target);
		return;
	}
	else if (condition == view_as<TFCond>(-2))
	{
		float gravity_factor = GetConVarFloat(sm_buffbot_gravity_modifier);
		SetEntityGravity(target, gravity_factor);
		CreateTimer(duration + 0.0, reset_gravity, target);
		Debug("Applied effect High Gravity to %d", target);
		return;
	}
	else if (condition == view_as<TFCond>(-3))
	{
		ticking_down[target] = duration - 1; //Just to make sure, this one has one second less duration.
		SetEntityGravity(target, 1.0);
		CreateTimer(1.0, weird_gravity, target, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(duration + 1.0, reset_gravity, target); //Just to make sure, we reset *one second* after normal duration
		Debug("Applied effect Weird Gravity to %d", target);
		return;
	}
	else if (condition == view_as<TFCond>(-4))
	{
		++blinded[target];
		blind(target, 253);
		Debug("Applied effect Darkened Vision to %d", target);
		CreateTimer(duration + 0.0, unblind, target);
		return;
	}
	else if (condition == view_as<TFCond>(-5))
	{
		++blinded[target];
		blind(target, 255);
		CreateTimer(duration + 0.0, unblind, target);
		TF2_AddCondition(target, TFCond_UberchargedOnTakeDamage, duration + 0.0, 0);
		TF2_AddCondition(target, TFCond_CritOnDamage, duration + 0.0, 0);
		TF2_AddCondition(target, TFCond_MarkedForDeathSilent, duration + 0.0, 0);
		TF2_AddCondition(target, TFCond_MegaHeal, duration + 0.0, 0); //Immunity to knock-back
		Debug("Applied effect Blind Rage to %d", target);
		return;
	}
	//Some effects need additional code.
	else if (condition == TFCond_Plague)
	{
		//Start a bleed effect as well as applying the Plague condition.
		//The condition causes a "squelch" sound and stuff; the bleed
		//causes hitpoint loss.
		TF2_MakeBleed(target, target, duration + 0.0);
	}
	else if (condition == TFCond_MarkedForDeathSilent)
	{
		//Make the death mark less silent. No tickdown - it looks for
		//the MFD condition's removal.
		//Removed 20171119 as it may be the cause of some crashes (????)
		if (!target) //aka "if (0)" but w/o warning
			CreateTimer(0.25, beacon, target, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	TF2_AddCondition(target, condition, duration + 0.0, 0);
	Debug("Applied effect %d to %d", condition, target);
}