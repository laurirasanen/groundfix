// Plugin for TF2 to fix rampbugs and slides in rocket jumping
// Based on mev's surf bug fix plugin: https://forums.alliedmods.net/showthread.php?t=277523

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
    description = "rampbug fix for jumping", 
    version = "1.0.0", 
    url = "http://steamcommunity.com/id/pancakelarry" 
}; 


ConVar g_hRampbugFixEnable;
bool   g_bRampbugFixEnable;
ConVar g_hRampslideFixEnable;
bool   g_bRampslideFixEnable;
ConVar g_hRampslideFixSpeed;
float   g_bRampslideFixSpeed;

float vOldVelocity[64][3];
bool ClientRampProjectionBool[64];


public OnPluginStart()
{
	g_hRampbugFixEnable = CreateConVar("rampbugfix_enable", "1", "Enables rampbug fix.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hRampslideFixEnable = CreateConVar("rampslidefix_enable", "1", "Enables rampslide fix.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hRampslideFixSpeed = CreateConVar("rampslidefix_speed", "300", "Rampslide fix speed.", FCVAR_NOTIFY, true, 1.0, true, 3500.0);
	
	HookConVarChange(g_hRampbugFixEnable, OnEnableRampbugFixChanged);
	HookConVarChange(g_hRampslideFixEnable, OnEnableRampslideFixChanged);
	HookConVarChange(g_hRampslideFixSpeed, OnEnableRampslideFixSpeedChanged);
	
}

public void OnConfigsExecuted()
{
	g_bRampbugFixEnable = GetConVarBool(g_hRampbugFixEnable);
	g_bRampslideFixEnable = GetConVarBool(g_hRampslideFixEnable);
	g_bRampslideFixSpeed = GetConVarFloat(g_hRampslideFixSpeed);
}

public OnEnableRampbugFixChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bRampbugFixEnable = StringToInt(newValue) == 1 ? true : false;
}

public OnEnableRampslideFixChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bRampslideFixEnable = StringToInt(newValue) == 1 ? true : false;
}

public OnEnableRampslideFixSpeedChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bRampslideFixSpeed = StringToFloat(newValue);
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	// Don't return players or player projectiles
	new entity_owner;
	entity_owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	return entity != data && !(0 < entity <= MaxClients) && !(0 < entity_owner <= MaxClients);
}

public Action ResetRampProjection(Handle timer, int client)
{
	ClientRampProjectionBool[client] = false;
}

