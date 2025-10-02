import 'dart:math';
import 'package:vector_math/vector_math_64.dart';

class QuantumPhysicsUtils {
  static final Random _random = Random();

  /// Applies Heisenberg uncertainty principle to position and momentum
  static Vector3 applyQuantumUncertainty(Vector3 position, Vector3 momentum, double particleSize) {
    // Planck constant (scaled for our simulation)
    const h = 1e-34;
    
    // Calculate uncertainty based on particle size
    double uncertaintyFactor = h / (2 * particleSize);
    
    // Apply quantum fluctuations
    return Vector3(
      position.x + ((_random.nextDouble() - 0.5) * uncertaintyFactor),
      position.y + ((_random.nextDouble() - 0.5) * uncertaintyFactor),
      position.z + ((_random.nextDouble() - 0.5) * uncertaintyFactor),
    );
  }

  /// Calculates quantum tunneling probability
  static double calculateTunnellingProbability(
    double barrierHeight,
    double particleEnergy,
    double barrierWidth,
    double particleMass
  ) {
    const h = 1e-34; // Planck constant (scaled)
    
    if (particleEnergy >= barrierHeight) return 1.0;
    
    // Simplified quantum tunneling formula
    double k = sqrt(2 * particleMass * (barrierHeight - particleEnergy)) / h;
    return exp(-2 * k * barrierWidth);
  }

  /// Simulates quantum superposition states
  static List<Vector3> generateSuperpositionStates(
    Vector3 basePosition,
    int numStates,
    double coherenceLength
  ) {
    final states = <Vector3>[];
    
    for (int i = 0; i < numStates; i++) {
      final angle = 2 * pi * i / numStates;
      final offset = Vector3(
        cos(angle) * coherenceLength,
        sin(angle) * coherenceLength,
        0
      );
      states.add(basePosition + offset);
    }
    
    return states;
  }

  /// Calculates quantum entanglement effects between particles
  static void applyEntanglementEffects(
    List<Vector3> positions,
    List<Vector3> momenta,
    double entanglementStrength
  ) {
    if (positions.length != momenta.length) return;
    
    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final separation = (positions[i] - positions[j]).length;
        final correlationFactor = entanglementStrength / (1 + separation);
        
        // Correlate momenta based on entanglement
        final momentumDiff = momenta[i] - momenta[j];
        momenta[i] -= momentumDiff.scaled(correlationFactor);
        momenta[j] += momentumDiff.scaled(correlationFactor);
      }
    }
  }
}

class AdvancedMaterialProperties {
  final double youngsModulus;     // Elastic modulus
  final double poissonRatio;      // Material deformation ratio
  final double yieldStrength;     // Material yield point
  final double thermalConductivity;
  final double specificHeat;
  final bool isQuantumMaterial;   // Whether material exhibits quantum properties
  final double coherenceLength;   // Quantum coherence length
  final double superpositionProbability;

  const AdvancedMaterialProperties({
    required this.youngsModulus,
    required this.poissonRatio,
    required this.yieldStrength,
    required this.thermalConductivity,
    required this.specificHeat,
    this.isQuantumMaterial = false,
    this.coherenceLength = 0.0,
    this.superpositionProbability = 0.0,
  });

  /// Predefined material types
  static const metallic = AdvancedMaterialProperties(
    youngsModulus: 200e9,
    poissonRatio: 0.3,
    yieldStrength: 250e6,
    thermalConductivity: 50.0,
    specificHeat: 500.0,
  );

  static const quantum = AdvancedMaterialProperties(
    youngsModulus: 100e9,
    poissonRatio: 0.25,
    yieldStrength: 150e6,
    thermalConductivity: 20.0,
    specificHeat: 300.0,
    isQuantumMaterial: true,
    coherenceLength: 1e-9,
    superpositionProbability: 0.1,
  );

  static const metamaterial = AdvancedMaterialProperties(
    youngsModulus: 300e9,
    poissonRatio: 0.15,
    yieldStrength: 500e6,
    thermalConductivity: 100.0,
    specificHeat: 800.0,
    isQuantumMaterial: true,
    coherenceLength: 1e-8,
    superpositionProbability: 0.3,
  );
}