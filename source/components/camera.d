module qrescent.components.camera;

import gl3n.linalg;
import sdlang;

import qrescent.ecs;
import qrescent.ecs.utils;
import qrescent.components.transform;
import qrescent.resources.loader;
import qrescent.resources.texture : TextureCubeMap;

/**
The CameraComponent, when attached, will set the current entity as
a possible viewpoint in 2D or 3D space, depending on the type of
transform component.
*/
@component struct CameraComponent
{
	/// Possible projection modes for a camera.
	enum ProjectionMode
	{
		orthographic,
		perspective
	}

	float width; /// The width of the viewport.
	float height; /// The height of the viewport.
	float near = -1; /// The near clip distance of the viewport.
	float far = 1; /// The far clip distance of the viewport.
	ProjectionMode mode; /// The mode of this camera, either orthographic or perspective.
	float fov = 90; /// The field of vision of the viewport, in degrees.
	bool active; /// If this camera is currently the active one.
	TextureCubeMap skybox; /// The texture to use as the skybox.

	/**
	Calculates a projection matrix depending on the projection mode of the camera.
	Returns: The projection matrix.
	*/
	mat4 getProjectionMatrix() const
	{
		final switch (mode) with (ProjectionMode)
		{
			case orthographic:
				return mat4.orthographic(0, width, height, 0, near, far);

			case perspective:
				return mat4.perspective(width, height, fov, near, far);
		}
	}

	/**
	Registers this component to the given entity, with values from a SDLang tag.

	Params:
		root = The root SDLang tag that describes this component.
		entity = The entity to register this component to.
		isOverride = `true` if overriding attributes of an already existing component,
		`false` otherwise.
	*/
	static void loadFromTag(Tag root, Entity entity, bool isOverride)
	{
		CameraComponent* component = entity.getComponent!CameraComponent(isOverride);

		setAttribute(root, "width", &component.width, isOverride);
		setAttribute(root, "height", &component.height, isOverride);
		setAttribute(root, "near", &component.near, true);
		setAttribute(root, "far", &component.far, true);
		setAttribute(root, "fov", &component.fov, true);
		setAttribute(root, "active", &component.active, isOverride);
		setAttribute(root, "mode", &component.mode, isOverride);
		setAttribute(root, "skybox", &component.skybox, true);
	}
}