module qrescent.core.qomproc.output;

import std.stdio;
import std.exception : assumeWontThrow;

/**
Interface used for creating output classes for Qomproc.
*/
interface IQomprocOutput
{
    /**
    This method will be called on all registered IQomprocOutput
    implementing classes.

    Params:
        message = The message to print.
    */
    void print(string message) nothrow @trusted;
}

/**
An implementation of IQomprocOutput, this class takes a D
`File` struct and relays messages from Qomproc into this file.
*/
class QomprocOutputFile : IQomprocOutput
{
public:
    /**
    Construct a new instance of this class.

    Params:
        file = The file to output messages into.
    */
    this(File file) @safe
    {
        _file = file;
    }

    /**
    Relays messages from Qomproc into this class' file.

    Params:
        message = The message to print.
    */
    void print(string message) nothrow @trusted
    {
        assumeWontThrow(_file.write(message));
    }

protected:
    File _file;
}