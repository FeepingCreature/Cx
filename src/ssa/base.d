module ssa.base;

import std.format;

struct BasicType
{
    import core.bitop : popcnt;

    size_t size;

    size_t alignment;
    invariant(this == BasicType.init || this.alignment.popcnt == 1);

    @property size_t aligned_size() const
    {
        return ((this.size - 1) | (this.alignment - 1)) + 1;
    }

    enum type(T) = BasicType(T.sizeof, T.alignof);
}

unittest
{
    assert(BasicType(4, 4).aligned_size == 4);
    assert(BasicType(5, 4).aligned_size == 8);
    assert(BasicType(6, 4).aligned_size == 8);
    assert(BasicType(7, 4).aligned_size == 8);
    assert(BasicType(8, 4).aligned_size == 8);
    assert(BasicType(9, 4).aligned_size == 12);
}

struct Reg
{
    size_t index;

    string toString() const { return format!"_%s"(index); }
}

struct BlockRef
{
    size_t index;

    string toString() const { return format!"block%s:"(index); }

    enum invalid = BlockRef(-1);

    @property bool valid() { return this != invalid; }
}

/// instruction with information that must be resolved at a later date, such as forward branches
struct InstrRel
{
    size_t block;

    size_t instr;
}
