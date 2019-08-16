module ssa.instr;

import ssa.base;

import std.format;
import std.variant;
import util.algebraic;

alias Instr = Algebraic!(
    Binary,
    Branch,
    Call,
    Literal,
    Return,
    Symbol,
    TestBranch,
    Alloca,
    Store,
    Load,
);

alias toString = (Instr instr) => instr.dispatch!(
    (Binary binary) => format!"%s\t= %s %s %s"(binary.target, binary.left, binary.operation, binary.right),
    (Branch branch) => format!"br %s"(branch.dest),
    (Call call) => format!"%s\t= call %s (%(%s, %))"(call.target, call.function_, call.args),
    (Literal literal) => format!"%s\t= %s"(literal.target, literal.value),
    (Return return_) => format!"return %s"(return_.value),
    (Symbol symbol) => format!"%s\t= symbol \"%s\""(symbol.target, symbol.name),
    (TestBranch tbr) => format!"if %s then br %s else br %s"(tbr.condition, tbr.then, tbr.else_),
    (Alloca alloca) => format!"%s\t= alloca(%s)"(alloca.target, alloca.type),
    (Store store) => format!"*%s\t:= %s %s"(store.target, store.type, store.value),
    (Load load) => format!"%s\t= %s *%s"(load.target, load.type, load.value),
);

enum typeIsBlockEnder(T) = is(T == Branch) || is(T == TestBranch) || is(T == Return);

bool isBlockEnder(Instr instr)
{
    return instr.dispatch!(component => typeIsBlockEnder!(typeof(component)));
}

struct Binary
{
    enum Operation
    {
        Add,
        Sub,
        Equal,
    }

    Operation operation;

    Reg left, right;

    Reg target;
}

struct Branch
{
    BlockRef dest;
}

struct TestBranch
{
    Reg condition;

    BlockRef then, else_;
}

struct Return
{
    Reg value;
}

struct Symbol
{
    string name;

    Reg target;
}

struct Alloca
{
    BasicType type;

    Reg target;
}

struct Store
{
    BasicType type;

    Reg value;

    Reg target;
}

struct Load
{
    BasicType type;

    Reg value;

    Reg target;
}

struct Literal
{
    int value;

    Reg target;
}

struct Call
{
    Reg function_;

    Reg[] args;

    Reg target;
}
