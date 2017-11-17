TF2 Buff Bot and Bot Control
============================

These two Team Fortress 2 mods can be used independently or together. The Buff
Bot is a roll-the-dice mod based around a desire to create carnage; Bot Control
allows a human player to give instructions to bots on the same team.

Buff Bot
--------

The Buff Bot's primary statistic is "carnage points", which are earned by all
game participants. Once you have enough, you can spend all your carnage points
on either a random effect for yourself, or a gift for another player.

Carnage points are earned by killing your opponents, destroying buildings, and
dying. You may also be able to earn carnage points by deploying Ubercharge or
upgrading a building (as Medic and Engineer, respectively), if the server has
enabled it.

To spend your carnage points, chat either "!roulette" or "!gift". The former
will grant a random effect to you; there is roughly two thirds chance of some
beneficial effect, and one third chance of something detrimental. The latter
grants a guaranteed beneficial effect to someone on the server. You will never
receive your own gift (if there is nobody to receive it, the gift is wasted).
Human players have far greater chance to receive gifts than bots do, and those
on your own team have twice the chance that opponents have.

Server admins, check out the sm_buffbot_* cvars to tweak a variety of knobs.
Note that carnage points are always reset if a player changes team, but are
otherwise carried over; this means, for instance, that you can accrue points
during Humiliation after one stage of a Payload map, and then use them in the
next stage.

No carnage points are granted for achieving map goals (capturing the flag,
taking a control point, moving the payload, etc). Such actions may help you
win, but they don't create death and destruction. Get out there killing stuff!

See [knobs](knobs.md) for a full list of tweakable knobs and some advice on how
they affect gameplay.

Known bugs: Some effects don't reset on death, some do reset when you touch a
resupply locker, and there's not a lot of consistency.

Bot Control
-----------

Have you ever had that really annoying situation where a "friendly" bot is just
sitting there being dead weight, and you wish you could grab him by the ear and
say "Oi! Do something!"? This is the mod for you. Address a bot using either:

    !oi BotName command
    !oi command BotName

The commands available are as follows.

* speak - make a bot say "Woof", like the servant it is. Good for testing.
* drop - if the bot's carrying the flag or a Mannpower powerup, it will drop it
* medic/soldier - immediately change class to Medic or Soldier. (TODO: Allow
  *any* class to be selected, and possibly "when you next die, go medic".)
* ready - Nonworking attempt to make a bot "ready up" in Mann vs Machine
* telehere - Nonworking attempt to have a bot engie build his tele exit here
* heel - the piece de ten-ohm wire, if only I could make it work. Tell a bot to
  follow you for the next few seconds. :( I wish.

Tip: It doesn't matter where you are when you give this instruction. So if one
human player is tailing a bot and wants to take over the flag, a completely
different human (on the same team) can say "!oi Zawmbeez drop".

As a silent bonus feature, having this plugin active will attempt to prevent
the issue with bots getting stuck in a class selection loop while spawning.
Not yet perfect, but can be helpful. Will encourage bots to select a damage
class (soldier/demo/pyro/heavy) rather than debating with themselves about
a support class.

License
-------

All code in this project, including the metaprogramming script, is made
available under the terms of the MIT license. In short: do what you like,
including commercial use, but don't sue me if something doesn't work.

If you use and like this, I'd love to hear from you, particularly if you have
ideas about how to improve on this code. It's my first forays into SourcePawn
and TF2 modding, so the code is pretty messy; pull requests are very much
welcome, as long as you're willing for your code to also be released under the
same terms.
