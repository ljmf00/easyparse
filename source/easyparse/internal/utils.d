module easyparse.internal.utils;

package(easyparse):

import std.traits;

// Converts an unsigned integer to a compile-time string constant.
enum toCtString(ulong n) =
	n.stringof[0 .. $ - "LU".length];

enum isSomeStringT(alias t) =
	isSomeString!(typeof(t));

/**
Detect whether `T` is a callable object, which can be called with the
function call operator `$(LPAREN)...$(RPAREN)`.

Note: This is from phobos due to: https://github.com/dlang/phobos/pull/8161/
 */
template isCallable_(alias callable)
{
    static if (is(typeof(&callable.opCall) == delegate))
        // T is a object which has a member function opCall().
        enum bool isCallable_ = true;
    else static if (is(typeof(&callable.opCall) V : V*) && is(V == function))
        // T is a type which has a static member function opCall().
        enum bool isCallable_ = true;
    else static if (is(typeof(&callable.opCall!())))
    {
        alias TemplateInstanceType = typeof(&callable.opCall!());
        enum bool isCallable_ = isCallable_!TemplateInstanceType;
    }
    else static if (is(typeof(&callable!())))
    {
        alias TemplateInstanceType = typeof(&callable!());
        enum bool isCallable_ = isCallable_!TemplateInstanceType;
    }
    else
    {
        enum bool isCallable_ = isSomeFunction!callable;
    }
}

/***
 * Get the type of the return value from a function,
 * a pointer to function, a delegate, a struct
 * with an opCall, a pointer to a struct with an opCall,
 * or a class with an `opCall`. Please note that $(D_KEYWORD ref)
 * is not part of a type, but the attribute of the function
 * (see template $(LREF functionAttributes)).
 * Note: This is from phobos due to: https://github.com/dlang/phobos/pull/8161/
 */
template ReturnType_(func...)
if (func.length == 1 && isCallable_!func)
{
    static if (is(FunctionTypeOf_!func R == return))
        alias ReturnType_ = R;
    else
        static assert(0, "argument has no return type");
}

/**
Get the function type from a callable object `func`.
Using builtin `typeof` on a property function yields the types of the
property value, not of the property function itself.  Still,
`FunctionTypeOf_` is able to obtain function types of properties.
Note:
Do not confuse function types with function pointer types; function types are
usually used for compile-time reflection purposes.
This is from phobos due to: https://github.com/dlang/phobos/pull/8161/
 */
template FunctionTypeOf_(func...)
if (func.length == 1 && isCallable_!func)
{
    static if (is(typeof(& func[0]) Fsym : Fsym*) && is(Fsym == function) || is(typeof(& func[0]) Fsym == delegate))
    {
        alias FunctionTypeOf_ = Fsym; // HIT: (nested) function symbol
    }
    else static if (is(typeof(& func[0].opCall) Fobj == delegate) || is(typeof(& func[0].opCall!()) Fobj == delegate))
    {
        alias FunctionTypeOf_ = Fobj; // HIT: callable object
    }
    else static if (
            is(typeof(& func[0].opCall) Ftyp : Ftyp*) && is(Ftyp == function) ||
            is(typeof(& func[0].opCall!()) Ftyp : Ftyp*) && is(Ftyp == function)
            )
    {
        alias FunctionTypeOf_ = Ftyp; // HIT: callable type
    }
    else static if (is(func[0] T) || is(typeof(func[0]) T))
    {
        static if (is(T == function))
            alias FunctionTypeOf_ = T;    // HIT: function
        else static if (is(T Fptr : Fptr*) && is(Fptr == function))
            alias FunctionTypeOf_ = Fptr; // HIT: function pointer
        else static if (is(T Fdlg == delegate))
            alias FunctionTypeOf_ = Fdlg; // HIT: delegate
        else
            static assert(0);
    }
    else
        static assert(0);
}
