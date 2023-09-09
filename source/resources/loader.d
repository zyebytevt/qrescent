module qrescent.resources.loader;

import std.path : extension;
import std.exception : enforce, collectException;
import std.typecons : Tuple;
import std.string : format;

import qrescent.core.servers.language : tr;
import qrescent.core.exceptions;
import qrescent.core.weakref;
import qrescent.core.qomproc;

/**
The ResourceLoader is responsible for loading resources
from files into memory, and caching them for future access.
*/
struct ResourceLoader
{
    @disable this();
    @disable this(this);

public static:
    /// Function type for loading a specific Resource type.
    alias loaderfunc_t = Resource function(string path);

    /**
    Initializes the resource loader.
    */
    void initialize() // @suppress(dscanner.style.doc_missing_throw)
    {
        Qomproc.registerQCMD("cleancache", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
        {
            cleanCache();
        },
        "Cleans the resource cache from unused resources.".tr));

        Qomproc.registerQCMD("precache", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            // This works slightly different than the load() function, so it's reimplemented here.
            enforce!QomprocException(args.length > 1, "Expected file to pre-cache.".tr);

            string format = args.length > 2 ? args[2] : args[1].extension;

            loader_t* loader = format in _loaders;
            enforce!QomprocException(loader, "No loader available for '%s'.".tr.format(args[1]));
            enforce!QomprocException(loader.shouldCache, "Given resource isn't eligable for caching.".tr);

            if (_resourceCache.get(args[1], null))
                return;

            Resource resource = loader.func(args[1]);
            resource._path = args[1];
            _resourceCache[args[1]] = weakReference(resource);
        },
        "Precaches the given resource, optionally with the specified extension loader.".tr));
        
        Qomproc.registerQCMD("listcached", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            foreach (string key, weakref; _resourceCache)
                Qomproc.printfln(" %s  %s", weakref.alive ? "+" : "-", key);

            Qomproc.printfln("\n%d cached resources.".tr, _resourceCache.length);
        },
        "Lists all resources that are currently cached.".tr));
    }

    /**
    Load the resource at the given path into memory, optionally with a pre-defined
    loader format.

    Params:
        path = The path of the file to load.
        format = If not `null`, loads the given file with the loader associated
                 with the given file ending. If `null`, takes the format from
                 `path`.

    Returns: The loaded resource.
    Throws: `Exception` if no loader is available for `format`.
    */
    Resource load(string path, string format = null)
    {
        if (format == null)
            format = path.extension;

        loader_t* loader = format in _loaders;
        enforce(loader, "No loader available for '%s'.".tr.format(path));

        // Check if we have it cached, and if so, if it's still alive
        auto weakref = _resourceCache.get(path, null);
        if (weakref && weakref.alive)
            return weakref.target;

        // Otherwise, load resource
        Resource resource = loader.func(path);
        resource._path = path;

        if (loader.shouldCache)
        {
            _resourceCache[path] = weakReference(resource);
            Qomproc.dprintfln("Caching '%s'...".tr, path);
        }

        return resource;
    }

    /**
    Registers a new resource loader.

    Params:
        extension = The extension to associate the loader to.
        loader = The loader function itself.
        shouldCache = If the resource should be cached for future access.
    */
    void registerLoader(string extension, loaderfunc_t loader, bool shouldCache = true)
    {
        Qomproc.dprintfln("Register loader for '%s', %s.".tr, extension,
            shouldCache ? "will cache".tr : "will not cache".tr);
        _loaders[extension] = loader_t(loader, shouldCache);
    }

    /**
    Removes the resource loader with the given extension.
    If no such loader exists, does nothing.

    Params:
        extension = The associated extension of the loader to remove.

    Returns: If the loader has been removed.
    */
    bool unregisterLoader(string extension)
    {
        return _loaders.remove(extension);
    }

    /**
    Checks if the given file is already cached.

    Params:
        path = The path of the file to check.

    Returns: If the file is already cached.
    */
    bool isCached(string path)
    {
        auto weakref = _resourceCache.get(path, null);
        return weakref && weakref.alive;
    }

    /**
    Destroys all cached resources.
    */
    void freeAll()
    {
        foreach (weakref; _resourceCache.values)
            if (weakref.alive)
                weakref.target.destroy();

        Qomproc.dprintln("Freed all resources.".tr);
    }

    /**
    Cleans the cache from resources that have already been garbage collected.
    */
    void cleanCache()
    {
        size_t cleaned;

        foreach (string key; _resourceCache.keys)
        {
            if (!isCached(key))
            {
                _resourceCache.remove(key);
                Qomproc.dprintfln("Uncaching '%s'...".tr, key);
                ++cleaned;
            }
        }

        Qomproc.dprintfln("%d resources cleaned from cache.".tr, cleaned);
    }

    /**
    Register loaders for all Qrescent internal types.
    */
    void registerDefaultLoaders()
    {
        import qrescent.resources.font : resLoadFont;
        import qrescent.resources.mesh : resLoadOBJMesh;
        import qrescent.resources.shader : resLoadShaderProgram;
        import qrescent.resources.sound : resLoadAudio, resLoadStreamingAudio;
        import qrescent.resources.texture : resLoadTexture2D, resLoadCubeMapTexture;
        import qrescent.resources.scene : SceneLoader;
        import qrescent.resources.material : resLoadMaterial;
        import qrescent.resources.sprite : resLoadSprite;
        import qrescent.resources.language : resLoadLanguage;

        // Texture2D formats
        _loaders[".png"] = _loaders[".bmp"] = _loaders[".jpg"] =
            _loaders[".jpeg"] = _loaders[".tga"] = loader_t(&resLoadTexture2D, true);

        // Texture cube map format
        _loaders[".sky"] = loader_t(&resLoadCubeMapTexture, true);

        // Mesh formats
        _loaders[".obj"] = loader_t(&resLoadOBJMesh, true);

        // Font formats
        _loaders[".qft"] = loader_t(&resLoadFont, true);

        // Shader formats
        _loaders[".shd"] = loader_t(&resLoadShaderProgram, true);

        // Audio formats
        _loaders[".ogg"] = _loaders[".wav"] = _loaders[".aiff"] =
            _loaders[".flac"] = loader_t(&resLoadAudio, true);

        _loaders[".sogg"] = _loaders[".swav"] = _loaders[".saiff"] =
            _loaders[".sflac"] = loader_t(&resLoadStreamingAudio, true);

        // Qrescent scene definition file
        _loaders[".qscn"] = loader_t(&SceneLoader._load, false);

        // Material
        _loaders[".mat"] = loader_t(&resLoadMaterial, true);

        // Sprite
        _loaders[".spr"] = loader_t(&resLoadSprite, true);

        // Language
        _loaders[".lang"] = loader_t(&resLoadLanguage, true);

        // Prefab
        //_loaders[".prefab"] = loader_t(&resLoadPrefab, true);

        Qomproc.dprintfln("Registered default loaders for %d extensions.".tr, _loaders.length);
    }

private static:
    alias loader_t = Tuple!(loaderfunc_t, "func", bool, "shouldCache");

    loader_t[string] _loaders;
    WeakReference!Resource[string] _resourceCache;
}

/**
Represents a resource, mostly assets, that are loaded from
disk and are mostly cached by the `ResourceLoader` for
future use.
*/
abstract class Resource
{
public:
    /// The path of this resource in the VFS.
    @property string path() pure const nothrow @nogc { return _path; } // @suppress(dscanner.style.doc_missing_returns)

protected:
    string _path;
}