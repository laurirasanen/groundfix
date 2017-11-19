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

public Plugin myinfo = 
{ 
    name = "rampbugfix", 
    author = "Larry", 
    description = "ramp fix", 
    version = "2.0.2", 
    url = "http://steamcommunity.com/id/pancakelarry" 
}; 

ConVar g_hRampbugFixEnable;
bool   g_bRampbugFixEnable;

float clientRampAngle[MAXPLAYERS];
float newVel[MAXPLAYERS][3];

bool clientHasNewVel[MAXPLAYERS];
bool clientRampProjectionBool[MAXPLAYERS];

float prevNormal[3];
float currentNormal[3];


public OnPluginStart()
{
	g_hRampbugFixEnable = CreateConVar("rampbugfix_enable", "1", "Enables rampbug fix.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	HookConVarChange(g_hRampbugFixEnable, OnEnableRampbugFixChanged);	
}

public void OnConfigsExecuted()
{
	g_bRampbugFixEnable = GetConVarBool(g_hRampbugFixEnable);
}

public OnEnableRampbugFixChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bRampbugFixEnable = StringToInt(newValue) == 1 ? true : false;
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	// Don't return players or player projectiles or same ramp twice
	new entity_owner;
	entity_owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	
	if(entity != data && !(0 < entity <= MaxClients) && !(0 < entity_owner <= MaxClients))
	{
		return true;
	}
	return false;	
}

public Action ResetRampProjection(Handle timer, int client)
{
	clientRampProjectionBool[client] = false;
}

float ClipVelocity(float[3] vVelocity, float[3] normal, int client)
{
	clientRampAngle[client] = normal[2];

	float backoff;
	float change;

	// Determine how far along plane to slide based on incoming direction.
	backoff = GetVectorDotProduct(vVelocity, normal);

	for(int i=0; i<3; i++)
	{
		change = normal[i]*backoff;
		newVel[client][i] = vVelocity[i] - change;
	}

	// iterate once to make sure we aren't still moving through the plane
	float adjust = GetVectorDotProduct(newVel[client], normal);
	if(adjust < 0.0)
	{
		for(int i=0; i<3; i++)
		{
			newVel[client][i] -= normal[i]*adjust;
		}						
	}
}

// Redirect player velocity parallel to ramp before we hit it
void RedirectClientVel(int client)
{
	// Redirect velocity before player hits ramp
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

	newVel[client] = vVelocity;

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

		prevNormal = vPlane;
			
		CloseHandle(traceHull);
		closed = true;
		
		// check bunch of crap
		if((FloatAbs(clientRampAngle[client]-vPlane[2]) > 0.001 || !clientRampProjectionBool[client]) && GetVectorDotProduct(newVel[client], vPlane) < 0.0 && GetVectorDotProduct(newVel[client], vRampSurfaceDir) > 0.0 && vPos[2] - vRealEndPos[2] < 2.0 && 0 < vPlane[2] < 1)
		{
			ClipVelocity(newVel[client], vPlane, client);
			clientHasNewVel[client] = true;

			// start cooldown timer
			clientRampProjectionBool[client] = true;
			CreateTimer(1.0, ResetRampProjection, client);

		}
	}
	if(!closed)
	{
		CloseHandle(traceHull);
		closed = true;
	}
	
	// set player velocity
	if(clientHasNewVel[client])
	{
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, newVel[client]);
		clientHasNewVel[client] = false;
	}
	
	// reset stuff
	for(int k=0; k < 3; k++)
	{		
		newVel[client][k] = 0.0;
		currentNormal[k] = 0.0;
		prevNormal[k] = 0.0;
	}
}

// Check if player is clipping into a plane
void UnstuckClientFeet(int client)
{
	float vPos[3], vEndPos[3], vMins[3], vMaxs[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", vPos);
	GetEntPropVector(client, Prop_Send, "m_vecMins", vMins);
	GetEntPropVector(client, Prop_Send, "m_vecMaxs", vMaxs);

	vEndPos[0] = vPos[0];
	vEndPos[1] = vPos[1];
	vEndPos[2] = vPos[2] + 1.0;
	
	// Make hull into a flat plane rather than a box
	vMaxs[2] = vMins[2];

	// Check if players feet are clipping into a surface
	// (TraceHull upwards from bottom of player bounds)		
	new Handle:trace = TR_TraceHullFilterEx(vPos, vEndPos, vMins, vMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceRayDontHitSelf, client);
	
	if(TR_DidHit(trace))
	{
		// Teleport player upwards by 1 unit
		vPos[2] += 1.0;
		TeleportEntity(client, vPos, NULL_VECTOR, NULL_VECTOR);
	}
	CloseHandle(trace);
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

		UnstuckClientFeet(i);
		RedirectClientVel(i);		
	}
}