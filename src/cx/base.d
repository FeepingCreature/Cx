module cx.base;

interface LanguageObject
{
}

interface Type : LanguageObject
{
    size_t size();
    size_t alignment();
    string toString() const;
}
