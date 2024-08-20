#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf2_stocks>
#include <tf2attributes>
#include <wpnget>
#include <sdkhooks>
#include <OpenUpgrades>

#define PLUGIN_VERSION "1.0"
public Plugin myinfo = {
	name = "OpenUpgrades",
	author = "TheKillerBnuuy",
	description = "MVM addon with weapon upgrade menu with spendable currency.",
	version = PLUGIN_VERSION,
	url = "https://steamcommunity.com/id/0x5F3759DF_TF2/"
};



#define U_COUNT 1024
#define C_COUNT 512
#define I_COUNT 64
#define F_COUNT 64

int gCurrencyOffset;
enum {
	Purchase_NoMoney = -1,
	Purchase_Limited = -2,
	Purchase_Spectator = -3,
}


int gCurUpgrade;
char gUpgradeName[U_COUNT][256];
char gUpgradeDesc[U_COUNT][256];
int gUpgradePrice[U_COUNT];
int gUpgradeRate[U_COUNT];
bool gUpgradeMenu[U_COUNT];
int gUpgradeCount[U_COUNT];
any gUpgradeItems[U_COUNT][I_COUNT];
int gUpgradeMax[U_COUNT];
bool gUpgradeShared[U_COUNT];
int gUpgradeParent[U_COUNT];
int gUpgradeFilterClass[U_COUNT][TFClassType];
int gUpgradeFilterWeaponCount[U_COUNT];
bool gUpgradeFilterWeaponMode[U_COUNT];
int gUpgradeFilterWeapons[U_COUNT][F_COUNT];
int gUpgradeDisplayMode[U_COUNT];
int gUpgradeDisplayValue[U_COUNT];
int gUpgradeDisplayStart[U_COUNT];

int gClientUpgrades[MAXPLAYERS + 1][U_COUNT];
int gClientUpgradesCheckpoint[MAXPLAYERS + 1][U_COUNT];

float gClientCustomAttributes[MAXPLAYERS + 1][C_COUNT];

int gMoney;
bool gInitRound = true;
int gMoneyCheckpoint;
int gClientSpentMoney[MAXPLAYERS + 1];
int gClientNode[MAXPLAYERS + 1];

int gClientUserid[MAXPLAYERS + 1];
TFClassType gClientClass[MAXPLAYERS + 1];
int gClientWeapons[MAXPLAYERS + 1][8];
int ClButtons[MAXPLAYERS + 1];

Menu gActiveMenu[MAXPLAYERS + 1];

bool gIsMvM = true;
bool gBlueWins;


public void OnPluginStart() {
	LoadConfigFromFile();
	
	CreateConVar("OpenUpgrades_version", PLUGIN_VERSION, "OpenUpgrades version number (no touchy)", FCVAR_NOTIFY);
	
	RegAdminCmd("sm_ou_load", Cmd_Load, ADMFLAG_ROOT, "[debug] force load mvm checkpoint");
	RegAdminCmd("sm_ou_save", Cmd_Save, ADMFLAG_ROOT, "[debug] force save mvm checkpoint");
	RegAdminCmd("sm_ou_reload", Cmd_ReloadConfig, ADMFLAG_ROOT, "Reload OU config and refund all upgrades");
	RegAdminCmd("sm_addcurrency", Cmd_AddCurrency, ADMFLAG_ROOT, "Adds currency to global pool");
	
	RegConsoleCmd("sm_buy", Cmd_BuyMenu, "Open the upgrade shop");
	RegConsoleCmd("sm_refund", Cmd_Refund, "Refund your upgrades");
	RegConsoleCmd("sm_qbuy", Cmd_Qbuy, "Quick-Buy upgrades, use sm_qbuy for more info");
	
	
	HookEvent("mvm_pickup_currency", Event_OnCollectCurrency, EventHookMode_Pre);
	HookEvent("post_inventory_application", Event_OnClientChanged);
	HookEvent("player_spawn", Event_OnClientChanged);
	
	HookEvent("mvm_reset_stats", Event_RoundReset);
	HookEvent("teamplay_round_win", Event_MissionEnd);
	HookEvent("teamplay_round_start", Event_MissionStart);
	HookEvent("mvm_begin_wave", Event_MissionStart);
	HookEvent("mvm_wave_complete", Event_WaveComplete);
	
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
			
		ClientChanged(i);
	}
	
	ResetRound();
}

