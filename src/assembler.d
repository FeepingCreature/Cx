module assembler;

import backend.x86;
import cx.ast.function_;
import cx.ast.parse;
import cx.type.inference;
import jit.x86 : Condition, Reg8, Reg32, X86Assembler = Assembler;
import ssa.base : SSABasicType = BasicType;
import ssa.fun : SSAFunctionBuilder = FunctionBuilder;
import ssa.instr;
import std.algorithm;
import std.exception;
import std.range;
import std.string;
import std.stdio;
import std.typecons;
import std.uni;
import util.algebraic;
import util.parser;

void acktest()
{
    string source = "
    int ack(int a, int b)
    {
        if (a == 0) { return b + 1; }
        if (b == 0) { return ack(a - 1, 1); }
        return ack(a - 1, ack(a, b - 1));
    }";
    auto parser = new Parser(source);
    Function ack_tree;
    {
        auto _ = parser.begin;
        ack_tree = parseFunction(parser);
        if (!ack_tree)
        {
            parser.error;
        }
        parser.succeed;
        parser.done;
    }

    auto ack_ssa =
    {
        writefln!"debug: %s"(ack_tree);
        auto instance = resolve_types(ack_tree);
        auto builder = new SSAFunctionBuilder(
            "ack",
            SSABasicType.type!int,
            [SSABasicType.type!int, SSABasicType.type!int]);

        ack_tree.encodeSymbol(builder, instance.types);
        return builder.value;
    }();

    writefln!"%s"(ack_ssa);

    auto ack =
    {
        import std.digest : toHexString;

        auto assembler = new X86Assembler;

        compile(assembler, ack_ssa);

        writefln!"x86: %s"(assembler.data.data.toHexString);
        return assembler.toFunction!(int function(int, int))("ack");
    }();
    for (int i = 0; i < 10; i++)
    {
        writefln!" ack(3, 8) = %s"(ack(3, 8));
    }
}

