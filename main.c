#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <ffi.h>
#include <sys/time.h>

typedef struct
{
    int type;
    int size;
    int alignmask;
} Type;

#define T_INT ((Type) { .type = 0, .size = sizeof(int), .alignmask = (1 << 2) - 1 })

int type_id_base = 1;

typedef enum
{
    DEFINED_FUNCTION,
    EXTERNAL_FUNCTION
} FunctionType;

typedef struct
{
    FunctionType type;
    Type *args_ptr;
    int args_len;
    Type ret;
} Function;

#define APPEND(BASE, VALUE...) ({ \
    BASE ## _ptr = realloc(BASE ## _ptr, sizeof(*BASE ## _ptr) * ++BASE ## _len); \
    BASE ## _ptr[BASE ## _len- 1] = (typeof(*BASE ## _ptr)) VALUE; \
    BASE ## _len - 1; \
})

typedef enum
{
    OP_READ_ARG, // int index
    OP_LITERAL_INT, // int
    OP_READ_MEM, // reg pointer
    OP_WRITE_MEM, // reg pointer, reg source
    OP_UNARY_OP, // int op, reg a
    OP_BINARY_OP, // int op, reg a, reg b
    OP_STACK_ALLOC, // ptr type
    OP_CALL, // ptr function, int len, ptr args
    // block enders
    OP_BRANCH, // int block
    OP_BRANCH_IF, // reg condition, int block_then, int block_else
    OP_RETURN // reg value
} OpType;

typedef enum
{
    NEG,
    NOT
} UnaryOpType;

typedef enum
{
    ADD, SUB, MUL, DIV,
    EQ, GT, LT, GE, LE
} BinaryOpType;

typedef struct
{
    OpType type;
    int target_reg;
    union
    {
        int num;
        void *ptr;
    } data1, data2, data3;
} Operation;

typedef struct
{
    Operation *instrs_ptr;
    int instrs_len;
} Block;

typedef struct
{
    Function base;
    Block *blocks_ptr;
    int blocks_len;
    Type *reg_types_ptr;
    int reg_types_len;
} DefinedFunction;

typedef struct
{
    int *regs_ptr;
    int regs_len;
} ParamList;

void build_open_block(DefinedFunction *fn)
{
    APPEND(fn->blocks, {0});
}

int build_read_arg(DefinedFunction *fn, int index)
{
    APPEND(fn->reg_types, fn->base.args_ptr[index]);

    Block *block = fn->blocks_ptr + fn->blocks_len - 1;
    APPEND(block->instrs, {
        .type = OP_READ_ARG,
        .target_reg = fn->reg_types_len - 1,
        .data1 = { .num = index },
    });

    return fn->reg_types_len - 1;
}

int build_literal_int(DefinedFunction *fn, int value)
{
    APPEND(fn->reg_types, T_INT);

    Block *block = fn->blocks_ptr + fn->blocks_len - 1;
    APPEND(block->instrs, {
        .type = OP_LITERAL_INT,
        .target_reg = fn->reg_types_len - 1,
        .data1 = { .num = value },
    });

    return fn->reg_types_len - 1;
}

int build_binary_op(DefinedFunction *fn, BinaryOpType op, int r1, int r2)
{
    assert(fn->reg_types_ptr[r1].type == T_INT.type);
    assert(fn->reg_types_ptr[r2].type == T_INT.type);
    APPEND(fn->reg_types, T_INT);

    Block *block = fn->blocks_ptr + fn->blocks_len - 1;
    APPEND(block->instrs, {
        .type = OP_BINARY_OP,
        .target_reg = fn->reg_types_len - 1,
        .data1 = { .num = op },
        .data2 = { .num = r1 },
        .data3 = { .num = r2 },
    });

    return fn->reg_types_len - 1;
}

int build_call(DefinedFunction *fn, Function *callfn, ParamList *params)
{
    APPEND(fn->reg_types, callfn->ret);

    Block *block = fn->blocks_ptr + fn->blocks_len - 1;
    APPEND(block->instrs, {
        .type = OP_CALL,
        .target_reg = fn->reg_types_len - 1,
        .data1 = { .ptr = callfn },
        .data2 = { .ptr = params },
    });

    return fn->reg_types_len - 1;
}

