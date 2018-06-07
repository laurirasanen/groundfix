// Plugin for TF2 to fix inconsistencies with ramps

#pragma semicolon 1

#include <sourcemod>
#include <dhooks>
#include <sdktools>
#include <halflife>

#define SND_BANANASLIP "misc/banana_slip.wav"

ConVar g_Cvar_slidefix;
ConVar g_Cvar_edgefix;

public Plugin myinfo =
{
	name = "rampbugfix",
	author = "jayess + Larry",
	description = "ramp fix",
	version = "3.0.5",
	url = "http://steamcommunity.com/id/jayessZA + http://steamcommunity.com/id/pancakelarry"
};

Handle g_hSetGroundEntityHook;

public void OnPluginStart() {
	Handle hGameData = LoadGameConfigFile("rampbugfix.games");

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
	g_Cvar_edgefix = CreateConVar("sm_groundfix_edge", "1", "Enables/disables edgebug fix for any fall height.", FCVAR_NONE, true, 0.0, true, 1.0);
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

	// * this bit fixes edgebugs to be consistent from any fall height
	// * it should not make them otherwise easier at all
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

		float vPredictedOrigin[3];
		vPredictedOrigin[0] = groundTraceEndPos[0];
		vPredictedOrigin[1] = groundTraceEndPos[1];
		vPredictedOrigin[2] = groundTraceEndPos[2];

		ScaleVector(vPredictedVel, GetGameFrameTime());
		ScaleVector(vPredictedVel, 1 - groundTraceFraction);

		AddVectors(vPredictedOrigin, vPredictedVel, vPredictedOrigin);

		float vMins[3], vMaxs[3];

		GetEntPropVector(client, Prop_Send, "m_vecMins", vMins);
		GetEntPropVector(client, Prop_Send, "m_vecMaxs", vMaxs);

		Handle trace;

		// check to see if we hit anything on the way to the predicted origin
		trace = TR_TraceHullFilterEx(groundTraceEndPos, vPredictedOrigin, vMins, vMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceRayDontHitSelf, client);

		if (!TR_DidHit(trace)) {
			CloseHandle(trace);
			float vTraceEndPos[3];
			vTraceEndPos[0] = vPredictedOrigin[0];
			vTraceEndPos[1] = vPredictedOrigin[1];
			vTraceEndPos[2] = vPredictedOrigin[2] - 2.0;

			// check if predicted origin would be standing on ground (<= 2 units above)
			trace = TR_TraceHullFilterEx(vPredictedOrigin, vTraceEndPos, vMins, vMaxs, MASK_PLAYERSOLID_BRUSHONLY, TraceRayDontHitSelf, client);
			if (!TR_DidHit(trace)) {
				PrintToChat(client, "Prevented failed edgebug!");
				CloseHandle(trace);
				EmitSoundToClient(client, SND_BANANASLIP);
				return MRES_Supercede;
			}
			CloseHandle(trace);
		}
	}

	if(g_Cvar_slidefix
		&& 1 > vPlane[2] > 0.7 // not flat ground, is a slope, but not a surf ramp (sanity check)
		&& GetVectorDotProduct(vVelocity, vPlane) < 0.0 /* moving up slope */)
	{
		float vPredictedVel[3];
		ClipVelocity(vVelocity, vPlane, vPredictedVel);

		// would be sliding up slope
		// https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/shared/gamemovement.cpp#L4591
		if (vPredictedVel[2] > 250.0)
		{
			PrintToChat(client, "Prevented slope bug.");
			EmitSoundToClient(client, SND_BANANASLIP);
			return MRES_Supercede;
		}
	}
	return MRES_Ignored;
}

// from https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/shared/gamemovement.cpp#L3145
void ClipVelocity(float[3] inVelocity, float[3] normal, float[3] outVelocity)
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
