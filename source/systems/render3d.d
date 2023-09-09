module qrescent.systems.render3d;

import std.conv : to;
import std.typecons : Tuple;

import derelict.opengl;
import gl3n.linalg;
import sdlang;

import qrescent.ecs;
import qrescent.components.camera;
import qrescent.components.mesh;
import qrescent.components.transform;
import qrescent.components.light;
import qrescent.components.text;
import qrescent.components.sprite;
import qrescent.resources.loader;
import qrescent.resources.shader;
import qrescent.resources.texture;
import qrescent.resources.mesh;
import qrescent.resources.material;

/// Handles the rendering of the 3D world.
class Render3DSystem : System
{
public:
    /// Registers this system to the system manager, with values from a SDLang tag.
	static void loadFromTag(Tag tag, SystemManager manager)
	{
        manager.register(new Render3DSystem());
    }

    this()
    {
        _skyboxShader = cast(ShaderProgram) ResourceLoader.load("res://shaders/skybox.shd");
        
        _skyboxMesh = new Mesh([
            Vertex(vec3(-1, 1, -1)),
            Vertex(vec3(-1, -1, -1)),
            Vertex(vec3(-1, -1, 1)),
            Vertex(vec3(-1, 1, 1)),
            Vertex(vec3(1, 1, -1)),
            Vertex(vec3(1, -1, -1)),
            Vertex(vec3(1, -1, 1)),
            Vertex(vec3(1, 1, 1))
        ],
        [
            0, 1, 5, 5, 4, 0,
            2, 1, 0, 0, 3, 2,
            5, 6, 7, 7, 4, 5,
            2, 3, 7, 7, 6, 2,
            0, 4, 7, 7, 3, 0,
            1, 2, 5, 5, 2, 6
        ]);
    }

protected:
    alias renderobj_t = Tuple!(Mesh, "mesh", Texture, "albedo", Texture, "normal", uint, "texUseFlags",
        mat4, "transformMatrix", ShaderProgram, "shader", float, "shineDamper", float, "reflectivity");

    alias light_t = Tuple!(vec3, "position", vec3, "color", vec3, "attenuation");

    Mesh _skyboxMesh;
    ShaderProgram _skyboxShader;

    override void run(EntityManager entities, EventManager events, Duration dt)
    {
        static renderobj_t[512] renderObjects;
        size_t renderObjectsCount;

        glEnable(GL_DEPTH_TEST);

        mat4 projectionMatrix, viewMatrix;
        TextureCubeMap skybox;
        bool foundCamera;

        foreach (Entity entity, Transform3DComponent* transform, CameraComponent* camera;
            entities.entitiesWith!(Transform3DComponent, CameraComponent))
        {
            if (camera.active)
            {
                viewMatrix = transform.globalMatrix.inverse;
                projectionMatrix = camera.getProjectionMatrix();
                skybox = camera.skybox;
                foundCamera = true;
                break;
            }
        }

        if (!foundCamera)
            return;

        if (skybox)
            _renderSkybox(projectionMatrix, viewMatrix, skybox);

        light_t[20] lights;
        uint lightsCount;

        foreach (Entity entity, Transform3DComponent* transform, LightComponent* light;
            entities.entitiesWith!(Transform3DComponent, LightComponent))
        {
            lights[lightsCount].position = transform.translation;
            lights[lightsCount].attenuation = light.attenuation;
            lights[lightsCount++].color = light.color;
            
            if (lightsCount == lights.length)
                break;
        }

        foreach (Entity entity, Transform3DComponent* transform, MeshComponent* mesh;
            entities.entitiesWith!(Transform3DComponent, MeshComponent))
        {
            renderObjects[renderObjectsCount++] = renderobj_t(mesh.mesh, mesh.material.albedo, mesh.material.normal,
                mesh.material.texUseFlags, transform.globalMatrix, mesh.material.shader, mesh.material.shineDamper,
                mesh.material.reflectivity);
        }

        foreach (Entity entity, Transform3DComponent* transform, TextComponent* text;
            entities.entitiesWith!(Transform3DComponent, TextComponent))
        {
            renderObjects[renderObjectsCount++] = renderobj_t(text.mesh, text.font.pages[0], null,
                cast(uint) Material.TextureUseFlags.albedo, transform.globalMatrix, text.shader, 0, 0);
        }

        foreach (Entity entity, Transform3DComponent* transform, SpriteComponent* sprite;
            entities.entitiesWith!(Transform3DComponent, SpriteComponent))
        {
            renderObjects[renderObjectsCount++] = renderobj_t(sprite.sprite.mesh, sprite.sprite.texture,
                null, cast(uint) Material.TextureUseFlags.albedo, transform.globalMatrix, sprite.shader, 0, 0);
        }

        foreach (ref renderobj_t renderObj; renderObjects[0 .. renderObjectsCount])
        {
            import std.conv : to;

            renderObj.shader.bind();
            if (renderObj.albedo) renderObj.albedo.bind(0);
            if (renderObj.normal) renderObj.normal.bind(1);
            renderObj.mesh.bind();

            renderObj.shader.setUniform("lightsCount", lightsCount);
            foreach (size_t i, light_t light; lights)
            {
                immutable string idx = "lights[" ~ i.to!string ~ "]";
                renderObj.shader.setUniform(idx ~ ".position", light.position);
                renderObj.shader.setUniform(idx ~ ".attenuation", light.attenuation);
                renderObj.shader.setUniform(idx ~ ".color", light.color);
            }

            renderObj.shader.setUniform("texUseFlags", renderObj.texUseFlags);
            renderObj.shader.setUniform("shineDamper", renderObj.shineDamper);
            renderObj.shader.setUniform("reflectivity", renderObj.reflectivity);
            renderObj.shader.setUniform("projection", projectionMatrix);
            renderObj.shader.setUniform("view", viewMatrix);
            renderObj.shader.setUniform("transform", renderObj.transformMatrix);

            renderObj.mesh.draw();
        }
    }

private:
    void _renderSkybox(mat4 projectionMatrix, mat4 viewMatrix, TextureCubeMap texture)
    {
        // Eliminate translation from the view matrix
        viewMatrix[0][3] = 0f;
        viewMatrix[1][3] = 0f;
        viewMatrix[2][3] = 0f;
        
        glDepthMask(GL_FALSE);

        texture.bind();
        _skyboxMesh.bind();
        _skyboxShader.bind();
        _skyboxShader.setUniform("projection", projectionMatrix);
        _skyboxShader.setUniform("view", viewMatrix);
        _skyboxMesh.draw();
        
        glDepthMask(GL_TRUE);
    }
}