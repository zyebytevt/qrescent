module qrescent.components.transform;

import std.algorithm : remove;
import std.string : format;

import sdlang;
import gl3n.linalg;

import qrescent.ecs;
import qrescent.ecs.utils;
import qrescent.core.exceptions;
import qrescent.core.servers.language : tr;

/**
The Transform2DComponent, if attached, will give an entity a 2D
world transformation. This is a base component necessary for most
other components.
*/
@component struct Transform2DComponent
{
public:
	vec2 translation = vec2(0, 0); /// The translation of this transform.
	float rotation = 0; /// The rotation of this transform, in radians.
	vec2 scale = vec2(1, 1); /// The scaling of this transform.
	int zIndex = 0; /// The layer of the transform. Lower values are above others.

	/**
	Calculates a transformation matrix with this transform's properties alone.

	Returns: The local transformation matrix.
	*/
	@property mat4 localMatrix() pure
	{
		return mat4.translation(translation.x, translation.y, 0)
			* mat4.rotation(-rotation, vec3(0, 0, 1))
			* mat4.scaling(scale.x, scale.y, 1);
	}

	/**
	Calculates a transformation matrix and multiplies it with the ones
	of it's parents.

	Returns: The global transformation matrix.
	*/
	@property mat4 globalMatrix() pure
	{
		if (_parent)
			return _parent.globalMatrix * localMatrix;
		else
			return localMatrix;
	}

	/**
	Convert a position from global to local space.

	Params:
		globalPoint = The position in global space.

	Returns: The position in local space.
	*/
	vec2 globalToLocalPosition(vec2 globalPoint) pure
	{
		/*mat4 inverseTransform;
		if (scale.x == scale.y)
			inverseTransform = globalMatrix.transposed;
		else
			inverseTransform = globalMatrix.inverse;*/

		return (globalMatrix.inverse * vec4(globalPoint, 0, 1)).xy;
	}

	/**
	Convert a position from local to global space.

	Params:
		localPoint = The position in local space.

	Returns: The position in global space.
	*/
	vec2 localToGlobalPosition(vec2 localPoint) pure
	{
		return (globalMatrix * vec4(localPoint, 0, 1)).xy;
	}

	/// The parent of this transform.
	@property Transform2DComponent* parent() pure nothrow { return _parent; } // @suppress(dscanner.style.doc_missing_returns)

	/**
	The parent of this transform.

	Throws: `ComponentException` in case of cyclic transform parenting.
	*/
	@property void parent(Transform2DComponent* parent) // @suppress(dscanner.style.doc_missing_params)
	{
		// Check if we ourselves are a parent of our future parent
		Transform2DComponent* check = parent;
		while (check)
		{
			enforce!ComponentException(check != &this, "Cyclic Transform2D parenting! (&this = %08X, parent = %08X).".tr
				.format(&this, parent));
			check = check._parent;
		}

		// If a parent exists, we need to remove us from there.
		if (_parent)
		{
			for (size_t i; i < _parent._children.length; ++i)
				if (_parent._children[i] == &this)
				{
					_parent._children.remove(i);
					break;
				}
		}

		_parent = parent;
		if (_parent) // In case parent is not null
			parent._children ~= &this;
	}

	/**
	Get the child of this transform with the given index.

	Params:
		index = The index of the child to get.

	Returns: Pointer to the Transform2DComponent child.
	Throws: `RangeError` with an invalid index.
	*/
	Transform2DComponent* getChild(size_t index) pure nothrow @nogc
	{
		return _children[index];
	}

	/// The amount of children this transform has.
	@property size_t childrenCount() const pure nothrow @nogc // @suppress(dscanner.style.doc_missing_returns)
	{
		return _children.length;
	}

	/**
	Registers this component to the given entity, with values from a SDLang tag.

	Params:
		root = The root SDLang tag that describes this component.
		entity = The entity to register this component to.
		isOverride = `true` if overriding attributes of an already existing component,
		`false` otherwise.

	Throws: `SceneException` if the entity already has a Transform3DComponent.
	*/
	static void loadFromTag(Tag root, Entity entity, bool isOverride)
	{
		if (!isOverride)
		{
			// Check for incompatible Transform3DComponent on entity
			import std.exception : enforce;
			import qrescent.core.exceptions : SceneException;
			enforce!SceneException(!entity.isRegistered!Transform3DComponent,
				"Cannot add Transform2D on entity with a Transform3D.".tr);
		}

		Transform2DComponent* component = entity.getComponent!Transform2DComponent(isOverride);

		setAttribute(root, "translation", &component.translation, isOverride);
		setAttribute(root, "rotation", &component.rotation, isOverride);
		setAttribute(root, "scale", &component.scale, isOverride);
		setAttribute(root, "z-index", &component.zIndex, true);
	}

private:
	Transform2DComponent* _parent;
	Transform2DComponent*[] _children;
}

