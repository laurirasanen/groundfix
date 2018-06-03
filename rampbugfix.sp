// Plugin for TF2 to fix inconsistencies with ramps

#pragma semicolon 1

#include <sourcemod>
#include <dhooks>
#include <sdktools>

public Plugin myinfo =
{
	name = "rampbugfix",
	author = "jayess + Larry",
	description = "ramp fix",
	version = "3.0.3",
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

	float vPlane[3];
	// retrieve plane normal from trace object
	DHookGetParamObjectPtrVarVector(hParams, 1, 24, ObjectValueType_Vector, vPlane);

	float vVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);

	if(GetVectorDotProduct(vVelocity, vPlane) < 0.0 // moving up slope
		&& 0 < vPlane[2] < 1 // not flat ground
		&& SquareRoot( Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0) ) > 300.0)
	{
		PrintToChat(client, "Prevented slope bug.");
		return MRES_Supercede;
	}
	return MRES_Ignored;
}
