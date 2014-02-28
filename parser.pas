unit parser;

{$INCLUDE defines.inc} {$LONGSTRINGS ON}

interface
   uses Stack, TokExpr, Values;

Type TLineInfo = LongInt; //This will probably become a record when functions get implemented // LOL NOPE
     TIf = Array[0..2] of TLineInfo;
     TLoop = Array[0..2] of TLineInfo;
     
     TConstructType = (CT_IF, CT_WHILE, CT_REPEAT);
     TConstructInfo = record
        Typ : TConstructType;
        Idx : LongWord
        end;
     
     PConstructStack = ^TConstructStack;
     TConstructStack = specialize GenericStack<TConstructInfo>;

Var IfArr : Array of TIf;
    RepArr, WhiArr : Array of TLoop;
    
    Func : PFunTrie;
    Cons : PValTrie;
    
    Pr : Array of TProc;
    Proc, ExLn : LongWord;

Procedure Fatal(Const Ln:LongWord;Const Msg:AnsiString;Const ErrCode:LongInt = 255);
Function MakeExpr(Var Tk:Array of AnsiString;Const Ln:LongInt; T:LongInt):PExpr;
Procedure ProcessLine(L:AnsiString;N:LongWord);
Procedure ParseFile(Var I:System.Text);
Procedure ReadFile(Var I:System.Text);

implementation
   uses Math, SysUtils, EmptyFunc, CoreFunc, Globals
        {$IFDEF CGI}, Functions_CGI, Functions_DateTime {$ENDIF}
        ;

Const PREFIX_VAL = '$';
      PREFIX_REF = '&';
      SKIP_BREAK = True;
      SKIP_CONTINUE = False;
      INCL_INCLUDE = False;
      INCL_REQUIRE = True;

Var cstruStack : PConstructStack;
    mulico:LongWord; {$IFDEF CGI} codemode:LongWord; {$ENDIF}

Procedure Fatal(Const Ln:LongWord;Const Msg:AnsiString;Const ErrCode:LongInt = 255);
   {$IFDEF CGI} Var DTstr:AnsiString; {$ENDIF}
   begin
   If (Ln <> 0) then Writeln(StdErr, YukName,'(',Ln,'): Fatal: ',Msg)
                else Writeln(StdErr, YukName,': Fatal: ',Msg);
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
   If (Ln <> 0) then Writeln(StdOut, '<p><strong>Line:</strong> ',Ln,'</p>');
   Writeln(StdOut, '<p><i>',EncodeHTML(Msg),'</i></p>');
   DateTimeToString(DTstr, dtf_def, Now());
   Writeln(StdOut, '<p><small>Generated by awful-cgi, r.',VREVISION,', on ',DTstr,'.</small></p>');
   Writeln(StdOut, '</body>');
   Writeln(StdOut, '</html>');
   Halt(0)
   {$ELSE}
   Halt(ErrCode)
   {$ENDIF}
   end;

Procedure Error(Const Ln:LongWord;Const Msg:AnsiString); Inline;
   begin Writeln(StdErr,YukName,'(',Ln,'): Error: ',Msg) end;

Procedure DupeFuncFatal(Const Ln:LongWord; Const Name:AnsiString);
   Var Fn : TFunc;
   begin
   Fn := Func^.GetVal(Name);
   If (Fn.Usr) then begin
      If (Pr[Fn.Ptr].Fil = 0)
         then Fatal(Ln,'duplicate function name "'+Name+'", originally declared in '+ScriptName+' on line '+IntToStr(Pr[Fn.Ptr].Lin)+'.') 
         else Fatal(Ln,'duplicate function name "'+Name+'", originally declared in '+FileIncludes[Pr[Fn.Ptr].Fil].Name+' on line '+IntToStr(Pr[Fn.Ptr].Lin)+'.')
      end else Fatal(Ln,'function name "'+Name+'" collides with built-in function.')
   end;

