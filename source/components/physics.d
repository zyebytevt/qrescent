module qrescent.components.physics;

import sdlang;
import gl3n.linalg;

import qrescent.core.servers.physics3d;
import qrescent.core.exceptions;
import qrescent.ecs;
import qrescent.ecs.utils;

/**
The Physics3DComponent, if attached, will make an entity eligable
for 3D Physics calculations.
*/
@component struct Physics3DComponent
{
    bool kinematic; /// If the physics objects is kinematic, it is not moved by the physics simulation.
    float mass; /// Mass of the object. This should never be 0!
    // Inertia tensor?
    float linearDrag; /// Linear drag of the object. Specifies how quickly the linear velocity of the object degrades without any other active forces present.
    float angularDrag; /// Angular drag of the object. Specifies how quickly the angular velocity of the object degrades without any other active torques present.
    float bounciness; /// Bounciness of the object. Bouncier objects get a larger impulse on collisions.
    float gravitationScale = 1; /// Gravitational scale of the object, which specifies how strong the object is influenced by gravity. Should usually be 1.

    CollisionShape shape; /// The collision shape to be used.

    vec3 linearVelocity = vec3(0); /// Current linear velocity of the object.
    vec3 angularVelocity = vec3(0); /// Current angular velocity of the object.

    vec3 currentForce = vec3(0); /// The force applied to this physics object in this frame.
    vec3 currentImpulse = vec3(0); /// The impulse applied to this physics object in this frame.
    vec3 currentTorque = vec3(0); /// The torque applied to this physics object in this frame.
    vec3 currentImpulsiveTorque = vec3(0); /// The impulsive torque applied to this physics object in this frame.

    /**
	Registers this component to the given entity, with values from a SDLang tag.

	Params:
		root = The root SDLang tag that describes this component.
		entity = The entity to register this component to.
		isOverride = `true` if overriding attributes of an already existing component,
		`false` otherwise.
	*/
	static void loadFromTag(Tag root, Entity entity, bool isOverride)
	{
        Physics3DComponent* component = entity.getComponent!Physics3DComponent(isOverride);

        setAttribute(root, "kinematic", &component.kinematic, isOverride);
        setAttribute(root, "mass", &component.mass, isOverride);
        setAttribute(root, "linear-drag", &component.linearDrag, isOverride);
        setAttribute(root, "angular-drag", &component.angularDrag, isOverride);
        setAttribute(root, "bounciness", &component.bounciness, isOverride);
        setAttribute(root, "gravitation-scale", &component.gravitationScale, true);

        {
            enum ShapeType
            {
                sphere,
                box
            }

            Tag shapeRoot = root.expectTag("shape");
            ShapeType type;
            setAttribute(shapeRoot, "type", &type, isOverride);

            final switch (type) with (ShapeType)
            {
                case sphere:
                    auto shape = new SphereCollisionShape(0, false);
                    setAttribute(shapeRoot, "trigger", &shape.isTrigger, true);
                    setAttribute(shapeRoot, "radius", &shape.radius, isOverride);
                    component.shape = shape;
                    break;

                case box:
                    auto shape = new BoxCollisionShape(vec3(0), false);
                    setAttribute(shapeRoot, "trigger", &shape.isTrigger, true);
                    setAttribute(shapeRoot, "extents", &shape.extents, isOverride);
                    component.shape = shape;
                    break;
            }
        }
	}
}