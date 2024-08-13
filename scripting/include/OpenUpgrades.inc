#if defined _OU_included
 #endinput
#endif
#define _OU_included

enum {
	C_USED_MENU,
	C_MAX_POWER,
	C_POWER_REGEN,
	C_SHIELD_BULLETS,
	C_SHIELD_BLAST,
	C_SHIELD_FIRE,
	C_SHIELD_MELEE,
	C_SHORT_CIRCUIT_FIRERATE,
	C_CURRENT_POWER,
	C_CURRENT_POWERDMG,
	C_SHIELD_CRIT
}


native float OU_GetCustomAttribute(int client, int index);


native float OU_SetCustomAttribute(int client, int index, float value);