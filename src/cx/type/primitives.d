module cx.type.primitives;

import cx.base;

class Int32 : Type
{
    override size_t size() { return 4; }
    override size_t alignment() { return 4; }
    override string toString() const { return "int32"; }
    static Int32 instance;
    static this()
    {
        instance = new Int32;
    }
}
