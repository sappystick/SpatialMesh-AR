import 'dart:async';
import 'package:vector_math/vector_math_64.dart';
import 'ar_scene_manager.dart';

class PhysicsSimulator {
  final Vector3 gravity;
  final _bodyController = StreamController<PhysicsUpdate>.broadcast();
  
  final Map<String, PhysicsBody> _bodies = {};
  final List<PhysicsConstraint> _constraints = [];
  final SpatialHashGrid _broadphase;
  final CollisionResolver _resolver;
  
  Timer? _simulationTimer;
  bool _isSimulating = false;
  
  static const _fixedTimeStep = Duration(milliseconds: 16); // 60Hz
  static const _maxSubSteps = 3;
  
  Stream<PhysicsUpdate> get updates => _bodyController.stream;

  PhysicsSimulator({
    required this.gravity,
  }) : _broadphase = SpatialHashGrid(cellSize: 2.0),
       _resolver = CollisionResolver();

  Future<void> initialize() async {
    _startSimulation();
  }

  Future<PhysicsBody> createRigidBody({
    required CollisionShape shape,
    required double mass,
    required Vector3 position,
    required Quaternion orientation,
    Vector3 velocity = const Vector3(0, 0, 0),
    Vector3 angularVelocity = const Vector3(0, 0, 0),
    double friction = 0.5,
    double restitution = 0.5,
  }) async {
    final body = PhysicsBody(
      id: DateTime.now().toIso8601String(),
      shape: shape,
      mass: mass,
      position: position,
      orientation: orientation,
      velocity: velocity,
      angularVelocity: angularVelocity,
      friction: friction,
      restitution: restitution,
    );

    _bodies[body.id] = body;
    _broadphase.addBody(body);

    return body;
  }

  Future<void> updateBody({
    required PhysicsBody body,
    Vector3? position,
    Quaternion? orientation,
    Vector3? velocity,
    Vector3? angularVelocity,
  }) async {
    if (position != null) body.position = position;
    if (orientation != null) body.orientation = orientation;
    if (velocity != null) body.velocity = velocity;
    if (angularVelocity != null) body.angularVelocity = angularVelocity;

    _broadphase.updateBody(body);
  }

  Future<void> removeBody(PhysicsBody body) async {
    _bodies.remove(body.id);
    _broadphase.removeBody(body);
    
    // Remove associated constraints
    _constraints.removeWhere((c) => 
      c.bodyA.id == body.id || c.bodyB.id == body.id
    );
  }

  void _startSimulation() {
    if (_isSimulating) return;
    _isSimulating = true;

    _simulationTimer = Timer.periodic(_fixedTimeStep, (timer) {
      _stepSimulation();
    });
  }

  void _stepSimulation() {
    final dt = _fixedTimeStep.inMicroseconds / 1000000.0;
    var needsOcclusionUpdate = false;
    var needsLightingUpdate = false;

    try {
      // Update broadphase
      _broadphase.update();

      // Get potential collisions
      final pairs = _broadphase.getCollisionPairs();

      // Detect and resolve collisions
      final contacts = _detectCollisions(pairs);
      final collisionResults = _resolver.resolveCollisions(contacts);

      // Apply gravity and integrate
      for (final body in _bodies.values) {
        if (body.mass > 0) {
          // Apply gravity
          body.velocity += gravity * dt;

          // Integrate velocity
          body.position += body.velocity * dt;
          
          // Integrate angular velocity
          final rotation = Quaternion(
            body.angularVelocity.x * dt,
            body.angularVelocity.y * dt,
            body.angularVelocity.z * dt,
            0,
          ) * body.orientation;
          
          body.orientation = Quaternion(
            rotation.x * 0.5,
            rotation.y * 0.5,
            rotation.z * 0.5,
            rotation.w * 0.5,
          ).normalized();

          needsOcclusionUpdate = true;
          needsLightingUpdate = true;
        }
      }

      // Apply constraints
      for (final constraint in _constraints) {
        constraint.solve(dt);
      }

      // Update broadphase after integration
      _broadphase.update();

      // Emit update
      _bodyController.add(PhysicsUpdate(
        bodies: _bodies.values.toList(),
        collisions: collisionResults,
        needsOcclusionUpdate: needsOcclusionUpdate,
        needsLightingUpdate: needsLightingUpdate,
      ));
    } catch (e) {
      print('Physics simulation error: $e');
    }
  }