public void OnMapStart() {
	gInitRound = true;
	RemoveAllUpgradeStations();
	FindCurrencyOffset();
}

public void OnClientPutInServer(int client) {
	gClientUserid[client] = 0;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	int delta = buttons ^ ClButtons[client];
	ClButtons[client] = buttons;
	
	//tab+r = open menu
	if(buttons & IN_SCORE && (delta & buttons) & IN_RELOAD)
		ShowUpgradeMenu(client, 0);
	
	if(delta & IN_DUCK && GetClientMenu(client, INVALID_HANDLE) != MenuSource_None && gActiveMenu[client])
		ShowUpgradeMenu(client, gClientNode[client], buttons & IN_DUCK ? 10 : 1);

	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (!strncmp(classname, "item_currencypack", 17)){
		SDKHook(entity, SDKHook_Spawn, CurrencyPackSpawned);
	}
	
	
	if(StrEqual(classname, "func_upgradestation")) {
		RequestFrame(RemoveUpgradeStation, EntIndexToEntRef(entity));
	}
}

void RemoveAllUpgradeStations() {
	int entity = -1;
	while(entity) {
		entity = FindEntityByClassname(entity, "func_upgradestation");
		if(entity == -1)
			break;
		RemoveEntity(entity);
	}
}

void FindCurrencyOffset(){
	int entity = CreateEntityByName("item_currencypack_large");
	SDKHook(entity, SDKHook_SpawnPost, FindCurrencyOffsetSpawn);
	DispatchSpawn(entity);
}

public void FindCurrencyOffsetSpawn(int entity){
	int offset = -1;
	for(int i = 1; i < 2000; i++) {
		if(GetEntData(entity, i) == 25) {
			offset = i;
			break;
		}
	}
	if(offset != -1) {
		PrintToServer("[OpenUpgrades] Found currency offset at: %i", offset);
		gCurrencyOffset = offset;
	} else {
		PrintToServer("[OpenUpgrades] Offset not found... this will cause issues!");
	}
	RemoveEntity(entity);
}

void RemoveUpgradeStation(int entity) {
	entity = EntRefToEntIndex(entity);
	if(entity != -1)
		RemoveEntity(entity);
}


public void CurrencyPackSpawned(int entity) {
	SDKUnhook(entity, SDKHook_Spawn, CurrencyPackSpawned);	
	if(GetEntProp(entity, Prop_Send, "m_bDistributed") && gCurrencyOffset) {
		int money = GetEntData(entity, gCurrencyOffset);
		SetEntData(entity, gCurrencyOffset, -money);
		gMoney += money;
	}
}


public Action Event_OnCollectCurrency(Handle event, const char[] name, bool dontBroadcast) {
	int cash = GetEventInt(event, "currency");
	if (cash > 0) {
		//cash is green, run code like normal
		gMoney += cash;
	} else {
		SetEventInt(event, "currency", cash * -1);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}


public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int errlen) {
	CreateNative("OU_GetCustomAttribute", N_GetCustomAttribute);
	CreateNative("OU_SetCustomAttribute", N_SetCustomAttribute);
	return APLRes_Success;
}


any N_GetCustomAttribute(Handle plugin, int args) {
	int client = GetNativeCell(1);
	int idx = GetNativeCell(2);
	return gClientCustomAttributes[client][idx];
}


any N_SetCustomAttribute(Handle plugin, int args) {
	int client = GetNativeCell(1);
	int idx = GetNativeCell(2);
	float value = GetNativeCell(3);
	gClientCustomAttributes[client][idx] = value;
	return 0;
}


public Action Cmd_Load(int client, int args) {
	LoadCheckpoint();
	return Plugin_Handled;
}


