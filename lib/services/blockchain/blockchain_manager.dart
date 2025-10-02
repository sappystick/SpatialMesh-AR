import 'dart:async';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';
import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';

class BlockchainManager {
  static const CONFIRMATION_BLOCKS = 12;
  static const MAX_GAS_PRICE = BigInt.from(100000000000); // 100 gwei
  static const RETRY_ATTEMPTS = 3;
  static const RETRY_DELAY = Duration(seconds: 15);
  static const GAS_PRICE_MULTIPLIER = 1.1;
  
  final BlockchainNetwork network;
  final List<BlockchainNetwork> _fallbackNetworks;
  late final Map<BlockchainNetwork, Web3Client> _clients;
  late final Credentials _credentials;
  late final Map<BlockchainNetwork, EthereumAddress> _contractAddresses;
  late final Map<BlockchainNetwork, DeployedContract> _contracts;
  
  BlockchainNetwork _currentNetwork;
  bool _isFailoverActive = false;
  
  final _eventController = StreamController<BlockchainEvent>.broadcast();
  final Map<String, Payment> _pendingPayments = {};
  final Map<String, int> _retryAttempts = {};
  Timer? _confirmationTimer;
  Timer? _healthCheckTimer;
  
  // Cache for gas prices and nonces
  final Map<BlockchainNetwork, BigInt> _lastGasPrices = {};
  final Map<BlockchainNetwork, int> _lastNonces = {};
  final Map<BlockchainNetwork, DateTime> _lastGasUpdates = {};
  
  BlockchainManager({
    required this.network,
    List<BlockchainNetwork>? fallbackNetworks,
  }) : _fallbackNetworks = fallbackNetworks ?? [],
       _currentNetwork = network {
    _clients = {};
    _contractAddresses = {};
    _contracts = {};
  }
  
  Stream<BlockchainEvent> get events => _eventController.stream;
  
  Future<void> initialize() async {
    try {
      // Initialize all Web3 clients (main + fallbacks)
      await _initializeClients();
      
      // Load credentials
      await _loadCredentials();
      
      // Load contracts for all networks
      await _loadContracts();
      
      // Initialize gas price cache
      await _initializeGasPrices();
      
      // Start monitoring and health checks
      _startConfirmationMonitoring();
      _startHealthChecks();
      
      // Subscribe to contract events
      _subscribeToEvents();
      
    } catch (e) {
      print('Blockchain initialization error: $e');
      rethrow;
    }
  }
  
