# Generate MVM waves with harbingers and such
# The actual .pop file has tons of redundancy, which means editing it is tedious.

STARTING_MONEY = 1509 # I use a weird value here so that versioning becomes easy
WAVE_MONEY = 500 # Money from regular waves
HARBINGER_MONEY = 100 # Money from the harbingers in tank waves
TANK_MONEY = 500 # Money from the tanks themselves
SUPPORT_MONEY = 100 # Total money spread across all support bots of each type

# Don't know what of this would be different for different maps
PREAMBLE = """//This file was generated by gen_mvm_waves.py
#base robot_giant.pop
#base robot_standard.pop
#base robot_gatebot.pop
"""

_indentation = 0
def write(key, obj, autoclose=True):
	"""Write an object to the 'pop' file.

	If autoclose is True, will end the block cleanly, leaving us at the
	same indentation level we were previously at. Otherwise, the final
	closing brace will be omitted, allowing subsequent write() calls
	to continue the current object.
	"""
	if obj is None: return # Allow "sometimes there, sometimes not" entries in dicts/lists
	global _indentation
	indent = "\t" * _indentation
	if " " in key and not key.startswith('"'):
		# Keys and string values with spaces in them get quoted.
		key = '"' + key + '"'
	if isinstance(obj, dict):
		print(indent + key, file=pop)
		print(indent + "{", file=pop)
		_indentation += 1; indent += "\t"
		for k, v in obj.items():
			write(k, v)
		if autoclose:
			close(1)
	elif isinstance(obj, (list, tuple)):
		for val in obj:
			write(key, val)
	else:
		# Should normally be a string, integer, float, or similar
		# simple type.
		obj = str(obj)
		# If there's a space in the value, it gets quoted for safety.
		if " " in obj:
			obj = '"' + obj + '"'
		print(indent + key + "\t" + obj, file=pop)

def close(levels=1):
	"""Close one or more indentation levels in the 'pop' file

	Writes out as many close braces as specified, reducing the
	indentation level accordingly. If levels is Ellipsis, close
	*all* braces still open.
	"""
	global _indentation
	if levels is Ellipsis:
		levels = _indentation
	for _ in range(levels):
		_indentation -= 1
		print("\t" * _indentation + "}", file=pop)

MASTER = {
	"StartingCurrency": STARTING_MONEY,
	"RespawnWaveTime": 6,
	"CanBotsAttackWhileInSpawnRoom": "no",
	"Templates": {
		"Anorexic_Heavy": {
			"Health": 100,
			"Name": "Heavy",
			"Class": "HeavyWeapons",
			"Skill": "Normal",
			"WeaponRestrictions": "SecondaryOnly",
			"Item": ["tf_weapon_minigun", "tf_weapon_shotgun_hwg", "tf_weapon_fists"],
		},
		"T_TFBot_Heavy": {
			"Health": 300,
			"Name": "Heavy",
			"Class": "HeavyWeapons",
			"Skill": "Normal",
			"Item": ["tf_weapon_minigun", "tf_weapon_shotgun_hwg", "tf_weapon_fists"],
		},
		"BOSS_ReflectMe": {
			"Health": 250000,
			"Name": "Reflect Me",
			"Class": "Soldier",
			"Skill": "Normal",
			"WeaponRestrictions": "PrimaryOnly",
			"Attributes": ["AlwaysCrit", "MiniBoss"],
			"Item": ["the original", "tf_weapon_shotgun_soldier", "tf_weapon_shovel"],
			"CharacterAttributes": {
				"Projectile speed decreased": 0.75,
				"damage bonus": 10,
				"dmg falloff decreased": 1,
				"move speed penalty": 0.15,
				"airblast vulnerability multiplier": 0,
				"damage force reduction": 0,
				"cannot pick up intelligence": 1,
			}
		},
		"T_TFBot_Demoman_Boom": {
			"Health": 175,
			"Name": "Demoman",
			"Class": "Demoman",
			"Skill": "Normal",
			"Item": [
				"tf_weapon_grenadelauncher",
				"tf_weapon_pipebomblauncher",
				"the ullapool caber",
				"scotsman's stove pipe",
				"ttg glasses",
			],
			"CharacterAttributes": {
				"health regen": 5,
			}
		}
	}
}

total_money = STARTING_MONEY

class Wave:
	"""Singleton just to allow 'with wave:' constructs"""
	def __enter__(self):
		write("Wave", {
			"WaitWhenDone": 65,
			"Checkpoint": "Yes",
			"StartWaveOutput": {
				"Target": "wave_start_relay",
				"Action": "Trigger",
			},
			"DoneOutput": {
				"Target": "wave_finished_relay",
				"Action": "Trigger",
			}
		}, autoclose=False)
		self.money = self.subwaves = 0
	def __exit__(self, t, v, tb):
		close(1)
		# The maximum possible money after a wave includes a 100-credit bonus.
		global total_money; total_money += self.money + 100
		print("Wave money:", self.money, "+ 100 ==> cumulative", total_money)
