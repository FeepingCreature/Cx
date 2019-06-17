module cx.ast.function_;

import std.format;

import cx.ast.base;
import ssa.base : SSAReg = Reg;
import ssa.fun : SSAFunctionBuilder = FunctionBuilder;
import cx.type.typesource;

class Function : Symbol, Expression
{
    string name;

    TypeVar ret;

    TypeVar[] args;

    ConstraintList constraintList;

    Statement body_;

    int num_typevars;

    override string toString() const
    {
        return format!"%s(%(%s, %)): %s %s\n%s"(name, args, ret, body_, constraintList);
    }

    override TypeSource type() { assert(false); }

    override SSAReg encode(SSAFunctionBuilder fun, TypeMap map)
    {
        return fun.symbol(this.name);
    }

    override void encodeSymbol(SSAFunctionBuilder fun, TypeMap map)
    {
        body_.encode(fun, map);
    }

    TypeVar allocTypeVar()
    {
        return TypeVar(num_typevars ++);
    }

    this(string name, TypeSource ret, TypeSource[] args)
    {
        this.name = name;
        this.constraintList = new ConstraintList;
        this.num_typevars = 0;
        this.ret = allocTypeVar;
        this.constraintList ~= new SetConstraint(this.ret, ret);
        foreach (arg; args)
        {
            auto argVar = allocTypeVar;
            this.args ~= argVar;
            this.constraintList ~= new SetConstraint(argVar, arg);
        }
    }
}

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

class Argument : Expression
{
    Function function_;

    size_t index;

    override TypeSource type()
    {
        return new TypeVarSource(function_.args[index]);
    }

    override SSAReg encode(SSAFunctionBuilder fun, TypeMap map)
    {
        return fun.arg(index);
    }

    override string toString() const { return format!"@%s"(index); }

    this(typeof(this.tupleof) args) { this.tupleof = args; }
}

struct Scope
{
    Function fun;
    Namespace namespace;
}
