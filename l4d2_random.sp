#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4downtown>
#include <l4d2_direct>
#include <l4d2_random_bonus>
#include <l4d2_penalty_bonus>
#include <l4d2_saferoom_detect>

#include "includes/random_constants.sp"
#include "includes/random_globals.sp"
#include "includes/random_init.sp"
#include "includes/random_support.sp"
#include "includes/random_random.sp"


// note: these must also be defined in includes/random_init
#define FIRE_PARTICLE           "gas_explosion_ground_fire"
#define EXPLOSION_PARTICLE      "FluidExplosion_fps"
#define EXPLOSION_PARTICLE2     "weapon_grenade_explosion"
#define EXPLOSION_PARTICLE3     "explosion_huge_b"
#define BURN_IGNITE_PARTICLE    "fire_small_01"

/*
        L4D2 Random
        -----------
        
        Basic plugin to get some of the freaky randomness going.
        
        randomizes:
            - map items
            - survivor starting items
            - survivor starting health
            - map distance and bonus
            - doors (locks a bunch)
            - survivor glows on/off
            - survivor outlines on/off
            - SI spawns / first attack / quads
            - uncommons spawning
            - ammo in weapons lying around
            - special events (various)
            - two-tank rounds (if tank spawns at all) [broken]
            - random item drops by common infected
            - gift boxes and opening results
            - pipebombs (are sometimes duds)
            
        
        ideas:
            - ?     - gift idea: key reversal effect, briefly. (negative effect)
            - ?     - gift idea: X second slowdown (like EVT_ENCUMBERED)
            - ?     - gift idea: ghost-effect for survivors for X seconds (no outlines for SI) (even if running)
            - ?     - gift idea: see outlines on infected for X seconds ('telepathy')
            
            - ?     - investigate c1m1 elevator.. see if you can move it up instead and/or make an alternative
                      pathing using that (or the second elevator).
            
            - MAYBE - mini-scavenge for specific rounds (decide per map)
                        do the research (how well possible? how much work? has anyone done it already?)
            - MAYBE - when cars are done (a minimal amount of) damage, they have a chance to explode
            - MAYBE - random car alarms & randomly going off when survivors are near?
            - MAYBE - play merry go round music for CLOWNS event
            - MAYBE - add 'rerandom' function, working on live round [ for testing / bad starts ]
            
            - STAB  - related cvars -- lower spawn timers = more useful items, or something like that
                        [ not much point as this moment, apart as an appreciative gesture to stabs. ]
            
            - NO    - for random glows: decide /per survivor/ whether they have glows...
            - NO    - memorize horde timers, repeat same hordes for second roundhalf
            - NO    - random event speeds/times & random event horde size/duration
            
            
        event ideas:
            
            in consideration
            ================
            - 'witch hunt': spawns many witches all over the place -- only way to score points = by killing them [pbonus]
                    consider it a 'miniwitches': give them 50% health, 50 dmg claw?
            - 'time penalty': every minute played gives a 25 point penalty on the round score
            - 'pistol round': only pistols (magnums included). No locked doors and easier ci/si. [maybe]
            - gnome VIP: only one gnome spawns (start saferoom), it must be brought or the end saferoom won't close
                or: gnome heaven, where the only way to score (many) points is to bring gnomes
                - for example: given only 1 gnome: distance points are frozen unless gnome is held
            - weird SI: random SI abilities (CRox's code) -- just give every SI a random ability...
            - axe effect / rockstar [stab]
                everyone gets an axe/guitar, all common are female, no tank only spitters and boomettes
            - clockwork: clockwork timed spawns, deaths, rinse repeat (no tank?)
            - quad damage [stab]
                one player gets special glow / sound => deals 4* damage
                tag-game: SI and survivors get quad, it switches when one hits another
            
            rejected
            ========
            - 'fallen survivor hunt'
            
            
        to-do:          
            - bugfix:   intro maps (and quite likely, only then?) get weird stuff spawning in saferooms sometimes
                        - see mikkel's doors, or that elevator in dc1, the boat
                        
                        - try: detect first mapload, delay randomitem stuff a bit more then?
                            - tried, needs testing
                        - alternatively, could be itemsblindinfected..?
            
            - bugfix:   adren event: gives wrong health (only 50)?
                        - cannot reproduce locally? maybe try with confogl loaded...
            
            - medium:   bot si spawn determination?
                        - or check if I can simply force the spawns just like human players (IsFakeClient() checks?)
                        - consider allowing bots in matchmode too, because.. why not?
            
            - low:      stripper-dir switch randomly: so maps automatically have two versions
                        - dec3 long way around vs. normal
                        - par3 random maze versions
            - low:      randomize location for gascans in scavenge finales
                            that is, find all the locations, get the total amount of cans and redistribute them
                            *near* every spawn location with random variance (then remember for next round)
            
            
            - code:     "The SetEntProp functions have a parameter for the array index, use it instead of doing manually lookups and computing offsets."
            - code:     Clean up the explosion timer/particles code a bit.
            - code:     Clean up the l4d_drop copied code some more.
            
*/
 /*
        equal flags:
        ------------
            1       items (startup & map)
            2       doors
            4       glows
            8       special event
            16      incap count / behaviour
            32      horde [once made available]
            64      item weights (preparechoices())
            128     survivor health (startup value)
            256     first attack (SI setup)
            512     tanks
           1024     points / scoring
 
        prop_physics    spawnflags
        --------------------------
            1 :         "Start Asleep" : 0
            2 :         "Don't take physics damage" : 0
            4 :         "Debris - Don't collide with the player or other debris" : 0
            8 :         "Motion Disabled" : 0
            128 :       "Not affected by rotor wash" : 0
            256 :       "Generate output on +USE " : 1
            512 :       "Prevent pickup" : 0
            1024:       "Prevent motion enable on player bump" : 0
            4096:       "Debris with trigger interaction" : 0
            8192:       "Force server-side (Multiplayer only)" : 0
            32768:      "Enable +use glow effect" : 0
            
        cvars to consider:
        ------------------
            z_common_limit
            z_background_limit
            z_cull_near
            
            z_hear_gunfire_range 1000
            z_hear_runner_far_range 900
            z_vision_range 1000
            z_vision_range_alert 2000
            z_vision_range_obscured 750
            z_vision_range_obscured_alert 1250
            z_acquire_near_range 500
            z_close_target_notice_distance 100
            z_notice_near_range 300
            
            
        What's this:
        ------------
            -Member: m_nHitboxSet (offset 1104) (type integer) (bits 2)
            -Member: m_flModelScale (offset 1108) (type float) (bits 0)
            -Member: m_iGlowType (offset 4) (type integer) (bits 32)
            -Member: m_nGlowRange (offset 8) (type integer) (bits 32)
            -Member: m_glowColorOverride (offset 12) (type integer) (bits 32)
            -Member: m_bFlashing (offset 16) (type integer) (bits 1)
            -Member: m_nRenderFX (offset 276) (type integer) (bits 8)
            -Member: m_nRenderMode (offset 277) (type integer) (bits 8)
            -Member: m_fEffects (offset 204) (type integer) (bits 10)
            -Member: m_clrRender (offset 280) (type integer) (bits 32)
            
        wait.. are these start/end saferoom checks? that'd be funny
            -Member: m_isInMissionStartArea (offset 11484) (type integer) (bits 1)
            -Member: m_bInBombZone (offset 10332) (type integer) (bits 1)
            -Member: m_bInBuyZone (offset 10333) (type integer) (bits 1)
            
        infected netprops:
            -Member: m_iGlowType (offset 4) (type integer) (bits 32)
            -Member: m_nGlowRange (offset 8) (type integer) (bits 32)
            -Member: m_glowColorOverride (offset 12) (type integer) (bits 32)
            -Member: m_bFlashing (offset 16) (type integer) (bits 1)
            -Member: m_nRenderFX (offset 276) (type integer) (bits 8)
            -Member: m_nRenderMode (offset 277) (type integer) (bits 8)
            -Member: m_fEffects (offset 204) (type integer) (bits 10)
            -Member: m_clrRender (offset 280) (type integer) (bits 32)
        may be used to change/force outlines...
        
        play with this..
            // experiment - test
            SetEntityGravity(entity, 400.0);
 */
 
 

public Plugin:myinfo = 
{
    name = "Randomize the Game",
    author = "Tabun",
    description = "Makes L4D2 sensibly random. Randomizes items, SI spawns and many other things.",
    version = "1.0.14",
    url = "https://github.com/Tabbernaut/L4D2-Random"
}


public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    g_bLateLoad = late;
    
    CreateNative("RNDMAIN_GetGnomeBonus",   Native_GetGnomeBonus);
    CreateNative("RNDMAIN_ShowGnomeBonus",  Native_ShowGnomeBonus);
    
    // depends on the configuration, if no special events are used,
    // we don't need l4d2_penalty_bonus
    MarkNativeAsOptional("PBONUS_GetRoundBonus");
    MarkNativeAsOptional("PBONUS_ReSetRoundBonus");
    MarkNativeAsOptional("PBONUS_SetRoundBonus");
    MarkNativeAsOptional("PBONUS_AddRoundBonus");
    
    return APLRes_Success;
}


public Native_GetGnomeBonus(Handle:plugin, numParams)
{
    new value = GetGnomeBonus();
    return _:value;
}
public Native_ShowGnomeBonus(Handle:plugin, numParams)
{
    GetGnomeBonus(true); // ignore what it returns, but do printout
}




