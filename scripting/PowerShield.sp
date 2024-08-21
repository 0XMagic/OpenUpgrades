#pragma semicolon 1
#pragma newdecls required

#include <OpenUpgrades>
#include <sdkhooks>
#include <tf2_stocks>
#include <TF2Attributes>

#define PLUGIN_VERSION "1.0"
public Plugin myinfo = {
	name = "PowerShield",
	author = "TheKillerBnuuy",
	description = "OpenUpgrades Addon: Power shield resistances",
	version = PLUGIN_VERSION,
	url = "https://steamcommunity.com/id/0x5F3759DF_TF2/"
};

#define ATTR_BULLETS 66
#define ATTR_BLAST 64
#define ATTR_FIRE 60
#define ATTR_MELEE 206
#define ATTR_CRIT 62

//how often to update the hud and apply resistance attributes
#define UPDATE_RATE 0.25

//how long to hold the power hud in addition to UPDATE_RATE
#define BAR_TIME_BUFFER 0.1

//how many characters to make the energy bar
#define BAR_SIZE 12

//balance stuff
#define MIN_POWER -150.0
#define MAX_POWERDMG 20.0
#define POWERDMG_BLOCK_THRESHOLD 5.0 //cant be 0.0 or it will cause errors
#define REGEN_RATE 5.0
#define OP_DECAY_RATE 10.0
#define OP_MAX 1.5

bool gClState[MAXPLAYERS + 1];


char gBarStrings[][] =  { "░", "█" };
Handle gSync;

int gHudColors[] = {
	15, 255, 25, //green: normal
	255, 248, 25, //yellow: alt powerdmg
	10, 255, 204, //blue: overpower
	150, 0, 0, //red: empty
};

public void OnPluginStart() {
	CreateConVar("PowerShield_version", PLUGIN_VERSION, "PowerShield version number (no touchy)", FCVAR_NOTIFY);
	gSync = CreateHudSynchronizer();
	CreateTimer(UPDATE_RATE, Timer_ProcessPower, 0, TIMER_REPEAT);
	HookEvent("post_inventory_application", Event_OnClientChanged);
	HookAll();
}

public void OnClientPutInServer(int client) {
	HookClient(client, true);
}

public void OnClientDisconnect(int client) {
	HookClient(client, false);
}

public Action Event_OnClientChanged(Handle event, const char[] name, bool dontBroadcast) {
	RequestFrame(ClientReset, GetEventInt(event, "userid"));
	return Plugin_Handled;
}

void ClientReset(int userid) {
	int client = GetClientOfUserId(userid);
	float power = OU_GetCustomAttribute(client, C_MAX_POWER);
	OU_SetCustomAttribute(client, C_CURRENT_POWER, power);
}

public Action Timer_ProcessPower(Handle timer, int arg) {
	
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i))
			continue;
			
		ApplyRegen(i);
		ApplyArmor(i);
		ShowPowerHud(i);
	}
	return Plugin_Handled;
}

void CatEnergyBar(char[] str, int maxlen, float power, float maxpower) {
	if(maxpower <= 0.0)
		return;
	
	int filled = RoundFloat(float(BAR_SIZE) * (power / maxpower));
	for(int i; i < BAR_SIZE; i++) {
		StrCat(str, maxlen, gBarStrings[filled > i ? 1 : 0]);
	}
}

int ilerp(int a, int b, float scale)
{
	return RoundToNearest(float(a) * (1.0 - scale) + float(b) * scale);
}

void ShowPowerHud(int client) {
	
	if(OU_GetCustomAttribute(client, C_MAX_POWER) <= 0.0) {
		return;
	}
	char str[256];
	float power = OU_GetCustomAttribute(client, C_CURRENT_POWER);
	float maxpower = OU_GetCustomAttribute(client, C_MAX_POWER);
	
	CatEnergyBar(str, sizeof(str), power, maxpower);
	
	Format(
		str, sizeof(str), "Power: %s (%i / %i)",
		str,
		RoundFloat(power),
		RoundFloat(maxpower)
	);
	
	int r, g, b;
	if(power > 0) {
		float t = OU_GetCustomAttribute(client, C_CURRENT_POWERDMG) / POWERDMG_BLOCK_THRESHOLD;
		if(t > 1.0)
			t = 1.0;
		if(t < 0.0)
			t = 0.0;
		r = ilerp(gHudColors[0], gHudColors[3], t);
		g = ilerp(gHudColors[1], gHudColors[4], t);
		b = ilerp(gHudColors[2], gHudColors[5], t);
		
		if(power > maxpower) {
			r = gHudColors[6];
			g = gHudColors[7];
			b = gHudColors[8];
		}
		
	} else {
		r = gHudColors[9];
		g = gHudColors[10];
		b = gHudColors[11];		
	}
	SetHudTextParams(0.0, 0.0, UPDATE_RATE + BAR_TIME_BUFFER, r, g, b, 255);
	ShowSyncHudText(client, gSync, str);
}