public Action Cmd_Save(int client, int args) {
	SaveCheckpoint();
	return Plugin_Handled;
}

public Action Cmd_AddCurrency(int client, int args) {
	if (!args) {
		ReplyToCommand(client, "[OpenUpgrades] sm_addcurrency <amount>");
		return Plugin_Handled;
	}
	int add = GetCmdArgInt(1);
	gMoney += add;
	ReplyToCommand(client, "[OpenUpgrades] Added %i cash to global pool.", add);
	return Plugin_Handled;
}

public Action Cmd_ReloadConfig(int client, int args) {
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		gClientUserid[i] = 0;
		ClientChanged(i);
	}
	LoadConfigFromFile();
	return Plugin_Handled;
}


int BuildQbuyArray(int client, int parent, int result[I_COUNT]) {
	int id;
	if(!gUpgradeMenu[parent])
		return 0;
	
	for(int i; i < gUpgradeCount[parent]; i++) {
		if(!CanAccessUpgrade(client, gUpgradeItems[parent][i]))
			continue;
		result[id++] = gUpgradeItems[parent][i];
	}
	return id;
}


public Action Cmd_Qbuy(int client, int args){
	if(args <= 1 || args > 10) {
		ReplyToCommand(client, "=====QBUY HELP=====\nUsage: !qbuy <address> <amount>\nExample: \"!qbuy 1 1 1 42\" buys health upgrade 42 times");
		return Plugin_Handled;
	}
	int amount = GetCmdArgInt(args);
	
	if(amount <= 0 || amount > 1000) {
		ReplyToCommand(client, "[QBuy] Invalid amount");
		return Plugin_Handled;
	}
	
	int array[I_COUNT];
	int location;
	int cur_node;
	int count;
	for(int i = 1; i < args; i++) {
		location = GetCmdArgInt(i);
		count = BuildQbuyArray(client, cur_node, array);
		
		if(!count || location > count || location <= 0){
			ReplyToCommand(client, "[QBuy] Invalid upgrade address");
			return Plugin_Handled;
		}
		cur_node = array[location - 1];
	}
	
	if(gUpgradeMenu[cur_node]) {
		ReplyToCommand(client, "[QBuy] Invalid upgrade address");
		return Plugin_Handled;
	}
	int prev_count = gClientUpgrades[client][cur_node];
	amount = TryBuyUpgrade(client, cur_node, amount);
	int price = GetUpgradePrice(cur_node, prev_count, amount);
	switch (amount) {
		case Purchase_Spectator: {
			ReplyToCommand(client, "[QBuy] Can't purchase upgrades in spectator!");
		}
		
		case Purchase_NoMoney: {
			ReplyToCommand(client, "[QBuy] Not enough money!");
		}
		
		case Purchase_Limited: {
			ReplyToCommand(client, "[QBuy] This upgrade is maxed out!");
		}
		
		default: {
			ReplyToCommand(client, "[QBuy] Bought %s x%i for $%i.", gUpgradeName[cur_node], amount, price);
		}
	}
	
	return Plugin_Handled;
}


public Action Cmd_BuyMenu(int client, int args) {
	if(!CanBuyUpgrades(client)) {
		ReplyToCommand(client, "[OpenUpgrades] Can't buy upgrades in spectator.");
		return Plugin_Handled;
	}
	
	ShowUpgradeMenu(client, 0);
	return Plugin_Handled;
}


public Action Cmd_Refund(int client, int args) {
	RefundAllUpgrades(client);
	ShowUpgradeMenu(client, 0);
	ReplyToCommand(client, "[OpenUpgrades] Upgrades refunded.");
	return Plugin_Handled;
}


public Action Event_MissionEnd(Handle event, const char[] name, bool dontBroadcast) {
	gBlueWins = GetEventInt(event, "team") == 3;
	return Plugin_Handled;
}


public Action Event_WaveComplete(Handle e, const char[] name, bool dontBroadcast) {
	if(gIsMvM)
		SaveCheckpoint();
	return Plugin_Handled;
}