public OnPluginStart()
{
    // Hooks
    HookEvent("round_start",                Event_RoundStart,               EventHookMode_PostNoCopy);
    HookEvent("round_end",                  Event_RoundEnd,                 EventHookMode_PostNoCopy);
    HookEvent("player_team",                Event_PlayerTeam,               EventHookMode_Post);
    HookEvent("player_left_start_area",     Event_PlayerLeftStartArea,      EventHookMode_PostNoCopy);
    
    HookEvent("player_hurt",                Event_PlayerHurt,               EventHookMode_Pre);
    HookEvent("player_death",               Event_PlayerDeath,              EventHookMode_Pre);
    HookEvent("player_spawn",               Event_PlayerSpawn,              EventHookMode_Post);
    HookEvent("ghost_spawn_time",           Event_GhostSpawnTime,           EventHookMode_Post);
    HookEvent("tank_spawn",                 Event_TankSpawned,              EventHookMode_Post);
    HookEvent("tank_frustrated",            Event_TankFrustrated,           EventHookMode_Post);
    
    HookEvent("player_now_it",              Event_PlayerBoomed,             EventHookMode_Post);
    HookEvent("player_no_longer_it",        Event_PlayerUnboomed,           EventHookMode_Post);

    HookEvent("player_use",                 Event_PlayerUse,                EventHookMode_Post);
    HookEvent("item_pickup",                Event_ItemPickup,               EventHookMode_Post);
    HookEvent("weapon_drop",                Event_WeaponDrop,               EventHookMode_Post);
    HookEvent("weapon_given",               Event_WeaponGiven,              EventHookMode_Post);    // also works for pills/adren
    HookEvent("player_shoved",              Event_ShovedPlayer,             EventHookMode_Post);
    HookEvent("weapon_fire",                Event_WeaponFire,               EventHookMode_Post);
    HookEvent("upgrade_pack_added",         Event_SpecialAmmo,              EventHookMode_Post);
    HookEvent("defibrillator_used",         Event_PlayerDefibbed,           EventHookMode_Post);
    HookEvent("heal_success",               Event_MedkitUsed,               EventHookMode_Post);
    HookEvent("pills_used",                 Event_PillsUsed,                EventHookMode_Post);
    HookEvent("adrenaline_used",            Event_PillsUsed,                EventHookMode_Post);
    
    HookEvent("ability_use",                Event_AbilityUse,               EventHookMode_Post);
    HookEvent("lunge_pounce",               Event_LungePounce,              EventHookMode_Post);
    
    
    // default convars
    g_hCvarTeamSize = FindConVar("survivor_limit");

    // do general init
    INIT_PrepareAllSDKCalls();
    INIT_DefineCVars();
    INIT_FillTries();
    INIT_CVarsGetDefault();
    INIT_PrecacheModels(true);
    
    // Unset home-grown storm cvar, to be sure
    new Handle: hTmpStormCVar = FindConVar("l4d2_storm_fogmode");
    if (hTmpStormCVar != INVALID_HANDLE) { SetConVarInt(hTmpStormCVar, 0); }
    
    // hooks
    if (g_bLateLoad)
    {
        // for testing, basically
        g_bPlayersLeftStart = true;
        
        for (new i=1; i <= MaxClients; i++) {
            if (IsClientInGame(i))
            {
                SDKHook(i, SDKHook_WeaponEquipPost, OnWeaponEquip);     // hook for penalty item tracking
                SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);         // hook for tank damage mod & protect event
            }
        }
    }


    // Commands
    RegConsoleCmd("sm_rand",    RandomReport_Cmd,   "Report what special randomness is currently active.");
    RegConsoleCmd("sm_bonus",   RandomBonus_Cmd,    "Report the special current round bonus (or penalty).");
    RegConsoleCmd("sm_penalty", RandomBonus_Cmd,    "Report the special current round bonus (or penalty).");
    RegConsoleCmd("sm_drop",    RandomDrop_Cmd,     "Drop your currently selected weapon or item.");
    
    // Admin and test commands
    RegAdminCmd("rand_test_gnomes", TestGnomes_Cmd, ADMFLAG_CHEATS, "...");
    RegAdminCmd("rand_test_swap",   TestSwap_Cmd,   ADMFLAG_CHEATS, "...");
    RegAdminCmd("rand_test_ents",   TestEnts_Cmd,   ADMFLAG_CHEATS, "...");
    RegAdminCmd("rand_test_event",  TestEvent_Cmd,  ADMFLAG_CHEATS, "...");
        
    /*
        Listen for ghost-exploit check
        -------------------------------
        catching these because there is no way to directly
        detect players going spectator... there's a team switch,
        but no clue whether players were ghosts before then...
        [test if this works on server with config_plugins.cfg order ...]
    */
    RegConsoleCmd("spectate",   Spectate_Cmd,   "...");
    RegConsoleCmd("say",        Say_Cmd,        "...");
    RegConsoleCmd("say_team",   Say_Cmd,        "...");
    
    
    // Blind infected
    g_hBlockedEntities = CreateArray(_:EntInfo);
    CreateTimer(BLND_ENT_CHECK_INTERVAL, Timer_EntCheck, _, TIMER_REPEAT);
}

public OnPluginEnd()
{
    // soundhook
    if (g_bSoundHooked) {
        RemoveNormalSoundHook(Event_SoundPlayed);
    }
    
    // timers
    //if (g_bTimerCheckFirstHuman) { KillTimer(g_hTimerCheckFirstHuman); }
    
    INIT_CVarsReset();
    
    // storm plugin
    SUPPORT_StormReset();
}


public OnClientDisconnect_Post(client)
{
    if (_:g_iSpecialEvent == EVT_KEYMASTER && g_iSpecialEventRole == client) {
        CreateTimer(0.1, Timer_CheckSpecialEventRole, g_bPlayersLeftStart);
        return;
    }
    
    if (!g_bIsTankInPlay || client != g_iTankClient) { return; }
    CreateTimer(0.1, Timer_CheckTankDeath, client);
}

