module cx.ast.base;

import std.exception : enforce;
import std.format : format;
import std.typecons;

import cx.base;
import cx.type.base;
import ssa.base : SSAReg = Reg;
import ssa.fun : SSAFunction = Function, SSAFunctionBuilder = FunctionBuilder;

class ConstraintList
{
    TypeConstraint[] constraints;

    override string toString() const
    {
        import std.algorithm : map;
        import std.range : join;

        return constraints.map!(a => format!"%s"(a)).join("\n");
    }

    TypeConstraint opOpAssign(string op: "~")(TypeConstraint typeConstraint)
    {
        constraints ~= typeConstraint;
        return typeConstraint;
    }
}

class BaseFunction
{
    int num_typevars;

    ConstraintList constraintList;

    TypeVar stackframe;

    TypeVar allocTypeVar()
    {
        return TypeVar(num_typevars ++);
    }
}

struct Scope
{
    BaseFunction fun;
    Namespace namespace;
    SSAReg stackframe;
    int[] stackpath; // type indexes in the stackframe
}

struct FunctionEncodeArgs
{
    SSAFunctionBuilder fun;
    TypeMap map;
    Scope scope_;
}

interface Expression : LanguageObject
{
    TypeSource type();
    SSAReg encode(FunctionEncodeArgs);
    string toString() const;
}

interface LValue : Expression
{
    SSAReg encodeLocation(FunctionEncodeArgs);
}

interface Symbol
{
    SSAFunction encodeSymbol(TypeMap);
}

interface Statement
{
    void encode(FunctionEncodeArgs);
    string toString() const;
}

class Namespace
{
    Namespace parent;

    LanguageObject[string] entries;

    this(Namespace parent)
    {
        this.parent = parent;
    }

    this()
    {
        this.parent = null;
    }

    void add(string name, Expression value)
    {
        enforce(name !in entries, "tried to define duplicate variable");

        entries[name] = value;
    }

    override string toString() const
    {
        if (!parent) return format!"%s"(entries.keys);
        return format!"%s -> %s"(entries.keys, parent);
    }

    LanguageObject lookup(string name)
    {
        if (auto entry = name in entries)
        {
            return *entry;
        }
        if (parent)
        {
            return parent.lookup(name);
        }
        return null;
    }
}