public Action Event_MissionStart(Handle e, const char[] name, bool dontBroadcast) {
	if(gBlueWins && gIsMvM)
		CreateTimer(0.15, Timer_OnLostPrevAttempt, 0);
	
	else if(gIsMvM)
		SaveCheckpoint();
	
	return Plugin_Handled;
}

public Action Timer_OnLostPrevAttempt(Handle timer, int tmp) {
	gBlueWins = false;
	LoadCheckpoint();
	return Plugin_Handled;
}

public Action Event_OnClientChanged(Event e, const char[] name, bool dontBroadcast) {
	Event event = e;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client) {
		return Plugin_Handled;
	}
	ClientChanged(client);
	
	if(gInitRound)
		ResetRound();
	
	return Plugin_Handled;
}


public Action Event_RoundReset(Handle e, const char[] name, bool dontBroadcast) {
	ResetRound();
	return Plugin_Handled;
}


void ResetRound() {
	gMoney = 0;
	gMoneyCheckpoint = 0;
	bool cl_found;
	for (int i = 1; i <= MaxClients; i++) {
		RefundAllUpgrades(i);
		if(gIsMvM && !cl_found && IsClientInGame(i) && TF2_GetClientTeam(i) == TFTeam_Red) {
			cl_found = true;
			i = GetClientUserId(i);
			CreateTimer(0.05, Timer_SetInitialCurrency, i);
			gInitRound = false;
		}
	}
	SaveCheckpoint();
}


public Action Timer_SetInitialCurrency(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if(!client)
		return Plugin_Handled;
	gMoney = GetEntProp(client, Prop_Send, "m_nCurrency");
	gMoneyCheckpoint = gMoney;
	return Plugin_Handled;
}


void ClientChanged(int client) {
	if(gIsMvM && IsFakeClient(client))
		return;
	
	bool force_reopen = false;
	if(UpdateClientEquipment(client)) {
		RefundAllUpgrades(client);
		force_reopen = true;
		for(int i; i < U_COUNT; i++) {
			gClientUpgradesCheckpoint[client][i] = 0;
		}
		
	} else {
		ReApplyAllUpgradeAttributes(client);
	}
	
	//would probs piss off admins if I didn't have this check
	if(CanBuyUpgrades(client) && !IsFakeClient(client) && (force_reopen || GetClientMenu(client, INVALID_HANDLE) == MenuSource_None)) {
		ShowUpgradeMenu(client, 0);
	}
}


void UnpackWeaponFilter(KeyValues keyvalues, int parent){
	KeyValues kv = keyvalues;
	char str[2048];
	kv.GetString("weapon_filter", str, 2048);
	if(!strlen(str)){
		return;
	}
	
	char split[64][8];
	ReplaceString(str, 2048, " ", "");
	int weapons = ExplodeString(str, ";", split, 64, 8);
	gUpgradeFilterWeaponCount[parent] = weapons;
	for(int i; i < weapons; i++){
		gUpgradeFilterWeapons[parent][i] = StringToInt(split[i]);
	}
}


