unit parser;

{$INCLUDE defines.inc} {$LONGSTRINGS ON} {$INLINE ON}

interface
   uses Stack, Trie, TokExpr, Values;

Type TLineInfo = LongInt; //This will probably become a record when functions get implemented // LOL NOPE
     TIf = Array[0..2] of TLineInfo;
     TLoop = Array[0..2] of TLineInfo;
     
     PLIS = ^TLIS;
     TLIS = specialize GenericStack<TLineInfo>;
     
     PNumTrie = ^TNumTrie; 
     TNumTrie = specialize GenericTrie<LongWord>;
     
     TFileInfo = record
        Name : AnsiString;
        Cons : Array[0..1] of PValue
        end;

Var IfArr : Array of TIf;
    RepArr, WhiArr : Array of TLoop;
    IfSta, RepSta, WhiSta : PLIS;
    
    Func : PFunTrie;
    Cons : PDict;
    
    UsrFun : PNumTrie;
    Pr : Array of TProc;
    Proc, ExLn : LongWord;
    
    mulico:LongWord; {$IFDEF CGI} codemode:LongWord; {$ENDIF}
    FileIncludes : Array of TFileInfo;

Procedure Fatal(Ln:LongWord;Msg:AnsiString);
Function MakeExpr(Var Tk:Array of AnsiString;Ln,T:LongInt):PExpr;
Function ProcessLine(L:AnsiString;N,E:LongWord):Array_PExpr;
Procedure ParseFile(Var I:System.Text);
Procedure ReadFile(Var I:System.Text);


implementation
   uses Math, SysUtils, EmptyFunc, CoreFunc, Globals
        {$IFDEF CGI}, Functions_CGI, Functions_DateTime {$ENDIF}
        ;

Const PREFIX_VAL = '$';
      PREFIX_REF = '&';

Function GetFunc(Name:AnsiString):PFunc; Inline;
   Var R:PFunc;
   begin
   Try R:=Func^.GetVal(Name);
       Exit(R)
   Except
       Exit(Nil)
   end end;

Procedure Fatal(Ln:LongWord;Msg:AnsiString);
   {$IFDEF CGI} Var DTstr:AnsiString; {$ENDIF}
   begin
   Writeln(StdErr, YukName,'(',Ln,'): Fatal: ',Msg);
   {$IFDEF CGI}
   Writeln('Content-Type: text/html; charset=UTF-8');
   Writeln(StdOut);
   Writeln(StdOut, '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">');
   Writeln(StdOut, '<html lang="en">');
   Writeln(StdOut, '<head>');
   Writeln(StdOut, '<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">');
   Writeln(StdOut, '<title>Error</title>');
   Writeln(StdOut, '</head>');
   Writeln(StdOut, '<body style="background: white; color: black">');
   Writeln(StdOut, '<h3>awful-cgi: fatal error</h3><hr>');
   Writeln(StdOut, '<p><strong>File:</strong> ',EncodeHTML(YukPath),'</p>');
   Writeln(StdOut, '<p><strong>Line:</strong> ',Ln,'</p>');
   Writeln(StdOut, '<p><i>',EncodeHTML(Msg),'</i></p>');
   DateTimeToString(DTstr, dtf_def, Now());
   Writeln(StdOut, '<p><small>Generated by awful-cgi, r.',VREVISION,', on ',DTstr,'.</small></p>');
   Writeln(StdOut, '</body>');
   Writeln(StdOut, '</html>');
   Halt(0)
   {$ELSE}
   Halt(255)
   {$ENDIF}
   end;

Procedure Error(Ln:LongWord;Msg:AnsiString); Inline;
   begin Writeln(StdErr,YukName,'(',Ln,'): Error: ',Msg) end;

