module qrescent.core.servers.physics3d.shapes;

import gl3n.linalg;

abstract class CollisionShape
{
public:
    bool isTrigger; /// Determines if this shape is a trigger.

    this(bool isTrigger = false)
    {
        this.isTrigger = isTrigger;
    }
}

class BoxCollisionShape : CollisionShape
{
public:
    vec3 extents;

    this(vec3 extents, bool isTrigger = false)
    {
        super(isTrigger);
        this.extents = extents;
    }
}

class SphereCollisionShape : CollisionShape
{
public:
    float radius;

    this(float radius, bool isTrigger = false)
    {
        super(isTrigger);
        this.radius = radius;
    }
}