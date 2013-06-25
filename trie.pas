unit trie;

{$MODE OBJFPC} {$COPERATORS ON} 

(* Do you want the Trie to be an object or a class? Obviously, it's   *
 * impossible to have both at the same time. If both symbols are set, *
 * Trie becomes a class. If none are set, compilation error occurs.   *)
//{$DEFINE TRIE_CLASS}
{$DEFINE TRIE_OBJECT} 

interface
   uses SysUtils;

{$MACRO ON}
{$IFDEF TRIE_CLASS}  {$DEFINE TRIETYPE:=Class(TObject)} {$ELSE}
{$IFDEF TRIE_OBJECT} {$DEFINE TRIETYPE:=Object}         {$ELSE}
   {$FATAL No OBJECT/CLASS symbol set!} {$ENDIF} {$ENDIF}

Type ExNotSet = class(Exception);
     
     generic GenericTrie<Tp> = TRIETYPE
     Private
        Type
        PTp = ^Tp;
        PNode = ^TNode;
        TNode = record
           Nxt : Array of PNode;
           Chi : LongWord;
           Val : PTp;
           end;
        Var
        Min, ArrS : LongInt;
        Vals : LongWord;
        Root : PNode;
        {Method}
        Procedure SetVal(Const K:AnsiString;P:LongWord;N:PNode;Const V:Tp);
        Procedure RemVal(Const K:AnsiString;P:LongWord;N:PNode);
        
        Function  IsVal(Const K:AnsiString;P:LongWord;N:PNode):Boolean;
        Function  GetVal(Const K:AnsiString;P:LongWord;N:PNode):Tp;
        
        Function  NextKey(N:PNode;K:AnsiString;Var R:AnsiString):Boolean;
        
        Function  GetVal(N:PNode):Tp;
        Function  RemVal(N:PNode):Tp;
        Procedure FreeNode(N:PNode);
     Public
        Procedure SetVal(Key:AnsiString;Val:Tp);
        Procedure RemVal(Key:AnsiString);
        
        Function  IsVal(Key:AnsiString):Boolean;
        Function  GetVal(Key:AnsiString):Tp;
        
        Function  GetVal():Tp;
        Function  RemVal():Tp;
        
        Function  NextKey(K:AnsiString):AnsiString;
        
        Function Empty() : Boolean;
        Property Count   : LongWord read Vals;
        
        Procedure Flush();
        
        Constructor Create(argMin, argMax : Char);
        Destructor  Destroy(); {$IFDEF TRIE_CLASS} Override; {$ENDIF}
     end;

implementation

Procedure GenericTrie.SetVal(Const K:AnsiString;P:LongWord;N:PNode;Const V:Tp);
   Var I:LongWord; E:PNode; C:LongWord;
   begin
   If (P<=Length(K)) then begin
      I:=Ord(K[P])-Min;
      If (N^.Nxt[I] = NIL) then begin
         New(E); SetLength(E^.Nxt,ArrS);
         E^.Val:=NIL; E^.Chi:=0;
         For C:=Low(E^.Nxt) to High(E^.Nxt) do E^.Nxt[C]:=NIL;
         N^.Nxt[I]:=E; N^.Chi+=1
         end;
      SetVal(K,P+1,N^.Nxt[I],V)
      end else begin
      If (N^.Val = NIL) then begin New(N^.Val); Self.Vals+=1 end;
      N^.Val^:=V
      end
   end;

Procedure GenericTrie.SetVal(Key:AnsiString;Val:Tp);
   begin SetVal(Key,1,Root,Val) end;

Procedure GenericTrie.RemVal(Const K:AnsiString;P:LongWord;N:PNode);
   Var I:LongWord;
   begin
   If (P<=Length(K)) then begin
      I:=Ord(K[P])-Min;
      If (N^.Nxt[I] = NIL) then Exit();
      RemVal(K,P+1,N^.Nxt[I]);
      If (N^.Nxt[I]^.Chi = 0) and (N^.Nxt[I]^.Val = NIL) then begin
         Dispose(N^.Nxt[I]); N^.Nxt[I]:=NIL;
         N^.Chi-=1
         end
      end else begin
      If (N^.Val <> NIL) then begin
         Dispose(N^.Val); N^.Val:=NIL;
         Self.Vals -= 1 end
      end
   end;

Procedure GenericTrie.RemVal(Key:AnsiString);
   begin RemVal(Key,1,Root) end;

Function GenericTrie.IsVal(Const K:AnsiString;P:LongWord;N:PNode):Boolean;
   Var I:LongWord;
   begin
   If (P<=Length(K)) then begin
      I:=Ord(K[P])-Min;
      If (N^.Nxt[I] = NIL) then Exit(False);
      Exit(IsVal(K,P+1,N^.Nxt[I]))
      end else begin
      Exit(N^.Val <> NIL)
      end;
   end;

Function GenericTrie.IsVal(Key:AnsiString):Boolean;
   begin Exit(IsVal(Key,1,Root)) end;

