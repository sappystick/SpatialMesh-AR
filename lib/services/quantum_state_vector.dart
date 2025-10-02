import 'package:vector_math/vector_math_64.dart';
import 'dart:math' as math;
import 'dart:typed_data';

class QuantumStateVector {
  late Float64List _amplitudes;
  late Float64List _phases;
  final int _numQubits;
  
  int get dimension => 1 << _numQubits; // 2^n states
  List<double> get amplitudes => _amplitudes.toList();
  List<double> get phases => _phases.toList();
  
  QuantumStateVector(this._numQubits) {
    final dim = 1 << _numQubits;
    _amplitudes = Float64List(dim);
    _phases = Float64List(dim);
    
    // Initialize to |0⟩ state
    _amplitudes[0] = 1.0;
    for (var i = 1; i < dim; i++) {
      _amplitudes[i] = 0.0;
      _phases[i] = 0.0;
    }
  }
  
  void applyGate(List<List<Complex>> gate, List<int> qubits) {
    if (gate.length != gate[0].length) {
      throw ArgumentError('Gate matrix must be square');
    }
    
    final gateSize = gate.length;
    if (gateSize != (1 << qubits.length)) {
      throw ArgumentError('Gate size does not match number of qubits');
    }
    
    final newAmplitudes = Float64List(dimension);
    final newPhases = Float64List(dimension);
    
    for (var i = 0; i < dimension; i++) {
      final superposition = Complex(0, 0);
      
      for (var j = 0; j < gateSize; j++) {
        final basisState = _mapQubitsToBasisState(i, j, qubits);
        final amplitude = Complex.fromPolar(
          _amplitudes[basisState],
          _phases[basisState],
        );
        superposition.add(gate[i % gateSize][j] * amplitude);
      }
      
      newAmplitudes[i] = superposition.magnitude;
      newPhases[i] = superposition.phase;
    }
    
    _amplitudes = newAmplitudes;
    _phases = newPhases;
    _normalize();
  }
  
  int _mapQubitsToBasisState(int state, int gateIndex, List<int> qubits) {
    var result = state;
    for (var i = 0; i < qubits.length; i++) {
      final qubit = qubits[i];
      final bit = (gateIndex >> i) & 1;
      result = (result & ~(1 << qubit)) | (bit << qubit);
    }
    return result;
  }
  
  void _normalize() {
    var normSquared = 0.0;
    for (var i = 0; i < dimension; i++) {
      normSquared += _amplitudes[i] * _amplitudes[i];
    }
    
    final norm = math.sqrt(normSquared);
    for (var i = 0; i < dimension; i++) {
      _amplitudes[i] /= norm;
    }
  }
  
  Map<String, dynamic> measure() {
    final random = math.Random();
    final r = random.nextDouble();
    
    var cumulativeProbability = 0.0;
    for (var i = 0; i < dimension; i++) {
      cumulativeProbability += _amplitudes[i] * _amplitudes[i];
      if (r <= cumulativeProbability) {
        // Collapse state vector
        for (var j = 0; j < dimension; j++) {
          _amplitudes[j] = j == i ? 1.0 : 0.0;
          _phases[j] = 0.0;
        }
        
        return {
          'state': i,
          'probability': _amplitudes[i] * _amplitudes[i],
        };
      }
    }
    
    throw StateError('Measurement failed');
  }
  
  void entangle(QuantumStateVector other) {
    if (_numQubits + other._numQubits > 30) {
      throw ArgumentError('Too many qubits for entanglement');
    }
    
    final newDimension = dimension * other.dimension;
    final newAmplitudes = Float64List(newDimension);
    final newPhases = Float64List(newDimension);
    
    for (var i = 0; i < dimension; i++) {
      for (var j = 0; j < other.dimension; j++) {
        final idx = i * other.dimension + j;
        newAmplitudes[idx] = _amplitudes[i] * other._amplitudes[j];
        newPhases[idx] = _phases[i] + other._phases[j];
      }
    }
    
    _amplitudes = newAmplitudes;
    _phases = newPhases;
    _normalize();
  }
  
  QuantumStateVector clone() {
    final copy = QuantumStateVector(_numQubits);
    copy._amplitudes = Float64List.fromList(_amplitudes);
    copy._phases = Float64List.fromList(_phases);
    return copy;
  }
}

class Complex {
  final double real;
  final double imaginary;
  
  Complex(this.real, this.imaginary);
  
  factory Complex.fromPolar(double r, double theta) {
    return Complex(
      r * math.cos(theta),
      r * math.sin(theta),
    );
  }
  
  double get magnitude => math.sqrt(real * real + imaginary * imaginary);
  
  double get phase => math.atan2(imaginary, real);
  
  Complex operator *(Complex other) {
    return Complex(
      real * other.real - imaginary * other.imaginary,
      real * other.imaginary + imaginary * other.real,
    );
  }
  
  void add(Complex other) {
    real += other.real;
    imaginary += other.imaginary;
  }
  
  @override
  String toString() => '$real + ${imaginary}i';
}