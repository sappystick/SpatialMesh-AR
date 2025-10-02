import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';

class LightningManager {
  static const DEFAULT_EXPIRY = Duration(hours: 24);
  static const POLLING_INTERVAL = Duration(seconds: 5);
  
  final String nodeUrl;
  final String macaroon;
  final bool testnet;
  
  final _eventController = StreamController<LightningEvent>.broadcast();
  final Map<String, Invoice> _pendingInvoices = {};
  Timer? _pollingTimer;
  
  LightningManager({
    required this.nodeUrl,
    required this.macaroon,
    this.testnet = false,
  });
  
  Stream<LightningEvent> get events => _eventController.stream;
  
  Future<void> initialize() async {
    try {
      // Test connection
      await _getInfo();
      
      // Start invoice monitoring
      _startInvoiceMonitoring();
      
    } catch (e) {
      print('Lightning initialization error: $e');
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> _getInfo() async {
    final response = await _makeRequest(
      method: 'GET',
      endpoint: 'v1/getinfo',
    );
    
    return json.decode(response.body);
  }
  
  Future<String> createInvoice({
    required String userId,
    required Decimal amount,
    Duration? expiry,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final memo = 'Payment for $userId';
      final amountSats = _convertToSats(amount);
      
      // Create invoice request
      final response = await _makeRequest(
        method: 'POST',
        endpoint: 'v1/invoices',
        body: {
          'memo': memo,
          'value': amountSats.toString(),
          'expiry': (expiry ?? DEFAULT_EXPIRY).inSeconds.toString(),
          'private': true,
        },
      );
      
      final data = json.decode(response.body);
      final paymentHash = data['r_hash'] as String;
      final paymentRequest = data['payment_request'] as String;
      
      // Create pending invoice
      final invoice = Invoice(
        id: paymentHash,
        userId: userId,
        amount: amount,
        paymentRequest: paymentRequest,
        timestamp: DateTime.now(),
        expiry: DateTime.now().add(expiry ?? DEFAULT_EXPIRY),
        metadata: metadata,
      );
      
      _pendingInvoices[paymentHash] = invoice;
      
      return paymentRequest;
      
    } catch (e) {
      print('Error creating invoice: $e');
      rethrow;
    }
  }
  
  Future<PaymentStatus> checkInvoice(String paymentHash) async {
    try {
      final invoice = _pendingInvoices[paymentHash];
      if (invoice == null) return PaymentStatus.notFound;
      
      if (DateTime.now().isAfter(invoice.expiry)) {
        _handleInvoiceExpired(invoice);
        return PaymentStatus.expired;
      }
      
      final response = await _makeRequest(
        method: 'GET',
        endpoint: 'v1/invoice/$paymentHash',
      );
      
      final data = json.decode(response.body);
      final settled = data['settled'] as bool;
      
      if (settled) {
        _handleInvoicePaid(invoice);
        return PaymentStatus.paid;
      }
      
      return PaymentStatus.pending;
      
    } catch (e) {
      print('Error checking invoice: $e');
      rethrow;
    }
  }
  
  Future<String> sendPayment({
    required String paymentRequest,
    Duration? timeout,
  }) async {
    try {
      final response = await _makeRequest(
        method: 'POST',
        endpoint: 'v1/channels/transactions',
        body: {
          'payment_request': paymentRequest,
          'timeout': (timeout ?? const Duration(seconds: 60)).inSeconds.toString(),
        },
      );
      
      final data = json.decode(response.body);
      return data['payment_hash'] as String;
      
    } catch (e) {
      print('Error sending payment: $e');
      rethrow;
    }
  }
  
  void _startInvoiceMonitoring() {
    _pollingTimer = Timer.periodic(
      POLLING_INTERVAL,
      (_) => _checkPendingInvoices(),
    );
  }
  
  Future<void> _checkPendingInvoices() async {
    try {
      for (final invoice in _pendingInvoices.values) {
        final status = await checkInvoice(invoice.id);
        
        switch (status) {
          case PaymentStatus.paid:
            _handleInvoicePaid(invoice);
            break;
          case PaymentStatus.expired:
            _handleInvoiceExpired(invoice);
            break;
          default:
            break;
        }
      }
    } catch (e) {
      print('Error checking pending invoices: $e');
    }
  }
  
  void _handleInvoicePaid(Invoice invoice) {
    _pendingInvoices.remove(invoice.id);
    
    _notifyEvent(LightningEvent(
      type: LightningEventType.invoicePaid,
      invoice: invoice,
    ));
  }
  
  void _handleInvoiceExpired(Invoice invoice) {
    _pendingInvoices.remove(invoice.id);
    
    _notifyEvent(LightningEvent(
      type: LightningEventType.invoiceExpired,
      invoice: invoice,
    ));
  }
  
  Future<http.Response> _makeRequest({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$nodeUrl/$endpoint');
    
    final headers = {
      'Grpc-Metadata-macaroon': macaroon,
      'Content-Type': 'application/json',
    };
    
    switch (method) {
      case 'GET':
        return await http.get(uri, headers: headers);
      case 'POST':
        return await http.post(
          uri,
          headers: headers,
          body: json.encode(body),
        );
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }
  }
  
  int _convertToSats(Decimal btc) {
    return (btc * Decimal.fromInt(100000000)).toBigInt().toInt();
  }
  
  Decimal _convertFromSats(int sats) {
    return Decimal.fromInt(sats) / Decimal.fromInt(100000000);
  }
  
  void _notifyEvent(LightningEvent event) {
    _eventController.add(event);
  }
  
  Future<void> dispose() async {
    _pollingTimer?.cancel();
    await _eventController.close();
  }
}

enum LightningEventType {
  invoicePaid,
  invoiceExpired,
}

class LightningEvent {
  final LightningEventType type;
  final Invoice invoice;
  final String? error;
  
  LightningEvent({
    required this.type,
    required this.invoice,
    this.error,
  });
}

enum PaymentStatus {
  notFound,
  pending,
  paid,
  expired,
}

class Invoice {
  final String id;
  final String userId;
  final Decimal amount;
  final String paymentRequest;
  final DateTime timestamp;
  final DateTime expiry;
  final Map<String, dynamic>? metadata;
  
  Invoice({
    required this.id,
    required this.userId,
    required this.amount,
    required this.paymentRequest,
    required this.timestamp,
    required this.expiry,
    this.metadata,
  });
}