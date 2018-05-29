// Plugin for TF2 to fix inconsistencies with ramps

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdktools_trace>
#include <tf2_stocks>
#include <tf2>
#include <morecolors>
#include <entity_prop_stocks>
#include <timers>
#include <sdkhooks>


public Plugin myinfo =
{
	name = "rampbugfix",
	author = "Larry",
	description = "ramp fix",
	version = "3.0.0",
	url = "http://steamcommunity.com/id/pancakelarry"
};

bool TakeDamage[MAXPLAYERS];


public OnPluginStart() {
	// late load
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client)) {
			OnClientPutInServer(client);
		}
	}
}

public OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_PostThink, Hook_Client_PostThinkPost);
}

public OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKUnhook(client, SDKHook_PostThink, Hook_Client_PostThinkPost);
}

public Action Hook_Client_PostThinkPost(int client)
{
	if(TF2_GetClientTeam(client) == TFTeam_Spectator
		|| TF2_GetClientTeam(client) == TFTeam_Unassigned
		|| !(TF2_GetPlayerClass(client) == TFClass_Soldier
		|| TF2_GetPlayerClass(client) == TFClass_DemoMan)
		|| GetEntityMoveType(client) == MOVETYPE_NOCLIP
		|| !IsPlayerAlive(client))
			return;
	SetClientGroundEntity(client);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	TakeDamage[victim] = true;
	return Plugin_Continue;
}

// Redirect player velocity parallel to ramp before we hit it
void SetClientGroundEntity(int client)
{
	// Client props
	float vVelocity[3], vPos[3], vMins[3], vMaxs[3], vEndPos[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);

	// Set origin bounds for hull trace
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", vPos);
	GetEntPropVector(client, Prop_Send, "m_vecMins", vMins);
	GetEntPropVector(client, Prop_Send, "m_vecMaxs", vMaxs);

	// End position for trace
	vEndPos[0] = vPos[0];
	vEndPos[1] = vPos[1];
	vEndPos[2] = vPos[2] - 3.0;

	new Handle:traceHull = TR_TraceHullFilterEx(vPos, vEndPos, vMins, vMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceRayDontHitSelf, client);
	bool closed = false;
	if(TR_DidHit(traceHull))
	{

		// Gets the normal vector of the surface under the player
		float vPlane[3], vRealEndPos[3];
		TR_GetPlaneNormal(traceHull, vPlane);

		// Ingore upside-down ramps
		if(vPlane[2] <= 0.0)
			return;

		// Calculate direction of ramps surface
		float vRampSurfaceDir[3];
		vRampSurfaceDir[0] = -vPlane[0];
		vRampSurfaceDir[1] = -vPlane[1];

		// HACK: insides of SquareRoots should not be negative but somehow they sometimes are..
		if(1-Pow(vPlane[2], 2.0) < 0 || Pow(vRampSurfaceDir[0], 2.0) + Pow(vRampSurfaceDir[1], 2.0) < 0)
		{
			CloseHandle(traceHull);
			return;
		}

		if(vPlane[2] > 0.0)
		{
			vRampSurfaceDir[2] = SquareRoot((1-Pow(vPlane[2], 2.0))/vPlane[2])*(SquareRoot(Pow(vRampSurfaceDir[0], 2.0) + Pow(vRampSurfaceDir[1], 2.0)));
		}

		// Gets the traceHull collision point directly below player
		TR_GetEndPosition(vRealEndPos, traceHull);

		// check bunch of crap
		// Remove friction if going up a ramp and horizontal velocity > 300
		// Maybe this would also work for surfing along ramps horizontally, instead of just rampbugs going up a ramp?
		// Would need to check if ramp angle is high enough to slide along (angle > 45 degrees (vPlane < 0.7))
		if(GetEntPropEnt(client, Prop_Data, "m_hGroundEntity") != -1 && GetVectorDotProduct(vVelocity, vPlane) < 0.0 && GetVectorDotProduct(vVelocity, vRampSurfaceDir) > 0.0 && vPos[2] - vRealEndPos[2] < 2.0 && 0 < vPlane[2] < 1 && SquareRoot( Pow(vVelocity[0],2.0) + Pow(vVelocity[1],2.0) ) > 300.0)
		{
			SetEntPropEnt(client, Prop_Data, "m_hGroundEntity", -1);
		}

		CloseHandle(traceHull);
		closed = true;
	}
	// Close handle if trace didn't hit anything
	if(!closed)
	{
		CloseHandle(traceHull);
		closed = true;
	}
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	// Don't return players or player projectiles
	new entity_owner;
	entity_owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");

	if(entity != data && !(0 < entity <= MaxClients) && !(0 < entity_owner <= MaxClients))
	{
		return true;
	}
	return false;
}
