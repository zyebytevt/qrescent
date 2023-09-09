module qrescent.resources.sprite;

import std.exception : collectException;

import sdlang;
import gl3n.linalg;

import qrescent.core.servers.language : tr;
import qrescent.core.vfs;
import qrescent.core.engine;
import qrescent.core.qomproc;
import qrescent.resources.loader;
import qrescent.resources.mesh;
import qrescent.resources.texture;

/**
A sprite is a convenience class that holds a reference
to a texture and a mesh of the texture's size to render it.
*/
class Sprite : Resource
{
public:
    /**
    Constructs a new sprite.

    Params:
        texture = The texture to use for rendering.
        origin = The origin used for transform offset.
    */
    this(Texture2D texture, vec2 origin = vec2(0, 0))
    {
        _texture = texture;
        _origin = origin;

        Vertex[] vertices = [
            Vertex(vec3(-_origin.x, -_origin.y, 0), vec2(0, 0)),
            Vertex(vec3(-_origin.x, _texture.height - _origin.y, 0), vec2(0, 1)),
            Vertex(vec3(_texture.width - _origin.x, _texture.height - _origin.y, 0), vec2(1, 1)),
            Vertex(vec3(_texture.width - _origin.x, -_origin.y, 0), vec2(1, 0))
        ];

        static uint[] indices = [
            3, 0, 1,
            3, 1, 2
        ];

        _mesh = new Mesh(vertices, indices);
    }

    ~this()
    {
        _mesh.destroy();
    }

    /// The texture used for rendering the sprite.
    @property Texture2D texture() pure nothrow @nogc { return _texture; } // @suppress(dscanner.style.doc_missing_returns)
    /// The origin used for transform offset.
    @property vec2 origin() pure nothrow @nogc { return _origin; } // @suppress(dscanner.style.doc_missing_returns)
    /// The mesh used for rendering the sprite.
    @property Mesh mesh() pure nothrow @nogc { return _mesh; } // @suppress(dscanner.style.doc_missing_returns)

private:
    Texture2D _texture;
    vec2 _origin;
    Mesh _mesh;
}

// ===== SPRITE LOADER FUNCTION =====

package:

Resource resLoadSprite(string path)
{
    Tag root;

    { // Parse definition file
        scope IVFSFile file;
        if (Exception ex = collectException(VFS.getFile(path), file))
        {
            Qomproc.printfln("Failed to load sprite '%s': %s".tr, path, ex.msg);
            file = VFS.getFile(EngineCore.projectSettings.fallbackSprite);
        }
        char[] source = new char[file.size];
        file.read(source);

        root = parseSource(cast(string) source, path);
    }

    Texture2D texture = cast(Texture2D) ResourceLoader.load(root.getTagValue!string("texture"));

    vec2 origin = vec2(0, 0);

    if (Tag originTag = root.getTag("origin"))
        origin = vec2(originTag.values[0].get!float, originTag.values[1].get!float);

    return new Sprite(texture, origin);
}