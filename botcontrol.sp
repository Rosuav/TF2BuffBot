#include <sourcemod>
#include <tf2_stocks>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
	name = "Bot Control",
	author = "Chris Angelico",
	description = "Force bots to obey humans on their teams",
	version = "0.1",
	url = "https://github.com/Rosuav/TF2BuffBot",
};

public void OnPluginStart()
{
	//RegAdminCmd("sm_oi", Command_Oi, 0); //Is this the right way to add a non-administrative command? Doesn't seem to work properly anyway.
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_say", Event_PlayerChat);
}
public void OnConfigsExecuted() 
{
	//Stop the bots from constantly suiciding to change class (and never being satisfied)
	SetConVarInt(FindConVar("tf_bot_reevaluate_class_in_spawnroom"), 0);
}

public Action Command_Oi(int client, int args)
{
	char player[32];
	GetCmdArg(1, player, sizeof(player));
	ReplyToCommand(client, "Arg 1 = %s", player);
	int target = FindTarget(client, player, false, true);
	if (target == -1) return Plugin_Handled;

	char command[32];
	GetCmdArg(2, command, sizeof(command));

	char name[MAX_NAME_LENGTH];
	GetClientName(target, name, sizeof(name));
	ReplyToCommand(client, "[SM] You order %s to %s.", name, command);

	return Plugin_Handled;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	//If we're spawning a bot that has no class, give it one. (Maybe.)
	//This SEEMS to prevent the "stuck in respawn" state that bots end up in.
	int team = GetEventInt(event, "team");
	int cls = GetEventInt(event, "class");
	if (team || cls) return; //Already picked team or class? Keep it. Except Spy.
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsClientConnected(client) && IsClientInGame(client) && IsFakeClient(client))
	{
		char cliname[MAX_NAME_LENGTH];
		GetClientName(client, cliname, sizeof(cliname));
		//PrintToServer("## assigning %s (%d) to a damage class on team %d ## %s ##", cliname, client, team, name);
		TFClassType damage_classes[] = {
			TFClass_Soldier,
			TFClass_DemoMan,
			TFClass_Heavy,
			TFClass_Pyro,
		};
		TF2_SetPlayerClass(client, damage_classes[RoundToFloor(sizeof(damage_classes) * GetURandomFloat())], false, true);
		return;
	}
	return;
}

public void Event_PlayerChat(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	char msg[64];
	event.GetString("text", msg, sizeof(msg));
	char arg[64] = "cmd_";
	int pos = 0;
	int target = -1;
	Function action = INVALID_FUNCTION;
	int team = GetClientTeam(client);
	for (int i = 0;; ++i)
	{
		//NOTE: Subscripting a string yields a substring starting at that
		//position. BreakString returns an index into its input. So we
		//maintain our own position marker.
		//Use arg[4] everywhere except when looking up a function name.
		int len = BreakString(msg[pos], arg[4], sizeof(arg)-4);
		if (!i && strcmp(arg[4], "!oi")) return; //First word must be "!oi"
		//We need to get a target (which must name a bot) and a command (which
		//will be one of a small set of known strings).
		Function callme = GetFunctionByName(INVALID_HANDLE, arg);
		if (callme != INVALID_FUNCTION) action = callme;
		int target_list[MAXPLAYERS]; char targname[8]; bool is_ml;
		int targets = ProcessTargetString(arg[4], client, target_list, MAXPLAYERS,
			COMMAND_FILTER_NO_IMMUNITY, targname, sizeof(targname), is_ml);
		for (int t = 0; t < targets; ++t) //targets could be <= 0, in which case we skip this loop
		{
			//Theoretically this should check for botness??
			if (IsClientConnected(target_list[t]) && IsClientInGame(target_list[t]) && IsFakeClient(target_list[t]))
				if (GetClientTeam(target_list[t]) == team) //No fair ordering opposing bots around!
					target = target_list[t];
		}
		//Once len is -1, we're done with args.
		if (len == -1) break;
		pos += len;
	}
	if (action == INVALID_FUNCTION)
	{
		PrintToChat(client, "Must specify a valid action");
		return;
	}
	if (target == -1)
	{
		PrintToChat(client, "Must target a bot on your own team");
		return;
	}
	Call_StartFunction(INVALID_HANDLE, action);
	Call_PushCell(client);
	Call_PushCell(target);
	Call_Finish();
}

public void cmd_speak(int client, int target)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	char targname[MAX_NAME_LENGTH];
	GetClientName(target, targname, sizeof(targname));
	PrintToChat(client, "%s orders %s to speak!", name, targname);
	FakeClientCommandEx(target, "say Woof!");
}

//Order a bot to drop powerups and/or the flag
public void cmd_drop(int client, int target)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	char targname[MAX_NAME_LENGTH];
	GetClientName(target, targname, sizeof(targname));
	PrintToChatAll("%s orders %s to drop it!", name, targname);
	FakeClientCommandEx(target, "dropitem");
}

//Order a bot to become a medic
public void cmd_medic(int client, int target)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	char targname[MAX_NAME_LENGTH];
	GetClientName(target, targname, sizeof(targname));
	PrintToChatAll("%s tells %s to go medic!", name, targname);
	TF2_SetPlayerClass(target, TFClass_Medic, false, true);
}

//Order a bot to become a soldier. TODO: Make a generic one: "!oi BotName go ClassName"
public void cmd_soldier(int client, int target)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	char targname[MAX_NAME_LENGTH];
	GetClientName(target, targname, sizeof(targname));
	PrintToChatAll("%s tells %s to go soldier!", name, targname);
	TF2_SetPlayerClass(target, TFClass_Soldier, false, true);
}

//MVM! Ready up!
//Doesn't seem to work.
public void cmd_ready(int client, int target)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	char targname[MAX_NAME_LENGTH];
	GetClientName(target, targname, sizeof(targname));
	PrintToChatAll("%s declares that %s is ready!", name, targname);
	FakeClientCommandEx(target, "player_ready_toggle");
}

//Order a bot to build his teleporter exit (engineers only, obviously)
//Doesn't seem to work.
public void cmd_telehere(int client, int target)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	char targname[MAX_NAME_LENGTH];
	GetClientName(target, targname, sizeof(targname));
	PrintToChatAll("%s orders %s to build a tele exit", name, targname);
	FakeClientCommandEx(target, "build 4");
}

//Would love to be able to add a "heel" command, which would cause the
//bot to attempt to move to the player's location for the next, say, 10 secs.