  List<Contact> _detectCollisions(List<CollisionPair> pairs) {
    final contacts = <Contact>[];

    for (final pair in pairs) {
      final bodyA = pair.bodyA;
      final bodyB = pair.bodyB;

      // Skip if both bodies are static
      if (bodyA.mass == 0 && bodyB.mass == 0) continue;

      // Apply quantum effects for small particles
      if (bodyA.material.isQuantumMaterial || bodyB.material.isQuantumMaterial) {
        final positionA = bodyA.material.isQuantumMaterial 
          ? QuantumPhysicsUtils.applyQuantumUncertainty(
              bodyA.position,
              bodyA.velocity.scaled(bodyA.mass),
              bodyA.shape.dimensions.length
            )
          : bodyA.position;
          
        final positionB = bodyB.material.isQuantumMaterial
          ? QuantumPhysicsUtils.applyQuantumUncertainty(
              bodyB.position,
              bodyB.velocity.scaled(bodyB.mass),
              bodyB.shape.dimensions.length
            )
          : bodyB.position;

        // Calculate tunneling probability
        double tunnelProb = 1.0;
        if ((bodyA.material.isQuantumMaterial || bodyB.material.isQuantumMaterial) && 
            bodyA.mass < 1e-10 || bodyB.mass < 1e-10) {
          tunnelProb = QuantumPhysicsUtils.calculateTunnellingProbability(
            0.5, // barrier height based on material properties
            0.5 * (bodyA.mass * bodyA.velocity.length2 + bodyB.mass * bodyB.velocity.length2),
            (positionB - positionA).length,
            bodyA.mass + bodyB.mass
          );
        }

        // Apply entanglement if both bodies are quantum materials
        if (bodyA.material.isQuantumMaterial && bodyB.material.isQuantumMaterial) {
          final positions = [bodyA.position, bodyB.position];
          final momenta = [
            bodyA.velocity.scaled(bodyA.mass),
            bodyB.velocity.scaled(bodyB.mass)
          ];
          QuantumPhysicsUtils.applyEntanglementEffects(
            positions,
            momenta,
            0.1 // entanglement strength
          );
        }

        // Only process collision if tunneling doesn't occur
        if (tunnelProb < Random().nextDouble()) {
          final contactPoints = _calculateContactPoints(bodyA, bodyB);
          if (contactPoints.isNotEmpty) {
            contacts.add(Contact(
              bodyA: bodyA,
              bodyB: bodyB,
              points: contactPoints,
              quantumProbability: tunnelProb
            ));
          }
        }
      } else {
        // Classical collision detection
        final contactPoints = _calculateContactPoints(bodyA, bodyB);
        if (contactPoints.isNotEmpty) {
          contacts.add(Contact(
            bodyA: bodyA,
            bodyB: bodyB,
            points: contactPoints,
            quantumProbability: 1.0
          ));
        }
      }
    }

    return contacts;
  }

  List<ContactPoint> _calculateContactPoints(
    PhysicsBody bodyA,
    PhysicsBody bodyB,
  ) {
    final points = <ContactPoint>[];

    switch (bodyA.shape.type) {
      case 'box':
        switch (bodyB.shape.type) {
          case 'box':
            points.addAll(_boxBoxContact(bodyA, bodyB));
            break;
          case 'sphere':
            points.addAll(_boxSphereContact(bodyA, bodyB));
            break;
        }
        break;

      case 'sphere':
        switch (bodyB.shape.type) {
          case 'box':
            points.addAll(_sphereBoxContact(bodyA, bodyB));
            break;
          case 'sphere':
            points.addAll(_sphereSphereContact(bodyA, bodyB));
            break;
        }
        break;
    }

    return points;
  }

  List<ContactPoint> _boxBoxContact(PhysicsBody bodyA, PhysicsBody bodyB) {
    // Implement box-box collision detection
    return [];
  }

  List<ContactPoint> _boxSphereContact(PhysicsBody box, PhysicsBody sphere) {
    // Implement box-sphere collision detection
    return [];
  }

  List<ContactPoint> _sphereBoxContact(PhysicsBody sphere, PhysicsBody box) {
    return _boxSphereContact(box, sphere);
  }

  List<ContactPoint> _sphereSphereContact(
    PhysicsBody sphereA,
    PhysicsBody sphereB,
  ) {
    final points = <ContactPoint>[];
    
    final radiusA = sphereA.shape.dimensions.x / 2;
    final radiusB = sphereB.shape.dimensions.x / 2;
    
    final delta = sphereB.position - sphereA.position;
    final distance = delta.length;
    
    if (distance < radiusA + radiusB) {
      final normal = delta.normalized();
      final point = sphereA.position + normal * radiusA;
      final depth = radiusA + radiusB - distance;
      
      points.add(ContactPoint(
        position: point,
        normal: normal,
        depth: depth,
      ));
    }
    
    return points;
  }

  void dispose() {
    _simulationTimer?.cancel();
    _isSimulating = false;
    _bodyController.close();
  }
}