wave = Wave()

def subwave(botclass, count, *, max_active=5, spawn_count=2, money=WAVE_MONEY, chain=False):
	wave.subwaves += 1
	write("WaveSpawn", {
		"Name": f"Subwave {wave.subwaves}",
		"WaitForAllSpawned": f"Subwave {wave.subwaves-1}" if chain else None,
		"TotalCurrency": money,
		"TotalCount": count,
		"MaxActive": max_active,
		"SpawnCount": spawn_count,
		"Where": "spawnbot",
		"WaitBeforeStarting": 0,
		"WaitBetweenSpawns": 10,
		"Squad": {"TFBot": {"Template": botclass}},
	})
	wave.money += money

def harby_tanks(count):
	# TODO: Make the names unique within a wave, such that calling
	# this function more than once results in parallel chains of
	# harbingers and tanks (muahahahahaha)
	for i in range(count):
		# Add the harbinger. The first one is a little bit different.
		write("WaveSpawn", {
			"Name": f"Harbinger {i + 1}",
			"WaitForAllDead": f"Harbinger {i}" if i else None,
			"TotalCurrency": HARBINGER_MONEY,
			"TotalCount": 1,
			"Where": "spawnbot",
			"WaitBeforeStarting": 30 if i else 0,
			"Squad": {"TFBot": {
				"Health": 500,
				"Name": "Soldier",
				"Class": "Soldier",
				"Skill": "Normal",
				"Item": ["tf_weapon_rocketlauncher", "tf_weapon_shotgun_soldier", "tf_weapon_shovel"],
			}},
		})
		# And add the tank itself.
		write("WaveSpawn", {
			"Name": f"Tank {i + 1}",
			"WaitForAllDead": f"Harbinger {i + 1}",
			"TotalCurrency": TANK_MONEY,
			"TotalCount": 1,
			"Where": "spawnbot",
			"WaitBeforeStarting": 0,
			"Squad": {"Tank": {
				"Health": 40000,
				"Name": "Tank",
				"Speed": 75,
				"StartingPathTrackNode": "boss_path_1",
				"OnKilledOutput": {
					"Target": "boss_dead_relay",
					"Action": "Trigger",
				},
				"OnBombDroppedOutput": {
					"Target": "boss_deploy_relay",
					"Action": "Trigger",
				}
			}},
		})
		wave.money += HARBINGER_MONEY + TANK_MONEY

def support(*botclasses, max_active=5, spawn_count=2):
	for botclass in botclasses:
		write("WaveSpawn", {
			"TotalCurrency": SUPPORT_MONEY,
			"TotalCount": 10, # With support waves, I think this controls the money drops
			"MaxActive": max_active,
			"SpawnCount": spawn_count,
			"Where": "spawnbot",
			"WaitBeforeStarting": 0,
			"WaitBetweenSpawns": 10,
			"Support": 1,
			"Squad": {"TFBot": {"Template": botclass}},
		})
		wave.money += SUPPORT_MONEY

with open("mvm_coaltown.pop", "w") as pop:
	print("Starting money:", STARTING_MONEY)
	print(PREAMBLE, file=pop)
	write("population", MASTER, autoclose=False)
	with wave:
		subwave("T_TFBot_Scout_Fish", 10, money=100)
		subwave("Anorexic_Heavy", 25, money=250, chain=True)
		subwave("T_TFBot_Demoman", 15, money=150)
		subwave("T_TFBot_Pyro", 5, money=50, chain=True)
	with wave:
		harby_tanks(1)
		support("T_TFBot_Scout_Scattergun_SlowFire")
	with wave:
		harby_tanks(2)
		subwave("T_TFBot_Demoman", 10)
		support("T_TFBot_Heavy", "T_TFBot_Sniper")
	with wave:
		harby_tanks(3)
		subwave("T_TFBot_Pyro", 20, max_active=10, spawn_count=4)
		subwave("T_TFBot_Medic", 10)
		support("T_TFBot_Scout_Fish")
	with wave:
		harby_tanks(5)
		subwave("T_TFBot_Sniper", 25, max_active=10, spawn_count=5)
		support("T_TFBot_Heavyweapons_Fist", "T_TFBot_Demoman_Boom")
	with wave:
		subwave("BOSS_ReflectMe", 1)
		subwave("T_TFBot_Demoman_Knight", 50, max_active=10, spawn_count=5)
		support("T_TFBot_Sniper_Huntsman", "T_TFBot_Pyro", spawn_count=1)
	close(...)
	print("Total money after all waves:", total_money)
