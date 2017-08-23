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
float vOldPos[64][3];
int triggerCount[64];
bool ClientRampProjectionBool[64];
float clientRampAngle[64];


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
	triggerCount[client] = 0;
}

//
//
//public OnGameFrame()
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{	
	//for(int i = 1; i<MaxClients; i++)
	//{
		//int client = i;
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
			/*
			vMins[0] += 1.0;
			vMins[1] += 1.0;
			vMaxs[0] -= 1.0;
			vMaxs[1] -= 1.0;
			*/
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

				//int entity;
				//TR_GetEntityIndex(entity);

				/*
				// Fix for 'real' rampbugs
				// Detects if player is inside a ramp and if so teleports player upwards by 1 unit.
				// vPlane[2] = z value of normal vector
				// 0 = wall (90°) | 1 = level floor (0°) | 0.5-0.99 ~ 60°-8.11° 
				if(vPos[2] - vRealEndPos[2] < 0.0)
					CPrintToChatAll("vPos[2] - vRealEndPos[2] = %f", vPos[2] - vRealEndPos[2]);
				if(0.5 < vPlane[2] < 0.99 && vPos[2] - vRealEndPos[2] < -0.025)
				{
					// Player was stuck, lets put him back on the ramp
					TeleportEntity(client, vRealEndPos, NULL_VECTOR, vOldVelocity[client]);
					decl String:nick[64];
					if(GetClientName(client, nick, sizeof(nick)))
						CPrintToChatAll("Prevented rampbug on {blue}%s{default}", nick);
				}
				*/
			/*			
				// Fix for when you random-ishly stop sliding up a ramp
				// Enable with 'sm_cvar rampslidefix_enable 1'
				// Detects if player is on a ramp and slows down by g_bRampslideFixSpeed u/s in a single tick,
				// if so, teleport player upwards by 25u and set velocity back to what it was previously.
				// Could be considered a bit of a cheat on some maps.
				// Doesn't work well on ramps that are too shallow.
				// 0.5-0.95 ~ 60°-18.19° 
				if(g_bRampslideFixEnable)
				{
					if(0.5 < vPlane[2] < 0.95 && !(vPos[2] - vRealEndPos[2] < -0.025) && (SquareRoot(Pow(vOldVelocity[client][0], 2.0) + Pow(vOldVelocity[client][1], 2.0))) - SquareRoot((Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0))) > g_bRampslideFixSpeed)
					{
						// Player lost speed too fast, setting velocity to what it was before
						// Teleport player 25 units up, for some reason lower values don't seem to work unless you increase players horizontal speed massively
						vRealEndPos[2] += 1.0;
						float vTempVel[3];
						//vTempVel[0] = vOldVelocity[client][0]*(1-vPlane[2])*1.9;
						//vTempVel[1] = vOldVelocity[client][1]*(1-vPlane[2])*1.9;
						vTempVel[0] = vOldVelocity[client][0];
						vTempVel[1] = vOldVelocity[client][1];
						vTempVel[2] = vOldVelocity[client][2];
						// Set vertical velocity to 0 if going down
						if(vTempVel[2] < 0.0)
							vTempVel[2] = 0.0;
			
						//vTempVel[2] = (1-vPlane[2])*50.0;
						TeleportEntity(client, vRealEndPos, NULL_VECTOR, vOldVelocity[client]);
						decl String:nick[64];
						if(GetClientName(client, nick, sizeof(nick)))
							CPrintToChatAll("[{green}RBFix{default}] Prevented slidebug on {blue}%s{default}", nick);
					}
				}
			*/
				// some ramps have very small differences in angle, check if larger than 0.001 to trigger again
				if((clientRampAngle[client]-vPlane[2] > 0.001 || !ClientRampProjectionBool[client]) && vPos[2] - vRealEndPos[2] < 3.0/* - triggerCount[client]*/ && 0 < vPlane[2] < 1 && SquareRoot( Pow(vVelocity[0],2.0) + Pow(vVelocity[1],2.0) ) > 300)
				{
					//CPrintToChatAll("[{green}RBFix{default}] x: %f", 5.0 - triggerCount[client]);
					if(!ClientRampProjectionBool[client])
						CPrintToChatAll("[{green}RBFix{default}] triggered, old angle: %.12f , new angle: %.12f", 0, vPlane[2]);
					else
						CPrintToChatAll("[{green}RBFix{default}] triggered, old angle: %.12f , new angle: %.12f", clientRampAngle[client], vPlane[2]);
					clientRampAngle[client] = vPlane[2];
					//clientEntity[client] = 0;
					float newVel[3];
					float backoff;
					float change;

					// Determine how far along plane to slide based on incoming direction.
					backoff = GetVectorDotProduct(vVelocity, vPlane);

					for(int i=0; i<3; i++)
					{
						change = vPlane[i]*backoff;
						newVel[i] = vVelocity[i] - change;
					}

					// iterate once to make sure we aren't still moving through the plane
					float adjust = GetVectorDotProduct(newVel, vPlane);
					if(adjust < 0.0)
					{
						for(int i=0; i<3; i++)
						{
							newVel[i] -= vPlane[i]*adjust;
						}						
					}

					// set player velocity
					//vPos[2] += 1.0;
					TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, newVel);
					//CPrintToChatAll("[{green}RBFix{default}] set vel");
					// start cooldown timer
					ClientRampProjectionBool[client] = true;
					
					if(triggerCount[client] == 0)
						CreateTimer(1.0, ResetRampProjection, client);
					if(triggerCount[client] < 2)
						triggerCount[client] += 1;
				}
				/*
				if(triggerCount[client] < 3 && (SquareRoot(Pow(vOldVelocity[client][0], 2.0) + Pow(vOldVelocity[client][1], 2.0))) - SquareRoot((Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0))) > g_bRampslideFixSpeed && 0.5 < vPlane[2] < 0.99 && vPos[2] - vRealEndPos[2] < 1.0)
				{
					float vRampDir[3];
					vRampDir[0] = -vPlane[0];
					vRampDir[1] = -vPlane[1];
					// Calculate Z
					//vRampDir[2] = SquareRoot((1-Pow(vPlane[2], 2.0))/vPlane[2])*(SquareRoot(Pow(vRampDir[0], 2.0) + Pow(vRampDir[1], 2.0))); 
					*
					float vTemp[3];
					vTemp[0] = vOldVelocity[client][0];
					vTemp[1] = vOldVelocity[client][1];
					vTemp[2] = 0.0;
					NormalizeVector(vTemp, vTemp);
					vPos[0] -= vTemp[0];
					vPos[1] -= vTemp[1];
					*
					//vRealEndPos[2] += 25.0;
					vOldPos[client][2] += 1.0;
					//vPos[1] += 5.0;
					//vOldVelocity[client][2] = SquareRoot((1-Pow(vPlane[2], 2.0))/vPlane[2])*(SquareRoot(Pow(vOldVelocity[client][0], 2.0) + Pow(vOldVelocity[client][1], 2.0)));
					
					float rotAngle = 0.0;

					if(vOldVelocity[client][0]*vRampDir[1] - vOldVelocity[client][1]*vRampDir[0] <= 0)
					{
						
						rotAngle = ((vOldVelocity[client][0]*vRampDir[1] - vOldVelocity[client][1]*vRampDir[0])/10000);
						if(rotAngle < -1.0*(3.14159/180))
							rotAngle=-1.0*(3.14159/180);
						
						//rotAngle = -1.0*(3.14159/180);
					}
					else
					{
						
						rotAngle = ((vOldVelocity[client][0]*vRampDir[1] - vOldVelocity[client][1]*vRampDir[0])/10000);
						if(rotAngle > 1.0*(3.14159/180))
							rotAngle=1.0*(3.14159/180);
						
						//rotAngle = 1.0*(3.14159/180);
					}
					CPrintToChatAll("[{green}RBFix{default}] Attempt: %i", triggerCount[client]+1);
					//CPrintToChatAll("[{green}RBFix{default}] res: %f", vOldVelocity[client][0]*vRampDir[1] - vOldVelocity[client][1]*vRampDir[0]);
					CPrintToChatAll("[{green}RBFix{default}] rotAngle: %f (%f)", rotAngle, rotAngle*(180/3.14159));
					CPrintToChatAll("[{green}RBFix{default}] old x: %f, y: %f, z: %f", vOldVelocity[client][0],vOldVelocity[client][1],vOldVelocity[client][2]);
					vOldVelocity[client][0] = vOldVelocity[client][0] * Cosine(rotAngle)- vOldVelocity[client][1]*Sine(rotAngle);
					vOldVelocity[client][1] = vOldVelocity[client][0] * Sine(rotAngle)+ vOldVelocity[client][1]*Cosine(rotAngle);
					//vOldVelocity[client][2] += 10.0;
					//vOldVelocity[client][2] = SquareRoot((1-Pow(vPlane[2], 2.0))/vPlane[2])*(SquareRoot(Pow(vOldVelocity[client][0], 2.0) + Pow(vOldVelocity[client][1], 2.0)));
					
					CPrintToChatAll("[{green}RBFix{default}] new: x: %f, y: %f, z: %f", vOldVelocity[client][0],vOldVelocity[client][1],vOldVelocity[client][2]);
					CPrintToChatAll("[{green}RBFix{default}] without fix: x: %f, y: %f, z: %f", vVelocity[0],vVelocity[1],vVelocity[2]);
					TeleportEntity(client, vOldPos[client], NULL_VECTOR, vOldVelocity[client]);
					triggerCount[client] += 1;
					
					
				}
				else
				{
					// Save client velocity from this tick for later use
					if(triggerCount[client] > 0 && !((SquareRoot(Pow(vOldVelocity[client][0], 2.0) + Pow(vOldVelocity[client][1], 2.0))) - SquareRoot((Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0))) > g_bRampslideFixSpeed))
					{
						CPrintToChatAll("[{green}RBFix{default}] saved from rampbug");
					}
					vOldVelocity[client][0] = vVelocity[0];
					vOldVelocity[client][1] = vVelocity[1];
					vOldVelocity[client][2] = vVelocity[2];
					vOldPos[client] = vPos;
					
					triggerCount[client] = 0;
				}
				*/
				/*
				if(false&&g_bRampslideFixEnable && 0.5 < vPlane[2] < 0.99 && !ClientRampProjectionBool[client] && vPos[2] - vRealEndPos[2] < 1.0* && SquareRoot(Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0)) > g_bRampslideFixSpeed*)
				{
					//CPrintToChatAll("[{green}RBFix{default}]normal x: %f, y: %f, z: %f", vPlane[0], vPlane[1], vPlane[2]);
					// Get direction of ramp (opposite direction of surface normal x,y)
					float vRampDir[3];
					vRampDir[0] = -vPlane[0];
					vRampDir[1] = -vPlane[1];

					// Normalize ramp direction vector so it is always greater than player horizontal velocity (so that projecting player velocity on it will not clamp)
					// max velocity 3500 on x and y axis:
					// assuming someone makes a very dumb ramp where normal x or y = 0.0000001 or something..
					NormalizeVector(vRampDir, vRampDir);
					vRampDir[0] *= 10000000000.0;
					vRampDir[1] *= 10000000000.0;
					// Calculate Z from using surface normal
					//vRampDir[2] = SquareRoot((1-Pow(vPlane[2], 2.0))/vPlane[2])*(SquareRoot(Pow(vRampDir[0], 2.0) + Pow(vRampDir[1], 2.0)));

					// Projecting player velocity to direction vector
					float vDot = GetVectorDotProduct(vOldVelocity[client], vRampDir);
					float vLength = GetVectorLength(vRampDir);
					float projMultiplier = vDot/Pow(vLength, 2.0);
			
					// Calculate player velocity
					float vProjVelocity[3];					
					vProjVelocity[0] = vRampDir[0]*projMultiplier*0.85;
					vProjVelocity[1] = vRampDir[1]*projMultiplier*0.85;
					float oldProjVelocityLength = GetVectorLength(vProjVelocity);
					if(vRampDir[0] == 0)
					{
						vProjVelocity[0] = vOldVelocity[client][0];
					}
					if(vRampDir[1] == 0)
					{
						vProjVelocity[1] = vOldVelocity[client][1];
					}
					// Players actual z velocity is needed for calculating angle between velocity and ramp surface
					vProjVelocity[2] = vOldVelocity[client][2];
					
					// Get angle between player velocity vector and ramp surface
					float angle;
					angle = ArcCosine(GetVectorDotProduct(vProjVelocity, vRampDir)/(GetVectorLength(vProjVelocity)*GetVectorLength(vRampDir)));
					//CPrintToChatAll("[{green}RBFix{default}]val: %f", GetVectorDotProduct(vProjVelocity, vRampDir)/(GetVectorLength(vProjVelocity)*GetVectorLength(vRampDir)));
					float rampAngle = SquareRoot((1-Pow(vPlane[2], 2.0))/vPlane[2])*(180/3.14159);
					float attackAngle = angle*(180/3.14159);
					//CPrintToChatAll("[{green}RBFix{default}]angle of ramp: %f", rampAngle);
					//CPrintToChatAll("[{green}RBFix{default}]angle of attack: %f", attackAngle);
					// Change z velocity to projected velocity
					//vProjVelocity[2] = vRampDir[2]*projMultiplier;
					vProjVelocity[2] = SquareRoot((1-Pow(vPlane[2], 2.0))/vPlane[2])*(SquareRoot(Pow(vProjVelocity[0], 2.0) + Pow(vProjVelocity[1], 2.0)));
					oldProjVelocityLength = SquareRoot(Pow(oldProjVelocityLength, 2.0) + Pow(vProjVelocity[2], 2.0));
					//CPrintToChatAll("[{green}RBFix{default}]projected velocity x: %f, y: %f, z: %f", vProjVelocity[0],vProjVelocity[1],vProjVelocity[2]);
					//CPrintToChatAll("[{green}RBFix{default}]projected velocity: %f", GetVectorLength(vProjVelocity));
					bool preventBool = false;
					float preventScale = 0.0;
					//CPrintToChatAll("[{green}RBFix{default}]horizontal velocity change: %.0f (%.0f needed)", SquareRoot(Pow(vOldVelocity[client][0], 2.0) + Pow(vOldVelocity[client][1], 2.0)) - SquareRoot(Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0)), g_bRampslideFixSpeed);
					if(GetVectorLength(vProjVelocity) >= 600.0 && (SquareRoot(Pow(vOldVelocity[client][0], 2.0) + Pow(vOldVelocity[client][1], 2.0))) - SquareRoot((Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0))) > g_bRampslideFixSpeed)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity)/(1/Cosine((rampAngle/180)*3.14159));	
						
						if(preventScale < 16675.0/rampAngle)
							preventScale = 16675.0/rampAngle;
						//CPrintToChatAll("[{green}RBFix{default}]scale: %f", preventScale);
						CPrintToChatAll("[{green}RBFix{default}]horizontal velocity changed by more than %.0fu/s", g_bRampslideFixSpeed);
					}
					
					*
					// Check if proj velocity > 1350 and we lost speed too fast
					if(GetVectorLength(vProjVelocity) >= 1350 && 15 > rampAngle >= 10 /&& (12 > attackAngle > 11 || 7>attackAngle>6)//&& (SquareRoot(Pow(vOldVelocity[client][0], 2.0) + Pow(vOldVelocity[client][1], 2.0))) - SquareRoot((Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0))) > g_bRampslideFixSpeed/)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity);
						if(GetVectorLength(vProjVelocity) < 1450)
							preventScale = 1450.0;
					}
					if(GetVectorLength(vProjVelocity) >= 1250 && 20 > rampAngle >= 15)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity);
						if(GetVectorLength(vProjVelocity) < 1350)
							preventScale = 1350.0;
					}
					if(GetVectorLength(vProjVelocity) >= 1150 && 25 > rampAngle >= 20)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity);
						if(GetVectorLength(vProjVelocity) < 1250)
							preventScale = 1250.0;
					}
					if(1300 > GetVectorLength(vProjVelocity) >= 1050 && 30 > rampAngle >= 25)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity);
						if(GetVectorLength(vProjVelocity) < 1150)
							preventScale = 1150.0;
					}
					if(1250 > GetVectorLength(vProjVelocity) >= 950 && 35 > rampAngle >= 30)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity);
						if(GetVectorLength(vProjVelocity) < 1050)
							preventScale = 1050.0;
					}
					if(1200 > GetVectorLength(vProjVelocity) >= 850 && 40 > rampAngle >= 35)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity);
						if(GetVectorLength(vProjVelocity) < 950)
							preventScale = 950.0;
					}
					if(1150 > GetVectorLength(vProjVelocity) >= 750 && 45 > rampAngle >= 40)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity);
						if(GetVectorLength(vProjVelocity) < 850)
							preventScale = 850.0;
					}
					if(1100 > GetVectorLength(vProjVelocity) >= 650 && 50 > rampAngle >= 45)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity);
						if(GetVectorLength(vProjVelocity) < 750)
							preventScale = 750.0;
					}
					if(1050 > GetVectorLength(vProjVelocity) >= 550 && 55 > rampAngle >= 50)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity);
						if(GetVectorLength(vProjVelocity) < 650)
							preventScale = 650.0;
					}
					if(1000 > GetVectorLength(vProjVelocity) >= 450 && 60 > rampAngle >= 55)
					{
						preventBool = true;
						preventScale = GetVectorLength(vProjVelocity);
						if(GetVectorLength(vProjVelocity) < 550)
							preventScale = 550.0;
					}
					*
					if(preventBool)
					{
						vRealEndPos[2] += 1.0;
						//CPrintToChatAll("[{green}RBFix{default}] BEFORE: x: %f, y: %f, z: %f", vProjVelocity[0],vProjVelocity[1],vProjVelocity[2]);
						*
						if(vProjVelocity[0] != vOldVelocity[client][0])
							vProjVelocity[0] *= 0.90;
						if(vProjVelocity[1] != vOldVelocity[client][1])
							vProjVelocity[1] *= 0.90;
						*
						NormalizeVector(vProjVelocity, vProjVelocity);
						//CPrintToChatAll("[{green}RBFix{default}] MID: x: %f, y: %f, z: %f", vProjVelocity[0],vProjVelocity[1],vProjVelocity[2]);
						//CPrintToChatAll("[{green}RBFix{default}] scale: %f", preventScale);
						ScaleVector(vProjVelocity, preventScale);
						//CPrintToChatAll("[{green}RBFix{default}] AFTER: x: %f, y: %f, z: %f", vProjVelocity[0],vProjVelocity[1],vProjVelocity[2]);
						TeleportEntity(client, vRealEndPos, NULL_VECTOR, vProjVelocity);
						//CPrintToChatAll("[{green}RBFix{default}] Hey I did something");
						decl String:nick[64];
						if(GetClientName(client, nick, sizeof(nick)))
						{
							//CPrintToChatAll("[{green}RBFix{default}] Set ProjVel on {blue}%s{default}", nick);
						}
					}


					// Start cooldown timer
					ClientRampProjectionBool[client] = true;
					CreateTimer(0.1, ResetRampProjection, client);



					/
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
						//vRealEndPos[2] += 1.0;
						TeleportEntity(client, vRealEndPos, NULL_VECTOR, vProjVelocity);
						
						decl String:nick[64];
						if(GetClientName(client, nick, sizeof(nick)))
						{
							//CPrintToChatAll("[{green}RBFix{default}] Set ProjVel on {blue}%s{default}", nick);
							CPrintToChatAll("[{green}RBFix{default}]vVelocity x: %f , y: %f , z: %f ", vVelocity[0], vVelocity[1], vVelocity[2]);
							CPrintToChatAll("[{green}RBFix{default}]vProjVelocity x: %f , y: %f , z: %f ", vProjVelocity[0], vProjVelocity[1], vProjVelocity[2]);
						}
			
						// Start cooldown timer
						ClientRampProjectionBool[client] = true;
						CreateTimer(1.0, ResetRampProjection, client);
					}
					*
				}
				*/
			}
		}
		/*
		// Save client velocity from this tick for later use
		vOldVelocity[client][0] = vVelocity[0];
		vOldVelocity[client][1] = vVelocity[1];
		vOldVelocity[client][2] = vVelocity[2];
		*/
	//}
}