class PhysicsBody {
  final String id;
  final CollisionShape shape;
  final double mass;
  Vector3 position;
  Quaternion orientation;
  Vector3 velocity;
  Vector3 angularVelocity;
  final double friction;
  final double restitution;
  final AdvancedMaterialProperties material;
  List<Vector3>? quantumStates;
  double? quantumProbability;

  PhysicsBody({
    required this.id,
    required this.shape,
    required this.mass,
    required this.position,
    required this.orientation,
    required this.velocity,
    required this.angularVelocity,
    required this.friction,
    required this.restitution,
    this.material = AdvancedMaterialProperties.metallic,
  }) {
    if (material.isQuantumMaterial) {
      quantumStates = QuantumPhysicsUtils.generateSuperpositionStates(
        position,
        3,
        material.coherenceLength
      );
      quantumProbability = material.superpositionProbability;
    }
}

class SpatialHashGrid {
  final double cellSize;
  final Map<int, Set<PhysicsBody>> _grid = {};
  
  SpatialHashGrid({
    required this.cellSize,
  });

  void addBody(PhysicsBody body) {
    final cells = _getCellsForBody(body);
    for (final cell in cells) {
      _grid.putIfAbsent(cell, () => {}).add(body);
    }
  }

  void updateBody(PhysicsBody body) {
    // Remove from old cells
    for (final bodies in _grid.values) {
      bodies.remove(body);
    }
    
    // Add to new cells
    addBody(body);
  }

  void removeBody(PhysicsBody body) {
    for (final bodies in _grid.values) {
      bodies.remove(body);
    }
  }

  Set<int> _getCellsForBody(PhysicsBody body) {
    final cells = <int>{};
    
    // Calculate AABB
    final aabb = _calculateAABB(body);
    
    // Get cells that the AABB overlaps
    final minCell = _getCellIndex(aabb.min);
    final maxCell = _getCellIndex(aabb.max);
    
    for (var x = minCell.x; x <= maxCell.x; x++) {
      for (var y = minCell.y; y <= maxCell.y; y++) {
        for (var z = minCell.z; z <= maxCell.z; z++) {
          cells.add(_hashCell(x, y, z));
        }
      }
    }
    
    return cells;
  }

  AABB _calculateAABB(PhysicsBody body) {
    final halfSize = body.shape.dimensions.scaled(0.5);
    return AABB(
      body.position - halfSize,
      body.position + halfSize,
    );
  }

  Vector3 _getCellIndex(Vector3 position) {
    return Vector3(
      (position.x / cellSize).floor().toDouble(),
      (position.y / cellSize).floor().toDouble(),
      (position.z / cellSize).floor().toDouble(),
    );
  }

  int _hashCell(double x, double y, double z) {
    // Simple spatial hash function
    final h1 = 0x8da6b343;
    final h2 = 0xd8163841;
    final h3 = 0xcb1ab31f;
    
    final ix = x.floor();
    final iy = y.floor();
    final iz = z.floor();
    
    return (ix * h1 + iy * h2 + iz * h3).toInt();
  }

  List<CollisionPair> getCollisionPairs() {
    final pairs = <CollisionPair>{};
    
    for (final bodies in _grid.values) {
      for (final bodyA in bodies) {
        for (final bodyB in bodies) {
          if (bodyA.id.compareTo(bodyB.id) < 0) {
            pairs.add(CollisionPair(bodyA, bodyB));
          }
        }
      }
    }
    
    return pairs.toList();
  }

  void update() {
    // Clear empty cells
    _grid.removeWhere((_, bodies) => bodies.isEmpty);
  }
}

class CollisionResolver {
  List<CollisionResult> resolveCollisions(List<Contact> contacts) {
    final results = <CollisionResult>[];
    
    for (final contact in contacts) {
      final bodyA = contact.bodyA;
      final bodyB = contact.bodyB;
      
      for (final point in contact.points) {
        // Calculate relative velocity at contact point
        final relativeVel = _calculateRelativeVelocity(
          bodyA,
          bodyB,
          point.position,
        );
        
        // Calculate impulse
        final impulse = _calculateImpulse(
          bodyA,
          bodyB,
          point,
          relativeVel,
        );
        
        // Apply impulse
        _applyImpulse(bodyA, bodyB, point, impulse);
        
        results.add(CollisionResult(
          bodyA: bodyA,
          bodyB: bodyB,
          point: point,
          impulse: impulse,
        ));
      }
    }
    
    return results;
  }

  Vector3 _calculateRelativeVelocity(
    PhysicsBody bodyA,
    PhysicsBody bodyB,
    Vector3 point,
  ) {
    final rA = point - bodyA.position;
    final rB = point - bodyB.position;
    
    final velA = bodyA.velocity + bodyA.angularVelocity.cross(rA);
    final velB = bodyB.velocity + bodyB.angularVelocity.cross(rB);
    
    return velB - velA;
  }

