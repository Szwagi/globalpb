#include <sourcemod>
#include <smjansson>
#include <sourcemod-colors>
#include <globalpb>

#undef REQUIRE_PLUGIN
#include <kztimer>
#include <gokz/core>
#define REQUIRE_PLUGIN

int g_iTargetJS[MAXPLAYERS+1];
float g_TimeoutExpireTime[MAXPLAYERS+1];
char g_cPrefix[64] = "{default}[{lime}KZ{default}] {grey}";
bool g_UsesGokz = false;

public Plugin myinfo =
{
	name = "GlobalPB",
	author = "Szwagi, Dave",
	version = "v1.3.0"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases.txt");

	RegConsoleCmd("sm_gpb", Command_GlobalPB);
	RegConsoleCmd("sm_globalpb", Command_GlobalPB);
	RegConsoleCmd("sm_gbpb", Command_GlobalBonusPB);
	RegConsoleCmd("sm_globalbonuspb", Command_GlobalBonusPB);

	RegConsoleCmd("sm_gjs", Command_GlobalJS);
	RegConsoleCmd("sm_globaljumpstats", Command_GlobalJS);
}

public void OnAllPluginsLoaded()
{
	g_UsesGokz = LibraryExists("gokz-core");

	ConVar cvPrefix = FindConVar("gokz_chat_prefix");
	if (cvPrefix != null)
	{
		cvPrefix.GetString(g_cPrefix, sizeof(g_cPrefix));
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

public void OnClientConnected(int client)
{
	g_TimeoutExpireTime[client] = 0.0;
}

Action Command_GlobalPB(int client, int argc)
{
	char map[128];
	char playerName[MAX_NAME_LENGTH];

	if (argc == 0) // Print calling player's PB for current map
	{
		GetCurrentMap(map, sizeof(map));
		GetMapDisplayName(map, map, sizeof(map));
		StartRequestGlobalPB(client, client, map, 0);
	}
	else if (argc == 1) // Print calling player's PB for specified map
	{
		GetCmdArgString(map, sizeof(map));
		if (FindMap(map, map, sizeof(map)) == FindMap_NotFound)
		{
			CPrintToChat(client, "%sYour search for map '{default}%s{grey}' returned no results.", g_cPrefix, map);
		}
		else
		{
			GetMapDisplayName(map, map, sizeof(map));
			StartRequestGlobalPB(client, client, map, 0);
		}
	}
	else if (argc == 2) // Print PB for specific map, for specified player
	{
		GetCmdArg(1, map, sizeof(map));
		if (FindMap(map, map, sizeof(map)) == FindMap_NotFound)
		{
			CPrintToChat(client, "%sYour search for map '{default}%s{grey}' returned no results.", g_cPrefix, map);
			return Plugin_Handled;
		}

		GetCmdArg(2, playerName, sizeof(playerName));

		int target = FindTarget(client, playerName, true, false);
		if (target == -1)
		{
			return Plugin_Handled;
		}

		StartRequestGlobalPB(client, target, map, 0);
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
		StartRequestGlobalPB(client, client, map, 1);
	}
	else
	{
		char args[4];
		GetCmdArgString(args, sizeof(args));

		int course = StringToInt(args);
		if (course <= 0)
		{
			CPrintToChat(client, "%s'{default}%s{grey}' is not a valid bonus number.", g_cPrefix, args);
		}
		else
		{
			StartRequestGlobalPB(client, client, map, course);
		}
	}
}

void StartRequestGlobalPB(int client, int target, const char[] map, int course)
{
	int userid = GetClientUserId(client);
	int targetUserid = GetClientUserId(target);
	int mode = 2; // Default to KZTimer

	/*if (g_UsesGokz)
	{
		mode = GOKZ_GetCoreOption(client, Option_Mode);
	}*/

	if (mode >= sizeof(gC_APIModes))
	{
		return;
	}


	if (g_TimeoutExpireTime[client] > GetEngineTime())
	{
		float timeoutLeft = g_TimeoutExpireTime[client] - GetEngineTime(); 
		CPrintToChat(client, "%sPlease wait %0.1f seconds before using that command.", g_cPrefix, timeoutLeft + 0.1);
		return;
	}
	g_TimeoutExpireTime[client] = GetEngineTime() + 4.0;

	DataPack data1 = new DataPack();
	data1.WriteCell(userid);
	data1.WriteCell(targetUserid);
	data1.WriteCell(mode);
	data1.WriteCell(course);
	data1.WriteString(map);

	RequestGlobalPB(target, map, course, mode, true, HTTPRequestCompleted_Stage1, data1);
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
	int targetUserid = data1.ReadCell();
	int mode = data1.ReadCell();
	int course = data1.ReadCell();

	char map[256];
	data1.ReadString(map, sizeof(map));

	int client = GetClientOfUserId(userid);
	int target = GetClientOfUserId(targetUserid);
	if (client == 0 || target == 0)
	{
		delete request;
		delete data1;
		return;
	}

	DataPack data2 = new DataPack();
	data2.WriteFloat(time);
	data2.WriteCell(teleports);

	RequestGlobalPB(target, map, course, mode, false, HTTPRequestCompleted_Stage2, data1, data2);
	
	delete request;
}

void HTTPRequestCompleted_Stage2(Handle request, bool failure, bool requestSuccess, EHTTPStatusCode status, DataPack data1, DataPack data2)
{
	data1.Reset();
	int userid = data1.ReadCell();
	int targetUserid = data1.ReadCell();
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
	int target = GetClientOfUserId(targetUserid);
	if (client == 0 || target == 0)
	{
		return;
	}

	PrintPbToChat(client, target, map, course, mode, tpTime, tpTeleports, proTime);
}

void PrintPbToChat(int client, int target, const char[] map, int course, int mode, float tpTime, int tpTeleports, float proTime)
{
	if (course == 0)
	{
		CPrintToChat(client, "%s{lime}%N {grey}on {default}%s {grey}[{purple}%s{grey}]", g_cPrefix, target, map, gC_ModeShort[mode]);
	}
	else
	{
		CPrintToChat(client, "%s{lime}%N {grey}on {default}%s {grey2}Bonus %d {grey}[{purple}%s{grey}]", g_cPrefix, target, map, course, gC_ModeShort[mode]);
	}

	if (tpTime <= 0.0 && proTime <= 0.0)
	{
		if (client == target)
		{
			CPrintToChat(client, "%sYou haven't set a time... yet.", g_cPrefix);
		}
		else
		{
			CPrintToChat(client, "%s{lime}%N {grey}hasn't set a time... yet.", g_cPrefix, target);
		}
	}
	else if ((tpTime > 0.0 && proTime > 0.0 && tpTime > proTime) || (tpTime <= 0.0 && proTime > 0.0))
	{
		char timeFmt[32];
		FormatDuration(timeFmt, sizeof(timeFmt), proTime);

		CPrintToChat(client, "%s{yellow}TP{grey}/{blue}PRO PB{grey}: {default}%s", g_cPrefix, timeFmt);
	}
	else
	{
		if (tpTime > 0.0)
		{
			char timeFmt[32];
			FormatDuration(timeFmt, sizeof(timeFmt), tpTime);

			CPrintToChat(client, "%s{yellow}TP PB{grey}: {default}%s {grey}({yellow}%d{grey})", g_cPrefix, timeFmt, tpTeleports);
		}
		else
		{
			CPrintToChat(client, "%s{yellow}TP PB{grey}: None... yet.", g_cPrefix);
		}

		if (proTime > 0.0)
		{
			char timeFmt[32];
			FormatDuration(timeFmt, sizeof(timeFmt), proTime);

			CPrintToChat(client, "%s{blue}PRO PB{grey}: {default}%s", g_cPrefix, timeFmt);
		}
		else
		{
			CPrintToChat(client, "%s{blue}PRO PB{grey}: None... yet.", g_cPrefix);
		}
	}
}

Action Command_GlobalJS(int client, int args)
{
	if(g_UsesGokz)
		return Plugin_Handled;

	int target;
    char bufferTarget[32];
	if(args > 0)
	{
		if(GetCmdArg(1, bufferTarget, sizeof(bufferTarget)))
		{
			target = FindTarget(client, bufferTarget, true);
		}
	} else 
	{
		target = client;
	}
	
	g_iTargetJS[client] = target;

	jsMenu(client, 0);
	return Plugin_Handled;
}

public Action jsMenu(int client, int args)
{
    Menu menu = new Menu(jsMenuHandler);
    SetMenuPagination(menu, MENU_NO_PAGINATION);

	for(int i = 0; i < 7; i++)
	{
		menu.AddItem(gC_JumpTypes[i], gC_JumpTypes[i]);
	}
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);

    return Plugin_Handled;
}

public int jsMenuHandler(Menu menu, MenuAction action, int client, int option)
{
	int target = g_iTargetJS[client];

    if(action == MenuAction_Select)
    {
        char jumpType[16];
        menu.GetItem(option, jumpType, sizeof(jumpType));
        CPrintToChat(client, "%sLoading stat...", g_cPrefix);
        if(g_TimeoutExpireTime[client] > GetEngineTime())
        {
            jsMenu(client, 0);
        }
        StartRequestStatPb(client, target, jumpType); 
    } else if(action == MenuAction_End)
    {
        delete menu;
    }
}

public void StartRequestStatPb(int client, int target, const char[] jumpType)
{
    int userid = GetClientUserId(client);
    int targetUserid = GetClientUserId(target);

    if(g_TimeoutExpireTime[client] > GetEngineTime())
    {
        float timeoutLeft = g_TimeoutExpireTime[client] - GetEngineTime();
        CPrintToChat(client, "%sTimeout, wait %0.1f seconds", g_cPrefix, timeoutLeft + 0.1);
        return;
    }

    g_TimeoutExpireTime[client] = GetEngineTime() + 4.0;

    DataPack data1 = new DataPack();
    data1.WriteCell(userid);
    data1.WriteCell(targetUserid);
    data1.WriteString(jumpType);

    RequestGlobalJS(target, jumpType, HTTPRequestCompleted_Stage1_JS, data1);
}

void HTTPRequestCompleted_Stage1_JS(Handle request, bool failure, bool requestSuccess, EHTTPStatusCode status, DataPack data1)
{
    if(failure || !requestSuccess || status != k_EHTTPStatusCode200OK)
    {
        delete request;
        delete data1;
        return;
    }
    
    float distance;
    int strafe_count, isBinded;
	char cDate[32];

    if(!GetRequestGlobalJSInfo(request, distance, strafe_count, isBinded, cDate))
    {
        delete request;
        delete data1;
        return;
    }

    data1.Reset();
    int userid = data1.ReadCell();
    int targetUserid = data1.ReadCell();
    
    char jumptype[12];
    data1.ReadString(jumptype, sizeof(jumptype));

    int client = GetClientOfUserId(userid);
    int target = GetClientOfUserId(targetUserid);
    if (client == 0 || target == 0)
	{
		delete request;
		delete data1;
		return;
	}

    DataPack data2 = new DataPack();
    data2.WriteFloat(distance);
    data2.WriteCell(strafe_count);
    data2.WriteCell(isBinded);
	data2.WriteString(cDate);

    RequestGlobalJS(target, jumptype, HTTPRequestCompleted_Stage2_JS, data1, data2);

    delete request;
}

void HTTPRequestCompleted_Stage2_JS(Handle request, bool failure, bool requestSuccess, EHTTPStatusCode status, DataPack data1, DataPack data2)
{
    data1.Reset();
    int userid = data1.ReadCell();
    int targetUserid = data1.ReadCell();

    char jumptype[12];
    data1.ReadString(jumptype, sizeof(jumptype));

    delete data1;

    data2.Reset();
    float distance = data2.ReadFloat();
    int strafe_count = data2.ReadCell();
    int isBinded = data2.ReadCell();
	
	char cDate[64];
	data2.ReadString(cDate, sizeof(cDate)); 

    delete data2;

	int client = GetClientOfUserId(userid);
    int target = GetClientOfUserId(targetUserid);

    if(!GetRequestGlobalJSInfo(request, distance, strafe_count, isBinded, cDate))
    {
        delete request;
        return;
    }
    delete request;

    if(client == 0 || target == 0)
    {
        return;
    }

    jsMenuInfo(client, target, jumptype, distance, strafe_count, isBinded, cDate);
}

public Action jsMenuInfo(int client, int target, const char[] jumptype, float distance, int strafe_count, int isBinded, char[] cDate)
{
    if(!distance)
    {
        CPrintToChat(client, "%sYou have no registered jumps of this type!", g_cPrefix);
		jsMenu(client, 0);
        return Plugin_Handled;
    }

	char steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));

    char czTitle[128], czBody[256];

	if(!g_UsesGokz)
		KZTimer_StopUpdatingOfClimbersMenu(client);

    Menu menu = new Menu(jsMenuInfoHandler);
	ReplaceString(cDate, 64, "T", " ");
    FormatEx(czTitle, sizeof(czTitle), "Global Personal Best %s:\n", jumptype);
	FormatEx(czBody, sizeof(czBody), "Player: %N\n - SteamID: %s\n - Distance: %f\n - Strafes: %d\n - Binded: %s \n - Date: %s", target, steamid, distance, strafe_count, isBinded == 1 ? "true" : "false", cDate);
    menu.SetTitle(czTitle);
	menu.AddItem("body", czBody, ITEMDRAW_DISABLED);

	menu.ExitButton = true;
    menu.Display(client, 0);

    return Plugin_Handled;
}

public int jsMenuInfoHandler(Menu menu, MenuAction action, int client, int option)
{
    if(action == MenuAction_Select)
    {
        jsMenu(client, 0);
    } else if(action == MenuAction_Cancel)
    {
        jsMenu(client, 0);
    }else if(action == MenuAction_End)
    {
        delete menu;
    }
}