Procedure cstruFatal(Const Ln:LongWord);
   Var cstru:TConstructInfo; Cnt:LongWord; PastWhat:ShortString;
   begin
   If (Ln <> 0) then PastWhat := 'function.'
                else PastWhat := 'end of code.';
   Cnt := cstruStack^.Count;
   While (Not cstruStack^.Empty) do begin
      cstru := cstruStack^.Pop();
      Case cstru.Typ of
             CT_IF: Writeln(StdErr,YukName,'(', IfArr[cstru.Idx][0],'): Error: !if block stretches past ',PastWhat);
          CT_WHILE: Writeln(StdErr,YukName,'(',WhiArr[cstru.Idx][0],'): Error: !while block stretches past ',PastWhat);
         CT_REPEAT: Writeln(StdErr,YukName,'(',RepArr[cstru.Idx][0],'): Error: !repeat block stretches past ',PastWhat)
      end end;
   Fatal(Ln, IntToStr(Cnt)+' unterminated code blocks.')
   end;

Function mkcstru(Const T:TConstructType; Const I:LongWord):TConstructInfo;
   begin Result.Typ := T; Result.Idx := I end;

Procedure AddExpr(Const Ex:PExpr);
   begin
   If (Pr[Proc].Num = Length(Pr[Proc].Exp)) 
      then SetLength(Pr[Proc].Exp, Length(Pr[Proc].Exp)+32);
   
   Pr[Proc].Exp[Pr[Proc].Num] := Ex;
   Pr[Proc].Num += 1
   end;

