import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'auth_service.dart';
import 'linq_theme.dart';

enum TransactionType { deposit, payment, refund }

class Transaction {
  final String id;
  final String title;
  final String description;
  final double amount;
  final DateTime date;
  final TransactionType type;

  const Transaction({
    required this.id,
    required this.title,
    required this.description,
    required this.amount,
    required this.date,
    required this.type,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] ?? 'payment').toString().toLowerCase();
    TransactionType type = TransactionType.payment;
    if (typeStr.contains('deposit') || typeStr.contains('topup')) {
      type = TransactionType.deposit;
    } else if (typeStr.contains('refund')) {
      type = TransactionType.refund;
    }

    return Transaction(
      id: json['id']?.toString() ?? json['reference']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Transaction',
      description: json['description']?.toString() ?? '',
      amount: (json['amount'] is num) ? json['amount'].toDouble() : 0.0,
      date: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      type: type,
    );
  }
}

class UserTransactionsPage extends StatefulWidget {
  const UserTransactionsPage({super.key});

  @override
  State<UserTransactionsPage> createState() => _UserTransactionsPageState();
}

class _PaystackCheckoutPage extends StatefulWidget {
  final String checkoutUrl;

  const _PaystackCheckoutPage({required this.checkoutUrl});

  @override
  State<_PaystackCheckoutPage> createState() => _PaystackCheckoutPageState();
}

class _PaystackCheckoutPageState extends State<_PaystackCheckoutPage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (request) {
            final url = request.url.toLowerCase();
            if (url.contains('status=success') ||
                url.contains('trxref=') ||
                url.contains('reference=')) {
              Navigator.pop(context);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        title: const Text('Complete payment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const LinearProgressIndicator(color: LinqColors.forest500),
        ],
      ),
    );
  }
}

