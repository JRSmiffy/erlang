%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1996-2009. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
-module(io_lib_fread).

%% Formatted input functions of io library.

-export([fread/2,fread/3]).

-import(lists, [reverse/1,reverse/2]).

%% fread(Continuation, CharList, FormatString)
%%  This is the main function into the re-entrant formatted reader. It
%%  repeatedly collects lines and calls fread/2 to format the input until
%%  all the format string has been used. And it counts the characters.

fread([], Chars, Format) ->
    %%io:format("FREAD: ~w `~s'~n", [Format,Chars]),
    fread_collect(Format, [], 0, [], Chars);
fread({Format,Stack,N,Results}=_Continuation, Chars, _) ->
    %%io:format("FREAD: ~w `~s'~n", [_Continuation,Chars]),
    fread_collect(Format, Stack, N, Results, Chars).

fread_collect(Format, [$\r|Stack], N, Results, [$\n|Chars]) ->
    fread_line(Format, reverse(Stack), N, Results, Chars, [$\r,$\n]);
fread_collect(Format, Stack, N, Results, [$\n|Chars]) ->
    fread_line(Format, reverse(Stack), N, Results, Chars, [$\n]);
fread_collect(Format, Stack, N, Results, []) ->
    Continuation = {Format,Stack,N,Results},
    {more,Continuation};
fread_collect(Format, [$\r|Stack], N, Results, Chars) -> % Maybe eof
    fread_line(Format, reverse(Stack), N, Results, Chars, [$\r]);
fread_collect(Format, Stack, N, Results, [C|Chars]) ->
    fread_collect(Format, [C|Stack], N, Results, Chars);
fread_collect(Format, Stack, N, Results, Chars) -> % eof
    fread_line(Format, reverse(Stack), N, Results, Chars, []).

fread_line(Format0, Line, N0, Results0, More, Newline) ->
    %%io:format("FREAD1: `~s' `~s'~n", [Format0,Line]),
    Chars = if is_list(More) -> More; true -> [] end,
    case fread(Format0, Line, N0, Results0) of
	{ok,Results,[]} ->
	    {done,{ok,Results},Chars};
	{ok,Results,Rest} ->
	    %% Don't loose the whitespace
	    {done,{ok,Results},Rest++(Newline++Chars)};
	%% fread/4 should not return {more,...} on eof; guard just in case...
	%% Count newline characters here since fread/4 does not get them.
	{more,Format,N,Results} when is_list(Line), is_list(More) ->
	    fread_collect(Format, [], N+length(Newline), Results, More);
	{more,Format,N,Results} when is_list(Line) -> % eof
	    fread_line(Format, eof, N+length(Newline), Results, More, []);
	Other ->				%An error has occurred
	    {done,Other,More}
    end.


%% Conventions
%%   ~s 	String White terminated
%%   ~d         Integer terminated by ~[0-9]
%%   ~u         Unsigned integer in base 2..36, no leading whitespace
%%   ~-         Optional sign character, no leading whitespace
%%   ~f         Float
%%   ~a         as ~s but converted to an atom
%%   ~c		characters without any stripping
%%   ~n		number of characters scanned
%%   WHITE      Skip white space
%%   X          Literal X

fread(Format, Line) ->
    fread(Format, Line, 0, []).

fread([$~|Format0], Line, N, Results) ->
    {Format,F,Sup,Unicode} = fread_field(Format0),
    fread1(Format, F, Sup, Unicode, Line, N, Results, Format0);
fread([$\s|Format], Line, N, Results) ->
    fread_skip_white(Format, Line, N, Results);
fread([$\t|Format], Line, N, Results) ->
    fread_skip_white(Format, Line, N, Results);
fread([$\r|Format], Line, N, Results) ->
    fread_skip_white(Format, Line, N, Results);
fread([$\n|Format], Line, N, Results) ->
    fread_skip_white(Format, Line, N, Results);
fread([C|Format], [C|Line], N, Results) ->
    fread(Format, Line, N+1, Results);
fread([_F|_Format], [_C|_Line], _N, _Results) ->
    fread_error(input);
fread([], Line, _N, Results) ->
    {ok,reverse(Results),Line}.

fread_skip_white(Format, [$\s|Line], N, Results) ->
    fread_skip_white(Format, Line, N+1, Results);
