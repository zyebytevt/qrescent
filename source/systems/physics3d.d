module qrescent.systems.physics3d;

import gl3n.linalg;
import sdlang;

import qrescent.core.engine;
import qrescent.core.servers.physics3d;
import qrescent.ecs;
import qrescent.ecs.utils;
import qrescent.components.physics;
import qrescent.components.transform;

class Physics3DSystem : System
{
public:
    /// Registers this system to the system manager, with values from a SDLang tag.
	static void loadFromTag(Tag tag, SystemManager manager)
	{
        manager.register(new Physics3DSystem());
    }

protected:
    Physics3DServer.CollisionData[1024] _collisions;
    size_t _collisionCount;
    Entity[2048] _entities;
    size_t _entityCount;

    override void run(EntityManager entities, EventManager events, Duration dt)
    {
        if (EngineCore.paused)
            return;

        immutable float delta = dt.total!"msecs" / 1000f;

        _collisionCount = _entityCount = 0;

        foreach (Entity entity, Transform3DComponent* transform, Physics3DComponent* physics;
            entities.entitiesWith!(Transform3DComponent, Physics3DComponent))
        {
            _entities[_entityCount++] = entity;
            Physics3DServer.performIntegration(transform, physics, delta);
        }

        for (size_t i; i < _entityCount; ++i)
            for (size_t j = i+1; j < _entityCount; ++j)
            {
                auto collision = Physics3DServer.checkCollision(_entities[j], _entities[i]);

                if (collision.isColliding)
                    _collisions[_collisionCount++] = collision;
            }

        for (size_t i; i < _collisionCount; ++i)
            Physics3DServer.resolveCollision(_collisions[i]);
    }
}