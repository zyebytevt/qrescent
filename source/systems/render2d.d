module qrescent.systems.render2d;

import std.algorithm : sort;
import std.typecons : Tuple;
import std.conv : to;

import derelict.opengl;
import gl3n.linalg;
import sdlang;

import qrescent.ecs;
import qrescent.components.camera;
import qrescent.components.sprite;
import qrescent.components.transform;
import qrescent.components.text;
import qrescent.components.light;
import qrescent.resources.shader;
import qrescent.resources.mesh;
import qrescent.resources.texture;
import qrescent.resources.material;

/// Handles the rendering of the 2D world.
class Render2DSystem : System
{
public:
    /// Registers this system to the system manager, with values from a SDLang tag.
	static void loadFromTag(Tag tag, SystemManager manager)
	{
        manager.register(new Render2DSystem());
    }

protected:
    alias renderobj_t = Tuple!(Mesh, "mesh", Texture, "texture", mat4, "transformMatrix", int, "zIndex",
        ShaderProgram, "shader");

    alias light_t = Tuple!(vec3, "position", vec3, "color", vec3, "attenuation");

    override void run(EntityManager entities, EventManager events, Duration dt)
    {
        static renderobj_t[512] renderObjects;
        size_t renderObjectsCount;

        glDisable(GL_DEPTH_TEST);

        mat4 projectionMatrix, viewMatrix;
        bool foundCamera;

        foreach (Entity entity, Transform2DComponent* transform, CameraComponent* camera;
            entities.entitiesWith!(Transform2DComponent, CameraComponent))
        {
            if (camera.active)
            {
                viewMatrix = transform.globalMatrix.inverse;
                projectionMatrix = camera.getProjectionMatrix();
                foundCamera = true;
                break;
            }
        }

        if (!foundCamera)
            return;

        light_t[20] lights;
        uint lightsCount;

        foreach (Entity entity, Transform2DComponent* transform, LightComponent* light;
            entities.entitiesWith!(Transform2DComponent, LightComponent))
        {
            lights[lightsCount].position = vec3(transform.translation, 0.01f);
            lights[lightsCount].attenuation = light.attenuation;
            lights[lightsCount++].color = light.color;
            
            if (lightsCount == lights.length)
                break;
        }

        foreach (Entity entity, Transform2DComponent* transform, SpriteComponent* sprite;
            entities.entitiesWith!(Transform2DComponent, SpriteComponent))
        {
            renderObjects[renderObjectsCount++] = renderobj_t(sprite.sprite.mesh, sprite.sprite.texture,
                transform.globalMatrix, transform.zIndex, sprite.shader);
        }

        foreach (Entity entity, Transform2DComponent* transform, TextComponent* text;
            entities.entitiesWith!(Transform2DComponent, TextComponent))
        {
            renderObjects[renderObjectsCount++] = renderobj_t(text.mesh, text.font.pages[0],
                transform.globalMatrix, transform.zIndex, text.shader);
        }

        foreach (ref renderobj_t renderObj; renderObjects[0 .. renderObjectsCount].sort!((a, b) => (a.zIndex < b.zIndex)))
        {
            renderObj.shader.bind();
            renderObj.texture.bind();
            renderObj.mesh.bind();

            renderObj.shader.setUniform("lightsCount", lightsCount);
            foreach (size_t i, light_t light; lights)
            {
                immutable string idx = "lights[" ~ i.to!string ~ "]";
                renderObj.shader.setUniform(idx ~ ".position", light.position);
                renderObj.shader.setUniform(idx ~ ".attenuation", light.attenuation);
                renderObj.shader.setUniform(idx ~ ".color", light.color);
            }

            renderObj.shader.setUniform("texUseFlags", cast(uint) Material.TextureUseFlags.albedo);
            renderObj.shader.setUniform("projection", projectionMatrix);
            renderObj.shader.setUniform("view", viewMatrix);
            renderObj.shader.setUniform("transform", renderObj.transformMatrix);

            renderObj.mesh.draw();
        }
    }
}