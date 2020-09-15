#include <sourcemod>
#include <smjansson>
#include <sourcemod-colors>
#include <globalpb>

#undef REQUIRE_PLUGIN
#include <gokz/core> // We might also run this on kztimer, or without anything at all.
#define REQUIRE_PLUGIN

char g_Prefix[32] = "{green}KZ {grey}| ";
bool g_UsesGokz = false;

public Plugin myinfo =
{
	name = "GlobalPB",
	author = "Szwagi",
	version = "v1.0.0"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_gpb", Command_GlobalPB);
	RegConsoleCmd("sm_globalpb", Command_GlobalPB);
	RegConsoleCmd("sm_gbpb", Command_GlobalBonusPB);
	RegConsoleCmd("sm_globalbonuspb", Command_GlobalBonusPB);
}

public void OnAllPluginsLoaded()
{
	g_UsesGokz = LibraryExists("gokz-core");

	ConVar cvPrefix = FindConVar("gokz_chat_prefix");
	if (cvPrefix != null)
	{
		cvPrefix.GetString(g_Prefix, sizeof(g_Prefix));
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "gokz-core"))
	{
		g_UsesGokz = false;
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "gokz-core"))
	{
		g_UsesGokz = true;
	}
}

Action Command_GlobalPB(int client, int argc)
{
	char map[128];
	if (argc == 0)
	{
		GetCurrentMap(map, sizeof(map));
		GetMapDisplayName(map, map, sizeof(map));
		StartRequestGlobalPB(client, map, 0);
	}
	else
	{
		GetCmdArgString(map, sizeof(map));
		if (FindMap(map, map, sizeof(map)) == FindMap_NotFound)
		{
			CPrintToChat(client, "%s{grey}Your search for map '{default}%s{grey}' returned no results.", g_Prefix, map);
		}
		else
		{
			GetMapDisplayName(map, map, sizeof(map));
			StartRequestGlobalPB(client, map, 0);
		}
	}
	return Plugin_Handled;
}

Action Command_GlobalBonusPB(int client, int argc)
{
	char map[256];
	GetCurrentMap(map, sizeof(map));
	GetMapDisplayName(map, map, sizeof(map));

	if (argc == 0)
	{
		StartRequestGlobalPB(client, map, 1);
	}
	else
	{
		char args[4];
		GetCmdArgString(args, sizeof(args));

		int course = StringToInt(args);
		if (course <= 0)
		{
			CPrintToChat(client, "%s{grey}'{default}%s{grey}' is not a valid bonus number.", g_Prefix, args);
		}
		else
		{
			StartRequestGlobalPB(client, map, course);
		}
	}
}

void StartRequestGlobalPB(int client, const char[] map, int course)
{
	int userid = GetClientUserId(client);
	int mode = 2; // Default to KZTimer

	if (g_UsesGokz)
	{
		mode = GOKZ_GetCoreOption(client, Option_Mode);
	}

	if (mode >= sizeof(gC_APIModes))
	{
		return;
	}

	DataPack data1 = new DataPack();
	data1.WriteCell(userid);
	data1.WriteCell(mode);
	data1.WriteCell(course);
	data1.WriteString(map);

	RequestGlobalPB(client, map, course, mode, true, HTTPRequestCompleted_Stage1, data1);
}

void HTTPRequestCompleted_Stage1(Handle request, bool failure, bool requestSuccess, EHTTPStatusCode status, DataPack data1)
{
	if (failure || !requestSuccess || status != k_EHTTPStatusCode200OK)
	{
		delete request;
		delete data1;
		return;
	}

	float time;
	int teleports;
	if (!GetRequestRecordInfo(request, time, teleports))
	{
		delete request;
		delete data1;
		return;
	}

	data1.Reset();
	int userid = data1.ReadCell();
	int mode = data1.ReadCell();
	int course = data1.ReadCell();

	char map[256];
	data1.ReadString(map, sizeof(map));

	int client = GetClientOfUserId(userid);
	if (client == 0)
	{
		delete request;
		delete data1;
		return;
	}

	DataPack data2 = new DataPack();
	data2.WriteFloat(time);
	data2.WriteCell(teleports);

	RequestGlobalPB(client, map, course, mode, false, HTTPRequestCompleted_Stage2, data1, data2);
	
	delete request;
}

void HTTPRequestCompleted_Stage2(Handle request, bool failure, bool requestSuccess, EHTTPStatusCode status, DataPack data1, DataPack data2)
{
	data1.Reset();
	int userid = data1.ReadCell();
	int mode = data1.ReadCell();
	int course = data1.ReadCell();

	char map[256];
	data1.ReadString(map, sizeof(map));
	
	delete data1;

	data2.Reset();
	float tpTime = data2.ReadFloat();
	int tpTeleports = data2.ReadCell();

	delete data2;

	float proTime;
	int proTeleports;
	if (!GetRequestRecordInfo(request, proTime, proTeleports))
	{
		delete request;
		return;
	}
	delete request;

	int client = GetClientOfUserId(userid);
	if (client == 0)
	{
		return;
	}

	PrintPbToChat(client, map, course, mode, tpTime, tpTeleports, proTime);
}

void PrintPbToChat(int client, const char[] map, int course, int mode, float tpTime, int tpTeleports, float proTime)
{
	if (course == 0)
	{
		CPrintToChat(client, "%s{lime}%N {grey}on {default}%s {grey}[{purple}%s{grey}]", g_Prefix, client, map, gC_ModeShort[mode]);
	}
	else
	{
		CPrintToChat(client, "%s{lime}%N {grey}on {default}%s {grey2}Bonus %d {grey}[{purple}%s{grey}]", g_Prefix, client, map, course, gC_ModeShort[mode]);
	}

	if (tpTime <= 0.0 && proTime <= 0.0)
	{
		CPrintToChat(client, "{grey}You haven't set a time... yet.");
	}
	else if ((tpTime > 0.0 && proTime > 0.0 && tpTime > proTime) || (tpTime <= 0.0 && proTime > 0.0))
	{
		char timeFmt[32];
		FormatDuration(timeFmt, sizeof(timeFmt), proTime);

		CPrintToChat(client, "{yellow}NUB{grey}/{blue}PRO PB{grey}: {default}%s", timeFmt);
	}
	else
	{
		if (tpTime > 0.0)
		{
			char timeFmt[32];
			FormatDuration(timeFmt, sizeof(timeFmt), tpTime);

			CPrintToChat(client, "{yellow}NUB PB{grey}: {default}%s {grey}({yellow}%d TP{grey})", timeFmt, tpTeleports);
		}
		else
		{
			CPrintToChat(client, "{yellow}NUB PB{grey}: None... yet.");
		}

		if (proTime > 0.0)
		{
			char timeFmt[32];
			FormatDuration(timeFmt, sizeof(timeFmt), proTime);

			CPrintToChat(client, "{blue}PRO PB{grey}: {default}%s", timeFmt);
		}
		else
		{
			CPrintToChat(client, "{blue}PRO PB{grey}: None... yet.");
		}
	}
}
