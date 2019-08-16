module cx.ast.function_;

import std.algorithm;
import std.range;
import std.format;

import cx.ast.base;
import cx.type.base;
import cx.type.structure;
import cx.type.typesource;
import ssa.base : SSABasicType = BasicType, SSAReg = Reg;
import ssa.fun : SSAFunction = Function, SSAFunctionBuilder = FunctionBuilder;

class Function : BaseFunction, Symbol, Expression, TypeConstraint
{
    string name;

    TypeSource ret;

    TypeVar retVar;

    TypeSource[] args;

    TypeVar[] argVars;

    invariant(args.length == argVars.length);

    Statement body_;

    override string toString() const
    {
        return name;
        // return format!"%s(%(%s, %)): %s %s\n%s"(name, args, ret, body_, constraintList);
    }

    override TypeSource type() { assert(false); }

    override SSAReg encode(FunctionEncodeArgs args)
    {
        return args.fun.symbol(this.name);
    }

    override SSAFunction encodeSymbol(TypeMap typeMap)
    {
        auto stackframeType = typeMap[stackframe];
        auto stackframeStruct = cast(Struct) stackframeType;
        auto basicStackframeType = SSABasicType(stackframeType.size(), 4); // TODO align
        auto fun = new SSAFunctionBuilder(
            name,
            SSABasicType(typeMap[retVar].size(), 4),
            argVars.map!(a => SSABasicType(typeMap[a].size(), 4)).array,
            basicStackframeType,
        );
        foreach (i, arg; argVars)
        {
            auto reg = fun.arg(i);
            auto type = SSABasicType(typeMap[arg].size(), 4); // TODO align
            auto offset = fun.add(fun.stackframe, fun.literal(stackframeStruct.offset(i)));

            fun.store(type, reg, offset);
        }
        body_.encode(FunctionEncodeArgs(fun, typeMap, Scope()));
        return fun.value;
    }

    override bool resolve(TypeMap map)
    {
        bool updated = false;

        if (this.ret.ready(map) && this.retVar !in map)
        {
            map[this.retVar] = this.ret.type(map);
            updated = true;
        }

        foreach (i, arg; this.args)
        {
            if (arg.ready(map) && this.argVars[i] !in map)
            {
                map[this.argVars[i]] = arg.type(map);
                updated = true;
            }
        }

        return updated;
    }

    this(string name, TypeSource ret, TypeSource[] args)
    {
        this.name = name;
        this.constraintList = new ConstraintList;
        this.num_typevars = 0;
        this.ret = ret;
        this.args = args.dup;
        this.retVar = allocTypeVar;
        foreach (arg; args)
        {
            this.argVars ~= allocTypeVar;
        }
        this.constraintList ~= this;
        this.stackframe = allocTypeVar;
        this.constraintList ~= new StructConstraint(this.stackframe, args);
    }
}

class StructMember : Expression
{
    Expression base;

    TypeVar type_;

    size_t index;

    override TypeSource type()
    {
        return new TypeVarSource(type_);
    }

    override string toString() const { return format!"(%s).%s"(base, index); }

    this(Expression base, size_t index, Function fun)
    {
        this.base = base;
        this.index = index;
        this.type_ = fun.allocTypeVar;
        fun.constraintList ~= new MemberTypeConstraint(this.type_, base.type, index);
    }

    override SSAReg encode(FunctionEncodeArgs args)
    {
        if (cast(LValue) base)
        {
            assert(false, "LVALUE BASE");
        }

        auto fun = args.fun;
        auto structType = cast(Struct) base.type.type(args.map);
        auto basicType = SSABasicType(structType.size, 4);
        auto value = base.encode(args);
        auto offset = structType.offset(index);

        auto space = fun.alloca(basicType);
        auto offsetReg = fun.literal(offset);
        auto memberBase = fun.add(space, offsetReg);

        args.fun.store(basicType, value, space);
        return args.fun.load(SSABasicType(args.map[type_].size, 4), memberBase);

        // assert(false, format!"%s.%s : %s"(base.type.type(args.map), index, args.map[type_]));
    }
}

class StructConstraint : TypeConstraint
{
    TypeVar target;

    TypeSource[] members;

    this(TypeVar target, TypeSource[] members)
    {
        this.target = target;
        this.members = members;
    }

    override string toString() const { return format!"[%s := { %(%s, %) }]"(target, members); }

    override bool resolve(TypeMap typeMap)
    {
        if (!members.all!(member => member.ready(typeMap)))
        {
            return false;
        }

        auto memberTypes = members.map!(member => member.type(typeMap)).array;

        typeMap[target] = new Struct(memberTypes);
        return true;
    }
}

class MemberTypeConstraint : TypeConstraint
{
    TypeVar target;

    TypeSource base;

    size_t index;

    this(TypeVar target, TypeSource base, size_t index)
    {
        this.target = target;
        this.base = base;
        this.index = index;
    }

    override string toString() const { return format!"[%s := %s.%s]"(target, base, index); }

    override bool resolve(TypeMap typeMap)
    {
        import cx.type.structure : Struct;

        if (!base.ready(typeMap))
        {
            return false;
        }

        auto baseType = base.type(typeMap);
        auto baseTypeStruct = cast(Struct) baseType;

        assert(baseTypeStruct, "Mistyped struct access: lhs is not a struct");
        assert(index < baseTypeStruct.members.length, "Mistyped struct access: not enough fields");

        typeMap[target] = baseTypeStruct.members[index];
        return true;
    }
}

class Argument : Expression
{
    Function function_;

    size_t index;

    override TypeSource type()
    {
        return new TypeVarSource(function_.argVars[index]);
    }

    override SSAReg encode(FunctionEncodeArgs args)
    {
        return args.fun.arg(index);
    }

    override string toString() const { return format!"@%s"(index); }

    this(typeof(this.tupleof) args) { this.tupleof = args; }
}
