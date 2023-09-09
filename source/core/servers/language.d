module qrescent.core.servers.language;

import std.traits : isSomeString;
import std.exception : enforce;
import std.conv : to;
import std.exception : assumeWontThrow;

import qrescent.core.qomproc;
import qrescent.core.exceptions;
import qrescent.resources.loader;
import qrescent.resources.language;

struct LanguageServer
{
    @disable this();
    @disable this(this);

public static:
    T translate(T = string)(string old) nothrow
        if (isSomeString!T)
    {
        if (!_current)
            return assumeWontThrow(old.to!T);
        else
            return assumeWontThrow(_current.translate!T(old));
    }

package(qrescent.core) static:
    void _initialize(string langPath)
    {
        Qomproc.println("LanguageServer initializing...".tr);

        if (langPath)
            _current = cast(Language) ResourceLoader.load(langPath);

        Qomproc.registerQCMD("loadlang", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            enforce!QomprocException(args.length >= 2, "Expected file to load.".tr);
            _current = cast(Language) ResourceLoader.load(args[1]);
        },
        "Loads a language from the given path.".tr));

        Qomproc.registerQCMD("translate", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            enforce!QomprocException(args.length >= 2, "Expected text to translate.".tr);
            Qomproc.println(translate!string(args[1]));
        },
        "Translates the given key.".tr));
    }

    void _shutdown()
    {
        Qomproc.unregisterQCMD("loadlang");
        Qomproc.unregisterQCMD("translate");
    }

private static:
    Language _current;
}

alias tr = LanguageServer.translate;