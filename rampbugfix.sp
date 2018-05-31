// Plugin for TF2 to fix inconsistencies with ramps

#pragma semicolon 1

#include <sourcemod>
#include <dhooks>

#pragma newdecls required


public Plugin myinfo =
{
	name = "rampbugfix",
	author = "Larry",
	description = "ramp fix",
	version = "3.0.1",
	url = "http://steamcommunity.com/id/pancakelarry"
};


Handle g_hSetGroundEntityHook;


public void OnPluginStart() {
	Handle hGameData = LoadGameConfigFile("rampbugfix.games");

	if (hGameData == INVALID_HANDLE)
		SetFailState("Missing gamedata!");

	Address pGameMovement = GameConfGetAddress(hGameData, "g_pGameMovement");
	if (pGameMovement == Address_Null)
	{
		LogError("Failed to find g_GameMovement address");
		return;
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
}


public MRESReturn PreSetGroundEntity(Address pThis, Handle hParams) {
	// not setting ground entity
	if (DHookIsNullParam(hParams, 1)) return MRES_Ignored;

	Address clientAddress = LoadFromAddress(pThis + view_as<Address>(4), NumberType_Int32);
	int client;

	for (int c = 1; c <= MaxClients; c++)
	{
		if (IsClientInGame(c) && GetEntityAddress(c) == clientAddress) {
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
		&& SquareRoot( Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0) ) > 1000.0)
	{
		PrintToChat(client, "Prevented slope bug.");
		return MRES_Supercede;
	}
	return MRES_Ignored;
}
