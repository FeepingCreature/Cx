module cx.type.inference;

import std.algorithm;
import std.typecons;

import cx.base;
import cx.ast.base;
import cx.ast.expressions;
import cx.ast.function_;
import cx.type.primitives;

struct FunctionInstance
{
    Function function_;
    TypeMap types;
}

FunctionInstance resolve_types(Function function_)
{
    auto map = TypeMap(new Nullable!Type[function_.num_typevars]);

    while (map.types.any!"a.isNull")
    {
        bool updated = false;
        foreach (i, constraint; function_.constraintList.constraints)
        {
            if (map.types[i].isNull && constraint.resolve(map)) updated = true;
        }
        if (!updated)
        {
            assert(false, "Could not resolve all types");
        }
    }
    return FunctionInstance(function_, map);
}
