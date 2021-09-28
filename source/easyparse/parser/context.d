module easyparse.parser.context;

import std.traits;
import std.functional;
import std.range;

/**
 * Parser context
 */
struct ParserContext(T)
	if(isRandomAccessRange!T || isArray!T)
{
	this(T content)
	{
		buffer = content;
	}

	ElementType!T front() const
	in(!empty, "Front on empty range")
	{
		return buffer[pos];
	}

	///
	@safe pure nothrow @nogc
	unittest
	{
		assert(TextParserContext("foo").front == 'f');
	}

	alias peek = front;

	void popFront()
	in(!empty)
	{
		++pos;
	}

	///
	@safe pure nothrow @nogc
	unittest
	{
		auto p = TextParserContext("bar");
		p.popFront();
		assert(p.front == 'a');
	}

	alias skip = popFront;

	T opSlice()
	{
		return buffer[pos .. $];
	}

	///
	@safe pure nothrow @nogc
	unittest
	{
		auto p = TextParserContext("bar");
		assert(p[] == "bar");
		p.popFront();
		assert(p[] == "ar");
	}

	size_t length() const @property
	{
		return buffer[pos .. $].length;
	}

	///
	@safe pure nothrow @nogc
	unittest
	{
		auto p = TextParserContext("bar");
		assert(p.length == 3);
		p.popFront();
		assert(p.length == 2);
	}

	@safe pure nothrow @nogc
	unittest
	{
		auto p = TextParserContext("atum");
		auto len = "atum".length;
		assert(p.length == len);
		assert(p.front == 'a');
		p.popFront();
		assert(p.front == 't');
		assert(p.length == len - 1);
	}

	bool empty() const
	{
		return length == 0;
	}

	///
	@safe pure nothrow @nogc
	unittest
	{
		assert(!TextParserContext("bar").empty);
		assert(TextParserContext("").empty);
	}

	void reset()
	{
		pos = 0;
	}

	///
	@safe pure nothrow @nogc
	unittest
	{
		auto p = TextParserContext("bar");
		p.popFront();
		assert(p.front == 'a');
		p.reset();
		assert(p.front == 'b');
	}

	static if(isSomeString!T)
	{
		import std.ascii : isWhite;

		T skipWhite()
		{
			return this.skipAll!isWhite;
		}

		@safe pure nothrow @nogc
		unittest
		{
			auto p = TextParserContext("   foo");
			assert(p.skipWhite == "   ");
			assert(p[] == "foo");
			assert(p.skipWhite == "");
			assert(p[] == "foo");
		}

		T skipUntilWhite(OpenRight or = OpenRight.yes)()
		{
			return this.skipUntil!(isWhite, or);
		}

		@safe pure nothrow @nogc
		unittest
		{
			auto p = TextParserContext("foo");
			assert(p.skipUntilWhite == "foo");

			p = TextParserContext("foo    ");
			assert(p.skipUntilWhite == "foo");
			p.reset();
			assert(p.skipUntilWhite!(OpenRight.no) == "foo ");
		}

		T peakUntilWhite(OpenRight or = OpenRight.yes)()
		{
			return this.peakUntil!(isWhite, or);
		}

		@safe pure nothrow @nogc
		unittest
		{
			auto p = TextParserContext("foo");
			assert(p.peakUntilWhite == "foo");

			p = TextParserContext("foo    ");
			assert(p.peakUntilWhite == "foo");
			assert(p.peakUntilWhite == "foo");
			assert(p.peakUntilWhite!(OpenRight.no) == "foo ");
		}

		auto acceptWhite(T seq)()
		{
			import std.algorithm : splitter;
			import std.array : array;
			import std.range : back;

			static immutable tokens = seq
				.splitter!isWhite
				.array;

			auto startPos = pos;

			static foreach(tok; tokens[0..$-1])
			{
				static if(!tok.empty)
				{
					if(!accept(tok))
						return Result!T(false, this);
				}
				skipWhite();
			}

			static if(!tokens.back.empty)
			{
				auto a = accept(tokens.back);
				return Result!T(a, this, buffer[startPos .. pos]);
			}
			else
				return Result!T(true, this, buffer[startPos .. pos]);
		}
	}

	@safe pure nothrow @nogc
	unittest
	{
		auto p = TextParserContext("    foo");
		p.skipWhite();
		assert(p[] == "foo");
		// there's no changes
		p.skipWhite();
		assert(p[] == "foo");
	}

	@safe pure nothrow @nogc
	unittest
	{
		auto p = TextParserContext("foo bar = foobar");
		assert(p.acceptWhite!"foo bar");
		assert(p[] == " = foobar");
		assert(!p.acceptWhite!"= =");
		p.acceptWhite!" = ";
		assert(!p.acceptWhite!"=");
	}

	auto orAccept(Args...)(Args seqs)
	if(seqs.length > 1 &&
		allSameType!Args &&
		is(Args[0] : T))
	{
		foreach(seq; seqs)
			if(accept(seq))
				return Result!T(true, this, seq);

		return Result!T(false, this);
	}

	@safe pure nothrow @nogc
	unittest
	{
		auto p = TextParserContext("foo");
		auto r = p.orAccept("bar", "foo");
		assert(r);
		assert(r.get == "foo");
		p.reset();
		assert(!p.orAccept("bar", "foobar"));
	}

	auto accept()(T seq)
	{
		foreach(ref c; seq)
		{
			if(!empty && c == front) popFront();
			else return false;
		}

		return true;
	}

	@safe pure nothrow @nogc
	unittest
	{
		assert(TextParserContext("foo").accept("foo"));
		assert(!TextParserContext("foo").accept("bar"));
	}

	auto accept()(ElementType!T c)
	{
		if(!empty && c == front)
		{
			popFront();
			return true;
		}

		return false;
	}

	@safe pure nothrow @nogc
	unittest
	{
		assert(TextParserContext("foo").accept('f'));
		assert(!TextParserContext("foo").accept('b'));
	}

	struct Result(U)
	{
		bool success;
		ParserContext!T context;
		private U node;

		this(bool success, ParserContext!T context, U node = U.init)
		{
			this.success = success;
			this.context = context;
			this.node = node;
		}

		U get()
		in(success, "Getting on an unsuccessful result")
		{
			return node;
		}

		T opCast(T : bool)() const
		{
			return success;
		}

		auto split()
		{
			import std.typecons : tuple;

			return tuple(
				context.buffer[0..context.pos],
				context[]
			);
		}

		@safe pure nothrow @nogc
		unittest
		{
			import std.ascii : isAlpha;
			import std.typecons : tuple;

			auto p = TextParserContext("foo bar");
			.accept!isAlpha(p);
			auto r = TextParserContext.Result!string(false, p);
			assert(r.split() == tuple("foo", " bar"));
		}
	}

	auto fail(U)()
	{
		return Result!U(false, this);
	}

	@safe pure nothrow @nogc
	unittest
	{
		auto p = TextParserContext("foobar");
		auto r = p.fail!string;
		assert(!r);
		assert(r.context == p);
	}

	auto success(U)(U value)
	{
		return Result!U(true, this, value);
	}

	@safe pure nothrow @nogc
	unittest
	{
		auto p = TextParserContext("foobar");
		auto r = p.success("foo");
		assert(r);
		assert(r.context == p);
		assert(r.get == "foo");
	}

	T buffer;
	size_t pos;
}