int RecurRegUpgrades(KeyValues keyvalues, int parent = 0) {
	if (!parent) {
		gCurUpgrade = 0;
	}
	
	KeyValues kv = keyvalues;
	kv.GetString("name", gUpgradeName[parent], 256, "<no name>");
	kv.GetString("desc", gUpgradeDesc[parent], 256);
	
	gUpgradePrice[parent] = kv.GetNum("price");
	gUpgradeRate[parent] = kv.GetNum("rate");
	gUpgradeMax[parent] = kv.GetNum("max");
	gUpgradeShared[parent] = !!kv.GetNum("shared_max");
	gUpgradeFilterWeaponMode[parent] = !!kv.GetNum("weapon_filter_blacklist");
	
	gUpgradeDisplayValue[parent] = kv.GetNum("disp_value");
	gUpgradeDisplayStart[parent] = kv.GetNum("disp_value_start");
	gUpgradeDisplayMode[parent] = kv.GetNum("disp_percent");
	
	gUpgradeParent[parent] = 0;
	gUpgradeMenu[parent] = false;
	gUpgradeFilterWeaponCount[parent] = 0;
	gUpgradeCount[parent] = 0;
	
	if(kv.JumpToKey("children") && kv.GotoFirstSubKey()) {
		gUpgradeMenu[parent] = true;
		int child;
		do {
			child = RecurRegUpgrades(kv, gCurUpgrade++ + 1);
			gUpgradeParent[child] = parent;
			gUpgradeItems[parent][gUpgradeCount[parent]++] = child;
		} while (kv.GotoNextKey());
		kv.GoBack();
		kv.GoBack();
	} else if(kv.JumpToKey("attributes") && kv.GotoFirstSubKey()) {
		int i;
		char str[8];
		do {
			kv.GetSectionName(str, sizeof(str));
			gUpgradeItems[parent][i + 0] = StringToInt(str); //defindex
			gUpgradeItems[parent][i + 1] = kv.GetFloat("start");
			gUpgradeItems[parent][i + 2] = kv.GetFloat("value");
			gUpgradeItems[parent][i + 3] = kv.GetNum("slot");
			gUpgradeCount[parent] += 4;
			i += 4;
		} while (kv.GotoNextKey());
		kv.GoBack();
		kv.GoBack();
	}
	if(kv.JumpToKey("class_filter")) {
		gUpgradeFilterClass[parent][TFClass_Unknown] = 0;
		gUpgradeFilterClass[parent][TFClass_Scout] = kv.GetNum("scout");
		gUpgradeFilterClass[parent][TFClass_Soldier] = kv.GetNum("soldier");
		gUpgradeFilterClass[parent][TFClass_Pyro] = kv.GetNum("pyro");
		gUpgradeFilterClass[parent][TFClass_DemoMan] = kv.GetNum("demoman");
		gUpgradeFilterClass[parent][TFClass_Heavy] = kv.GetNum("heavy");
		gUpgradeFilterClass[parent][TFClass_Engineer] = kv.GetNum("engineer");
		gUpgradeFilterClass[parent][TFClass_Medic] = kv.GetNum("medic");
		gUpgradeFilterClass[parent][TFClass_Sniper] = kv.GetNum("sniper");
		gUpgradeFilterClass[parent][TFClass_Spy] = kv.GetNum("spy");
		kv.GoBack();
	} else {
		gUpgradeFilterClass[parent][TFClass_Unknown] = 0;
		gUpgradeFilterClass[parent][TFClass_Scout] = 1;
		gUpgradeFilterClass[parent][TFClass_Soldier] = 1;
		gUpgradeFilterClass[parent][TFClass_Pyro] = 1;
		gUpgradeFilterClass[parent][TFClass_DemoMan] = 1;
		gUpgradeFilterClass[parent][TFClass_Heavy] = 1;
		gUpgradeFilterClass[parent][TFClass_Engineer] = 1;
		gUpgradeFilterClass[parent][TFClass_Medic] = 1;
		gUpgradeFilterClass[parent][TFClass_Sniper] = 1;
		gUpgradeFilterClass[parent][TFClass_Spy] = 1;
	}
	
	UnpackWeaponFilter(kv, parent);
	return parent;
}


void LoadConfigFromFile() {
	gCurUpgrade = 0;
	char str[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, str, PLATFORM_MAX_PATH, "configs/OpenUpgrades.cfg");
	KeyValues kv = new KeyValues("Uber Upgrades");
	kv.ImportFromFile(str);
	RecurRegUpgrades(kv);
	delete kv;
}


bool CanBuyUpgrades(int client) {
	if(!IsClientInGame(client))
		return false;
	
	TFTeam team = TF2_GetClientTeam(client);
	return team == TFTeam_Red || team == TFTeam_Blue;
}


void UpdateClientEquipmentWeapon(int client, int slot, bool &result){
	int defindex = GetDefIndex(GetWeapon(client, slot));
	if(gClientWeapons[client][slot] != defindex) {
		gClientWeapons[client][slot] = defindex;
		result = true;
	}
}


