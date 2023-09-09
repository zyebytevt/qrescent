module qrescent.resources.material;

import std.exception : collectException;

import sdlang;

import qrescent.core.servers.language : tr;
import qrescent.core.engine;
import qrescent.core.vfs;
import qrescent.core.qomproc;
import qrescent.resources.loader;
import qrescent.resources.texture;
import qrescent.resources.shader;

/**
A material is used for rendering meshes. It contains various textures
and a `ShaderProgram`.
*/
class Material : Resource
{
public:
    /// Flags used to give shaders a hint on which textures are used.
    enum TextureUseFlags : uint
    {
        albedo = 1,
        normal = 1<<1
    }

    ShaderProgram shader; /// The shader to render the mesh with.
    float shineDamper = 5; /// How much reflected light is dampened.
    float reflectivity = 0.2; /// How reflective the surface is.

    /// The texture to use as albedo.
    @property Texture2D albedo() @safe nothrow @nogc { return _albedo; }
    /// ditto
    @property void albedo(Texture2D value) @safe nothrow @nogc
    {
        _albedo = value;

        if (value) _texUseFlags |= TextureUseFlags.albedo;
        else _texUseFlags &= ~TextureUseFlags.albedo;
    }
    
    /// The texture to use as normal.
    @property Texture2D normal() @safe nothrow @nogc { return _normal; }
    /// ditto
    @property void normal(Texture2D value) @safe nothrow @nogc
    {
        _normal = value;
        
        if (value) _texUseFlags |= TextureUseFlags.normal;
        else _texUseFlags &= ~TextureUseFlags.normal;
    }

    @property uint texUseFlags() @safe const nothrow @nogc { return _texUseFlags; }

private:
    Texture2D _albedo;
    Texture2D _normal;
    uint _texUseFlags;
}

// ===== MATERIAL LOADER FUNCTION =====

package:

Resource resLoadMaterial(string path)
{
    Tag root;

    { // Parse definition file
        scope IVFSFile file;
        if (Exception ex = collectException(VFS.getFile(path), file))
        {
            Qomproc.printfln("Failed to load material '%s': %s".tr, path, ex.msg);
            file = VFS.getFile(EngineCore.projectSettings.fallbackMaterial);
        }
        char[] source = new char[file.size];
        file.read(source);

        root = parseSource(cast(string) source, path);
    }

    Material material = new Material();

    if (string texPath = root.getTagValue!string("albedo"))
        material.albedo = cast(Texture2D) ResourceLoader.load(texPath);

    if (string texPath = root.getTagValue!string("normal"))
        material.normal = cast(Texture2D) ResourceLoader.load(texPath);

    material.shader = cast(ShaderProgram)
        ResourceLoader.load(root.getTagValue!string("shader", EngineCore.projectSettings.fallbackShader));

    material.shineDamper = root.getTagValue!float("shine-damper", 5f);
    material.reflectivity = root.getTagValue!float("reflectivity", 0.2f);

    return material;
}