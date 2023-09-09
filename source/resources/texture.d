module qrescent.resources.texture;

import std.exception : collectException;

import sdlang;
import derelict.opengl;
import imageformats;

import qrescent.core.servers.language : tr;
import qrescent.core.vfs;
import qrescent.core.qomproc;
import qrescent.core.engine;
import qrescent.resources.loader;

/**
Struct used for texture loading and initialization.
*/
struct TextureSettings
{
    /// Types of minifying functions
    enum MinFilter
    {
        nearest = GL_NEAREST,
        linear = GL_LINEAR,
        nearestMipmapNearest = GL_NEAREST_MIPMAP_NEAREST,
        linearMipmapNearest = GL_LINEAR_MIPMAP_NEAREST,
        nearestMipmapLinear = GL_NEAREST_MIPMAP_LINEAR,
        linearMipmapLinear = GL_LINEAR_MIPMAP_LINEAR
    }

    /// Types of magnifying functions
    enum MagFilter
    {
        nearest = GL_NEAREST,
        linear = GL_LINEAR
    }

    /// Types of texture wrapping
    enum TextureWrap
    {
        clampToEdge = GL_CLAMP_TO_EDGE,
        mirroredRepeat = GL_MIRRORED_REPEAT,
        repeat = GL_REPEAT
    }

    MinFilter minFilter = MinFilter.nearest; /// What magnifying function to use
    MagFilter magFilter = MagFilter.nearest; /// What minifying function to use
    TextureWrap wrapS = TextureWrap.repeat; /// How to wrap the texture in horizontal direction
    TextureWrap wrapT = TextureWrap.repeat; /// How to wrap the texture in vertical direction
    TextureWrap wrapR = TextureWrap.repeat; /// How to wrap the texture in depth (3D, Cubemap)
    bool generateMipmap = true; /// If mipmaps should be generated
}

/**
Represents a general OpenGL Texture, sharing functionalities common with
all texture types.
*/
abstract class Texture : Resource
{
public:
    /**
    Binds the texture for future use.

    Params:
        unit = On which unit index to bind the texture on.
    */
    abstract void bind(int unit = 0) const nothrow @trusted @nogc;

    /// The internal OpenGL texture id.
    @property final uint textureID() const nothrow @safe @nogc { return _textureID; } // @suppress(dscanner.style.doc_missing_returns)

    ~this()
    {
        if (_textureID > 0)
            glDeleteTextures(1, &_textureID);
    }

protected:
    uint _textureID;
}

/**
Represents a simple 2D texture.
*/
class Texture2D : Texture
{
public:
    this(IFImage img, TextureSettings settings = TextureSettings.init) nothrow @trusted @nogc
    {
        glGenTextures(1, &_textureID);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, _textureID);
    	
        GLenum mode = 0;
    	
        final switch (img.c)
        {
            case ColFmt.Y:
            case ColFmt.YA:
                mode = GL_ALPHA;
                break;
            	
            case ColFmt.RGB:
                mode = GL_RGB;
                break;
            	
            case ColFmt.RGBA:
                mode = GL_RGBA;
                break;
        }
    	
        glTexImage2D(GL_TEXTURE_2D, 0, mode, img.w, img.h, 0, mode, GL_UNSIGNED_BYTE, img.pixels.ptr);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, settings.wrapS);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, settings.wrapT);
    	
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, settings.minFilter);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, settings.magFilter);

        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_BASE_LEVEL, 0);
    	
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_LOD_BIAS, -1);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, settings.generateMipmap ? 100 : 0);

        if (settings.generateMipmap)
        {
            glEnable(GL_TEXTURE_2D); // Because of a bug in certain ATI drivers
            glGenerateMipmap(GL_TEXTURE_2D);
        }
    	
        _width = img.w;
        _height = img.h;
    }

    /**
    Binds the texture for future use.

    Params:
        unit = On which unit index to bind the texture on.
    */
    override void bind(int unit = 0) const nothrow @trusted @nogc
    {
        debug assert(unit >= 0 && unit <= 31, "Invalid texture unit.");
    	
        glActiveTexture(GL_TEXTURE0 + unit);
        glBindTexture(GL_TEXTURE_2D, _textureID);
    }
	
    /**
    Unbinds any currently bound 2D texture.

    Params:
        unit = On which unit index to unbind a texture from.
    */
    static void unbind(int unit = 0) nothrow @trusted @nogc
    {
        debug assert(unit >= 0 && unit <= 31, "Invalid texture unit.");
    	
        glActiveTexture(GL_TEXTURE0 + unit);
        glBindTexture(GL_TEXTURE_2D, 0);
    }

    /// The width of the texture, in pixels.
    @property int width() const nothrow @safe @nogc { return _width; } // @suppress(dscanner.style.doc_missing_returns)
    /// The height of the texture, in pixels.
    @property int height() const nothrow @safe @nogc { return _height; } // @suppress(dscanner.style.doc_missing_returns)
	
