module ssa.fun;

import ssa.base;
import ssa.instr;
import std.algorithm;
import std.format;
import std.range;
import util.algebraic;

struct Block
{
    Instr[] instrs;
    invariant(!instrs.empty && instrs.back.isBlockEnder && instrs.dropBackOne.none!isBlockEnder);
}

class Function
{
    string name;

    const BasicType[] args;

    BasicType ret;

    const BasicType[] variables;

    const Block[] blocks;

    this(string name, const BasicType[] args, BasicType ret, const BasicType[] variables, const Block[] blocks)
    {
        this.name = name;
        this.args = args;
        this.ret = ret;
        this.variables = variables;
        this.blocks = blocks;
    }

    override string toString()
    {
        string toString(size_t index, const Block block)
        {
            return format!"  block%s:\n"(index) ~ block.instrs.map!(i => "    " ~ .toString(i)).join("\n");
        }
        return format!"%s(%(%s, %):\n"(name, args) ~ blocks.enumerate.map!(b => toString(b.index, b.value)).join("\n");
    }
}

class FunctionBuilder
{
    string name;

    const BasicType[] args;

    const BasicType ret;

    BasicType[] variables;

    Block[] blocks;

    Instr[] instrs;

    Reg stackframe;

    this(string name, const BasicType ret, const BasicType[] args, const BasicType stackframeType)
    {
        this.name = name;
        this.ret = ret;
        this.args = args;
        this.variables = this.args.dup;
        this.stackframe = alloca(stackframeType);
    }

    Reg alloc(BasicType type)
    {
        variables ~= type;

        return Reg(variables.length - 1);
    }

    Reg alloca(BasicType type)
    {
        // TODO void*
        auto target = alloc(BasicType.type!int);

        instrs ~= Instr(Alloca(type, target));
        return target;
    }

    @property BlockRef here()
    in (instrs.empty) // can only jump to start of block
    {
        return BlockRef(blocks.length);
    }

    Reg binary(Binary.Operation operation, Reg left, Reg right)
    in (left.index < variables.length)
    in (right.index < variables.length)
    in (instrs.none!isBlockEnder)
    {
        auto target = alloc(BasicType.type!int);

        instrs ~= Instr(Binary(operation, left, right, target));
        return target;
    }

    auto equal(Reg left, Reg right)
    {
        return binary(Binary.Operation.Equal, left, right);
    }

    auto add(Reg left, Reg right)
    {
        return binary(Binary.Operation.Add, left, right);
    }

    auto sub(Reg left, Reg right)
    {
        return binary(Binary.Operation.Sub, left, right);
    }

    Reg arg(size_t offset)
    in (offset < args.length)
    {
        return Reg(offset);
    }

    // value is a value, target is a pointer
    void store(BasicType type, Reg value, Reg target)
    {
        instrs ~= Instr(Store(type, value, target));
    }

    // value is a value, target is a pointer
    Reg load(BasicType type, Reg value)
    {
        auto target = alloc(type);

        instrs ~= Instr(Load(type, value, target));
        return target;
    }

    void endBlock()
    in (!instrs.empty && instrs.back.isBlockEnder)
    {
        blocks ~= Block(instrs);
        instrs = null;
    }

    InstrRel branch()
    in (instrs.none!isBlockEnder)
    {
        auto result = InstrRel(blocks.length, instrs.length);

        instrs ~= Instr(Branch(BlockRef.invalid));
        endBlock;

        return result;
    }

    Reg call(Reg function_, Reg[] args)
    in (args.all!(arg => arg.index < variables.length))
    in (instrs.none!isBlockEnder)
    {
        // TODO non-int function type
        auto target = alloc(BasicType.type!int);

        instrs ~= Instr(Call(function_, args.dup, target));
        return target;
    }

    void return_(Reg reg)
    in (instrs.none!isBlockEnder)
    {
        instrs ~= Instr(Return(reg));
        endBlock;
    }

    Reg symbol(string name)
    {
        // TODO non-int symbols
        auto target = alloc(BasicType.type!int);

        instrs ~= Instr(Symbol(name, target));
        return target;
    }

    Reg literal(int value)
    {
        auto target = alloc(BasicType.type!int);

        instrs ~= Instr(Literal(value, target));
        return target;
    }

    InstrRel testBranch(Reg condition)
    in (instrs.none!isBlockEnder)
    {
        auto result = InstrRel(blocks.length, instrs.length);

        instrs ~= Instr(TestBranch(condition, BlockRef.invalid, BlockRef.invalid));
        endBlock;

        return result;
    }

    void resolveBranch(InstrRel rel, BlockRef dest)
    in (rel.block < blocks.length)
    in (rel.instr < blocks[rel.block].instrs.length)
    {
        void updateBranch(T)(ref T branch)
        {
            static if (is(T == Branch))
            {
                branch.dest = dest;
            }
            else
            {
                assert(false, "wrong instruction to resolve");
            }
        }
        blocks[rel.block].instrs[rel.instr].dispatch!((ref a) => updateBranch(a));
    }

    void resolveTestBranch(InstrRel rel, BlockRef then, BlockRef else_)
    in (rel.block < blocks.length)
    in (rel.instr < blocks[rel.block].instrs.length)
    {
        void updateBranches(T)(ref T branch)
        {
            static if (is(T == TestBranch))
            {
                branch.then = then;
                branch.else_ = else_;
            }
            else
            {
                assert(false, "wrong instruction to resolve");
            }
        }
        blocks[rel.block].instrs[rel.instr].dispatch!((ref a) => updateBranches(a));
    }

    Function value()
    in (instrs.empty)
    {
        return new Function(name, args, ret, variables, blocks);
    }
}

class Scope
{
    Function function_;

    Scope* parent;
    Reg[Object] vars;

    Reg get(Object key)
    {
        if (key in vars) return vars[key];
        if (parent) return parent.get(key);
        assert(false);
    }

    bool opIn_r(Object key)
    {
        return key in vars || parent && key in *parent;
    }

    void set(Object key, Reg value)
    in (key !in this)
    {
        vars[key] = value;
    }
}

alias none(alias pred) = value => !value.any!pred;
