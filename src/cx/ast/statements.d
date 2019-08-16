module cx.ast.statements;

import std.format;

import cx.ast.base;
import ssa.fun : SSAFunctionBuilder = FunctionBuilder;

class IfStatement : Statement
{
    Expression condition;
    Statement then;
    Statement else_;

    override void encode(FunctionEncodeArgs args)
    {
        auto fun = args.fun;
        auto condReg = condition.encode(args);
        auto thenElseBranch = fun.testBranch(condReg);

        if (else_ !is null)
        {
            auto elseLabel = fun.here;
            else_.encode(args);
            auto endBranch1 = fun.branch;

            auto thenLabel = fun.here;
            then.encode(args);
            auto endBranch2 = fun.branch;

            auto endLabel = fun.here;

            fun.resolveTestBranch(thenElseBranch, thenLabel, elseLabel);
            fun.resolveBranch(endBranch1, endLabel);
            fun.resolveBranch(endBranch2, endLabel);
        }
        else
        {
            auto thenLabel = fun.here;
            then.encode(args);
            auto endBranch = fun.branch;

            auto endLabel = fun.here;
            fun.resolveTestBranch(thenElseBranch, thenLabel, endLabel);
            fun.resolveBranch(endBranch, endLabel);
        }
    }

    override string toString() const
    {
        return format!"if (%s) %s else %s"(condition, then, else_);
    }

    this(typeof(this.tupleof) args) { this.tupleof = args; }
}

class ReturnStatement : Statement
{
    Expression value;

    override void encode(FunctionEncodeArgs args)
    {
        args.fun.return_(value.encode(args));
    }

    this(typeof(this.tupleof) args) { this.tupleof = args; }

    override string toString() const
    {
        return format!"return %s;"(value);
    }
}

class SequenceStatement : Statement
{
    Statement[] statements;

    override void encode(FunctionEncodeArgs args)
    {
        foreach (statement; statements)
        {
            statement.encode(args);
        }
    }

    this(typeof(this.tupleof) args) { this.tupleof = args; }
    override string toString() const
    {
        return format!"{ %(%s, %) }"(statements);
    }
}
