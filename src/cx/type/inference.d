module cx.type.inference;

import std.algorithm;
import std.format;
import std.range;
import std.typecons;

import cx.base;
import cx.ast.base;
import cx.ast.expressions;
import cx.ast.function_;
import cx.type.base;
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
        foreach (constraint; function_.constraintList.constraints)
        {
            // TODO fix constraints being able to assign multiple map entries
            if (constraint.resolve(map)) updated = true;
        }
        if (!updated)
        {
            assert(false, "Could not resolve all types: %s in %s".format(
                function_.constraintList.constraints
                    .enumerate
                    .filter!(pair => map.types[pair.index].isNull)
                    .map!(pair => pair.value)
                    .array,
                map
            ));
        }
    }
    return FunctionInstance(function_, map);
}
