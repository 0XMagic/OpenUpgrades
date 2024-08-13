#if defined _wpnget_included
 #endinput
#endif
#define _wpnget_included

//code snippet taken from tf2x10
//https://forums.alliedmods.net/showthread.php?t=270723
stock int WeaponScanEnt(int startEnt, const char[] classname)
{
	while (startEnt > -1 && !IsValidEntity(startEnt)) { startEnt--; }
	return FindEntityByClassname(startEnt, classname);
}

stock int WeaponGetWearable(int client, int iSlot)
{
	int edict = MaxClients + 1;
	if(iSlot == TFWeaponSlot_Secondary)
	{
		while((edict = WeaponScanEnt(edict, "tf_wearable_demoshield")) != -1)
		{
			int idx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
			if((idx == 131 || idx == 406 || idx == 1099 || 1144) && GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == client && !GetEntProp(edict, Prop_Send, "m_bDisguiseWearable"))
				return edict;
			
		}
	}
	edict = MaxClients+1;
	while((edict = WeaponScanEnt(edict, "tf_wearable")) != -1)
	{
		char netclass[32];
		if(GetEntityNetClass(edict, netclass, sizeof(netclass)) && StrEqual(netclass, "CTFWearable"))
		{
			int idx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
			if(((iSlot == TFWeaponSlot_Primary && (idx == 405 || idx == 608))
				|| (iSlot == TFWeaponSlot_Secondary && (idx == 57 || idx == 133 || idx == 231 || idx == 444 || idx == 642)))
				&& GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == client && !GetEntProp(edict, Prop_Send, "m_bDisguiseWearable"))
				return edict;
		}
	}
	return -1;
}
stock int GetWeapon(int client, int slot)
{
		if (slot == -1) return client; 
		int result = GetPlayerWeaponSlot(client, slot);
		if (result == -1)return WeaponGetWearable(client, slot);
		return result;
}


stock int GetDefIndex(int wpn)
{
	if(wpn <= MaxClients)
		return -1;
	return GetEntProp(wpn, Prop_Send, "m_iItemDefinitionIndex");
}
