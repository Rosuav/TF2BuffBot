#include <sourcemod>
#include <tf2_stocks>
#include "randeffects"

public Plugin myinfo =
{
	name = "Buff Bot",
	author = "Chris Angelico",
	description = "Experimental bot that can buff players",
	version = "0.1",
	url = "http://www.rosuav.com/",
};

//Before you can use !roulette or !gift, you must fill your (invisible) carnage counter.
ConVar sm_buffbot_carnage_initial = null; //(0) Carnage points a player has on first joining
ConVar sm_buffbot_carnage_per_kill = null; //(2) Carnage points gained for each kill
ConVar sm_buffbot_carnage_per_assist = null; //(1) Carnage points gained for each assist
ConVar sm_buffbot_carnage_per_death = null; //(3) Carnage points gained when you die
ConVar sm_buffbot_carnage_required = null; //(10) Carnage points required to use !roulette or !gift
//When you grant a !gift, players (other than yourself) will have this many chances each.
ConVar sm_buffbot_gift_chance_friendly_human = null; //(20) Chance that each friendly human has of receiving a !gift
ConVar sm_buffbot_gift_chance_friendly_bot = null; //(2) Chance that each friendly bot has of receiving a !gift
ConVar sm_buffbot_gift_chance_enemy_human = null; //(10) Chance that each enemy human has of receiving a !gift
ConVar sm_buffbot_gift_chance_enemy_bot = null; //(1) Chance that each enemy bot has of receiving a !gift
#include "convars"

public void OnPluginStart()
{
	RegAdminCmd("sm_critboost", Command_CritBoost, ADMFLAG_SLAY);
	HookEvent("player_say", Event_PlayerChat);
	//The actual code to create convars convars is built by the Python script,
	//and yes, I'm aware that I now have two problems.
	CreateConVars();
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

public void Event_PlayerChat(Event event, const char[] name, bool dontBroadcast)
{
	//if (event.GetBool("teamonly")) return; //Ignore team chat (not working)
	char msg[64];
	event.GetString("text", msg, sizeof(msg));
	//PrintToServer("User %d said: %s", event.GetInt("userid"), msg);
	if (!strcmp(msg, "!roulette"))
	{
		int target = GetClientOfUserId(event.GetInt("userid"));
		//Give a random effect to self, more of which are beneficial than not
		//TODO: Have a small chance of death (since this is Russian Roulette after all)
		int sel;
		TFCond condition;
		char targetname[MAX_NAME_LENGTH];
		GetClientName(target, targetname, sizeof(targetname));
		switch (RoundToFloor(10 * GetURandomFloat()))
		{
			case 0, 1, 2, 3, 4, 5: //60% chance + 6% chance below = two times in three
			{
				sel = RoundToFloor(sizeof(benefits)*GetURandomFloat());
				condition = benefits[sel];
				PrintToChatAll(benefits_desc[sel], targetname);
			}
			case 6, 7, 8: //30% chance of detriment
			{
				sel = RoundToFloor(sizeof(detriments)*GetURandomFloat());
				condition = detriments[sel];
				PrintToChatAll(detriments_desc[sel], targetname);
			}
			case 9: switch (RoundToFloor(10 * GetURandomFloat()))
			{
				case 0, 1, 2, 3, 4, 5: //The other 6% chance for the above
				{
					//Duplicate of the above
					sel = RoundToFloor(sizeof(benefits)*GetURandomFloat());
					condition = benefits[sel];
					PrintToChatAll(benefits_desc[sel], targetname);
				}
				case 6, 7, 8: //3% chance of a weird effect
				{
					sel = RoundToFloor(sizeof(weird)*GetURandomFloat());
					condition = weird[sel];
					PrintToChatAll(weird_desc[sel], targetname);
				}
				case 9: //1% chance of death
					//TODO: Kill the person
					return;
			}
		}

		TF2_AddCondition(target, condition, 30.0, 0);
		PrintToServer("Applied effect %d", condition);
	}
	if (!strcmp(msg, "!gift"))
	{
		//TODO: Pick a random target OTHER THAN the one who said it
		//Give a random effect, guaranteed beneficial
		int self = GetClientOfUserId(event.GetInt("userid"));
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
			PrintToChatAll("%s offered a gift, but nobody took it :(", selfname);
			return;
		}
		PrintToServer("Total gift chance pool: %d", tot_weight);
		int sel = RoundToFloor(GetURandomFloat() * tot_weight);
		for (int i = 1; i <= MaxClients; ++i)
		{
			if (sel < client_weight[i])
			{
				char targetname[MAX_NAME_LENGTH];
				GetClientName(i, targetname, sizeof(targetname));
				PrintToChatAll("%s offered a random gift, which was gratefully accepted by %s!", selfname, targetname);
				sel = RoundToFloor(sizeof(benefits)*GetURandomFloat());
				PrintToChatAll(benefits_desc[sel], targetname);
				TF2_AddCondition(i, benefits[sel], 30.0, 0);
				PrintToServer("Applied effect %d to %s", benefits[sel], targetname);
				break;
			}
			sel -= client_weight[i];
		}
	}
}
