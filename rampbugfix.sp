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
    author = "Larry + insane help from nolem", 
    description = "ramp fix", 
    version = "1.0.1", 
    url = "http://steamcommunity.com/id/pancakelarry" 
}; 


ConVar g_hRampbugFixEnable;
bool   g_bRampbugFixEnable;
ConVar g_hRampbugFixSpeed;
float   g_bRampbugFixSpeed;

float clientRampAngle[MAXPLAYERS];
float newVel[MAXPLAYERS][3];

bool clientHasNewVel[MAXPLAYERS];
bool clientRampProjectionBool[MAXPLAYERS];

float prevNormal[4][3];
float currentNormal[3];

int hitCount[MAXPLAYERS];
int maxHit[MAXPLAYERS];


public OnPluginStart()
{
	g_hRampbugFixEnable = CreateConVar("rampbugfix_enable", "1", "Enables rampbug fix.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hRampbugFixSpeed = CreateConVar("rampbugfix_speed", "300", "Rampslide fix speed.", FCVAR_NOTIFY, true, 1.0, true, 3500.0);
	
	HookConVarChange(g_hRampbugFixEnable, OnEnableRampbugFixChanged);
	HookConVarChange(g_hRampbugFixSpeed, OnEnableRampbugFixSpeedChanged);	
}

public void OnConfigsExecuted()
{
	g_bRampbugFixEnable = GetConVarBool(g_hRampbugFixEnable);
	g_bRampbugFixSpeed = GetConVarFloat(g_hRampbugFixSpeed);
}

public OnEnableRampbugFixChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bRampbugFixEnable = StringToInt(newValue) == 1 ? true : false;
}

public OnEnableRampbugFixSpeedChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bRampbugFixSpeed = StringToFloat(newValue);
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	// Don't return players or player projectiles or same ramp twice
	// FIXME : returns the same surface multiple times
	// doesn't fix V shaped ramps where you hit multiple surfaces simultaneously, such as the very bad one on jump_it_final
	new entity_owner;
	entity_owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	
	if(entity != data && !(0 < entity <= MaxClients) && !(0 < entity_owner <= MaxClients))
	{
		hitCount[data]++;
		if(hitCount[data] > maxHit[data])
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

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{	
	float vVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);

	if(g_bRampbugFixEnable && TF2_GetClientTeam(client) != TFTeam_Spectator && TF2_GetClientTeam(client) != TFTeam_Unassigned && TF2_GetPlayerClass(client) != TFClass_Unknown && GetEntityMoveType(client) != MOVETYPE_NOCLIP)
	{
		// Set origin bounds for hull trace
		float vPos[3];
		GetEntPropVector(client, Prop_Data, "m_vecOrigin", vPos);

		float vMins[3];
		GetEntPropVector(client, Prop_Send, "m_vecMins", vMins);

		float vMaxs[3];
		GetEntPropVector(client, Prop_Send, "m_vecMaxs", vMaxs);
		
		// End position for trace
		float vEndPos[3];				
		vEndPos[0] = vPos[0];
		vEndPos[1] = vPos[1];
		vEndPos[2] = vPos[2] - 10000;

		newVel[client] = vVelocity;

		maxHit[client] = -1;
		// Loop for up to 4 planes
		for(int j = 0; j<4; j++)
		{
			hitCount[client] = 0;
			maxHit[client]++;

			new Handle:trace = TR_TraceHullFilterEx(vPos, vEndPos, vMins, vMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceRayDontHitSelf, client);
			if(TR_DidHit(trace))
			{

				// Gets the normal vector of the surface under the player
				float vPlane[3], vRealEndPos[3];
				TR_GetPlaneNormal(trace, vPlane);

				// Gets the trace collision point directly below player
				TR_GetEndPosition(vRealEndPos, trace);

				prevNormal[j] = vPlane;
					
				CloseHandle(trace);
				
				// some ramps have very small differences in angle, check if larger than 0.001 to trigger again
				if(FloatAbs(clientRampAngle[client]-vPlane[2]) > 0.001 && GetVectorDotProduct(newVel[client], vPlane) < 0.0 && vPos[2] - vRealEndPos[2] < 3.0 && 0 < vPlane[2] < 1 && SquareRoot( Pow(vVelocity[0],2.0) + Pow(vVelocity[1],2.0) ) > g_bRampbugFixSpeed)
				{
					ClipVelocity(newVel[client], vPlane, client);
					clientHasNewVel[client] = true;

					// start cooldown timer
					clientRampProjectionBool[client] = true;
					CreateTimer(1.0, ResetRampProjection, client);
					/*if(j==0)
					{
						CPrintToChatAll("[{green}RBFix{default}] tick");
					}
					CPrintToChatAll("[{green}RBFix{default}] hit normal x: %f, y: %f, z: %f", prevNormal[j][0],prevNormal[j][1],prevNormal[j][2]);*/
				}
			}
			CloseHandle(trace);
		}
		
		// set player velocity
		if(clientHasNewVel[client])
		{
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, newVel[client]);
			clientHasNewVel[client] = false;
		}
		
		// reset entity filter and newVel
		for(int k=0; k < 3; k++)
		{
			for(int l=0; l<2; l++)
			{
				prevNormal[k][l] = 0.0;
			}			
			newVel[client][k] = 0.0;
		}
		for(int x=0; x<2; x++)
		{
			currentNormal[x] = 0.0;
		}
	}
}