//> path: ~/tf2server/steamcmd_linux/csgo/game/csgo/addons/counterstrikesharp/api
//> path: ~/tf2server/steamcmd_linux/csgo/game/csgo/addons/counterstrikesharp/dotnet/shared/Microsoft.NETCore.App/8.0.3
//> -target:library
//> import: System.Runtime
//> import: System.Private.CoreLib
//> import: CounterStrikeSharp.API
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Attributes;
using CounterStrikeSharp.API.Core.Attributes.Registration;

namespace DrZed {public class DrZedPlugin : BasePlugin {
	public override string ModuleName => "DrZed Hello World Plugin";

	public override string ModuleVersion => "0.0.1";

	public override void Load(bool hotReload) {
		System.Console.WriteLine("Hello Dr Zed's World! 1");
	}

/*	[ConsoleCommand("chat", "Send administrative chat messages")]
	//[CommandHelper(minArgs: 1, usage: "[msg]", whoCanExecute: CommandUsage.SERVER)]
	public void OnChatCommand(CCSPlayerController? player, CommandInfo command) {
		Console.Write($@"
		Arg Count: {command.ArgCount}
		Arg String: {command.ArgString}
		Command String: {command.GetCommandString}");
	}*/

	[GameEventHandler]
	public HookResult OnPlayerHurt(EventPlayerHurt @event, GameEventInfo info) {
		/*if (@event.Userid.IsValid) {
			System.Console.WriteLine("Player got hurt! " + @event.Userid.PlayerName);
		}*/
		System.Console.WriteLine("Player got hurt!");

		return HookResult.Continue;
	}
}}
//Stuff to port in:
//zed_money (s/be a nice easy test of chat commands)
//sm_drzed_max_hitpoints
//The two-flashes-no-knife bug, see if it's still there
//Disable kits in warmup
//!mark/!showpos
//!drop