fread_skip_white(Format, [$\t|Line], N, Results) ->
    fread_skip_white(Format, Line, N+1, Results);
fread_skip_white(Format, [$\r|Line], N, Results) ->
    fread_skip_white(Format, Line, N+1, Results);
fread_skip_white(Format, [$\n|Line], N, Results) ->
    fread_skip_white(Format, Line, N+1, Results);
fread_skip_white(Format, Line, N, Results) ->
    fread(Format, Line, N, Results).

%% fread_field(Format) 
%%  Reads the field specification paramters. Returns:
%%
%%	{RestFormat,FieldWidth,Suppress}

fread_field([$*|Format]) -> fread_field(Format, true, false);
fread_field(Format) -> fread_field(Format, false, false).

fread_field([C|Format], Sup, Unic) when C >= $0, C =< $9 ->
    fread_field(Format, C - $0, Sup, Unic);
fread_field([$t|Format], Sup, _Unic) -> 
    {Format,none,Sup,true};
fread_field(Format, Sup, Unic) -> 
    {Format,none,Sup,Unic}.

fread_field([C|Format], F, Sup, Unic) when C >= $0, C =< $9 ->
    fread_field(Format, 10*F + C - $0, Sup, Unic);
fread_field([$t|Format], F, Sup, _Unic) ->
    {Format,F,Sup,true};
fread_field(Format, F, Sup, Unic) ->
    {Format,F,Sup,Unic}.

%% fread1(Format, FieldWidth, Suppress, Line, N, Results, AllFormat)
%% fread1(Format, FieldWidth, Suppress, Line, N, Results)
%%  The main dispatch function for the formatting commands. Done in two
%%  stages so format commands that need no input can always be processed.

fread1([$l|Format], _F, Sup, _U, Line, N, Res, _AllFormat) ->
    fread(Format, Line, N, fread_result(Sup, N, Res));
fread1(_Format, _F, _Sup, _U, [], N, Res, AllFormat) ->
    %% Need more input here.
    {more,[$~|AllFormat],N,Res};
fread1(_Format, _F, _Sup, _U, eof, _N, [], _AllFormat) ->
    %% This is at start of format string so no error.
    eof;
fread1(_Format, _F, _Sup, _U, eof, _N, _Res, _AllFormat) ->
    %% This is an error as there is no more input.
    fread_error(input);
fread1(Format, F, Sup, U, Line, N, Res, _AllFormat) ->
    fread1(Format, F, Sup, U, Line, N, Res).

fread1([$f|Format], none, Sup, false, Line0, N0, Res) ->
    {Line,N,Cs} = fread_float_cs(Line0, N0),
    fread_float(Cs, Sup, Format, Line, N, Res);
fread1([$f|Format], F, Sup, false, Line0, N, Res) ->
    {Line,Cs} = fread_chars(Line0, F, false),
    fread_float(Cs, Sup, Format, Line, N+F, Res);
fread1([$d|Format], none, Sup, false, Line0, N0, Res) ->
    {Line,N,Cs} = fread_int_cs(Line0, N0),
    fread_integer(Cs, 10, Sup, Format, Line, N, Res);
fread1([$d|Format], F, Sup, false, Line0, N, Res) ->
    {Line,Cs} = fread_chars(Line0, F, false),
    fread_integer(Cs, 10, Sup, Format, Line, N+F, Res);
fread1([$u|Format], none, Sup, false, Line0, N0, Res) ->
    {Line,N,Cs} = fread_digits(Line0, N0, 10, []),
    fread_unsigned(Cs, 10, Sup, Format, Line, N, Res);
fread1([$u|Format], F, Sup, false, Line0, N0, Res) when F >= 2, F =< 1+$Z-$A+10 ->
    {Line,N,Cs} = fread_digits(Line0, N0, F, []),
    fread_unsigned(Cs, F, Sup, Format, Line, N, Res);
fread1([$-|Format], _F, Sup, false, Line, N, Res) ->
    fread_sign_char(Sup, Format, Line, N, Res);