bool UpdateClientEquipment(int client) {
	bool result;
	int userid = GetClientUserId(client);
	
	if(userid != gClientUserid[client]) {
		gClientUserid[client] = userid;
		result = true;
	}
	
	TFClassType class = TF2_GetPlayerClass(client);
	
	if(class != gClientClass[client]) {
		gClientClass[client] = class;
		result = true;
	}
	
	UpdateClientEquipmentWeapon(client, TFWeaponSlot_Primary, result);
	UpdateClientEquipmentWeapon(client, TFWeaponSlot_Secondary, result);
	UpdateClientEquipmentWeapon(client, TFWeaponSlot_Melee, result);
	UpdateClientEquipmentWeapon(client, TFWeaponSlot_PDA, result);
	UpdateClientEquipmentWeapon(client, TFWeaponSlot_Building, result);
	UpdateClientEquipmentWeapon(client, TFWeaponSlot_Item1, result);
	UpdateClientEquipmentWeapon(client, TFWeaponSlot_Item2, result);
	UpdateClientEquipmentWeapon(client, TFWeaponSlot_Grenade, result);
	
	
	return result;
}


void ResetWeapon(int client, int slot){
	int weapon = GetWeapon(client, slot);
	if(IsValidEntity(weapon))
		TF2Attrib_RemoveAll(weapon);
}


void ResetClientAttributes(int client) {
	
	if(!IsClientInGame(client))
		return;
	
	TF2Attrib_RemoveAll(client);
	ResetWeapon(client, TFWeaponSlot_Primary);
	ResetWeapon(client, TFWeaponSlot_Secondary);
	ResetWeapon(client, TFWeaponSlot_Melee);
	ResetWeapon(client, TFWeaponSlot_PDA);
	ResetWeapon(client, TFWeaponSlot_Building);
	ResetWeapon(client, TFWeaponSlot_Item1);
	ResetWeapon(client, TFWeaponSlot_Item2);
	ResetWeapon(client, TFWeaponSlot_Grenade);
	
	for(int i; i < C_COUNT; i++) {
		gClientCustomAttributes[client][i] = 0.0;
	}
	
	TF2_AddCondition(client, TFCond_SpeedBuffAlly, 0.01);
}


void ApplyUpgradeAttributes(int client, int upgrade) {
	float count = float(gClientUpgrades[client][upgrade]);
	int defindex;
	float value;
	float start;
	int slot;
	int to_apply;
	
	for(int i; i < gUpgradeCount[upgrade]; i += 4) {
		defindex = gUpgradeItems[upgrade][i + 0];
		start = gUpgradeItems[upgrade][i + 1];
		value = gUpgradeItems[upgrade][i + 2];
		slot = gUpgradeItems[upgrade][i + 3];
		
		if(defindex > 0) {
			to_apply = GetWeapon(client, slot);
			TF2Attrib_SetByDefIndex(to_apply, defindex, count * value + start);
			TF2Attrib_ClearCache(to_apply);
			
			if(defindex == 107) {
				TF2_AddCondition(client, TFCond_SpeedBuffAlly, 0.01);
			}
		} else {
			gClientCustomAttributes[client][-defindex] = count * value + start;
		}
	}
}


void ReApplyAllUpgradeAttributes(int client) {
	ResetClientAttributes(client);
	for(int i; i < U_COUNT; i++) {
		if(gUpgradeMenu[i] || !gClientUpgrades[client][i])
			continue;
		ApplyUpgradeAttributes(client, i);
	}
}


//todo: optmize this since it is a summation
int GetUpgradePrice(int upgrade, int start, int count) {
	int price = gUpgradePrice[upgrade];
	int rate = gUpgradeRate[upgrade];
	int stop = count + start;
	int result;
	
	for(int i = start; i < stop; i++) {
		result += price + rate * i;
	}
	
	return result;
}


void RecalcSpentMoney(int client) {
	gClientSpentMoney[client] = 0;
	for(int i; i < U_COUNT; i++) {
		if(gUpgradeMenu[client] || !gClientUpgrades[client][i])
			continue;
			
		gClientSpentMoney[client] += GetUpgradePrice(i, 0, gClientUpgrades[client][i]);
	}
}


