module qrescent.resources.language;

import std.algorithm : canFind;
import std.exception : enforce;
import std.conv : to;
import std.traits : isSomeString;
import std.algorithm : filter;
import std.string : format;

import sdlang;

import qrescent.core.servers.language : tr;
import qrescent.core.vfs;
import qrescent.core.exceptions;
import qrescent.resources.loader;

class Language : Resource
{
public:
    T translate(T)(string old)
        if (isSomeString!T)
    {
        dstring* value = old in _translations;

        if (value)
            return to!T(*value);
        else
            return to!T(old);
    }

private:
    dstring[string] _translations;
}

package:

Resource resLoadLanguage(string path)
{
    Language lang = new Language();
    string[] parsedFiles;

    void parseFile(string filePath)
    {
        Tag root;
        { // Parse language file
            scope IVFSFile file = VFS.getFile(filePath);
            scope char[] s = new char[file.size];
            file.read(s);

            root = parseSource(cast(string) s, filePath);
        }

        // Parse includes
        foreach (Tag includeTag; root.all.tags.filter!(a => a.name == "include"))
        {
            immutable string includePath = includeTag.expectValue!string;

            enforce!LanguageException(!parsedFiles.canFind(includePath), "Path '%s' was already parsed.".tr
                .format(includePath));
            parsedFiles ~= includePath;
            parseFile(includePath);
        }

        // Parse translations
        foreach (Tag translationTag; root.all.tags.filter!(a => a.name == "translate"))
        {
            immutable string old = translationTag.expectTag("old").expectValue!string;
            immutable dstring new_ = translationTag.expectTag("new").expectValue!string.to!dstring;

            lang._translations[old] = new_;
        } 
    }

    parsedFiles ~= path;
    parseFile(path);

    return lang;
}