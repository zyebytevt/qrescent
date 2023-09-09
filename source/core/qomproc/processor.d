module qrescent.core.qomproc.processor;

import std.exception : enforce, collectException, assumeWontThrow;
import std.format : sformat;
import std.conv : ConvException;
import std.array : join;

import qrescent.core.servers.language : tr;
import qrescent.core.servers.input;
import qrescent.core.exceptions;
import qrescent.core.qomproc;
import qrescent.core.vfs;
import qrescent.core.engine;

/**
The Qrescent Command Processor is responsible for interpreting and dispatching
commands given by the user or the game itself. It also holds references to
variables in memory, which can be freely modified.
*/
struct Qomproc
{
    @disable this();
    @disable this(this);

public static:
    /// From where the command originated from.
    enum CommandSource
    {
        buffer, /// Command originated from buffer, e.g. user input, append or exec.
        internal /// Command originated from the execute() method.
    }

    /**
    Initializes internal Qomproc commands.
    */
    void initSystemQCMDs() nothrow @safe // @suppress(dscanner.style.doc_missing_throw)
    {
        registerQCMD("echo", QCMD(delegate void(string[] args, CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
        {
            if (args.length == 1)
                println();
            else
                println(args[1..$].join(" "));
        },
        "Prints a string out to Qomproc. With no arguments, a blank line.".tr));
    	
        registerQCMD("wait", QCMD(delegate void(string[] args, CommandSource cmdsrc)
        {
            import std.conv : to;

            if (args.length == 1)
                _suspendTimer++;
            else if (args.length == 2)
            {
                _suspendTimer = args[1].to!ushort;
                
                if (_suspendTimer > 600)
                {
                    println("Cannot wait more than 600 cycles.".tr);
                    _suspendTimer = 600;
                }
            }
            else
                throw new QomprocException("Too many arguments, expected at most 1.".tr);
        },
        "Suspends command execution for given cycles. Without arguments, waits one cycle.".tr));
    	
        registerQCMD("exec", QCMD(delegate void(string[] args, CommandSource cmdsrc)
        {
            enforce!QomprocException(args.length == 2, "Expected file to exec.".tr);

            IVFSFile sourceFile = VFS.getFile(args[1]);
            char[] source = new char[sourceFile.size];
            sourceFile.read(source);
            sourceFile.destroy();

            append(cast(string) source);
            printfln("Execing %s".tr, args[1]);
        },
        "Executes a configuration file.".tr));
    	
        registerQCMD("toggle", QCMD(delegate void(string[] args, CommandSource cmdsrc)
        {
            enforce!QomprocException(args.length == 2, "Expected QVAR to toggle.".tr);
            
            QVAR* cvar = args[1] in _qvars;
            enforce!QomprocException(cvar, "Unknown QVAR '%s'.".tr.format(args[1]));
            enforce!QomprocException(cvar._type == QVAR.Type.boolean, "QVAR must be of type bool.".tr);
            
            *(cast(bool*) cvar._value) = !*(cast(bool*) cvar._value);

            printfln("'%s' is '%s'.".tr, args[1], *(cast(bool*) cvar._value));
        },
        "Toggles a boolean QVAR between true and false.".tr));

        registerQCMD("help", QCMD(delegate void(string[] args, CommandSource cmdsrc)
        {
            if (args.length < 2)
            {
                Qomproc.println("For a list of QCMDs, type 'cmdlist'.".tr);
                Qomproc.println("For a list of QVARs, type 'cvarlist'.".tr);
                Qomproc.println("For a list of actions, type 'actionlist'.".tr);
                Qomproc.println("For a detailled description of any of these, write it's name after 'help'.".tr);
                Qomproc.println("Alternatively, append a ? at the end of your input as a shortcut.".tr);
                return;
            }

            // Find which QVAR, QCMD or action was requested.
            QCMD* qcmd = args[1] in _qcmds;
            if (qcmd)
            {
                Qomproc.printfln("QCMD '%s':".tr, args[1]);
                Qomproc.println(qcmd._description);
                return;
            }

            QVAR* qvar = args[1] in _qvars;
            if (qvar)
            {
                Qomproc.printfln("QVAR '%s', type '%s':".tr, args[1], qvar._type);
                if (qvar._flags & QVAR.Flags.archive)
                    Qomproc.println("This variable is archived.".tr);
                if (qvar._flags & QVAR.Flags.readOnly)
                    Qomproc.println("This variable is read only.".tr);
                Qomproc.println(qvar._description);
                return;
            }

            if (args[1].length > 1)
            {
                bool** action = args[1][1..$] in _actions;
                if (action)
                {
                    Qomproc.printfln("Action '%s' is currently %s.".tr, args[1], **action ? "active".tr : "inactive".tr);
                    return;
                }
            }

            Qomproc.printfln("No QCMD, QVAR or action named '%s' exists.".tr, args[1]);
        },
        "Shows the description of the specified QVAR or QCMD.".tr));

        registerQCMD("cmdlist", QCMD(delegate void(string[] args, CommandSource cmdsrc)
        {
            foreach (string name, ref QCMD qcmd; _qcmds)
                Qomproc.println("    " ~ name);

            Qomproc.printfln("\n%d commands.".tr, _qcmds.length);
        },
        "Lists all available commands.".tr));

        registerQCMD("actionlist", QCMD(delegate void(string[] args, CommandSource cmdsrc)
        {
            foreach (string name, bool* action; _actions)
                Qomproc.println("    +" ~ name);

            Qomproc.printfln("\n%d actions.".tr, _actions.length);
        },
        "Lists all available actions.".tr));

        registerQCMD("cvarlist", QCMD(delegate void(string[] args, CommandSource cmdsrc)
        {
            foreach (string name, ref QVAR qvar; _qvars)
            {
                char[3] flags = ' ';

                if (qvar._flags & QVAR.Flags.archive) flags[0] = 'A';
                if (qvar._flags & QVAR.Flags.readOnly) flags[1] = 'R';

                Qomproc.printfln("%s %s (%s)", flags, name, qvar._type);
            }

            Qomproc.printfln("\n%d variables.".tr, _qvars.length);
        },
        "Lists all available variables.".tr));

        registerQCMD("alias", QCMD(delegate void(string[] args, CommandSource cmdsrc)
        {
            if (args.length == 1)
            {
                foreach (string name, string value; _aliases)
                    Qomproc.printfln("'%s' = '%s'", name, value);

                return;
            }

            enforce!QomprocException(args.length >= 3, "Expected alias name and value.".tr);

            _aliases[args[1]] = args[2];
        },
        "Alias a token to another value.".tr));

        registerQCMD("unalias", QCMD(delegate void(string[] args, CommandSource cmdsrc)
        {
            enforce!QomprocException(args.length >= 2, "Expected alias name.".tr);

            _aliases.remove(args[1]);
        },
        "Removes an alias.".tr));

        registerQCMD("unaliasall", QCMD(delegate void(string[] args, CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
        {
            _aliases.clear();
        },
        "Removes all defined aliases.".tr));

        registerQVAR("con_printdispatch", QVAR(&_printDispatch, "Prints commands that are executed by the Qomproc.".tr));
    }

    /**
    Register an output to Qomproc, to which future messages will be relayed to.

    Params:
        output = The instance to relay future messages to.
    */
    void addOutput(IQomprocOutput output) nothrow @safe
    {
        _outputs ~= output;
    }

    /**
    Output a line, relaying it to all registered outputs.

    Params:
        message = The message to print.
    */
    void println(string message = "") nothrow @safe
    {
        message ~= '\n'; // Add line end

        foreach (output; _outputs)
            output.print(message);
    }

    /**
    Output a formatted, relaying it to all registered outputs.

    Params:
        fmt = The string to be formatted.
        args = Values to be inserted into the format string.
    */
    void printfln(T...)(string fmt, T args) nothrow @trusted
    {
        static char[500] fmtBuffer = void;
        char[] msgSlice;

        if (collectException(sformat(fmtBuffer[], fmt, args), msgSlice))
            println("<< Qomproc.printfln failed formatting >>");
        else
            println(cast(string) msgSlice);
    }

    /**
    Output a line, relaying it to all registered outputs, if developer mode is turned on.

    Params:
        message = The message to print.
    */
    void dprintln(lazy string message = "") nothrow @safe
    {
        if (EngineCore.developer)
            assumeWontThrow(println(message));
    }

    /**
    Output a formatted, relaying it to all registered outputs, if developer mode is turned on.

    Params:
        fmt = The string to be formatted.
        args = Values to be inserted into the format string.
    */
    void dprintfln(T...)(lazy string fmt, lazy T args) nothrow @trusted
    {
        if (EngineCore.developer)
            assumeWontThrow(printfln(fmt, args));
    }

    /**
    Register a command with the given name.

    Params:
        name = The name of the command to register.
        qcmd = The command struct to register.
    */
    void registerQCMD(string name, QCMD qcmd) nothrow @safe
    {
        _qcmds[name] = qcmd;
    }

    /**
    Register a variable with the given name.

    Params:
        name = The name of the variable to register.
        qvar = The variable struct to register.
    */
    void registerQVAR(string name, QVAR qvar) nothrow @safe
    {
        _qvars[name] = qvar;
    }

    /**
    Register an action with the given name.

    Params:
        name = The name of the action to register.
        action = Pointer to a boolean variable, set to `true` or `false`
        depending on weither the action is active or not.
    */
    void registerAction(string name, bool* action) nothrow @safe
    {
        _actions[name] = action;
    }

    /**
    Remove the command with the given name.
    If the command does not exist, do nothing.

    Params:
        name = The name of the command to remove.
    */
    void unregisterQCMD(string name) nothrow @safe
    {
        _qcmds.remove(name);
    }

    /**
    Remove the variable with the given name.
    If the variable does not exist, do nothing.

    Params:
        name = The name of the variable to remove.
    */
    void unregisterQVAR(string name) nothrow @safe
    {
        _qvars.remove(name);
    }

    /**
    Remove the action with the given name.
    If the action does not exist, do nothing.

    Params:
        name = The name of the action to remove.
    */
    void unregisterAction(string name) nothrow @safe
    {
        _actions.remove(name);
    }

    /**
    Append text to the internal command buffer.

    Params:
        text = The text to append.
    */
    void append(string text) nothrow @safe @nogc
    {
        if (text.length == 0)
            return;

        int t = void;
    	
        foreach (char c; text)
        {   
            t = (_buffer.tail + 1) % _buffer.buffer.length; // New tail spot
        	
            assert(t != _buffer.head, "Qomproc Ring Buffer overflow!"); // Ring buffer is full
        	
            _buffer.buffer[t] = c;
            _buffer.tail = t;
        }

        if (text[$ - 1] != '\n' || text[$ - 1] != ';' || text[$ - 1] != '\0')
        {
            _buffer.buffer[t+1] = '\0';
            ++_buffer.tail;
        }
    }
	
    /**
    Insert some text into the internal command buffer, in front of any other queued text.
    
    Params:
        text = The text to insert.
    */
    void insert(string text) nothrow @safe @nogc
    {
        if (text.length == 0)
            return;

        int h = void;
    	
        foreach_reverse (char c; text)
        {
            h = (_buffer.head - 1) < 0 ? _buffer.buffer.length - 1 : _buffer.head - 1; // New head spot @suppress(dscanner.suspicious.length_subtraction)
        	
            assert(h != _buffer.tail, "Qomproc Ring Buffer overflow!"); // Ring buffer is full
        	
            _buffer.buffer[h] = c;
            _buffer.head = h;
        }

        if (text[$ - 1] != '\n' || text[$ - 1] != ';' || text[$ - 1] != '\0')
        {
            _buffer.buffer[h-1] = '\0';
            --_buffer.head;
        }
    	
        --_buffer.head;
    }
	
    /**
    Execute a command string immediately, bypassing the internal command buffer.

    Params:
        text = The text to execute.
    */
    void execute(string text) nothrow
    {
        _cmdsrc = CommandSource.internal;
        _parse(text);
        _dispatch();
    }
	
    /**
    Performs one cycle, where the next command, if existant, will
    be fetched and executed from the internal command buffer.
    Alternatively waits if instructed to do so by the `wait` QCMD.
    */
    void cycle() nothrow
    {
        if (_suspendTimer > 0)
        {
            _suspendTimer--;
            return;
        }
    	
        if (_buffer.head != _buffer.tail)
        {
            _cmdsrc = CommandSource.buffer;
            _extract();
            _parse(_extracted);
            _dispatch();
        }
    }
	
    /**
    Executes all text still queued in the internal command buffer immediately,
    and cancels `wait` if previously instructed.
    */
    void flush() nothrow
    {
        while (_buffer.head != _buffer.tail)
        {
            _cmdsrc = CommandSource.buffer;
            _extract();
            _parse(_extracted);
            _dispatch();
        }

        _suspendTimer = 0;
    }

    /**
    Saves all key bindings, archived variables and aliases into the given file.
    
    Params:
        path = The path of the config file to write to.
    */
    void saveArchiveToFile(string path)
    {
        string escapeString(string input) pure const nothrow @safe
        {
            import std.string : replace;
            return input.replace("\"", "\\\"");
        }

        IVFSFile archive = VFS.getFile(path, "w");

        archive.write("# Qomproc script setting archived QVARs, key bindings and aliases\n\n");

        // Write key bindings
        archive.write("unbindall\n");
        foreach (int key, string command; InputServer.bindings)
            archive.write("bind \"" ~ InputServer.getNameForKey(key) ~ "\" \"" ~ escapeString(command) ~ "\"\n");

        // Write archived QVARs
        foreach (string name, ref QVAR qvar; _qvars)
            if (qvar._flags & QVAR.Flags.archive)
                archive.write(name ~ " \"" ~ escapeString(qvar.getValueAsString()) ~ "\"\n");

        // Write aliases
        archive.write("unaliasall\n");
        foreach (string name, string value; _aliases)
            archive.write("alias \"" ~ name ~ "\" \"" ~ escapeString(value) ~ "\"");

        archive.destroy();
    }

    /// Returns all registered commands.
    @property QCMD[string]* qcmds() { return &_qcmds; } // @suppress(dscanner.style.doc_missing_returns)

    /// Returns all registered variables.
    @property QVAR[string]* qvars() { return &_qvars; } // @suppress(dscanner.style.doc_missing_returns)

    /// Returns all registered actions.
    @property bool*[string]* actions() { return &_actions; } // @suppress(dscanner.style.doc_missing_returns)
    
    /// Returns all registered aliases.
    @property string[string]* aliases() { return &_aliases; } // @suppress(dscanner.style.doc_missing_returns)

private static:
    struct RingBuffer
    {
        int head, tail;
        char[8192] buffer = ' ';
    }

    IQomprocOutput[] _outputs;
    RingBuffer _buffer;

    string[] _cmdArgs;
    string _extracted;
    ushort _suspendTimer;

    QCMD[string] _qcmds;
    QVAR[string] _qvars;
    bool*[string] _actions; // Used for +forward/-forward for example.
    string[string] _aliases;

    CommandSource _cmdsrc;
    bool _printDispatch;

    void _extract() nothrow @safe
    {
        enum ParseState { start, token, quote, stop, comment }
        
        int i;
        char c;
        ParseState parse = ParseState.start;

        _extracted.length = 0;

        for (i = _buffer.head; parse != ParseState.stop; i = (i + 1) % _buffer.buffer.length)
        {
            c = _buffer.buffer[i];

            if (i == _buffer.tail)
            {
                --i;
                parse = ParseState.stop;
            }

            final switch (parse) with (ParseState)
            {
                case start:
                case token:
                    if (c == '\0' || c == '\n' || c == ';')
                        parse = stop;
                    else if (c == '#')
                        parse = comment;
                    else if (c == '"')
                        parse = quote;
                    break;

                case quote:
                    if (c == '\0' || c == '\n')
                        parse = stop;
                    else if (c == '"')
                        parse = start;
                    break;

                case comment:
                    if (c == '\0' || c == '\n')
                        parse = stop;
                    break;

                case stop:
                    break;
            }

            if (parse != ParseState.stop)
                _extracted ~= c;
        }
    	
        _buffer.head = i;
    }

    void _parse(string text) nothrow @safe
    {
        _cmdArgs.length = 0;
    	
        string currentToken;
        bool inQuotes;
    	
        void finishToken()
        {
            if (currentToken.length > 0)
            {
                _cmdArgs ~= currentToken;
                currentToken.length = 0;
                inQuotes = false;
            }
        }
    	
    parseLoop:
        for (size_t i; i < text.length; ++i)
        {
            char c = text[i];
        	
            switch (c)
            {
                case ' ':
                case '\t':
                    if (inQuotes)
                        goto default;
                	
                    finishToken();
                    break;
                	
                case '"':
                    inQuotes = !inQuotes;
                    break;

                case '#':
                    if (!inQuotes)
                        break parseLoop;
                    goto default;

                case '\\':
                    if (i >= text.length)
                        break parseLoop;

                    switch (text[++i])
                    {
                        case 'n': currentToken ~= '\n'; break;
                        case '"': currentToken ~= '"'; break;
                        case '\\': currentToken ~= '\\'; break;
                        default:
                            break;
                    }
                    break;
                	
                default:
                    currentToken ~= c;
            }
        }
    	
        finishToken();
    }

    void _dispatch() nothrow
    {
        if (_cmdArgs.length == 0 || _cmdArgs[0].length == 0)
            return;

        try
        {
            foreach (string aliasName, string aliasValue; _aliases)
                if (_cmdArgs[0] == aliasName)
                    _cmdArgs[0] = aliasValue;
        }
        catch (Exception ex) {}
    	
        if (_printDispatch)
        {
            import std.array : join;
            Qomproc.println("DISPATCH> " ~ _cmdArgs.join(" "));
        }

        // Syntax sugar for help command
        if (_cmdArgs[0][$-1] == '?')
        {
            execute("help " ~ _cmdArgs[0][0 .. $-1]);
            return;
        }
    	
        // Dispatch action
        if (_cmdArgs[0][0] == '+' || _cmdArgs[0][0] == '-')
        {
            string action = _cmdArgs[0][1 .. $];
            bool** value = action in _actions;
        	
            if (!value)
                printfln("Unknown action: %s".tr, action);
            else
                **value = _cmdArgs[0][0] == '+';
        	
            return;
        }
    	
        // Dispatch QCMD
        if (QCMD* ccmd = _cmdArgs[0] in _qcmds)
        {
            try
            {
                ccmd._callback(_cmdArgs, _cmdsrc);
            }
            catch (Exception ex)
            {
                printfln("%s failed: %s".tr, _cmdArgs[0], ex.msg);
            }
        	
            return;
        }
    	
        // Dispatch QVAR
        if (QVAR* cvar = _cmdArgs[0] in _qvars)
        {
            if (_cmdArgs.length == 1) // query value
                printfln("'%s' is '%s'".tr, _cmdArgs[0], cvar.getValueAsString());
            else // assign value
            {
                if (cvar._flags & cvar.Flags.readOnly)
                {
                    println("Assign failed: QVAR is read only.".tr);
                    return;
                }
            	
                try
                {
                    cvar._setValueFromString(_cmdArgs[1]);
                    
                    if (cvar._callback)
                        cvar._callback(cvar._value);
                }
                catch (ConvException ex)
                {
                    printfln("Assign failed: Expected value of type %s.".tr, cvar._type);
                }
                catch (Exception ex)
                {
                    printfln("Assign failed: %s".tr, ex.msg);
                }
            }
        	
            return;
        }
    	
        // None of the above
        printfln("Unknown command: %s".tr, _cmdArgs[0]);
    }
}