void RefundAllUpgrades(int client) {
	gClientSpentMoney[client] = 0;
	for(int i; i < U_COUNT; i++) {
		gClientUpgrades[client][i] = 0;
	}
	RecalcSpentMoney(client);
	ResetClientAttributes(client);
}

void SetClientUpgrade(int client, int upgrade, int number) {
	int parent = gUpgradeParent[upgrade];
	gClientUpgrades[client][upgrade] = number;
	gClientUpgrades[client][parent] = 0;
	ApplyUpgradeAttributes(client, upgrade);
	
	int count = gUpgradeCount[parent];
	for(int i; i < count; i++) {
		gClientUpgrades[client][parent] += gClientUpgrades[client][gUpgradeItems[parent][i]];
	}
}

int TryBuyUpgrade(int client, int upgrade, int count = 1) {
	if(gUpgradeMenu[upgrade])
		return 0;
		
	if(!CanBuyUpgrades(client))
		return Purchase_Spectator;
	
	if(gUpgradeMax[upgrade] && gClientUpgrades[client][upgrade] + count > gUpgradeMax[upgrade]) {
		count = gUpgradeMax[upgrade] - gClientUpgrades[client][upgrade];
		
		if(count <= 0)
			return Purchase_Limited;
	}
	
	int price = GetUpgradePrice(upgrade, gClientUpgrades[client][upgrade], count);
	if(price > gMoney - gClientSpentMoney[client])
		return Purchase_NoMoney;
	
	gClientUpgrades[client][upgrade] += count;
	gClientSpentMoney[client] += price;
	SetClientUpgrade(client, upgrade, gClientUpgrades[client][upgrade]);
	return count;
}


void SaveCheckpoint() {
	PrintToServer("[OpenUpgrades] Saved checkpoint.");
	gMoneyCheckpoint = gMoney;
	for(int client = 1; client <= MaxClients; client++) {
		for(int i; i < U_COUNT; i++) {
			gClientUpgradesCheckpoint[client][i] = gClientUpgrades[client][i];
		}
	}
}


void LoadCheckpoint() {
	PrintToServer("[OpenUpgrades] Loaded checkpoint.");
	gMoney = gMoneyCheckpoint;
	for(int client = 1; client <= MaxClients; client++) {
		RefundAllUpgrades(client);
		for(int i; i < U_COUNT; i++) {
			if(!gUpgradeMenu[i] && gClientUpgradesCheckpoint[client][i])
				TryBuyUpgrade(client, i, gClientUpgradesCheckpoint[client][i]);
		}
		
		if(IsClientInGame(client) && !IsFakeClient(client)) {
			ShowUpgradeMenu(client, 0);
		}
	}
}


bool CanAccessUpgrade(int client, int upgrade) {
	
	if(!gUpgradeFilterClass[upgrade][TF2_GetPlayerClass(client)]){
		return false;
	}
	
	int wpn_count = gUpgradeFilterWeaponCount[upgrade];
	if(wpn_count) {
		if(gUpgradeFilterWeaponMode[upgrade]) {
			//blacklist mode
			for(int i; i < wpn_count; i++) {
				for(int j; j < 3; j++) {
					if(gClientWeapons[client][j] == gUpgradeFilterWeapons[upgrade][i])
						return false;
				}
			}
			return true;
		} else {
			//whitelist mode
			for(int i; i < wpn_count; i++) {
				for(int j; j < 3; j++) {
					if(gClientWeapons[client][j] == gUpgradeFilterWeapons[upgrade][i])
						return true;
				}
			}
			return false;
		}
	}
	return true;
}

bool CanSelectUpgrade(int client, int upgrade, bool menu_is_true = true) {
	if(!gUpgradeMax[upgrade])
		return true;
		
	if(menu_is_true && gUpgradeMenu[upgrade])
		return true;
		
	if(gClientUpgrades[client][upgrade] >= gUpgradeMax[upgrade])
		return false;
		
	if (gUpgradeShared[upgrade])
		return CanSelectUpgrade(client, gUpgradeParent[upgrade], false);
		
	return true;
	
}


