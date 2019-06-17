module cx.ast.parse;

import std.algorithm;
import std.range;
import std.typecons;

import cx.ast.base;
import cx.ast.expressions;
import cx.ast.function_;
import cx.ast.statements;
import cx.type.primitives;
import cx.type.typesource;
import util.parser;

TypeSource parseType(Parser parser)
{
    auto _ = parser.begin;
    string type;
    if (parser.getIdentifier(type))
    {
        switch (type)
        {
            case "int":
                parser.succeed;
                return new LiteralTypeSource(Int32.instance);
            default:
                break;
        }
        parser.abort("basic type not found");
    }
    parser.abort;
    return null;
}

Function parseFunction(Parser parser)
{
    auto _ = parser.begin;

    auto ret = parseType(parser);
    string name;

    if (!ret)
    {
        parser.abort("cannot parse function");
        return null;
    }

    if (!parser.getIdentifier(name))
    {
        parser.abort("cannot parse function name");
        return null;
    }

    struct Argument
    {
        TypeSource typeSource;

        string name;
    }

    Argument[] args;

    bool parseArg()
    {
        auto _ = parser.begin;

        auto type = parseType(parser);

        if (!type)
        {
            parser.abort("cannot parse parameter type");
            return false;
        }

        string name;

        if (!parser.getIdentifier(name))
        {
            parser.abort("cannot parse parameter name");
            return false;
        }

        args ~= Argument(type, name);
        parser.succeed;
        return true;
    }

    bool parseArgList()
    {
        auto _ = parser.begin;

        if (!parser.accept("("))
        {
            parser.abort("cannot parse function: opening paren expected");
            return false;
        }

        if (parser.accept(")"))
        {
            parser.succeed;
            return true;
        }

        while (true)
        {
            if (!parseArg())
            {
                parser.abort;
                return false;
            }

            if (parser.accept(")"))
            {
                parser.succeed;
                return true;
            }

            if (!parser.accept(","))
            {
                parser.abort("cannot parse argument list: comma expected");
                return false;
            }
        }
    }

    if (!parseArgList)
    {
        parser.abort;
        return null;
    }

    auto fun = new Function(name, ret, args.map!"a.typeSource".array);

    auto argTuples = args.enumerate.map!(pair => tuple(pair.value.name, new .Argument(fun, pair.index))).array;

    parser.succeed;
    return parseFunctionBody(parser, fun, argTuples);
}

Expression parseRootTerm(Parser parser, Scope scope_)
{
    auto _ = parser.begin;

    int i;
    if (parser.getInt(i))
    {
        parser.succeed;
        return new IntLiteral(i);
    }
    string name;
    if (parser.getIdentifier(name))
    {
        if (auto obj = scope_.namespace.lookup(name))
        {
            if (auto expr = cast(Expression) obj)
            {
                parser.succeed;
                return expr;
            }
            parser.abort("not an expression");
            return null;
        }
        parser.abort("no such variable");
        return null;
    }

    parser.abort("no term matched");
    return null;
}

Expression parseCall(Parser parser, Scope scope_, Function base)
{
    auto _ = parser.begin;

    if (!parser.accept("("))
    {
        parser.abort("call expected");
        return null;
    }
    Expression[] args;
    if (!parser.accept(")"))
    {
        while (true)
        {
            auto arg = parseExpression(parser, scope_);
            if (!arg)
            {
                parser.abort;
                return null;
            }
            args ~= arg;

            if (parser.accept(")"))
            {
                break;
            }

            if (!parser.accept(","))
            {
                parser.abort("comma expected in parameter list");
                return null;
            }
        }
    }

    parser.succeed;
    return new Call(base, args);
}

Expression parseTerm(Parser parser, Scope scope_)
{
    auto left = parseRootTerm(parser, scope_);
    if (!left) return null;

    while (true)
    {
        if (auto fun = cast(Function) left)
        {
            auto combined = parseCall(parser, scope_, fun);
            if (combined)
            {
                left = combined;
                continue;
            }
        }

        break;
    }

    return left;
}