public OnGameFrame()
{	
	int client = 1;
	for(new i = 1; i<MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i)) 
		{
			client = i;

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
		
				// Reduce horizontal bounds by one unit to prevent trace from hitting walls
				vMins[0] += 1.0;
				vMins[1] += 1.0;
				vMaxs[0] -= 1.0;
				vMaxs[1] -= 1.0;

				// End position for trace
				float vEndPos[3];				
				vEndPos[0] = vPos[0];
				vEndPos[1] = vPos[1];
				vEndPos[2] = vPos[2] - 10000;
				
				TR_TraceHullFilter(vPos, vEndPos, vMins, vMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceRayDontHitSelf, client);
				if(TR_DidHit())
				{

					// Gets the normal vector of the surface under the player
					float vPlane[3], vRealEndPos[3];
					TR_GetPlaneNormal(INVALID_HANDLE, vPlane);

					// Gets the trace collision point directly below player
					TR_GetEndPosition(vRealEndPos);
					
					// BROKEN? doesn't seem to ever trigger | vPos[2] - vRealEndPos[2] seems to be 0.20 when standing on a shallow ramp, 0.50ish on steeper ramps, 1.00 very steep ramp or flat ground 
					// Fix for 'real' rampbugs
					// Detects if player is inside a ramp and if so teleports player upwards by 1 unit.
					// vPlane[2] = z value of normal vector
					// 0 = wall (90°) | 1 = level floor (0°) | 0.5-0.99 ~ 60°-8.11° 
					if(0.5 < vPlane[2] < 0.99 && vPos[2] - vRealEndPos[2] < 0.0)
					{
						// Player was stuck, lets put him back on the ramp
						TeleportEntity(client, vRealEndPos, NULL_VECTOR, NULL_VECTOR);
						decl String:nick[64];
						if(GetClientName(client, nick, sizeof(nick)))
							CPrintToChatAll("Prevented rampbug on {blue}%s{default}", nick);
					}

			   /* OLD CODE
				*	
				*	// Fix for when you random-ishly stop sliding up a ramp
				*	// Enable with 'sm_cvar rampslidefix_enable 1'
				*	// Detects if player is on a ramp and slows down by g_bRampslideFixSpeed u/s in a single tick,
				*	// if so, teleport player upwards by 25u and set velocity back to what it was previously.
				*	// Could be considered a bit of a cheat on some maps.
				*	// Doesn't work well on ramps that are too shallow.
				*	// 0.5-0.95 ~ 60°-18.19° 
				*	if(g_bRampslideFixEnable)
				*	{
				*		if(0.5 < vPlane[2] < 0.95 && !(vPos[2] - vRealEndPos[2] < -0.025) && (SquareRoot(Pow(vOldVelocity[client][0], 2.0) + Pow(vOldVelocity[client][1], 2.0))) - SquareRoot((Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0))) > 700)
				*		{
				*			// Player lost speed too fast, setting velocity to what it was before
				*			// Teleport player 25 units up, for some reason lower values don't seem to work unless you increase players horizontal speed massively
				*			vRealEndPos[2] += 25.0;
				*			float vTempVel[3];
				*			//vTempVel[0] = vOldVelocity[client][0]*(1-vPlane[2])*1.9;
				*			//vTempVel[1] = vOldVelocity[client][1]*(1-vPlane[2])*1.9;
				*			vTempVel[0] = vOldVelocity[client][0];
				*			vTempVel[1] = vOldVelocity[client][1];
				*			vTempVel[2] = vOldVelocity[client][2];
				*			// Set vertical velocity to 0 if going down
				*			if(vTempVel[2] < 0.0)
				*				vTempVel[2] = 0.0;
				*
				*			//vTempVel[2] = (1-vPlane[2])*50.0;
				*			TeleportEntity(client, vRealEndPos, NULL_VECTOR, vTempVel);
				*			decl String:nick[64];
				*			if(GetClientName(client, nick, sizeof(nick)))
				*				CPrintToChatAll("[{green}RBFix{default}] Prevented slidebug on {blue}%s{default}", nick);
				*		}
				*	}
				*/
					
					// Check if on a ramp and this loop hasn't been done for client in the past 1 second and is moving faster than 300u/s
					if(g_bRampslideFixEnable && 0.5 < vPlane[2] < 0.95 && !ClientRampProjectionBool[client] && vPos[2] - vRealEndPos[2] < 1.0 && SquareRoot(Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0)) > g_bRampslideFixSpeed)
					{

						// Get direction of ramp (opposite direction of surface normal x,y)
						float vRampDir[3];
						vRampDir[0] = -vPlane[0];
						vRampDir[1] = -vPlane[1];
						vRampDir[2] = 0.0;
						
						// Normalize ramp direction vector so it is always greater than player horizontal velocity (so that projecting player velocity on it will not clamp)
						// max velocity 3500 on x and y axis:
						// sqrt(3500^2+3500^2) ~4990 total horizontal

						NormalizeVector(vRampDir, vRampDir);
						vRampDir[0] *= 5000.0;
						vRampDir[1] *= 5000.0;

						// Get dot product of player velocity and ramp direction
						float vDot = GetVectorDotProduct(vVelocity, vRampDir);

						// Make sure the ramp is facing the same direction we are moving in (prevents weird bouncing going down a ramp)
						if(vDot > 0)
						{
							// Projecting player velocity to direction vector
							float vLength = GetVectorLength(vRampDir);
							float projMultiplier = vDot/Pow(vLength, 2.0);

							// Calculate player velocity
							float vProjVelocity[3];					
							vProjVelocity[0] = vRampDir[0]*projMultiplier;
							vProjVelocity[1] = vRampDir[1]*projMultiplier;

							// Trigonometry magic - Get vertical velocity based on horizontal velocity and angle of ramp
							vProjVelocity[2] = SquareRoot((1-Pow(vPlane[2], 2.0))/vPlane[2])*(SquareRoot(Pow(vProjVelocity[0], 2.0) + Pow(vProjVelocity[1], 2.0)));

							// Clamp projected velocity to length of original velocity
							NormalizeVector(vProjVelocity, vProjVelocity);
							vVelocity[2] = 0.0;
							ScaleVector(vProjVelocity, GetVectorLength(vVelocity));

							// If ramp is aligned on y-axis (vPlane[0] = 0.0) projected velocity on x-axis will be 0.0 and vise versa (hitting a ramp on y-axis would set your x-axis velocity to 0)
							// Not sure yet if this approach works on ramps that aren't lined up with x- or y-axis yet.
							if(FloatAbs(vProjVelocity[0]) < 1.0)
							{
								vProjVelocity[0] = vVelocity[0];
							}
							if(FloatAbs(vProjVelocity[1]) < 1.0)
							{
								vProjVelocity[1] = vVelocity[1];
							}						

							// Teleport up by 1u and set player velocity
							vRealEndPos[2] += 1.0;
							TeleportEntity(client, vRealEndPos, NULL_VECTOR, vProjVelocity);
							
							decl String:nick[64];
							if(GetClientName(client, nick, sizeof(nick)))
							{
								//CPrintToChatAll("[{green}RBFix{default}] Set ProjVel on {blue}%s{default}", nick);
								//CPrintToChatAll("[{green}RBFix{default}] AFTER x: %f , y: %f , z: %f ", vProjVelocity[0], vProjVelocity[1], vProjVelocity[2]);
							}

							// Start cooldown timer
							ClientRampProjectionBool[client] = true;
							CreateTimer(1.0, ResetRampProjection, client);
						}
						
					}

						
				}
			}
			// Save client velocity from this tick for later use
			vOldVelocity[client][0] = vVelocity[0];
			vOldVelocity[client][1] = vVelocity[1];
			vOldVelocity[client][2] = vVelocity[2];
		}
	}
}