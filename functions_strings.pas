unit functions_strings;

interface
   uses Values;

Procedure Register(FT:PFunTrie);


Function F_Trim(DoReturn:Boolean; Arg:Array of PValue):PValue;
Function F_TrimLeft(DoReturn:Boolean; Arg:Array of PValue):PValue;
Function F_TrimRight(DoReturn:Boolean; Arg:Array of PValue):PValue;
Function F_UpperCase(DoReturn:Boolean; Arg:Array of PValue):PValue;
Function F_LowerCase(DoReturn:Boolean; Arg:Array of PValue):PValue;
Function F_StrLen(DoReturn:Boolean; Arg:Array of PValue):PValue;
Function F_StrPos(DoReturn:Boolean; Arg:Array of PValue):PValue;
Function F_SubStr(DoReturn:Boolean; Arg:Array of PValue):PValue;
Function F_DelStr(DoReturn:Boolean; Arg:Array of PValue):PValue;

Function F_Chr(DoReturn:Boolean; Arg:Array of PValue):PValue;
Function F_Ord(DoReturn:Boolean; Arg:Array of PValue):PValue;


implementation
   uses SysUtils, EmptyFunc;


Procedure Register(FT:PFunTrie);
   begin
   FT^.SetVal('chr',@F_chr);
   FT^.SetVal('ord',@F_ord);
   FT^.SetVal('trim',@F_Trim);
   FT^.SetVal('trimle',@F_TrimLeft);
   FT^.SetVal('trimri',@F_TrimRight);
   FT^.SetVal('uppercase',@F_UpperCase);
   FT^.SetVal('lowercase',@F_LowerCase);
   FT^.SetVal('strlen',@F_StrLen);
   FT^.SetVal('strpos',@F_StrPos);
   FT^.SetVal('substr',@F_SubStr);
   FT^.SetVal('delstr',@F_DelStr);
   end;


Function F_Trim(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; S:AnsiString;
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)=0) then Exit(NewVal(VT_STR,''));
   For C:=High(Arg) downto 1 do
      If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   If (Arg[0]^.Typ = VT_STR)
      then S:=Trim(PStr(Arg[0]^.Ptr)^)
      else begin
      V:=ValToStr(Arg[0]);
      S:=Trim(PStr(V^.Ptr)^);
      FreeVal(V)
      end;
   If (Arg[0]^.Lev >= CurLev) then FreeVal(Arg[0]);
   Exit(NewVal(VT_STR,S))
   end;

Function F_TrimLeft(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; S:AnsiString;
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)=0) then Exit(NewVal(VT_STR,''));
   For C:=High(Arg) downto 1 do
      If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   If (Arg[0]^.Typ = VT_STR)
      then S:=TrimLeft(PStr(Arg[0]^.Ptr)^)
      else begin
      V:=ValToStr(Arg[0]);
      S:=TrimLeft(PStr(V^.Ptr)^);
      FreeVal(V)
      end;
   If (Arg[0]^.Lev >= CurLev) then FreeVal(Arg[0]);
   Exit(NewVal(VT_STR,S))
   end;

Function F_TrimRight(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; S:AnsiString;
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)=0) then Exit(NewVal(VT_STR,''));
   For C:=High(Arg) downto 1 do
      If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   If (Arg[0]^.Typ = VT_STR)
      then S:=TrimRight(PStr(Arg[0]^.Ptr)^)
      else begin
      V:=ValToStr(Arg[0]);
      S:=TrimRight(PStr(V^.Ptr)^);
      FreeVal(V)
      end;
   If (Arg[0]^.Lev >= CurLev) then FreeVal(Arg[0]);
   Exit(NewVal(VT_STR,S))
   end;

Function F_UpperCase(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; S:AnsiString;
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)=0) then Exit(NewVal(VT_STR,''));
   For C:=High(Arg) downto 1 do
      If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   If (Arg[0]^.Typ = VT_STR)
      then S:=UpperCase(PStr(Arg[0]^.Ptr)^)
      else begin
      V:=ValToStr(Arg[0]);
      S:=UpperCase(PStr(V^.Ptr)^);
      FreeVal(V)
      end;
   If (Arg[0]^.Lev >= CurLev) then FreeVal(Arg[0]);
   Exit(NewVal(VT_STR,S))
   end;

Function F_LowerCase(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; S:AnsiString;
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)=0) then Exit(NewVal(VT_STR,''));
   For C:=High(Arg) downto 1 do
      If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   If (Arg[0]^.Typ = VT_STR)
      then S:=LowerCase(PStr(Arg[0]^.Ptr)^)
      else begin
      V:=ValToStr(Arg[0]);
      S:=LowerCase(PStr(V^.Ptr)^);
      FreeVal(V)
      end;
   If (Arg[0]^.Lev >= CurLev) then FreeVal(Arg[0]);
   Exit(NewVal(VT_STR,S))
   end;

