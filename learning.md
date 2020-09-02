# Learning CS:GO with server-side help

There's a lot that you can do to learn CS:GO just by using your own private
server, possibly with `sv_cheats 1` to enable additional commands and tools.
These learning modes go beyond that, and add extra instrumentation to help
you become better at the game.

## Throwing smokes/flashes

Example config file: [learnsmoke.cfg](https://github.com/Rosuav/tf2server/blob/master/steamcmd_linux/csgo/csgo/cfg/learnsmoke.cfg)

Core CS:GO features that work well with this:
* cl_grenadepreview 1 - great for the short throws or to see where it'll bounce
* sv_rethrow_last_grenade - run this command to recreate the last grenade throw
* noclip - go anywhere, spectate from any angle, and then watch the rethrown nade

Learn to throw a specific smoke at a specific target by seeing the exact position
you were at when you threw one. For distant smokes, see where the projectile's
first bounce hit, as this can be a good indication of where it's going to land.
For jump throws, master the synchronization by being shown whether you jumped
before or after you threw, and by how many server ticks.

Specifically to smoking Xbox on Dust II, this also automatically validates the
above statistics and tells you whether the first bounce is promising or not,
and whether the smoke landed in the right place. "Promising" is based on
[the throw from T spawn](images/Xbox_TSpawn.png), a jump throw straight down
Mid that bounces on the steps. Ignoring the "Promising" flag, this can still be
used to test other ways to smoke the same location, such as a run-throw from
outside Bedroom towards Mid, or a highly specific standing throw
[from the white X near the origin](images/Xbox_standhere.png) tossed
[over the building](images/Xbox_throwhere.png).

## Stutter-stepping

If you move sideways across someone's field of view, you're harder to hit. If
you aren't moving while you shoot, you're accurate. Combining those is the art
of stutter-stepping. One thing seldom explained in stutter-stepping tutorial
videos is the magical 34% threshold: if you are moving at no more than 34% of
your weapon's maximum movement speed, you are fully accurate. You don't have to
be completely stationary; you don't have to perfectly synchronize the movement
and shooting in order to benefit from this.

Example config file: [learnstutter.cfg](https://github.com/Rosuav/tf2server/blob/master/steamcmd_linux/csgo/csgo/cfg/learnstutter.cfg)

Core CS:GO features that work well with this:
* sv_maxspeed - cap your speed at some value to test accuracy at different
  speeds (server-side only)
* weapon_debug_spread_show 1 - add a box highlight showing your accuracy, even
  when scoped in with a sniper or premium rifle
* cl_showpos 1 - get some numbers on your speed

Every time you fire a shot, the server informs you of its accuracy in this way:

    Stutter: speed NNNN/NN side NN% good/bad SYNC +/- NN

The speed is compared against the maximum accurate speed with this weapon. If
you're below that (eg "29.54/81"), it's a "good" shot - completely accurate.
Otherwise it's a "bad" shot and has some movement inaccuracy. The proportion
of movement that is lateral is shown; 100% means you're moving precisely left
or right, and 0% means you're moving forward or backward. Finally, the sync
indicator says whether you are shooting after the direction change (positive)
or before it (negative), so you can adjust your key and click synchronization.

Each time you reload, stats for that magazine are shown to everyone:

    Yourname: stopped NN, accurate NN, inaccurate NN - spread NNNN

Shots taken while completely stationary and not holding either strafe key (or
both at once) are counted separately, as they most likely don't qualify. The
number of accurate (below 34% speed) and inaccurate (above 34%) shots are
counted, and then an average spread score is shown. A spread of 0 is perfect
and means all your shots were accurate; a spread of 7.65 is bad, and means you
fired every shot at maximum speed. (The exact formula is: `(speed/threshold)**2 - 1`
for inaccurate shots, and `0` for accurate ones.)

Note that these calculations do not take into account weapon recoil. You'll
have to master THAT separately :)


Enjoy putting in a few hours getting better at the game, and I hope that we
meet in matchmaking some day - for do not the poets say that a noble friend is
the best gift, and a noble enemy the next best?