Statement parseIfStatement(Parser parser, Scope scope_)
{
    auto _ = parser.begin;
    // TODO acceptIdentifier
    if (!parser.accept("if") || !parser.accept("("))
    {
        parser.abort;
        return null;
    }
    auto condition = parseExpression(parser, scope_);
    if (!condition)
    {
        parser.abort;
        return null;
    }

    if (!parser.accept(")"))
    {
        parser.abort("closing paren expected");
        return null;
    }
    auto thenStatement = parseStatement(parser, scope_);

    if (!thenStatement)
    {
        parser.abort;
        return null;
    }

    Statement elseStatement;
    if (parser.accept("else"))
    {
        elseStatement = parseStatement(parser, scope_);
        if (!elseStatement)
        {
            parser.abort;
            return null;
        }
    }

    parser.succeed;
    return new IfStatement(condition, thenStatement, elseStatement);
}

Expression parseInfixExpression(Parser parser, Scope scope_, int precedence = 0)
{
    auto left = parseTerm(parser, scope_);
    if (!left) return null;

    if (precedence <= 1)
    {
        while (true)
        {
            if (parser.accept("+"))
            {
                auto right = parseInfixExpression(parser, scope_, 1);
                if (!right) return null;
                left = new Binary(Binary.Operation.Add, left, right, scope_.fun);
                continue;
            }
            if (parser.accept("-"))
            {
                auto right = parseInfixExpression(parser, scope_, 1);
                if (!right) return null;
                left = new Binary(Binary.Operation.Sub, left, right, scope_.fun);
                continue;
            }
            break;
        }
    }

    if (precedence == 0)
    {
        if (parser.accept("=="))
        {
            auto right = parseInfixExpression(parser, scope_, 1);
            if (!right) return null;
            left = new Binary(Binary.Operation.Equal, left, right, scope_.fun);
        }
    }

    return left;
}

Expression parseExpression(Parser parser, Scope scope_)
{
    return parseInfixExpression(parser, scope_, 0);
}

Statement parseReturnStatement(Parser parser, Scope scope_)
{
    auto _ = parser.begin;
    // TODO acceptIdentifier
    if (!parser.accept("return"))
    {
        parser.abort("return expected");
        return null;
    }
    Expression expr = parseExpression(parser, scope_);
    if (!expr)
    {
        parser.abort("return expected expression");
        return null;
    }
    if (!parser.accept(";"))
    {
        parser.abort("return expected semicolon " ~ parser.text);
        return null;
    }

    parser.succeed;
    return new ReturnStatement(expr);
}

Statement parseSequenceStatement(Parser parser, Scope scope_)
{
    auto _ = parser.begin;
    if (!parser.accept("{"))
    {
        parser.abort("opening bracket expected");
        return null;
    }
    Statement[] statements;
    while (true)
    {
        if (parser.accept("}"))
        {
            break;
        }
        auto subStatement = parseStatement(parser, scope_);

        if (!subStatement)
        {
            parser.abort;
            return null;
        }

        statements ~= subStatement;
    }

    parser.succeed;
    return new SequenceStatement(statements);
}

Statement parseStatement(Parser parser, Scope scope_)
{
    auto _ = parser.begin;
    if (auto stmt = parseSequenceStatement(parser, scope_))
    {
        parser.succeed;
        return stmt;
    }

    if (auto stmt = parseIfStatement(parser, scope_))
    {
        parser.succeed;
        return stmt;
    }

    if (auto stmt = parseReturnStatement(parser, scope_))
    {
        parser.succeed;
        return stmt;
    }

    parser.abort;
    return null;
}

Function parseFunctionBody(Parser parser, Function fun, Tuple!(string, Argument)[] args)
{
    auto namespace = new Namespace;

    namespace.add(fun.name, fun);

    foreach (pair; args)
    {
        namespace.add(pair[0], pair[1]);
    }

    auto body_ = parseStatement(parser, Scope(fun, namespace));

    if (!body_)
    {
        return null;
    }

    fun.body_ = body_;
    return fun;
}
