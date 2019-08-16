module cx.ast.expressions;

import std.format : format;

import cx.ast.base;
import cx.ast.function_;
import cx.type.base;
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

    override SSAReg encode(FunctionEncodeArgs args)
    {
        return args.fun.literal(this.value);
    }

    override string toString() const { return format!"%s"(value); }
}

class StackFrameExpression : Expression
{
    TypeVar stackframeType;

    this(BaseFunction fun) {
        this.stackframeType = fun.stackframe;
    }

    override TypeSource type()
    {
        return new TypeVarSource(this.stackframeType);
    }

    override SSAReg encode(FunctionEncodeArgs args)
    {
        // assert(false);
        return args.scope_.stackframe;
    }

    override string toString() const { return "_stackframe"; }
}

class Binary : Expression, TypeConstraint
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

    override SSAReg encode(FunctionEncodeArgs args)
    {
        auto leftReg = left.encode(args);
        auto rightReg = right.encode(args);

        final switch (operation)
        {
            case Operation.Add:
                return args.fun.add(leftReg, rightReg);
            case Operation.Sub:
                return args.fun.sub(leftReg, rightReg);
            case Operation.Equal:
                return args.fun.equal(leftReg, rightReg);
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

    override bool resolve(TypeMap typeMap)
    {
        import std.algorithm : any, map;
        import std.range : array;

        if (this.type_ in typeMap) return false;
        if (!left.type.ready(typeMap) || !right.type.ready(typeMap))
        {
            return false;
        }
        assert(left.type.type(typeMap) == Int32.instance);
        assert(right.type.type(typeMap) == Int32.instance);

        typeMap[this.type_] = Int32.instance;
        return true;
    }

    this(Operation operation, Expression left, Expression right, BaseFunction fun)
    {
        this.operation = operation;
        this.left = left;
        this.right = right;
        this.type_ = fun.allocTypeVar;
        fun.constraintList ~= this;
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

    override SSAReg encode(FunctionEncodeArgs args)
    {
        SSAReg[] paramRegs;
        foreach (param; params)
        {
            paramRegs ~= param.encode(args);
        }
        auto funReg = target.encode(args);
        return args.fun.call(funReg, paramRegs);
    }

    this(typeof(this.tupleof) args) { this.tupleof = args; }
}
