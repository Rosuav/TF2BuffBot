# tail -n +0 -f steamcmd_linux/csgo/csgo/weapon_scores.log | python3 weapon_scores.py
# TODO: Reimplement fast tail in Python and just take the file name as arg
import collections
import itertools
import os
import re
import shutil

scores = collections.Counter()
total_score = 0

def show_scores():
	sz = shutil.get_terminal_size()
	n = sz.lines - 2
	sc = scores.most_common()
	winners = [s for s in sc[:n] if s[1] > 0]
	losers = [s for s in sc[-n:] if s[1] < 0]
	width = sz.columns // 2
	print("%-*s %s" % (width, "Top %d winners" % n, "Worst %d losers" % n))
	for idx, (winner, winsc), (loser, losesc) in itertools.zip_longest(range(n), winners, losers, fillvalue=("", "")):
		if winner: winner = "[%2.2f%%] %s" % (winsc / total_score * 100, winner)
		if loser: loser = "[%2.2f%%] %s" % (-losesc / total_score * 100, loser)
		print("%-*s %s" % (width, winner, loser))

while "moar data":
	line = input()
	# Zero-sum game: every point gained in one place is lost somewhere else
	m = re.match("^(.+) (|team|self)damaged (.+) for ([0-9]+) \(([0-9]+)hp\)$", line)
	if not m: continue
	killer, mode, victim, score, hp = m.groups()
	# TODO: Score team damage and self damage differently from normal damage-to-enemies
	score = int(score)
	total_score += score
	scores[killer] += score
	scores[victim] -= score
	show_scores()