  Vector3 _calculateImpulse(
    PhysicsBody bodyA,
    PhysicsBody bodyB,
    ContactPoint point,
    Vector3 relativeVel,
  ) {
    final normalVel = relativeVel.dot(point.normal);
    if (normalVel > 0) return Vector3.zero();
    
    // Basic material properties
    final restitution = (bodyA.restitution + bodyB.restitution) * 0.5;
    final friction = (bodyA.friction + bodyB.friction) * 0.5;
    
    // Advanced material deformation
    final effectiveModulus = 1 / (
      (1 - bodyA.material.poissonRatio * bodyA.material.poissonRatio) / bodyA.material.youngsModulus +
      (1 - bodyB.material.poissonRatio * bodyB.material.poissonRatio) / bodyB.material.youngsModulus
    );
    
    // Calculate normal impulse with material properties
    final deformationFactor = min(1.0, effectiveModulus / 1e9);
    final j = -(1 + restitution * deformationFactor) * normalVel;
    
    // Adjust for yield strength
    final impactEnergy = 0.5 * (bodyA.mass * bodyA.velocity.length2 + 
                               bodyB.mass * bodyB.velocity.length2);
    final yieldFactor = min(1.0, 
      (bodyA.material.yieldStrength + bodyB.material.yieldStrength) / (2 * impactEnergy)
    );
    
    final normalImpulse = point.normal.scaled(j * yieldFactor);
    
    // Calculate friction impulse with thermal effects
    final thermalDissipation = (
      bodyA.material.thermalConductivity / bodyA.material.specificHeat +
      bodyB.material.thermalConductivity / bodyB.material.specificHeat
    ) * 0.5;
    
    final tangent = (relativeVel - point.normal.scaled(normalVel)).normalized();
    final frictionImpulse = tangent.scaled(-friction * j * (1 - thermalDissipation));
    
    // Apply quantum probability if applicable
    if (bodyA.material.isQuantumMaterial || bodyB.material.isQuantumMaterial) {
      final quantumFactor = (bodyA.quantumProbability ?? 1.0) * 
                           (bodyB.quantumProbability ?? 1.0);
      return (normalImpulse + frictionImpulse).scaled(quantumFactor);
    }
    
    return normalImpulse + frictionImpulse;
  }

  void _applyImpulse(
    PhysicsBody bodyA,
    PhysicsBody bodyB,
    ContactPoint point,
    Vector3 impulse,
  ) {
    final rA = point.position - bodyA.position;
    final rB = point.position - bodyB.position;
    
    if (bodyA.mass > 0) {
      bodyA.velocity -= impulse.scaled(1 / bodyA.mass);
      bodyA.angularVelocity -= rA.cross(impulse);
    }
    
    if (bodyB.mass > 0) {
      bodyB.velocity += impulse.scaled(1 / bodyB.mass);
      bodyB.angularVelocity += rB.cross(impulse);
    }
  }
}

class Contact {
  final PhysicsBody bodyA;
  final PhysicsBody bodyB;
  final List<ContactPoint> points;

  Contact({
    required this.bodyA,
    required this.bodyB,
    required this.points,
  });
}

class ContactPoint {
  final Vector3 position;
  final Vector3 normal;
  final double depth;

  ContactPoint({
    required this.position,
    required this.normal,
    required this.depth,
  });
}

class CollisionPair {
  final PhysicsBody bodyA;
  final PhysicsBody bodyB;

  CollisionPair(this.bodyA, this.bodyB);

  @override
  bool operator ==(Object other) {
    return other is CollisionPair &&
           ((bodyA == other.bodyA && bodyB == other.bodyB) ||
            (bodyA == other.bodyB && bodyB == other.bodyA));
  }

  @override
  int get hashCode => bodyA.hashCode ^ bodyB.hashCode;
}

class CollisionResult {
  final PhysicsBody bodyA;
  final PhysicsBody bodyB;
  final ContactPoint point;
  final Vector3 impulse;

  CollisionResult({
    required this.bodyA,
    required this.bodyB,
    required this.point,
    required this.impulse,
  });
}

class PhysicsUpdate {
  final List<PhysicsBody> bodies;
  final List<CollisionResult> collisions;
  final bool needsOcclusionUpdate;
  final bool needsLightingUpdate;

  PhysicsUpdate({
    required this.bodies,
    required this.collisions,
    required this.needsOcclusionUpdate,
    required this.needsLightingUpdate,
  });
}

class AABB {
  final Vector3 min;
  final Vector3 max;

  AABB(this.min, this.max);
}