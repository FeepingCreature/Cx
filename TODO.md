- fold ClassMethodPtr into LateSymbol
- endLifetime should not take or need to take a Reference!
- copyInto should not exist; instead there should be a copy() op that can then be chained into Assignment.
    - Sure? Needs more thinky. Maybe just `beginLifetime`?
- `Loc`/`ReLoc`/`FileRegistry` should not ought to exist. It doesn't save anything.
    - Loc should just have the file/line/column info. The parser can track it easy.
