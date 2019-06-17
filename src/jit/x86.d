module jit.x86;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;

enum Instr : ubyte
{
    ArithMemReg32 = 0x01,
    Push = 0x50,
    Pop = 0x58,
    Arith = 0x81,
    MovRegMem = 0x89,
    MovMemReg = 0x8b,
    Nop = 0x90,
    MovImmReg = 0xb8, // + register
    RetNear = 0xc3,
    Int3 = 0xcc,
    JumpRel = 0xe9,
    Call = 0xff,
}

enum Reg8 : ubyte
{
    AL = 0,
    CL = 1,
    DL = 2,
    BL = 3,
    AH = 4,
    CH = 5,
    DH = 6,
    BH = 7,
}

enum Reg32 : ubyte
{
    EAX = 0,
    ECX = 1,
    EDX = 2,
    EBX = 3,
    ESP = 4,
    EBP = 5,
    ESI = 6,
    EDI = 7,
}

enum ArithModifier : ubyte
{
    Add = 0x0,
    Or = 0x1,
    AddCarry = 0x2,
    SubBorrow = 0x3,
    And = 0x4,
    Sub = 0x5,
    Xor = 0x6,
    Cmp = 0x7,
}

enum Condition : ubyte
{
    Below = 0x2,
    AboveEqual = 0x3,
    Zero = 0x4,
    Equal = 0x4,
    NonZero = 0x5,
    NonEqual = 0x5,
    BelowEqual = 0x6,
    Above = 0x7,
    Less = 0xc,
    GreaterEqual = 0xd,
    LessEqual = 0xe,
    Greater = 0xf,
}

extern(C) alias CFunction(R, T...) = R function(T);

class Assembler
{
    Appender!(ubyte[]) data;

    struct Offset
    {
        int fromStart;
    }

    struct RelocationOffset
    {
        int fromStart;
    }

    Offset[string] symbols;

    RelocationOffset[][string] symbolRefs;

    @property Offset here()
    {
        return Offset(data.data.length.to!int);
    }

    void enter()
    {
        push(Reg32.EBP);
        mov(Reg32.ESP, Reg32.EBP);
    }

    void leave()
    {
        mov(Reg32.EBP, Reg32.ESP);
        pop(Reg32.EBP);
        ret;
    }

    void push(Reg32 reg)
    {
        data.put(to!ubyte(Instr.Push + reg));
    }

    void pop(Reg32 reg)
    {
        data.put(to!ubyte(Instr.Pop + reg));
    }

    void mov(Reg32 regFrom, Reg32 regTo)
    {
        data.put(Instr.MovMemReg);
        data.put(to!ubyte(0b11_000_000 | (regTo << 3) | (regFrom << 0)));
    }

    void mov(int immediate, Reg32 regTo)
    {
        data.put(to!ubyte(Instr.MovImmReg + regTo));
        data.put(to!ubyte((0x000000ff & immediate) >>  0));
        data.put(to!ubyte((0x0000ff00 & immediate) >>  8));
        data.put(to!ubyte((0x00ff0000 & immediate) >> 16));
        data.put(to!ubyte((0xff000000 & immediate) >> 24));
    }

    void mov(string name, Reg32 regTo)
    {
        data.put(to!ubyte(Instr.MovImmReg + regTo));
        data.put(to!ubyte(0xde));
        data.put(to!ubyte(0xad));
        data.put(to!ubyte(0xbe));
        data.put(to!ubyte(0xef));
        symbolRefs[name] ~= RelocationOffset(data.data.length.to!int - 4);
    }

    /// to = [from]
    void load(Reg32 regFrom, Reg32 regTo)
    {
        data.put(Instr.MovMemReg);
        with (Reg32)
        {
            if ([EAX, EBX, ECX, EDX].canFind(regFrom))
            {
                data.put(to!ubyte(0b00_000_000 | (regTo << 3) | (regFrom << 0)));
            }
            else if ([EBP, ESI, EDI].canFind(regFrom))
            {
                // [to + 0] = from
                data.put(to!ubyte(0b01_000_000 | (regTo << 3) | (regFrom << 0)));
                data.put(to!ubyte(0));
            }
            else
            {
                assert(regFrom == ESP);
                data.put(to!ubyte(0b00_000_100 | (regTo << 3)));
                data.put(to!ubyte(0b00_100_100)); // 0 * 1 + esp
            }
        }
    }

    /// [to] = from
    void store(Reg32 regFrom, Reg32 regTo)
    {
        data.put(Instr.MovRegMem);
        with (Reg32)
        {
            if ([EAX, EBX, ECX, EDX].canFind(regTo))
            {
                data.put(to!ubyte(0b00_000_000 | (regFrom << 3) | (regTo << 0)));
            }
            else if ([EBP, ESI, EDI].canFind(regTo))
            {
                // [to + 0] = from
                data.put(to!ubyte(0b01_000_000 | (regFrom << 3) | (regTo << 0)));
                data.put(to!ubyte(0));
            }
            else
            {
                assert(regTo == ESP);
                data.put(to!ubyte(0b00_000_100 | (regFrom << 3)));
                data.put(to!ubyte(0b00_100_100)); // 0 * 1 + esp
            }
        }
    }