Function F_StrLen(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; L:QInt;
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)=0) then Exit(NewVal(VT_INT,0));
   If (Length(Arg)>1) then
      For C:=High(Arg) downto 1 do
          If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   If (Arg[0]^.Typ<>VT_STR) then begin
      V:=ValToStr(Arg[0]); If (Arg[0]^.Lev >= CurLev) then FreeVal(Arg[0]);
      Arg[0]:=V end;
   L:=Length(PStr(Arg[0]^.Ptr)^);
   If (Arg[0]^.Lev >= CurLev) then FreeVal(Arg[0]);
   Exit(NewVal(VT_INT,L))
   end;

Function F_StrPos(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; P:QInt;
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)<2) then Exit(NewVal(VT_INT,0));
   If (Length(Arg)>2) then
      For C:=High(Arg) downto 1 do
          If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   For C:=1 downto 0 do 
      If (Arg[C]^.Typ<>VT_STR) then begin
         V:=ValToStr(Arg[C]); If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
         Arg[C]:=V end;
   P:=Pos(PStr(Arg[0]^.Ptr)^,PStr(Arg[1]^.Ptr)^);
   For C:=1 downto 0 do If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   Exit(NewVal(VT_INT,P))
   end;

Function F_SubStr(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; I:Array[1..2] of QInt; R:TStr;
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)=0) then Exit(NewVal(VT_STR,''));
   If (Length(Arg)>3) then
      For C:=High(Arg) downto 3 do
          If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   For C:=2 downto 1 do
       If (Length(Arg)>C) then
          If (Arg[C]^.Typ >= VT_INT) and (Arg[C]^.Typ<= VT_BIN)
             then i[C]:=PQInt(Arg[C]^.Ptr)^
             else begin
             V:=ValToInt(Arg[C]); i[C]:=PQInt(V^.Ptr)^; FreeVal(V)
             end else
             If (C=2) then i[C]:=High(Integer) else i[C]:=1;
   If (Arg[0]^.Typ = VT_STR)
      then R:=Copy(PStr(Arg[0]^.Ptr)^,i[1],i[2]) 
      else begin
      V:=ValToStr(Arg[0]); R:=Copy(PStr(V^.Ptr)^,i[1],i[2]); 
      FreeVal(V) end;
   For C:=2 downto 0 do
       If (Length(Arg)>C) and (Arg[C]^.Lev >= CurLev)
          then FreeVal(Arg[C]);
   Exit(NewVal(VT_STR,R))
   end;

Function F_DelStr(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; I:Array[1..2] of QInt; 
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)=0) then Exit(NewVal(VT_STR,''));
   If (Length(Arg)>3) then
      For C:=High(Arg) downto 3 do
          If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   For C:=2 downto 1 do
       If (Length(Arg)>C) then
          If (Arg[C]^.Typ >= VT_INT) and (Arg[C]^.Typ<= VT_BIN)
             then i[C]:=PQInt(Arg[C]^.Ptr)^
             else begin
             V:=ValToInt(Arg[C]); i[C]:=PQInt(V^.Ptr)^; FreeVal(V)
             end else
             If (C=2) then i[C]:=High(SizeInt) else i[C]:=1;
   If (Arg[0]^.Typ = VT_STR)
      then V:=CopyVal(Arg[0])
      else V:=ValToStr(Arg[0]);
   Delete(PStr(V^.Ptr)^,i[1],i[2]); 
   For C:=2 downto 0 do
       If (Length(Arg)>C) and (Arg[C]^.Lev >= CurLev)
          then FreeVal(Arg[C]);
   Exit(V)
   end;

Function F_Ord(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; S:AnsiString;
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)=0) then Exit(NilVal());
   For C:=High(Arg) downto 1 do
      If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   If (Arg[0]^.Typ = VT_STR) then begin
      S:=PStr(Arg[0]^.Ptr)^;
      If (Length(S) = 0) then V:=NilVal()
                         else V:=NewVal(VT_INT, Ord(S[1]));
      end;
   If (Arg[0]^.Lev >= CurLev) then FreeVal(Arg[0]);
   Exit(V)
   end;

Function F_Chr(DoReturn:Boolean; Arg:Array of PValue):PValue;
   Var C:LongWord; V:PValue; I:QInt; F:TFloat;
   begin
   If (Not DoReturn) then Exit(F_(False, Arg));
   If (Length(Arg)=0) then Exit(NilVal());
   For C:=High(Arg) downto 1 do
      If (Arg[C]^.Lev >= CurLev) then FreeVal(Arg[C]);
   If (Arg[0]^.Typ >= VT_INT) and (Arg[0]^.Typ <= VT_BIN) then begin
      I:=PQInt(Arg[0]^.Ptr)^;
      V:=NewVal(VT_STR, Chr(I));
      end else
   If (Arg[0]^.Typ = VT_FLO) then begin
      F:=PFloat(Arg[0]^.Ptr)^;
      V:=NewVal(VT_STR, Chr(Trunc(F)));
      end else V:=NilVal();
   If (Arg[0]^.Lev >= CurLev) then FreeVal(Arg[0]);
   Exit(V)
   end;

end.