Function MakeExpr(Var Tk:Array of AnsiString;Const Ln:LongInt; T:LongInt):PExpr;
   
   Function ConstPrefix(C:Char):Boolean; Inline;
      begin Exit(Pos(C,'suflihob=')<>0) end;
   
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
      If (Tk[Index][1]='u') then begin
         V:=NewVal(VT_UTF,Copy(Tk[Index],3,Length(Tk[Index])-3));
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
   
   Function NewToken(Const Typ:TValueType;Const Val:Int64):PToken;
      Var Tok:PToken; 
      begin
      New(Tok); Tok^.Typ := TK_LITE; Tok^.Ptr := NewVal(Typ,Val); 
      PValue(Tok^.Ptr)^.Lev := 0;
      Exit(Tok)
      end;
   
   Var E:PExpr; FPtr:TFunc; sex:PExpr; A,Etk,LeTk:LongWord;
       Tok,otk:PToken; V:PValue; {PS:PStr;} atk : PArrTk;
       Nest:LongWord; CName:TStr; Tmp:LongInt; cstru : TConstructInfo;
   
   Procedure AddToken(Const Tok:PToken);
      begin
      If (Etk = Length(E^.Tok))
         then SetLength(E^.Tok, Etk + 8);
      
      E^.Tok[Etk] := Tok;
      Etk += 1
      end;
   
   Function cstruType():ShortString;
      begin
      Case cstru.Typ of
             CT_IF: Exit('!if');
          CT_WHILE: Exit('!while');
         CT_REPEAT: Exit('!repeat');
         else Exit('!_UNKNOWN')
      end end;
   
   Procedure Construct_If();
      begin
      A := Length(IfArr);
      SetLength(IfArr,(A+1));
      IfArr[A][0]:=Ln; // !if line number
      IfArr[A][1]:=-1; // !else expression number
      IfArr[A][2]:=-1; // !fi expression number
      cstruStack^.Push(mkcstru(CT_IF, A)); // push !if identifier on stack, so we know which !if to match !else and !fi to
      
      SetLength(E^.Tok, 1);
      E^.Tok[0] := NewToken(VT_INT, A);
      FPtr.Usr := False; FPtr.Ref := REF_CONST;
      FPtr.Ptr := PtrUInt(@F_If)
      end;
   
   Procedure Construct_Else();
      begin
      If (cstruStack^.Empty) then Fatal(Ln,'!else without corresponding !if.');
      cstru:=cstruStack^.Peek();
      
      If (cstru.Typ <> CT_IF)
         then Fatal(Ln,'!else inside a '+cstruType()+' block.');
      If (IfArr[cstru.Idx][1]>=0)
         then Fatal(Ln,'!if from line '+IntToStr(IfArr[cstru.Idx][0])+' has a second !else.');
      
      If (LeTk - T > 1) then Fatal(Ln,'!else cannot take any arguments.');
      
      IfArr[cstru.Idx][1]:=Pr[Proc].Num; // set !else expression number
      
      SetLength(E^.Tok, 1);
      E^.Tok[0] := NewToken(VT_INT, cstru.Idx);
      FPtr.Usr := False; FPtr.Ref := REF_CONST;
      FPtr.Ptr := PtrUInt(@F_Else)
      end;
   
   Procedure Construct_Fi();
      begin
      If (cstruStack^.Empty) then Fatal(Ln,'!fi without corresponding !if.');
      cstru:=cstruStack^.Pop();
      
      If (cstru.Typ <> CT_IF)
         then Fatal(Ln,'!fi inside a '+cstruType()+' block.');
      
      If (LeTk - T > 1) then Fatal(Ln,'!fi cannot take any arguments.');
      
      IfArr[cstru.Idx][2]:=Pr[Proc].Num; // set !fi expr num
      If (IfArr[cstru.Idx][1]<0) then IfArr[cstru.Idx][1]:=Pr[Proc].Num; // if !else expr num is not present, set it to !fi expr num
      
      SetLength(E^.Tok, 1);
      E^.Tok[0] := NewToken(VT_INT, cstru.Idx);
      FPtr.Usr := False; FPtr.Ref := REF_CONST;
      FPtr.Ptr := PtrUInt(@F_)
      end;
   
   Procedure Construct_While();
      begin
      A:=Length(WhiArr);
      SetLength(WhiArr,(A+1));
      WhiArr[A][0]:=Ln;             // set !while line number
      WhiArr[A][1]:=Pr[Proc].Num-1; // set !while jump point
      WhiArr[A][2]:=-1;             // set !done expr num
      cstruStack^.Push(mkcstru(CT_WHILE, A));
      
      SetLength(E^.Tok, 1);
      E^.Tok[0] := NewToken(VT_INT, A);
      FPtr.Usr := False; FPtr.Ref := REF_CONST;
      FPtr.Ptr := PtrUInt(@F_While)
      end;
   
   Procedure Construct_Done();
      begin
      If (cstruStack^.Empty()) then Fatal(Ln,'!done without corresponding !while.');
      cstru:=cstruStack^.Pop();
      
      If (cstru.Typ <> CT_WHILE)
         then Fatal(Ln,'!done inside a '+cstruType()+' block.');
      
      If (LeTk - T > 1) then Fatal(Ln,'!done cannot take any arguments.');
      
      WhiArr[cstru.Idx][2]:=Pr[Proc].Num; // set !done expr num
      
      SetLength(E^.Tok, 1);
      E^.Tok[0] := NewToken(VT_INT, cstru.Idx);
      FPtr.Usr := False; FPtr.Ref := REF_CONST;
      FPtr.Ptr := PtrUInt(@F_Done)
      end;
   
   Procedure Construct_Repeat();
      begin
      If (LeTk - T > 1) then Fatal(Ln,'!repeat cannot take any arguments.');
      
      A:=Length(RepArr);
      SetLength(RepArr,(A+1));
      RepArr[A][0]:=Ln;           // set !repeat line number
      RepArr[A][1]:=Pr[Proc].Num; // set !repeat jump point
      RepArr[A][2]:=-1;           // set !until expr num
      cstruStack^.Push(mkcstru(CT_REPEAT, A));
      
      SetLength(E^.Tok, 1);
      E^.Tok[0] := NewToken(VT_INT, A);
      FPtr.Usr := False; FPtr.Ref := REF_CONST;
      FPtr.Ptr := PtrUInt(@F_)
      end;
   
   Procedure Construct_Until();
      begin
      If (cstruStack^.Empty()) then Fatal(Ln,'!until without corresponding !repeat.');
      cstru:=cstruStack^.Pop();
      
      If (cstru.Typ <> CT_REPEAT)
         then Fatal(Ln,'!until inside a '+cstruType()+' block.');
      
      RepArr[cstru.Idx][2]:=Pr[Proc].Num; // set !until expr num
      
      SetLength(E^.Tok, 1);
      E^.Tok[0] := NewToken(VT_INT, cstru.Idx);
      FPtr.Usr := False; FPtr.Ref := REF_CONST;
      FPtr.Ptr := PtrUInt(@F_Until)
      end;
   
   Procedure Construct_Const();
      begin
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
      If (Tk[T+2][1]='u') then
         V:=NewVal(VT_UTF,Copy(Tk[T+2],3,Length(Tk[T+2])-3)) else
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
         Try    V:=CopyVal(Cons^.GetVal(Copy(Tk[T+2],2,Length(Tk[T+2]))))
         Except Fatal(Ln,'Unknown const "'+Copy(Tk[T+2],2,Length(Tk[T+2]))+'".') end;
      V^.Lev := 0; Cons^.SetVal(CName,V)
      end;
   
   Procedure Construct_Fun();
      begin
      If (Not cstruStack^.Empty) then begin
         cstru:=cstruStack^.Peek();
         Fatal(Ln,'!fun inside a '+cstruType()+'block.')
         end;
      If (Proc<>0) then Fatal(Ln,'Nested function declaration.');
      If ((LeTk-T)<2) then Fatal(Ln,'No function name specified.');
      If (Length(Tk[T+1])=0) or (Tk[T+1][1]<>':')
         then Fatal(Ln,'Function names must start with the colon (":") character.');
      CName:=Copy(Tk[T+1],2,Length(Tk[T+1]));
      If (Func^.IsVal(CName))
         then DupeFuncFatal(Ln,CName);
      SetLength(Pr,Length(Pr)+1);
      Proc:=High(Pr); ExLn:=0;
      Pr[Proc].Fil := Length(FileIncludes); Pr[Proc].Lin := Ln;
      Pr[Proc].Num := 0; SetLength(Pr[Proc].Exp,0);
      SetLength(Pr[Proc].Arg, LeTk - 2); A := 0;
      Func^.SetVal(CName,MkFunc(Proc)); T+=2;
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
      end;
   
   Procedure Construct_Nuf();
      begin
      If (Proc = 0) then Fatal(Ln,'!nuf without corresponding !fun.');
      If (Not cstruStack^.Empty) then cstruFatal(Ln);
      
      SetLength(Pr[Proc].Exp, Pr[Proc].Num);
      Proc:=0; ExLn:=Pr[0].Num-1
      end;
   
   Procedure Construct_Skip(Brk:Boolean);
      Var cstruName : ShortString; Constant : PValue; 
          DepStr:AnsiString; Dep:Int64; Met:LongWord;
      begin
      If (Brk) then cstruName := '!break' else cstruName := '!continue';
      If (cstruStack^.Empty) then Fatal(Ln,cstruName+' outside a loop block.');
      
      If (LeTk > 1) then begin
         If (LeTk > 2) then Fatal(Ln,cstruName+' accepts at most one parameter.');
         DepStr := Copy(Tk[1], 2, Length(Tk[T]));
         If (Tk[1][1]='s') then Dep := Values.StrToInt(Copy(DepStr,2,Length(DepStr)-2)) else
         If (Tk[1][1]='u') then Dep := Values.StrToInt(Copy(DepStr,2,Length(DepStr)-2)) else
         If (Tk[1][1]='i') then Dep := Values.StrToInt(DepStr) else
         If (Tk[1][1]='h') then Dep := Values.StrToHex(DepStr) else
         If (Tk[1][1]='o') then Dep := Values.StrToOct(DepStr) else
         If (Tk[1][1]='b') then Dep := Values.StrToBin(DepStr) else
         If (Tk[1][1]='f') then Dep := Trunc(Values.StrToReal(DepStr)) else
         If (Tk[1][1]='l') then Dep := BoolToInt(StrToBoolDef(DepStr,False)) else
         If (Tk[1][1]='=') then begin
            Try    Constant := Cons^.GetVal(DepStr);
            Except Fatal(Ln,'Unknown constant "'+DepStr+'"') end;
            Dep := ValAsInt(Constant)
            end else
            Fatal(Ln,'Arguments for '+cstruName+' must be either value literals or constants.');
         
         If (Dep <= 0) then Fatal(Ln,'invalid '+cstruName+' depth ('+IntToStr(Dep)+').')
         end else Dep := 1;
      
      A := 0; Met := 0;
      Repeat
         cstru := cstruStack^.Peek(A); A += 1;
         If (cstru.Typ <> CT_IF) then begin 
            Met += 1; If (Met = Dep) then break
            end;
         If (cstruStack^.Count <= A) then begin
            If (LeTk = 1) then Fatal(Ln,cstruName+' outside a loop block.')
                          else Fatal(Ln,cstruName+' depth ('+IntToStr(Dep)+') is greater than loop nest level ('+IntToStr(Met)+').')
            end
         until False;
      
      SetLength(E^.Tok, 2);
      E^.Tok[0] := NewToken(VT_INT, Ord(cstru.Typ));
      E^.Tok[1] := NewToken(VT_INT, cstru.Idx);
      FPtr.Usr := False; FPtr.Ref := REF_CONST;
      If (Brk) then FPtr.Ptr := PtrUInt(@F_Break)
               else FPtr.Ptr := PtrUInt(@F_Continue)
      end;
   
   Procedure Construct_Include(Req:Boolean);
      Var FileName,Construct:AnsiString; Constant:PValue; F:System.Text;
          OldName, OldPath : AnsiString; FiIn:LongWord;
          OldNameCons, OldPathCons : PValue;
      begin
      If (Req) then Construct := '!require' else Construct := '!include';
      FileName := Copy(Tk[T], 2, Length(Tk[T]));
      If (Tk[T][1]='s') then begin Delete(FileName,Length(FileName),1); Delete(FileName,1,1) end else
      If (Tk[T][1]='u') then begin Delete(FileName,Length(FileName),1); Delete(FileName,1,1) end else
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
   
   Function GetFunc(Const Name:AnsiString):Boolean;
      begin
      Try FPtr:=Func^.GetVal(Name);
          Exit(True)
      Except
          Exit(False)
      end end;
   
   begin
   New(E); LeTk:=Length(Tk);
   If (Tk[T][1]=':') then begin
      If (Not GetFunc(Copy(Tk[T],2,Length(Tk[T]))))
         then Fatal(Ln,'Unknown function: "'+Tk[T]+'".');
      
      If (FPtr.Usr) then begin
         SetLength(E^.Tok, 1);
         E^.Tok[0] := NewToken(VT_INT, FPtr.Ptr);
         FPtr.Ptr:=PtrUInt(@F_AutoCall)
         end
      end else
   If (Tk[T][1]='!') then Case (Tk[T]) of
      '!if': 
         Construct_If();
      '!else': 
         Construct_Else();
      '!fi': 
         Construct_Fi();
      '!while':
         Construct_While();
      '!done':
         Construct_Done();
      '!repeat':
         Construct_Repeat();
      '!until':
         Construct_Until();
      '!break':
         Construct_Skip(SKIP_BREAK);
      '!continue':
         Construct_Skip(SKIP_CONTINUE);
      '!const': begin
         Construct_Const();
         Dispose(E); Exit(NIL)
         end;
      '!fun': begin
         Construct_Fun();
         Dispose(E); Exit(NIL)
         end;
      '!nuf': begin
         Construct_Nuf();
         Dispose(E); Exit(NIL)
         end;
      '!include': begin
         T += 1; If (T = LeTk) then Error(Ln,'!include without arguments.');
         Repeat Construct_Include(INCL_INCLUDE); T += 1 until (T = LeTk);
         Dispose(E); Exit(NIL)
         end;
      '!require': begin
         T += 1; If (T = LeTk) then Fatal(Ln,'!require without arguments.');
         Repeat Construct_Include(INCL_REQUIRE); T += 1 until (T = LeTk);
         Dispose(E); Exit(NIL)
         end;
      {'!return': begin
         If (Proc = 0) then Fatal(Ln,'!return used in main function.');
         FPtr:=@F_Return
         end; }
      else
         Fatal(Ln,'Unknown language construct: "'+Tk[T]+'".')
      end else
      Fatal(Ln,'First token in expression ("'+Tk[T]+'") is neither a function call nor a language construct.');
   E^.Fun:=TBuiltIn(FPtr.Ptr); E^.Ref := FPtr.Ref;
   T+=1; If (T >= LeTk) then Exit(E);
   Etk := Length(E^.Tok); If (LeTk > Etk) then SetLength(E^.Tok, LeTk);
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
            Fatal(Ln,'Invalid token ("'+Tk[T]+'").')
         end;
      T+=1 end;
   SetLength(E^.Tok, Etk); Exit(E)
   end;

