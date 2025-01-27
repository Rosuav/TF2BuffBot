using CounterStrikeSharp.API.Core;

namespace DrZed {
	public class DrZedPlugin : BasePlugin
	{
	    public override string ModuleName => "DrZed Hello World Plugin";

	    public override string ModuleVersion => "0.0.1";

	    public override void Load(bool hotReload)
	    {
		System.Console.WriteLine("Hello Dr Zed's World!");
	    }
	}
}
//Stuff to port in:
//zed_money (s/be a nice easy test of chat commands)
//sm_drzed_max_hitpoints
//The two-flashes-no-knife bug, see if it's still there
//Disable kits in warmup
//!mark/!showpos
//!drop
