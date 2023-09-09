module qrescent.components.light;

import gl3n.linalg;
import sdlang;

import qrescent.ecs;
import qrescent.ecs.utils;

/**
The LightComponent, when attached, will emit light from the entity.
*/
@component struct LightComponent
{
    vec3 color; /// The color of the light.
	vec3 attenuation; /// The attenuation of the light.

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
        LightComponent* component = entity.getComponent!LightComponent(isOverride);

        setAttribute(root, "color", &component.color, isOverride);
		setAttribute(root, "attenuation", &component.attenuation, isOverride);
	}
}