Procedure ProcessLine(L:AnsiString;N:LongWord);
   Var Tk:Array of AnsiString; P,S,Len:LongWord;
       Str:LongInt; Del:Char; PipeChar:AnsiString;
       Ex:PExpr; HiTk, Rs :LongWord; Utf:Boolean;
   
   Function BreakToken(Ch:Char):Boolean; Inline;
      begin Exit(Pos(Ch,' (|)[#]~')<>0) end;
   
   begin
   {$IFDEF CGI}
   If (codemode = 0) and (Length(L) = 0) then begin
      SetLength(Tk,1); Tk[0]:=':writeln';
      AddExpr(MakeExpr(Tk, N, 0));
      Exit()
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
         If (Str=0) and ((L[P]='s') or (L[P]='u'))
            then begin Str:=+1; Utf:=L[P]='u' end
            else Str:=-1
         end else
      If (Str = 1) then begin
         If (P>Len) then begin
            Error(N,'String prefix found at end of line.');
            SetLength(Tk,Length(Tk)+1);
            If (Not Utf) then Tk[High(Tk)]:='s""'
                         else Tk[High(Tk)]:='u""';
            S:=Len+1; Str:=0
            end else begin
            Del:=L[P]; Str:=2
         end end else
      If (Str = 2) and ((P>Len) or (L[P]=Del)) then begin
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
   If (Length(Tk)=0) then Exit();
   If (Length(Tk)=1) and (Tk[0][1]='~') then Exit();
   Rs:=0; HiTk := High(Tk); P:=1;
   While (P <= HiTk) do begin
      If (Tk[P][1]='!') then begin //if (n=11) then writeln('makeexpr ',rs,'..',p-1);
         Ex := MakeExpr(Tk[Rs..P-1], N, 0);
         If (Ex<>NIL) then AddExpr(Ex);
         Rs := P;
         end else
      If (Tk[P][1]='~') then begin
         If (Tk[Rs][1]<>'~') then begin //if (n=11) then writeln('makeexpr ',rs,'..',p-1);
            Ex:=MakeExpr(Tk[Rs..P-1], N, 0);
            If (Ex<>NIL) then AddExpr(Ex)
            end;
         While (P <= HiTk) and (Tk[P][1] = '~') do P += 1; Rs := P;
         If (P > HiTk) or (Tk[P][1] <> '!') then P -= 1
         end;
      P += 1
      end;
   If (Rs <= HiTk) and (Tk[Rs][1]<>'~') then begin
      Ex := MakeExpr(Tk[Rs..HiTk], N, 0); 
      If (Ex<>NIL) then AddExpr(Ex)
      end
   end;

