#pragma semicolon 1
#pragma newdecls required

#include <sdkhooks>
#include <sdktools>
#include <OpenUpgrades>

#define PLUGIN_VERSION "1.0"
public Plugin myinfo = {
	name = "ShortCircuitFirerate",
	author = "TheKillerBnuuy",
	description = "OpenUpgrades Addon: increases firerate of short circuit alt-fire",
	version = PLUGIN_VERSION,
	url = "https://steamcommunity.com/id/0x5F3759DF_TF2/"
};

public void OnPluginStart() {
	CreateConVar("ShortCircuitFirerate_version", PLUGIN_VERSION, "ShortCircuitFirerate version number (no touchy)", FCVAR_NOTIFY);
}

#define SHORT_CIRCUIT 528
public void OnEntityCreated(int entity, const char[] classname) {
	if(StrEqual(classname,"tf_projectile_mechanicalarmorb")) {
		SDKHook(entity, SDKHook_SpawnPost, OnEngyBallCreated);
	}
}

public void OnEngyBallCreated(int entity) {
	SDKUnhook(entity, SDKHook_SpawnPost, OnEngyBallCreated);
	int client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(client < 0 || client > MaxClients || !IsClientInGame(client))
		return;
	RequestFrame(Frame_ReduceTime, GetClientUserId(client));
}

void Frame_ReduceTime(int client) {
	client = GetClientOfUserId(client);
	if (!client)return;
	
	float reduction = OU_GetCustomAttribute(client, C_SHORT_CIRCUIT_FIRERATE);
	if(reduction > 0.0) {
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		int defindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
		if(defindex != SHORT_CIRCUIT)
			return;
		
		float time = GetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack");
		SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", time - reduction);
	}
}