void build_branch_if(DefinedFunction *fn, int rtest, int block1, int block2)
{
    Block *block = fn->blocks_ptr + fn->blocks_len - 1;
    APPEND(block->instrs, {
        .type = OP_BRANCH_IF,
        .data1 = { .num = rtest },
        .data2 = { .num = block1 },
        .data3 = { .num = block2 },
    });
}

void build_return(DefinedFunction *fn, int reg)
{
    assert(fn->base.ret.type == fn->reg_types_ptr[reg].type);

    Block *block = fn->blocks_ptr + fn->blocks_len - 1;
    APPEND(block->instrs, {
        .type = OP_RETURN,
        .data1 = { .num = reg },
    });
}

typedef struct
{
    Function base;
    const char *name;
} ExternalFunction;

void interpret_closure(ffi_cif *cif, void *ret, void *args[], DefinedFunction *fn)
{
    int framesize = 0;
    int *offset = malloc(sizeof(int) * fn->reg_types_len);
    for (int i = 0; i < fn->reg_types_len; i++)
    {
        Type *type = &fn->reg_types_ptr[i];
        framesize += type->alignmask;
        framesize &= ~type->alignmask;
        offset[i] = framesize;
        framesize += type->size;
    }
    void *frame = malloc(framesize);

    int block = 0, instr = 0; // entry point
    while (true)
    {
        Operation *op = &fn->blocks_ptr[block].instrs_ptr[instr];
        switch (op->type)
        {
            case OP_READ_ARG:
                assert(op->target_reg < fn->reg_types_len);
                memcpy(frame + offset[op->target_reg], args[op->data1.num], fn->reg_types_ptr[op->target_reg].size);
                instr++;
                break;
            case OP_LITERAL_INT:
                *(int*)(frame + offset[op->target_reg]) = op->data1.num;
                instr++;
                break;
            case OP_BINARY_OP:
            {
                int lhs = *(int*)(frame + offset[op->data2.num]);
                int rhs = *(int*)(frame + offset[op->data3.num]);
                int res;
                switch (op->data1.num)
                {
                    case ADD:
                        res = lhs + rhs;
                        break;
                    case SUB:
                        res = lhs - rhs;
                        break;
                    case EQ:
                        res = lhs == rhs;
                        break;
                    default: assert(false);
                }
                *(int*)(frame + offset[op->target_reg]) = res;
                instr++;
                break;
            }
            break;
            case OP_BRANCH_IF:
            {
                int test = *(int*)(frame + offset[op->data1.num]);
                int blk_then = op->data2.num;
                int blk_else = op->data3.num;
                block = test ? blk_then : blk_else;
                instr = 0;
                break;
            }
            case OP_RETURN:
            {
                int value = *(int*)(frame + offset[op->data1.num]);
                *(int*) ret = value;
                free(frame);
                free(offset);
                return;
            }
            case OP_CALL:
            {
                DefinedFunction *call_fn = op->data1.ptr;
                ParamList *params = op->data2.ptr;
                int callmapsize = 0;
                for (int i = 0; i < call_fn->base.args_len; i++)
                {
                    Type *type = &call_fn->base.args_ptr[i];
                    callmapsize += type->size + type->alignmask;
                    callmapsize &= ~type->alignmask;
                }
                void *callmap = malloc(callmapsize);
                void **args = malloc(sizeof(void*) * call_fn->base.args_len);
                int call_offset = 0;
                assert(params->regs_len == fn->base.args_len);
                for (int i = 0; i < call_fn->base.args_len; i++)
                {
                    Type *type = &call_fn->base.args_ptr[i];

                    assert(fn->reg_types_ptr[params->regs_ptr[i]].type == fn->base.args_ptr[i].type);
                    memcpy(callmap + call_offset, frame + offset[params->regs_ptr[i]], type->size);
                    args[i] = callmap + call_offset;

                    call_offset += type->size + type->alignmask;
                    call_offset &= ~type->alignmask;
                }

                int ret;
                interpret_closure(cif, &ret, args, call_fn);

                free(callmap);
                free(args);

                *(int*)(frame + offset[op->target_reg]) = ret;
                instr++;
                break;
            }
            default:
                fprintf(stderr, "unimplemented op %i\n", op->type);
                assert(false);
        }
    }
}

