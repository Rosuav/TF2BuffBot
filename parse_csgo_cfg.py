# NOTE: For stable output, this should be run on a Python version that
# guarantees dict order (3.7+).
import re
import os.path
from pprint import pprint

fn = os.path.expanduser("~/tf2server/steamcmd_linux/csgo/csgo/scripts/items/items_game.txt")

# In a Source config file (does the format have a name?), data consists
# of alternating keys and values. Keys are always strings; values are
# either strings or mappings. A string starts with a double quote, ends
# with a double quote, and... what happens if it contains one? TODO.
# A mapping starts with an open brace, contains one or more (TODO: can
# it contain zero?) key+value pairs, and ends with an open brace.
# Between any two values, any amount of whitespace is found, possibly
# including comments, which start with "//" and end at EOL.

# Skip whitespace and comments
RE_SKIP = re.compile(r'(\s*//[^\n]*\n)*\s*')
# Read a single string
RE_STRING = re.compile(r'"([^"\n]*)"')

def merge_mappings(m1, m2, path):
	"""Recursively merge the contents of m2 into m1"""
	if type(m1) is not type(m2): raise ValueError("Cannot merge %s and %s" % (type(m1), type(m2)))
	if type(m1) is str:
		if m1 == m2: return m1 # Attempting to merge "foo" into "foo" just produces "foo"
		# Actually.... the Valve-provided files have dirty data in them.
		# We can't make assertions like this. Sigh.
		# raise ValueError("Cannot merge different strings %r and %r --> %s" % (m1, m2, path))
		return m1 # Keep the one from m1... I think??
	for k,v in m2.items():
		if k in m1: merge_mappings(m1[k], v, path + "." + k)
		else: m1[k] = v

def parse_cfg(data):
	pos = 0
	def skip_ws():
		nonlocal pos
		pos = RE_SKIP.match(data, pos).end()
	def parse_str():
		nonlocal pos
		m = RE_STRING.match(data, pos)
		if not m: raise ValueError("Unable to parse string at pos %d" % pos)
		pos = m.end()
		return m.group(1)
	def parse_mapping(path):
		nonlocal pos
		pos += 1 # Skip the initial open brace
		ret = {}
		while "moar stuffo":
			skip_ws()
			if data[pos] == '}': break
			key = parse_str()
			value = parse_value(path + "." + key)
			if key in ret:
				# Sometimes there are duplicates. I don't know what the deal is.
				merge_mappings(value, ret[key], path + "." + key)
			ret[key] = value
		pos += 1 # Skip the final close brace
		return ret
	def parse_value(path):
		skip_ws()
		if data[pos] == '"': return parse_str()
		if data[pos] == '{': return parse_mapping(path)
		raise ValueError("Unexpected glyph '%s' at pos %d" % (data[pos], pos))
	skip_ws()
	assert data[pos] == '"' # The file should always start with a string
	title = parse_str()
	print("GOT TITLE:", title)
	return parse_value(title)

with open(fn) as f: data = f.read()
info = parse_cfg(data)

for weapon, data in info["prefabs"].items():
	if "item_class" not in data or "attributes" not in data: continue
	# This is a sneaky way to restrict it to just "normal weapons", since
	# you can't apply a sticker to your fists or your tablet :)
	if "stickers" not in data: continue
	print(weapon.replace("_prefab", "") + ":") # NOTE: This isn't always the same as the weapon_class (cf CZ75a).
	for attr, dflt in {
		"primary clip size": "-1",
		"primary reserve ammo max": "-1",
		"is full auto": "0",
		"max player speed": "260",
		"in game price": "-1",
		"kill award": "300",
		"bullets": "1", # Shotguns have this >1
	}.items():
		print("\t%s => %s" % (attr, data["attributes"].get(attr, dflt)))
	print("\tarmor penetration => %.2f" % (float(data["attributes"]["armor ratio"]) * 50))
# pprint(list(info["prefabs"]))
