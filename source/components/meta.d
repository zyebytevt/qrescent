module qrescent.components.meta;

import std.variant : Variant;
import std.exception : enforce;

import qrescent.ecs.component;

/**
The MetaComponent component is not a real component per se, but
rather a dummy component that holds meta data associated with
individual entities. If an entity has no meta data defined,
no MetaComponent will be attached to it.
*/
@component struct MetaComponent
{
public:
    /**
    Set the meta value with the given name to a new value.

    Params:
        name = The name of the meta value.
        value = The new value.
    */
    void set(T)(string name, T value)
    {
        _metadata[name] = value;
    }

    /// ditto
    void set(string name, Variant value)
    {
        _metadata[name] = value;
    }

    /**
    Gets the meta value with the given name.

    Params:
        T = The type the value should be returned as.
        name = The name of the meta value.

    Returns: The associated value.
    Throws: `RangeError` if no meta value with `name` exists. 
    */
    T get(T)(string name)
    {
        return _metadata[name].coerce!T;
    }

    /**
    Checks if a meta value with the given name exists.

    Params:
        name = The name of the meta value.
    Returns: `true` if such a meta value exists, `false` otherwise.
    */
    bool has(string name)
    {
        return (name in _metadata) !is null;
    }

    /**
    Removes a meta value. If no meta value of such name exists,
    do nothing.

    Params:
        name = The name of the meta value.
    */
    void remove(string name) nothrow
    {
        _metadata.remove(name);
    }

private:
    Variant[string] _metadata;
}