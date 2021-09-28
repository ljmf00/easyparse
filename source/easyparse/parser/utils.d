module easyparse.parser.utils;

import std.traits;
import std.meta;

import easyparse.parser.context;
import easyparse.internal.utils;

auto parseStrings(Strings...)(ParserContext!(typeof(Strings[0])) p)
if(Strings.length > 0 && allSatisfy!(isSomeStringT, Strings))
{
	alias S = typeof(Strings[0]);
	alias R = ParserContext!S.Result!S;

	static if(Strings.length > 1)
		return p.accept(Strings);
	else
		return R(p.accept(Strings), p, Strings);
}

import std.typecons : Flag;
alias OpenRight = Flag!"openRight";

auto parseWhitespaces(OpenRight or = OpenRight.no, T)(ParserContext!T p)
{
	static if(or)
	{
		auto r = p.skipWhite();
		return ParserContext!T.Result!T(true, p, r);
	}
	else
	{
		import std.ascii : isWhite;
		return p.accept!isWhite;
	}
}

auto parseEmpty(T)(ParserContext!T p)
{
	return ParserContext!T.Result!T(true, p);
}
