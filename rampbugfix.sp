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
	version = "3.0.2",
	url = "http://steamcommunity.com/id/jayessZA + http://steamcommunity.com/id/pancakelarry"
};

Handle g_hSetGroundEntityDetour;

public void OnPluginStart() {
	Handle hGameData = LoadGameConfigFile("rampbugfix.games");

	if (!hGameData)
	{
		SetFailState("Missing gamedata!");
		return;
	}
	
	g_hSetGroundEntityDetour = DHookCreateFromConf(hGameData, "SetGroundEntity");

	if(!g_hSetGroundEntityDetour) 
		SetFailState("Failed to create SetGroundEntity hook.");
	delete hGameData;
	
	if (!DHookEnableDetour(g_hSetGroundEntityDetour, false, Detour_SetGroundEntity))
		SetFailState("Failed to detour SetGroundEntity.");					

    PrintToServer("SetGroundEntity detoured!");
}

public MRESReturn Detour_SetGroundEntity(Address pThis, Handle hParams) {
		
	// not setting ground entity
	if (DHookIsNullParam(hParams, 2)) return MRES_Ignored;

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
	DHookGetParamObjectPtrVarVector(hParams, 2, 24, ObjectValueType_Vector, vPlane);

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
