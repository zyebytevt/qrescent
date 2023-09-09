module qrescent.core.qomproc.qvar;

import std.conv : to, ConvException;
import std.algorithm : canFind;

import qrescent.core.qomproc;

/**
Holds information about a Qomproc variable that can be changed by configuration
files or the user directly. It will take a memory address of a variable
in memory and modifies it accordingly.
*/
struct QVAR
{
public:
    @disable this();

    /// The type that callback delegates must use.
    alias callback_t = void function(void* value);
    alias uint_t = uint; /// QVAR's uint type.
    alias int_t = int; /// QVAR's int type.
    alias float_t = double; /// QVAR's floating type.
    alias string_t = string; /// QVAR's string type.
    alias bool_t = bool; /// QVAR's bool type.

    /// All value types a QVAR can hold.
    enum Type
    {
        uinteger, /// Unsigned integer (`uint_t`)
        integer, /// Integer (`int_t`)
        floating, /// Floating point (`float_t`)
        string, /// String (`string_t`)
        boolean /// Boolean (`bool_t`)
    }

    /// Flags associated with QVARs.
    enum Flags : uint
    {
        archive = 1, /// Variable is archived and will be saved.
        readOnly = 1 << 1 /// Variable cannot be modified.
    }

    /**
    Constructs a new instance.

    Params:
        value = Pointer to the value to be governed by this QVAR.
        description = The description of this variable that will be shown to the user.
        flags = Flags associated with this variable.
        callback = The callback called when the variable is changed.
    */
    this(T)(T* value, string description, uint flags = 0, callback_t callback = null) pure nothrow @nogc @safe
    {
        _flags = flags;
        _callback = callback;
        _description = description;

        static if(is(T == uint_t))
            _type = Type.uinteger;
        else static if(is(T == int_t))
            _type = Type.integer;
        else static if(is(T == float_t))
            _type = Type.floating;
        else static if(is(T == string_t))
            _type = Type.string;
        else static if(is(T == bool_t))
            _type = Type.boolean;
        else
            static assert(false, "A QVAR cannot hold a variable of type " ~ T.stringof);
    	
        _value = cast(void*) value;
    }

    /**
    Gets the value of this variable as a string, or "<qvar valstr error>" if
    converting fails.

    Returns: Value as a string.
    */
    string getValueAsString() const nothrow
    {
        template Case(Type T, U)
        {
            enum Case = "case " ~ T.stringof ~ ": return (*cast(" ~ U.stringof ~ "*) _value).to!string;";
        }
    	
        try
        {
            final switch (_type)
            {
                mixin(Case!(Type.uinteger, uint_t));
                mixin(Case!(Type.integer, int_t));
                mixin(Case!(Type.floating, float_t));
                mixin(Case!(Type.string, string_t));
                mixin(Case!(Type.boolean, bool_t));
            }
        }
        catch (Exception)
        {
            return "<qvar valstr error>";
        }
    }

package:
    Type _type;
    string _description;
    uint _flags;
    callback_t _callback;
    void* _value;

    void _setValueFromString(string value)
    {
        static immutable string[] trueValues = ["yes", "true", "on", "1"];
        static immutable string[] falseValues = ["no", "false", "off", "0"];

        template Case(Type T, U)
        {
            enum Case = "case " ~ T.stringof ~ ": *(cast(" ~ U.stringof ~ "*) _value) = value.to!"
                ~ U.stringof ~ "; break;";
        }
    	
        final switch (_type)
        {
            mixin(Case!(Type.uinteger, uint_t));
            mixin(Case!(Type.integer, int_t));
            mixin(Case!(Type.floating, float_t));
            mixin(Case!(Type.string, string_t));
        	
            case Type.boolean:
                if (trueValues.canFind(value))
                    *(cast(bool*) _value) = true;
                else if (falseValues.canFind(value))
                    *(cast(bool*) _value) = false;
                else
                    throw new ConvException("");
                break;
        }
    }
}