//Analyze the smoke logs from drzed

mapping(string:object) scatterplots = ([]);
//Scale the resulting image such that the edges of the display are these values
//constant top = -16.0, bottom = -14.0, left = 88.0, right = 91.0; //Good for Xbox smokes (-22.09, 89.07) - (-13.79, 90.51)
constant top = -26.0, bottom = -25.0, left = 67.0, right = 68.0; //Good for B window smokes (-25.65, 67.44) - (-25.33, 67.55)
constant img_width = 800, img_height = 600;
constant colors = ([
	"GOOD": ({0, 255, 0}),
	"FAIL": ({192, 0, 0}),
]);

float a1_min = 361.0, a1_max = -361.0, a2_min = 361.0, a2_max = -361.0;
void place_marker(string timing, float a1, float a2, string type)
{
	if (!scatterplots[timing]) scatterplots[timing] = Image.Image(img_width, img_height);
	//Convert the angles into pixel positions.
	//Angle a1 determines elevation so we use that for the y axis
	//Angle a2 effectively determines the left-right positioning of the throw,
	//since we're working with a fairly narrow band of valid angles.
	if (type == "GOOD")
	{
		a1_min = min(a1_min, a1);
		a1_max = max(a1_max, a1);
		a2_min = min(a2_min, a2);
		a2_max = max(a2_max, a2);
	}
	int x = (int)(img_width * (a2 - left) / (right - left));
	int y = (int)(img_height * (a1 - top) / (bottom - top));
	scatterplots[timing]->setcolor(@colors[type])->polyfill(({
		//Create a sort of plus-shaped marker surrounding (x,y)
		x-3, y+1, x-1, y+1, x-1, y+3, x, y+5,
		x+1, y+3, x+1, y+1, x+3, y+1, x+5, y,
		x+3, y-1, x+1, y-1, x+1, y-3, x, y-5,
		x-1, y-3, x-1, y-1, x-3, y-1, x-5, y,
	}));
}

//See if the throw location was near enough to our specified point
int near_enough(float x, float y)
{
	//return ((x - -299.96) ** 2 + (y - -1163.96) ** 2) < 1; //Analyze Xbox smokes
	return ((x - -2185.96) ** 2 + (y - 1059.02) ** 2) < 1; //Analyze B Window smokes
}

int main()
{
	//Each throw is an array:
	//({x1,y1,z1,a1,a2, timing, x2,y2,z2, bounce, x3,y3,z3, result})
	//x1,y1,z1	Location during launch (the z value is correlated somewhat to timing)
	//a1,a2		Eye angles during launch (consistent regardless of timing)
	//timing	Timing of a jump-throw (negative means smoke-then-throw, positive throw-then-smoke), or "" if not a jump-throw
	//x2,y2,z2	Location of first grenade bounce - a strong clue as to success
	//bounce	The predicted result based on bounce position - "PROMISING" or "MISSED" (or "" if it never bounced)
	//x3,y3,z3	Location where the smoke popped
	//result	Calculated result - "GOOD" or "FAIL"
	array throws = ({ "x1 y1 z1 a1 a2 timing x2 y2 z2 bounce x3 y3 z3 result"/" " });
	mapping(int:array) clients = ([]); //Pending throws that we don't have entity IDs for
	mapping(int:array) nades = ([]); //Active throws that haven't popped yet (by entity ID)
	foreach (Stdio.read_file("../tf2server/steamcmd_linux/csgo/csgo/learn_smoke.log") / "\n"; int lno; string line)
	{
		/*
		A grenade sequence consists of (up to) five lines, with a single
		client ID (n) and, where available, a single entity ID (x).
		[n-A] Smoke
		[n-B] JumpThrow (may be absent)
		[n-C-x] Spawn
		[n-D-x] Bounce (may be absent, esp if I use this for flashes too)
		[n-E-x] Pop
		They will always occur in strict sequence for any given throw.
		They may be interleaved, however. It's virtually impossible to
		throw two grenades before one has spawned, so for any given client
		ID, assume that n-A and n-C-x will correspond (as will n-B if it's
		there). After n-C-x, the entity ID can be used reliably until it
		pops, as it cannot be reused.
		*/
		if (sscanf(line, "[%d-A] Smoke (%f, %f, %f) - (%f, %f)",
			int client, float x, float y, float z, float a1, float a2) == 6)
		{
			clients[client] = ({x, y, z, a1, a2}) + ({""})*9 + ({lno});
		}
		else if (sscanf(line, "[%d-B] JumpThrow %s", int client, string timing) == 2)
		{
			if (clients[client]) clients[client][5] = timing; //Note that this will be a string, which allows "+0" and "-0" to be distinguished
		}
		else if (sscanf(line, "[%d-C-%d] Spawn", int client, int entity) == 2)
		{
			//Note that sv_rethrow_last_grenade will spawn one with an owner of 0.
			if (client > 0) nades[entity] = m_delete(clients, client);
		}
		else if (sscanf(line, "[%d-D-%d] Bounce (%f, %f, %f) - %s",
			int client, int entity, float x, float y, float z, string status) == 6)
		{
			if (!nades[entity]) continue;
			nades[entity][6] = x;
			nades[entity][7] = y;
			nades[entity][8] = z;
			nades[entity][9] = status;
		}
		else if (sscanf(line, "[%d-E-%d] Pop (%f, %f, %f) - %s",
			int client, int entity, float x, float y, float z, string status) == 6)
		{
			array nade = m_delete(nades, entity);
			if (!nade) continue;
			nade += ({lno - nade[-1]});
			nade[10] = x;
			nade[11] = y;
			nade[12] = z;
			nade[13] = status;
			//if (status == "GOOD" && nade[9] == "PROMISING") write("%{%8.2f %}   %s\n", nade[..4], nade[5]);
			if (near_enough(nade[0], nade[1]) && nade[5] != "")
				place_marker(nade[5], nade[3], nade[4], status);
			throws += ({nade});
		}
	}
	Stdio.write_file("smoke_analysis.csv", sprintf("%{%O,%}\n", throws[*]) * ""); //Yeah, it puts a trailing comma on each line. Whatevs.
	write("Good throws are all within (%.2f, %.2f) - (%.2f, %.2f)\n", a1_min, a2_min, a1_max, a2_max);
	foreach (scatterplots; string timing; object plot)
	{
		//For some reason my PNG encoder is broken.
		//Stdio.write_file("plot" + timing + ".png", Image.PNG.encode(plot));
		Stdio.write_file("tmp.tiff", Image.TIFF.encode(plot));
		Process.create_process(({"/usr/bin/convert", "tmp.tiff", "plot" + timing + ".png"}))->wait();
	}
	rm("tmp.tiff");
}
