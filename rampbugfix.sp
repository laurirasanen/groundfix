#pragma semicolon 1 

#include <sourcemod> 
#include <sdktools>
#include <sdktools_trace>
#include <tf2_stocks>
#include <tf2>
#include <morecolors>

public Plugin myinfo = 
{ 
    name = "rampbugfix",
    author = "Larry", 
    description = "ramp bug fix", 
    version = "2.0.0", 
    url = "http://steamcommunity.com/id/pancakelarry" 
}; 


ConVar g_hRampbugFixEnable;
bool   g_bRampbugFixEnable;
ConVar g_hRampbugFixNotify;
bool   g_bRampbugFixNotify;

public OnPluginStart()
{
	g_hRampbugFixEnable = CreateConVar("rampbugfix_enable", "1", "Enables ramp bug fix.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hRampbugFixNotify = CreateConVar("rampbugfix_notify", "1", "Notifies player when a ramp bug is prevented.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	HookConVarChange(g_hRampbugFixEnable, OnEnableRampbugFixChanged);
	HookConVarChange(g_hRampbugFixNotify, OnEnableRampbugFixNotifyChanged);
}

public void OnConfigsExecuted()
{
	g_bRampbugFixEnable = GetConVarBool(g_hRampbugFixEnable);
	g_bRampbugFixNotify = GetConVarBool(g_hRampbugFixNotify);
}

public OnEnableRampbugFixChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bRampbugFixEnable = StringToInt(newValue) == 1 ? true : false;
}
public OnEnableRampbugFixNotifyChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bRampbugFixNotify = StringToInt(newValue) == 1 ? true : false;
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	// Don't return entity itself, it's owner (if entity is stickybomb for example), or player entities
	new entity_owner;
	entity_owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	
	if(entity != data && !(0 < entity <= MaxClients) && !(0 < entity_owner <= MaxClients))
	{
		return true;
	}
	return false;	
}

public void OnGameFrame()
{
	if(!g_bRampbugFixEnable)
			return;
	for(new i = 1; i <= MaxClients; i++)
	{		
		if(!IsClientInGame(i))
			continue;
		if(TF2_GetClientTeam(i) == TFTeam_Spectator || TF2_GetClientTeam(i) == TFTeam_Unassigned || GetEntityMoveType(i) == MOVETYPE_NOCLIP || !IsPlayerAlive(i))
			continue;

		float vPos[3], vEndPos[3], vMins[3], vMaxs[3];
		GetEntPropVector(i, Prop_Data, "m_vecAbsOrigin", vPos);
		GetEntPropVector(i, Prop_Send, "m_vecMins", vMins);
		GetEntPropVector(i, Prop_Send, "m_vecMaxs", vMaxs);

		vEndPos[0] = vPos[0];
		vEndPos[1] = vPos[1];
		vEndPos[2] = vPos[2] + 1.0;
		
		// Make hull into a flat plane rather than a box
		vMaxs[2] = vMins[2];

		// Check if players feet are clipping into a surface
		// (TraceHull upwards from bottom of player bounds)
		new Handle:trace = TR_TraceHullFilterEx(vPos, vEndPos, vMins, vMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceRayDontHitSelf, i);
		
		if(TR_DidHit(trace))
		{
			// Teleport player upwards by 1 unit
			vPos[2] += 1.0;
			TeleportEntity(i, vPos, NULL_VECTOR, NULL_VECTOR);

			if(g_bRampbugFixNotify)
				CPrintToChat(i, "[{green}rampbugfix{default}] {blueviolet}~Woosh~{default} You've just been saved from a ramp bug");
		}
		CloseHandle(trace);
	}
}