  Future<void> _initializeClients() async {
    // Initialize main network
    _clients[network] = Web3Client(_getRpcUrl(network), Client());
    
    // Initialize fallback networks
    for (final fallbackNetwork in _fallbackNetworks) {
      _clients[fallbackNetwork] = Web3Client(
        _getRpcUrl(fallbackNetwork),
        Client(),
      );
    }
    
    // Test connections
    await Future.wait([
      for (final client in _clients.values)
        client.getBlockNumber().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Network connection timeout'),
        ),
    ]);
  }
  
  Future<void> _initializeGasPrices() async {
    await Future.wait([
      for (final network in _clients.keys)
        _updateGasPrice(network),
    ]);
  }
  
  Future<void> _updateGasPrice(BlockchainNetwork network) async {
    try {
      final client = _clients[network]!;
      final gasPrice = await client.getGasPrice();
      
      _lastGasPrices[network] = gasPrice.getInWei;
      _lastGasUpdates[network] = DateTime.now();
    } catch (e) {
      print('Error updating gas price for $network: $e');
    }
  }
  
  void _startHealthChecks() {
    _healthCheckTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _performHealthCheck(),
    );
  }
  
  Future<void> _performHealthCheck() async {
    try {
      final client = _clients[_currentNetwork]!;
      await client.getBlockNumber().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Network health check timeout'),
      );
    } catch (e) {
      print('Health check failed for $_currentNetwork: $e');
      await _handleNetworkFailure();
    }
  }
  
  Future<void> _handleNetworkFailure() async {
    if (_isFailoverActive || _fallbackNetworks.isEmpty) return;
    
    _isFailoverActive = true;
    print('Initiating failover from $_currentNetwork');
    
    // Try each fallback network
    for (final fallbackNetwork in _fallbackNetworks) {
      try {
        final client = _clients[fallbackNetwork]!;
        await client.getBlockNumber().timeout(
          const Duration(seconds: 5),
        );
        
        // Switch to working network
        _currentNetwork = fallbackNetwork;
        print('Failover successful: switched to $fallbackNetwork');
        
        // Notify about network change
        _notifyEvent(BlockchainEvent(
          type: BlockchainEventType.networkChanged,
          payment: null,
          metadata: {'network': fallbackNetwork.toString()},
        ));
        
        _isFailoverActive = false;
        return;
      } catch (e) {
        print('Failover attempt to $fallbackNetwork failed: $e');
        continue;
      }
    }
    
    _isFailoverActive = false;
    print('All failover attempts exhausted');
  }
  
  String _getRpcUrl(BlockchainNetwork network) {
    final Map<BlockchainNetwork, List<String>> RPC_URLS = {
      BlockchainNetwork.mainnet: [
        'https://mainnet.infura.io/v3/YOUR_PROJECT_ID',
        'https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY',
        'https://cloudflare-eth.com',
      ],
      BlockchainNetwork.polygon: [
        'https://polygon-rpc.com',
        'https://rpc-mainnet.matic.network',
        'https://matic-mainnet.chainstacklabs.com',
      ],
      BlockchainNetwork.arbitrum: [
        'https://arb1.arbitrum.io/rpc',
        'https://arbitrum.llamarpc.com',
        'https://arb-mainnet.g.alchemy.com/v2/YOUR_API_KEY',
      ],
      BlockchainNetwork.optimism: [
        'https://mainnet.optimism.io',
        'https://opt-mainnet.g.alchemy.com/v2/YOUR_API_KEY',
      ],
      BlockchainNetwork.base: [
        'https://mainnet.base.org',
        'https://base.llamarpc.com',
      ],
    };
    
    final urls = RPC_URLS[network];
    if (urls == null || urls.isEmpty) {
      throw UnsupportedError('Unsupported network: $network');
    }
    
    // Get cached health status or use first URL
    final healthyUrl = _findHealthyRpcUrl(urls);
    return healthyUrl ?? urls.first;
  }
  
  final Map<String, bool> _rpcHealthCache = {};
  final Map<String, DateTime> _rpcLastChecked = {};
  
  String? _findHealthyRpcUrl(List<String> urls) {
    final now = DateTime.now();
    
    // Try cached healthy URL first
    for (final url in urls) {
      final lastChecked = _rpcLastChecked[url];
      final isRecentCheck = lastChecked?.isAfter(
        now.subtract(const Duration(minutes: 5)),
      ) ?? false;
      
      if (isRecentCheck && _rpcHealthCache[url] == true) {
        return url;
      }
    }
    
    // No recently checked healthy URL found
    return null;
  }
  
  Future<void> _updateRpcHealth(String url, bool isHealthy) async {
    _rpcHealthCache[url] = isHealthy;
    _rpcLastChecked[url] = DateTime.now();
  }
  
  Future<void> _loadContracts() async {
    // Load contract ABI
    final contractJson = await _loadContractJson();
    final abi = ContractAbi.fromJson(contractJson, 'SpatialPayments');
    
    // Load contracts for all networks
    for (final network in {...[network], ..._fallbackNetworks}) {
      final address = _getContractAddress(network);
      _contractAddresses[network] = EthereumAddress.fromHex(address);
      
      _contracts[network] = DeployedContract(
        abi,
        _contractAddresses[network]!,
      );
      
      // Verify contract deployment
      await _verifyContract(network);
    }
  }
  
  Future<void> _verifyContract(BlockchainNetwork network) async {
    try {
      final client = _clients[network]!;
      final contract = _contracts[network]!;
      
      // Check contract code
      final code = await client.getCode(contract.address);
      if (code.isEmpty || code == '0x') {
        throw Exception('Contract not deployed at ${contract.address}');
      }
      
      // Verify contract interface
      final supportsInterface = await _callViewFunction(
        network,
        'supportsInterface',
        [Uint8List.fromList(contract.abi.functions.first.selector)],
      );
      
      if (!supportsInterface) {
        throw Exception('Contract does not support required interface');
      }
    } catch (e) {
      print('Contract verification failed for $network: $e');
      rethrow;
    }
  }
  
  Future<T> _callViewFunction<T>(
    BlockchainNetwork network,
    String functionName,
    List<dynamic> params,
  ) async {
    final client = _clients[network]!;
    final contract = _contracts[network]!;
    
    try {
      final result = await client.call(
        contract: contract,
        function: contract.function(functionName),
        params: params,
      );
      
      return result.first as T;
    } catch (e) {
      print('Error calling $functionName on $network: $e');
      rethrow;
    }
  }
  
  Future<String> _loadContractJson() async {
    // Load contract ABI from assets
    return '''
    {
      "abi": [
        {
          "inputs": [
            {
              "internalType": "string",
              "name": "userId",
              "type": "string"
            },
            {
              "internalType": "uint256",
              "name": "amount",
              "type": "uint256"
            }
          ],
          "name": "createPayment",
          "outputs": [
            {
              "internalType": "string",
              "name": "paymentId",
              "type": "string"
            }
          ],
          "stateMutability": "payable",
          "type": "function"
        },
        {
          "inputs": [
            {
              "internalType": "string",
              "name": "paymentId",
              "type": "string"
            }
          ],
          "name": "confirmPayment",
          "outputs": [],
          "stateMutability": "nonpayable",
          "type": "function"
        },
        {
          "inputs": [
            {
              "internalType": "string",
              "name": "userId",
              "type": "string"
            },
            {
              "internalType": "address",
              "name": "recipient",
              "type": "address"
            },
            {
              "internalType": "uint256",
              "name": "amount",
              "type": "uint256"
            }
          ],
          "name": "withdraw",
          "outputs": [],
          "stateMutability": "nonpayable",
          "type": "function"
        }
      ]
    }
    ''';
  }
  
  String _getContractAddress(BlockchainNetwork network) {
    final Map<BlockchainNetwork, String> CONTRACT_ADDRESSES = {
      BlockchainNetwork.mainnet: '0x1234567890123456789012345678901234567890',
      BlockchainNetwork.polygon: '0x9876543210987654321098765432109876543210',
      BlockchainNetwork.arbitrum: '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd',
      BlockchainNetwork.optimism: '0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
      BlockchainNetwork.base: '0xbaadf00dbaadf00dbaadf00dbaadf00dbaadf00d',
    };
    
    final address = CONTRACT_ADDRESSES[network];
    if (address == null) {
      throw UnsupportedError('No contract deployed on network: $network');
    }
    
    return address;
  }
  
  Future<void> _loadCredentials() async {
    // Load private key from secure storage
    final privateKey = await _loadPrivateKey();
    _credentials = EthPrivateKey.fromHex(privateKey);
  }
  
  Future<String> _loadPrivateKey() async {
    // Load from secure storage
    return 'your_private_key_here';
  }
  
  void _startConfirmationMonitoring() {
    _confirmationTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkPendingPayments(),
    );
  }
  
  Future<void> _checkPendingPayments() async {
    try {
      for (final payment in _pendingPayments.values) {
        final status = await checkPayment(payment.id);
        
        switch (status) {
          case PaymentStatus.confirmed:
            _handlePaymentConfirmed(payment);
            break;
          case PaymentStatus.failed:
            _handlePaymentFailed(payment, 'Transaction failed');
            break;
          default:
            break;
        }
      }
    } catch (e) {
      print('Error checking pending payments: $e');
    }
  }
  
  void _subscribeToEvents() {
    // Subscribe to contract events
    _contract.events.listen((event) {
      if (event.name == 'PaymentCreated') {
        _handlePaymentCreatedEvent(event);
      } else if (event.name == 'PaymentConfirmed') {
        _handlePaymentConfirmedEvent(event);
      }
    });
  }
  
  void _handlePaymentCreatedEvent(ContractEvent event) {
    final paymentId = event.parameters[0].value as String;
    final userId = event.parameters[1].value as String;
    final amount = event.parameters[2].value as BigInt;
    
    final payment = Payment(
      id: paymentId,
      userId: userId,
      amount: _convertFromWei(amount),
      type: PaymentType.blockchain,
      timestamp: DateTime.now(),
    );
    
    _pendingPayments[paymentId] = payment;
    
    _notifyEvent(BlockchainEvent(
      type: BlockchainEventType.paymentReceived,
      payment: payment,
    ));
  }
  
  void _handlePaymentConfirmedEvent(ContractEvent event) {
    final paymentId = event.parameters[0].value as String;
    final payment = _pendingPayments[paymentId];
    
    if (payment != null) {
      _handlePaymentConfirmed(payment);
    }
  }
  
  void _handlePaymentConfirmed(Payment payment) {
    _pendingPayments.remove(payment.id);
    
    _notifyEvent(BlockchainEvent(
      type: BlockchainEventType.paymentConfirmed,
      payment: payment,
    ));
  }
  
  void _handlePaymentFailed(Payment payment, String error) {
    _pendingPayments.remove(payment.id);
    
    _notifyEvent(BlockchainEvent(
      type: BlockchainEventType.paymentFailed,
      payment: payment,
      error: error,
    ));
  }
  
  Future<String> createPaymentRequest({
    required String userId,
    required Decimal amount,
    TransactionPriority priority = TransactionPriority.medium,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final paymentId = const Uuid().v4();
      final weiAmount = _convertToWei(amount);
      final network = _currentNetwork;
      final client = _clients[network]!;
      final contract = _contracts[network]!;
      
      // Get sender address
      final senderAddress = await _credentials.extractAddress();
      
      // Check balance
      final balance = await client.getBalance(
        EthereumAddress.fromHex(senderAddress),
      );
      
      if (balance.getInWei < weiAmount) {
        throw InsufficientBalanceException(
          'Insufficient balance for payment',
          required: weiAmount,
          available: balance.getInWei,
        );
      }
      
      // Get next nonce
      final nonce = await _getNextNonce(network, senderAddress);
      
      // Estimate gas with buffer
      final gasEstimate = await contract.estimateGas(
        function: contract.function('createPayment'),
        parameters: [userId, weiAmount],
      );
      final gasLimit = (gasEstimate * BigInt.from(120)) ~/ BigInt.from(100); // 20% buffer
      
      // Get optimized gas price
      final gasPrice = await _getOptimalGasPrice(priority: priority);
      
      // Calculate total cost
      final totalCost = gasPrice.getInWei * gasLimit + weiAmount;
      if (balance.getInWei < totalCost) {
        throw InsufficientBalanceException(
          'Insufficient balance for payment + gas',
          required: totalCost,
          available: balance.getInWei,
        );
      }
      
      // Create and sign transaction
      final transaction = Transaction(
        to: contract.address,
        from: EthereumAddress.fromHex(senderAddress),
        gasPrice: gasPrice,
        maxGas: gasLimit.toInt(),
        value: weiAmount,
        nonce: nonce,
        data: contract.function('createPayment').encodeCall([
          userId,
          weiAmount,
        ]),
      );
      
      // Send with retry mechanism
      String? txHash;
      for (var attempt = 1; attempt <= RETRY_ATTEMPTS; attempt++) {
        try {
          txHash = await client.sendTransaction(
            _credentials,
            transaction,
            chainId: _getChainId(network),
          );
          break;
        } catch (e) {
          if (attempt == RETRY_ATTEMPTS) rethrow;
          
          if (_shouldRetry(e)) {
            await Future.delayed(RETRY_DELAY * attempt);
            continue;
          }
          rethrow;
        }
      }
      
      if (txHash == null) {
        throw Exception('Failed to send transaction after $RETRY_ATTEMPTS attempts');
      }
      
      // Update nonce cache
      _lastNonces[network] = nonce + 1;
      
      // Create pending payment
      final payment = Payment(
        id: paymentId,
        userId: userId,
        amount: amount,
        type: PaymentType.blockchain,
        timestamp: DateTime.now(),
        metadata: {
          ...?metadata,
          'txHash': txHash,
          'network': network.toString(),
          'gasPrice': gasPrice.getInWei.toString(),
          'gasLimit': gasLimit.toString(),
        },
      );
      
      _pendingPayments[paymentId] = payment;
      
      // Notify about new payment
      _notifyEvent(BlockchainEvent(
        type: BlockchainEventType.paymentReceived,
        payment: payment,
      ));
      
      return paymentId;
      
    } catch (e) {
      print('Error creating payment request: $e');
      rethrow;
    }
  }
  
  Future<int> _getNextNonce(BlockchainNetwork network, String address) async {
    final client = _clients[network]!;
    
    // Get current nonce from network
    final networkNonce = await client.getTransactionCount(
      EthereumAddress.fromHex(address),
    );
    
    // Compare with cached nonce
    final cachedNonce = _lastNonces[network];
    if (cachedNonce != null && cachedNonce > networkNonce) {
      return cachedNonce;
    }
    
    return networkNonce;
  }
  
  bool _shouldRetry(dynamic error) {
    final message = error.toString().toLowerCase();
    return message.contains('nonce too low') ||
           message.contains('transaction underpriced') ||
           message.contains('connection refused') ||
           message.contains('timeout');
  }
  
  Future<PaymentStatus> checkPayment(String paymentId) async {
    try {
      final payment = _pendingPayments[paymentId];
      if (payment == null) {
        // Check if payment was already confirmed
        final status = await _loadPaymentFromChain(paymentId);
        if (status != null) return status;
        return PaymentStatus.notFound;
      }
      
      // Get transaction details
      final txHash = payment.metadata?['txHash'] as String?;
      if (txHash == null) return PaymentStatus.pending;
      
      final network = _getPaymentNetwork(payment);
      final client = _clients[network]!;
      
      // Check if transaction is pending for too long
      final timestamp = payment.timestamp;
      if (DateTime.now().difference(timestamp) > const Duration(hours: 1)) {
        // Check if we need to speed up or resubmit
        return await _handleStalledPayment(payment);
      }
      
      // Get transaction receipt
      final receipt = await client.getTransactionReceipt(txHash);
      if (receipt == null) {
        // Transaction not yet mined
        return await _checkPendingTransaction(payment);
      }
      
      // Check confirmations
      final currentBlock = await client.getBlockNumber();
      final confirmations = currentBlock - receipt.blockNumber.toInt();
      
      if (confirmations >= _getRequiredConfirmations(network)) {
        if (receipt.status ?? false) {
          // Verify payment amount and recipient
          if (await _verifyPaymentDetails(payment, receipt)) {
            await _handlePaymentSuccess(payment, receipt);
            return PaymentStatus.confirmed;
          } else {
            await _handlePaymentMismatch(payment, receipt);
            return PaymentStatus.failed;
          }
        } else {
          await _handlePaymentFailure(payment, 'Transaction reverted');
          return PaymentStatus.failed;
        }
      }
      
      return PaymentStatus.pending;
      
    } catch (e) {
      print('Error checking payment: $e');
      await _recordPaymentError(paymentId, e.toString());
      rethrow;
    }
  }
  
  Future<PaymentStatus> _handleStalledPayment(Payment payment) async {
    final network = _getPaymentNetwork(payment);
    final txHash = payment.metadata!['txHash'] as String;
    final client = _clients[network]!;
    
    try {
      // Check if transaction is still in mempool
      final tx = await client.getTransactionByHash(txHash);
      if (tx == null) {
        // Transaction dropped - resubmit with higher gas price
        return await _resubmitTransaction(payment);
      }
      
      // Transaction still pending - try to speed it up
      return await _speedUpTransaction(payment, tx);
    } catch (e) {
      print('Error handling stalled payment: $e');
      return PaymentStatus.pending;
    }
  }
  
  Future<PaymentStatus> _checkPendingTransaction(Payment payment) async {
    final network = _getPaymentNetwork(payment);
    final txHash = payment.metadata!['txHash'] as String;
    
    try {
      // Check transaction pool
      final isInMempool = await _isTransactionInMempool(network, txHash);
      if (!isInMempool) {
        // Transaction might be dropped - wait for a few checks before resubmitting
        _retryAttempts[payment.id] = (_retryAttempts[payment.id] ?? 0) + 1;
        
        if (_retryAttempts[payment.id]! >= 3) {
          return await _resubmitTransaction(payment);
        }
      }
      
      return PaymentStatus.pending;
    } catch (e) {
      print('Error checking pending transaction: $e');
      return PaymentStatus.pending;
    }
  }
  
  Future<bool> _isTransactionInMempool(BlockchainNetwork network, String txHash) async {
    try {
      final client = _clients[network]!;
      final tx = await client.getTransactionByHash(txHash);
      return tx != null && tx.blockNumber == null;
    } catch (e) {
      return false;
    }
  }
  
  Future<PaymentStatus> _resubmitTransaction(Payment payment) async {
    try {
      final network = _getPaymentNetwork(payment);
      final oldGasPrice = BigInt.parse(payment.metadata!['gasPrice'] as String);
      
      // Calculate new gas price (50% higher than original)
      final newGasPrice = (oldGasPrice * BigInt.from(150)) ~/ BigInt.from(100);
      if (newGasPrice > MAX_GAS_PRICE) {
        await _handlePaymentFailure(payment, 'Gas price too high for resubmission');
        return PaymentStatus.failed;
      }
      
      // Create replacement transaction
      final result = await createPaymentRequest(
        userId: payment.userId,
        amount: payment.amount,
        priority: TransactionPriority.high,
        metadata: {...payment.metadata ?? {}, 'replacedTx': payment.id},
      );
      
      // Update payment tracking
      _pendingPayments.remove(payment.id);
      
      return PaymentStatus.pending;
    } catch (e) {
      print('Error resubmitting transaction: $e');
      return PaymentStatus.pending;
    }
  }
  
  BlockchainNetwork _getPaymentNetwork(Payment payment) {
    final networkStr = payment.metadata?['network'] as String?;
    if (networkStr == null) return _currentNetwork;
    
    return BlockchainNetwork.values.firstWhere(
      (n) => n.toString() == networkStr,
      orElse: () => _currentNetwork,
    );
  }
  
  int _getRequiredConfirmations(BlockchainNetwork network) {
    switch (network) {
      case BlockchainNetwork.mainnet:
        return 12;
      case BlockchainNetwork.polygon:
        return 128;
      case BlockchainNetwork.arbitrum:
        return 20;
      case BlockchainNetwork.optimism:
        return 15;
      case BlockchainNetwork.base:
        return 15;
    }
  }
  
  Future<String> withdraw({
    required String userId,
    required String address,
    required Decimal amount,
  }) async {
    try {
      final weiAmount = _convertToWei(amount);
      final recipient = EthereumAddress.fromHex(address);
      
      // Estimate gas
      final gasEstimate = await _contract.estimateGas(
        function: _contract.function('withdraw'),
        parameters: [userId, recipient, weiAmount],
      );
      
      // Get gas price
      final gasPrice = await _getOptimalGasPrice();
      
      // Create transaction
      final transaction = Transaction(
        to: _contractAddress,
        from: EthereumAddress.fromHex(await _credentials.extractAddress()),
        gasPrice: gasPrice,
        maxGas: gasEstimate.toInt(),
        data: _contract.function('withdraw').encodeCall([
          userId,
          recipient,
          weiAmount,
        ]),
      );
      
      // Send transaction
      return await _client.sendTransaction(
        _credentials,
        transaction,
        chainId: _getChainId(),
      );
      
    } catch (e) {
      print('Error withdrawing funds: $e');
      rethrow;
    }
  }
  
  Future<EtherAmount> _getOptimalGasPrice({
    TransactionPriority priority = TransactionPriority.medium,
  }) async {
    final network = _currentNetwork;
    final now = DateTime.now();
    
    // Check if we need to update gas price
    final lastUpdate = _lastGasUpdates[network];
    if (lastUpdate == null ||
        now.difference(lastUpdate) > const Duration(minutes: 1)) {
      await _updateGasPrice(network);
    }
    
    final baseGasPrice = _lastGasPrices[network] ?? BigInt.zero;
    if (baseGasPrice == BigInt.zero) {
      throw Exception('Failed to get gas price for $network');
    }
    
    // Apply priority multiplier
    final multiplier = _getPriorityMultiplier(priority);
    var adjustedGasPrice = (baseGasPrice * BigInt.from(multiplier * 100) / BigInt.from(100));
    
    // Apply network congestion adjustment
    final congestionMultiplier = await _getCongestionMultiplier(network);
    adjustedGasPrice = adjustedGasPrice * BigInt.from(congestionMultiplier * 100) ~/ BigInt.from(100);
    
    // Cap gas price at maximum
    if (adjustedGasPrice > MAX_GAS_PRICE) {
      adjustedGasPrice = MAX_GAS_PRICE;
    }
    
    return EtherAmount.fromBigInt(EtherUnit.wei, adjustedGasPrice);
  }
  
  double _getPriorityMultiplier(TransactionPriority priority) {
    switch (priority) {
      case TransactionPriority.low:
        return 0.8;
      case TransactionPriority.medium:
        return 1.0;
      case TransactionPriority.high:
        return 1.5;
      case TransactionPriority.urgent:
        return 2.0;
    }
  }
  
  Future<double> _getCongestionMultiplier(BlockchainNetwork network) async {
    try {
      final client = _clients[network]!;
      
      // Get recent blocks
      final latestBlock = await client.getBlockNumber();
      final blocks = await Future.wait([
        for (var i = 0; i < 5; i++)
          client.getBlockByNumber(latestBlock - i),
      ]);
      
      // Calculate average gas usage
      final avgGasUsed = blocks
          .map((b) => b!.gasUsed)
          .reduce((a, b) => a + b) /
          blocks.length;
      
      // Compare to target gas limit
      final gasLimit = blocks.first!.gasLimit;
      final usage = avgGasUsed / gasLimit;
      
      // Return congestion multiplier
      if (usage > 0.9) return 1.5;     // Very high congestion
      if (usage > 0.75) return 1.3;    // High congestion
      if (usage > 0.5) return 1.1;     // Moderate congestion
      return 1.0;                      // Low congestion
      
    } catch (e) {
      print('Error calculating congestion for $network: $e');
      return 1.0; // Default multiplier on error
    }
  }
  
  int _getChainId() {
    switch (network) {
      case BlockchainNetwork.mainnet:
        return 1;
      case BlockchainNetwork.polygon:
        return 137;
      case BlockchainNetwork.arbitrum:
        return 42161;
      default:
        throw UnsupportedError('Unsupported network: $network');
    }
  }
  
  BigInt _convertToWei(Decimal amount) {
    return BigInt.parse((amount * Decimal.fromInt(10).pow(18)).toString());
  }
  
  Decimal _convertFromWei(BigInt wei) {
    return Decimal.fromBigInt(wei) / Decimal.fromInt(10).pow(18);
  }
  
  Future<PaymentStatus?> _loadPaymentFromChain(String paymentId) async {
    try {
      // Try all networks
      for (final network in {...[_currentNetwork], ..._fallbackNetworks}) {
        final client = _clients[network]!;
        final contract = _contracts[network]!;
        
        final result = await _callViewFunction<Map<String, dynamic>>(
          network,
          'getPayment',
          [paymentId],
        );
        
        if (result['exists'] as bool) {
          return result['confirmed'] as bool
              ? PaymentStatus.confirmed
              : PaymentStatus.pending;
        }
      }
      
      return null;
    } catch (e) {
      print('Error loading payment from chain: $e');
      return null;
    }
  }
  
  Future<bool> _verifyPaymentDetails(Payment payment, TransactionReceipt receipt) async {
    try {
      final network = _getPaymentNetwork(payment);
      final client = _clients[network]!;
      final contract = _contracts[network]!;
      
      // Get transaction
      final tx = await client.getTransactionByHash(receipt.transactionHash);
      if (tx == null) return false;
      
      // Verify amount
      if (tx.value?.getInWei != _convertToWei(payment.amount)) return false;
      
      // Verify recipient
      if (tx.to != contract.address) return false;
      
      // Decode and verify function call
      final function = contract.function('createPayment');
      final decoded = function.decodeCall(tx.input!);
      
      return decoded[0] == payment.userId &&
             decoded[1] == _convertToWei(payment.amount);
             
    } catch (e) {
      print('Error verifying payment details: $e');
      return false;
    }
  }
  
  Future<void> _handlePaymentSuccess(Payment payment, TransactionReceipt receipt) async {
    // Remove from pending
    _pendingPayments.remove(payment.id);
    _retryAttempts.remove(payment.id);
    
    // Update metadata
    final updatedPayment = payment.copyWith(
      metadata: {
        ...payment.metadata ?? {},
        'blockNumber': receipt.blockNumber.toString(),
        'gasUsed': receipt.gasUsed.toString(),
        'effectiveGasPrice': receipt.effectiveGasPrice?.toString(),
        'confirmedAt': DateTime.now().toIso8601String(),
      },
    );
    
    // Notify about confirmation
    _notifyEvent(BlockchainEvent(
      type: BlockchainEventType.paymentConfirmed,
      payment: updatedPayment,
    ));
  }
  
  Future<void> _handlePaymentFailure(Payment payment, String reason) async {
    // Remove from pending
    _pendingPayments.remove(payment.id);
    _retryAttempts.remove(payment.id);
    
    // Update metadata
    final updatedPayment = payment.copyWith(
      metadata: {
        ...payment.metadata ?? {},
        'failureReason': reason,
        'failedAt': DateTime.now().toIso8601String(),
      },
    );
    
    // Notify about failure
    _notifyEvent(BlockchainEvent(
      type: BlockchainEventType.paymentFailed,
      payment: updatedPayment,
      error: reason,
    ));
  }
  
  Future<void> _handlePaymentMismatch(Payment payment, TransactionReceipt receipt) async {
    final reason = 'Payment details mismatch in transaction ${receipt.transactionHash}';
    await _handlePaymentFailure(payment, reason);
    
    // Notify about security alert
    _notifyEvent(BlockchainEvent(
      type: BlockchainEventType.securityAlert,
      payment: payment,
      metadata: {
        'alert': 'payment_mismatch',
        'txHash': receipt.transactionHash,
        'blockNumber': receipt.blockNumber.toString(),
      },
    ));
  }
  
  Future<void> _recordPaymentError(String paymentId, String error) async {
    try {
      final payment = _pendingPayments[paymentId];
      if (payment == null) return;
      
      final updatedPayment = payment.copyWith(
        metadata: {
          ...payment.metadata ?? {},
          'lastError': error,
          'errorTimestamp': DateTime.now().toIso8601String(),
        },
      );
      
      _pendingPayments[paymentId] = updatedPayment;
    } catch (e) {
      print('Error recording payment error: $e');
    }
  }
  
  void _notifyEvent(BlockchainEvent event) {
    _eventController.add(event);
  }
  
  @override
  Future<void> dispose() async {
    _confirmationTimer?.cancel();
    _healthCheckTimer?.cancel();
    
    // Dispose all clients
    await Future.wait([
      for (final client in _clients.values)
        client.dispose(),
    ]);
    
    await _eventController.close();
  }
}

