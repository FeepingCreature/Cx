module util.parser;

import std.exception;
import std.range;
import std.stdio;
import std.string;
import std.uni;

class Parser
{
    string fullText;

    string text;

    string[] states;

    struct ParseOutcome
    {
        bool failed;
        // Loc location;
        string message;
        ParseOutcome[] reasons;
    }

    ParseOutcome[] errorStack;

    this(string text)
    {
        this.fullText = text;
        this.text = text;
    }

    auto begin(string file = __FILE__, size_t line = __LINE__)
    {
        struct ParserCheck
        {
            Parser parser;
            string file;
            size_t line;
            size_t preDepth;
            this(Parser parser, size_t preDepth, string file, size_t line)
            {
                this.parser = parser;
                this.preDepth = preDepth;
                this.file = file;
                this.line = line;
            }
            @disable this();
            ~this()
            {
                if (parser.errorStack.length != preDepth)
                {
                    writefln(
                        "%s:%s: depth bug: expected %s, got %s",
                        file, line, preDepth, parser.errorStack.length
                    );
                }
            }
        }
        auto res = ParserCheck(this, errorStack.length, file, line);
        states ~= text;
        errorStack ~= ParseOutcome(false, null, null); // parse in progress
        return res;
    }

    void strip()
    {
        text = text.strip;
    }

    void abort(string error = null)
    {
        text = states.back;
        states.popBack;

        auto lastError = errorStack.back;

        errorStack.popBack;

        if (error)
        {
            lastError.failed = true;
            lastError.message = error;

            errorStack.back.reasons ~= lastError;
        }
        else
        {
            // no message, just copy our subreasons and attribute to whatever failure below will define one
            errorStack.back.reasons ~= lastError.reasons;
        }
    }

    void succeed()
    {
        states.popBack;

        errorStack.popBack; // discard sub-errors, since we succeeded
    }

    void error()
    {
        writefln("failed: %s", errorStack);
        import core.stdc.stdlib : abort;
        abort;
    }

    bool getIdentifier(out string identifier)
    {
        auto _ = begin;
        strip;
        if (!text.length || !text.front.isAlpha)
        {
            abort("invalid identifier: " ~ text);
            return false;
        }
        string prevText = text;
        while (text.length && text.front.isAlphaNum)
        {
            text.popFront;
        }
        identifier = prevText[0 .. prevText.length - text.length];
        succeed;
        return true;
    }

    bool getInt(out int i)
    {
        auto _ = begin;
        strip;
        if (!text.length || !text.front.isNum)
        {
            abort("not a number");
            return false;
        }
        string prevText = text;
        while (text.length && text.front.isNum)
        {
            text.popFront;
        }
        auto number = prevText[0 .. prevText.length - text.length];
        if (number == "0")
        {
            i = 0;
            succeed;
            return true;
        }
        if (number.front == '0')
        {
            abort("unexpected leading zero");
            return false;
        }

        foreach (ch; number)
        {
            i = i * 10 + (ch - '0');
        }
        succeed;
        return true;
    }

    bool accept(string needle)
    {
        auto _ = begin;
        strip;
        if (text.startsWith(needle))
        {
            text = text[needle.length .. $];
            succeed;
            return true;
        }
        abort;
        return false;
    }

    void done()
    {
        auto _ = begin;
        strip;
        enforce(states.length == 1, format!"states.length expected 1, got %s"(states.length));
        enforce(errorStack.length == 1, format!"errorStack.length expected 1, got %s"(errorStack.length));
        if (!text.empty)
        {
            abort("invalid input");
        }
        else
        {
            succeed;
        }
    }
}

alias isNum = ch => ch >= '0' && ch <= '9';
