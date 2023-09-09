module qrescent.resources.scene;

import std.exception : enforce;
import std.string : format;
import std.algorithm : filter;
import std.variant : Variant;

import sdlang;

import qrescent.core.servers.language : tr;
import qrescent.core.exceptions;
import qrescent.core.vfs;
import qrescent.ecs;
import qrescent.resources.loader;
import qrescent.components.meta;
import qrescent.components.transform;
import qrescent.systems.render3d;
import qrescent.systems.render2d;

/**
A scene represents a state of gameplay in the engine.
It hosts the ECS functionality.
*/
class Scene : Resource
{
public:
    /**
    Construct a new scene.
    */
    this()
    {
        _events = new EventManager();
        _entities = new EntityManager(_events, 64, 8192);
        _systems = new SystemManager(_entities, _events);
    }

    ~this()
    {
        destroy(_systems);
        destroy(_entities);
        destroy(_systems);
    }

    /// The EntityManager of this scene.
    @property EntityManager entities() pure nothrow { return _entities; } // @suppress(dscanner.style.doc_missing_returns)

    /// The SystemManager of this scene.
    @property SystemManager systems() pure nothrow { return _systems; } // @suppress(dscanner.style.doc_missing_returns)

    /// The EventManager of this scene.
    @property EventManager events() pure nothrow { return _events; } // @suppress(dscanner.style.doc_missing_returns)

    /**
    Gets the entity with the specified scene id.

    Params:
        id = The scene id of the requested entity.

    Returns: The entity with the given scene id.
    Throws: `SceneException` if no such entity exists.
    */
    Entity getEntityWithSceneID(int id)
    {
        import std.string : format;

        Entity* entity = id in _sceneIDEntities;
        enforce!SceneException(entity, "No entity with Scene ID '%d'.".tr.format(id));

        return *entity;
    }

private:
    EntityManager _entities;
    SystemManager _systems;
    EventManager _events;
    Entity[int] _sceneIDEntities;
}

// ===== SCENE LOADER FUNCTION =====

/**
The SceneLoader is responsible for constructing scenes out of
Qrescent Scene Definition Files (QSCN).
Therefore, it holds references to registered components and systems.
*/
struct SceneLoader
{
    @disable this();
    @disable this(this);

public static:
    /// Function type for a component loader function.
    alias comploaderfunc_t = void function(Tag root, Entity entity, bool isOverride);
    // Function type for a system loader function.
    alias sysloaderfunc_t = void function(Tag root, SystemManager manager);

    /**
    Registers a new component with it's associated loader.

    Params:
        name = The name of the component, by which it is referred to in the QSCN.
        func = The loader function.
    */
    void registerComponentLoader(string name, comploaderfunc_t func) nothrow
    {
        _componentLoader[name] = func;
    }

    /**
    Removes a registered component loader.
    If no such component exists, does nothing.

    Params:
        name = The name of the component to unregister.
    */
    void unregisterComponentLoader(string name) nothrow
    {
        _componentLoader.remove(name);
    }

    /**
    Registers a new system with it's associated loader.

    Params:
        name = The name of the system, by which it is referred to in the QSCN.
        func = The loader function.
    */
    void registerSystemLoader(string name, sysloaderfunc_t func) nothrow
    {
        _systemLoader[name] = func;
    }

