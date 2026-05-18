
{ � Inquisition's Timer Services Unit � }

{ � This file is part of the Inquisition Sound Server for the Free � }
{ � Pascal Compiler (http://www.freepascal.org) but also can be    � }
{ � be distributed separately. The source code is FREE FOR ANY NON � }
{ � COMMERCIAL USAGE.                                              � }
{ � You can modify this file, but you musn't distribute the        � }
{ � modified file, only the original version. Instead, send your   � }
{ � modification to us, so we can add it to the official version.  � }
{ � Please note, that we can't quarantee the compatibility with    � }
{ � previous versions.                                             � }
{ � If we'll stop the development of this unit in the future,      � }
{ � the source code will be freely available for any use.          � }

{ � You can always download the newest version from our website,  � }
{ � http://scenergy.dfmk.hu/inqcoders/                            � }
{ � About Inquisition itself, see                                 � }
{ � http://scenergy.dfmk.hu/inquisition/                          � }

{ � Comments, notes, suggestions, bug reports are welcome.      � }
{ � Send your mails to charlie@scenergy.dfmk.hu                 � }
{ � Please prefer hungarian or english languages.               � }

{ � ISS_TIM - Timer Unit (GO32V2 Only!)      � }
{ � Coding Starts     : 10. October. 1998.   � }
{ � Last Modification : 01. March. 2001.     � }

{ � Note: req. FPC version 1.0.0+ for GO32V2 to compile � }

{$ASMMODE INTEL}
{$MODE FPC}
Unit ISS_Tim;

Interface

Uses GO32;

Const ISS_TimerSpeed  : DWord = 1193180;
      ISS_MaxTimers   = $8; { � Maximum Number of Timers  � }

      TimerIRQ        = $8; { � HW IRQ Number � }

      ISS_TENoFree   = $01; { � Can't add new timer. All timers locked. � }
      ISS_TENotFound = $02; { � Can't find specified Timer, to stop. � }

Type TTimerStruc = Record
       TSpeed     : DWord;
       TCount     : DWord;     { � Tick Counter � }
       TPrevCount : DWord;     { � Tick Counter state at prev. activity � }
       TProc      : Pointer;   { � Procedure To Call Offset � }
       TActive    : Boolean;   { � 1 If The Timer Is On � }
      End;

Var ISS_TimersData : Array[1..ISS_MaxTimers] Of TTimerStruc;
    ISS_TimerError : DWord; { � Contains the last timer error code. � }

Function ISS_StartTimer(Var NewTProc : Pointer; NewTSpeed : DWord) : Boolean;
Function ISS_StopTimer(Var TimerProc : Pointer) : Boolean;
Function ISS_GetTimerNumber(TimerProc : Pointer) : DWord;

Implementation

Var IntStack        : array[0..4095] of byte;

Var TimerSpeed      : DWord;
    OldTimer        : TSegInfo;
    OldTimerCnt     : DWord;
    NewIRQActive    : Boolean;
    NewTimerHandler : TSegInfo;
    BackupDS        : Word; External Name '___v2prt0_ds_alias';


Procedure UpdateUserTimers;
Type Proc   = Procedure;
Var Counter : Word;
Begin
 For Counter:=1 To ISS_MaxTimers Do Begin
   With ISS_TimersData[Counter] Do Begin
     If TActive Then Begin
       Inc(TCount,TimerSpeed);
       If (TCount>TSpeed) Then Begin
         Dec(TCount,TSpeed);
         TPrevCount:=TCount;
         Proc(TProc); { � Calling the specified routine � }
        End;
      End;
    End;
  End;
End;
Procedure UpdateUserTimers_Dummy; Begin End;

Procedure SysTimerIRQ; Assembler;
Asm
  CLI
  PUSH   DS
  PUSH   ES
  PUSH   FS
  PUSH   GS
  PUSHAD

  { with DPMI, the stack is not DS/ES, but a minimal 4K locked pm stack dedicated for interrupts, switch to DS }
  MOV    CX, SS
  MOV    EDX, ESP
  MOV    AX,CS:[BackupDS]
  MOV    SS, AX
  LEA    ESP, IntStack+4096
  PUSH   CX
  PUSH   EDX

  MOV    DS,AX
  MOV    ES,AX
  MOV    AX,DosMemSelector
  MOV    FS,AX

  CALL   UpdateUserTimers

  MOV    EAX,TimerSpeed
  ADD    OldTimerCnt,EAX
  CMP    OldTimerCnt,$10000
  JB     @NotUpdateClock

    SUB   OldTimerCnt,$10000
    INC   WORD PTR FS:[1132]
    JNZ   @Timer_2
    INC   WORD PTR FS:[1134]
    @Timer_2:
    MOV  AX,$018
    CMP  FS:[1134],AX
    JNZ  @Timer_3
    MOV  AX,$0B0
    CMP  FS:[1132],AX
    JNZ  @Timer_3
    MOV  WORD PTR FS:[1134],$0
    MOV  WORD PTR FS:[1132],$0
    MOV  BYTE PTR FS:[1136],$1
    @Timer_3:

  @NotUpdateClock:
  MOV   DX,$20 { � Interrupt request acknowledge � }
  MOV   AL,$20
  OUT   DX,AL

  {restore old stack}
  POP   EDX
  POP   CX
  MOV   SS, CX
  MOV   ESP, EDX

  POPAD
  POP   GS
  POP   FS
  POP   ES
  POP   DS
  IRET
End;
Procedure SysTimerIRQ_Dummy; Begin End;

Procedure SetTimerSpeed(NewTimerSpeed : DWord);
Begin
 If NewTimerSpeed<>TimerSpeed Then Begin
   Asm
    PUSH EAX
    CLI
    MOV  AL,00110110B
    OUT  43H,AL
    MOV  EAX,NEWTIMERSPEED
    OUT  40H,AL
    MOV  AL,AH
    OUT  40H,AL
    STI
    POP  EAX
   End;
   TimerSpeed:=NewTimerSpeed;
  End;
End;

Function GetTimerSpeed : DWord;
Var Counter  : DWord;
    TFastest : DWord;
Begin
 TFastest:=$10000;
 For Counter:=1 To ISS_MaxTimers Do Begin
   If ISS_TimersData[Counter].TActive And
      (ISS_TimersData[Counter].TSpeed < TFastest) Then
     TFastest:=ISS_TimersData[Counter].TSpeed;
  End;
 GetTimerSpeed:=TFastest;
End;

Function ISS_StartTimer(Var NewTProc : Pointer; NewTSpeed : DWord) : Boolean;
Var Counter : Word;
    TNumber : Word;
Begin
 Counter:=0; TNumber:=0;
 Repeat
  Inc(Counter);
  If Not ISS_TimersData[Counter].TActive Then TNumber:=Counter;
 Until (TNumber<>0) Or (Counter=ISS_MaxTimers);
 If TNumber=0 Then Begin
   ISS_TimerError:=ISS_TENoFree;
   ISS_StartTimer:=False;
   Exit;
  End;
 If Not NewIRQActive Then Begin
   Lock_Data(ISS_TimersData,SizeOf(ISS_TimersData));
   Lock_Data(DosMemSelector,SizeOf(DosMemSelector));
   Lock_Code(@SysTimerIRQ,DWord(@SysTimerIRQ_Dummy)-DWord(@SysTimerIRQ));
   Lock_Code(@UpdateUserTimers,DWord(@UpdateUserTimers_Dummy)-DWord(@UpdateUserTimers));
   NewTimerHandler.Offset:=@SysTimerIRQ;
   NewTimerHandler.Segment:=Get_CS;
   Get_PM_Interrupt(TimerIRQ,OldTimer);
   Set_PM_Interrupt(TimerIRQ,NewTimerHandler);
  End;
 ISS_TimersData[TNumber].TSpeed:=NewTSpeed;
 ISS_TimersData[TNumber].TCount:=0;
 ISS_TimersData[TNumber].TProc:=NewTProc;
 ISS_TimersData[TNumber].TActive:=True;
 SetTimerSpeed(GetTimerSpeed);
 ISS_StartTimer:=True;
End;

Function ISS_StopTimer(Var TimerProc : Pointer) : Boolean;
Var TNumber    : Word;
    Counter    : Word;
    LastTimer  : Boolean;
Begin
 Disable;
 TNumber:=0;
 For Counter:=1 To ISS_MaxTimers Do Begin
   With ISS_TimersData[Counter] Do Begin
     If TActive And (TProc=TimerProc) Then TNumber:=Counter;
    End;
  End;
 If TNumber=0 Then Begin
   ISS_TimerError:=ISS_TENotFound;
   ISS_StopTimer:=False;
   Enable;
  End Else Begin
   ISS_TimersData[TNumber].TActive:=False;
   LastTimer:=True;
   For Counter:=1 To ISS_MaxTimers Do Begin
     If ISS_TimersData[Counter].TActive=True Then LastTimer:=False;
    End;
   If LastTimer Then Begin
     TimerSpeed:=0;
     SetTimerSpeed($10000);
     Set_PM_Interrupt(TimerIRQ,OldTimer);
     Unlock_Data(DosMemSelector,SizeOf(DosMemSelector));
     Unlock_Data(ISS_TimersData,SizeOf(ISS_TimersData));
     UnLock_Code(@SysTimerIRQ,DWord(@SysTimerIRQ_Dummy)-DWord(@SysTimerIRQ));
     UnLock_Code(@UpdateUserTimers,DWord(@UpdateUserTimers_Dummy)-DWord(@UpdateUserTimers));
    End;
   ISS_StopTimer:=True;
   Enable;
  End;
End;

Function ISS_GetTimerNumber(TimerProc : Pointer) : DWord;
Var Counter : DWord;
Begin
 For Counter:=1 To ISS_MaxTimers Do Begin
   With ISS_TimersData[Counter] Do Begin
     If TActive And (TProc=TimerProc) Then Begin
       ISS_GetTimerNumber:=Counter;
       Exit;
      End;
    End;
  End;
End;

Begin
 FillChar(ISS_TimersData,SizeOf(ISS_TimersData),#0);
 NewIRQActive:=False;
 TimerSpeed:=0;
End.
{ � ISS_TIM.PAS - (C) 1998-2001 Charlie/Inquisition � }

{ � Changelog : � }
{ � 1.1.1 - Some code cleanup for less compiler hacking...                � }
{ �       - Webpage and email addresses fixed in the header comment.      � }
{ �         [01.march.2001]                                               � }
{ � 1.1.0 - Major update, a new IRQ routine which contains less compiler  � }
{ �         hacking. Based on the docs of FPC 1.0.2. Not tested with      � }
{ �         versions below 1.0.0. GNU AS no longer required to compile.   � }
{ �         [03.december.2000]                                            � }
{ � 1.0.2 - Header comment fixed.                                         � }
{ �         [18.apr.2000]                                                 � }
{ � 1.0.1 - Removed a limitation which made smartlinking impossible.      � }
{ �         (Reported by Surgi/Terror Opera)                              � }
{ �         [13.apr.2000]                                                 � }
{ � 1.0.0 - First Public Version                                          � }
{ �         [08.jan.2000]                                                 � }