// ==============================================================================

/**
The Transform3DComponent, if attached, will give an entity a 3D
world transformation. This is a base component necessary for most
other components.
*/
@component struct Transform3DComponent
{
public:
	vec3 translation = vec3(0, 0, 0); /// The translation of this transform.
	quat rotation = quat.identity; /// The rotation of this transform, as a quaternion.
	vec3 scale = vec3(1, 1, 1); /// The scaling of this transform.

	/**
	Calculates a transformation matrix with this transform's properties alone.

	Returns: The local transformation matrix.
	*/
	@property mat4 localMatrix() pure
	{
		return mat4.translation(translation.x, translation.y, translation.z)
			* rotation.to_matrix!(4, 4)
			* mat4.scaling(scale.x, scale.y, scale.z);
	}

	/**
	Calculates a transformation matrix and multiplies it with the ones
	of it's parents.

	Returns: The global transformation matrix.
	*/
	@property mat4 globalMatrix() pure
	{
		if (_parent)
			return _parent.globalMatrix * localMatrix;
		else
			return localMatrix;
	}

	/**
	Convert a position from global to local space.

	Params:
		globalPoint = The position in global space.

	Returns: The position in local space.
	*/
	vec3 globalToLocalPosition(vec3 globalPoint) //pure
	{
		/*mat4 inverseTransform;
		if (scale.x == scale.y && scale.y == scale.z)
			inverseTransform = globalMatrix.transposed;
		else
			inverseTransform = globalMatrix.inverse;

		import qrescent.core.qomproc;

		Qomproc.printfln("Orig: %s\nTrans: %s\nInv: %s", globalMatrix, globalMatrix.transposed, globalMatrix.inverse);*/

		return (globalMatrix.inverse * vec4(globalPoint, 1)).xyz;
	}

	/**
	Convert a position from local to global space.

	Params:
		localPoint = The position in local space.

	Returns: The position in global space.
	*/
	vec3 localToGlobalPosition(vec3 localPoint) pure
	{
		return (globalMatrix * vec4(localPoint, 1)).xyz;
	}
	
	/// The parent of this transform.
	@property Transform3DComponent* parent() pure nothrow { return _parent; } // @suppress(dscanner.style.doc_missing_returns)

	/**
	The parent of this transform.

	Throws: `ComponentException` in case of cyclic transform parenting.
	*/
	@property void parent(Transform3DComponent* parent) // @suppress(dscanner.style.doc_missing_params)
	{
		// Check if we ourselves are a parent of our future parent
		Transform3DComponent* check = parent;
		while (check)
		{
			enforce!ComponentException(check != &this, "Cyclic Transform3D parenting! (&this = %08X, parent = %08X).".tr
				.format(&this, parent));
			check = check._parent;
		}

		// If a parent exists, we need to remove us from there.
		if (_parent)
		{
			for (size_t i; i < _parent._children.length; ++i)
				if (_parent._children[i] == &this)
				{
					_parent._children.remove(i);
					break;
				}
		}

		_parent = parent;
		if (_parent) // In case parent is not null
			parent._children ~= &this;
	}

	/**
	Get the child of this transform with the given index.

	Params:
		index = The index of the child to get.

	Returns: Pointer to the Transform3DComponent child.
	Throws: `RangeError` with an invalid index.
	*/
	Transform3DComponent* getChild(size_t index) pure nothrow
	{
		return _children[index];
	}

	/// The amount of children this transform has.
	@property size_t childrenCount() const pure nothrow @nogc // @suppress(dscanner.style.doc_missing_returns)
	{
		return _children.length;
	}

	/**
	Registers this component to the given entity, with values from a SDLang tag.

	Params:
		root = The root SDLang tag that describes this component.
		entity = The entity to register this component to.
		isOverride = `true` if overriding attributes of an already existing component,
		`false` otherwise.

	Throws: `SceneException` if the entity already has a Transform3DComponent.
	*/
	static void loadFromTag(Tag root, Entity entity, bool isOverride)
	{
		if (!isOverride)
		{
			// Check for incompatible Transform3DComponent on entity
			import std.exception : enforce;
			import qrescent.core.exceptions : SceneException;
			enforce!SceneException(!entity.isRegistered!Transform2DComponent,
				"Cannot add Transform3D on entity with a Transform2D.".tr);
		}

		Transform3DComponent* component = entity.getComponent!Transform3DComponent(isOverride);

		setAttribute(root, "translation", &component.translation, isOverride);
		setAttribute(root, "rotation", &component.rotation, isOverride);
		setAttribute(root, "scale", &component.scale, isOverride);
	}

private:
	Transform3DComponent* _parent;
	Transform3DComponent*[] _children;
}
