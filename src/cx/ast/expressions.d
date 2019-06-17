module cx.ast.expressions;

import std.format : format;

import cx.ast.base;
import cx.ast.function_;
import cx.type.primitives;
import cx.type.typesource;
import ssa.base : SSAReg = Reg;
import ssa.fun : SSAFunctionBuilder = FunctionBuilder;

class IntLiteral : Expression
{
    int value;

    this(int value) { this.value = value; }

    override TypeSource type()
    {
        return new LiteralTypeSource(Int32.instance);
    }

    override SSAReg encode(SSAFunctionBuilder fun, TypeMap)
    {
        return fun.literal(this.value);
    }

    override string toString() const { return format!"%s"(value); }
}

class Binary : Expression
{
    enum Operation
    {
        Add,
        Sub,
        Equal,
    }

    Operation operation;

    Expression left, right;

    TypeVar type_;

    override TypeSource type()
    {
        return new TypeVarSource(type_);
    }

    override SSAReg encode(SSAFunctionBuilder fun, TypeMap map)
    {
        auto leftReg = left.encode(fun, map);
        auto rightReg = right.encode(fun, map);

        final switch (operation)
        {
            case Operation.Add:
                return fun.add(leftReg, rightReg);
            case Operation.Sub:
                return fun.sub(leftReg, rightReg);
            case Operation.Equal:
                return fun.equal(leftReg, rightReg);
        }
    }

    override string toString() const
    {
        final switch (operation)
        {
            case Operation.Add:
                return format!"(%s + %s) : %s"(left, right, type_);
            case Operation.Sub:
                return format!"(%s - %s) : %s"(left, right, type_);
            case Operation.Equal:
                return format!"(%s == %s) : %s"(left, right, type_);
        }

    }

    this(Operation operation, Expression left, Expression right, Function fun)
    {
        this.operation = operation;
        this.left = left;
        this.right = right;
        this.type_ = fun.allocTypeVar;
        fun.constraintList ~= new OperatorConstraint(this.type_, operation, [left.type, right.type]);
    }
}

class OperatorConstraint : TypeConstraint
{
    TypeVar target;

    Binary.Operation operation;

    TypeSource[] args;

    this(TypeVar target, Binary.Operation operation, TypeSource[] args)
    {
        this.target = target;
        this.operation = operation;
        this.args = args;
    }

    override string toString() const { return format!"[%s := %s(%(%s, %))]"(target, operation, args); }

    override bool resolve(TypeMap typeMap)
    {
        import std.algorithm : any, map;
        import std.range : array;

        if (args.any!(a => !a.ready(typeMap)))
        {
            return false;
        }
        assert(args.map!(a => a.type(typeMap)).array == [Int32.instance, Int32.instance]);

        typeMap[target] = Int32.instance;
        return true;
    }
}

class Call : Expression
{
    Function target;
    Expression[] params;

    override TypeSource type()
    {
        assert(false);
    }

    override string toString() const
    {
        return format!"%s(%(%s, %))"(target.name, params);
    }

    override SSAReg encode(SSAFunctionBuilder fun, TypeMap map)
    {
        SSAReg[] paramRegs;
        foreach (param; params)
        {
            paramRegs ~= param.encode(fun, map);
        }
        auto funReg = target.encode(fun, map);
        return fun.call(funReg, paramRegs);
    }

    this(typeof(this.tupleof) args) { this.tupleof = args; }
}
