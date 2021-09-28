module easyparse.combinator;

import easyparse.parser.context;
import easyparse.parser.interfaces;
import easyparse.parser.utils;
import easyparse.internal.utils;

import std.traits;
import std.sumtype;
import std.meta;

template isCombinator(T)
{
	enum _isCombinator(U) = isInstanceOf!(Combinator, U)
		|| __traits(isSame, U, Combinator);

	static if(_isCombinator!T)
		enum isCombinator = true;
	else static if(__traits(compiles, __traits(parent, T)))
	{
		alias parent = __traits(parent, T);
		enum isCombinator = _isCombinator!parent;
	} else {
		enum isCombinator = false;
	}
}

template isParserReturnType(T) {
	static if(isCallable!T)
		alias Tret = TemplateOf!(ReturnType_!T);
	else
		alias Tret = TemplateOf!T;

	static if(__traits(compiles, __traits(parent, Tret)))
	{
		alias parent = __traits(parent, Tret);
		enum isParserReturnType = __traits(isSame, TemplateOf!parent, ParserContext)
			&& __traits(isSame, Tret, parent.Result);
	} else
		enum isParserReturnType = false;
}

private alias FilterCombinatorArgs(T...) =
	Filter!(templateNot!(isStaticParserType), T);

struct Combinator(Types...)
if(
	allSatisfy!(templateOr!(isParser, isCombinator), Types)/* &&
	allSameType!(staticMap!(Parameters, Types))*/)
{
	private alias CombinatorT = typeof(this);
	private alias Result(T) = ReturnType_!(T);

	static if(Types.length > 0)
		private alias ParserContextT = Parameters!(Types[0])[0];
	else
		private alias ParserContextT = ParserContext!(void[]);

	import std.typecons : Tuple;
	private alias DefaultResultT = ParserContextT.Result!(Tuple!());

	private static immutable enumerateParsers = ()
		{
			ulong m, a;
			ulong[] ret;
			static foreach(T; Types)
			{
				static if(isStaticParserType!T)
					ret ~= a++;
				else
					ret ~= m++;
			}

			return ret;
		}();

	static foreach (i, T; Types)
	{
		static if(isStaticParserType!T)
			mixin("private alias a_Parser", toCtString!(enumerateParsers[i]), " = T;");
		else
			mixin("private T m_Parser", toCtString!(enumerateParsers[i]), ";");
	}

	static if(FilterCombinatorArgs!(Types).length > 0)
	{
		this(FilterCombinatorArgs!Types t)
		{
			static foreach (i, T; FilterCombinatorArgs!Types)
			{
				mixin("this.m_Parser", toCtString!i, " = t[", toCtString!i, "];");
			}
		}
	}

	static if(Types.length > 0 && anySatisfy!(isStaticParserType, Types))
	{
		this(Types t)
		{
			static foreach (i, T; Types)
			{
				static if(!isStaticParserType!T)
					mixin("this.m_Parser", toCtString!(enumerateParsers[i]),
						" = t[", toCtString!(enumerateParsers[i]), "];");
			}
		}
	}

	struct Then
	{
		auto this(CombinatorT combinator)
		{
			this.combinator = combinator;
		}

		static if(Types.length == 0)
		{
			auto opCall()(ParserContextT p) { return DefaultResultT(true, p); }
		}
		else
		{
			auto opCall()(ParserContextT p)
			if(allSameType!(staticMap!(ReturnType_, Types)))
			{
				Result!(Types[0]) r;
				static foreach (i, T; Types)
				{
					mixin("r = combinator.",
						isStaticParserType!T ? "a_Parser" : "m_Parser",
						toCtString!(enumerateParsers[i]), "(p);");

					if(!r) return r;
					p = r.context;
				}

				return r;
			}

			auto opCall()(ParserContextT p)
			if(!allSameType!(staticMap!(ReturnType_, Types)))
			{
				// returned result
				Result!(Types[$ - 1]) ret;

				static foreach (i, T; Types[0..$ - 1])
				{
					{
						// parser `i` result
						mixin("auto r = combinator.",
							isStaticParserType!T ? "a_Parser" : "m_Parser",
							toCtString!(enumerateParsers[i]), "(p);");

						// return current parser result if failed to parse
						if(!r) {
							ret.context = r.context;
							return ret;
						}
						p = r.context;
					}
				}

				// return last parser result
				return mixin("combinator.",
					isStaticParserType!(Types[$ - 1]) ? "a_Parser" : "m_Parser",
					toCtString!(enumerateParsers[Types.length - 1UL]), "(p);");
			}
		}

		CombinatorT combinator;

		alias combinator this;
	}

	auto then() { return Then(this); }
	auto then(T...)(T t) { return Then(this)(t); }

	auto opCall(ParserContextT p)
	{
		static if(Types.length == 0)
			return DefaultResultT(true, p);
		else
			//FIXME: default for then for now
			return this.then(p);
	}
}

auto combine(CA...)(CA combinatorArgs)
{
	return Combinator!CA(combinatorArgs);
}

auto combine(CA...)()
if(CA.length > 0)
{
	return Combinator!CA();
}

auto combine()()
{
	return Combinator!().init;
}

@safe pure nothrow @nogc
unittest
{
	combine(&parseStrings!"foo");
	combine(&parseStrings!"foo", &parseStrings!"bar");
	combine(&parseStrings!"foo", combine(&parseStrings!"foo"));
	combine(&parseStrings!"foo", combine(&parseStrings!"foo").then);
}

