# Dr Zed: I maintain the med vendors

This plugin is intended for use with Counter-Strike: Global Offensive. It adds
a number of new features, mostly controlled by cvars, and also makes a few
quality-of-life tweaks eg to the behaviour of bots.

These game features can be mixed and matched in a variety of ways to create new
gameplay modes. Some such game modes are [documented by example](gamemodes.md),
and for the rest, the limit is your own imagination! Of course, not everything
has been tested with everything else, but have fun, go wild!

## Major features

### Healing

As the plugin's name suggests, the first large feature added was the ability
to purchase healing. You must still be alive for this to work, and it has a
monetary cost. Healing restores your hitpoints but not your armor; depending
on the game mode, you may be able to immediately rebuy armor in the normal
way.

* sm_drzed_heal_max: set to 100 to permit healing up to full health, or to
  50 to allow only half healing, or even to 200 to allow people to buy
  overheal.
* sm_drzed_heal_price: How many dollars it should cost (eg 1000) to heal.
  This is not in any way scaled - it always costs exactly this much to heal
  to the given maximum.
* sm_drzed_heal_freq_flyer: Every time you heal up, your maximum health is
  increased by this much. Not recommended in classic modes (casual/compet),
  but can work well in (eg) Arms Race.
* sm_drzed_heal_cooldown: If you have an abundance of money and a lack of
  health, you could heal-spam while under fire and be indestructible. To
  prevent this, healing has a short cooldown.

### Health gating

Sometimes, it just feels bad to get one-tapped. Maybe that shouldn't happen.
Configuring a health gate will give you a second chance - you're critically
low on health, but still alive. Of course, getting AWPed in the head is
still going to smash you to pieces...

* sm_drzed_gate_health_left: How much health you should be left on (eg 10)
* sm_drzed_gate_overkill: A single hit of at least this much will crash right
  through the health gate.

### Altered max hitpoints

Easy way to adjust the overall time-to-kill. Simple in effect, but can have
extremely far-reaching impact on game balance. Adjusting health by 5% in
either direction will have a notable effect on which weapons can one-tap,
and may change whether it takes five shots or six (three? seven? go take a
shower, Harry) to kill. Larger adjustments (setting health to 200) will
drastically change which weapons are viable at which ranges.

* sm_drzed_max_hitpoints: Number of hitpoints everyone gets. There's no way
  to set different values for different teams or anything.
* sm_drzed_suit_health_bonus: Additional health if you have the Heavy Assault
  Suit, which normally isn't available (but can be enabled with Valve's own
  cvars - see mp_weapons_allow_heavyassaultsuit and its friends).

### Crippled before killed

In some games, when you get dropped, you can be revived for a short period of
time before you become "dead-dead". While crippled, you cannot use guns, nor
plant or defuse the bomb. Successfully landing a knife blow on an enemy will
instantly revive you (this MAY change in the future, eg require you to drop
an opponent completely), and your teammates can revive you with their knives.

When the round ends, everyone on the winning team instantly revives, and
everyone on the losing team is instantly slain. Dropping someone during the
round-end period (exit fragging) instantly kills without cripping.

Note that this game mode is incompatible with the normal use of the heavy
assault suit, as it uses the suit to control crippled players.

* sm_drzed_crippled_health: How many hitpoints you get while crippled
* sm_drzed_crippled_revive_count: How many knife-slashes it takes to revive a
  teammate. Don't set this to 0; the behaviour if this is 0 may change in the
  future.

## Minor features

### Give everyone money

Console command: zed_money

Tada, everyone has $1000 more than they had before. That's not enough? Run it
again. Easy. Applies to all players, both teams. Use it before a round starts
if you want the bots to be able to use that money to buy gear; humans can, of
course, spend the money any time they like (within buy period).

### Talkative bots

Any time a bot drops one weapon in favour of another, during freeze time, he
will announce it to his team ("I'm dropping this AWP in favour of an M4A4").
This doesn't affect other bots' purchasing decisions, but it can allow humans
on the team to make smarter choices.

### Bots with Nades

Bots will buy more grenades (of all types except decoys) if they have spare
money after buying essentials. They still won't be any more coordinated with
their use of them, but at least they have them. Humans can also say "!jayne"
to the team to have friendly bots try to buy even more grenades (subject to
the usual limits).

### Deselect/reselect your sole grenade

If you disable knives (by clearing out mp_[ct/t]_default_melee) and buy two
of the same grenade and nothing else, CS:GO bugs out and won't let you throw
the second one. This bug is silently worked around; you get a quick flicker
and then you're back with the same weapon selected.

### No kits in warmup

To facilitate buy-binds without making the CTs waste money in warmup, defuse
kits cannot be purchased while in warmup mode.

### Mark and measure

Say "!mark" to record a position, then say "!showpos" to get a constantly
updated distance report. Say "!unshowpos" to stop updating. Can be used to
easily measure distance across the map. The mark is shared among players, so
measuring distance between two players is easy.

### Wealthy bots help the team

Say "!drop" to your team to request a weapon drop. The wealthiest bot will
drop his current weapon and then buy a replacement. Great for those times
when there's some stupid bot sitting on a pile of cash while everyone else
can't afford rifles. Note that bots still aren't smart enough to trade
weapons with you, but if the default replacement weapon (M4 or AK) is
superior to the one the wealthiest bot is using, you CAN use this to force
him to upgrade.

### Weapon scoring

"So-and-so brought a knife to a gunfight". Yep, that's a mistake. But what if
you made the mistake of bringing a pistol to a riflefight? Or a scoped-in AWP
to a SMG fight? Which is actually better at resolving encounters - an AUG or
an M249? Track it with this log. Analysis is outside the plugin's control; it
records the raw data. An associated Python script [weapon_scores.py](weapon_scores.py)
shows the top winners and worst losers, and similar analysis could be done on
entire categories of weapon, or adjusting for weapon price, etc.

Note that self-damage and team-damage are recorded, so you can easily track
which weapons tend to be mis-aimed too, if that interests you.
