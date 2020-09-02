# Alternate game modes made available by Dr Zed

The drzed plugin creates a number of tools which can be put together in many
different ways, creating a variety of game modes. Here are just a few that can
be built using the plugin and some cvars. Each is derived from a standard game
mode; configure your server with just a few additional directives (eg with an
"exec" command in your server_last.cfg).

These modes are designed for gameplay. See also the [learning modes](learning.md),
which are designed for training and practice.

## Arms & Armor

Base game mode: Arms Race (aka Gun Game Progressive, type 1 mode 0)

Start with an Arms Race map and configuration. Grant kill awards. Permit
healing, which means setting a price etc. Killing enemies now ranks you up
but also lets you purchase something - maybe grenades, maybe healing, maybe
the heavy assault suit (if it's enabled).

Example config file: [armsarmor.cfg](https://github.com/Rosuav/tf2server/blob/master/steamcmd_linux/csgo/csgo/cfg/armsarmor.cfg)

## Flashbean

Base game mode: Classic (type 0) or short demolition (type 1 mode 1)

Remove all default weapons from everyone. Give everyone a flashbang with
infinite ammo. Reduce everyone's hitpoints to 1. Now you have to bean people
with flashbangs!

Example config file: [flashbean.cfg](https://github.com/Rosuav/tf2server/blob/master/steamcmd_linux/csgo/csgo/cfg/flashbean.cfg)

## Leave No Man Behind

Base game mode: Classic competitive (type 0 mode 1)

Classic mode. Add in a second hitpoint pool wherein you are crippled before
you actually die. Teammates can revive you, or you can revive yourself by
getting a kill on an enemy (or winning the round).

Example config file: [revival.cfg](https://github.com/Rosuav/tf2server/blob/master/steamcmd_linux/csgo/csgo/cfg/revival.cfg)

## No One-Shots

Base game mode: Classic competitive (type 0 mode 1)

Classic mode. Add a health gate: if you are on full health and something
would kill you, it leaves you on critically low health, but still alive.
Certain attacks are able to bypass the health gate, including the knife;
anything that deals massive overkill damage can punch right past it.

Example config file: [drzed.cfg](https://github.com/Rosuav/tf2server/blob/master/steamcmd_linux/csgo/csgo/cfg/drzed.cfg)

## Mad Moxxi's Crash Site Underdome

Base game mode: Guardian (type 4 mode 0)

Designed for gd_crashsite, but can work on other maps (would need some
tweaking of armory locations, that's all). Grindy Guardian mission - needs
fifty kills to win - but every wave has different rules. You get to buy any
weapons you like, but your money is finite, so don't throw away your old
ones! Some waves will have easy requirements, some hard. Some will mess with
you in ways you won't expect. Stay on your toes and keep that site safe!

Tips for difficult waves:
* Worst case, just kill all the terrorists and let it change to a new wave. You
  might not get any progress towards the goal, but you'll be past that wave.
* There are two weapon caches - or occasionally, one cache with twice as many
  weapons in it. They're somewhere on the CT side of the map.
* Don't forget that taking weapons from your enemy is an option too.
* Sniper rifles count as rifles. LMGs count as heavy weapons.

Example config file: [underdome.cfg](https://github.com/Rosuav/tf2server/blob/master/steamcmd_linux/csgo/csgo/cfg/underdome.cfg)
