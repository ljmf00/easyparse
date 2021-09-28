module easyparse.parser.interfaces;

import std.traits;
import std.meta;

import easyparse.parser.context;

/**
 * Static callable parser interface
 */
interface IStaticParser(T, U)
{
	static ParserContext!T.Result!U opCall(ParserContext!T);
}

/**
 * Callable parser interface
 */
interface IParser(T, U)
{
	ParserContext!T.Result!U opCall(ParserContext!T);
}

/// Check whether is or not valid return type of a parser callable
template isParserReturnType(T) {
	static if(isCallable!T)
		alias Tret = TemplateOf!(ReturnType!T);
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

///
@safe pure nothrow @nogc
unittest
{
	static assert(isParserReturnType!(TextParserContext.Result!string));

	struct Foo {}
	static assert(!isParserReturnType!(Foo));
}

/// Check whether is or not valid parameters of a parser callable
enum isParserParameters(T) = Parameters!(T).length == 1 &&
	__traits(isSame, TemplateOf!(Parameters!T), ParserContext);

/// Check whether is or not a valid parser callable
enum isParserCallable(T) = isCallable!T &&
	isParserParameters!T && isParserReturnType!T;

/// Check whether T is a valid parser interface
enum isParserInterface(alias T) = __traits(isSame, T, IStaticParser)
	|| __traits(isSame, T, IParser)
	|| isInstanceOf!(IStaticParser, T)
	|| isInstanceOf!(IParser, T);

///
@safe pure nothrow @nogc
unittest
{
	static assert(isParserInterface!(IParser!(string, string)));
	static assert(isParserInterface!IParser);
	static assert(isParserInterface!(IStaticParser!(string, string)));
	static assert(isParserInterface!IStaticParser);
}

/**
 * Check whether T is a valid parser struct
 *
 * Params:
 *   T = given struct with the same IParser or IStaticParser interfaces
 */
template isParserStruct(alias T)
{
	static if(isType!T || __traits(compiles, { auto _ = T.init; }))
		enum Ti = T.init;
	else
		alias Ti = T;

	static if(is(typeof(Ti) == struct))
	{
		static if(hasStaticMember!(typeof(Ti), "opCall"))
		{
			alias opCallT = FunctionTypeOf!(typeof(Ti).opCall);
			enum isParserStruct = isParserCallable!(opCallT);
		} else static if(isCallable!T) {
			alias opCallT = FunctionTypeOf!(Ti.opCall);
			enum isParserStruct = Parameters!(T).length == 1
				&& isParserReturnType!opCallT;
		} else
			enum isParserStruct = false;
	} else
		enum isParserStruct = false;
}

///
@safe pure nothrow @nogc
unittest
{
	struct Foo
	{
		void opCall() {}
	}

	static assert(!isParserStruct!Foo);
	static assert(!isParserStruct!(Foo.init));

	struct SFoo
	{
		static void opCall() {}
	}

	static assert(!isParserStruct!SFoo);

	struct Foobar
	{
		TextParserContext.Result!string opCall(TextParserContext p)
		{ return typeof(return).init; }
	}

	static assert(isParserStruct!Foobar);
	static assert(isParserStruct!(Foobar.init));

	struct Bar
	{
		static TextParserContext.Result!string opCall(TextParserContext p)
		{ return typeof(return).init; }
	}

	static assert(isParserStruct!Bar);
	static assert(isParserStruct!(Bar.init));

	struct EmptyFoo {}

	static assert(!isParserStruct!EmptyFoo);
}

enum isParserType(T) = (is(T == class) && anySatisfy!(isParserInterface, BaseTypeTuple!T))
	|| (is(T == interface) && isParserInterface!T)
	|| (is(T == struct) && isParserStruct!T);

enum isStaticParserType(T) = isParserType!T && hasStaticMember!(T, "opCall");

enum isParser(T) = isParserType!T || isParserCallable!T;