class _UserTransactionsPageState extends State<UserTransactionsPage>
    with WidgetsBindingObserver {
  double _walletBalance = 0.0;
  List<Transaction> _transactions = [];
  bool _loading = true;
  String? _errorMessage;
  Timer? _pollTimer;

  static const _cacheKeyBalance = 'cached_wallet_balance';
  static const _cacheKeyTx = 'cached_transactions';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFromCacheThenFetch();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _silentRefresh(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _silentRefresh();
  }

  Future<void> _loadFromCacheThenFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedBalance = prefs.getDouble(_cacheKeyBalance);
    final cachedTxRaw = prefs.getString(_cacheKeyTx);

    if (cachedBalance != null && cachedTxRaw != null) {
      final List<dynamic> raw = jsonDecode(cachedTxRaw);
      final txList = raw
          .whereType<Map<String, dynamic>>()
          .map(Transaction.fromJson)
          .toList();
      if (mounted) {
        setState(() {
          _walletBalance = cachedBalance;
          _transactions = txList;
          _loading = false;
        });
      }
      _silentRefresh();
    } else {
      await _loadWalletData(showSpinner: true);
    }
  }

  Future<void> _silentRefresh() async {
    await _loadWalletData(showSpinner: false);
  }

  Future<void> _saveToCache(double balance, List<Transaction> txList) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_cacheKeyBalance, balance);
    final raw = txList.map((tx) => {
      'id': tx.id,
      'title': tx.title,
      'description': tx.description,
      'amount': tx.amount,
      'created_at': tx.date.toIso8601String(),
      'type': tx.type.name,
    }).toList();
    await prefs.setString(_cacheKeyTx, jsonEncode(raw));
  }

  Future<void> _loadWalletData({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    final balanceResult = await AuthService.getWalletBalance();
    final txResult = await AuthService.getTransactions(limit: 50, offset: 0);

    if (!mounted) return;

    if (balanceResult['auth_required'] == true ||
        txResult['auth_required'] == true) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    if (balanceResult['success'] == true) {
      final balanceData = balanceResult['data'] as Map<String, dynamic>;
      final balance = _extractWalletBalance(balanceData);

      List<Transaction> txList = [];
      if (txResult['success'] == true) {
        final txData = txResult['data'];
        if (txData is Map<String, dynamic>) {
          final transactions =
              txData['transactions'] as List<dynamic>? ??
              txData['data'] as List<dynamic>?;
          if (transactions != null) {
            txList = transactions
                .whereType<Map<String, dynamic>>()
                .map(Transaction.fromJson)
                .toList();
          }
        } else if (txData is List<dynamic>) {
          txList = txData
              .whereType<Map<String, dynamic>>()
              .map(Transaction.fromJson)
              .toList();
        }
      }

      await _saveToCache(balance, txList);

      if (mounted) {
        setState(() {
          _walletBalance = balance;
          _transactions = txList;
          _loading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _loading = false;
          if (showSpinner) {
            _errorMessage =
                balanceResult['message'] ?? 'Failed to load wallet data.';
          }
        });
      }
    }
  }

  Future<void> _handleTopup(double amount, String paymentMethod) async {
    setState(() => _loading = true);

    final result = await AuthService.initiateTopup(
      amount: amount,
      paymentMethod: paymentMethod,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;
      final responseData = data['data'] is Map<String, dynamic>
          ? data['data'] as Map<String, dynamic>
          : data;
      final topup = responseData['topup'] is Map<String, dynamic>
          ? responseData['topup'] as Map<String, dynamic>
          : responseData;
      final reference =
          (responseData['reference'] ??
                  responseData['gateway_ref'] ??
                  responseData['payment_reference'] ??
                  responseData['transaction_reference'] ??
                  topup['gateway_ref'] ??
                  topup['reference'] ??
                  topup['ulid'] ??
                  topup['id'] ??
                  '')
              .toString();
      final authorizationUrl = (responseData['authorization_url'] ?? '')
          .toString()
          .trim();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              authorizationUrl.isNotEmpty
                  ? 'Complete payment in Paystack to update your available balance.'
                  : 'Top-up initiated. Balance will update after payment is confirmed.',
              style: LinqTextStyles.bodySm.copyWith(
                color: LinqColors.textOnBrand,
              ),
            ),
            backgroundColor: LinqColors.success500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
          ),
        );
      }

      if (authorizationUrl.isNotEmpty) {
        await _openPaymentCheckout(authorizationUrl);
      }

      // Reload wallet data
      await _silentRefresh();

      // Check topup status
      if (reference.isNotEmpty) {
        Future.delayed(const Duration(seconds: 2), () async {
          for (var attempt = 0; attempt < 3; attempt++) {
            final statusResult = await AuthService.getTopupStatus(reference);
            if (!mounted) return;
            if (statusResult['success'] == true) {
              print('[TopupStatus] $reference: ${statusResult['data']}');
              await _silentRefresh();
              return;
            }
            await Future.delayed(const Duration(seconds: 2));
          }
        });
      }
    } else {
      setState(() => _loading = false);
      if (result['auth_required'] == true) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? 'Failed to process top-up.',
              style: LinqTextStyles.bodySm.copyWith(
                color: LinqColors.textOnBrand,
              ),
            ),
            backgroundColor: LinqColors.danger500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
          ),
        );
      }
    }
  }

  Future<void> _openPaymentCheckout(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PaystackCheckoutPage(checkoutUrl: uri.toString()),
      ),
    );
    if (mounted) {
      await _silentRefresh();
    }
  }

  double _extractWalletBalance(Map<String, dynamic> data) {
    double? read(dynamic value, {bool kobo = false}) {
      if (value is num) {
        final amount = value.toDouble();
        return kobo ? amount / 100 : amount;
      }
      if (value is String) {
        final cleaned = value.replaceAll(',', '').replaceAll('₦', '').trim();
        final amount = double.tryParse(cleaned);
        if (amount == null) return null;
        return kobo ? amount / 100 : amount;
      }
      return null;
    }

    double? search(Map<String, dynamic> source) {
      for (final key in [
        'balance',
        'available_balance',
        'availableBalance',
        'wallet_balance',
        'walletBalance',
        'amount',
      ]) {
        final amount = read(source[key]);
        if (amount != null) return amount;
      }

      for (final key in [
        'balance_kobo',
        'available_kobo',
        'available_balance_kobo',
        'availableBalanceKobo',
        'wallet_balance_kobo',
        'walletBalanceKobo',
        'amount_kobo',
      ]) {
        final amount = read(source[key], kobo: true);
        if (amount != null) return amount;
      }

      for (final key in ['data', 'wallet', 'account']) {
        final nested = source[key];
        if (nested is Map<String, dynamic>) {
          final amount = search(nested);
          if (amount != null) return amount;
        }
      }

      return null;
    }

    return search(data) ?? 0.0;
  }

  void _showFundWalletDialog() {
    final amountCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final suggestedAmounts = <double>[1000, 2000, 5000, 10000, 20000];
    double? selectedAmount;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: LinqColors.bgSurface,
          shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderLg),
          title: Text('Fund wallet', style: LinqTextStyles.h3),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose an amount or enter a custom amount:',
                    style: LinqTextStyles.bodySm,
                  ),
                  const SizedBox(height: LinqSpacing.s4),
                  Wrap(
                    spacing: LinqSpacing.s2,
                    runSpacing: LinqSpacing.s2,
                    children: suggestedAmounts.map((amount) {
                      final selected = selectedAmount == amount;
                      return ChoiceChip(
                        label: Text('₦ ${amount.toStringAsFixed(0)}'),
                        selected: selected,
                        selectedColor: LinqColors.forest500,
                        backgroundColor: LinqColors.stone100,
                        labelStyle: LinqTextStyles.labelSm.copyWith(
                          color: selected
                              ? LinqColors.textOnBrand
                              : LinqColors.textBody,
                        ),
                        side: BorderSide(
                          color: selected
                              ? LinqColors.forest500
                              : LinqColors.borderDefault,
                        ),
                        onSelected: (_) {
                          setState(() {
                            selectedAmount = amount;
                            amountCtrl.text = amount.toStringAsFixed(0);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: LinqSpacing.s4),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() => selectedAmount = null),
                    decoration: linqInputDecoration(
                      label: 'Enter amount',
                      icon: Icons.payments_outlined,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final val = double.tryParse(v.replaceAll(',', '').trim());
                      if (val == null || val <= 0)
                        return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: LinqSpacing.s4),
                  Container(
                    padding: const EdgeInsets.all(LinqSpacing.s3),
                    decoration: BoxDecoration(
                      color: LinqColors.forest50,
                      borderRadius: LinqRadius.borderMd,
                      border: Border.all(color: LinqColors.forest100),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: LinqColors.forest500,
                          size: 18,
                        ),
                        const SizedBox(width: LinqSpacing.s2),
                        Expanded(
                          child: Text(
                            'Card, bank, and transfer options will be handled securely by Paystack.',
                            style: LinqTextStyles.bodySm.copyWith(
                              color: LinqColors.forest600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: LinqTextStyles.label.copyWith(
                  color: LinqColors.textTertiary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: LinqColors.forest500,
                foregroundColor: LinqColors.textOnBrand,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: LinqRadius.borderMd,
                ),
              ),
              onPressed: _loading
                  ? null
                  : () {
                      if (!formKey.currentState!.validate()) return;
                      final amount = double.parse(
                        amountCtrl.text.replaceAll(',', '').trim(),
                      );
                      Navigator.pop(context);
                      _handleTopup(amount, 'paystack');
                    },
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: LinqColors.textOnBrand,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        elevation: 0,
        title: Text(
          'Transactions',
          style: LinqTextStyles.h3.copyWith(color: LinqColors.textOnBrand),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadWalletData(showSpinner: false),
        color: LinqColors.forest500,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: LinqColors.forest500),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                children: [
                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.all(LinqSpacing.s4),
                      padding: const EdgeInsets.all(LinqSpacing.s3),
                      decoration: BoxDecoration(
                        color: LinqColors.danger50,
                        borderRadius: LinqRadius.borderMd,
                        border: Border.all(color: LinqColors.danger100),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: LinqColors.danger500,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: LinqTextStyles.bodySm.copyWith(
                                color: LinqColors.danger700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _WalletCard(
                    balance: _walletBalance,
                    onFund: _showFundWalletDialog,
                    onRefresh: _loadWalletData,
                    isLoading: _loading,
                  ),
                  const SizedBox(height: LinqSpacing.s5),
                  _TransactionHistory(transactions: _transactions),
                  const SizedBox(height: 80),
                ],
              ),
            ),
        ),
      bottomNavigationBar: const _BottomNav(),
    );
  }
}

// ── WALLET CARD ──────────────────────────────────────────────────
class _WalletCard extends StatelessWidget {
  final double balance;
  final VoidCallback onFund;
  final VoidCallback onRefresh;
  final bool isLoading;

  const _WalletCard({
    required this.balance,
    required this.onFund,
    required this.onRefresh,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(LinqSpacing.s5),
      padding: const EdgeInsets.all(LinqSpacing.s6),
      decoration: BoxDecoration(
        color: LinqColors.forest500,
        borderRadius: LinqRadius.borderXl,
        boxShadow: LinqShadows.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LINQ WALLET',
                style: LinqTextStyles.labelSm.copyWith(
                  color: LinqColors.forest200,
                ),
              ),
              const Icon(
                Icons.account_balance_wallet,
                color: LinqColors.forest200,
                size: 26,
              ),
            ],
          ),
          const SizedBox(height: LinqSpacing.s5),
          Text(
            '₦ ${balance.toStringAsFixed(2)}',
            style: LinqTextStyles.moneyStyle(
              fontSize: 40,
              color: LinqColors.textOnBrand,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Available balance',
            style: LinqTextStyles.bodySm.copyWith(color: LinqColors.forest100),
          ),
          const SizedBox(height: LinqSpacing.s6),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : onFund,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Fund wallet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LinqColors.forest700,
                    foregroundColor: LinqColors.textOnBrand,
                    padding: const EdgeInsets.symmetric(
                      vertical: LinqSpacing.s4,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: LinqRadius.borderMd,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: LinqSpacing.s3),
              IconButton(
                onPressed: isLoading ? null : onRefresh,
                icon: const Icon(Icons.refresh, color: LinqColors.textOnBrand),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── TRANSACTION HISTORY ──────────────────────────────────────────
class _TransactionHistory extends StatelessWidget {
  final List<Transaction> transactions;
  const _TransactionHistory({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Transaction history', style: LinqTextStyles.h3),
              const Icon(Icons.filter_list, color: LinqColors.textTertiary),
            ],
          ),
          const SizedBox(height: LinqSpacing.s4),
          if (transactions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(LinqSpacing.s8),
                child: Text(
                  'No transactions yet.',
                  style: LinqTextStyles.bodySm,
                ),
              ),
            )
          else
            ...transactions.map((tx) => _TransactionTile(transaction: tx)),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  const _TransactionTile({required this.transaction});

  static const _typeIcons = {
    TransactionType.deposit: Icons.arrow_downward,
    TransactionType.payment: Icons.arrow_upward,
    TransactionType.refund: Icons.refresh,
  };

  static const _typeBg = {
    TransactionType.deposit: LinqColors.success50,
    TransactionType.payment: LinqColors.danger50,
    TransactionType.refund: LinqColors.info50,
  };

  static const _typeFg = {
    TransactionType.deposit: LinqColors.success500,
    TransactionType.payment: LinqColors.danger500,
    TransactionType.refund: LinqColors.info500,
  };

  @override
  Widget build(BuildContext context) {
    final bg = _typeBg[transaction.type]!;
    final fg = _typeFg[transaction.type]!;
    final icon = _typeIcons[transaction.type]!;
    final isPositive = transaction.type != TransactionType.payment;

    return Container(
      margin: const EdgeInsets.only(bottom: LinqSpacing.s3),
      padding: const EdgeInsets.all(LinqSpacing.s3),
      decoration: BoxDecoration(
        color: LinqColors.stone100,
        borderRadius: LinqRadius.borderMd,
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: bg,
            child: Icon(icon, color: fg, size: 18),
          ),
          const SizedBox(width: LinqSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(transaction.title, style: LinqTextStyles.label),
                const SizedBox(height: 2),
                Text(transaction.description, style: LinqTextStyles.bodySm),
                const SizedBox(height: 2),
                Text(
                  '${transaction.date.day}/${transaction.date.month}/${transaction.date.year}',
                  style: LinqTextStyles.bodyXs,
                ),
              ],
            ),
          ),
          Text(
            '${isPositive ? '+' : '-'}₦ ${transaction.amount.toStringAsFixed(2)}',
            style: LinqTextStyles.label.copyWith(
              color: fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ── BOTTOM NAV ───────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 2,
      selectedItemColor: LinqColors.forest500,
      unselectedItemColor: LinqColors.textTertiary,
      backgroundColor: LinqColors.bgSurface,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        switch (index) {
          case 0:
            Navigator.pushNamed(context, '/customer-dashboard');
            break;
          case 1:
            Navigator.pushNamed(context, '/user-jobs');
            break;
          case 2:
            break;
          case 3:
            Navigator.pushNamed(context, '/user-profile');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discovery'),
        BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Jobs'),
        BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet),
          label: 'Transactions',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}
