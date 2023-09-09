module qrescent.ecs.utils;

import std.string : format;
import std.exception : enforce, collectException;
import std.conv : to;
import std.traits : isSomeString;

import sdlang;
import gl3n.linalg;

import qrescent.ecs;
import qrescent.resources.loader;
import qrescent.core.servers.language : tr;
import qrescent.core.exceptions : SceneException;

void setAttribute(T)(Tag root, string name, T* target, bool optional = false)
{
    Tag tag = root.getTag(name);

    if (!tag)
    {
        enforce!SceneException(optional, "Missing non-optional attribute '%s' in '%s' at %s.".tr.format(name, root.name, root.location));
        return;
    }

    static if (is(T == vec2))
    {
        enforce!SceneException(tag.values.length == 2
            && !collectException(*target = vec2(tag.values[0].get!float, tag.values[1].get!float)),
            "Expected 2 floats for attribute '%s' in '%s' at %s.".tr.format(name, root.name, tag.location));
    }
    else static if (is(T == vec3))
    {
        enforce!SceneException(tag.values.length == 3
            && !collectException(*target = vec3(tag.values[0].get!float, tag.values[1].get!float, tag.values[2].get!float)),
            "Expected 3 floats for attribute '%s' in '%s' at %s.".tr.format(name, root.name, tag.location));
    }
    else static if (is(T == quat))
    {
        enforce!SceneException(tag.values.length == 4
            && !collectException(*target = quat(vec4(tag.values[0].get!float, tag.values[1].get!float, tag.values[2].get!float, tag.values[3].get!float))),
            "Expected 4 floats for attribute '%s' in '%s' at %s.".tr.format(name, root.name, tag.location));
    }
    else static if (is(T : Resource))
    {
        Exception ex = collectException(*target = cast(T) ResourceLoader.load(tag.expectValue!string));
        enforce!SceneException(!ex,
            "Failed to load resource for attribute '%s' in '%s' at %s: %s".tr.format(name, root.name, tag.location, ex.msg));
        enforce!SceneException(*target !is null,
            "Wrong resource type given for attribute '%s' in '%s' at %s.".tr.format(name, root.name, tag.location));
    }
    else static if (is(T == enum))
    {
        enforce!SceneException(!collectException(*target = tag.expectValue!string.to!T),
            "Invalid value given for attribute '%s' in '%s' at %s.".tr.format(name, root.name, tag.location));
    }
    else static if (is(T == int) || is(T == float) || is(T == bool))
    {
        enforce!SceneException(!collectException(*target = tag.expectValue!T),
            "Expected type '%s' for attribute '%s' in '%s' at %s.".tr.format(T.stringof, name, root.name, tag.location));
    }
    else static if(isSomeString!T)
    {
        enforce!SceneException(!collectException(*target = tag.expectValue!string.to!T),
            "Expected type '%s' for attribute '%s' in '%s' at %s.".tr.format(T.stringof, name, root.name, tag.location));
    }
    else
        static assert(false, "setAttribute doesn't support " ~ T.stringof);
}

T* getComponent(T)(Entity entity, ref bool isOverride)
{
    if (entity.isRegistered!T)
    {
        isOverride = true;
        return entity.component!T;
    }
    else
    {
        isOverride = false;
        return entity.register!T;
    }
}