# groundfix

A Sourcemod plugin for preventing various movement bugs related to hitting the ground.

Currently implemented:
* Slope sliding fix: `sm_groundfix_slide` `0/1` `(default 1)`
  * On TF2, this fixes stopping dead on the slope. In CS:S, and maybe some other games, because landing on the ground doesn't cap you to walk speed, it prevents a speed boost that happens instead.
* Edgebug fall height fix: `sm_groundfix_edge` `0/1` `(default 0)`
  * This aims to make 1-unit-wide edgebugs consistent for any fall height. It's not very well tested yet, so it defaults to disabled.
* Chat notification: `sm_groundfix_chat` `0/1` `(default 0)`
  * Prints a message in chat when the plugin prevents a slopebug.
* Banana sound: `sm_groundfix_banana` `0/1` `(default 0)`
  * Plays a banana slip sound for giggles when the plugin prevents a slopebug.

Note that this does not fix "random" bugs when already sliding on a slope or surf ramp — only a specific bug that occurs when landing initially.
