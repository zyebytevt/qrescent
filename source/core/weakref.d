module qrescent.core.weakref;

import core.memory;
import core.atomic;

// Weak references reimplemented and fitted for Qrescent from unstd

/**
Detect whether a weak reference to type $(D T) can be created.

A weak reference can be created for a $(D class), $(D interface), or $(D delegate).

Warning:
$(D delegate) context must be a class instance.
I.e. creating a weak reference for a $(D delegate) created from a $(D struct)
member function will result in undefined behavior.

$(RED Weak reference will not work for closures) unless enhancement $(DBUGZILLA 9601)
is implemented as now regular D objects aren't created on closures.
*/
enum isWeakReferenceable(T) = is(T == class) || is(T == interface) || is(T == delegate);

/**
Implements weak reference.

Note: The class contains a pointer to a target object thus it behaves as
a normal reference if placed in GC block without $(D NO_SCAN) attribute.

Tip: This behaves like C#'s short weak reference or Java's weak reference.
*/
final @trusted class WeakReference(T)
if(isWeakReferenceable!T)
{
	/* Create weak reference for $(D target).

	Preconditions:
	$(D target !is null)
	*/
	this(T target)
	in { assert(target); }
	body
	{
		_data.target = target;
		rt_attachDisposeEvent(_targetToObj(target), &onTargetDisposed);
	}

	/// Determines whether referenced object is finalized.
	@property bool alive() const pure nothrow @nogc
	{ return !!atomicLoad(_data.ptr); }

	/**
	Returns referenced object if it isn't finalized
	thus creating a strong reference to it.
	Returns null otherwise.
	*/
	@property inout(T) target() inout nothrow
	{
		return _data.getTarget();
	}

	~this()
	{
		if(T t = target)
		{
			rt_detachDisposeEvent(_targetToObj(t), &onTargetDisposed);
		}
	}

private:
	shared ubyte[T.sizeof] _dataStore;

	@property ref inout(_WeakData!T) _data() inout pure nothrow @nogc
	{
		return _dataStore.viewAs!(_WeakData!T);
	}

	void onTargetDisposed(Object) pure nothrow @nogc
	{
		atomicStore(_data.ptr, cast(shared void*) null);
	}
}

/// Convenience function that returns a $(D WeakReference!T) object for $(D target).
@safe WeakReference!T weakReference(T)(T target)
if(isWeakReferenceable!T)
{
	return new WeakReference!T(target);
}


private:

alias DisposeEvt = void delegate(Object);

extern(C)
{
	Object _d_toObject(void* p) pure nothrow @nogc;
	void rt_attachDisposeEvent(Object obj, DisposeEvt evt);
	void rt_detachDisposeEvent(Object obj, DisposeEvt evt);
}

union _WeakData(T)
if(isWeakReferenceable!T)
{
	T target;
    shared void* ptr;

	// Returns referenced object if it isn't finalized.
	@property inout(T) getTarget() inout nothrow
	{
		auto ptr = cast(inout shared void*) atomicLoad(/*de-inout*/(cast(const) this).ptr);
		if(!ptr)
			return null;

		// Note: this is an implementation dependent GC fence as there
		// is no guarantee `addrOf` will really lock GC mutex.
		GC.addrOf(cast(void*) -1);

		// We have strong reference to ptr here so just test
		// whether we are still alive:
		if(!atomicLoad(/*de-inout*/(cast(const) this).ptr))
			return null;

		// We have to use obtained reference to ptr in result:
        inout _WeakData res = { ptr: ptr };
		return res.target;
	}
}

inout(Object) _targetToObj(T)(inout T t) @trusted pure nothrow @nogc
if(is(T == class) || is(T == interface))
{ return cast(inout(Object)) t; }

@property inout(To) viewAs(To, From)(inout(From) val) @system @nogc
{
	return val.viewAs!To;
}

/// ditto
@property ref inout(To) viewAs(To, From)(ref inout(From) val) @system @nogc
{
	static assert(To.sizeof == From.sizeof,
		format("Type size mismatch in `viewAs`: %s.sizeof(%s) != %s.sizeof(%s)",
		To.stringof, To.sizeof, From.stringof, From.sizeof));
	return *cast(inout(To)*) &val;
}