void ApplyRegen(int client) {
	if(!IsPlayerAlive(client))
		return;
	float power = OU_GetCustomAttribute(client, C_CURRENT_POWER);
	float powerdmg = OU_GetCustomAttribute(client, C_CURRENT_POWERDMG);
	float maxpower = OU_GetCustomAttribute(client, C_MAX_POWER);
	
	if(powerdmg != 0.0) {
		powerdmg -= UPDATE_RATE;
		if(powerdmg < 0.0)
			powerdmg = 0.0;
		OU_SetCustomAttribute(client, C_CURRENT_POWERDMG, powerdmg);
	}
	
	if(power == maxpower)
		return;
		
		
	if(power < maxpower && powerdmg <= POWERDMG_BLOCK_THRESHOLD) {
		float regen_amount = UPDATE_RATE * REGEN_RATE;
		regen_amount *= 1.0 + OU_GetCustomAttribute(client, C_POWER_REGEN);
		regen_amount *= 1.0 - (powerdmg / POWERDMG_BLOCK_THRESHOLD);
		power += regen_amount;
		
		if(power > maxpower){
			power = maxpower;
		}
		OU_SetCustomAttribute(client, C_CURRENT_POWER, power);
	} else if(power > maxpower){
		power -= UPDATE_RATE * OP_DECAY_RATE;
		
		if(power < maxpower) {
			power = maxpower;
		}
		
		if(power > maxpower * OP_MAX) {
			power = maxpower * OP_MAX;
		}
		OU_SetCustomAttribute(client, C_CURRENT_POWER, power);
	}
}

void ApplyArmor(int client) {
	float power = OU_GetCustomAttribute(client, C_CURRENT_POWER);
	ProcessArmor(client, power, ATTR_BULLETS, C_SHIELD_BULLETS);
	ProcessArmor(client, power, ATTR_BLAST, C_SHIELD_BLAST);
	ProcessArmor(client, power, ATTR_FIRE, C_SHIELD_FIRE);
	ProcessArmor(client, power, ATTR_MELEE, C_SHIELD_MELEE);
	ProcessArmor(client, power, ATTR_CRIT, C_SHIELD_CRIT);
	TF2Attrib_ClearCache(client);
}

void ProcessArmor(int client, float power, int defindex, int custom) {
	float c = OU_GetCustomAttribute(client, custom);
	power = power > 0.0 ? 1.0 : 0.0;
	power = 1.0 - power * c;
	if(power == 1.0)
		TF2Attrib_RemoveByDefIndex(client, defindex);
	else
		TF2Attrib_SetByDefIndex(client, defindex, power);
}

void HookAll() {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			HookClient(i, true);
		}
	}
}


void HookClient(int client, bool state) {
	if(state != gClState[client]) {
		gClState[client] = !gClState[client];
		if(state) {
			SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		}
		else {
			SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		}
	}
}


float GetResistanceMultiplier(int client, int damagetype) {
	float result = 0.0;
	
	if(damagetype & (DMG_BUCKSHOT | DMG_BULLET))
		result += OU_GetCustomAttribute(client, C_SHIELD_BULLETS);
		
	if(damagetype & DMG_BLAST)
		result += OU_GetCustomAttribute(client, C_SHIELD_BLAST);
		
	if(damagetype & DMG_BURN)
		result += OU_GetCustomAttribute(client, C_SHIELD_FIRE);
		
	if(damagetype & DMG_CLUB)
		result += OU_GetCustomAttribute(client, C_SHIELD_MELEE);
		
	if(damagetype & DMG_ACID)
		result += OU_GetCustomAttribute(client, C_SHIELD_CRIT) * 2.0;
		
	result = 1.0 - result;
	if (result < 0.0)result = 0.0;
	
	return result;
}


public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	if (victim == attacker) {return Plugin_Continue;}
	
	if(!victim || !attacker || victim > MaxClients || attacker > MaxClients){
		return Plugin_Continue;
	}
	
	if(TF2_GetClientTeam(victim) == TF2_GetClientTeam(attacker)){
		return Plugin_Continue;
	}
	
	float power = OU_GetCustomAttribute(victim, C_CURRENT_POWER);	
	if(power <= 0.0) {
		return Plugin_Continue;
	}
	
	float power_drain = damage * (1.0 - GetResistanceMultiplier(victim, damagetype));
	power -= power_drain;
	
	if(power < MIN_POWER){
		power = MIN_POWER;
	}
	
	float powerdmg = OU_GetCustomAttribute(victim, C_CURRENT_POWERDMG);
	
	powerdmg += 1.0;
	
	if(powerdmg > MAX_POWERDMG) {
		powerdmg = MAX_POWERDMG;
	}
	
	OU_SetCustomAttribute(victim, C_CURRENT_POWERDMG, powerdmg);
	
	if(power_drain != 0.0) {
		OU_SetCustomAttribute(victim, C_CURRENT_POWER, power);
	}
	return Plugin_Continue;
}