void GetUpgradeString(int client, int upgrade, char[] string, int maxlen, int count = 1) {
	if(gUpgradeMenu[upgrade]) {
		strcopy(string, maxlen, gUpgradeName[upgrade]);
		return;
	}
	char str[128];
	
	Format(string, maxlen, "$%i %s", 
	GetUpgradePrice(upgrade, gClientUpgrades[client][upgrade], count), 
	gUpgradeName[upgrade]
	);
	
	if(count != 1) {
		Format(string, maxlen, "%s x%i", string, count);
	}
	
	Format(
		str, sizeof(str), 
		"\n%s%i%s (%i%s)", 
		gUpgradeDisplayValue[upgrade] >= 0 ? "+" : "", 
		gUpgradeDisplayValue[upgrade] * count, 
		gUpgradeDisplayMode[upgrade] == 0 ? "" : "%",
		gUpgradeDisplayValue[upgrade] * gClientUpgrades[client][upgrade] + gUpgradeDisplayStart[upgrade],
		gUpgradeDisplayMode[upgrade] == 0 ? "" : "%"
	);
	StrCat(string, maxlen, str);
	if(gUpgradeMax[upgrade]) {
		Format(str, sizeof(str), " %i / %i", gClientUpgrades[client][upgrade], gUpgradeMax[upgrade]);
		StrCat(string, maxlen, str);
	}
}

void ShowUpgradeMenu(int client, int node, int bcount = -1) {
	OU_SetCustomAttribute(client, C_USED_MENU, 1.0);
	gClientNode[client] = node;
	Menu menu = new Menu(MenuCallback);
	gActiveMenu[client] = menu;
	char title[1024];
	char str[8];
	menu.SetTitle("$%i - %s", gMoney - gClientSpentMoney[client], gUpgradeName[node]);
	int count = gUpgradeCount[node];
	int item;
	
	if(bcount == -1) {
		if (GetClientButtons(client) & IN_DUCK) {
		bcount = 10;
		} else {
			bcount = 1;
		}
	}
	int ucount;
	for(int i; i < count; i++) {
		item = gUpgradeItems[node][i];
		if(!CanAccessUpgrade(client, item)) {
			continue;
		}
		IntToString(item, str, sizeof(str));
		
		
		ucount = bcount;
		
		if(gUpgradeMax[item] && ucount + gClientUpgrades[client][item] > gUpgradeMax[item]) {
			ucount = gUpgradeMax[item] - gClientUpgrades[client][item];
		}
		
		if(ucount <= 1)
			ucount = 1;
		
		GetUpgradeString(client, item, title, sizeof(title), ucount);
		menu.AddItem(str, title, CanSelectUpgrade(client, item) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	
	menu.ExitBackButton = !!node;
	menu.Display(client, MENU_TIME_FOREVER);
}


public int MenuCallback(Menu menu, MenuAction action, int param1, int param2){
	switch (action) {
		case MenuAction_Select: {
			char cmd[8];
			menu.GetItem(param2, cmd, 8);
			int c = StringToInt(cmd);
			if(gUpgradeMenu[c]) {
				gClientNode[param1] = c;
			} else {
				int count = GetClientButtons(param1) & IN_DUCK ? 10 : 1;
				int result = TryBuyUpgrade(param1, c, count);
				if(result == Purchase_NoMoney) {
					PrintToChat(param1, "[OpenUpgrades] Not enough money!");
				} else if (result == Purchase_Limited) {
					PrintToChat(param1, "[OpenUpgrades] This upgrade is maxed out!");
				} else if(result == Purchase_Spectator) {
					PrintToChat(param1, "[OpenUpgrades] Can't buy upgrades in spectator!");
				}
			}
			
			ShowUpgradeMenu(param1, gClientNode[param1]);
		}
		
		case MenuAction_Cancel: {
			if (param2 == -6) {
				ShowUpgradeMenu(param1, gUpgradeParent[gClientNode[param1]]);
			}
		}
		
		
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}


