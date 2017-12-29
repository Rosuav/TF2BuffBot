# Generate MVM waves with harbingers and such
# The actual .pop file has tons of redundancy, which means editing it is tedious.

STARTING_MONEY = 1505 # I use a weird value here so that versioning becomes easy
HARBINGER_MONEY = 100
TANK_MONEY = 500
SUPPORT_MONEY = 100

# Don't know what of this would be different for different maps
PREAMBLE = """//This file was generated by gen_mvm_waves.py
#base robot_giant.pop
#base robot_standard.pop
#base robot_gatebot.pop
population
{
	StartingCurrency	%d
	RespawnWaveTime		6
	CanBotsAttackWhileInSpawnRoom	no
	Templates
	{
		T_TFBot_Heavy
		{
			Health	300
			Name	Heavy
			Class	HeavyWeapons
			Skill	Normal
			Item	"tf_weapon_minigun"
			Item	"tf_weapon_shotgun_hwg"
			Item	"tf_weapon_fists"
		}
		BOSS_ReflectMe
		{
			Health	200000
			Name	"Reflect Me"
			Class	Soldier
			Skill	Normal
			WeaponRestrictions	PrimaryOnly
			Attributes	"AlwaysCrit"
			Attributes	"MiniBoss"
			Item	"the original"
			Item	"tf_weapon_shotgun_soldier"
			Item	"tf_weapon_shovel"
			CharacterAttributes
			{
				"Projectile speed decreased"	0.75
				"damage bonus"			10
				"dmg falloff decreased"		1
				"move speed penalty"		0.15
				"airblast vulnerability multiplier"	0
			}
		}
	}"""

total_money = STARTING_MONEY

def make_wave(tanks=1, support=()):
	wave_money = 0
	info = """	Wave
	{
		WaitWhenDone	65
		Checkpoint	Yes
		StartWaveOutput
		{
			Target	wave_start_relay
			Action	Trigger
		}
		DoneOutput
		{
			Target	wave_finished_relay
			Action	Trigger
		}
"""
	for i in range(tanks):
		# Add the harbinger. The first one is a little bit different.
		info += """		WaveSpawn
		{
			Name	"Harbinger %d"
			%s
			TotalCurrency	%d
			TotalCount	1
			MaxActive	5
			SpawnCount	2
			Where	spawnbot
			WaitBeforeStarting	%d
			WaitBetweenSpawns	10
			Squad
			{
				TFBot
				{
					Health	500
					Name	Soldier
					Class	Soldier
					Skill	Normal
					Item	"tf_weapon_rocketlauncher"
					Item	"tf_weapon_shotgun_soldier"
					Item	"tf_weapon_shovel"
				}
			}
		}
""" % (i + 1, 'WaitForAllDead	"Harbinger %d"' % i if i else '', HARBINGER_MONEY, 30 if i else 0)
		# And add the tank itself.
		info += """		WaveSpawn
		{
			Name	"Tank %d"
			WaitForAllDead	"Harbinger %d"
			TotalCurrency	%d
			TotalCount	1
			MaxActive	5
			SpawnCount	2
			Where	spawnbot
			WaitBeforeStarting	0
			WaitBetweenSpawns	30
			Squad
			{
				Tank
				{
					Health	40000
					Name	Tank
					Speed	75
					StartingPathTrackNode	boss_path_1
					OnKilledOutput
					{
						Target	boss_dead_relay
						Action	Trigger
					}
					OnBombDroppedOutput
					{
						Target	boss_deploy_relay
						Action	Trigger
					}
				}
			}
		}
""" % (i+1, i+1, TANK_MONEY)
		wave_money += HARBINGER_MONEY + TANK_MONEY
	for botclass in support:
		info += """		WaveSpawn
		{
			TotalCurrency	%d
			TotalCount	10
			MaxActive	5
			SpawnCount	2
			Where	spawnbot
			WaitBeforeStarting	0
			WaitBetweenSpawns	10
			Support	1
			Squad
			{
				TFBot
				{
					Template	%s
				}
			}
		}
""" % (SUPPORT_MONEY, botclass)
		wave_money += SUPPORT_MONEY
	# The maximum possible money after a wave includes a 100-credit bonus.
	global total_money; total_money += wave_money + 100
	print("Wave money:", wave_money, "+ 100 ==> cumulative", total_money)
	return info + "	}"

with open("mvm_coaltown.pop", "w") as pop:
	print("Starting money:", STARTING_MONEY)
	print(PREAMBLE % STARTING_MONEY, file=pop)
	print(make_wave(tanks=1, support=["T_TFBot_Scout_Fish"]), file=pop)
	print(make_wave(tanks=2, support=["T_TFBot_Heavy"]), file=pop)
	print(make_wave(tanks=3, support=["T_TFBot_Sniper", "T_TFBot_Demoman"]), file=pop)
	print(make_wave(tanks=5, support=["T_TFBot_Sniper_Huntsman", "T_TFBot_Pyro", "T_TFBot_Demoman_Knight"]), file=pop)
	print("}", file=pop)
	print("Total money after all waves:", total_money)
