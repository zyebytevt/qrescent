module qrescent.components.mesh;

import sdlang;

import qrescent.ecs;
import qrescent.ecs.utils;
import qrescent.core.engine;
import qrescent.resources.loader;
import qrescent.resources.mesh;
import qrescent.resources.shader;
import qrescent.resources.material;

/**
The MeshComponent, when attached, will cause the specified mesh to be rendered
with the entity's current transform.
*/
@component struct MeshComponent
{
    Mesh mesh; /// The mesh to render.
    Material material; /// The material used to render the mesh.

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
        MeshComponent* component = entity.getComponent!MeshComponent(isOverride);

        setAttribute(root, "material", &component.material, isOverride);
		setAttribute(root, "mesh", &component.mesh, isOverride);
	}
}