void main()
{
    auto dbl =
    {
        with (new X86Assembler)
        {
            enter;
            mov(Reg32.EBP, Reg32.EAX);
            add(8, Reg32.EAX); // skip ebp, eip
            load(Reg32.EAX, Reg32.ECX);
            load(Reg32.EAX, Reg32.EDX);
            add(Reg32.ECX, Reg32.EDX);
            mov(Reg32.EDX, Reg32.EAX);
            mov(Reg32.EBP, Reg32.EDX);
            add(8, Reg32.EDX); // skip ebp, eip
            store(Reg32.EAX, Reg32.EDX);
            leave;
            return toFunction!(int function(int));
        }
    }();
    auto test4 =
    {
        with (new X86Assembler)
        {
            enter;
            mov(Reg32.EBP, Reg32.EAX);
            add(8, Reg32.EAX); // skip ebp, eip
            load(Reg32.EAX, Reg32.ECX);
            xor(Reg32.EDX, Reg32.EDX);
            cmp(4, Reg32.ECX);
            set(Condition.Equal, Reg8.DL);
            mov(Reg32.EDX, Reg32.EAX);
            leave;
            return toFunction!(int function(int));
        }
    }();
    auto twoBlocks =
    {
        with (new X86Assembler)
        {
            enter;
            auto jump1 = jmp;
            dbg;
            auto label1 = here;
            resolve(jump1, label1);
            leave;
            return toFunction!(void function());
        }
    }();
    auto ifElse =
    {
        with (new X86Assembler)
        {
            enter;
            mov(Reg32.EBP, Reg32.EAX);
            add(8, Reg32.EAX); // skip ebp, eip
            load(Reg32.EAX, Reg32.ECX);
            xor(Reg32.EDX, Reg32.EDX);
            cmp(4, Reg32.ECX);
            set(Condition.Equal, Reg8.DL);

            cmp(1, Reg32.EDX);
            auto jump1 = jmp(Condition.Equal);
            mov(2, Reg32.EAX);
            auto jump2 = jmp;
            resolve(jump1, here);
            mov(3, Reg32.EAX);
            resolve(jump2, here);
            leave;
            return toFunction!(int function(int));
        }
    }();
    auto factorial =
    {
        with (new X86Assembler)
        {
            align_;
            declare("factorial");
            enter;
            mov(Reg32.EBP, Reg32.EAX);
            sub(4, Reg32.ESP); // scratch space
            add(8, Reg32.EAX); // skip ebp, eip
            load(Reg32.EAX, Reg32.ECX);
            xor(Reg32.EDX, Reg32.EDX);
            cmp(1, Reg32.ECX);
            set(Condition.Equal, Reg8.DL);

            cmp(1, Reg32.EDX);
            auto jump1 = jmp(Condition.Equal);
            store(Reg32.ECX, Reg32.ESP);
            sub(1, Reg32.ECX);
            // call sequence
            sub(4, Reg32.ESP);
            store(Reg32.ECX, Reg32.ESP);
            mov("factorial", Reg32.EAX);
            call(Reg32.EAX);
            add(4, Reg32.ESP);

            mov(Reg32.EAX, Reg32.ECX);
            load(Reg32.ESP, Reg32.EAX);
            imul(Reg32.ECX, Reg32.EAX);
            leave;
            align_;
            resolve(jump1, here);
            mov(1, Reg32.EAX);
            leave;
            return toFunction!(int function(int));
        }
    }();
    auto ack =
    {
        /*
        int ack(int a, int b)
        {
            if (a == 0) { return b + 1; }
            if (b == 0) { return ack(a - 1, 1); }
            return ack(a - 1, ack(a, b - 1));
        }*/
        // b
        // a
        // eip
        // esp
        with (new X86Assembler)
        {
            align_;
            declare("ack");
            enter;
            sub(0x54, Reg32.ESP); // scratch space

            // a == 0
            mov(Reg32.EBP, Reg32.EAX);
            add(8, Reg32.EAX);
            load(Reg32.EAX, Reg32.ECX);
            xor(Reg32.EDX, Reg32.EDX);
            cmp(0, Reg32.ECX);
            set(Condition.Equal, Reg8.DL);

            // if
            cmp(0, Reg32.EDX);
            auto jump1 = jmp(Condition.Equal);
            // return b + 1
            mov(Reg32.EBP, Reg32.EAX);
            add(12, Reg32.EAX);
            load(Reg32.EAX, Reg32.ECX);
            add(1, Reg32.ECX);
            mov(Reg32.ECX, Reg32.EAX);
            leave;

            align_;
            resolve(jump1, here);

            // b == 0
            mov(Reg32.EBP, Reg32.EAX);
            add(12, Reg32.EAX);
            load(Reg32.EAX, Reg32.ECX);
            xor(Reg32.EDX, Reg32.EDX);
            cmp(0, Reg32.ECX);
            set(Condition.Equal, Reg8.DL);

            // if
            cmp(0, Reg32.EDX);
            auto jump2 = jmp(Condition.Equal);
            // return ack(a - 1, 1)
            sub(8, Reg32.ESP);
            mov(Reg32.ESP, Reg32.EAX);
            add(4, Reg32.EAX);
            mov(1, Reg32.ECX);
            store(Reg32.ECX, Reg32.EAX);
            // a - 1
            mov(Reg32.EBP, Reg32.EAX);
            add(8, Reg32.EAX);
            load(Reg32.EAX, Reg32.ECX);
            sub(1, Reg32.ECX);
            store(Reg32.ECX, Reg32.ESP);
            mov("ack", Reg32.EAX);
            call(Reg32.EAX);
            add(8, Reg32.ESP);
            leave;

            align_;
            resolve(jump2, here);
            // return ack(a - 1, ack(a, b - 1));
            // ack(a, b - 1)
            sub(8, Reg32.ESP);
            // b - 1
            mov(Reg32.EBP, Reg32.EAX);
            add(12, Reg32.EAX);
            load(Reg32.EAX, Reg32.ECX);
            sub(1, Reg32.ECX);
            mov(Reg32.ESP, Reg32.EAX);
            add(4, Reg32.EAX);
            store(Reg32.ECX, Reg32.EAX);
            // a
            mov(Reg32.EBP, Reg32.EAX);
            add(8, Reg32.EAX);
            load(Reg32.EAX, Reg32.ECX);
            store(Reg32.ECX, Reg32.ESP);
            // ack(...)
            mov("ack", Reg32.EAX);
            call(Reg32.EAX);
            add(8, Reg32.ESP);

            // return ack(a - 1, ...)
            sub(8, Reg32.ESP);
            mov(Reg32.ESP, Reg32.ECX);
            add(4, Reg32.ECX);
            store(Reg32.EAX, Reg32.ECX);
            // a - 1
            mov(Reg32.EBP, Reg32.EAX);
            add(8, Reg32.EAX);
            load(Reg32.EAX, Reg32.ECX);
            sub(1, Reg32.ECX);
            store(Reg32.ECX, Reg32.ESP);
            // return ack(...)
            mov("ack", Reg32.EAX);
            call(Reg32.EAX);

            leave;
            return toFunction!(int function(int, int));
        }
    }();
    // asm { int 3; }
    int four = dbl(2);
    writefln!" => %s"(four);
    writefln!" => %s"(iota(8).map!(a => tuple(a, test4(a))).array);
    twoBlocks();
    writefln!" => %s"(iota(8).map!(a => tuple(a, ifElse(a))).array);
    writefln!" => %s"(iota(1, 8).map!(a => tuple(a, factorial(a))).array);
    /*
    for (int i = 0; i < 10; i++)
    {
        writefln!" ack(3, 8) = %s"(ack(3, 8));
    }
    */
    acktest;
}