private:
    int _width, _height;
}

/**
Represents a cube map, e.g. a collection of six textures that maps
all sides of a cube. Useful for skyboxes.
*/
class TextureCubeMap : Texture
{
public:
    this(IFImage[6] images, TextureSettings settings = TextureSettings.init) nothrow @trusted// @nogc
    {
        glGenTextures(1, &_textureID);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_CUBE_MAP, _textureID);

        for (int i; i < 6; ++i)
        {
            IFImage img = images[i];

            GLenum mode = 0;
    	
            final switch (img.c)
            {
                case ColFmt.Y:
                case ColFmt.YA:
                    mode = GL_ALPHA;
                    break;
                    
                case ColFmt.RGB:
                    mode = GL_RGB;
                    break;
                    
                case ColFmt.RGBA:
                    mode = GL_RGBA;
                    break;
            }
            
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, GL_RGBA, img.w, img.h, 0, mode, GL_UNSIGNED_BYTE,
                img.pixels.ptr);
        }

        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, settings.wrapS);
        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, settings.wrapT);
        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, settings.wrapR);

        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, settings.magFilter);
        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, settings.minFilter);

        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_BASE_LEVEL, 0);

        glTexParameterf(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_LOD_BIAS, -1);
        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAX_LEVEL, settings.generateMipmap ? 100 : 0);

        if (settings.generateMipmap)
        {
            glEnable(GL_TEXTURE_CUBE_MAP); // Because of a bug in certain ATI drivers
            glGenerateMipmap(GL_TEXTURE_CUBE_MAP);
        }
    }

    /**
    Binds the texture for future use.

    Params:
        unit = On which unit index to bind the texture on.
    */
    override void bind(int unit = 0) const nothrow @trusted @nogc
    {
        debug assert(unit >= 0 && unit <= 31, "Invalid texture unit.");
    	
        glActiveTexture(GL_TEXTURE0 + unit);
        glBindTexture(GL_TEXTURE_CUBE_MAP, _textureID);
    }
	
    /**
    Unbinds any currently bound 2D texture.

    Params:
        unit = On which unit index to bind the texture on.
    */
    static void unbind(int unit = 0) nothrow @trusted @nogc
    {
        debug assert(unit >= 0 && unit <= 31, "Invalid texture unit.");
    	
        glActiveTexture(GL_TEXTURE0 + unit);
        glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
    }
}

// ===== TEXTURE2D LOADER FUNCTION =====

package:

Resource resLoadTexture2D(string path)
{
    scope IVFSFile file;
    if (Exception ex = collectException(VFS.getFile(path), file))
    {
        Qomproc.printfln("Failed to load texture '%s': %s".tr, path, ex.msg);
        file = VFS.getFile(EngineCore.projectSettings.fallbackTexture);
    }
    ubyte[] data = new ubyte[file.size];
    file.read(data);

    IFImage img = read_image_from_mem(data);

    return new Texture2D(img);
}

Resource resLoadCubeMapTexture(string path)
{
    Tag root;

    { // Parse definition file
        scope IVFSFile file = VFS.getFile(path);
        char[] source = new char[file.size];
        file.read(source);

        root = parseSource(cast(string) source, path);
    }

    IFImage readTextureData(string path)
    {
        scope IVFSFile file = VFS.getFile(path);
        ubyte[] data = new ubyte[file.size];
        file.read(data);

        return read_image_from_mem(data);
    }

    IFImage[6] sides;
    sides[0] = readTextureData(root.expectTagValue!string("positive-x"));
    sides[1] = readTextureData(root.expectTagValue!string("negative-x"));
    sides[2] = readTextureData(root.expectTagValue!string("positive-y"));
    sides[3] = readTextureData(root.expectTagValue!string("negative-y"));
    sides[4] = readTextureData(root.expectTagValue!string("positive-z"));
    sides[5] = readTextureData(root.expectTagValue!string("negative-z"));

    return new TextureCubeMap(sides);
}