enum BlockchainNetwork {
  mainnet,
  polygon,
  arbitrum,
  optimism,
  base,
}

enum TransactionPriority {
  low,    // Slower but cheaper
  medium, // Balanced
  high,   // Faster but more expensive
  urgent, // Immediate inclusion (max gas price)
}

enum BlockchainEventType {
  paymentReceived,
  paymentConfirmed,
  paymentFailed,
  networkChanged,
  gasPriceUpdate,
  contractMigration,
  securityAlert,
}

class BlockchainEvent {
  final BlockchainEventType type;
  final Payment payment;
  final String? error;
  
  BlockchainEvent({
    required this.type,
    required this.payment,
    this.error,
  });
}

enum PaymentType {
  blockchain,
  lightning,
}

enum PaymentStatus {
  notFound,
  pending,
  confirmed,
  failed,
}

class BlockchainException implements Exception {
  final String message;
  final String? code;
  final Map<String, dynamic>? details;
  
  BlockchainException(this.message, {this.code, this.details});
  
  @override
  String toString() => 'BlockchainException: $message${code != null ? ' (code: $code)' : ''}';
}

class InsufficientBalanceException extends BlockchainException {
  final BigInt required;
  final BigInt available;
  
  InsufficientBalanceException(
    String message, {
    required this.required,
    required this.available,
  }) : super(
    message,
    code: 'INSUFFICIENT_BALANCE',
    details: {
      'required': required.toString(),
      'available': available.toString(),
      'missing': (required - available).toString(),
    },
  );
}

class NetworkException extends BlockchainException {
  final BlockchainNetwork network;
  
  NetworkException(
    String message,
    this.network, {
    String? code,
    Map<String, dynamic>? details,
  }) : super(message, code: code, details: details);
}

class ContractException extends BlockchainException {
  final String contractAddress;
  final String? functionName;
  
  ContractException(
    String message,
    this.contractAddress, {
    this.functionName,
    String? code,
    Map<String, dynamic>? details,
  }) : super(message, code: code, details: details);
}

class TransactionException extends BlockchainException {
  final String txHash;
  final BlockchainNetwork network;
  
  TransactionException(
    String message,
    this.txHash,
    this.network, {
    String? code,
    Map<String, dynamic>? details,
  }) : super(message, code: code, details: details);
}

class Payment {
  final String id;
  final String userId;
  final Decimal amount;
  final PaymentType type;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  
  Payment({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.timestamp,
    this.metadata,
  });
  
  Payment copyWith({
    String? id,
    String? userId,
    Decimal? amount,
    PaymentType? type,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return Payment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }
  
  @override
  String toString() {
    return 'Payment{id: $id, userId: $userId, amount: $amount, type: $type, timestamp: $timestamp}';
  }
}