alias TextParserContext = ParserContext!string;

import std.typecons : Flag;
alias OpenRight = Flag!"openRight";

// Workaround for issue https://issues.dlang.org/show_bug.cgi?id=5710

auto skipUntil(alias pred, OpenRight or = OpenRight.yes, T)(auto ref ParserContext!T context)
{
	import std.functional : unaryFun;
	alias func = unaryFun!pred;

	auto startPos = context.pos;
	while(!context.empty && !func(context.front)) context.popFront();
	static if(!or)
	{
		if(!context.empty) context.popFront();
	}

	return context.buffer[startPos .. context.pos];
}

@safe pure nothrow @nogc
unittest
{
	auto p = TextParserContext("foobar");
	assert(p.skipUntil!"a == 'r'" == "fooba");
	p.reset();
	assert(p.skipUntil!("a == 'r'", OpenRight.no) == "foobar");

	p = TextParserContext("");
	assert(p.skipUntil!"a == ' '" == "");
	assert(p.skipUntil!("a == ' '", OpenRight.no) == "");
}

// Workaround for issue https://issues.dlang.org/show_bug.cgi?id=5710

auto peakUntil(alias pred, OpenRight or = OpenRight.yes, T)(ParserContext!T context)
{
	return skipUntil!(pred, or)(context);
}

// Workaround for issue https://issues.dlang.org/show_bug.cgi?id=5710

auto skipAll(alias pred, T)(auto ref ParserContext!T context)
{
	import std.functional : unaryFun;
	alias func = unaryFun!pred;

	auto startPos = context.pos;
	while(!context.empty && func(context.front)) context.popFront();

	return context.buffer[startPos .. context.pos];
}

@safe pure nothrow @nogc
unittest
{
	import std.ascii : isWhite;

	auto p = TextParserContext("    foo");
	assert(p.skipAll!isWhite == "    ");
	assert(p.skipAll!isWhite == "");
}

// Workaround for issue https://issues.dlang.org/show_bug.cgi?id=5710

auto accept(alias pred, T)(auto ref ParserContext!T context)
if(__traits(isTemplate, pred) ||
		(is(typeof(pred) : string) && __traits(compiles, {alias _ = unaryFun!pred;})) ||
		isFunction!pred)
{
	alias func = unaryFun!pred;
	alias R = typeof(context).Result!T;

	if(context.empty || (!context.empty && !func(context.front)))
		return R(false, context);

	return R(true, context, context.skipAll!(func, T));
}

///
@safe pure nothrow @nogc
unittest
{
	import std.ascii : isDigit;
	auto p = TextParserContext("143523 + 2");
	auto r = accept!isDigit(p);
	assert(r);
	assert(r.get == "143523");

	assert(!accept!isDigit(p));
}
