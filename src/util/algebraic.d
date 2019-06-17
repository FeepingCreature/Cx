module util.algebraic;

import std.format;
import std.meta;
import std.range;
import std.variant;

template dispatch(args...)
{
    auto dispatch(A : VariantN!(size, Types), size_t size, Types...)(ref A algebraic)
    in (algebraic.hasValue)
    {
        enum canCallWith(Type, size_t offset)
            = __traits(compiles, { Type value = Type.init; return args[offset](value); });
        static foreach (Type; Types)
        {
            if (auto ptr = algebraic.peek!Type)
            {
                alias callables = Filter!(ApplyLeft!(canCallWith, Type), aliasSeqOf!(args.length.iota));

                static if (callables.length == 0)
                {
                    static assert(false, "Type `" ~ Type.stringof ~ "' is not handled in dispatch!");
                }
                else static if (callables.length > 1)
                {
                    static assert(false, "Type `" ~ Type.stringof ~ "' is handled multiple times in dispatch!");
                }
                else
                {
                    return args[callables[0]](*ptr);
                }
            }
        }
        assert(false, "logic error: algebraic with value did not contain any component type");
    }
}

unittest
{
    struct Struct1
    {
        int a;
    }

    struct Struct2
    {
        int a;
    }

    alias Foo = Algebraic!(Struct1, Struct2);

    Foo foo = Foo(Struct1(5));

    auto text = foo.dispatch!(
        (Struct1 s1) => format!"Struct1(%s)"(s1.a),
        (Struct2 s2) => format!"Struct2(%s)"(s2.a),
    );
    assert(text == "Struct1(5)");
}
