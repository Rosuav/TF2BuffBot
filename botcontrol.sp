#include <sourcemod>
#include <tf2_stocks>

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
	HookEvent("player_say", Event_PlayerChat);
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

public void Event_PlayerChat(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	char msg[64];
	event.GetString("text", msg, sizeof(msg));
	char arg[64] = "cmd_";
	int pos = 0;
	int target = -1;
	new Function:action = INVALID_FUNCTION;
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
		new Function:callme = GetFunctionByName(INVALID_HANDLE, arg);
		if (callme != INVALID_FUNCTION) action = callme;
		int target_list[1]; char targname[8]; bool is_ml;
		if (ProcessTargetString(arg[4], client, target_list, 1,
			COMMAND_FILTER_NO_IMMUNITY, targname, sizeof(targname), is_ml) > 0)
		{
			target = target_list[0];
		}
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
		PrintToChat(client, "Must nominate a (bot) target");
		return;
	}
	//TODO: Verify that the target is (a) a bot, and (b) on the same team as the client
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
