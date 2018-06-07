# groundfix

A Sourcemod plugin for preventing various movement bugs related to hitting the ground.

Currently implemented:
* Slope sliding fix: `sv_groundfix_slide` `0/1` `(default 1)`
* Edgebug fall height fix: `sv_groundfix_edge` `0/1` `(default 1)`

Note that this does not fix "random" bugs when already sliding on a slope or surf ramp — only a specific bug that occurs when landing initially.

Requires DHooks: https://forums.alliedmods.net/showthread.php?t=180114
