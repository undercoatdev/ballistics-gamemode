# Ballistics Game Mode

A 5v5 round-based Garry's Mod gamemode (Good vs Bad) built on top of
[TacRP](https://steamcommunity.com/sharedfiles/filedetails/?id=3734712166) and Player Ballistics.

Buy phase, spawn objectives with capture circles, per-player money and an admin panel.

## Install
Copy `gamemodes/ballistics` into `garrysmod/gamemodes/` and pick "Ballistics Game Mode" in the menu.

## Dependencies (Workshop, not bundled)
These are **not** included. Subscribe and enable them:

- [TacRP — Tactical RP Weapons (OFFICIAL)](https://steamcommunity.com/sharedfiles/filedetails/?id=3734712166) (`3734712166`) — all weapons, knife, grenades, attachment menu
- Player Ballistics (workshop id TBD) — meds bag, knockout / unconscious state
- Body Damage core (workshop id TBD) — required by Player Ballistics (`BODY_DAMAGE.FindRecord`)

If TacRP is missing the gamemode still boots and prints a warning; the buy menu stays disabled.

## Tests
`sh tests/run_all.sh` (needs luajit).
