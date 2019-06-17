module cx.ast.base;

import std.exception : enforce;
import std.format : format;
import std.typecons;

import cx.base;
import ssa.base : SSAReg = Reg;
import ssa.fun : SSAFunctionBuilder = FunctionBuilder;

struct TypeVar
{
    int index;
    string toString() const { return format!"t%s"(index); }
}

struct TypeMap
{
    Nullable!Type[] types;

    bool opBinaryRight(string op : "in")(TypeVar typeVar)
    in (typeVar.index < types.length)
    {
        return !types[typeVar.index].isNull;
    }

    Type opIndex(TypeVar typeVar)
    in (typeVar.index < types.length && !types[typeVar.index].isNull)
    {
        return types[typeVar.index].get;
    }

    Type opIndexAssign(Type type, TypeVar typeVar)
    in (typeVar.index < types.length && types[typeVar.index].isNull)
    {
        types[typeVar.index] = type;
        return type;
    }
}

abstract class TypeSource
{
    abstract bool ready(TypeMap);
    abstract Type type(TypeMap);
    override abstract string toString() const;
}

abstract class TypeConstraint
{
    abstract bool resolve(TypeMap);
    override abstract string toString() const;
}

class SetConstraint : TypeConstraint
{
    TypeVar target;

    TypeSource source;

    this(TypeVar target, TypeSource source)
    {
        this.target = target;
        this.source = source;
    }

    override string toString() const { return format!"[%s := %s]"(target, source); }

    override bool resolve(TypeMap map)
    {
        if (!source.ready(map)) return false;

        assert(target !in map, format!"%s in %s"(target, map));
        map[target] = source.type(map);
        return true;
    }
}

interface Expression : LanguageObject
{
    TypeSource type();
    SSAReg encode(SSAFunctionBuilder, TypeMap);
    string toString() const;
}

abstract class Symbol
{
    void encodeSymbol(SSAFunctionBuilder, TypeMap);
}

abstract class Statement
{
    abstract void encode(SSAFunctionBuilder, TypeMap);
    abstract override string toString() const;
}

class Namespace
{
    Namespace parent;

    LanguageObject[string] entries;

    this(Namespace parent)
    {
        this.parent = parent;
    }

    this()
    {
        this.parent = null;
    }

    void add(string name, Expression value)
    {
        enforce(name !in entries, "tried to define duplicate variable");

        entries[name] = value;
    }

    override string toString() const
    {
        if (!parent) return format!"%s"(entries.keys);
        return format!"%s -> %s"(entries.keys, parent);
    }

    LanguageObject lookup(string name)
    {
        if (auto entry = name in entries)
        {
            return *entry;
        }
        if (parent)
        {
            return parent.lookup(name);
        }
        return null;
    }
}
