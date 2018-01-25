# Generate MVM waves with harbingers and such
# The actual .pop file has tons of redundancy, which means editing it is tedious.
from itertools import cycle

# Default amounts of money per enemy (can be changed per-wave)
WAVE_MONEY = 25 # Money for bots from regular waves
HARBINGER_MONEY = 50 # Money from the harbingers in tank waves
TANK_MONEY = 500 # Money from the tanks themselves
SUPPORT_MONEY = 10 # Money for the first N support bots

TEMPLATES = {
	"Anorexic_Heavy": {
		"Health": 100,
		"Name": "Heavy",
		"Class": "HeavyWeapons",
		"Skill": "Normal",
		"WeaponRestrictions": "SecondaryOnly",
		"Item": ["tf_weapon_minigun", "tf_weapon_shotgun_hwg", "tf_weapon_fists"],
	},
	"Milkman": {
		"Health": 25,
		"Name": "Scout",
		"Class": "Scout",
		"Skill": "Normal",
		"WeaponRestrictions": "SecondaryOnly",
		"Item": ["the shortstop", "mad milk", "the holy mackerel", "the milkman", "osx item"],
	},
	"T_TFBot_Heavy": {
		"Health": 300,
		"Name": "Heavy",
		"Class": "HeavyWeapons",
		"Skill": "Normal",
		"Item": ["tf_weapon_minigun", "tf_weapon_shotgun_hwg", "tf_weapon_fists"],
	},
	"BOSS_ReflectMe_Coaltown": {
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

class Wave:
	"""Singleton just to allow 'with wave:' constructs"""
	def __enter__(self):
		pop.write("Wave", {
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
		pop.closeblock()
		# The maximum possible money after a wave includes a 100-credit bonus.
		pop.total_money += self.money + 100
		print("Wave money:", self.money, "+ 100 ==> cumulative", pop.total_money)
wave = Wave()

def subwave(botclass, count, *, max_active=5, spawn_count=2, money=WAVE_MONEY, chain=False, delay=0):
	wave.subwaves += 1
	pop.write("WaveSpawn", {
		"Name": f"Subwave {wave.subwaves}",
		"WaitForAllSpawned": f"Subwave {wave.subwaves-1}" if chain else None,
		"TotalCurrency": money * count,
		"TotalCount": count,
		"MaxActive": max_active,
		"SpawnCount": spawn_count,
		"Where": "spawnbot",
		"WaitBeforeStarting": delay,
		"WaitBetweenSpawns": 10,
		"Squad": {"TFBot": {"Template": botclass}},
	})
	wave.money += money * count

def harby_tanks(count, harby_money=HARBINGER_MONEY, tank_money=TANK_MONEY):
	# NOTE: Calling this function twice within a wave will result in duplicate
	# harby/tank subwave names, with confusing results (it'll wait for BOTH
	# harbingers to die before sending BOTH tanks, for instance). It'd be very
	# confusing to have parallel chains of harbies and tanks anyway, so just
	# don't do this. It'd be poor UX. :)
	for i in range(count):
		# Add the harbinger. The first one is a little bit different.
		pop.write("WaveSpawn", {
			"Name": f"Harbinger {i + 1}",
			"WaitForAllDead": f"Harbinger {i}" if i else None,
			"TotalCurrency": harby_money,
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
		pop.write("WaveSpawn", {
			"Name": f"Tank {i + 1}",
			"WaitForAllDead": f"Harbinger {i + 1}",
			"TotalCurrency": tank_money,
			"TotalCount": 1,
			"Where": "spawnbot",
			"WaitBeforeStarting": 0,
			"Squad": {"Tank": {
				"Health": pop.tank_health,
				"Name": "Tank",
				"Speed": pop.tank_speed,
				"StartingPathTrackNode": next(pop.tank_path),
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
		wave.money += harby_money + tank_money

def support(*botclasses, money=SUPPORT_MONEY, count=10, max_active=5, spawn_count=2):
	for botclass in botclasses:
		pop.write("WaveSpawn", {
			"TotalCurrency": money * count,
			"TotalCount": count, # With support waves, this controls how many drop money
			"MaxActive": max_active,
			"SpawnCount": spawn_count,
			"Where": "spawnbot",
			"WaitBeforeStarting": 0,
			"WaitBetweenSpawns": 10,
			"Support": 1,
			"Squad": {"TFBot": {"Template": botclass}},
		})
		wave.money += money * count

class PopFile:
	"""Context manager to create an entire .pop file"""

	# The possible tank paths were found from old.mvm.tf, and presumably come
	# from the map details. If a map is not listed here, tanks will not be
	# spawned on that map; for instance, on mvm_mannhattan, attempting to
	# create a tank will make the wave unwinnable, as the tank appears and
	# instantly goes into its victory sequence (without a hole for the bomb).
	TANK_PATHS = {
		"mvm_coaltown.pop": ["boss_path_1"],
		"mvm_coaltown_event.pop": ["boss_path_1"],
		"mvm_decoy.pop": ["boss_path_1"],
		"mvm_mannworks.pop": ["boss_path_1", "boss_path2_1"],
		"mvm_bigrock.pop": ["boss_path_1", "boss_path_a1"],
		"mvm_skullcave.pop": ["tank_path_left", "tank_path_right"],
	}

	def __init__(self, fn, **kw):
		self.fn = fn
		self.tank_health = 40000
		self.tank_speed = 75
		self.__dict__.update(kw)
		paths = self.TANK_PATHS.get(fn)
		self.tank_path = cycle(paths) if paths else self

	def __next__(self):
		"""Abuse self as a raising non-iterable"""
		raise ValueError("No tank paths on %s, cannot spawn tanks" % self.fn)

	def __enter__(self):
		self.file = open(self.fn, "w")
		print("Starting:", self.fn)
		print("Starting money:", self.starting_money)
		print("""//This file was generated by gen_mvm_waves.py
#base robot_giant.pop
#base robot_standard.pop
#base robot_gatebot.pop
""", file=self.file)
		self.total_money = self.starting_money
		self.indentation = 0
		self.write("population", {
			"StartingCurrency": self.starting_money,
			"RespawnWaveTime": 6,
			"CanBotsAttackWhileInSpawnRoom": "no",
			"Templates": TEMPLATES,
		}, autoclose=False)
		return self

	def __exit__(self, t, v, tb):
		while self.indentation:
			self.closeblock()
		print("Total money after all waves:", self.total_money)
		self.file.close()
		self.file = None
		print("Completing:", self.fn)

	def write(self, key, obj, autoclose=True):
		"""Write an object to the 'pop' file.

		If autoclose is True, will end the block cleanly, leaving us at the
		same indentation level we were previously at. Otherwise, the final
		closing brace will be omitted, allowing subsequent write() calls
		to continue the current object.
		"""
		if obj is None: return # Allow "sometimes there, sometimes not" entries in dicts/lists
		indent = "\t" * self.indentation
		if " " in key and not key.startswith('"'):
			# Keys and string values with spaces in them get quoted.
			key = '"' + key + '"'
		if isinstance(obj, dict):
			print(indent + key, file=self.file)
			print(indent + "{", file=self.file)
			self.indentation += 1
			for k, v in obj.items():
				self.write(k, v)
			if autoclose:
				self.closeblock()
		elif isinstance(obj, (list, tuple)):
			for val in obj:
				self.write(key, val)
		else:
			# Should normally be a string, integer, float, or similar
			# simple type.
			obj = str(obj)
			# If there's a space in the value, it gets quoted for safety.
			if " " in obj:
				obj = '"' + obj + '"'
			print(indent + key + "\t" + obj, file=self.file)

	def closeblock(self):
		"""Close an object that was written with autoclose=False"""
		self.indentation -= 1
		print("\t" * self.indentation + "}", file=self.file)

# The starting money also functions as a sort of version number
with PopFile("mvm_coaltown.pop", starting_money=1511) as pop:
	with wave:
		subwave("T_TFBot_Scout_Fish", 10, money=10)
		subwave("Anorexic_Heavy", 20, money=10, chain=True)
		subwave("T_TFBot_Demoman", 15, money=10)
		subwave("T_TFBot_Pyro", 5, money=10, chain=True)
	with wave:
		harby_tanks(1)
		support("T_TFBot_Scout_Scattergun_SlowFire", count=20)
	with wave:
		harby_tanks(2)
		subwave("T_TFBot_Demoman", 10)
		subwave("T_TFBot_Heavy", 20, max_active=3)
		support("T_TFBot_Sniper")
	with wave:
		harby_tanks(3)
		subwave("T_TFBot_Pyro", 20, max_active=10, spawn_count=4)
		subwave("T_TFBot_Medic", 10)
		support("T_TFBot_Scout_Fish")
	with wave:
		harby_tanks(5)
		subwave("T_TFBot_Sniper", 25, money=20, max_active=10, spawn_count=5)
		support("T_TFBot_Heavyweapons_Fist", "T_TFBot_Demoman_Boom")
	with wave:
		# The big fat boss should never take the bomb, but it's possible for
		# him to START with it. However, if he waits a few seconds before
		# spawning, someone else should take the bomb.
		subwave("BOSS_ReflectMe_Coaltown", 1, delay=5)
		subwave("T_TFBot_Demoman_Knight", 50, max_active=10, spawn_count=5)
		support("T_TFBot_Sniper_Huntsman", "T_TFBot_Pyro_Flaregun")

with PopFile("mvm_decoy.pop", starting_money=1501, tank_speed=50) as pop:
	# TODO: Back down the money across the board. With ten waves,
	# we need slower progression.
	with wave:
		subwave("Milkman", 100, max_active=50, spawn_count=10, money=5)
		subwave("Anorexic_Heavy", 10)
	with wave:
		subwave("T_TFBot_Heavy", 5, max_active=1, spawn_count=1)
		harby_tanks(1)
		support("T_TFBot_Sniper_Huntsman", count=25)
	with wave:
		subwave("T_TFBot_Demoman", 25)
		subwave("T_TFBot_Demoman_Knight", 25)
		harby_tanks(1)
		support("T_TFBot_Scout_Fish")
	with wave:
		harby_tanks(3)
		support("Milkman")
	with wave:
		subwave("T_TFBot_Pyro", 15)
		harby_tanks(4)
		support("Anorexic_Heavy")
	with wave:
		harby_tanks(6)
		support("T_TFBot_Scout_Fish", "T_TFBot_Pyro")
	with wave:
		subwave("T_TFBot_Heavy", 50)
		subwave("Milkman", 50)
	with wave:
		harby_tanks(8)
		support("T_TFBot_Sniper_Huntsman")
	with wave:
		subwave("T_TFBot_Demoman", 10)
		subwave("T_TFBot_Demoman_Knight", 10, chain=True)
		subwave("T_TFBot_Demoman", 10, chain=True)
		subwave("T_TFBot_Demoman_Knight", 10, chain=True)
		subwave("T_TFBot_Demoman", 10, chain=True)
		subwave("T_TFBot_Demoman_Knight", 10, chain=True)
		subwave("T_TFBot_Demoman", 10, chain=True)
		subwave("T_TFBot_Demoman_Knight", 10, chain=True)
		subwave("T_TFBot_Demoman", 10, chain=True)
		subwave("T_TFBot_Demoman_Knight", 10, chain=True)
		support("Anorexic_Heavy")
	with wave:
		harby_tanks(10)
		support("Milkman", count=5)
