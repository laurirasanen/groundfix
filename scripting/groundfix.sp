// Plugin for TF2 to fix inconsistencies with ground movement
//#define DRAWBEAM_TESTING

#pragma semicolon 1

#include <sourcemod>
#include <dhooks>
#include <sdktools>
#include <halflife>
#if defined DRAWBEAM_TESTING
	#include <smlib>
#endif

#define SND_BANANASLIP "misc/banana_slip.wav"

ConVar g_Cvar_slidefix;
ConVar g_Cvar_edgefix;
ConVar g_Cvar_banana;
ConVar g_Cvar_chat;

public Plugin myinfo =
{
	name = "groundfix",
	author = "jayess + Larry",
	description = "movement fixes for ground bugs",
	version = "3.1.3",
	url = "http://steamcommunity.com/id/jayessZA + http://steamcommunity.com/id/pancakelarry"
};

Handle g_hSetGroundEntityHook;

public void OnPluginStart() {
	Handle hGameData = LoadGameConfigFile("groundfix.games");

	if (!hGameData)
		SetFailState("Missing gamedata!");

	StartPrepSDKCall(SDKCall_Static);
	if(!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CreateInterface"))
	{
		SetFailState("Failed to get CreateInterface");
		CloseHandle(hGameData);
	}

	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);

	char iface[64];
	if(!GameConfGetKeyValue(hGameData, "GameMovementInterface", iface, sizeof(iface)))
	{
		SetFailState("Failed to get game movement interface name");
		CloseHandle(hGameData);
	}

	Handle call = EndPrepSDKCall();
	Address pGameMovement = SDKCall(call, iface, 0);
	CloseHandle(call);

	if(!pGameMovement)
	{
		SetFailState("Failed to get game movement pointer");
	}

	int iOffset = GameConfGetOffset(hGameData, "SetGroundEntity");
	g_hSetGroundEntityHook = DHookCreate(
		iOffset, HookType_Raw, ReturnType_Void, ThisPointer_Address, PreSetGroundEntity);

	if(g_hSetGroundEntityHook == null) {
		SetFailState("Failed to create SetGroundEntity hook.");
		return;
	}

	DHookAddParam(g_hSetGroundEntityHook, HookParamType_ObjectPtr);
	DHookRaw(g_hSetGroundEntityHook, false, pGameMovement);

	delete hGameData;
	PrecacheSound(SND_BANANASLIP);

	g_Cvar_slidefix = CreateConVar("sm_groundfix_slide", "1", "Enables/disables slide fix for slopes.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_Cvar_edgefix = CreateConVar("sm_groundfix_edge", "0", "Enables/disables edgebug fall height fix.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_Cvar_banana = CreateConVar("sm_groundfix_banana", "0", "Enables/disables banana slip sound on slide fix", FCVAR_NONE, true, 0.0, true, 1.0);
	g_Cvar_chat = CreateConVar("sm_groundfix_chat", "0", "Enables/disables chat message on slide fix", FCVAR_NONE, true, 0.0, true, 1.0);
}

public void OnMapStart()
{
	PrecacheSound(SND_BANANASLIP);
}

public void OnClientPutInServer(client)
{
	EmitSoundToClient(client, SND_BANANASLIP, _, _, _, _, 0.0);
}

public MRESReturn PreSetGroundEntity(Address pThis, Handle hParams) {
	// not setting ground entity
	if (DHookIsNullParam(hParams, 1)) return MRES_Ignored;

	int clientAddress = LoadFromAddress(pThis + view_as<Address>(4), NumberType_Int32);
	int client;

	for (int c = 1; c <= MaxClients; c++)
	{
		if (IsClientInGame(c)
			&& GetEntityAddress(c) == view_as<Address>(clientAddress)) {
			client = c;
			break;
		}
	}

	if (!client) return MRES_Ignored;

	// ignore player in noclip
	if (GetEntityMoveType(client) != MOVETYPE_WALK) return MRES_Ignored;

	float vPlane[3];
	// retrieve plane normal from trace object
	DHookGetParamObjectPtrVarVector(hParams, 1, 24, ObjectValueType_Vector, vPlane);

	float vVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", vVelocity);

	// this bit aims to fix edgebugs on 1-unit-wide brushes to be consistent from any fall height
	// these are used as a mechanic in some TF2 jump maps
	// it shouldn't make other edgebugs easier at all, due to the somewhat hacky width check
	// TODO: check to see if there are any that use greater widths

	// was not on ground
	if (g_Cvar_edgefix.BoolValue
		&& GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == -1)
	{
		// get CBaseTrace->fraction
		float groundTraceFraction = DHookGetParamObjectPtrVar(hParams, 1, 44, ObjectValueType_Float);

		float groundTraceEndPos[3];
		// get CBaseTrace->endpos
		DHookGetParamObjectPtrVarVector(hParams, 1, 12, ObjectValueType_Vector, groundTraceEndPos);

		float vPredictedVel[3];
		// clip velocity to plane normal
		ClipVelocity(vVelocity, vPlane, vPredictedVel);

		// velocity per tick
		ScaleVector(vPredictedVel, GetGameFrameTime());
		// remaining distance traveled from ground hitpos
		ScaleVector(vPredictedVel, 1 - groundTraceFraction);

		float vAddVel[3];
		NormalizeVector(vPredictedVel, vAddVel);

		// scale the velocity by the diagonal length of a 1-unit square to account for varied movement direction
		ScaleVector(vAddVel, 1.41421356);

		float vMins[3], vMaxs[3];

		GetEntPropVector(client, Prop_Send, "m_vecMins", vMins);
		GetEntPropVector(client, Prop_Send, "m_vecMaxs", vMaxs);

		float vBacktraceOrigin[3];
		vBacktraceOrigin[0] = groundTraceEndPos[0];
		vBacktraceOrigin[1] = groundTraceEndPos[1];
		vBacktraceOrigin[2] = groundTraceEndPos[2];

		SubtractVectors(vBacktraceOrigin, vAddVel, vBacktraceOrigin);

		Handle trace;

		// trace backwards to find another plane intersecting our ground
		trace = TR_TraceHullFilterEx(groundTraceEndPos, vBacktraceOrigin, vMins, vMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceRayDontHitSelf, client);

		// if we didn't hit another plane, the brush is too wide in our movement direction
		if (TR_DidHit(trace))
		{
			float vStartPos[3];
			TR_GetEndPosition(vStartPos, trace);
			CloseHandle(trace);

			float vEndPos[3];
			vEndPos[0] = vStartPos[0];
			vEndPos[1] = vStartPos[1];
			vEndPos[2] = vStartPos[2];

			AddVectors(vEndPos, vAddVel, vEndPos);

			// check to see if we hit anything on the way to the predicted origin
			trace = TR_TraceHullFilterEx(vStartPos, vEndPos, vMins, vMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceRayDontHitSelf, client);

			if (!TR_DidHit(trace))
			{
				CloseHandle(trace);
				float vTraceEndPos[3];
				vTraceEndPos[0] = vEndPos[0];
				vTraceEndPos[1] = vEndPos[1];
				vTraceEndPos[2] = vEndPos[2] - 2.0;

				// check if predicted origin would be standing on ground (<= 2 units above)
				trace = TR_TraceHullFilterEx(vEndPos, vTraceEndPos, vMins, vMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceRayDontHitSelf, client);
				float vGroundNormal[3];
				TR_GetPlaneNormal(trace, vGroundNormal);

				if (!TR_DidHit(trace) || vGroundNormal[2] <= 0.7) {
					#if defined DRAWBEAM_TESTING
						float m_vecAbsOrigin[3];
						GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", m_vecAbsOrigin);

						float vBoxPrimeMins[3];
						float vBoxPrimeMaxs[3];
						AddVectors(m_vecAbsOrigin, vMins, vBoxPrimeMins);
						AddVectors(m_vecAbsOrigin, vMaxs, vBoxPrimeMaxs);

						float vBoxOneMins[3];
						float vBoxOneMaxs[3];
						AddVectors(vStartPos, vMins, vBoxOneMins);
						AddVectors(vStartPos, vMaxs, vBoxOneMaxs);

						float vBoxTwoMins[3];
						float vBoxTwoMaxs[3];
						AddVectors(vEndPos, vMins, vBoxTwoMins);
						AddVectors(vEndPos, vMaxs, vBoxTwoMaxs);

						int material = PrecacheModel("materials/effects/beam_generic_2.vmt");

						Effect_DrawBeamBoxToClient(client, vBoxPrimeMins, vBoxPrimeMaxs, material, material, 0, 0, 10.0, 0.1, 0.1, 0, 0.0, {255, 255, 0, 255}, 0);
						Effect_DrawBeamBoxToClient(client, vBoxOneMins, vBoxOneMaxs, material, material, 0, 0, 10.0, 0.1, 0.1, 0, 0.0, {0, 255, 0, 255}, 0);
						Effect_DrawBeamBoxToClient(client, vBoxTwoMins, vBoxTwoMaxs, material, material, 0, 0, 10.0, 0.1, 0.1, 0, 0.0, {0, 200, 255, 255}, 0);
					#endif

					PrintToChat(client, "Prevented failed edgebug!");
					CloseHandle(trace);
					EmitSoundToClient(client, SND_BANANASLIP);
					return MRES_Supercede;
				}
				else
				{
					CloseHandle(trace);
				}
			}
		}
		else
		{
			CloseHandle(trace);
		}
	}

	if(g_Cvar_slidefix.BoolValue
		&& 1 > vPlane[2] > 0.7 // not flat ground, is a slope, but not a surf ramp (sanity check)
		&& GetVectorDotProduct(vVelocity, vPlane) < 0.0 /* moving up slope */)
	{
		float vPredictedVel[3];
		ClipVelocity(vVelocity, vPlane, vPredictedVel);

		// would be sliding up slope
		// https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/shared/gamemovement.cpp#L4591
		if (vPredictedVel[2] > 250.0)
		{
			if (g_Cvar_chat.BoolValue)
			{
				PrintToChat(client, "Prevented slope bug.");
			}
			if (g_Cvar_banana.BoolValue)
			{
				EmitSoundToClient(client, SND_BANANASLIP);
			}
			return MRES_Supercede;
		}
	}
	return MRES_Ignored;
}

// from https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/shared/gamemovement.cpp#L3145
void ClipVelocity(float inVelocity[3], float normal[3], float outVelocity[3])
{
	float backoff;
	float change;

	// Determine how far along plane to slide based on incoming direction.
	backoff = GetVectorDotProduct(inVelocity, normal);

	for (int i = 0; i < 3; i++)
	{
		change = normal[i] * backoff;
		outVelocity[i] = inVelocity[i] - change;
	}

	// iterate once to make sure we aren't still moving through the plane
	float adjust = GetVectorDotProduct(outVelocity, normal);
	if (adjust < 0.0)
	{
		float adjustedNormal[3];
		for (int i = 0; i < 3; i++)
		{
			adjustedNormal[i] = normal[i] * adjust;
			outVelocity[i] -= adjustedNormal[i];
		}
	}
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	// Don't return players or player projectiles
	int entity_owner;
	entity_owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");

	if(entity != data && !(0 < entity <= MaxClients) && !(0 < entity_owner <= MaxClients))
	{
		return true;
	}
	return false;
}
