import 'package:flutter/material.dart';
import 'linq_theme.dart';

import 'user_profile_page.dart' as user_profile;
import 'user_jobs_page.dart' as user_jobs;
import 'user_transactions_page.dart' as user_transactions;
import 'category_page.dart' as category_page;
import 'bookingandpayment.dart' as booking;
import 'signup.dart' as create_account;
import 'customer_profile_setup.dart' as customer_profile;
import 'cutomer_dashboard.dart' as customer_dashboard;
import 'email_verification.dart' as email_verification;
import 'provider_job_details.dart' as job_details;
import 'provider_jobs_page.dart' as provider_jobs;
import 'linq_pay_wallet.dart' as wallet;
import 'login.dart' as login;
import 'market_analytics.dart' as market_analytics;
import 'match_recommendation.dart' as match_recommendation;
import 'Nearby_map.dart' as nearby_map;
import 'provider_dashboard.dart' as provider_dashboard;
import 'provider_hire_page.dart' as provider_hire_page;
import 'provider_messages_page.dart' as provider_messages_page;
import 'provider_profile_screen.dart' as provider_profile_screen;
import 'provider_profile.dart';
// import 'role_selection_screen.dart' as role_selection;
import 'service_catalogue.dart' as service_catalogue;
import 'splashscreen.dart' as splash;
import 'verification_screen.dart' as verification;

void main() {
  runApp(const LinqTrustApp());
}

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  // static const roleSelection = '/role-selection';
  static const register = '/register';
  static const verifyEmail = '/verify-email';
  static const completeProfile = '/complete-profile';
  static const providerSetup = '/provider-setup';
  static const providerVerification = '/provider-verification';
  static const customerDashboard = '/customer-dashboard';
  static const providerDashboard = '/provider-dashboard';
  static const providerProfile = '/provider-profile';
  static const providerAccountProfile = '/provider-account-profile';
  static const providerHire = '/provider-hire';
  static const providerMessages = '/provider-messages';
  static const serviceCatalogue = '/service-catalogue';
  static const marketAnalytics = '/market-analytics';
  static const wallet = '/wallet';
  static const providerWallet = '/provider-wallet';
  static const providerJobs = '/provider-jobs';
  static const providerTransactions = '/provider-transactions';
  static const nearbyMap = '/nearby-map';
  static const matchRecommendation = '/match-recommendation';
  static const jobDetails = '/job-details';
  static const bookingPayment = '/booking-payment';
  static const userProfile = '/user-profile';
  static const userJobs = '/user-jobs';
  static const userTransactions = '/user-transactions';
}

class LinqTrustApp extends StatelessWidget {
  const LinqTrustApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LINQ-TRUST',
      theme: linqTheme(),
      initialRoute: AppRoutes.splash,
      routes: {
        AppRoutes.splash: (context) => const splash.SplashScreen(),
        AppRoutes.login: (context) => const login.LoginScreen(),
        // AppRoutes.roleSelection: (context) => const role_selection.RoleSelectionScreen(),
        AppRoutes.register: (context) =>
            const create_account.RegistrationScreen(),
        AppRoutes.verifyEmail: (context) =>
            const email_verification.OtpVerificationPage(),
        AppRoutes.completeProfile: (context) =>
            const customer_profile.CompleteProfilePage(),
        AppRoutes.providerSetup: (context) =>
            const provider_profile_screen.ProviderProfileScreen(),
        AppRoutes.providerVerification: (context) =>
            const verification.VerificationScreen(),
        AppRoutes.customerDashboard: (context) =>
            const customer_dashboard.HomePage(),
        AppRoutes.providerDashboard: (context) =>
            const provider_dashboard.ProviderDashboardScreen(),
        AppRoutes.providerProfile: (context) {
          final routeSettings = ModalRoute.of(context);
          final args = routeSettings?.settings.arguments;
          final provider = args is Map<String, dynamic>
              ? args
              : <String, dynamic>{};
          return ProviderProfilePage(provider: provider);
        },
        AppRoutes.providerAccountProfile: (context) =>
            const provider_profile_screen.ProviderProfileScreen(),
        AppRoutes.providerHire: (context) {
          final routeSettings = ModalRoute.of(context);
          final args = routeSettings?.settings.arguments;
          final provider = args is Map<String, dynamic>
              ? args
              : <String, dynamic>{};
          return provider_hire_page.ProviderHirePage(provider: provider);
        },
        AppRoutes.providerMessages: (context) =>
            const provider_messages_page.ProviderMessagesPage(),
        AppRoutes.serviceCatalogue: (context) =>
            const service_catalogue.ServiceManagementPage(),
        AppRoutes.marketAnalytics: (context) =>
            const market_analytics.DashboardScreen(),
        AppRoutes.wallet: (context) => const wallet.WalletDashboard(),
        AppRoutes.providerWallet: (context) => const wallet.WalletDashboard(isProvider: true),
        AppRoutes.providerJobs: (context) => const provider_jobs.ProviderJobsPage(),
        AppRoutes.providerTransactions: (context) =>
            const user_transactions.UserTransactionsPage(),
        AppRoutes.nearbyMap: (context) => const nearby_map.MapScreen(),
        AppRoutes.matchRecommendation: (context) =>
            const match_recommendation.MatchScreen(),
        AppRoutes.jobDetails: (context) {
          final routeSettings = ModalRoute.of(context);
          final args = routeSettings?.settings.arguments;
          final jobData = args is Map<String, dynamic>
              ? args
              : <String, dynamic>{};
          return job_details.ActiveJobDetailsScreen(jobData: jobData);
        },
        AppRoutes.bookingPayment: (context) =>
            const booking.CheckoutEscrowScreen(),
        AppRoutes.userProfile: (context) =>
            const user_profile.UserProfilePage(),
        AppRoutes.userJobs: (context) => const user_jobs.UserJobsPage(),
        AppRoutes.userTransactions: (context) =>
            const user_transactions.UserTransactionsPage(),
        '/category': (context) {
          final routeSettings = ModalRoute.of(context);
          final args = routeSettings?.settings.arguments;
          final parsedArgs = args is Map<String, dynamic>
              ? args
              : <String, dynamic>{};
          return category_page.CategoryPage(
            category: parsedArgs['category']?.toString() ?? '',
            icon: parsedArgs['icon'] is IconData
                ? parsedArgs['icon'] as IconData
                : Icons.category,
            categoryId: (parsedArgs['categoryId'] ?? '').toString(),
            categorySlug: (parsedArgs['categorySlug'] ?? '').toString(),
            children: (parsedArgs['children'] is List
                ? (parsedArgs['children'] as List).cast<Map<String, dynamic>>()
                : <Map<String, dynamic>>[]),
          );
        },
      },
    );
  }
}
