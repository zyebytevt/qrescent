module qrescent.components.sprite;

import sdlang;
import gl3n.linalg;

import qrescent.ecs;
import qrescent.ecs.utils;
import qrescent.core.engine;
import qrescent.resources.loader;
import qrescent.resources.texture;
import qrescent.resources.shader;
import qrescent.resources.sprite;

/**
The SpriteComponent, if attached, will render a sprite with the
entity's current transform.
*/
@component struct SpriteComponent
{
public:
    Sprite sprite; /// The sprite used for rendering.
    ShaderProgram shader; /// The shader used for rendering.

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
        SpriteComponent* component = entity.getComponent!SpriteComponent(isOverride);

        setAttribute(root, "sprite", &component.sprite, isOverride);
        setAttribute(root, "shader", &component.shader, isOverride);
	}
}