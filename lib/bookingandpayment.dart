import 'package:flutter/material.dart';
import 'linq_theme.dart';

class CheckoutEscrowScreen extends StatefulWidget {
  const CheckoutEscrowScreen({super.key});

  @override
  State<CheckoutEscrowScreen> createState() => _CheckoutEscrowScreenState();
}

class _CheckoutEscrowScreenState extends State<CheckoutEscrowScreen> {
  String _selectedPayment = 'card';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: LinqSpacing.s6, vertical: LinqSpacing.s4),
              decoration: BoxDecoration(
                color: LinqColors.bgSurface,
                border: const Border(
                    bottom: BorderSide(color: LinqColors.borderDefault)),
                boxShadow: LinqShadows.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const Icon(Icons.location_on,
                        color: LinqColors.forest500),
                    const SizedBox(width: 6),
                    Text('Lagos, NG',
                        style: LinqTextStyles.h4
                            .copyWith(color: LinqColors.forest500)),
                  ]),
                  Text('LINQ-PAY',
                      style: LinqTextStyles.labelSm
                          .copyWith(color: LinqColors.forest500)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    LinqSpacing.s6, LinqSpacing.s8, LinqSpacing.s6, 140),
                child: Column(
                  children: [
                    Text('Review & pay', style: LinqTextStyles.h1),
                    const SizedBox(height: 8),
                    Text('Emergency pipe repair • Job #4829',
                        style: LinqTextStyles.bodySm),
                    const SizedBox(height: LinqSpacing.s8),
                    _escrowBanner(),
                    const SizedBox(height: LinqSpacing.s6),
                    _buildCostBreakdown(),
                    const SizedBox(height: LinqSpacing.s5),
                    _buildPaymentMethod(),
                    const SizedBox(height: LinqSpacing.s6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _trustChip(Icons.verified, 'LINQ-TRUST verified',
                            LinqColors.trustBg, LinqColors.trustText),
                        _trustChip(Icons.lock, '256-bit encryption',
                            LinqColors.stone100, LinqColors.textSecondary),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(
            LinqSpacing.s6, LinqSpacing.s4, LinqSpacing.s6, LinqSpacing.s6),
        decoration: BoxDecoration(
          color: LinqColors.bgSurface,
          border: const Border(
              top: BorderSide(color: LinqColors.borderDefault)),
          boxShadow: LinqShadows.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: LinqColors.forest500,
                  foregroundColor: LinqColors.textOnBrand,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: LinqRadius.borderMd),
                ),
                onPressed: () =>
                    Navigator.pushNamed(context, '/customer-dashboard'),
                icon: const Icon(Icons.lock_person),
                label: Text('Confirm & pay ₦ 237.50',
                    style: LinqTextStyles.label.copyWith(
                        color: LinqColors.textOnBrand,
                        fontWeight: FontWeight.w600,
                        fontSize: 16)),
              ),
            ),
            const SizedBox(height: LinqSpacing.s3),
            Text(
              'By confirming, you authorise holding of funds in the LINQ-PAY escrow account subject to our Terms of Service.',
              textAlign: TextAlign.center,
              style: LinqTextStyles.bodyXs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _escrowBanner() {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.forest500,
        borderRadius: LinqRadius.borderXl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(LinqSpacing.s3),
            decoration: BoxDecoration(
              color: LinqColors.forest700,
              borderRadius: LinqRadius.borderMd,
            ),
            child: const Icon(Icons.verified_user,
                color: LinqColors.textOnBrand),
          ),
          const SizedBox(width: LinqSpacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LINQ-PAY escrow protected',
                    style: LinqTextStyles.h4
                        .copyWith(color: LinqColors.textOnBrand)),
                const SizedBox(height: 6),
                Text(
                  'Your payment is held securely and only released when you confirm the job is done.',
                  style: LinqTextStyles.bodySm
                      .copyWith(color: LinqColors.forest100),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostBreakdown() {
    return Container(
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
          Text('COST BREAKDOWN',
              style: LinqTextStyles.labelSm
                  .copyWith(color: LinqColors.textSecondary)),
          const SizedBox(height: LinqSpacing.s6),
          _priceRow('Service fee', '₦ 180.00'),
          _priceRow('Materials (parts & fixtures)', '₦ 45.50'),
          _priceRow('Platform fee', '₦ 12.00',
              valueColor: LinqColors.forest500),
          Divider(height: LinqSpacing.s8, color: LinqColors.borderDefault),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total amount', style: LinqTextStyles.h4),
              Text('₦ 237.50',
                  style: LinqTextStyles.moneyStyle(
                      fontSize: 26, color: LinqColors.forest500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethod() {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.stone100,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PAYMENT METHOD',
              style: LinqTextStyles.labelSm
                  .copyWith(color: LinqColors.textSecondary)),
          const SizedBox(height: LinqSpacing.s5),
          _paymentTile(
            title: 'Visa ending in 4429',
            subtitle: 'Expires 12/26',
            icon: Icons.credit_card,
            value: 'card',
          ),
          const SizedBox(height: LinqSpacing.s4),
          _paymentTile(
            title: 'LINQ wallet',
            subtitle: 'Balance: ₦ 84.20',
            icon: Icons.account_balance_wallet,
            value: 'wallet',
          ),
        ],
      ),
    );
  }

  Widget _paymentTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
  }) {
    final selected = _selectedPayment == value;
    return InkWell(
      onTap: () => setState(() => _selectedPayment = value),
      borderRadius: LinqRadius.borderLg,
      child: Container(
        padding: const EdgeInsets.all(LinqSpacing.s4),
        decoration: BoxDecoration(
          color: LinqColors.bgSurface,
          borderRadius: LinqRadius.borderLg,
          border: Border.all(
            color: selected ? LinqColors.forest500 : LinqColors.borderDefault,
            width: selected ? LinqBorders.medium : LinqBorders.thin,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 36,
              decoration: BoxDecoration(
                color: LinqColors.stone100,
                borderRadius: LinqRadius.borderSm,
              ),
              child: Icon(icon, color: LinqColors.textSecondary),
            ),
            const SizedBox(width: LinqSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: LinqTextStyles.label),
                  Text(subtitle, style: LinqTextStyles.bodySm),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: _selectedPayment,
              activeColor: LinqColors.forest500,
              onChanged: (val) => setState(() => _selectedPayment = val!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(String label, String amount, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: LinqTextStyles.body),
          Text(amount,
              style: LinqTextStyles.label.copyWith(
                  color: valueColor ?? LinqColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _trustChip(IconData icon, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: LinqSpacing.s4, vertical: LinqSpacing.s2_5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: LinqRadius.borderFull,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(text, style: LinqTextStyles.labelSm.copyWith(color: fg)),
        ],
      ),
    );
  }
}
