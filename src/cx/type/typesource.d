module cx.type.typesource;

import std.format;

import cx.base;
import cx.type.base;

class LiteralTypeSource : TypeSource
{
    Type type_;

    this(Type type_) { this.type_ = type_; }

    override bool ready(TypeMap) { return true; }
    override Type type(TypeMap) { return type_; }
    override string toString() const { return type_.toString; }
}

class GlobalTypeSource : TypeSource
{
    string name;

    override bool ready(TypeMap) { return true; }
    override string toString() const { return this.name; }
    override Type type(TypeMap) { assert(false, format!"global lookup '%s' not resolved"(name)); }
}

class TypeVarSource : TypeSource
{
    TypeVar typeVar_;

    this(TypeVar typeVar_) { this.typeVar_ = typeVar_; }

    override string toString() const { return typeVar_.toString; }

    override bool ready(TypeMap map)
    {
        return typeVar_ in map;
    }

    override Type type(TypeMap map)
    {
        return map[typeVar_];
    }
}