fread1([$#|Format], none, Sup, false, Line0, N0, Res) ->
    case catch
	begin
	    {Line1,N1,B1} = fread_base(Line0, N0),
	    B = abs(B1),
	    true = (B >= 2) and (B =< 1+$Z-$A+10),
	    {Line2,N2,Cs2} = fread_digits(Line1, N1, B, []),
	    fread_based(reverse(Cs2), B1, Sup, Format, Line2, N2, Res)
	end of
	{'EXIT',_} ->
	    fread_error(based);
	Other ->
	    Other
    end;
fread1([$#|Format], F, Sup, false, Line0, N, Res) ->
    case catch
	begin
	    {Line1,Cs1} = fread_chars(Line0, F, false),
	    {Line2,_,B2} = fread_base(reverse(Cs1), N),
	    true = ((B2 >= 2) and (B2 =< 1+$Z-$A+10)),
	    fread_based(Line2, B2, Sup, Format, Line1, N+F, Res)
	end	of
	{'EXIT',_} ->
	    fread_error(based);
	Other ->
	    Other
    end;
fread1([$s|Format], none, Sup, U, Line0, N0, Res) ->
    {Line,N,Cs} = fread_string_cs(Line0, N0, U),
    fread_string(Cs, Sup, U, Format, Line, N, Res);
fread1([$s|Format], F, Sup, U, Line0, N, Res) ->
    {Line,Cs} = fread_chars(Line0, F, U),
    fread_string(Cs, Sup, U, Format, Line, N+F, Res);
%% XXX:PaN Atoms still only latin1...
fread1([$a|Format], none, Sup, false, Line0, N0, Res) ->
    {Line,N,Cs} = fread_string_cs(Line0, N0, false),
    fread_atom(Cs, Sup, Format, Line, N, Res);
fread1([$a|Format], F, Sup, false, Line0, N, Res) ->
    {Line,Cs} = fread_chars(Line0, F, false),
    fread_atom(Cs, Sup, Format, Line, N+F, Res);
fread1([$c|Format], none, Sup, U, Line0, N, Res) ->
    {Line,Cs} = fread_chars(Line0, 1, U),
    fread_chars(Cs, Sup, U, Format, Line, N+1, Res);
fread1([$c|Format], F, Sup, U, Line0, N, Res) ->
    {Line,Cs} = fread_chars(Line0, F, U),
    fread_chars(Cs, Sup, U, Format, Line, N+F, Res);
fread1([$~|Format], _F, _Sup, _U, [$~|Line], N, Res) ->
    fread(Format, Line, N+1, Res);
fread1(_Format, _F, _Sup, _U, _Line, _N, _Res) ->
    fread_error(format).

%% fread_float(FloatChars, Suppress, Format, Line, N, Results)

fread_float(Cs, Sup, Format, Line, N, Res) ->
    case catch list_to_float(fread_skip_white(reverse(Cs))) of
	{'EXIT',_} ->
	    fread_error(float);
	Float ->
	    fread(Format, Line, N, fread_result(Sup, Float, Res))
    end.

%% fread_integer(IntegerChars, Base, Suppress, Format, Line, N, Results)

fread_integer(Cs, Base, Sup, Format, Line, N, Res) ->
    case catch erlang:list_to_integer(fread_skip_white(reverse(Cs)), Base) of
	{'EXIT',_} ->
	    fread_error(integer);
	Integer ->
	    fread(Format, Line, N, fread_result(Sup, Integer, Res))
    end.


%% fread_unsigned(IntegerChars, Base, Suppress, Format, Line, N, Results)

fread_unsigned(Cs, Base, Sup, Format, Line, N, Res) ->
    case catch erlang:list_to_integer(fread_skip_white(reverse(Cs)), Base) of
	{'EXIT',_} ->
	    fread_error(unsigned);
	Integer ->
	    fread(Format, Line, N, fread_result(Sup, Integer, Res))
    end.
    

%% fread_based(IntegerChars, Base, Suppress, Format, Line, N, Results)

fread_based(Cs0, B, Sup, Format, Line, N, Res) ->
    {Cs,Base} = if B < 0 -> {[$-|Cs0],-B};
		   true ->  {Cs0,B}
		end,
    I = erlang:list_to_integer(Cs, Base),
    fread(Format, Line, N, fread_result(Sup, I, Res)).
    

%% fread_sign_char(Suppress, Format, Line, N, Results)

fread_sign_char(Sup, Format, [$-|Line], N, Res) ->
    fread(Format, Line, N+1, fread_result(Sup, -1, Res));
fread_sign_char(Sup, Format, [$+|Line], N, Res) ->
    fread(Format, Line, N+1, fread_result(Sup, +1, Res));
fread_sign_char(Sup, Format, Line, N, Res) ->
    fread(Format, Line, N, fread_result(Sup, 1, Res)).


%% fread_string(StringChars, Suppress, Format, Line, N, Results)

fread_string(error, _Sup, _U, _Format, _Line, _N, _Res) ->
    fread_error(string);
fread_string(Cs0, Sup, U, Format, Line, N, Res) ->
    Cs = fread_skip_white(reverse(fread_skip_white(Cs0))),
    fread(Format, Line, N, fread_convert(fread_result(Sup, Cs, Res),U)).

%% fread_atom(AtomChars, Suppress, Format, Line, N, Results)

fread_atom(error, _Sup, _Format, _Line, _N, _Res) ->
    fread_error(atom);
fread_atom(Cs0, Sup, Format, Line, N, Res) ->
    Cs = fread_skip_white(reverse(fread_skip_white(Cs0))),
    fread(Format, Line, N, fread_result(Sup, list_to_atom(Cs), Res)).

%% fread_chars(Characters, Suppress, Format, Line, N, Results)

fread_chars(error, _Sup, _U, _Format, _Line, _N, _Res) ->
    fread_error(character);
fread_chars(Cs, Sup, U, Format, Line, N, Res) ->
    fread(Format, Line, N, fread_convert(fread_result(Sup, reverse(Cs), Res),U)).

%% fread_chars(Line, Count)

fread_chars(Line, C, U) ->
    fread_chars(C, Line, U, []).

fread_chars(0, Line, _U, Cs) -> {Line,Cs};
fread_chars(_N, [$\n|Line], _U, _Cs) -> {[$\n|Line],error};
fread_chars(N, [C|Line], true, Cs) ->
    fread_chars(N-1, Line, true, [C|Cs]);
fread_chars(N, [C|Line], false, Cs) when C >= 0, C =< 255 ->
    fread_chars(N-1, Line, false, [C|Cs]);
fread_chars(_N, L, _U, _Cs) ->
    {L,error}.
%%fread_chars(_N, [], _U,_Cs) -> 
%%    {[],error}.

%% fread_int_cs(Line, N)

fread_int_cs(Line0, N0) ->
    {Line1,N1} = fread_skip_white(Line0, N0),
    {Line,N,Cs} = fread_sign(Line1, N1, []),
    fread_digits(Line, N, Cs).

%% fread_float_cs(Line, N)
%%  A float is "[+|-][0-9]+.[0-9]+[[E|e][+|-][09-]+]

fread_float_cs(Line0, N0) ->
    {Line1,N1} = fread_skip_white(Line0, N0),
    {Line2,N2,Cs2} = fread_sign(Line1, N1, []),
    {Line,N,Cs} = fread_digits(Line2, N2, Cs2),
    fread_float_cs_1(Line, N, Cs).

fread_float_cs_1([$.|Line0], N0, Cs0) ->
    {Line,N,Cs} = fread_digits(Line0, N0+1, [$.|Cs0]),
    fread_float_cs_2(Line, N, Cs);
fread_float_cs_1(Line, N, Cs) ->
    {Line,N,Cs}.

fread_float_cs_2([$e|Line0], N0, Cs0) ->
    {Line,N,Cs} = fread_sign(Line0, N0+1, [$e|Cs0]),
    fread_digits(Line, N, Cs);
fread_float_cs_2([$E|Line0], N0, Cs0) ->
    {Line,N,Cs} = fread_sign(Line0, N0+1, [$E|Cs0]),
    fread_digits(Line, N, Cs);
fread_float_cs_2(Line, N, Cs) ->
    {Line,N,Cs}.

%% fread_string_cs(Line, N, Unicode)

fread_string_cs(Line0, N0, false) ->
    {Line,N} = fread_skip_white(Line0, N0),
    fread_skip_latin1_nonwhite(Line, N, []);
fread_string_cs(Line0, N0, true) ->
    {Line,N} = fread_skip_white(Line0, N0),
    fread_skip_nonwhite(Line, N, []).

%% fread_skip_white(Line)
%% fread_skip_white(Line, N)
%% fread_skip_nonwhite(Line, N, Characters)
%% fread_sign(Line, N, Characters)
%% fread_digits(Line, N, Characters)
%% fread_digits(Line, N, Base, Characters)
%%  Read segments of things, return "thing" characters in reverse order.

fread_skip_white([$\s|Line]) -> fread_skip_white(Line);
fread_skip_white([$\t|Line]) -> fread_skip_white(Line);
fread_skip_white([$\r|Line]) -> fread_skip_white(Line);
fread_skip_white([$\n|Line]) -> fread_skip_white(Line);
fread_skip_white(Line) -> Line.

fread_skip_white([$\s|Line], N) ->
    fread_skip_white(Line, N+1);
fread_skip_white([$\t|Line], N) ->
    fread_skip_white(Line, N+1);
fread_skip_white([$\r|Line], N) ->
    fread_skip_white(Line, N+1);
fread_skip_white([$\n|Line], N) ->
    fread_skip_white(Line, N+1);
fread_skip_white(Line, N) -> {Line,N}.

fread_skip_latin1_nonwhite([$\s|Line], N, Cs) -> {[$\s|Line],N,Cs};
fread_skip_latin1_nonwhite([$\t|Line], N, Cs) -> {[$\t|Line],N,Cs};
fread_skip_latin1_nonwhite([$\r|Line], N, Cs) -> {[$\r|Line],N,Cs};
fread_skip_latin1_nonwhite([$\n|Line], N, Cs) -> {[$\n|Line],N,Cs};
fread_skip_latin1_nonwhite([C|Line], N, []) when C > 255 ->
    {[C|Line],N,error};
fread_skip_latin1_nonwhite([C|Line], N, Cs) when C > 255 ->
    {[C|Line],N,Cs};
fread_skip_latin1_nonwhite([C|Line], N, Cs) ->
    fread_skip_latin1_nonwhite(Line, N+1, [C|Cs]);
fread_skip_latin1_nonwhite([], N, Cs) -> {[],N,Cs}.

fread_skip_nonwhite([$\s|Line], N, Cs) -> {[$\s|Line],N,Cs};
fread_skip_nonwhite([$\t|Line], N, Cs) -> {[$\t|Line],N,Cs};
fread_skip_nonwhite([$\r|Line], N, Cs) -> {[$\r|Line],N,Cs};
fread_skip_nonwhite([$\n|Line], N, Cs) -> {[$\n|Line],N,Cs};
fread_skip_nonwhite([C|Line], N, Cs) ->
    fread_skip_nonwhite(Line, N+1, [C|Cs]);
fread_skip_nonwhite([], N, Cs) -> {[],N,Cs}.

fread_sign([$+|Line], N, Cs) -> {Line,N+1,[$+|Cs]};
fread_sign([$-|Line], N, Cs) -> {Line,N+1,[$-|Cs]};
fread_sign(Line, N, Cs) -> {Line,N,Cs}.

fread_base(Line0, N0) ->
    {[$#|Line1],N1,Cs1} = fread_int_cs(Line0, N0),
    B = list_to_integer(reverse(Cs1)),
    {Line1,N1+1,B}.

fread_digits([C|Line], N, Cs) when C >= $0, C =< $9 ->
    fread_digits(Line, N+1, [C|Cs]);
fread_digits(Line, N, Cs) -> {Line,N,Cs}.

fread_digits([C|Line], N, Base, Cs) when C >= $0, C =< $9 ->
    fread_digits(Line, N+1, Base, [C|Cs]);
fread_digits([C|Line], N, Base, Cs) when C >= $A, C < $A+Base-10 ->
    fread_digits(Line, N+1, Base, [C|Cs]);
fread_digits([C|Line], N, Base, Cs) when C >= $a, C < $a+Base-10 ->
    fread_digits(Line, N+1, Base, [C|Cs]);
fread_digits(Line, N, _Base, Cs) -> {Line,N,Cs}.



%% fread_result(Suppress, Value, Results)

fread_result(true, _V, Res) -> Res;
fread_result(false, V, Res) -> [V|Res].

-ifdef(UNICODE_AS_BINARIES).
fread_convert([L|R],true) when is_list(L) ->
    [unicode:characters_to_binary(L) | R];
fread_convert(Any,_) ->
    Any.
-else.
fread_convert(Any,_) ->
    Any.
-endif.
fread_error(In) ->
    {error,{fread,In}}.
