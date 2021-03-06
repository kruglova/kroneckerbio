fastchar := proc(f)
begin
    // Substitute MATLAB-style constant names for MuPAD-style constant names
    f := subs(f, PI=pi, EULER=eulergamma, CATALAN=catalan);
    if testtype(f,Dom::Matrix()) then
        numberofterms := nops(f);
    else
        numberofterms := 1;
    end_if;
    
    stringtoreturn := "{";
    if numberofterms = 1 then
        stringtoreturn := stringtoreturn."'".expr2text(f)."'";
    else
        for termindex from 1 to numberofterms do
            if termindex = numberofterms then
                stringtoreturn := stringtoreturn."'".f[termindex,1]."'";
            else
                stringtoreturn := stringtoreturn."'".f[termindex,1]."';";
            end_if;
        end_for;
    end_if;
    stringtoreturn := stringtoreturn."}";
    return(stringtoreturn)
end_proc