Function MakeExpr(Var Tk:Array of AnsiString;Ln,T:LongInt):PExpr;
   
   Function ConstPrefix(C:Char):Boolean; Inline;
      begin Exit(Pos(C,'sflihob=')<>0) end;
   
   Function MakeToken(Var Index:LongInt):PToken;
      Var Tok,otk:PToken; atk:PArrTk; TkIn, Nest:LongInt;
          sex:PExpr; V:PValue; PS:PStr; CName:TStr; 
      begin
      // Check string prefix and generate token
      If (Tk[Index][1]=PREFIX_VAL) then begin
         New(Tok); New(PS); Tok^.Typ:=TK_VARI; Tok^.Ptr:=PS; 
         PS^:=Copy(Tk[Index],2,Length(Tk[Index]))
         end else
      If (Tk[Index][1]=PREFIX_REF) then begin
         New(Tok); New(PS); Tok^.Typ:=TK_REFE; Tok^.Ptr:=PS; 
         PS^:=Copy(Tk[Index],2,Length(Tk[Index]))
         end else
      If (Tk[Index][1]='=') then begin
         CName:=Copy(Tk[Index],2,Length(Tk[Index]));
         Try    V:=Cons^.GetVal(CName);
         Except Fatal(Ln,'Unknown constant "'+CName+'".') end;
         New(Tok); Tok^.Typ:=TK_CONS; Tok^.Ptr:=V
         end else
      If (Tk[Index][1]='s') then begin
         V:=NewVal(VT_STR,Copy(Tk[Index],3,Length(Tk[Index])-3));
         New(Tok); Tok^.Typ:=TK_LITE; Tok^.Ptr:=V; V^.Lev := 0
         end else
      If (Tk[Index][1]='i') then begin
         V:=NewVal(VT_INT,Values.StrToInt(Copy(Tk[Index],2,Length(Tk[Index]))));
         New(Tok); Tok^.Typ:=TK_LITE; Tok^.Ptr:=V; V^.Lev := 0
         end else
      If (Tk[Index][1]='h') then begin
         V:=NewVal(VT_HEX,Values.StrToHex(Copy(Tk[Index],2,Length(Tk[Index]))));
         New(Tok); Tok^.Typ:=TK_LITE; Tok^.Ptr:=V; V^.Lev := 0
         end else
      If (Tk[Index][1]='o') then begin
         V:=NewVal(VT_OCT,Values.StrToOct(Copy(Tk[Index],2,Length(Tk[Index]))));
         New(Tok); Tok^.Typ:=TK_LITE; Tok^.Ptr:=V; V^.Lev := 0
         end else
      If (Tk[Index][1]='b') then begin
         V:=NewVal(VT_BIN,Values.StrToBin(Copy(Tk[Index],2,Length(Tk[Index]))));
         New(Tok); Tok^.Typ:=TK_LITE; Tok^.Ptr:=V; V^.Lev := 0
         end else
      If (Tk[Index][1]='l') then begin
         V:=NewVal(VT_BOO,SysUtils.StrToBoolDef(Copy(Tk[Index],2,Length(Tk[Index])),False));
         New(Tok); Tok^.Typ:=TK_LITE; Tok^.Ptr:=V; V^.Lev := 0
         end else
      If (Tk[Index][1]='f') then begin
         V:=NewVal(VT_FLO,Values.StrToReal(Copy(Tk[Index],2,Length(Tk[Index]))));
         New(Tok); Tok^.Typ:=TK_LITE; Tok^.Ptr:=V; V^.Lev := 0
         end else
         Tok:=NIL;
      // Check if next token is an array index
      If (Index < High(Tk)) and (Tk[Index+1][1] = '[') then begin
         If (Tok = NIL) then
            Fatal(Ln,'Index token ("[") found, but previous token is neither a variable name nor an expression.');
         otk:=Tok; Index += 1; TkIn := Index + 1; // E^.Tok[High(E^.Tok)];
         If (otk^.Typ = TK_VARI) or (otk^.Typ = TK_REFE) then begin
            Tok:=MakeToken(TkIn);
            If (Tok=NIL) then begin
               sex:=MakeExpr(Tk, Ln, Index + 1);
               New(Tok); Tok^.Typ:=TK_EXPR; Tok^.Ptr:=sex
               end;
            CName:=PStr(otk^.Ptr)^; Dispose(PStr(otk^.Ptr)); New(atk);
            New(PS); atk^.Ptr:=PS; PS^:=CName;
            If (otk^.Typ = TK_REFE) then otk^.Typ := TK_AREF
                                    else otk^.Typ := TK_AVAL;
            SetLength(atk^.Ind, 1); atk^.Ind[0] := Tok;
            otk^.Ptr := atk
            end else 
            Fatal(Ln,'Index token ("[") found, but previous token is neither a variable name nor an expression.');
         Nest:=0;
         While (Index <= High(Tk)) do 
            //If (Length(Tk[Index])=0) then Index +=1 else
            If (Tk[Index][1]='[') then begin Nest+=1; Index+=1 end else
            If (Tk[Index][1]=']') then begin
               Nest-=1; If (Nest=0) then Break else Index+=1
               end else Index+=1;
         If (Nest>0) then Error(Ln,'Un-closed index expression. ("[" without a matching "]".)');
         Tok := otk // Return value
         end;
      Exit(Tok)
      end;
   
   Function NewToken(Typ:TValueType;Val:Int64):PToken;
      Var Tok:PToken; 
      begin
      New(Tok); Tok^.Typ := TK_LITE; Tok^.Ptr := NewVal(Typ,Val);
      Exit(Tok)
      end;
   
   Var E:PExpr; FPtr:PFunc; sex:PExpr; A,Etk,LeTk:LongWord;
       Tok,otk:PToken; V:PValue; {PS:PStr;} atk : PArrTk;
       Nest:LongWord; CName:TStr; Tmp:LongInt;
   
   Procedure AddToken(Tok:PToken);
      begin
      If (Etk = Length(E^.Tok))
         then SetLength(E^.Tok, Etk + 8);
      
      E^.Tok[Etk] := Tok;
      Etk += 1
      end;
   
   Procedure Construct_Include(Req:Boolean);
      Var FileName,Construct:AnsiString; Constant:PValue; F:System.Text;
          OldName, OldPath : AnsiString; FiIn:LongWord;
          OldNameCons, OldPathCons : PValue;
      begin
      If (Req) then Construct := '!require' else Construct := '!include';
      FileName := Copy(Tk[T], 2, Length(Tk[T]));
      If (Tk[T][1]='s') then begin Delete(FileName,Length(FileName),1); Delete(FileName,1,1) end else
      If (Tk[T][1]='i') then FileName:=IntToStr(Values.StrToInt(FileName)) else
      If (Tk[T][1]='h') then FileName:=HexToStr(Values.StrToHex(FileName)) else
      If (Tk[T][1]='o') then FileName:=OctToStr(Values.StrToOct(FileName)) else
      If (Tk[T][1]='b') then FileName:=BinToStr(Values.StrToBin(FileName)) else
      If (Tk[T][1]='f') then FileName:=FloatToStr(Values.StrToReal(FileName)) else
      If (Tk[T][1]='l') then FileName:=BoolToStr(StrToBoolDef(FileName,False)) else
      If (Tk[T][1]='=') then begin
         Try    Constant := Cons^.GetVal(FileName);
         Except Fatal(Ln,'Unknown constant "'+FileName+'"') end;
         FileName := ValAsStr(Constant)
         end else
         Fatal(Ln,'Arguments for '+Construct+' must be either value literals or constants.');
      
      Assign(F, FileName); {$I-} Reset(F); {$I+}
      If (IOResult()<>0) then begin
         If (Req) then Fatal(Ln,'Unable to include file "'+FileName+'".')
                  else Error(Ln,'Unable to include file "'+FileName+'".');
         Exit() end;
      
      FiIn := Length(FileIncludes);
      SetLength(FileIncludes, FiIn + 1);
      FileIncludes[FiIn].Name := FileName;
      
      OldName := YukName; OldPath := YukPath;
      YukPath := ExpandFileName(FileName);
      YukName := ExtractFileName(YukPath);
      
      OldNameCons := Cons^.GetVal('FILE-NAME');
      Constant := NewVal(VT_STR, YukName); Constant^.Lev := 0; Cons^.SetVal('FILE-NAME', Constant);
      FileIncludes[FiIn].Cons[0] := Constant;
      
      OldPathCons := Cons^.GetVal('FILE-PATH');
      Constant := NewVal(VT_STR, YukPath); Constant^.Lev := 0; Cons^.SetVal('FILE-PATH', Constant);
      FileIncludes[FiIn].Cons[1] := Constant;
      
      ParseFile(F);
      Close(F);
      
      Cons^.SetVal('FILE-NAME', OldNameCons); YukName := OldName;
      Cons^.SetVal('FILE-PATH', OldPathCons); YukPath := OldPath
      end;
   
   begin
   New(E); LeTk:=Length(Tk);
   If (Tk[T][1]=':') then begin
      FPtr:=GetFunc(Copy(Tk[T],2,Length(Tk[T])));
      If (FPtr = NIL) then begin
         Try    A:=UsrFun^.GetVal(Copy(Tk[T],2,Length(Tk[T])));
         Except Fatal(Ln,'Unknown function: "'+Tk[T]+'".') end;
         
         SetLength(E^.Tok, 1);
         E^.Tok[0] := NewToken(VT_INT, A);
         FPtr:=@F_AutoCall
         end
      end else
   If (Tk[T][1]='!') then begin
      If (Tk[T]='!if') then begin
         A := Length(IfArr);
         SetLength(IfArr,(A+1));
         IfArr[A][0]:=Ln; // !if line number
         IfArr[A][1]:=-1; // !else expression number
         IfArr[A][2]:=-1; // !fi expression number
         IfSta^.Push(A);  // push !if identifier on stack, so we know which !if to match !else and !fi to
         
         SetLength(E^.Tok, 1);
         E^.Tok[0] := NewToken(VT_INT, A);
         FPtr:=@(F_If)
         end else
      If (Tk[T]='!else') then begin
         If (IfSta^.Empty) then Fatal(Ln,'!else without corresponding !if.');
         A:=IfSta^.Peek();
         If (IfArr[A][1]>=0) then Fatal(Ln,'!if from line '+IntToStr(IfArr[A][0])+' has a second !else.');
         IfArr[A][1]:=ExLn; // set !else expression number
         
         SetLength(E^.Tok, 1);
         E^.Tok[0] := NewToken(VT_INT, A);
         FPtr:=@(F_Else)
         end else
      If (Tk[T]='!fi') then begin
         If (IfSta^.Empty()) then Fatal(Ln,'!fi without corresponding !if.');
         A:=IfSta^.Pop();
         IfArr[A][2]:=ExLn; // set !fi expr num
         If (IfArr[A][1]<0) then IfArr[A][1]:=ExLn; // if !else expr num is not present, set it to !fi expr num
         
         SetLength(E^.Tok, 1);
         E^.Tok[0] := NewToken(VT_INT, A);
         FPtr:=@(F_)
         end else
      If (Tk[T]='!while') then begin
         A:=Length(WhiArr);
         SetLength(WhiArr,(A+1));
         WhiArr[A][0]:=Ln;     // set !while line number
         WhiArr[A][1]:=ExLn-1; // set !while jump point
         WhiArr[A][2]:=-1;     // set !done expr num
         WhiSta^.Push(A);
         
         SetLength(E^.Tok, 1);
         E^.Tok[0] := NewToken(VT_INT, A);
         FPtr:=@(F_While)
         end else
      If (Tk[T]='!done') then begin
         If (WhiSta^.Empty()) then Fatal(Ln,'!done without corresponding !while.');
         A:=WhiSta^.Pop();
         WhiArr[A][2]:=ExLn; // set !done expr num
         
         SetLength(E^.Tok, 1);
         E^.Tok[0] := NewToken(VT_INT, A);
         FPtr:=@(F_Done)
         end else
      If (Tk[T]='!repeat') then begin
         A:=Length(RepArr);
         SetLength(RepArr,(A+1));
         RepArr[A][0]:=Ln;   // set !repeat line number
         RepArr[A][1]:=ExLn; // set !repeat jump point
         RepArr[A][2]:=-1;   // set !until expr num
         RepSta^.Push(A);
         
         SetLength(E^.Tok, 1);
         E^.Tok[0] := NewToken(VT_INT, A);
         FPtr:=@(F_)
         end else
      If (Tk[T]='!until') then begin
         If (RepSta^.Empty()) then Fatal(Ln,'!until without corresponding !repeat.');
         A:=RepSta^.Pop();
         RepArr[A][2]:=ExLn; // set !until expr num
         
         SetLength(E^.Tok, 1);
         E^.Tok[0] := NewToken(VT_INT, A);
         FPtr:=@(F_Until)
         end else
      If (Tk[T]='!const') then begin
         If ((LeTk-T)<>3) then Fatal(Ln,'Wrong number of arguments passed to !const.');
         If (Length(Tk[T+1])=0) or (Tk[T+1][1]<>'=')
            then Fatal(Ln,'!const names must start with a "=" character.');
         CName:=Copy(Tk[T+1],2,Length(Tk[T+1]));
         If (Cons^.IsVal(CName)) 
            then Fatal(Ln,'Redefinition of const "'+CName+'".');
         If (Length(Tk[T+2])=0) or (Not ConstPrefix(Tk[T+2][1]))
            then Fatal(Ln,'Second argument for !const must be either a value literal or another const.');
         If (Tk[T+2][1]='s') then
            V:=NewVal(VT_STR,Copy(Tk[T+2],3,Length(Tk[T+2])-3)) else
         If (Tk[T+2][1]='f') then
            V:=NewVal(VT_FLO,StrToReal(Copy(Tk[T+2],2,Length(Tk[T+2])))) else
         If (Tk[T+2][1]='l') then
            V:=NewVal(VT_BOO,StrToBoolDef(Copy(Tk[T+2],2,Length(Tk[T+2])),False)) else
         If (Tk[T+2][1]='i') then
            V:=NewVal(VT_INT,Values.StrToInt(Copy(Tk[T+2],2,Length(Tk[T+2])))) else
         If (Tk[T+2][1]='h') then
            V:=NewVal(VT_HEX,Values.StrToHex(Copy(Tk[T+2],2,Length(Tk[T+2])))) else
         If (Tk[T+2][1]='o') then
            V:=NewVal(VT_OCT,Values.StrToOct(Copy(Tk[T+2],2,Length(Tk[T+2])))) else
         If (Tk[T+2][1]='b') then
            V:=NewVal(VT_BIN,Values.StrToBin(Copy(Tk[T+2],2,Length(Tk[T+2])))) else
         If (Tk[T+2][1]='=') then
            Try    V:=Cons^.GetVal(Copy(Tk[T+2],2,Length(Tk[T+2])))
            Except Fatal(Ln,'Unknown const "'+Copy(Tk[T+2],2,Length(Tk[T+2]))+'".') end;
         V^.Lev := 0; Cons^.SetVal(CName,V);
         Dispose(E); Exit(NIL)
         end else
      If (Tk[T]='!fun') then begin
         If (Not IfSta^.Empty()) then begin
            A:=IfSta^.Peek(); A:=IfArr[A][0];
            Fatal(A,'Function declaration inside an !if block.')
            end else
         If (Not WhiSta^.Empty()) then begin
            A:=WhiSta^.Peek(); A:=WhiArr[A][0];
            Fatal(A,'Function declaration inside a !while block.')
            end else
         If (Not RepSta^.Empty()) then begin
            A:=RepSta^.Peek(); A:=RepArr[A][0];
            Fatal(A,'Function declaration inside a !repeat block.')
            end else
         If (Proc<>0) then Fatal(Ln,'Nested function declaration.');
         If ((LeTk-T)<2) then Fatal(Ln,'No function name specified.');
         If (Length(Tk[T+1])=0) or (Tk[T+1][1]<>':')
            then Fatal(Ln,'Function names must start with the colon (":") character.');
         CName:=Copy(Tk[T+1],2,Length(Tk[T+1]));
         If (UsrFun^.IsVal(CName))
            then Fatal(Ln,'Duplicate user function identifier ("'+Cname+'").');
         SetLength(Pr,Length(Pr)+1);
         Proc:=High(Pr); ExLn:=0;
         Pr[Proc].Num:=0; SetLength(Pr[Proc].Exp,0);
         SetLength(Pr[Proc].Arg, LeTk - 2); A := 0;
         UsrFun^.SetVal(CName,Proc); T+=2;
         While (T < LeTk) do begin
            If (Length(Tk[T])=0) then begin
               Error(Ln,'Empty token (#'+IntToStr(T)+').'); T+=1; Continue
               end;
            If ((Tk[T][1]<>'$') and (Tk[T][1]<>'&'))  then
               Fatal(Ln,'Function arguments must specify variable names. ("$name" or "&name")');
            //SetLength(Pr[Proc].Arg,Length(Pr[Proc].Arg)+1);
            Pr[Proc].Arg[A]:=Copy(Tk[T],2,Length(Tk[T]));
            A+=1; T+=1 end;
         SetLength(Pr[Proc].Arg, A);
         Dispose(E); Exit(NIL)
         end else
      If (Tk[T]='!nuf') then begin
         If (Proc = 0) then Fatal(Ln,'!nuf without corresponding !fun.');
         If (Not IfSta^.Empty()) then begin
            A:=IfSta^.Peek(); A:=IfArr[A][0];
            Fatal(A,'!if stretches past end of function.')
            end else
         If (Not WhiSta^.Empty()) then begin
            A:=WhiSta^.Peek(); A:=WhiArr[A][0];
            Fatal(A,'!while stretches past end of function.')
            end else
         If (Not RepSta^.Empty()) then begin
            A:=RepSta^.Peek(); A:=RepArr[A][0];
            Fatal(A,'!repeat stretches past end of function.')
            end;
         SetLength(Pr[Proc].Exp, Pr[Proc].Num);
         Proc:=0; ExLn:=Pr[0].Num-1;
         Dispose(E); Exit(NIL)
         end else
      If (Tk[T]='!include') then begin
         T += 1; While (T < LeTk) do begin Construct_Include(False); T += 1 end;
         Dispose(E); Exit(NIL)
         end else
      If (Tk[T]='!require') then begin
         T += 1; While (T < LeTk) do begin Construct_Include(True); T += 1 end;
         Dispose(E); Exit(NIL)
         end else
      {If (Tk[T]='!return') then begin
         If (Proc = 0) then Fatal(Ln,'!return used in main function.');
         FPtr:=@F_Return
         end else}
         Fatal(Ln,'Unknown language construct: "'+Tk[T]+'".')
      end else
      Fatal(Ln,'First token in expression ("'+Tk[T]+'") is neither a function call nor a language construct.');
   E^.Fun:=FPtr; T+=1; Etk := Length(E^.Tok);
   If (LeTk > 0) then SetLength(E^.Tok, LeTk);
   While (T < LeTk) do begin
      If (Length(Tk[T])=0) then Error(Ln,'Empty token (#'+IntToStr(T)+').') else
      If (Tk[T][1]='(') then begin
         sex:=MakeExpr(Tk,Ln,T+1);
         New(Tok); Tok^.Typ:=TK_EXPR; Tok^.Ptr:=sex;
         AddToken(Tok);
         Nest:=0;
         While (T < LeTk) do 
            If (Length(Tk[T])=0) then T+=1 else
            If (Tk[T][1]='(') then begin Nest+=1; T+=1 end else
            If (Tk[T][1]=')') then begin
               Nest-=1; If (Nest=0) then Break else T+=1
               end else T+=1;
         If (Nest>0) then Error(Ln,'Un-closed sub-expression. ("(" without a matching ")".)')
         end else
      If (Tk[T][1]=')') then begin
         SetLength(E^.Tok, Etk); Exit(E)
         end else 
      If (Tk[T][1]='[') then begin
         If (Length(E^.Tok)=0) then
            Fatal(Ln,'Index token ("[") found, but previous token is neither a variable name nor an expression.');
         otk:=E^.Tok[Etk-1]; Tmp:=T+1;
         If (otk^.Typ = TK_AREF) or (otk^.Typ = TK_AVAL) or (otk^.Typ = TK_AFLY) then begin
            Tok:=MakeToken(Tmp);
            If (Tok=NIL) then begin
               sex:=MakeExpr(Tk,Ln,T+1);
               New(Tok); Tok^.Typ:=TK_EXPR; Tok^.Ptr:=sex
               end;
            atk := PArrTk(otk^.Ptr);
            SetLength(atk^.Ind, Length(atk^.Ind) + 1);
            atk^.Ind[High(atk^.Ind)] := Tok
            end else
         If (otk^.Typ = TK_EXPR) then begin
            Tok:=MakeToken(Tmp);
            If (Tok=NIL) then begin
               sex:=MakeExpr(Tk,Ln,T+1);
               New(Tok); Tok^.Typ:=TK_EXPR; Tok^.Ptr:=sex
               end;
            New(atk); atk^.Ptr := otk^.Ptr;
            SetLength(atk^.Ind, 1); atk^.Ind[0] := Tok;
            otk^.Ptr := atk; otk^.Typ := TK_AFLY
            end else
            Fatal(Ln,'Index token ("[") found, but previous token is neither a variable name nor an expression.');
         Nest:=0;
         While (T < LeTk) do 
            If (Length(Tk[T])=0) then T+=1 else
            If (Tk[T][1]='[') then begin Nest+=1; T+=1 end else
            If (Tk[T][1]=']') then begin
               Nest-=1; If (Nest=0) then Break else T+=1
               end else T+=1;
         If (Nest>0) then Error(Ln,'Un-closed index expression. ("[" without a matching "]".)')
         end else 
      If (Tk[T][1]=']') then begin
         SetLength(E^.Tok, Etk); Exit(E)
         end else
      If (Tk[T][1]=':') then begin
         sex:=MakeExpr(Tk,Ln,T);
         New(Tok); Tok^.Typ:=TK_EXPR; Tok^.Ptr:=sex;
         AddToken(Tok);
         SetLength(E^.Tok, Etk); Exit(E)
         end else
      If (Tk[T][1]='!') then begin
         Fatal(Ln,'Language construct used as a sub-expression. ("'+Tk[T]+'").')
         end else begin
         Tok:=MakeToken(T);
         If (Tok<>NIL) then begin
            AddToken(Tok)
            end else
            Error(Ln,'Invalid token ("'+Tk[T]+'").')
         end;
      T+=1 end;
   SetLength(E^.Tok, Etk); Exit(E)
   end;

