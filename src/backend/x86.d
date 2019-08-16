module backend.x86;

import jit.x86 : Condition, Reg8, Reg32, X86Assembler = Assembler;
import ssa.base;
import ssa.fun : SSAFunction = Function;
import ssa.instr;
import util.algebraic;

void compile(X86Assembler assembler, SSAFunction function_)
{
    with (assembler)
    {
        int[] ebp_offsets;

        int[] stack_offsets;
        int offset = 0;
        foreach_reverse (arg; function_.args)
        {
            offset += arg.aligned_size; // grow down
            stack_offsets ~= offset;
        }

        offset += 8; // eip, ebp
        foreach_reverse (argOffset; stack_offsets)
        {
            ebp_offsets ~= offset - argOffset;
        }

        offset = 0;
        foreach (arg; function_.variables)
        {
            offset -= arg.aligned_size; // grow down
            ebp_offsets ~= offset;
        }

        align_;
        declare(function_.name);
        enter;
        sub(-offset, Reg32.ESP); // scratch space

        RelocationOffset[][BlockRef] jumps;
        Offset[] blkOffsets;

        foreach (block; function_.blocks)
        {
            align_;
            blkOffsets ~= here;
            foreach (instr; block.instrs)
            {
                with (Reg32)
                {
                    instr.dispatch!(
                        (Binary binary)
                        {
                            auto offs_l = ebp_offsets[binary.left.index];
                            auto offs_r = ebp_offsets[binary.right.index];
                            auto offs_t = ebp_offsets[binary.target.index];

                            mov(EBP, EAX);
                            add(offs_r, EAX);
                            load(EAX, EAX);
                            mov(EBP, ECX);
                            add(offs_l, ECX);
                            load(ECX, ECX);
                            final switch (binary.operation)
                            {
                                case Binary.Operation.Add:
                                    add(EAX, ECX);
                                    break;
                                case Binary.Operation.Sub:
                                    sub(EAX, ECX);
                                    break;
                                case Binary.Operation.Equal:
                                    xor(EDX, EDX);
                                    cmp(EAX, ECX);
                                    set(Condition.Equal, Reg8.DL);
                                    mov(Reg32.EDX, Reg32.ECX);
                                    break;
                            }
                            mov(EBP, EDX);
                            add(offs_t, EDX);
                            store(ECX, EDX);
                        },
                        (Branch branch)
                        {
                            assert (branch.dest.valid);
                            auto relo = jmp;
                            jumps[branch.dest] ~= relo;
                        },
                        (const Call call_)
                        {
                            int[] offsets;
                            int offset = 0;
                            foreach_reverse (arg; call_.args)
                            {
                                auto type = function_.variables[arg.index];
                                offsets ~= offset;
                                offset += type.aligned_size;
                                assert(type.aligned_size == 4);
                            }
                            sub(offset, ESP);
                            foreach (i, arg; call_.args)
                            {
                                mov(ESP, EAX);
                                add(offsets[i], EAX);
                                mov(EBP, ECX);
                                add(ebp_offsets[arg.index], ECX);
                                load(ECX, EDX);
                                store(EDX, EAX);
                            }
                            mov(EBP, EAX);
                            add(ebp_offsets[call_.function_.index], EAX);
                            load(EAX, EAX);
                            call(EAX);
                            add(offset, ESP);
                            mov(EBP, ECX);
                            add(ebp_offsets[call_.target.index], ECX);
                            store(EAX, ECX);
                        },
                        (Literal literal)
                        {
                            mov(EBP, EAX);
                            add(ebp_offsets[literal.target.index], EAX);
                            mov(literal.value, ECX);
                            store(ECX, EAX);
                        },
                        (Return return_)
                        {
                            mov(EBP, EAX);
                            add(ebp_offsets[return_.value.index], EAX);
                            load(EAX, EAX);
                            leave;
                        },
                        (Symbol symbol)
                        {
                            mov(EBP, EAX);
                            add(ebp_offsets[symbol.target.index], EAX);
                            mov(symbol.name, ECX);
                            store(ECX, EAX);
                        },
                        (TestBranch tbr)
                        {
                            assert (tbr.then.valid);
                            assert (tbr.else_.valid);
                            mov(EBP, EAX);
                            add(ebp_offsets[tbr.condition.index], EAX);
                            load(EAX, ECX);
                            cmp(1, ECX);
                            jumps[tbr.then] ~= jmp(Condition.Equal);
                            jumps[tbr.else_] ~= jmp;
                        },
                        (Alloca alloca)
                        {
                            sub(alloca.type.aligned_size, ESP);
                            mov(EBP, EAX);
                            add(ebp_offsets[alloca.target.index], EAX);
                            store(ESP, EAX);
                        },
                        (Store store_)
                        {
                            // value is a value
                            // target is a pointer
                            import std.format:format;
                            assert(store_.type.size == 4, format!"TODO %s"(store_));
                            mov(EBP, EAX);
                            add(ebp_offsets[store_.value.index], EAX); // eax = T*
                            mov(EBP, EBX);
                            add(ebp_offsets[store_.target.index], EBX); // ebx = T**
                            load(EAX, ECX); // ecx = T
                            load(EBX, EDX); // edx = T*
                            store(ECX, EDX); // edx := T
                        },
                        (Load load_)
                        {
                            // value is a pointer
                            // target is a value
                            import std.format:format;
                            assert(load_.type.size == 4, format!"TODO %s"(load_));
                            mov(EBP, EAX);
                            add(ebp_offsets[load_.value.index], EAX); // eax = T**
                            mov(EBP, EBX);
                            add(ebp_offsets[load_.target.index], EBX); // ebx = T*
                            load(EAX, ECX); // ecx = T*
                            load(ECX, ECX); // ecx = T
                            store(ECX, EBX); // ebx := T
                        },
                    );
                }
            }
        }

        foreach (blkRef, relos; jumps)
        {
            foreach (relo; relos)
            {
                resolve(relo, blkOffsets[blkRef.index]);
            }
        }
    }
}
