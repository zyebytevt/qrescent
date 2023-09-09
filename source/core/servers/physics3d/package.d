module qrescent.core.servers.physics3d;

public
{
    import qrescent.core.servers.physics3d.shapes;
}

import std.algorithm : clamp;

import gl3n.linalg;

import qrescent.ecs.entity;
import qrescent.components.transform;
import qrescent.components.physics;

struct Physics3DServer
{
    @disable this();
    @disable this(this);

public static:
    struct CollisionData
    {
        bool isColliding;
        Entity firstCollider;
        Entity secondCollider;
        vec3 normal;
        vec3 point;
        float penetrationDepth;
    }

    vec3 gravity = vec3(0, -9.81, 0); /// Constant gravity factor that is applied to physics objects.
    float ignoreInterpenetrationThreshold = 0.01; /// Threshold up to which to ignore interepenetration to avoid jittering.
    float interpenetrationResolutionFactor = 0.9; /// Fraction to which to resolve interpenetration to avoid jittering.

    void delegate(Entity firstEntity, Entity secondEntity) triggerCallback;

    CollisionData checkCollision(Entity firstEntity, Entity secondEntity)
    {
        auto firstShape = firstEntity.component!Physics3DComponent.shape;
        auto secondShape = secondEntity.component!Physics3DComponent.shape;

        if (auto firstSphereShape = cast(SphereCollisionShape) firstShape)
        {
            if (auto secondSphereShape = cast(SphereCollisionShape) secondShape)
                return checkCollision(firstSphereShape, firstEntity, secondSphereShape, secondEntity);
            else if (auto secondBoxShape = cast(BoxCollisionShape) secondShape)
                return checkCollision(firstSphereShape, firstEntity, secondBoxShape, secondEntity);
        }

        return CollisionData.init;
    }

    CollisionData checkCollision(SphereCollisionShape firstShape, Entity firstEntity,
        SphereCollisionShape secondShape, Entity secondEntity)
    {
        CollisionData result;

        auto firstTransform = firstEntity.component!Transform3DComponent;
        auto secondTransform = secondEntity.component!Transform3DComponent;

        // Check for collision first
        immutable vec3 distance = secondTransform.translation - firstTransform.translation;
        if (distance.magnitude_squared > (firstShape.radius + secondShape.radius)^^2)
            return result;

        result.isColliding = true;
        result.firstCollider = firstEntity;
        result.secondCollider = secondEntity;
        result.normal = distance.normalized;
        result.point = firstTransform.localToGlobalPosition(result.normal * firstShape.radius);
        result.penetrationDepth = firstShape.radius + secondShape.radius - distance.magnitude;

        return result;
    }

    CollisionData checkCollision(SphereCollisionShape firstShape, Entity firstEntity,
        BoxCollisionShape secondShape, Entity secondEntity)
    {
        CollisionData result;

        auto firstTransform = firstEntity.component!Transform3DComponent;
        auto secondTransform = secondEntity.component!Transform3DComponent;

        immutable vec3 sphereCenter = secondTransform.globalToLocalPosition(firstTransform.translation);

        immutable vec3 closestPoint = vec3(
            clamp(sphereCenter.x, -secondShape.extents.x, secondShape.extents.x),
            clamp(sphereCenter.y, -secondShape.extents.y, secondShape.extents.y),
            clamp(sphereCenter.z, -secondShape.extents.z, secondShape.extents.z)
        );

        immutable float distanceSquared = (closestPoint - sphereCenter).magnitude_squared;

        if (distanceSquared > firstShape.radius^^2)
            return result;

        immutable vec3 closestPointGlobal = secondTransform.localToGlobalPosition(closestPoint);

        result.isColliding = true;
        result.firstCollider = firstEntity;
        result.secondCollider = secondEntity;
        result.normal = (closestPointGlobal - firstTransform.translation).normalized;
        result.point = closestPointGlobal;
        result.penetrationDepth = firstShape.radius - (firstTransform.translation - closestPointGlobal).magnitude;

        return result;
    }

    void performIntegration(Transform3DComponent* transform, Physics3DComponent* physics, float delta)
    {
        if (!physics.kinematic)
            return;

        immutable vec3 linearAcceleration = physics.currentForce / physics.mass;

        physics.linearVelocity += (linearAcceleration + gravity * physics.gravitationScale) * delta + physics.currentImpulse;
        physics.angularVelocity += (physics.currentTorque / physics.mass) * delta + physics.currentImpulsiveTorque;

        transform.translation += physics.linearVelocity * delta + linearAcceleration * (delta ^^ 2 / 2f);
        transform.rotation = (transform.rotation + (delta/2) * transform.rotation
            * quat(0, physics.angularVelocity.xyz)).normalized;

        physics.linearVelocity *= 1 - delta * physics.linearDrag;
        physics.angularVelocity *= 1 - delta * physics.angularDrag;

        physics.currentForce = physics.currentImpulse = physics.currentTorque =
            physics.currentImpulsiveTorque = vec3(0);
    }

    void resolveCollision(CollisionData collision)
    {
        if (collision.penetrationDepth < ignoreInterpenetrationThreshold)
            return;

        Physics3DComponent* firstCollider = collision.firstCollider.component!Physics3DComponent;
        Physics3DComponent* secondCollider = collision.secondCollider.component!Physics3DComponent;

        Transform3DComponent* firstTransform = collision.firstCollider.component!Transform3DComponent;
        Transform3DComponent* secondTransform = collision.secondCollider.component!Transform3DComponent;

        // If one of the two objects is a trigger. Or both.
        if (firstCollider.shape.isTrigger || secondCollider.shape.isTrigger)
        {
            if (triggerCallback)
                triggerCallback(collision.firstCollider, collision.secondCollider);
            return;
        }

        if (firstCollider.linearVelocity.magnitude_squared > secondCollider.linearVelocity.magnitude_squared)
            firstTransform.translation -= collision.normal * collision.penetrationDepth;
        else
            secondTransform.translation += collision.normal * collision.penetrationDepth;

        immutable vec3 closingVelocity = secondCollider.linearVelocity - firstCollider.linearVelocity;
        vec3 impulse = closingVelocity.dot(collision.normal) * collision.normal;

        impulse /= (1 / firstCollider.mass + 1 / secondCollider.mass) / 2;
        immutable vec3 firstImpulse = impulse * (1 + firstCollider.bounciness);
        immutable vec3 secondImpulse = -impulse * (1 + secondCollider.bounciness);

        firstCollider.currentImpulse += firstImpulse;
        secondCollider.currentImpulse += secondImpulse;

        firstCollider.currentImpulsiveTorque += firstTransform.globalToLocalPosition(collision.point) / firstCollider.mass * 0.017444;
        secondCollider.currentImpulsiveTorque += secondTransform.globalToLocalPosition(collision.point) / secondCollider.mass * 0.017444;
    }
}