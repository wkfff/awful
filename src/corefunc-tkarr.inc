If (T < E^.Num)
   then 
      If(E^.Arg[T+1]^.Typ <> VT_CHR)
         then Tp:=E^.Arg[T+1]^.Typ
         else Tp:=E^.Arg[T+1]^.Chr^.Val^.Typ
   else Tp:=VT_NIL;

E^.Arg[T]:=GetVar(E^.Tok[T]^.atk^.Nam, VT_DIC);

For I:=Low(E^.Tok[T]^.atk^.Ind) to High(E^.Tok[T]^.atk^.Ind) do
   E^.Arg[T]:=GetArr(E^.Arg[T], E^.Tok[T]^.atk^.Ind[I], Tp);
