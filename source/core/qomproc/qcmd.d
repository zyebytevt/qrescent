module qrescent.core.qomproc.qcmd;

import qrescent.core.qomproc;

/**
Holds a command that can be called from the Qomproc or
configuration files.
*/
struct QCMD
{
public:
    @disable this();

    /// The type that callback delegates must use.
    alias callback_t = void delegate(string[] args, Qomproc.CommandSource cmdsrc);

    /**
    Constructs a new instance.

    Params:
        callback = The callback for this command.
        description = The description of this command that will be shown to the user.
    */
    this(callback_t callback, string description) nothrow pure @nogc @safe
    {
        assert(callback, "QCMD callback cannot be null!");
        _callback = callback;
        _description = description;
    }

package:
    callback_t _callback;
    string _description;
}