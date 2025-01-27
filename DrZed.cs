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