@safe pure nothrow @nogc
unittest
{
	struct Foo {
		static auto opCall(TextParserContext p)
		{
			return parseStrings!"foo"(p);
		}
	}
	//combine(&parseStrings!"foo", Foo.init);

	struct Bar {
		static auto opCall(TextParserContext p)
		{
			return TextParserContext.Result!bool.init;
		}
	}
	//combine(&parseStrings!"foo", Bar.init);
	//cast(void)combine;
	//cast(void)combine!Foo;
}

// 	private template mapCombinator(alias combinator, string additional = "")
// 	{
// 		import std.string : startsWith;
// 		enum isMember(string p) = p.startsWith("m_");
// 		enum thisCommaArg(string a) = a ~ ",";
// 		enum combinatorCommaArg(string a) = combinator.stringof ~ "." ~ a ~ ",";

// 		alias thisMap = staticMap!(
// 			thisCommaArg,
// 			Filter!(isMember, __traits(allMembers, typeof(this)))
// 		);

// 		static if(isInstanceOf!(TemplateOf!(Combinator), typeof(combinator)))
// 		{
// 			alias ret = staticMap!(
// 				combinatorCommaArg,
// 				Filter!(isMember, __traits(allMembers, typeof(combinator)))
// 			);
// 		} else static if(isCallable!(typeof(combinator))) {
// 			alias ret = AliasSeq!(
// 				combinator.stringof
// 			);
// 		} else {
// 			alias ret = AliasSeq!(
// 				combinator
// 			);
// 		}

// 		enum mapCombinator = AliasSeq!(
// 			thisMap,
// 			additional.length > 0 ? additional ~ "," : "",
// 			ret
// 		);
// 	}

// 	auto opBinary(string op : ">>", T)(T t)
// 		if(isInstanceOf!(TemplateOf!(Combinator), T) || (!isSomeString!T && isCallable!T))
// 	{
// 		mixin("return combine(",
// 			mapCombinator!(t),
// 			").then;"
// 		);
// 	}

// 	static if(isSomeString!(TemplateArgsOf!ParserT))
// 	{
// 		auto opBinary(string op : ">>", T)(T t)
// 		if(isSomeString!T)
// 		{
// 			scope auto dg = &parseStrings!(t);
// 			mixin("return combine(",
// 				mapCombinator!("dg"),
// 				").then;"
// 			);
// 		}

// 		auto opBinary(string op : ">>>", T)(T t)
// 			if(isInstanceOf!(TemplateOf!(Combinator), T) || (!isSomeString!T && isCallable!T))
// 		{
// 			alias S = TemplateArgsOf!ParserT;
// 			mixin("return combine(",
// 				mapCombinator!(t, "&parseWhitespaces!(OpenRight.yes, S)"),
// 				").then;"
// 			);
// 		}

// 		auto opBinary(string op : ">>>", T)(T t)
// 			if(isSomeString!T)
// 		{
// 			alias S = TemplateArgsOf!ParserT;
// 			mixin("return combine(",
// 				mapCombinator!("&parseStrings!(t)", "&parseWhitespaces!(OpenRight.yes, S)"),
// 				").then;"
// 			);
// 		}
// 	}

// // @safe pure nothrow @nogc
// // unittest {
// // 	struct Foo {
// // 		string value;
// // 	}

// // 	struct Bar {
// // 		string value;
// // 	}

// // 	TextParserContext.Result!Foo parseFoo(TextParserContext p)
// // 	{
// // 		return typeof(return)(p.accept("foo"), p, Foo("foo"));
// // 	}

// // 	TextParserContext.Result!Bar parseBar(TextParserContext p)
// // 	{
// // 		return typeof(return)(p.accept("bar"), p, Bar("bar"));
// // 	}

// // 	auto p = TextParserContext("foofoo");
// // 	assert(combine(&parseFoo, &parseFoo).then(p));
// // 	assert((combine(&parseFoo) >> &parseFoo)(p));

// // 	p = TextParserContext("foobar");
// // 	assert(combine(&parseFoo, &parseBar).then(p));
// // 	assert((combine(&parseFoo) >> &parseBar)(p));
// // 	assert(!combine(&parseFoo, &parseFoo).then(p));
// // 	assert(!(combine(&parseFoo) >> &parseFoo)(p));
// // }

// auto combine(Strings...)()
// if(Strings.length > 0 &&
// 	!isType!(Strings[0]) &&
// 	allSatisfy!(isSomeStringT, Strings))
// {
// 	return combine(&parseStrings!(Strings));
// }

// auto combine(P)()
// if(__traits(isSame, TemplateOf!P, Parser))
// {
// 	alias S = TemplateArgsOf!P;
// 	return combine(&parseEmpty!S);
// }

// auto combine(T)()
// {
// 	return combine(&parseEmpty!T);
// }

// @safe pure nothrow @nogc
// unittest
// {
// 	auto p = TextParserContext("foobar");
// 	assert(combine!("foo", "bar").then(p));
// }

// // @safe pure nothrow @nogc
// // unittest
// // {
// // 	auto p = TextParserContext("foo bar");
// // 	assert((combine!string >> "foo" >>> "bar")(p));
// // 	// assert((combine!string >>> "foo" >>> "bar").then(p));
// // 	// assert((combine!("foo") >>> combine!("bar")).then(p));
// // 	// assert((combine!("foo") >>> "bar").then(p));
// // }