Procedure AddExpr(Ex:PExpr;Var E:LongWord);
   begin
   If (Pr[Proc].Num = Length(Pr[Proc].Exp)) 
      then SetLength(Pr[Proc].Exp, Length(Pr[Proc].Exp)+32);
   
   Pr[Proc].Exp[E] := Ex;
   Pr[Proc].Num += 1;
   ExLn += 1;
   E += 1
   end;

Function ProcessLine(L:AnsiString;N,E:LongWord):Array_PExpr;
   Var Tk:Array of AnsiString; P,S,Len:LongWord;
       Str:LongInt; Del:Char; PipeChar:AnsiString;
       Ex:PExpr; HiTk, Rs :LongWord;
   
   Function BreakToken(Ch:Char):Boolean; Inline;
      begin Exit(Pos(Ch,' (|)[#]~')<>0) end;
   
   begin
   {$IFDEF CGI}
   If (codemode = 0) and (Length(L) = 0) then begin
      SetLength(Tk,1); Tk[0]:=':writeln';
      AddExpr(MakeExpr(Tk, N, 0), E);
      Exit(NIL)
      end;
   {$ENDIF}
   SetLength(Tk,0); S := 1; Len:=Length(L); P:=1; Str:=0; Del:=#255; PipeChar:='';
   While (S <= Len) do begin
      //Writeln(N:8,#32,Len:8,#32,S:8,#32,P:8,' "',L[P],'"');
      If (mulico > 0) then begin
         If (P>Len) then S := Len+1 else
         If (L[P]='#') then
            If (Len>P) and (L[P+1]='~') then mulico+=1 else
            If (P>1) and (L[P-1]='~') then begin
               If (mulico > 1) then mulico-=1 else begin
                  S:=P+1; {P-=1;} mulico:=0
               end end
         end else
      {$IFDEF CGI}
      If (codemode = 0) then begin
         If (P>Len) then begin
            If (Length(Tk) > 0) and (Tk[High(Tk)][1] <> '~') then begin
               SetLength(Tk, Length(Tk)+3); Tk[High(Tk)-2] := '~'
               end else SetLength(Tk, Length(Tk)+2);
            Tk[High(Tk)-1] := ':writeln';
            Tk[High(Tk)] := 's"' + L[S..Len] +'"';
            S := Len + 1; P-=1
            end else
         If (L[P] = '?') then begin
            If ((P>1) and (L[P-1] = '<')) and ((P <= Len-3) and (L[P+1..P+3] = 'yuk')) then begin
               If (P > S+1) then begin
                  If (Length(Tk) > 0) and (Tk[High(Tk)][1]<>'~') then begin
                     SetLength(Tk, Length(Tk)+4); Tk[High(Tk)-2] := '~'
                     end else SetLength(Tk, Length(Tk)+3);
                  Tk[High(Tk)-2] := ':write';
                  Tk[High(Tk)-1] := 's"' + L[S..P-2] +'"';
                  Tk[High(Tk)] := '~'
                  end else
                  If (Length(Tk)>0) and (Tk[High(Tk)][1] <> '~') then begin
                     SetLength(Tk, Length(Tk)+1); Tk[High(Tk)] := '~'
                     end;
               //Writeln(StdErr,ExtractFileName(YukPath),'(',N,'): Entering codemode');
               codemode := 1; S:=P+5; P+=3
               end else
            If (P<Len) and (L[P+1] = '>') and (codemode = 0) then begin
               Fatal(N, 'Unexpected codemode close tag ("?>").') end;
            end else
         If (N = 1) and (P = 1) and (L[1]='#') then begin
            If (Len>1) and (L[2]='!') then S:=Len+1 // #!shebang
            end
         end else
      {$ENDIF}
      If (Str<=0) then begin
         If (P>Len) or (BreakToken(L[P])) then begin
            //Writeln(StdErr,'Breaking line: "',L,'" at "',L[P],'".');
            If (L[P]=' ') then begin
               If (P>S) then begin
                  SetLength(Tk,Length(Tk)+1);
                  Tk[High(Tk)]:=Copy(L,S,P-S)
                  end;
               While (P<Len) and (L[P+1]=#32) do P+=1;
               S := P+1; P+=1
               end else 
            If (L[P]='#') then begin //Comment character! 
               If (P>S) then begin 
                  SetLength(Tk,Length(Tk)+1);
                  Tk[High(Tk)]:=Copy(L,S,P-S)
                  end;
               If (Len>P) and (L[P+1]='~') //begin of multi-line comment
                  then begin S := P+2; P+=2; mulico += 1 end 
                  else S:=Len+1 {normal comment}
               end
            {$IFDEF CGI}
               else
            If (P >= 3) and (L[P-2..P-1] = '?>') then begin
               codemode -= 1; S:=P; P+=1 //Delete(L, 1, 2)
               end
            {$ENDIF}
               else begin // paren
               If (P>S) then begin
                  SetLength(Tk, Length(Tk)+1);
                  Tk[High(Tk)]:=Copy(L,S,P-S)
                  end;
               If (P<=Len) then begin
                  SetLength(Tk,Length(Tk)+1);
                  Tk[High(Tk)]:=L[P];
                  While (P<Len) and (L[P+1]=#32) do P+=1
                  end;
               S:=P+1; P+=1;
               If (Tk[High(Tk)]='|') then begin
                  If (Length(PipeChar)=0) then begin
                     SetLength(Tk, Length(Tk)-1);
                     Error(N, 'Pipe ("|") without matching parentheses or brackets.') 
                     end else begin
                     SetLength(Tk, Length(Tk)+1);
                     If (PipeChar[Length(PipeChar)] = '(') then begin
                        Tk[High(Tk)-1]:=')'; Tk[High(Tk)]:='('
                        end else begin
                        Tk[High(Tk)-1]:=']'; Tk[High(Tk)]:='['
                        end
                     end
                  end else
               If (Tk[High(Tk)]='(') or (Tk[High(Tk)] = '[') then
                  PipeChar += Tk[High(Tk)] else
               If ((Tk[High(Tk)]=')') or (Tk[High(Tk)] = ']')) and
                  (Length(PipeChar)>0) and (PipeChar[Length(PipeChar)]=Tk[High(Tk)]) then
                  Delete(PipeChar, Length(PipeChar), 1)
               end;
            P:=S-1; Str:=0
            end else
         {$IFDEF CGI}
         If (L[P]='?') and (P<Len) and (L[P+1]='>') then begin
            codemode -= 1; S:=P+2; P+=1 //Delete(L, 1, P+1); P:=0;
            end else
         {$ENDIF}
         If (Str=0) and (L[P]='s')
            then Str:=+1 else Str:=-1
         end else
      If (Str=1) then begin
         If (P>Len) then begin
            Error(N,'String prefix found at end of line.');
            SetLength(Tk,Length(Tk)+1);
            Tk[High(Tk)]:='s""';
            S:=Len+1; Str:=0
            end else begin
            Del:=L[P]; Str:=2
         end end else
      If (Str=2) and ((P>Len) or (L[P]=Del)) then begin
         SetLength(Tk,Length(Tk)+1);
         Tk[High(Tk)]:=Copy(L,S,P-S+1);
         If (P<=Len)
            then While (P<Len) and (L[P+1]=#32) do P+=1
            else begin
            Error(N,'String token exceeds line.');
            Tk[High(Tk)]+=Del
            end;
         S:=P+1; {P-=1;} Str:=0
         end;
      P+=1
      end;
   //If (N = 11) then for p:=low(tk) to high(tk) do writeln(tk[p]);
   If (Length(Tk)=0) then Exit(NIL);
   If (Length(Tk)=1) and (Tk[0][1]='~') then Exit(NIL);
   Rs:=0; HiTk := High(Tk); P:=1;
   While (P <= HiTk) do begin
      If (Tk[P][1]='!') then begin //if (n=11) then writeln('makeexpr ',rs,'..',p-1);
         Ex := MakeExpr(Tk[Rs..P-1], N, 0);
         If (Ex<>NIL) then AddExpr(Ex, E);
         Rs := P;
         end else
      If (Tk[P][1]='~') then begin
         If (Tk[Rs][1]<>'~') then begin //if (n=11) then writeln('makeexpr ',rs,'..',p-1);
            Ex:=MakeExpr(Tk[Rs..P-1], N, 0);
            If (Ex<>NIL) then AddExpr(Ex, E);
            end;
         While (P <= HiTk) and (Tk[P][1] = '~') do P += 1; Rs := P;
         If (P > HiTk) or (Tk[P][1] <> '!') then P -= 1
         end;
      P += 1
      end;
   If (Rs <= HiTk) and (Tk[Rs][1]<>'~') then begin
      Ex := MakeExpr(Tk[Rs..HiTk], N, 0); 
      If (Ex<>NIL) then AddExpr(Ex, E);
      end;
   Exit(NIL)
   end;

Procedure ParseFile(Var I:System.Text);
   Var L:AnsiString; N,E,P:LongWord; 
   begin
   N := 0;
   While (Not Eof(I)) do begin
      Readln(I,L); N+=1;
      {$IFNDEF CGI} L:=Trim(L); {$ELSE} If (codemode > 0) then L:=TrimLeft(L); {$ENDIF}
      {$IFNDEF CGI} If (Length(L)>0) then begin {$ENDIF}
         P:=Proc; E:=Pr[P].Num; ExLn:=E; 
         ProcessLine(L, N, E)
         end
      {$IFNDEF CGI} end {$ENDIF}
   end;

Procedure ReadFile(Var I:System.Text);
   
   {$MACRO ON}{$IFDEF CGI}{$DEFINE _ISCGI_:=True}{$ELSE}{$DEFINE _ISCGI_:=False}{$ENDIF}
   
   Function BuildNum():AnsiString; Inline;
      Var D,T:AnsiString;
      begin
      D:={$I %DATE%}; Delete(D, 8, 1);
      T:={$I %TIME%}; Delete(T, 3, 1); Delete(T, 5, 3);
      Exit(D+'/'+T)
      end;
   
   Var A:LongWord; V:PValue; PTV:PValue; 
   begin
   New(UsrFun,Create('!','~'));
   SetLength(Pr,1); Proc:=0; ExLn:=0; mulico:=0; {$IFDEF CGI} codemode:=0; {$ENDIF}
   SetLength(Pr[0].Arg,0); SetLength(Pr[0].Exp,0); Pr[0].Num:=0;
   
   SetLength(IfArr,0);  New(IfSta,Create());
   SetLength(WhiArr,0); New(WhiSta,Create());
   SetLength(RepArr,0); New(RepSta,Create());
   SetLength(FileIncludes, 0);
   
   New(Cons,Create('!','~'));
   SpareVars_Prepare();
   
   V:=NilVal(); V^.Lev := 0; Cons^.SetVal('NIL', V);
   
   {$IFDEF CGI} V:=NewVal(VT_STR, GetEnvironmentVariable('REQUEST_METHOD')); V^.Lev:=0; Cons^.SetVal('REQUEST-METHOD', V); {$ENDIF}
   
   V:=NewVal(VT_STR,YukPath); V^.Lev := 0; Cons^.SetVal('FILE-PATH',V);
   V:=NewVal(VT_STR,YukName); V^.Lev := 0; Cons^.SetVal('FILE-NAME',V);
   
   V:=NewVal(VT_BOO,_ISCGI_);     V^.Lev := 0; Cons^.SetVal('AWFUL-CGI',V);
   V:=NewVal(VT_STR,ParamStr(0)); V^.Lev := 0; Cons^.SetVal('AWFUL-PATH',V);
   V:=NewVal(VT_STR,BuildNum());  V^.Lev := 0; Cons^.SetVal('AWFUL-BUILD',V);
   V:=NewVal(VT_STR,VERSION);     V^.Lev := 0; Cons^.SetVal('AWFUL-VERSION',V);
   V:=NewVal(VT_INT,VREVISION);   V^.Lev := 0; Cons^.SetVal('AWFUL-REVISION',V);
   PTV:=EmptyVal(VT_INT);       PTV^.Lev := 0; Cons^.SetVal('AWFUL-PARSETIME',PTV);
   
   V:=NewVal(VT_FLO,2.71828182845904523536); V^.Lev := 0; Cons^.SetVal('e',  V);
   V:=NewVal(VT_FLO,3.14159265358979323846); V^.Lev := 0; Cons^.SetVal('pi', V);
   
   SetLength(FCal,1); New(FCal[0].Vars,Create('!','~')); FCal[0].Args := NIL; FLev := 0;
   
   ParseFile(I); // loop moved to other file
   
   SetLength(Pr[0].Exp, Pr[0].Num); // truncate array of main function
   If (mulico > 0) then Writeln(StdErr,YukName,': multi-line comment stretches past end of code.');
   
   If (Not IfSta^.Empty()) then begin
      A:=IfSta^.Peek(); A:=IfArr[A][0];
      Fatal(A, '!if stretches past end of code.') end;
   Dispose(IfSta,Destroy());
      
   If (Not WhiSta^.Empty()) then begin
      A:=WhiSta^.Peek(); A:=WhiArr[A][0];
      Fatal(A, '!while stretches past end of code.') end;
   Dispose(WhiSta,Destroy()); 
      
   If (Not RepSta^.Empty()) then begin
      A:=RepSta^.Peek(); A:=RepArr[A][0];
      Fatal(A, '!repeat stretches past end of code.') end;
   Dispose(RepSta,Destroy());
   
   PQInt(PTV^.Ptr)^ := Ceil(TimeStampToMSecs(DateTimeToTimeStamp(Now()))-GLOB_ms)
   end;

end.