    /**
    Removes a registered system loader.
    If no such system exists, does nothing.

    Params:
        name = The name of the system to unregister.
    */
    void unregisterSystemLoader(string name) nothrow
    {
        _systemLoader.remove(name);
    }

package static:
    Resource _load(string path)
    {
        // Read scene def file
        IVFSFile file = VFS.getFile(path);
        char[] source = new char[file.size];
        file.read(source);
        file.destroy();

        Tag root = parseSource(source.idup, path);
        Scene scene = new Scene();

        // Check version
        enforce!SceneException(root.expectTagValue!int("version") == 1,
            "Invalid version of the scene definition file; expected version 1.".tr);

        // Parse entities
        auto entityTags = root.all.tags.filter!(a => a.name == "entity");

        foreach (ref Tag entityRoot; entityTags)
        {
            immutable int sceneID = entityRoot.expectValue!int;

            if (string prefabPath = entityRoot.getAttribute!string("prefab"))
            {
                scope IVFSFile subFile = VFS.getFile(prefabPath);
                char[] subSource = new char[subFile.size];
                subFile.read(subSource);
                Tag prefabRoot = parseSource(subSource.idup, prefabPath);

                Entity entity = _parseNewEntity(sceneID, prefabRoot, scene);
                _parseEntityOverride(entity, entityRoot);
            }
            else
                _parseNewEntity(sceneID, entityRoot, scene);
        }

        // After parsing entites, build scene tree via transforms if possible
        foreach (Tag entity; entityTags)
        {
            Tag parentTag = entity.getTag("parent"); // @suppress(dscanner.suspicious.unmodified)

            if (!parentTag)
                continue;

            immutable int childID = entity.expectValue!int;
            immutable int parentID = parentTag.expectValue!int;

            Entity child = scene.getEntityWithSceneID(childID);
            Entity parent = scene.getEntityWithSceneID(parentID);

            // Check which transform relationship between child and parent exists
            if (child.isRegistered!Transform2DComponent && parent.isRegistered!Transform2DComponent)
                child.component!Transform2DComponent.parent = parent.component!Transform2DComponent;
            else if (child.isRegistered!Transform3DComponent && parent.isRegistered!Transform3DComponent)
                child.component!Transform3DComponent.parent = parent.component!Transform3DComponent;
            else
                throw new SceneException("Tried to set parent with no or incompatible transform components.".tr);
        }

        // Parse systems
        foreach (Tag system; root.expectTag("systems").all.tags)
        {
            sysloaderfunc_t loader = _systemLoader.get(system.name, null);
            enforce!SceneException(loader, "Unknown system type '%s'.".tr.format(system.name));

            loader(system, scene.systems);
        }

        return scene;
    }

private static:
    comploaderfunc_t[string] _componentLoader;
    sysloaderfunc_t[string] _systemLoader;

    Entity _parseNewEntity(int sceneID, Tag root, Scene scene)
    {
        Entity entity = scene.entities.create();

        enforce!SceneException(sceneID !in scene._sceneIDEntities,
            "Entity with scene ID %d defined multiple times.".tr.format(sceneID));
        scene._sceneIDEntities[sceneID] = entity;

        // Parse meta data, if available
        if (Tag metaDataRoot = root.getTag("meta"))
        {
            MetaComponent* meta = entity.register!MetaComponent();

            foreach (Tag value; metaDataRoot.all.tags)
                meta.set(value.name, value.values[0]);
        }

        // Parse components
        foreach (Tag componentRoot; root.expectTag("components").all.tags)
        {
            comploaderfunc_t loader = _componentLoader.get(componentRoot.name, null);
            enforce!SceneException(loader, "Unknown component type '%s'.".tr.format(componentRoot.name));

            loader(componentRoot, entity, false);
        }

        return entity;
    }

    void _parseEntityOverride(Entity entity, Tag root)
    {
        // Parse meta data, if available
        if (Tag metaDataRoot = root.getTag("meta"))
        {
            MetaComponent* meta = entity.isRegistered!MetaComponent() ?
                entity.component!MetaComponent() : entity.register!MetaComponent();

            foreach (Tag value; metaDataRoot.all.tags)
                meta.set(value.name, value.values[0]);
        }

        // Parse components
        if (Tag componentsRoot = root.getTag("components"))
            foreach (Tag componentRoot; componentsRoot.all.tags)
            {
                comploaderfunc_t loader = _componentLoader.get(componentRoot.name, null);
                enforce!SceneException(loader, "Unknown component type '%s'.".tr.format(componentRoot.name));

                loader(componentRoot, entity, true);
            }
    }
}