Function GenericTrie.GetVal(Const K:AnsiString;P:LongWord;N:PNode):Tp;
   Var I:LongWord;
   begin
   If (P<=Length(K)) then begin
      I:=Ord(K[P])-Min;
      If (N^.Nxt[I] = NIL) 
         then Raise ExNotSet.Create('Called GenericTrie.GetVal() with an unset key!');
      Exit(GetVal(K,P+1,N^.Nxt[I]))
      end else begin
      If (N^.Val = NIL)
         then Raise ExNotSet.Create('Called GenericTrie.GetVal() with an unset key!');
      Exit(N^.Val^)
      end;
   end;

Function GenericTrie.GetVal(Key:AnsiString):Tp;
   begin Exit(GetVal(Key,1,Root)) end;

Function GenericTrie.Empty():Boolean;
   begin Exit(Self.Vals = 0) end;

Constructor GenericTrie.Create(argMin, argMax : Char);
   Var C:LongWord;
   begin
   {$IFDEF TRIE_CLASS} Inherited Create(); {$ENDIF}
   Min:=ord(argMin); ArrS:=Ord(argMax)-Ord(argMin)+1;
   New(Root); SetLength(Root^.Nxt,ArrS);
   Root^.Chi:=0; Root^.Val:=NIL;
   For C:=Low(Root^.Nxt) to High(Root^.Nxt) do Root^.Nxt[C]:=NIL;
   Self.Vals:=0
   end;

Function GenericTrie.GetVal(N:PNode):Tp;
   Var C:LongWord;
   begin
   If (N^.Val <> NIL) Then Exit(N^.Val^);
   If (N^.Chi = 0) then
      Raise ExNotSet.Create('Called GenericTrie.GetVal() on an empty trie!');
   For C:=Low(N^.Nxt) to High(N^.Nxt) do
       If (N^.Nxt[C]<>NIL) then Exit(GetVal(N^.Nxt[C]))
   end;

Function GenericTrie.GetVal():Tp;
   begin Exit(GetVal(Root)) end;

Function GenericTrie.RemVal(N:PNode):Tp;
   Var C:LongWord; R:Tp;
   begin
   If (N^.Val <> NIL) Then begin
      R:=N^.Val^; Dispose(N^.Val); N^.Val:=NIL; Self.Vals-=1;
      Exit(R)
      end;
   If (N^.Chi = 0) then
      Raise ExNotSet.Create('Called GenericTrie.RemVal() on an empty trie!');
   For C:=Low(N^.Nxt) to High(N^.Nxt) do
       If (N^.Nxt[C]<>NIL) then begin
          R:=RemVal(N^.Nxt[C]);
          If (N^.Nxt[C]^.Val = NIL) and (N^.Nxt[C]^.Chi = 0) then begin
             Dispose(N^.Nxt[C]); N^.Nxt[C]:=NIL; N^.Chi-=1
             end;
          Exit(R)
          end
   end;

Function GenericTrie.RemVal():Tp;
   begin Exit(RemVal(Root)) end;

Function GenericTrie.NextKey(N:PNode;K:AnsiString;Var R:AnsiString):Boolean;
   Var C,I,S:LongWord;
   begin
   If (N^.Chi = 0) then Exit(False);
   If (Length(K)>0) then begin
      I:=Ord(K[1])-Self.Min; Delete(K,1,1);
      If (N^.Nxt[I]<>NIL) then begin
         If (NextKey(N^.Nxt[I],K,R)) then begin
            R:=Chr(Self.Min+I)+R; Exit(True)
         end end;
      S:=(I+1) 
      end else S:=Low(N^.Nxt);
   For C:=S to High(N^.Nxt) do
       If (N^.Nxt[C]<>NIL) then
          If (N^.Nxt[C]^.Val<>NIL)
             then begin 
             R:=Chr(Self.Min+C)+R; Exit(True)
             end else begin
             If (NextKey(N^.Nxt[C],'',R)) then begin
                R:=Chr(Self.Min+C)+R; Exit(True)
             end end;
   Exit(False)
   end;

Function GenericTrie.NextKey(K:AnsiString):AnsiString;
   Var R:AnsiString;
   begin R:='';
   If NextKey(Root,K,R) then Exit(R) else Exit('') end;

Procedure GenericTrie.FreeNode(N:PNode);
   Var I:LongWord;
   begin
   If (N^.Chi > 0) then begin
      For I:=Low(N^.Nxt) to High(N^.Nxt) do
          If (N^.Nxt[I]<>NIL) then begin
             FreeNode(N^.Nxt[I]);
             Dispose(N^.Nxt[I]);
             N^.Nxt[I]:=NIL
             end;
      N^.Chi:=0
      end;
   If (N^.Val <> NIL) then begin Dispose(N^.Val); Self.Vals-=1 end
   end;

Procedure GenericTrie.Flush();
   begin FreeNode(Root) end;

Destructor GenericTrie.Destroy();
   begin
   Flush(); Dispose(Root);
   {$IFDEF TRIE_CLASS} ; Inherited Destroy() {$ENDIF}
   end;

end.