public OnClientPostAdminCheck(client)
{
    /*
    // hook for gnome bonus
    SDKHook(client, SDKHook_WeaponDropPost, Event_DropWeapon);
    */
    
    SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);    // hook for item penalty
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);        // hook for events damage changes
    
    // special case: gunswap ammo count
    if (_:g_iSpecialEvent == EVT_GUNSWAP && IsSurvivor(client))
    {
        CreateTimer(0.1, Timer_CheckSurvivorGun, client, TIMER_FLAG_NO_MAPCHANGE);
    }
    
    // bot gets in, check for gnome-holding
    if (IsFakeClient(client))
    {
        CreateTimer(0.05, Timer_ClientPostAdminCheck_Delayed, client, TIMER_FLAG_NO_MAPCHANGE);
    }
    
    // prevent weapon equip calls from counting after bot-join
    g_bArBlockPickupCall[client] = true;
    CreateTimer(0.01, Timer_UnblockWeaponPickupCall, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action: Timer_ClientPostAdminCheck_Delayed(Handle:timer, any:client)
{
    if (!IsClientAndInGame(client)) { return; }
    
    // check for gnome/cola..
    new holdingEnt = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    new gnomeIndex = FindGnomeIndex(holdingEnt);
    
    if (gnomeIndex != -1) {
        // update gnome, held by different client now
        g_strArGnomes[gnomeIndex][gnomebHeldByPlayer] = true;
        g_strArGnomes[gnomeIndex][gnomeiHoldingClient] = client;
    }
}




public Action: Timer_UnblockWeaponPickupCall(Handle:timer, any:client)
{
    g_bArBlockPickupCall[client] = false;
}

// test
public Action: TestSwap_Cmd(client, args)
{
    EVENT_SwapSurvivorGun(client);
}

public Action: TestGnomes_Cmd(client, args)
{
    // test: are we in saferoom?
    new bool: inStart = IsEntityInSaferoom(client, true, false);
    new bool: inEnd = IsEntityInSaferoom(client, true, true);
    
    PrintToChatAll( "\x01Are we in saferoom? Start: \x03%s\x01 - End: \x03%s\x01", (inStart) ? "yes":"no", (inEnd) ? "yes":"no" );
    PrintToChatAll("gnomebonus: %i", GetGnomeBonus() );
    
    // show a little list of all the known gnomes and their status
    for (new i=0; i < g_iGnomes; i++)
    {
        if (g_strArGnomes[i][gnomebFirstPickup]) {
            PrintToChatAll("gnome/cola [%i]: isCola=%i, pickedUp=%i (%.2f), entity: %i, held?: %i (by: %i)", i, g_strArGnomes[i][gnomebIsCola], g_strArGnomes[i][gnomebFirstPickup], g_strArGnomes[i][gnomefFirstPickup], g_strArGnomes[i][gnomeEntity], g_strArGnomes[i][gnomebHeldByPlayer], g_strArGnomes[i][gnomeiHoldingClient]);
        }
    }
    
    for (new x=0; x < g_iGnomesHeld; x++)
    {
        PrintToChatAll("gnome/cola HELD [%i]: %i", x, g_iArGnomesHeld[x]);
    }

    // test:
    SetEntityHealth(1, 1);
    SetEntPropFloat(1, Prop_Send, "m_healthBuffer", 100.0);
    
    //CheckGnomes();
    
    /*
    // do scoring manip
    new tmpInt = GetRandomInt(1,20);
    
    PrintToChatAll("test: set defibs used for roundhalf %i [team: %i] to: %i", g_bSecondHalf, GameRules_GetProp("m_bAreTeamsFlipped", 4, 0), tmpInt);
    GameRules_SetProp("m_iVersusDefibsUsed", tmpInt, 4, GameRules_GetProp("m_bAreTeamsFlipped", 4, 0) );
    */
}

public Action: TestEnts_Cmd(client, args)
{
    DoItemsServerReport(true);
}
public Action: TestEvent_Cmd(client, args)
{
    // for a special event next round
    decl String:sMessage[MAX_NAME_LENGTH];
    GetCmdArg(1, sMessage, sizeof(sMessage));

    new eventIndex = StringToInt(sMessage);
    
    if (eventIndex < 0 || eventIndex >= EVT_TOTAL)
    {
        if (g_iSpecialEventToForce != -1) {
            PrintToChatAll("[rand_debug] Admin removed event-forcing for next round (previously set to %i).", g_iSpecialEventToForce);
        }
        g_iSpecialEventToForce = eventIndex;
        
        return Plugin_Handled;
    }
    
    // else, force event next round
    PrintToChatAll("[rand_debug] Admin forced event %i for next round (%s)...", eventIndex, g_csEventText[eventIndex]);
    
    g_iSpecialEventToForce = eventIndex;
    
    return Plugin_Handled;
}

/*
    Commands
    -------------------------- */
public Action: RandomReport_Cmd(client, args)
{
    DoReport(client);
    return Plugin_Handled;
}

public Action: RandomBonus_Cmd(client, args)
{
    if (g_bUsingPBonus) {
        EVENT_DisplayRoundPenalty(client);
    } else {
        PrintToChat(client, "\x01[\x05r\x01] This round has no special bonus or penalty.");
    }
    return Plugin_Handled;
}

public Action: RandomDrop_Cmd(client, args)
{
    // only allow when able to drop anything
    if ( !IsSurvivor(client) || !IsPlayerAlive(client) || IsHangingFromLedge(client) || IsIncapacitated(client) ) { return Plugin_Handled; }
    
    if ( SUPPORT_DropItem(client, true, 0, true) ) {
        PrintToChat(client, "\x01[\x05r\x01] Dropped.");
    }
    
    return Plugin_Handled;
}

public Action: Spectate_Cmd(client, args)
{
    if (g_bHasGhost[client]) { g_bSpectateDeath[client] = true; }
    
    return Plugin_Continue;
}
public Action: Say_Cmd(client, args)
{
    // get the string, determine whether it's a legit !spectate command
    new String: full[11];
    GetCmdArgString(full, sizeof(full));
    StripQuotes(full);
    TrimString(full);
    
    if (StrEqual(full, "!spectate")) {
        if (g_bHasGhost[client]) { g_bSpectateDeath[client] = true; }
    }
    
    if (IsChatTrigger())
    {
        decl String:sMessage[MAX_NAME_LENGTH];
        GetCmdArg(1, sMessage, sizeof(sMessage));

        if (StrEqual(sMessage, "!rand")) return Plugin_Handled;
        else if (StrEqual (sMessage, "!drop")) return Plugin_Handled;
        else if (StrEqual (sMessage, "!bonus")) return Plugin_Handled;
        else if (StrEqual (sMessage, "!penalty")) return Plugin_Handled;
        
        // catch 'ready' and 'r' and other chat-attempts at readyup?
        if (StrEqual(sMessage, "ready") || StrEqual(sMessage, "r")) {
            FakeClientCommand(client, "sm_ready");
        }
        else if (StrEqual(sMessage, "unready") || StrEqual(sMessage, "nr")) {
            FakeClientCommand(client, "sm_unready");
        }
    }
    
    return Plugin_Continue;
}




/*
    Round management
    -------------------------- */

public OnMapStart()
{
    /*
        doesn't need a seed..
        // Attempt to get nice random -- use clock
        SetRandomSeed( RoundFloat( GetTime() ) );
    */
    
    // check gamemode for 'coop'
    new String:tmpStr[16];
    GetConVarString(FindConVar("mp_gamemode"), tmpStr, sizeof(tmpStr));
    if (StrEqual(tmpStr, "coop", false)) { g_bCampaignMode = true; } else { g_bCampaignMode = false; }
    
    INIT_PrecacheModels();
    INIT_PrecacheParticles();
    INIT_GetMeleeClasses();
    
    SUPPORT_StormReset();               // safety to catch plugin acting on its own
    
    g_bSecondHalf = false;
    
    if (g_bVeryFirstMapLoad)
    {
        g_bVeryFirstMapLoad = false;
        CreateTimer(DELAY_FIRSTMAPLOAD, SUPPORT_RoundPreparation, _, TIMER_FLAG_NO_MAPCHANGE);
    } else {
        CreateTimer(0.1, SUPPORT_RoundPreparation, _, TIMER_FLAG_NO_MAPCHANGE);
        //SUPPORT_RoundPreparation();     // prepare stuff for this round
    }
    
    // Start checking for humans loading in...
    //g_hTimerCheckFirstHuman = CreateTimer(TIMER_HUMANCHECK, Timer_CheckForHumans, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    //g_bTimerCheckFirstHuman = true;
    CreateTimer(TIMER_HUMANCHECK, Timer_CheckForHumans, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    
    g_bMapStartDone = true;
    g_bInRound = true;
}

public OnMapEnd()
{
    g_bSecondHalf = false;
    g_bInRound = false;
    g_bMapStartDone = false;
    g_bIsFirstAttack = true;
    g_bModelsPrecached = false;
    
    // this causes error spam sometimes... but do we even need it?
    //if (g_bTimerCheckFirstHuman) { KillTimer(g_hTimerCheckFirstHuman); }
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    // this is a bit silly, since roundstart gets called before onmapstart...
    // so just do the round start stuff in onmapstart
    if (g_bMapStartDone && !g_bInRound)
    {
        g_bInRound = true;
        
        CreateTimer(0.1, SUPPORT_RoundPreparation, _, TIMER_FLAG_NO_MAPCHANGE);
        //SUPPORT_RoundPreparation();     // prepare stuff for this round (only second round)
    }
}

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
    // this is only called once in versus games, so we know which round we're in
    g_bSecondHalf = true;
    g_bIsFirstAttack = true;
    
    if (g_bInRound && g_bUsingPBonus)   // only display once, and only when using pbonus
    {
        EVENT_DisplayRoundPenalty();
    }
    
    if (g_bInRound) { g_bInRound = false; }
}

/*  General hooks
    ------------- */

// for blind infected
public Action:OnTransmit(entity, client)
{
    if (GetClientTeam(client) != TEAM_INFECTED) return Plugin_Continue;

    new size = GetArraySize(g_hBlockedEntities);
    decl currentEnt[EntInfo];

    for (new i=0; i < size; i++)
    {
        GetArrayArray(g_hBlockedEntities, i, currentEnt[0]);
        if (entity == currentEnt[iEntity])
        {
            if (currentEnt[hasBeenSeen]) return Plugin_Continue;
            else return Plugin_Handled;
        }
    }
    
    return Plugin_Continue;
}

// for detecting when a player uses a gift box:
public Action:OnPlayerRunCmd(client, &buttons)
{
    if (!IsSurvivor(client) || !IsPlayerAlive(client)) { return Plugin_Continue; }

    if ((buttons & IN_USE))
    {
        if (!RANDOM_PlayerGiftUse(client)) { return Plugin_Handled; }
    }
    return Plugin_Continue;
}

// tank randomization
public Action:L4D_OnTryOfferingTankBot(tank_index, &bool:enterStatis)
{
    // if you don't do this.. double-passes
    if (!IsFakeClient(tank_index)) {
        return Plugin_Continue;
    }
    
    if (GetConVarBool(g_hCvarRandomTank))
    {
        ForceTankPlayer();
    }

    return Plugin_Continue;
}

// for encumbered mode
public Action:L4D_OnGetRunTopSpeed(target, &Float:retVal)
{
    if (_:g_iSpecialEvent != EVT_ENCUMBERED || !IsClientAndInGame(target) || GetClientTeam(target) != TEAM_SURVIVOR) { return Plugin_Continue; }
    
    new Float: fSpeedFactor = SUPPORT_GetSpeedFactor(target);
    if (fSpeedFactor != 1.0) {
        retVal = retVal * fSpeedFactor;
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

public Action: L4D_OnGetWalkTopSpeed(target, &Float:retVal)
{
    if (_:g_iSpecialEvent != EVT_ENCUMBERED || !IsClientAndInGame(target) || GetClientTeam(target) != TEAM_SURVIVOR) { return Plugin_Continue; }
    
    new Float: fSpeedFactor = SUPPORT_GetSpeedFactor(target);
    if (fSpeedFactor != 1.0) {
        retVal = retVal * fSpeedFactor;
        return Plugin_Handled;
    }
    return Plugin_Continue;
}
public Action:L4D_OnGetCrouchTopSpeed(target, &Float:retVal)
{
    if (_:g_iSpecialEvent != EVT_ENCUMBERED || !IsClientAndInGame(target) || GetClientTeam(target) != TEAM_SURVIVOR) { return Plugin_Continue; }
    
    new Float: fSpeedFactor = SUPPORT_GetSpeedFactor(target);
    if (fSpeedFactor != 1.0) {
        retVal = retVal * fSpeedFactor;
        return Plugin_Handled;
    }
    return Plugin_Continue;
}


/*  SDK-Hooks
    ------------- */

// sound catching for silence special event
public Action: Event_SoundPlayed(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{
    if (IsClientAndInGame(entity))
    {
        if (g_iSpecialEventExtra == SILENCED_SURV && IsSurvivor(entity))
        {
            return Plugin_Handled;
        }
        else if (g_iSpecialEventExtra == SILENCED_SI && IsInfected(entity))
        {
            return Plugin_Handled;
        }
    }
    
    return Plugin_Continue;
}  

public Action: OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
    if (_:g_iSpecialEvent != EVT_MINITANKS && _:g_iSpecialEvent != EVT_PROTECT) { return Plugin_Continue; }
    if ( !IsClientAndInGame(victim) || damage == 0.0 ) { return Plugin_Continue; }
    
    // protect, baby player takes more damage (the others less)
    if (_:g_iSpecialEvent == EVT_PROTECT)
    {
        if ( GetClientTeam(victim) != TEAM_SURVIVOR ) { return Plugin_Continue; }
        
        new String: classname[32];
        GetEdictClassname(inflictor, classname, sizeof(classname));
        
        if (StrEqual(classname, "infected", false))
        {
            // CI-to-survivor
            if (victim == g_iSpecialEventRole) {
                damage *= EVENT_PROTECT_CIWEAK;
            } else {
                damage *= EVENT_PROTECT_CISTRONG;
            }
            return Plugin_Changed;
        }
        else if ( IsClientAndInGame(attacker) && GetClientTeam(attacker) == TEAM_INFECTED ) {
            // SI-to-survivor
            if (victim == g_iSpecialEventRole) {
                damage = damage * EVENT_PROTECT_WEAK;
            } else {
                damage = damage * EVENT_PROTECT_STRONG;
            }
            return Plugin_Changed;
        }
    }
    
    if ( !IsClientAndInGame(attacker) ) { return Plugin_Continue; }
    
    // set a fixed damage amount for melee weaps on tank
    if (_:g_iSpecialEvent == EVT_MINITANKS)
    {
        if ( GetClientTeam(attacker) != TEAM_SURVIVOR || GetClientTeam(victim) != TEAM_INFECTED || !IsTank(victim) || !IsValidEdict(inflictor) ) { return Plugin_Continue; }
    
        new String: classname[32];
        GetEdictClassname(inflictor, classname, sizeof(classname));
        
        if (StrEqual(classname, "weapon_melee", false))
        {
            damage = MINITANK_MELEE_DMG;
            return Plugin_Changed;
        }
    }
    
    return Plugin_Continue;
}


/*  Human tracking (join/etc)
    -------------------------- */

public Action: Timer_CheckForHumans(Handle:hTimer)
{
    if (AnyoneLoadedIn()) {
        DoFirstHumanDetected();
        //g_bTimerCheckFirstHuman = false;
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

stock DoFirstHumanDetected()
{
    // finally the first real player loaded in (survivor side)
    
    // report if still necessary:
    if (!g_bFirstReportDone)
    {
        g_hTimerReport = CreateTimer(GetConVarFloat(g_hCvarReportDelay), Timer_RoundStartReport, _, TIMER_FLAG_NO_MAPCHANGE);
        g_bTimerReport = true;
    }

    // hand out gifts, if any 'remain'
    if (g_bSurvHandout) {
        CreateTimer(DELAY_SURVSETUP, Timer_PlayerJoinedSurvivor, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action: Timer_RoundStartReport(Handle:timer)
{
    // do the report
    g_bTimerReport = false;
    if (GetConVarBool(g_hCvarDoReport)) { DoReport(); }
    g_bFirstReportDone = true;
}

public Action: Timer_PlayerJoinedSurvivor(Handle:timer, any:pack)
{
    // just do a general survivor check
    //  should give items early enough
    CheckSurvivorSetup();
}

public Action: Event_PlayerLeftStartArea(Handle:event, const String:name[], bool:dontBroadcast)
{
    g_bIsFirstAttack = false;
    
    // if report hasn't been shown by now, show it!
    if (!g_bFirstReportDone)
    {
        // stop the report timer, if it's running
        if (g_bTimerReport) {
            KillTimer(g_hTimerReport);
            g_bTimerReport = false;
        }
        
        // do the report
        g_bFirstReportDone = true;
        if (GetConVarBool(g_hCvarDoReport)) { DoReport(); }
        
    }
    
    // do special late round prep
    if (!g_bPlayersLeftStart)
    {
        g_bPlayersLeftStart = true;
        CreateTimer(0.1, EVENT_SurvivorsLeftSaferoom, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}




public Action:Event_PlayerTeam(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
    if (!IsClientAndInGame(client)) { return Plugin_Continue; }

    new newTeam = GetEventInt(hEvent, "team");
    new oldTeam = GetEventInt(hEvent, "oldteam");
    
    
    // survivor-based events
    if (_:g_iSpecialEvent == EVT_PEN_ITEM)
    {
        // temporarily block pickup
        g_bArBlockPickupCall[client] = true;
        CreateTimer(0.01, Timer_UnblockWeaponPickupCall, client, TIMER_FLAG_NO_MAPCHANGE);
    }
    else if (_:g_iSpecialEvent == EVT_GUNSWAP && newTeam == TEAM_SURVIVOR)
    {
        CreateTimer(0.1, Timer_CheckSurvivorGun, client, TIMER_FLAG_NO_MAPCHANGE);
    }
    else if (_:g_iSpecialEvent == EVT_KEYMASTER || _:g_iSpecialEvent == EVT_PROTECT)
    {
        if (!g_bSpecialRoleAboutToChange)
        {
            g_bSpecialRoleAboutToChange = true;
            CreateTimer(DELAY_TEAMSWAP, Timer_CheckSpecialEventRole, g_bPlayersLeftStart, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
    // do some delayed checks/changes when people go survivor/infected
    else if (_:g_iSpecialEvent == EVT_NOHUD || _:g_iSpecialEvent == EVT_DEFIB)
    {
        // oddity:  somehow timers swap the order of the infected => spec => survivor switch
        //          so just ignore specs for now
        new Handle:pack = CreateDataPack();
        WritePackCell(pack, client);
        WritePackCell(pack, newTeam);
        CreateTimer(DELAY_TEAMSWAP, Timer_TeamSwapDelayed, pack, TIMER_FLAG_NO_MAPCHANGE);
    }
    
    // ghost spawns:
    if (newTeam == TEAM_INFECTED)
    {
        g_bHasMaterialised[client] = false;
        g_bHasSpawned[client] = false;
        
        CreateTimer(ZC_TIMERCHECKGHOST, Timer_CheckPlayerGhostDelayed, client, TIMER_FLAG_NO_MAPCHANGE);
    }
    else if (newTeam == TEAM_SPECTATOR && oldTeam == TEAM_INFECTED)
    {
        /*
            if they were a ghost (didn't spawn, didn't get tank and didn't die),
            remember and reset when a player returns
            no need to remember if it's still first attack (that's handled)
        */
        if (!g_bIsFirstAttack && g_bHasGhost[client]) {
            new tmpClass = GetEntProp(client, Prop_Send, "m_zombieClass");
            if (tmpClass >= ZC_SMOKER && tmpClass <= ZC_CHARGER)
            {
                g_iSpectateGhost[g_iSpectateGhostCount] = tmpClass;
                if (g_iSpectateGhostCount < (TEAM_SIZE - 1)) {
                    g_iSpectateGhostCount++;
                }
            }
        }
        
    }
    
    if (oldTeam == TEAM_INFECTED) {
        g_bHasGhost[client] = false;
    }
    
    return Plugin_Continue;
}

public Action:Timer_TeamSwapDelayed(Handle:hTimer, any:pack)
{
    ResetPack(pack);
    new client = ReadPackCell(pack);
    new newTeam = ReadPackCell(pack);
    CloseHandle(pack);
    
    if (!IsClientAndInGame(client)) { return; }
    
    // remove / add hud
    if (_:g_iSpecialEvent == EVT_NOHUD && g_bPlayersLeftStart && !IsFakeClient(client))
    {
        if (newTeam == TEAM_INFECTED) {
            HUDRestoreClient(client);
        } else {
            HUDRemoveClient(client);
        }
    }
    // set thirdstrike
    else if (_:g_iSpecialEvent == EVT_DEFIB && newTeam == TEAM_SURVIVOR)
    {
        SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", 1);
        SetEntProp(client, Prop_Send, "m_isGoingToDie", 1);
    }
}



/*  Boomers
    --------------------------
    boomer stuff can't be (cleanly/consistently) done.
    it's a shame, but multiple boomers getting double booms
    on single survivors cannot be correctly detected

    combo's on multiple survivors can be done though, and we're doing it.
*/    
public Event_PlayerBoomed(Handle:event, const String:name[], bool:dontBroadcast)
{
    // only do it if there's a reward window
    if (GetConVarFloat(g_hCvarBoomedTime) == 0.0) { return; }
    
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    
    // only do it for infected booming survivors
    if (!IsSurvivor(client) || !IsInfected(attacker)) { return; }
    
    // boomer combo tracking
    g_iBoomedSurvivors[client] = attacker;
    new alreadyIn = false;
    for (new i = 0; i < TEAM_SIZE; i++)
    {
        if (g_iBoomersInCombo[i] == attacker) {
            g_iBoomsPerBoomer[i]++; // add one to the count
            g_fBoomTime[i] = GetEngineTime();
            alreadyIn = true;
        }
    }
    
    if (!alreadyIn) { 
        for (new i=0; i < TEAM_SIZE; i++)
        {
            if (g_iBoomersInCombo[i] == 0)
            {
                g_iBoomersInCombo[i] = attacker;
                g_iBoomsPerBoomer[i] = 1;
                g_fBoomTime[i] = GetEngineTime();
                //PrintToChatAll("Added to combo tracking: %i: %i", i, attacker);
                break;
            }
        }
        
        // only check/report combo's in this case -- on this boomer's first victim
        BoomerCheckCombo(client);
    }
}

public Event_PlayerUnboomed(Handle:event, const String:name[], bool:dontBroadcast)
{
    // only do it if there is a boom combo reward window
    if (GetConVarFloat(g_hCvarBoomedTime) == 0.0) { return; }
    
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    //PrintToChatAll("Boomer effect wore off (%i)", client);
    
    // remove client/boomer from combo tracking (if 0 survivors are boomed by it)
    if (client < 1 || client > MAXPLAYERS) { return; }
    
    for (new i=0; i < TEAM_SIZE; i++) {
        if (g_iBoomersInCombo[i] == g_iBoomedSurvivors[client]) {
            g_iBoomsPerBoomer[i]--;
            if (g_iBoomsPerBoomer[i] < 1) {
                g_iBoomsPerBoomer[i] = 0;
                //PrintToChatAll("Removing from combo tracking: %i: %i", i, g_iBoomedSurvivors[client]);
                g_iBoomersInCombo[i] = 0;
                g_fBoomTime[i] = 0.0;
            }
        }
    }
    g_iBoomedSurvivors[client] = 0;
}


// see if the boomer tracking shows 2+ combo
public BoomerCheckCombo(victim)
{
    new countBoomers = 0;
    new countTry = 0;
    new Float: fWindowTime = GetConVarFloat(g_hCvarBoomedTime);
    
    for (new i=0; i < TEAM_SIZE; i++) {
        if (g_iBoomersInCombo[i] == 0) { continue; }
        
        countTry = 1;
        
        // try this boomer's boom time as the start of the boom window
        //  if any of the other boomers' booms fit in the window, count them
        for (new j=0; j < TEAM_SIZE; j++) {
            if (j == i || g_iBoomersInCombo[j] == 0) { continue; }
            
            if (g_fBoomTime[j] >= g_fBoomTime[i] && g_fBoomTime[j] <= g_fBoomTime[i] + fWindowTime) {
                countTry++;
            }
        }
        
        //PrintToChatAll("Trying for boomer %i, start time: %.f: %i combo.", i, g_fBoomTime[i], countTry);
        if (countTry > countBoomers) { countBoomers = countTry; }
    }
    
    if (countBoomers > 1) {
        PrintToChatAll("\x01[\x05r\x01] \x04%i\x01-way boomer combo!", countBoomers);
        
        DoBoomerComboReward(countBoomers, victim);
    }
    
    return countBoomers;
}

// give boomers a reward for getting the combo
public DoBoomerComboReward(combo, victim)
{
    // make sure we have a spawning client
    if (!IsClientAndInGame(victim) && !IsFakeClient(victim)) {
        victim = GetSpawningClient();
    }
    if (victim == 0) {
        PrintDebug("[rand] Couldn't reward %i-way boom combo (no spawning client available).", combo);
        return;
    }
    
    // give appropriate reward
    if (combo == 2 || combo == 3 || combo != TEAM_SIZE) {
        g_bBoomHighRewardMode = (combo == 3);
        g_iCommonBoomQueue += BOOMCOMBO_REWARD;
        SpawnCommon(BOOMCOMBO_REWARD);
    } else {
        // reward quad-combo with huge horde
        SpawnPanicHorde(victim, 2);
    }
}

// boomer track
stock ClearBoomerTracking()
{
    for (new i = 1; i <= MAXPLAYERS; i++) {
        g_iBoomedSurvivors[i] = 0;
    }
    for (new i = 0; i < TEAM_SIZE; i++) {
        g_iBoomersInCombo[i] = 0;
        g_iBoomsPerBoomer[i] = 0;
        g_fBoomTime[i] = 0.0;
    }
}




// tracking hunter skeets
public Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{    
    if (_:g_iSpecialEvent != EVT_SKEET) { return; }
    
    new victim = GetClientOfUserId(GetEventInt(event, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    
    if (!IsClientAndInGame(attacker) || GetClientTeam(attacker) != TEAM_SURVIVOR || !IsClientAndInGame(victim) || GetClientTeam(victim) != TEAM_INFECTED) { return; }
    
    new damage =        GetEventInt(event, "dmg_health");
    new damagetype =    GetEventInt(event, "type");
    
    new zombieClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
    
    // track damage (per hit)
    if (zombieClass != ZC_HUNTER) { return; }
    
    // handle old shotgun blast, if there was one
    if (iHunterShotDmg[victim][attacker] > 0 && FloatSub(GetGameTime(), fHunterShotStart[victim][attacker]) > SHOTGUN_BLAST_TIME) {
        fHunterShotStart[victim][attacker] = 0.0;
    }
        
    // handle new hit (only shotgun), and only on pouncing hunters
    if (bHunterPouncing[victim] && damagetype & DMG_BUCKSHOT) {
        
        // first pellet hit?
        if (fHunterShotStart[victim][attacker] == 0.0)
        {
            // new shotgun blast
            fHunterShotStart[victim][attacker] = GetGameTime();
            iHunterShotDmg[victim][attacker] = damage;
        } else {
            // add to current shotgun blast
            iHunterShotDmg[victim][attacker] += damage;
        }
        iHunterShotDmgTeam[victim] += damage;
    }
}

public Event_LungePounce(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (_:g_iSpecialEvent != EVT_SKEET) { return; }
    
    new attacker = GetClientOfUserId(GetEventInt(event, "userid"));

    // clear hunter-hit stats (not skeeted)
    ResetHunter(attacker);
}

// hunters pouncing / tracking
public Event_AbilityUse(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (_:g_iSpecialEvent != EVT_SKEET) { return; }
    
    // track hunters pouncing
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    new String:abilityName[64];
    GetEventString(event, "ability", abilityName, sizeof(abilityName));
    
    if (IsClientAndInGame(client) && strcmp(abilityName, "ability_lunge", false) == 0 && !bHunterPouncing[client])
    {
        // hunter started a pounce
        
        iHunterShotDmgTeam[client] = 0; // reset team damage for each pounce
        
        bHunterPouncing[client] = true;
        CreateTimer(TIMER_POUNCE, Timer_GroundTouch, client, TIMER_REPEAT);
    }
}

public Action: Timer_GroundTouch(Handle:timer, any:client)
{
    if (IsClientAndInGame(client) && (isGrounded(client) || !IsPlayerAlive(client)) )
    {
        // Reached the ground or died in mid-air
        bHunterPouncing[client] = false;
        KillTimer(timer);
    }
}

public bool:isGrounded(client)
{
    return (GetEntProp(client,Prop_Data,"m_fFlags") & FL_ONGROUND) > 0;
}


public ResetHunter(client)
{
    bHunterPouncing[client] = false;
    iHunterShotDmgTeam[client] = 0;
    for (new i=1; i <= MaxClients; i++)
    {
        iHunterShotDmg[client][i] = 0;
        fHunterShotStart[client][i] = 0.0;
    }
}

/*  Player use & item pickup
    ------------------------ */
public Action:Event_PlayerUse(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    new entity = GetEventInt(event, "targetid");
    
    if (!IsValidEntity(entity) || !IsClientAndInGame(client) || IsFakeClient(client) || GetClientTeam(client) != TEAM_SURVIVOR) { return Plugin_Continue; }
    
    new String:classname[128];
    GetEdictClassname(entity, classname, sizeof(classname));
    
    // only if it's a door or a gnome
    new bool: isDoor = StrEqual(classname, "prop_door_rotating");
    new bool: isProp = StrEqual(classname, "prop_physics");
    new bool: isCola = StrEqual(classname, "weapon_cola_bottles");
    
    // check for boobytraps...
    if (_:g_iSpecialEvent == EVT_BOOBYTRAP)
    {
        new Float:targetPos[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", targetPos);
        
        EVENT_CheckBoobyTrap(entity, targetPos, client);
    }
    
    if (!isDoor && !isProp && !isCola) { return Plugin_Continue; }
    
    /*
        new tmpHamId = GetEntProp(door, Prop_Data, "m_iHammerID");
        new tmpData = GetEntPropEnt(door, Prop_Data, "m_hOwnerEntity");
    */
    
    if (isDoor)
    {
        // door:
        
        new bool: inArray = false;
        for (new i = 0; i < g_iDoorsLockedTotal; i++)
        {
            if (entity == g_iDoorsLocked[i]) {
                inArray = true;
                break;
            }
        }
        if (inArray)
        {
            // keymaster event!
            if (_:g_iSpecialEvent == EVT_KEYMASTER)
            {
                if (client != g_iSpecialEventRole) {
                    EmitSoundToAll(DOOR_SOUND, entity);
                    PrintToChat(client, "\x01[\x05r\x01] This door is locked, only keymaster %N may open it.", g_iSpecialEventRole);
                    return Plugin_Continue;
                } else {
                    
                    new doorState = GetEntProp(entity, Prop_Data, "m_eDoorState");
                    
                    AcceptEntityInput(entity, "Unlock");
                    if (doorState == 0) {   // closed
                        AcceptEntityInput(entity, "Open");
                    } else {
                        AcceptEntityInput(entity, "Close");
                    }
                    AcceptEntityInput(entity, "Lock");
                    return Plugin_Continue;
                }
            } else {
                EmitSoundToAll(DOOR_SOUND, entity);
                PrintToChat(client, "\x01[\x05r\x01] This door is locked, break it down.");
            }
        }
    }
    else if (isProp || isCola)
    {
        // gnome/cola:
        if (GetConVarFloat(g_hCvarGnomeBonus) == 0.0) { return Plugin_Continue; }
        
        new String:modelname[STR_MAX_MODELNAME];
        GetEntPropString(entity, Prop_Data, "m_ModelName", modelname, STR_MAX_MODELNAME);
        
        new bool: isGnome = false;
        if (!isCola)
        {
            isGnome = StrEqual(modelname, "models/props_junk/gnome.mdl", false);
            isCola = StrEqual(modelname, "models/w_models/weapons/w_cola.mdl", false);
        }
        
        if (isGnome || isCola)
        {
            if (g_iJustPickedItemUp == GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"))
            {
                new gnomeIndex = FindGnomeIndex(entity);
                
                // set value to max if not found in gnome array, then add to array (if the gnome's in the start saferoom somehow)
                if ( gnomeIndex == -1 && (IsEntityInSaferoom(client, true, false) || IsEntityInSaferoom(entity, false, false) ) )
                {
                    // fix up gnome and array(s) to match
                    UpdateAfterGnomeGiven(client, entity);
                    gnomeIndex = g_iGnomes - 1;
                }
                
                if (gnomeIndex == -1 || !g_strArGnomes[gnomeIndex][gnomebWorthPoints])
                {
                    // weird, unknown gnome
                    if (!g_bCampaignMode) {
                        PrintToChat(client, "\x01[\x05r\x01] This %s is not worth any points.", (isGnome) ? "gnome" : "cola" );
                    }
                }
                else
                {
                    // manage held gnomes array
                    g_iGnomesHeld++;
                    if (g_iGnomesHeld > TEAM_SIZE) { g_iGnomesHeld = 1; PrintDebug("[rand] Excessive 'held gnome/cola' count!"); }
                    g_iArGnomesHeld[g_iGnomesHeld-1] = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
                    
                    if (!g_strArGnomes[gnomeIndex][gnomebFirstPickup])
                    {
                        // first pickup = set value according to flow distance
                        g_strArGnomes[gnomeIndex][gnomebFirstPickup] = true;
                        g_strArGnomes[gnomeIndex][gnomefFirstPickup] = FloatAbs( L4D2Direct_GetFlowDistance(client) / L4D2Direct_GetMapMaxFlowDistance() );
                    }
                    
                    new tmpPoints = GetGnomeValue( g_strArGnomes[gnomeIndex][gnomefFirstPickup] );
                    
                    if (!g_bCampaignMode) {
                        PrintToChat(client, "\x01[\x05r\x01] This %s is worth \x03%i\x01 point%s.", (isGnome) ? "gnome" : "cola", tmpPoints, (tmpPoints > 1) ? "s" : "" );
                        //PrintToChatAll("picked up gnomecola [%i]: %i is now: %i", g_iGnomesHeld, g_strArGnomes[gnomeIndex][gnomeEntity], g_iArGnomesHeld[g_iGnomesHeld-1]);
                    }
                    
                    g_strArGnomes[gnomeIndex][gnomeEntity] = g_iArGnomesHeld[g_iGnomesHeld-1];
                    g_strArGnomes[gnomeIndex][gnomebHeldByPlayer] = true;
                    g_strArGnomes[gnomeIndex][gnomeiHoldingClient] = client;
                }
            }
            
            g_iJustPickedItemUp = 0;
        }
        
    }
    return Plugin_Continue;
}

public Action:Event_ItemPickup(Handle:event, const String:name[], bool:dontBroadcast)
{
    // this gets called first (but only if item was really picked up),
    // so use it to prepare player_use call
    
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (!IsClientAndInGame(client) || GetClientTeam(client) != TEAM_SURVIVOR) { return; }
    
    new String:sItem[32];
    GetEventString(event, "item", sItem, sizeof(sItem));
    
    // debug:
    //PrintToChatAll("picked up: %s", sItem);
    
    // special event:
    if (_:g_iSpecialEvent == EVT_PEN_ITEM)
    {
        // only give penalty outside of saferoom
        if (!SAFEDETECT_IsPlayerInStartSaferoom(client))
        {
            new itemPickupPenalty: itemHasPenalty;
            if (GetTrieValue(g_hTriePenaltyItems, sItem, itemHasPenalty))
            {
                // it's a penaltied item, check if it's really picked up
                g_bArJustBeenGiven[client] = false;
                CreateTimer(TIMER_PICKUPCHECK, Timer_CheckItemPickup, client, TIMER_FLAG_NO_MAPCHANGE);
            }
        }
    }
    
    if (GetConVarFloat(g_hCvarGnomeBonus) == 0.0) { return; }
    
    // gnome
    new bool: isGnome = StrEqual(sItem, "gnome", false);
    new bool: isCola = StrEqual(sItem, "cola_bottles", false);
    
    if (isGnome || isCola)
    {
        g_iJustPickedItemUp = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    }
}

// this is never called:
//public Action:Event_WeaponPickup(Handle:event, const String:name[], bool:dontBroadcast) { }

// for checking whether an item pickup call is really a weapon_given call
public Action:Timer_CheckItemPickup(Handle:hTimer, any:client)
{
    if (g_bArJustBeenGiven[client]) { return Plugin_Continue; }
    
    if (_:g_iSpecialEvent == EVT_PEN_ITEM)
    {
        g_iBonusCount++;
        PBONUS_AddRoundBonus( -1 * EVENT_PENALTY_ITEM );
        EVENT_ReportPenalty(client);
    }
    
    return Plugin_Continue;
}

public Action:OnWeaponEquip(client, weapon)
{
    // SDKHooks weapon equiped
    
    if (!IsValidEntity(weapon) || !IsClientAndInGame(client)) { return Plugin_Continue; }
    if (_:g_iSpecialEvent != EVT_PEN_ITEM) { return Plugin_Continue; }
    if (GetClientTeam(client) != TEAM_SURVIVOR || g_bArBlockPickupCall[client]) { return Plugin_Continue; }
    
    new String: classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));
    
    // debug
    //PrintToChatAll("%N equipped %i: %s", client, weapon, classname);
    
    if (!SAFEDETECT_IsPlayerInStartSaferoom(client))
    {
        new itemPickupPenalty: itemHasPenalty;
        if (GetTrieValue(g_hTriePenaltyItems, classname, itemHasPenalty))
        {
            g_iBonusCount++;
            PBONUS_AddRoundBonus( -1 * EVENT_PENALTY_ITEM );
            EVENT_ReportPenalty(client);
        }
    }
    
    return Plugin_Continue;
}

public Action:Event_WeaponGiven(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (!IsClientAndInGame(client)) { return; }
    
    new weapId = GetEventInt(event, "weapon");
    
    if (weapId == WEPID_PILLS || weapId == WEPID_ADREN)
    {
        g_bArJustBeenGiven[client] = true;
        //PrintToChatAll("weapon given to %N: %i", client, weapId);
    }
}

public Action:Event_WeaponDrop(Handle:event, const String:name[], bool:dontBroadcast)
{
    // this gets called first (but only if item was really picked up),
    // so use it to prepare player_use call
    
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    new entity = GetClientOfUserId(GetEventInt(event, "propid"));

    if (!IsClientAndInGame(client)) { return; }
    if (GetConVarFloat(g_hCvarGnomeBonus) == 0.0) { return; }
    
    new String:sItem[32];
    GetEventString(event, "item", sItem, sizeof(sItem));
    
    if (StrEqual(sItem, "cola_bottles", false))
    {
        // can we find it by entity?
        new gnomeIndex = -1;
        
        if (entity && IsValidEntity(entity)) {
            gnomeIndex = FindGnomeIndex(entity);
        } else {
            gnomeIndex = FindGnomeIndexByClient(client);
            if (gnomeIndex != -1) {
                entity = g_strArGnomes[gnomeIndex][gnomeEntity];
            }
        }
        
        //PrintToChatAll("dropped cola: ent %i (or heldby %i) (index: %i)", entity, client, gnomeIndex);
        
        if (gnomeIndex != -1)
        {
            new found = -1;
            for (new i = 0; i < g_iGnomesHeld; i++) {
                if (entity == g_iArGnomesHeld[i]) {
                    found = i;
                    break;
                }
            }
            
            // cola was dropped, remove from held array
            if (found != -1)
            {
                new gnomeEnt = g_iArGnomesHeld[found];
                RemoveGnomeHeld(gnomeEnt);
                
                //PrintToChatAll("dropped gnome: %i (= %i) (now %i held)", entity, gnomeEnt, g_iGnomesHeld);

                g_iGnomeJustDropped = gnomeEnt;
            }
            
            // adjust gnomes array too
            g_strArGnomes[gnomeIndex][gnomeEntity] = entity; // though it shouldn't be changed
            g_strArGnomes[gnomeIndex][gnomebHeldByPlayer] = false;
            g_strArGnomes[gnomeIndex][gnomeiHoldingClient] = 0;
        }
    }
}


/*  Weapon fire and item use
    ------------------------ */
public Action:Event_PlayerDefibbed(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "subject"));
    if (!IsClientAndInGame(client)) { return; }
    
    // if we're in no-hud mode, hide hud after defib
    if (_:g_iSpecialEvent == EVT_NOHUD && !IsFakeClient(client)) {
        HUDRemoveClient(client);
        return;
    }
    
    new user = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if (_:g_iSpecialEvent == EVT_PEN_HEALTH) {
        g_iBonusCount++;
        PBONUS_AddRoundBonus( -1 * EVENT_PENALTY_HEALTH );
        EVENT_ReportPenalty(user);
    }
    
    // if we want to be entirely spot on, we'll set any solid health to bleed health too
    // if we're doing EVT_DEFIB
    // but meh. random uses bwdefib plugin
}

public Action:Event_MedkitUsed(Handle:event, const String:name[], bool:dontBroadcast)
{
    new user = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if (_:g_iSpecialEvent == EVT_PEN_HEALTH) {
        g_iBonusCount++;
        PBONUS_AddRoundBonus( -1 * EVENT_PENALTY_HEALTH );
        EVENT_ReportPenalty(user);
    }
}

public Action:Event_PillsUsed(Handle:event, const String:name[], bool:dontBroadcast)
{
    new user = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if (_:g_iSpecialEvent == EVT_PEN_HEALTH) {
        g_iBonusCount++;
        PBONUS_AddRoundBonus( -1 * EVENT_PENALTY_HEALTH );
        EVENT_ReportPenalty(user);
    }
}


// shoving
public Action:Event_ShovedPlayer(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "attacker"));
    new victim = GetClientOfUserId(GetEventInt(event, "userid"));
    if (!IsClientAndInGame(client) || GetClientTeam(client) != TEAM_SURVIVOR) { return; }
    if (!IsClientAndInGame(victim) || GetClientTeam(victim) != TEAM_INFECTED) { return; }
    
    //PrintToChatAll("%N shoved player %N.", client, victim);
    
    if (_:g_iSpecialEvent == EVT_PEN_M2) {
        g_iBonusCount++;
        PBONUS_AddRoundBonus( -1 * EVENT_PENALTY_M2_SI );
        EVENT_ReportPenalty(client);
    }
}

// not hooked at this time, no need for it (do so if we want to track/penalty common shoving too)
public Action:Event_ShovedEntity(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "attacker"));
    if (!IsClientAndInGame(client) || GetClientTeam(client) != TEAM_SURVIVOR) { return; }    
    
    new entity = GetClientOfUserId(GetEventInt(event, "entityid"));
    if (!entity || !IsValidEntity(entity)) { return; }
    
    //PrintToChatAll("%N shoved entity %i.", client, entity);
    /*
    if (EVENT_PENALTY_CI && _:g_iSpecialEvent == EVT_PEN_M2) {
        new String: classname[64];
        GetEdictClassname(entity, classname, sizeof(classname));
        
        new CreatedEntityType: classnameShoved;
        if (!GetTrieValue(g_hTrieEntityCreated, classname, classnameShoved)) { return; }
        
        if (classnameShoved == CREATED_INFECTED) 
        {
            g_iBonusCount++;
            PBONUS_AddRoundBonus( -1 * EVENT_PENALTY_M2_CI );
            EVENT_ReportPenalty(client);
        }
    }
    */
}


// weaponfire
public Action:Event_WeaponFire(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (!IsClientAndInGame(client) || GetClientTeam(client) != TEAM_SURVIVOR) { return; }
    
    // only on special event
    if (_:g_iSpecialEvent != EVT_GUNSWAP) { return; }

    // only if the weapon is a primary
    new weapId = GetEventInt(event, "weaponid");
    if (!SUPPORT_IsWeaponPrimary(weapId)) { return; }    
    
    g_iArGunAmmoCount[client]--;
    //PrintToChat(client, "primary fired: %i bullets left", g_iArGunAmmoCount[client]);
    
    if (g_iArGunAmmoCount[client] <= 0)
    {
        EVENT_SwapSurvivorGun(client);
    }
}

/*
    Ghosts and spawning events
    -------------------------- */

public Action:Event_PlayerSpawn(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));

    if (!IsClientAndInGame(client) || IsFakeClient(client) || GetClientTeam(client) != TEAM_INFECTED) { return Plugin_Continue; }
    if (!g_bHasSpawned[client]) { ClearSpawnGhostTimer(client); }
    g_bHasSpawned[client] = true;
    g_bHasGhost[client] = false;

    return Plugin_Continue;
}
public Action:Event_PlayerDeath(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
    new victim = GetClientOfUserId(GetEventInt(hEvent, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(hEvent, "attacker")); 
    
    if (!victim) {
        // common infected died
        new common = GetEventInt(hEvent, "entityid");
        
        if (GetRandomFloat(0.001, 1.0) <= GetConVarFloat(g_hCvarItemDropChance))
        {
            new Float: loc[3];
            new Float:vel[3];
            
            GetEntPropVector(common, Prop_Send, "m_vecOrigin", loc);
            loc[2] += 10.0;
            vel[0] = GetRandomFloat(-80.0, 80.0);
            vel[1] = GetRandomFloat(-80.0, 80.0);
            vel[2] = GetRandomFloat(40.0, 80.0);
            
            // pick a random item (different list) and spawn it
            SpawnCommonItem(loc, vel);
        }
        
        return Plugin_Continue;
    }
    
    if (!IsClientAndInGame(victim)) { return Plugin_Continue; }

    
    // survivor dies
    // -------------------
    if (IsSurvivor(victim))
    {
        // remove hud if we're in special event
        if (_:g_iSpecialEvent == EVT_NOHUD && !IsFakeClient(victim)) {
            HUDRemoveClient(victim);
        }
        else if ( (_:g_iSpecialEvent == EVT_KEYMASTER || _:g_iSpecialEvent == EVT_PROTECT) && g_iSpecialEventRole == victim) {
            CreateTimer(0.1, Timer_CheckSpecialEventRole, true, TIMER_FLAG_NO_MAPCHANGE);
        }
        
        // check gnome status
        new gnomeIndex = FindGnomeIndexByClient(victim);
        
        if (gnomeIndex == -1) {
            gnomeIndex = FindGnomeIndex( GetEntPropEnt(victim, Prop_Send, "m_hActiveWeapon") );
        }
        
        if (gnomeIndex != -1) {
            // update gnome, not held anymore
            RemoveGnomeHeld(g_strArGnomes[gnomeIndex][gnomeEntity]);
            
            g_strArGnomes[gnomeIndex][gnomebHeldByPlayer] = false;
            g_strArGnomes[gnomeIndex][gnomeiHoldingClient] = 0;
        }
    }
    // -------------------
    
    if (!IsClientAndInGame(attacker) || GetClientTeam(victim) != TEAM_INFECTED) { return Plugin_Continue; }
    
    // track hunter skeets?
    if (_:g_iSpecialEvent == EVT_SKEET && GetEntProp(victim, Prop_Send, "m_zombieClass") == ZC_HUNTER)
    {
        //PrintToChatAll("hunter died: %i dmg / %i team dmg", iHunterShotDmg[victim][attacker], iHunterShotDmgTeam[victim]);             
        
        if (iHunterShotDmg[victim][attacker] > 0) {
            // skeet?
            new iPounceInterrupt = GetConVarInt(FindConVar("z_pounce_damage_interrupt"));
            if (iHunterShotDmg[victim][attacker] >= iPounceInterrupt) {
                // single player's skeet
                EVENT_HandleSkeet(attacker, victim);
            }
            else if (iHunterShotDmgTeam[victim] >= iPounceInterrupt) {
                // team skeet
                EVENT_HandleSkeet(-2, victim);
            }
        }
        
        iHunterShotDmgTeam[victim] = 0;
        iHunterShotDmg[victim][attacker] = 0;
        bHunterPouncing[victim] = false;
    }
    
    if (!IsFakeClient(victim))
    {
        // sack protection, check if someone got a ghost and doesn't have a first death set yet
        g_fGotGhost[victim] = 0.0;
        g_fDeathAfterGhost[victim] = 0.0;
        
        if (!g_bIsFirstAttack)        // just a safeguard against false detections
        {
            for (new i=0; i <= MaxClients; i++) {
                if (i == victim) { continue; }
                
                if (g_fGotGhost[i] != 0.0 && g_fDeathAfterGhost[i] == 0.0 && GetGameTime() - g_fGotGhost[i] > SACKPROT_MARGIN)
                {
                    g_fDeathAfterGhost[i] = GetGameTime();
                }
            }
        }
        
        g_bHasMaterialised[victim] = false;
        g_bHasSpawned[victim] = false;
        
        /*
            this is also called when a player spectates
            so we have to distinguish between an actual death and a 'spectate death'
        */
        if (!g_bSpectateDeath[victim]) {
            g_bHasGhost[victim] = false;
        } else {
            g_bSpectateDeath[victim] = false;
        }
    }
    
    // tank stuff:
    if (!g_bIsTankInPlay || victim != g_iTankClient) { return Plugin_Continue; }
    
    // remember place where tank died
    GetClientAbsOrigin(victim, g_fTankDeathLocation);
    //GetEntPropVector(victim, Prop_Send, "m_vecOrigin", g_fTankDeathLocation); <- better or worse? test.
    
    CreateTimer(0.1, Timer_CheckTankDeath, victim); // Use a delayed timer due to bugs where the tank passes to another player
    
    return Plugin_Continue;
}

public Action:Event_TankSpawned(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
    
    // tank stuff:
    g_iTankClient = client;
    if (!g_bIsTankInPlay) {
        g_bIsTankInPlay = true;
    }
    
    // if we have multitanks, prepare next
    if (_:g_iSpecialEvent == EVT_MINITANKS)
    {
        CreateTimer(1.0, Timer_PrepareNextTank, _, TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(1.0, Timer_SetTankMiniScale, client, TIMER_FLAG_NO_MAPCHANGE);
    }
    else if (!g_bFirstTankSpawned)  // double tank ?
    {
        g_bFirstTankSpawned = true;
        
        // spawn second
        if (g_bDoubleTank) {
            CreateTimer(1.0, Timer_PrepareNextTank, _, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
    
    // ghost stuff:
    if (!IsClientAndInGame(client) || IsFakeClient(client)) { return Plugin_Continue; }
    
    g_bHasGhost[client] = false;
    
    return Plugin_Continue;
}

public Action:Timer_SetTankMiniScale(Handle:hTimer, any:client)
{
    if (IsClientAndInGame(client)) {
        // set model size
        SetEntPropFloat(client, Prop_Send,"m_flModelScale", MINITANKS_SCALE);
    }
}

public Action:Event_TankFrustrated(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));

    g_bHasMaterialised[client] = false;
    g_bHasSpawned[client] = false;
    g_bHasGhost[client] = false;
    
    g_hSpawnGhostTimer[client] = CreateTimer(ZC_TIMERAFTERTANK, Timer_SpawnGhostClass, client, TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Continue;
}
public Action:Event_GhostSpawnTime(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));

    if (!IsClientAndInGame(client) || IsFakeClient(client)) { return Plugin_Continue; }
    if (IsPlayerAlive(client)) { return Plugin_Continue; }

    new Float: fSpawnTime = GetEventFloat(hEvent, "spawntime");
    
    if (g_hSpawnGhostTimer[client] == INVALID_HANDLE) {
        g_hSpawnGhostTimer[client] = CreateTimer(fSpawnTime - ZC_TIMEROFFSET, Timer_SpawnGhostClass, client, TIMER_FLAG_NO_MAPCHANGE);
    }

    g_bHasMaterialised[client] = false;
    g_bHasSpawned[client] = false;

    return Plugin_Continue;
}

public Action:Timer_CheckPlayerGhostDelayed(Handle:hTimer, any:client)
{
    if (IsClientAndInGame(client) && IsValidEntity(client) && IsPlayerGhost(client)) {
        DetermineSpawnClass(client, GetEntProp(client, Prop_Send, "m_zombieClass"));
    }

}

public Action:Timer_SpawnGhostClass(Handle:hTimer, any:client)
{
    g_hSpawnGhostTimer[client] = INVALID_HANDLE;

    if (!IsClientAndInGame(client) || IsFakeClient(client) || GetClientTeam(client) != TEAM_INFECTED) { return Plugin_Continue; }
    if (!IsPlayerAlive(client)) {
        CreateTimer(ZC_TIMERDEATHCHECK, Timer_SpawnGhostClass, client, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Continue;
    }
    if (!IsValidEntity(client) || !IsPlayerGhost(client)) { return Plugin_Continue; }
    
    DetermineSpawnClass(client, GetEntProp(client, Prop_Send, "m_zombieClass"));

    return Plugin_Continue;
}

public ClearSpawnGhostTimer(any:client)
{
    if (g_hSpawnGhostTimer[client] != INVALID_HANDLE) {
        CloseHandle(g_hSpawnGhostTimer[client]);
        g_hSpawnGhostTimer[client] = INVALID_HANDLE;
    }
}

public Action:Timer_CheckTankDeath(Handle:hTimer, any:client_oldTank)
{
    if (g_iTankClient != client_oldTank) { return Plugin_Continue; }
 
    new tankclient = FindTankClient();
    if (tankclient && tankclient != client_oldTank)
    {
        g_iTankClient = tankclient;
        return Plugin_Continue;
    }
    
    // do whatever you do when tank is dead...
    g_bIsTankInPlay = false;
    
    // drop stuff?
    if (_:g_iSpecialEvent != EVT_MINITANKS) {
        RANDOM_TankDropItems();
    }
    
    return Plugin_Continue;
}

/*
    Uncommon infected spawning
    and pipebomb dudding
    -------------------------- */
public OnEntityCreated(entity, const String:classname[])
{
    if (!g_bModelsPrecached) { return; }
    if (entity < 1 || !IsValidEntity(entity) || !IsValidEdict(entity)) { return; }
    
    //PrintToChatAll("created: %s", classname);
    
    new CreatedEntityType: classnameOEC;
    if (!GetTrieValue(g_hTrieEntityCreated, classname, classnameOEC)) { return; }
    
    if (classnameOEC == CREATED_INFECTED) 
    {
        
        new Float: fChance = GetConVarFloat(g_hCvarUncommonChance);
        new bool: isUncommon = false;
        
        if (g_iSpecialEvent == _:EVT_UNCOMMON) { fChance = EVENT_UNCOMMON_CHANCE; }
        else if (g_iSpecialEvent == _:EVT_CLOWNS) { fChance = EVENT_CLOWNS_CHANCE; }
            
        // common infected, chance to spawn something else:
        if (g_iCommonBoomQueue == 0 && GetRandomFloat(0.001,1.0) <= fChance)
        {
            isUncommon = true;
            if (GetRandomFloat(0.001,1.0) <= GetConVarFloat(g_hCvarJimmyChance))
            {
                SetEntityModel(entity, "models/infected/common_male_jimmy.mdl");
            }
            else if (GetRandomFloat(0.001,1.0) <= GetConVarFloat(g_hCvarFallenChance))
            {
                SetEntityModel(entity, "models/infected/common_male_fallen_survivor.mdl");
            }
            else
            {
                if ((g_iSpecialEvent != _:EVT_UNCOMMON && g_iSpecialEvent != _: EVT_CLOWNS)
                    || g_iSpecialEventExtra == -1)
                {
                    SetEntityModel(entity, g_csUncommonModels[GetRandomInt(0, sizeof(g_csUncommonModels) - 1)]);
                } else {
                    // special event picked one type
                    SetEntityModel(entity, g_csUncommonModels[g_iSpecialEventExtra]);
                }
            }
        }
        
        // check boom queue
        if (g_iCommonBoomQueue > 0)
        {
            // this is an infected that was spawned by a boomer effect
            
            // so it is made, as a reward, an uncommon
            if (!isUncommon) {
                if (!g_bBoomHighRewardMode) {
                    // low reward: clowns, mudmen or construction workers
                    SetEntityModel(entity, g_csUncommonModels[ GetRandomInt(2, 4) ]);
                } else {
                    // high reward: riot COPSJ (index 0)
                    SetEntityModel(entity, g_csUncommonModels[0]);
                }
            }
            
            SetEntProp(entity, Prop_Send, "m_mobRush", 2);
            new ticktime = RoundToNearest( FloatDiv( GetGameTime() , GetTickInterval() ) ) + 5;
            SetEntProp(entity, Prop_Data, "m_nNextThinkTick", ticktime);
            
            ActivateEntity(entity);
            
            // clear the queue so we don't keep spawning
            g_iCommonBoomQueue--;
        }
    }
    else if (classnameOEC == CREATED_PIPEBOMB)
    {
        // this is not always a pipebomb (thanks valve :/)
        CreateTimer( 0.1, Timer_PipeCheck, entity);
    }
    else if (classnameOEC == CREATED_PROP_PHYSICS)
    {
        // is really the gnome?
        if (GetConVarFloat(g_hCvarGnomeBonus) == 0.0) { return; }
        
        CreateTimer(0.05, Timer_CreatedPropPhysics, entity);
    }
}

public Action: Timer_CreatedPropPhysics(Handle:timer, any:entity)
{
    // now the gnome we held is destroyed, so only check if we did drop one
    if (!IsValidEntity(entity) || !g_iGnomeJustDropped) { return Plugin_Continue; }
    
    new String:modelname[STR_MAX_MODELNAME];
    GetEntPropString(entity, Prop_Data, "m_ModelName", modelname, STR_MAX_MODELNAME);
    
    new bool: isGnome = StrEqual(modelname, "models/props_junk/gnome.mdl", false);
    new bool: isCola = StrEqual(modelname, "models/w_models/weapons/w_cola.mdl", false);
    if (isGnome || isCola)
    {
        new gnomeIndex = FindGnomeIndex(g_iGnomeJustDropped);
        
        if (gnomeIndex != -1) {
            g_strArGnomes[gnomeIndex][gnomeEntity] = entity;
            g_strArGnomes[gnomeIndex][gnomebHeldByPlayer] = false;
            g_strArGnomes[gnomeIndex][gnomeiHoldingClient] = 0;
            
            //PrintToChatAll("gnome drop continued: %i => %i", g_iGnomeJustDropped, entity);
        }
        
        g_iGnomeJustDropped = 0;
    }
    
    return Plugin_Continue;
}


public OnEntityDestroyed(entity)
{
    // can't check entity properties (since it's already destroyed)
    // so just check if a gnome was just created...
    
    if (g_iGnomesHeld && GetConVarFloat(g_hCvarGnomeBonus) >= 0.0)
    {
        new found = -1;
        for (new i = 0; i < g_iGnomesHeld; i++) {
            if (entity == g_iArGnomesHeld[i]) {
                found = i;
                break;
            }
        }
        
        // yup, a gnome was dropped
        if (found != -1)
        {
            new gnomeEnt = g_iArGnomesHeld[found];
            RemoveGnomeHeld(gnomeEnt);
            g_iGnomeJustDropped = gnomeEnt;
        }
    }
}


public Action:Timer_PipeDud(Handle:timer, any:entity)
{
    // dudding pipebomb (simple kill)
    PrintToChatAll("\x01[\x05r\x01] Pipebomb was a dud!");
    AcceptEntityInput(entity, "Kill");
}

public Action:Timer_PipeCheck(Handle:timer, any:entity)
{
    // only proceed if it is really a pipe
    if (!IsValidEntity(entity)) { return; }
    
    new String:classname[64];
    GetEdictClassname(entity, classname, sizeof(classname));
    if (!StrEqual(classname, "pipe_bomb_projectile", false)) { return; }
    
    // dud chance...
    if (GetRandomFloat(0.001,1.0) <= GetConVarFloat(g_hCvarPipeDudChance)) {
        CreateTimer( PIPEDUD_MINTIME + GetRandomFloat(0.0, PIPEDUD_ADDTIME) , Timer_PipeDud, entity);
    }    
}



/*
    SI Spawning
    -------------------------- */
public GetClassForFirstAttack(ignoreClient)
{
    // check the current spawns up and compare them to the stored spawns
    //  add one that isn't up yet
    
    new classCount[ZC_TOTAL], neededCount[ZC_TOTAL], classType;
    
    for (new i=1; i <= MaxClients; i++)
    {
        if (i == ignoreClient) { continue; }                                // so it doesn't count the client's class that it is about to change..

        if (IsClientInGame(i) && GetClientTeam(i) == TEAM_INFECTED) {
            if (IsValidEntity(i) && IsPlayerAlive(i)) {
                classType = GetEntProp(i, Prop_Send, "m_zombieClass");
                if (classType < 0 || classType > ZC_TOTAL - 1) { classType = 0; }  // safeguard
                classCount[classType]++;
            }
        }
    }
        
    // got all the counts, check what we still need
    for (new j=0; j < TEAM_SIZE; j++) {
        classType = g_iArStorageSpawns[j];
        neededCount[classType]++;
    }
    
    // if any class still needs a spawn, return it
    for (new j = ZC_SMOKER; j <= ZC_CHARGER; j++) {
        if (classCount[j] < neededCount[j]) { return j; }
    }
    
    // shouldn't happen, but just return hunter
    PrintDebug("[random spawns] error, no first attack storage entry found. should never happen");
    return ZC_HUNTER;
}


public InitSpawnArrays()
{
    for (new i=1; i <= MaxClients; i++) {
        g_bHasMaterialised[i] = false;
        g_bHasSpawned[i] = false;
        g_bHasGhost[i] = false;
        g_bSpectateDeath[i] = false;
        g_hSpawnGhostTimer[i] = INVALID_HANDLE;
    }
}


// special ammo types
//      used to limit amount of special ammo in extra clip..
public Action:Event_SpecialAmmo(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    new upgradeid = GetEventInt(event, "upgradeid");
    decl String:class[256];
    GetEdictClassname(upgradeid, class, sizeof(class));
    
    if (!IsClientAndInGame(client)) { return; }
    if (StrEqual(class, "upgrade_laser_sight")) { return; }
    
    // get clipsize for special ammo, apply factor
    new gunEnt = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEdict(gunEnt)) { return; }
    
    new oldAmmo = GetEntProp(gunEnt, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", 1);
    new newAmmo = 0;
    
    if (StrEqual(class, "upgrade_ammo_incendiary"))
    {
        newAmmo = RoundFloat(float(oldAmmo) * GetConVarFloat(g_hCvarClipFactorInc));
        SetEntProp(gunEnt, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", newAmmo, 1);
    }
    else if (StrEqual(class, "upgrade_ammo_explosive"))    
    {
        newAmmo = RoundFloat(float(oldAmmo) * GetConVarFloat(g_hCvarClipFactorExp));
        SetEntProp(gunEnt, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", newAmmo, 1);
    }
}




// reset gnomes status
stock ResetGnomes()
{
    g_iGnomes = 0;
    for (new x=0; x < GNOME_MAX_COUNT; x++)
    {
        g_strArGnomes[x][gnomebIsCola] = false;
        g_strArGnomes[x][gnomebWorthPoints] = true;
        g_strArGnomes[x][gnomebHeldByPlayer] = false;
        g_strArGnomes[x][gnomeiHoldingClient] = 0;
        g_strArGnomes[x][gnomebFirstPickup] = false;
        g_strArGnomes[x][gnomefFirstPickup] = 9999.0;
        g_strArGnomes[x][gnomeEntity] = -1;
    }
    
    g_iGnomesHeld = 0;
    for (new x=0; x < TEAM_SIZE; x++)
    {
        g_iArGnomesHeld[x] = 0;
    }
    
}

stock FindGnomeIndex(entity)
{
    for (new x=0; x < g_iGnomes; x++)
    {
        if (g_strArGnomes[x][gnomeEntity] == entity) {
            return x;
        }
    }
    return -1;
}

stock FindGnomeIndexByClient(client)
{
    for (new x=0; x < g_iGnomes; x++)
    {
        if (g_strArGnomes[x][gnomeiHoldingClient] == client) {
            return x;
        }
    }
    return -1;
}

stock FindGnomeHeldIndex(entity)
{
    for (new i=0; i < g_iGnomesHeld; i++)
    {
        if (g_iArGnomesHeld[i] == entity) { return i; }
    }
    return -1;
}

stock RemoveGnomeHeld(entity)
{
    // unsets a gnome as held (and cleans up the array)
    new found = FindGnomeHeldIndex(entity);
    
    if (found != -1)
    {
        g_iArGnomesHeld[found] = 0;
        if (found + 1 < g_iGnomesHeld) {
            for (new i = found; i < g_iGnomesHeld - 1; i++) {
                g_iArGnomesHeld[i] = g_iArGnomesHeld[i+1];
            }
        }
        g_iGnomesHeld--;
    }
}

UpdateAfterGnomeGiven(client, entity=-1, bool:setHeld=true)
{
    // if a client is handed a gnome (at round start)
    if (!IsSurvivor(client)) { return; }
    
    
    g_iGnomes++;
    g_strArGnomes[g_iGnomes-1][gnomebFirstPickup] = true;
    g_strArGnomes[g_iGnomes-1][gnomefFirstPickup] = 0.0;
    if (entity == -1) {
        g_strArGnomes[g_iGnomes-1][gnomeEntity] = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    } else {
        g_strArGnomes[g_iGnomes-1][gnomeEntity] = entity;
    }
    g_strArGnomes[g_iGnomes-1][gnomebHeldByPlayer] = true;
    g_strArGnomes[g_iGnomes-1][gnomeiHoldingClient] = client;
    
    // if it's not in held gnome array, add it
    if (setHeld && FindGnomeHeldIndex( g_strArGnomes[g_iGnomes-1][gnomeEntity] ) == -1)
    {
        g_iGnomesHeld++;
        g_iArGnomesHeld[g_iGnomesHeld-1] = g_strArGnomes[g_iGnomes-1][gnomeEntity];
    }
}


// value of a gnome when picked up at given distance
GetGnomeValue(Float:distance)
{
    distance = FloatAbs(distance);
    new Float: fBonus = GetConVarFloat(g_hCvarGnomeBonus);
    
    if (L4D_IsMissionFinalMap())
    {
        fBonus = fBonus * GetConVarFloat(g_hCvarGnomeFinaleFactor);
        
        // weigh distance for only this factor, if we're going by distance
        if (fBonus < 10.0) {
            fBonus = fBonus * L4D_GetVersusMaxCompletionScore();
            // factor in distance factor (get right average between full and distance-scaled bonus)
            fBonus = ((1.0 - GNOME_FINALE_DIST_FACTOR) * fBonus) + (GNOME_FINALE_DIST_FACTOR * fBonus * (1.0 - distance));
        }
    } else {
        if (fBonus < 10.0) {
            fBonus = fBonus * L4D_GetVersusMaxCompletionScore() * (1.0 - distance);
        }
    }
    
    return RoundToCeil( fBonus );
}

GetGnomeBonus(bool:showMessage = false)
{
    /*
        This gets called internally only on round-end to display the result
        This gets called by l4d2_random_bonus to actually calculate/get the bonus working
            showMessage is only set by internal calls
    */
    
    // check if gnomes are held
    // check which gnomes are in saferoom as props
    
    new countGnomes = 0;
    new countCola = 0;
    new countPoints = 0;
    
    // only do calc if there can be bonus at all
    if (GetConVarFloat(g_hCvarGnomeBonus) == 0.0) { return 0; }
    
    for (new i=0; i < g_iGnomes; i++)
    {
        //PrintToChatAll("gnome %i: held: %i, insafe: %i...", i, g_strArGnomes[i][gnomebHeldByPlayer], IsEntityInSaferoom( g_strArGnomes[i][gnomeEntity] , false, true) );
        
        // is it in saferoom?
        if (!g_strArGnomes[i][gnomebHeldByPlayer] && !IsEntityInSaferoom( g_strArGnomes[i][gnomeEntity], false, true)) { continue; }
        if (!g_strArGnomes[i][gnomebFirstPickup] || !g_strArGnomes[i][gnomebWorthPoints]) { continue; }
        
        if (!g_strArGnomes[i][gnomebIsCola]) { countGnomes++; } else { countCola++; }
        
        countPoints += GetGnomeValue(g_strArGnomes[i][gnomefFirstPickup]);
    }
    
    if (!countGnomes && !countCola) { return 0; }
    
    if (showMessage) {
        new String: msgPart[128] = "";
        if (countGnomes) {
            Format(msgPart, sizeof(msgPart), "\x03%i\x01 gnome%s%s", countGnomes, (countGnomes == 1) ? "" : "s", (countCola) ? " and " : "" );
        }
        if (countCola) {
            Format(msgPart, sizeof(msgPart), "%s\x03%i\x01 colapack%s", msgPart, countCola, (countCola == 1) ? "" : "s");
        }
        
        PrintToChatAll("\x01[\x05r\x01] Survivors brought %s, worth \x04%i\x01 bonus point%s.", msgPart, countPoints, (countPoints == 1) ? "" : "s"  );
    }
    
    return countPoints;
}

