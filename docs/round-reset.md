# Round reset

At every BUY phase start, before slotted players spawn:

- Corpses and ragdolls go away, including Player Ballistics kept bodies (that addon has no remove-all call, so the gamemode drops the body list and the entities). Blood decals are cleared on the server and each client runs `r_cleardecals`. Spawn flags and other gamemode entities stay. `game.CleanUpMap` is not used.
- TacRP infinite ammo stays off while the gamemode runs (`tacrp_infiniteammo` is remembered, forced to 0, and restored on shut down). Buying a gun gives that gun's own clip size times Rules → General "Magazines per gun" (default 3) as reserve. TacRP's default ammo grant is not added on top.
- The buy wheel Weapons tab groups guns, in order: Pistol, Magnum, Machine Pistol, SMG, Assault Rifle, Battle Rifle, Shotgun, Sniper. Each button still shows the gun name and price.
- Every player still alive at round end, on either team (win, loss or draw), keeps weapons, clip, reserve ammo, TacRP attachments, and meds at the next buy spawn. Attachments are put back through the weapon's own Attach data and are not charged. Anyone who died, and everyone at a new match, starts with nothing.
- Organ health is the exception to the usual Body Damage reset. It is snapshotted before the respawn, written onto the new record, then healed by Rules → General "Healed up organs" (default 10, capped at that organ's max). A destroyed organ comes back with at least 1. Bleeding, blood, consciousness, and the rest still reset. A new match starts organs full. Clients see the values through Body Damage's organ sync.

Reset to defaults restores both new settings. The hover blurb on "Healed up organs" is: "At each new round every organ heals this many units (capped at max). Destroyed organs always come back working, just weak."
