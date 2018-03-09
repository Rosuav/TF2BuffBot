# Generate MVM waves with harbingers and such
# The actual .pop file has tons of redundancy, which means editing it is tedious.
from itertools import cycle

# Global defaults - can be overridden per popfile, and provide the
# defaults for waves and subwaves.
DEFAULTS = {
	"tank_health": 40000,
	"tank_speed": 75,
	"money_factor": 1.0, # Quick-and-dirty way to experiment with scaling the wave money
	"wave_money": 25, # Money for bots from regular waves
	"harby_money": 50, # Money from the harbingers in tank waves
	"tank_money": 500, # Money from the tanks themselves
	"support_money": 10, # Money for the first N support bots
}

TEMPLATES = {
	"Anorexic_Heavy": {
		"Health": 100,
		"Name": "Heavy",
		"Class": "HeavyWeapons",
		"Skill": "Normal",
		"WeaponRestrictions": "SecondaryOnly",
		"Item": ["tf_weapon_minigun", "tf_weapon_shotgun_hwg", "tf_weapon_fists"],
	},
	"Stroller": {
		"Health": 100,
		"Name": "Heavy",
		"Class": "HeavyWeapons",
		"Skill": "Normal",
		"WeaponRestrictions": "MeleeOnly",
		"Item": ["the holiday punch"],
		"CharacterAttributes": {
			"move speed penalty": 0.20,
		},
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
	"Tomislav_Heavy": {
		"Health": 300,
		"Name": "Heavy",
		"Class": "HeavyWeapons",
		"Skill": "Normal",
		"Item": ["tomislav", "tf_weapon_shotgun_hwg", "tf_weapon_fists"],
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
			"Projectile speed decreased": 0.40, # Decreased to this proportion of normal speed (so 0.75 == 25% decreased)
			"damage bonus": 10,
			"dmg falloff decreased": 1,
			"move speed penalty": 0.20,
			"airblast vulnerability multiplier": 0,
			"damage force reduction": 0,
			"cannot pick up intelligence": 1,
			"mod shovel speed boost": 1, # Give him the Escape Plan effect of increased speed as health decreases
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
		bonus = ""
		if self.money:
			# The maximum possible money after a wave includes a 100-credit bonus.
			# This bonus is NOT given if no money was picked up, though.
			pop.total_money += self.money + 100
			bonus = "+ 100 "
		print("Wave money:", self.money, bonus + "==> cumulative", pop.total_money)
wave = Wave()

def subwave(botclass, count, *, max_active=5, spawn_count=2, money=None, chain=False, delay=0):
	if money is None: money = pop.wave_money
	wave.subwaves += 1
	pop.write("WaveSpawn", {
		"Name": f"Subwave {wave.subwaves}",
		"WaitForAllSpawned": f"Subwave {wave.subwaves-1}" if chain else None,
		"TotalCurrency": pop.money(money * count),
		"TotalCount": count,
		"MaxActive": max_active,
		"SpawnCount": spawn_count,
		"Where": "spawnbot",
		"WaitBeforeStarting": delay,
		"WaitBetweenSpawns": 10,
		"Squad": {"TFBot": {"Template": botclass}},
	})
	wave.money += pop.money(money * count)

def harby_tanks(count, harby_money=None, tank_money=None, delay=30):
	# NOTE: Calling this function twice within a wave will result in
	# parallel streams of harbies and tanks. This can be extremely
	# confusing and should usually be avoided.

	# Note: For game balance purposes, it's best that the tank take
	# about two minutes from breaking the barrier to destroying the
	# facility. If it's faster than that, consider either reducing
	# the tank speed or lowering its health.
	wave.subwaves += 1
	harby_money = pop.money(harby_money or pop.harby_money)
	tank_money = pop.money(tank_money or pop.tank_money)
	for i in range(count):
		# Add the harbinger. The first one is a little bit different.
		pop.write("WaveSpawn", {
			"Name": f"Harbinger {wave.subwaves}-{i + 1}",
			"WaitForAllDead": f"Harbinger {wave.subwaves}-{i}" if i else None,
			"TotalCurrency": harby_money,
			"TotalCount": 1,
			"Where": "spawnbot",
			"WaitBeforeStarting": delay if i else wave.subwaves * 15,
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
			"Name": f"Tank {wave.subwaves}-{i + 1}",
			"WaitForAllDead": f"Harbinger {wave.subwaves}-{i + 1}",
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

def support(*botclasses, money=None, count=25, max_active=5, spawn_count=2):
	if money is None: money = pop.support_money
	for botclass in botclasses:
		pop.write("WaveSpawn", {
			"TotalCurrency": pop.money(money * count),
			"TotalCount": count, # With support waves, this controls how many drop money
			"MaxActive": max_active,
			"SpawnCount": spawn_count,
			"Where": "spawnbot",
			"WaitBeforeStarting": 0,
			"WaitBetweenSpawns": 10,
			"Support": 1,
			"Squad": {"TFBot": {"Template": botclass}},
		})
		wave.money += pop.money(money * count)

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
		self.__dict__.update(DEFAULTS)
		self.__dict__.update(kw)
		paths = self.TANK_PATHS.get(fn)
		self.tank_path = cycle(paths) if paths else self

	def __next__(self):
		"""Abuse self as a raising non-iterable"""
		raise ValueError("No tank paths on %s, cannot spawn tanks" % self.fn)

	def money(self, amount):
		return int(amount * self.money_factor + 0.5)

	def __enter__(self):
		self.file = open(self.fn, "w")
		print("Building:", self.fn)
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
with PopFile("mvm_coaltown.pop", starting_money=1511, tank_health=25000) as pop:
	with wave:
		subwave("T_TFBot_Scout_Fish", 10, money=15)
		subwave("Anorexic_Heavy", 20, money=15, chain=True)
		subwave("T_TFBot_Demoman", 15, money=15)
		subwave("T_TFBot_Pyro", 5, money=15, chain=True)
	with wave:
		harby_tanks(1)
		support("T_TFBot_Scout_Scattergun_SlowFire", count=20)
	with wave:
		harby_tanks(2)
		subwave("T_TFBot_Demoman", 10)
		subwave("Tomislav_Heavy", 20, max_active=2)
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

with PopFile("mvm_decoy.pop", starting_money=1502, tank_speed=50, harby_money=25, tank_money=250, support_money=5) as pop:
	with wave:
		subwave("Milkman", 100, max_active=50, spawn_count=10, money=2)
		subwave("Anorexic_Heavy", 10, money=15)
	with wave:
		harby_tanks(1)
		subwave("T_TFBot_Heavy", 5, max_active=1, spawn_count=1, money=15)
		support("T_TFBot_Sniper_Huntsman", count=25)
	with wave:
		harby_tanks(1)
		subwave("T_TFBot_Demoman", 25, money=10)
		subwave("T_TFBot_Demoman_Knight", 25, money=10)
		support("T_TFBot_Scout_Fish")
	with wave:
		harby_tanks(3)
		support("Milkman")
	with wave:
		harby_tanks(4)
		subwave("T_TFBot_Pyro", 15, money=15)
		support("Anorexic_Heavy")
	with wave:
		harby_tanks(6)
		support("T_TFBot_Scout_Fish", "T_TFBot_Pyro")
	with wave:
		subwave("T_TFBot_Heavy", 50, money=15)
		subwave("Milkman", 50, money=5)
	with wave:
		harby_tanks(3)
		harby_tanks(5)
		support("T_TFBot_Sniper_Huntsman")
	with wave:
		for i in range(5):
			subwave("T_TFBot_Demoman", 10, money=10, chain=(i>0))
			subwave("T_TFBot_Demoman_Knight", 10, money=10, chain=True)
		support("Anorexic_Heavy")
	with wave:
		harby_tanks(3)
		harby_tanks(3)
		harby_tanks(4)
		support("Milkman", count=5)

# TODO: Give practically all the money up-front, and basically nothing
# in each wave. You have been hired, mercs, to defend this facility.
# Your pay has been given in advance. Now defend this place to the pain!

# Balance note: Every second tank (across waves) is running on a slightly
# longer track (about 30-40% longer than the other tanks follow). Running
# the numbers suggests that 30K health is right for the short path, and
# 40K for the long path. We split the difference on 2**15-1. Because.

# Wave progression: Start with an easy wave (warmup), but then get harder
# fairly rapidly. Plateau by about wave 3-4 and keep the waves roughly at
# the same difficulty, and then have a "boss fight" at the end, either as
# a single really tough challenge (a tank, or a ReflectMe), or as a long
# grind with a ton of mooks and no respite.
with PopFile("mvm_mannworks.pop", starting_money=5002, harby_money=0, tank_health=32767, tank_money=0, wave_money=0, support_money=0) as pop:
	with wave:
		subwave("T_TFBot_Scout_Fish", 20)
		subwave("T_TFBot_Pyro", 10)
	with wave:
		subwave("T_TFBot_Demoman", 25)
		subwave("T_TFBot_Scout_Scattergun_SlowFire", 20)
		subwave("T_TFBot_Heavy", 5, max_active=1, spawn_count=1)
	with wave:
		harby_tanks(1)
		subwave("T_TFBot_Pyro_Flaregun", 20)
		subwave("T_TFBot_Demoman_Boom", 25)
		support("T_TFBot_Pyro")
	with wave:
		harby_tanks(2)
		support("T_TFBot_Demoman_Knight")
	with wave:
		subwave("Anorexic_Heavy", 20)
		subwave("T_TFBot_Heavy", 20)
		support("T_TFBot_Sniper_Huntsman")
	with wave:
		harby_tanks(1)
		subwave("Anorexic_Heavy", 10)
		for _ in range(3):
			subwave("T_TFBot_Pyro_Flaregun", 5, chain=True)
			subwave("T_TFBot_Pyro", 5, chain=True)
		subwave("Anorexic_Heavy", 10, chain=True)
		support("T_TFBot_Scout_Fish")
	with wave: # Boss fight!
		# Yes, that's right. Eight tanks... but none but harbies to carry the bomb.
		for _ in range(2): harby_tanks(4, delay=100)
		# Bonus: a bit of Air Strike fodder to start things off. Helps if the
		# wave has to be restarted.
		subwave("Milkman", 10, max_active=10, spawn_count=10)
