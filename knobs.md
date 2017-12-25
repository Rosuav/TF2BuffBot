Tweakables in the Buff Bot
==========================

There's a lot you can mess around with. Most of it is in cvars for conveninence
and run-time tweakability. Everything has sane defaults, so it's perfectly
reasonable to take the buff bot for a spin without changing any of these.

* sm_ccc_carnage_initial: 0 normally, but you can have players start with
  some carnage points. Setting this to the same as sm_ccc_carnage_required
  will allow players one free roulette spin on joining, and any time teams are
  reorganized. (Including if a player simply chooses to change team.) Best to
  keep this at zero generally.
* sm_ccc_carnage_per_{kill, assist, solo_kill}: By default, these are the
  same as the score gained (two for a kill whether assisted or not, and one for
  an assist); a viable tweak would be for a solo kill to claim all three points
  as if you were both the killer and assister.
* sm_ccc_carnage_per_death: 3 by default, but could easily be higher or
  lower. Setting this equal to carnage_required guarantees a roulette spin any
  time you die. Having this higher than the kill score compensates some for the
  time spent respawning. Note that suicide doesn't grant any score, but getting
  finished off does (and also grants the killer points, of course).
* sm_ccc_carnage_per_{building, sentry}: Taking down an engineer's building
  or a spy's sapper counts as a little kill. Taking down a sentry gun counts as
  a full player kill (2 points). Equally viable options: guns count as kills,
  but others don't (carnage_per_building 0); or all buildings score equally
  (carnage_per_sentry 1).
* sm_ccc_carnage_per_ubercharge: Normally zero, and best to keep it that
  way, but if you really feel the need to reward a Medic for doing his job, set
  this to maybe 1 at most. Bear in mind that a medic should be scoring assists,
  so a well-timed Uber should result in a decent carnage score for the Medic.
  During setup time, a Medic can build and discharge Uber more than once, thus
  cranking up carnage points somewhat unfairly.
* sm_ccc_carnage_per_upgrade: Also normally zero, and definitely best to
  keep it disabled. The same concerns about ubercharge apply here too, plus the
  extra problem that, even _after_ setup time, an engineer can easily build his
  buildings in useless places. If this is set to any value at all, it should be
  extremely low, and since all values are integers, that means every other
  score needs to be increased to compensate.
* sm_ccc_carnage_required: 10 normally, and sets the overall scale of the
  numbers. Every value above can be viewed as a fraction of this (for instance,
  a kill is 20% of the requirement, and a death is 30%), so if you need finer
  grained control, increase this (eg to 100) and then increase everything else
  accordingly (perhaps set kills to 20, but deaths to 33). NOT RECOMMENDED:
  Setting this to zero will allow everyone to just spam !roulette to their
  hearts' content, making the entire carnage system immaterial, and negating
  several of the deleterious effects (doesn't mean much to be marked for death
  if you have ubercharge, for example).
* sm_ccc_buff_duration: 30 seconds by default. Whatever buff or debuff you
  get, it lasts this long. Effects can be terminated prematurely, often by
  touching a resupply locker; some effects have their own cutoffs too (eg
  invisibility, which ends immediately upon attacking).
* sm_ccc_crits_on_domination: 5 seconds by default. Be aware that, despite this
  cvar's name, not everyone gets crits; some classes get mini-crits for twice
  this duration, or other buffs. See the source code for details. Don't set
  this to high, or dominations will simply cascade, letting one team utterly
  crush and, well, dominate.

Note that using !roulette or !gift will always consume ALL of your carnage
points (unless you don't have enough). Having triple the required points does
not allow you to give three gifts, so just pop it whenever you think it'll be
useful.

When you spin the roulette wheel, you could get something good or something
bad. Within each category, a selection of effects will be picked from with
uniform probability, but the categories themselves are tweakable:

* sm_ccc_roulette_chance_good: 64 by default - chance of something good.
* sm_ccc_roulette_chance_bad: 30 by default - chance of something bad.
* sm_ccc_roulette_chance_weird: 5 by default - chance of something odd.

Gift-giving has its own set of knobs. Instead of having some chance of a good
result and some chance of bad, the gift is guaranteed to be good, but might go
to your opponents. Every player who's alive and in the game is given a certain
number of raffle tickets, and the winning ticket grants the buff. How many
tickets? That depends on whether you're friendly or not, and whether you're a
human or not. (Don't worry, we don't make you do a CAPTCHA.)

* sm_ccc_gift_chance_friendly_human defaults to 20
* sm_ccc_gift_chance_friendly_bot defaults to 2
* sm_ccc_gift_chance_enemy_human defaults to 10
* sm_ccc_gift_chance_enemy_bot defaults to 1

On servers with huge bot counts (eg two humans and thirty bots), the human
scores may need to be increased; on servers where bots just pad out the numbers
when there are imbalanced humans, the human/bot discrepancy could be reduced.
Keeping the friendly/enemy ratio at about two to one is recommended; it should
be approximately the same as the good/bad ratio on the roulette wheel.

Further tweakables that are not easy to make into cvars:

* Variable buff durations (eg you get 10 secs of Uber, but 25 of Crit-A-Cola)
* The set of buffs distributed
* Buff incompatibilities (eg "if you have 100% Crits, don't drink Crit-A-Cola")
