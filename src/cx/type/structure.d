module cx.type.structure;

import std.algorithm;
import std.format;
import std.range;

import cx.type.base;

class Struct : Type
{
    Type[] members;
    this(Type[] members) { this.members = members; }
    size_t offset(size_t index) { return members.take(index).fold!((i, a) => i.align_(a.alignment) + a.size)(0); }
    override size_t size() { return members.map!(a => a.size).sum(0); }
    override size_t alignment() { return members.map!(a => a.alignment).maxElement(4); } // TODO
    override string toString() const { return format!"{ %(%s, %) }"(members); }
}

class Union : Type
{
    Type[] members;
    this(Type[] members) { this.members = members; }
    override size_t size() { return members.map!(a => a.size).maxElement; }
    override size_t alignment() { return members.map!(a => a.alignment).maxElement(4); }
    override string toString() const { return format!"{ %(%s | %) }"(members); }
}

size_t align_(size_t offset, size_t alignment)
{
    size_t n = offset + alignment - 1;
    return n - (n % alignment);
}

unittest
{
    assert(align_(0, 4) == 0);
    assert(align_(1, 4) == 4);
    assert(align_(2, 4) == 4);
    assert(align_(3, 4) == 4);
    assert(align_(4, 4) == 4);
    assert(align_(5, 4) == 8);
}
