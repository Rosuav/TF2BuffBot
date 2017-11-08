#include <sourcemod>
#include <tf2_stocks>

public Plugin myinfo =
{
	name = "Hello World",
	author = "Chris Angelico",
	description = "Basic test plugin",
	version = "0.1",
	url = "http://www.rosuav.com/",
};

public void OnPluginStart()
{
	RegAdminCmd("sm_critboost", Command_CritBoost, ADMFLAG_SLAY);
	HookEvent("player_say", Event_PlayerChat);
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
	if (!strcmp(msg, "kaboom")) //TODO: Have the keyword change randomly
	{
		//TODO: Pick a random target OTHER THAN the one who said it
		int target = GetClientOfUserId(event.GetInt("userid"));
		char name[MAX_NAME_LENGTH];
		GetClientName(target, name, sizeof(name));
		PrintToServer("User %d is named %s", target, name);
		TF2_AddCondition(target, TFCond_CritOnDamage, 30.0, 0);
		TF2_AddCondition(target, TFCond_UberchargedOnTakeDamage, 5.0, 0);
	}
}