    void set(Condition condition, Reg8 regTo)
    {
        // two-byte command: 0x0f 0x90 = set conditional + condition
        data.put(to!ubyte(0x0f));
        data.put(to!ubyte(0x90 + condition));
        data.put(to!ubyte(0b11_000_000 | (regTo << 0)));
    }

    template arith(ArithModifier modifier)
    {
        void arith(int immediate, Reg32 regTo)
        {
            static if (modifier == ArithModifier.Add)
            {
                if (immediate < 0)
                {
                    return sub(-immediate, regTo);
                }
            }
            else static if (modifier == ArithModifier.Sub)
            {
                if (immediate < 0)
                {
                    return add(-immediate, regTo);
                }
            }
            data.put(Instr.Arith);
            data.put(to!ubyte(0b11_000_000 | (modifier << 3) | regTo));
            data.put(to!ubyte((immediate & 0x000000ff) >>  0));
            data.put(to!ubyte((immediate & 0x0000ff00) >>  8));
            data.put(to!ubyte((immediate & 0x00ff0000) >> 16));
            data.put(to!ubyte((immediate & 0xff000000) >> 24));
        }
        void arith(Reg32 regFrom, Reg32 regTo)
        {
            data.put(to!ubyte(Instr.ArithMemReg32 + (modifier << 3)));
            data.put(to!ubyte(0b11_000_000 | (regFrom << 3) | (regTo << 0)));
        }
    }

    alias add = arith!(ArithModifier.Add);
    alias sub = arith!(ArithModifier.Sub);
    alias xor = arith!(ArithModifier.Xor);
    alias cmp = arith!(ArithModifier.Cmp);

    void imul(Reg32 regFrom, Reg32 regTo)
    {
        // two-byte command: 0x0f 0xaf /r = imul
        data.put(to!ubyte(0x0f));
        data.put(to!ubyte(0xaf));
        data.put(to!ubyte(0b11_000_000 | (regTo << 3) | (regFrom << 0)));
    }

    void ret()
    {
        data.put(Instr.RetNear);
    }

    void dbg()
    {
        data.put(Instr.Int3);
    }

    RelocationOffset jmp()
    {
        data.put(Instr.JumpRel);
        data.put(to!ubyte(0xde));
        data.put(to!ubyte(0xad));
        data.put(to!ubyte(0xbe));
        data.put(to!ubyte(0xef));
        return RelocationOffset(data.data.length.to!int - 4);
    }

    RelocationOffset jmp(Condition condition)
    {
        // two-byte command: 0x0f 0x80 = jump conditional + condition
        data.put(to!ubyte(0x0f));
        data.put(to!ubyte(0x80 + condition));
        data.put(to!ubyte(0xde));
        data.put(to!ubyte(0xad));
        data.put(to!ubyte(0xbe));
        data.put(to!ubyte(0xef));
        return RelocationOffset(data.data.length.to!int - 4);
    }

    void call(Reg32 reg)
    {
        data.put(Instr.Call);
        data.put(to!ubyte(0b11_010_000 | (reg << 0)));
    }

    void resolve(RelocationOffset relo, Offset label)
    {
        int jumpDistance = label.fromStart - (relo.fromStart + 4);

        data.data[relo.fromStart + 0] = (jumpDistance & 0x000000ff) >>  0;
        data.data[relo.fromStart + 1] = (jumpDistance & 0x0000ff00) >>  8;
        data.data[relo.fromStart + 2] = (jumpDistance & 0x00ff0000) >> 16;
        data.data[relo.fromStart + 3] = (jumpDistance & 0xff000000) >> 24;
    }

    void declare(string name)
    {
        enforce(name !in symbols);

        symbols[name] = here;
    }

    void link(ubyte[] data)
    {
        foreach (name, relOffsets; symbolRefs)
        {
            enforce(name in symbols, format!"Undefined reference `%s'"(name));
            auto address = cast(size_t) (data.ptr + symbols[name].fromStart);

            foreach (relo; relOffsets)
            {
                data[relo.fromStart + 0] = (address & 0x000000ff) >>  0;
                data[relo.fromStart + 1] = (address & 0x0000ff00) >>  8;
                data[relo.fromStart + 2] = (address & 0x00ff0000) >> 16;
                data[relo.fromStart + 3] = (address & 0xff000000) >> 24;
            }
        }
    }

    CFunction!(R, P) toFunction(T : R function(P), R, P...)(string name = null)
    in (name is null || name in symbols)
    {
        import core.sys.posix.sys.mman :
            mmap, mprotect,
            MAP_ANON, MAP_PRIVATE,
            PROT_EXEC, PROT_READ, PROT_WRITE;

        auto offset = (name is null) ? 0 : symbols[name].fromStart;
        auto data = this.data.data;
        ubyte* ptr = cast(ubyte*) mmap(null, data.length, PROT_READ | PROT_WRITE,
                                    MAP_PRIVATE | MAP_ANON, -1, 0);

        assert(ptr !is null); // TODO

        auto target = ptr[0 .. data.length];

        target[] = data;
        link(target);
        int err = mprotect(ptr, data.length, PROT_READ | PROT_EXEC);

        assert(err != -1); // TODO
        return cast(CFunction!(R, P)) (ptr + offset);
    }

    void align_()
    {
        while (data.data.length % 4 != 0)
        {
            data.put(to!ubyte(Instr.Nop));
        }
    }
}