Procedure ParseFile(Var I:System.Text);
   Var L:AnsiString; N:LongWord; 
   begin
   N := 0;
   While (Not Eof(I)) do begin
      Readln(I,L); N+=1;
      {$IFNDEF CGI} L:=Trim(L); {$ELSE} If (codemode > 0) then L:=TrimLeft(L); {$ENDIF}
      {$IFNDEF CGI} If (Length(L)>0) then begin {$ENDIF}
         ProcessLine(L, N)
         end
      {$IFNDEF CGI} end {$ENDIF}
   end;

Procedure ReadFile(Var I:System.Text);
   
   {$IFDEF CGI}{$DEFINE __ISCGI__:=True}{$ELSE}{$DEFINE __ISCGI__:=False}{$ENDIF}
   
   Function BuildNum():AnsiString; Inline;
      Var D,T:AnsiString;
      begin
      D:={$I %DATE%}; Delete(D, 8, 1);
      T:={$I %TIME%}; Delete(T, 3, 1); Delete(T, 5, 3);
      Exit(D+'/'+T)
      end;
   
   Var V:PValue; PTV:PValue; 
   begin
   SetLength(Pr,1); Proc:=0; ExLn:=0; mulico:=0; {$IFDEF CGI} codemode:=0; {$ENDIF}
   SetLength(Pr[0].Arg,0); SetLength(Pr[0].Exp,0); Pr[0].Num:=0;
   
   New(cstruStack, Create());
   SetLength(IfArr,0); SetLength(WhiArr,0); SetLength(RepArr,0);
   SetLength(FileIncludes, 0);
   
   New(Cons,Create(#33,#255));
   SpareVars_Prepare();
   
   V:=NilVal(); V^.Lev := 0; Cons^.SetVal('NIL', V);
   
   {$IFDEF CGI} V:=NewVal(VT_STR, GetEnvironmentVariable('REQUEST_METHOD')); V^.Lev:=0; Cons^.SetVal('REQUEST-METHOD', V); {$ENDIF}
   
   V:=NewVal(VT_STR,YukPath); V^.Lev := 0; Cons^.SetVal('FILE-PATH',V);
   V:=NewVal(VT_STR,YukName); V^.Lev := 0; Cons^.SetVal('FILE-NAME',V);
   
   V:=NewVal(VT_BOO,__ISCGI__);   V^.Lev := 0; Cons^.SetVal('AWFUL-CGI',V);
   V:=NewVal(VT_STR,ParamStr(0)); V^.Lev := 0; Cons^.SetVal('AWFUL-PATH',V);
   V:=NewVal(VT_STR,BuildNum());  V^.Lev := 0; Cons^.SetVal('AWFUL-BUILD',V);
   V:=NewVal(VT_STR,VERSION);     V^.Lev := 0; Cons^.SetVal('AWFUL-VERSION',V);
   V:=NewVal(VT_INT,VREVISION);   V^.Lev := 0; Cons^.SetVal('AWFUL-REVISION',V);
   PTV:=EmptyVal(VT_INT);       PTV^.Lev := 0; Cons^.SetVal('AWFUL-PARSETIME',PTV);
   
   V:=NewVal(VT_FLO,2.71828182845904523536); V^.Lev := 0; Cons^.SetVal('e',  V);
   V:=NewVal(VT_FLO,3.14159265358979323846); V^.Lev := 0; Cons^.SetVal('pi', V);
   
   SetLength(FCal,1); New(FCal[0].Vars,Create(#33,#255)); FCal[0].Args := NIL; FLev := 0;
   
   ParseFile(I); // loop moved to other file
   
   If (mulico > 0) then Writeln(StdErr,YukName,': multi-line comment stretches past end of code.');
   
   If (Not cstruStack^.Empty) then cstruFatal(0);
   Dispose(cstruStack, Destroy());
   
   If (Proc <> 0) then Fatal(0,'!fun block stretches past end of code.');
   SetLength(Pr[0].Exp, Pr[0].Num); // truncate array of main function
   
   PQInt(PTV^.Ptr)^ := Ceil(TimeStampToMSecs(DateTimeToTimeStamp(Now()))-GLOB_ms)
   end;

end.