void (*interpret_translate(DefinedFunction *fn))()
{
    ffi_cif *cif = malloc(sizeof(ffi_cif));
    ffi_type **args = malloc(sizeof(ffi_type*) * fn->base.args_len);
    void (*ffi_fn)();
    ffi_closure *closure = ffi_closure_alloc(sizeof(ffi_closure), (void**) &ffi_fn);
    assert(closure);
    for (int i = 0; i < fn->base.args_len; i++)
    {
        Type type = fn->base.args_ptr[i];
        assert(type.type == T_INT.type);
        args[i] = &ffi_type_sint32;
    }
    assert(fn->base.ret.type == T_INT.type);
    ffi_prep_cif(cif, FFI_DEFAULT_ABI, fn->base.args_len, &ffi_type_sint32, args);
    ffi_prep_closure_loc(closure, cif, (void(*)(ffi_cif*, void*, void**, void*)) interpret_closure, fn, ffi_fn);
    return ffi_fn;
}

int ack_native(int m, int n) {
  if (m == 0) return n+1;
  if (n == 0) return ack_native(m - 1, 1);
  return ack_native(m - 1, ack_native(m, n - 1));
}

long long int usec()
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000000 + tv.tv_usec;
}

int main()
{
    DefinedFunction ack = {
        .base = {
            .type = DEFINED_FUNCTION,
            .ret = T_INT,
        }
    };
    APPEND(ack.base.args, T_INT);
    APPEND(ack.base.args, T_INT);

    build_open_block(&ack); // 0
    int r1 = build_read_arg(&ack, 0); // m
    int r2 = build_literal_int(&ack, 0); // 0
    int r3 = build_binary_op(&ack, EQ, r1, r2); // m == 0
    build_branch_if(&ack, r3, 1, 2); // if (m == 0)

    build_open_block(&ack); // 1
    int r4 = build_read_arg(&ack, 1); // n
    int r5 = build_literal_int(&ack, 1); // 1
    int r6 = build_binary_op(&ack, ADD, r4, r5); // n + 1
    build_return(&ack, r6); // return n + 1

    build_open_block(&ack); // 2
    int r7 = build_read_arg(&ack, 1); // n
    int r8 = build_literal_int(&ack, 0); // 0
    int r9 = build_binary_op(&ack, EQ, r7, r8); // n == 0
    build_branch_if(&ack, r9, 3, 4); // if (n == 0)

    build_open_block(&ack); // 3
    int r10 = build_read_arg(&ack, 0); // m
    int r11 = build_literal_int(&ack, 1); // 1
    int r12 = build_binary_op(&ack, SUB, r10, r11); // m - 1

    ParamList *plist = malloc(sizeof(ParamList));
    *plist = (ParamList) {0};
    APPEND(plist->regs, r12);
    APPEND(plist->regs, r11);
    int r13 = build_call(&ack, &ack.base, plist); // ack(m - 1, 1)
    build_return(&ack, r13); // return ack(m - 1, 1)

    build_open_block(&ack); // 4
    int r14 = build_read_arg(&ack, 0); // m
    int r15 = build_read_arg(&ack, 1); // n
    int r16 = build_literal_int(&ack, 1); // 1
    int r17 = build_binary_op(&ack, SUB, r15, r16); // n - 1
    plist = malloc(sizeof(ParamList));
    *plist = (ParamList) {0};
    APPEND(plist->regs, r14);
    APPEND(plist->regs, r17);
    int r18 = build_call(&ack, &ack.base, plist); // ack(m, n - 1)
    int r19 = build_binary_op(&ack, SUB, r14, r16); // m - 1
    plist = malloc(sizeof(ParamList));
    *plist = (ParamList) {0};
    APPEND(plist->regs, r19);
    APPEND(plist->regs, r18);
    int r20 = build_call(&ack, &ack.base, plist); // ack(m - 1, ack(m, n - 1))
    build_return(&ack, r20); // return ack(m - 1, ack(m, n - 1))

    int (*ack_interp)(int, int) = (int(*)(int, int)) interpret_translate(&ack);

    long long native_start = usec();
    int native = ack_native(3, 8);
    long long native_end = usec();
    printf("native ack(3, 8) = %i in %fms\n", native, (native_end - native_start) / 1000.0f);

    long long interp_start = usec();
    int interp = ack_interp(3, 8);
    long long interp_end = usec();
    printf("interp ack(3, 8) = %i in %fms\n", interp, (interp_end - interp_start) / 1000.0f);

    return 0;
}
