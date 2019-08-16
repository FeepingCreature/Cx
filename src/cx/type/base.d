module cx.type.base;

import std.format;
import std.typecons;

import cx.base;

interface Type : LanguageObject
{
    size_t size();
    size_t alignment();
    string toString() const;
}

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

abstract interface TypeSource
{
    abstract bool ready(TypeMap);
    abstract Type type(TypeMap);
    abstract string toString() const;
}

abstract interface TypeConstraint
{
    abstract bool resolve(TypeMap);
    abstract string toString() const;
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
        if (target in map) return false;
        if (!source.ready(map)) return false;

        map[target] = source.type(map);
        return true;
    }
}
