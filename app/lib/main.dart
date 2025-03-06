import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:totals/cli_output.dart';
import 'package:another_telephony/telephony.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart' as shelfRouter;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intl/intl.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/utils/sms_utils.dart';
import 'package:totals/widgets/add_account_form.dart';
import 'package:totals/widgets/bank_detail.dart';
import 'package:totals/widgets/banks_summary_list.dart';
import 'package:totals/auth-service.dart';

@pragma('vm:entry-point')
onBackgroundMessage(SmsMessage message) async {
  print("Received message in background from ${message.address}");
  if (message.body == null) {
    return;
  }
  if (!message.body!.contains("Dear Customer your Account")) {
    return message;
  }

  try {
    if (message.body?.isNotEmpty == true) {
      var details = extractDetails(message.body!);
      print(details);
      if (details['amount'] != 'Not found' &&
          details['reference'] != 'Not found' &&
          details['creditor'] != 'Not found' &&
          details['time'] != 'Not found') {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        var transactionExists = prefs.getStringList("transactions") ?? [];
        if (transactionExists.isNotEmpty) {
          for (var i = 0; i < transactionExists.length; i++) {
            var transaction = jsonDecode(transactionExists[i]);
            if (transaction['reference'] == details['reference']) {
              return;
            }
          }
        }
        transactionExists.add(jsonEncode(details));
        await prefs.setStringList("transactions", transactionExists);
        syncDataBackground();
      }
    }
  } catch (e) {
    print(e);
  }
  return message;
}

Future<void> syncDataBackground() async {
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // Retrieve existing transactions
    List<String> existingTransactions =
        prefs.getStringList('transactions') ?? [];

    // Decode transactions
    List<Map<String, dynamic>> transactionsInStore = (existingTransactions
        .map((transaction) => json.decode(transaction) as Map<String, dynamic>)
        .toList());
    print(transactionsInStore);
    // Filter out transactions that are not yet synced
    List<Map<String, dynamic>> unsyncedTransactions = transactionsInStore
        .where((transaction) => transaction['status'] != 'SYNCED')
        .toList();
    if (unsyncedTransactions.isEmpty) {
      print("No transactions to sync.");
      return;
    }

    final response = await http.post(
      Uri.parse('https://cniff-admin.vercel.app/api/transactions'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'data': unsyncedTransactions}),
    );
    if (response.statusCode == 201) {
      // Save the updated transactions back to shared preferences
      var updatedTransactions = existingTransactions.map((e) {
        var existingTransaction = json.decode(e);
        // Check if the transaction is in the unsyncedTransactions list
        var unsyncedTransaction = unsyncedTransactions.firstWhere(
          (transaction) =>
              transaction['reference'] == existingTransaction['reference'],
          orElse: () => {},
        );

        // If a match is found in unsynced transactions, update it
        if (unsyncedTransaction.isNotEmpty) {
          existingTransaction['status'] = 'SYNCED'; // Update the status field
          return json.encode(existingTransaction);
        } else {
          return e; // Return the original transaction if no match is found
        }
      }).toList();
      print(updatedTransactions);

      await prefs.setStringList('transactions', updatedTransactions);
      await prefs.setString('last_sync', DateTime.now().toString());
      print("Transactions synced successfully!");
    } else {
      throw Exception(
          "Failed to sync transactions. Status: ${response.statusCode}");
    }
  } catch (e) {
    print("Sync failed: $e");
  } finally {}
}

Map<String, dynamic> extractDetails(String message) {
  try {
    // Extract amount
    String amount = extractBetween(message, "ETB", "Ref:").trim();

    // Extract reference number
    String reference = extractBetween(message, "Ref:", "from").trim();

    // Extract date and time
    String dateTime = extractBetween(message, "ON", "BY").trim();

    // Extract creditor
    String creditor = extractBetween(message, "BY", ".").trim();

    return {
      'amount': amount,
      'reference': reference,
      'creditor': creditor,
      'time': dateTime,
      'status': "PENDING",
    };
  } catch (e) {
    // Return an error status if parsing fails
    return {
      'amount': null,
      'reference': null,
      'creditor': null,
      'time': null,
      'status': "ERROR",
    };
  }
}

String extractBetween(String text, String startKeyword, String endKeyword) {
  if (text.contains(startKeyword) && text.contains(endKeyword)) {
    int startIndex = text.indexOf(startKeyword) + startKeyword.length;
    int endIndex = text.indexOf(endKeyword, startIndex);
    return text.substring(startIndex, endIndex).trim();
  }
  return "";
}

class BankSummary {
  final int bankId;
  final double totalCredit;
  final double totalDebit;
  final double settledBalance;
  final double pendingCredit;
  final int accountCount;

  BankSummary(
      {required this.accountCount,
      required this.bankId,
      required this.totalCredit,
      required this.totalDebit,
      required this.settledBalance,
      required this.pendingCredit});
}

class AccountSummary {
  final int bankId;
  final String accountNumber;
  final String accountHolderName;
  final double totalTransactions;
  final double totalCredit;
  final double totalDebit;
  final double settledBalance;
  final double pendingCredit;

  AccountSummary(
      {required this.bankId,
      required this.accountNumber,
      required this.accountHolderName,
      required this.totalTransactions,
      required this.totalCredit,
      required this.totalDebit,
      required this.settledBalance,
      required this.pendingCredit});
}

Map<String, dynamic> extractCBETransactionDetails(String text) {
  String amountKeyword = "Credited with ETB ";
  int amountStart = text.indexOf(amountKeyword) + amountKeyword.length;
  int amountEnd = text.indexOf(".", amountStart) + 3; // Includes decimal part
  String creditedAmount = text.substring(amountStart, amountEnd);

  String transactionKeyword = "?id=";
  int transactionStart =
      text.indexOf(transactionKeyword) + transactionKeyword.length;
  String transactionId =
      text.substring(transactionStart).split(" ")[0]; // Stops at first space

  return {
    "creditedAmount": creditedAmount,
    "transactionId": transactionId,
    "bankId": 1,
    "type": "CREDIT",
  };
}

class AllSummary {
  final double totalCredit;
  final double totalDebit;
  final int banks;
  final int accounts;

  AllSummary(
      {required this.totalCredit,
      required this.totalDebit,
      required this.banks,
      required this.accounts});
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();

  List<SmsMessage> receivedMessages = [];
  List<SmsMessage> sentMessages = [];
  String output = 'App launched\n';
  bool _isAuthenticated = false;

  bool serviceStarted = false;
  String connectionStatus = "Server is offline";
  String? wifiIp;
  HttpServer? server;
  String key = "transactions";
  List<Map<String, dynamic>> transactions = [];
  final telephony = Telephony.instance;
  String lastSyncTime = '';
  int transactionCount = 0;
  int totalAccounts = 0;
  double totalCredit = 0.0;
  double currentBalance = 0.0;
  DateTime? selectedDate = DateTime.now();
  bool sortByCreditor = false;
  List<BankSummary> bankSummaries = [];
  List<AccountSummary> accountSummaries = [];
  AllSummary? summary;

  List<int> tabs = [0];
  int activeTab = 0;
  Future<void> _selectDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
      getItems();
    }
  }

  onMessage(SmsMessage message) async {
    print(message.body);
    print("Received new messages from ${message.address}");
    try {
      if (message.address == "+251943685872") {
        var details = SmsUtils.extractCBETransactionDetails(message.body!);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        var allTransactions = prefs.getStringList(key) ?? [];
        if (allTransactions.isNotEmpty) {
          for (var i = 0; i < allTransactions.length; i++) {
            var transaction = jsonDecode(allTransactions[i]);
            if (details['reference'] != null &&
                (transaction['reference'] == details['reference'])) {
              return;
            }
          }
        }
        print(details);
        allTransactions.add(jsonEncode(details));
        await prefs.setStringList(key, allTransactions);
        getItems();
        return;
      }
    } catch (e) {
      print(e);
    }
  }

  void updateOutput(String newOutput) {
    setState(() {
      output +=
          '> $newOutput [${DateFormat('yyyy-MM-dd kk:mm:ss').format(DateTime.now())}]\n';
    });
  }

  Future<void> startServer() async {
    final bool? result = await telephony.requestSmsPermissions;
    print("telephony permission $result");

    if (result != null && result) {
      telephony.listenIncomingSms(
          onNewMessage: onMessage, onBackgroundMessage: onBackgroundMessage);
    } else {
      updateOutput("permission denied");
    }
  }

  void stopServer() {
    server?.close(force: true);
    debugPrint("server stopped");
    updateOutput("Server stopped");
  }

  @override
  void initState() {
    super.initState();
    // _authenticate();
    WidgetsBinding.instance.addObserver(this); // Add observer
    startServer();
    getItems();
    syncData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Remove observer
    super.dispose();
  }

  // This will be called when the app lifecycle changes (e.g., when the app comes to the foreground).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // Refresh data whenever the app comes into view (resumed from background)
      getItems();
      syncData();
    }
  }

  Future<void> _authenticate() async {
    bool authenticated = await AuthService().authenticate();
    setState(() {
      _isAuthenticated = authenticated;
    });
  }

  void getItems({String searchKey = ""}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    List<String>? transactionExists = prefs.getStringList('transactions');
    print(transactionExists?.length);
    List<String>? allAccounts = prefs.getStringList('accounts');
    List<String>? allTransactions = prefs.getStringList('transactions');

    if (allAccounts != null) {
      Map<int, List<Map<String, dynamic>>> groupedAccounts = {};
      for (var account in allAccounts) {
        var accountData = jsonDecode(account);
        int bankId = accountData['bank'];
        if (!groupedAccounts.containsKey(bankId)) {
          groupedAccounts[bankId] = [];
        }
        groupedAccounts[bankId]!.add(accountData);
      }

      List<BankSummary> tempBankSummaries =
          groupedAccounts.entries.map((entry) {
        int bankId = entry.key;
        // find all the transactions for this bankId only
        List<Map<String, dynamic>> bankTransactions = allTransactions
                ?.map((transaction) =>
                    jsonDecode(transaction) as Map<String, dynamic>)
                .where((transaction) => transaction['bankId'] == bankId)
                .toList() ??
            [];
        List<Map<String, dynamic>> accounts = entry.value;
        double totalDebit = 0.0;
        double totalCredit = 0.0;

        for (var transaction in bankTransactions) {
          if (transaction["type"] == "DEBIT") {
            totalDebit +=
                double.tryParse(transaction["amount"].toString()) ?? 0.0;
          } else if (transaction["type"] == "CREDIT") {
            double creditAmount =
                double.tryParse(transaction["amount"].toString()) ?? 0.0;
            totalCredit += creditAmount;
          }
        }

        double settledBalance = accounts.fold(
            0.0, (sum, account) => sum + (account['settledBalance'] ?? 0.0));
        double pendingCredit = accounts.fold(
            0.0, (sum, account) => sum + (account['pendingCredit'] ?? 0.0));
        int accountCount = accounts.length;

        print("total credit: $totalCredit total debit: $totalDebit");

        return BankSummary(
          bankId: bankId,
          totalCredit: totalCredit,
          totalDebit: totalDebit,
          settledBalance: settledBalance,
          pendingCredit: pendingCredit,
          accountCount: accountCount,
        );
      }).toList();
      List<int> bankIds =
          tempBankSummaries.map((e) => e.bankId).toList(); // Get bank names

      List<AccountSummary> tempAccountSummary = allAccounts.map((account) {
        var accountData = jsonDecode(account);
        double totalDebit = 0.0;
        double totalCredit = 0.0;
        List<Map<String, dynamic>> accountTransactions =
            accountData['bank'] == 1
                ? allTransactions
                        ?.map((transaction) =>
                            jsonDecode(transaction) as Map<String, dynamic>)
                        .where((transaction) =>
                            transaction['bankId'] == 1 &&
                            transaction['accountNumber'] ==
                                accountData['accountNumber'].substring(
                                    accountData['accountNumber'].length - 4))
                        .toList() ??
                    []
                : allTransactions
                        ?.map((transaction) =>
                            jsonDecode(transaction) as Map<String, dynamic>)
                        .where((transaction) =>
                            transaction['bankId'] == accountData['bank'] &&
                            transaction['accountNumber'] ==
                                accountData['accountNumber'])
                        .toList() ??
                    [];
        for (var transaction in accountTransactions) {
          if (transaction["type"] == "DEBIT") {
            totalDebit +=
                double.tryParse(transaction["amount"].toString()) ?? 0.0;
          } else if (transaction["type"] == "CREDIT") {
            double creditAmount =
                double.tryParse(transaction["amount"].toString()) ?? 0.0;
            totalCredit += creditAmount;
          }
        }
        return AccountSummary(
          accountNumber: accountData['accountNumber'],
          bankId: accountData['bank'],
          accountHolderName: accountData['accountHolderName'],
          totalTransactions: accountTransactions.length.toDouble() ?? 0,
          totalCredit: totalCredit,
          totalDebit: totalDebit,
          settledBalance: accountData['settledBalance'] ?? 0.00,
          pendingCredit: accountData['pendingCredit'] ?? 0.00,
        );
      }).toList();
      setState(() {
        totalAccounts = allAccounts.length;
        bankSummaries = tempBankSummaries;
        tabs = [0, ...bankIds];
        accountSummaries = tempAccountSummary;
        // total credit is the sum of all transaction amount with the type CREDIT
        double tempTotalCredit = bankSummaries.fold(
            0.0, (sum, bank) => sum + bank.totalCredit - bank.totalDebit);
        summary = AllSummary(
            totalCredit: tempTotalCredit,
            totalDebit: 0,
            banks: allAccounts.length,
            accounts: allAccounts.length);
      });
    }

    // if (transactionExists != null) {
    //   List<Map<String, dynamic>> filteredTransactions = transactionExists
    //       .map((e) => jsonDecode(e) as Map<String, dynamic>) // Explicit cast
    //       .toList();
    //   // filter out only todays transaction
    //   filteredTransactions = searchKey.isEmpty
    //       ? filteredTransactions
    //           .where((transaction) => transaction['time'].contains(
    //               DateFormat('dd MMM yyyy')
    //                   .format(selectedDate ?? DateTime.now())
    //                   .toUpperCase()))
    //           .toList()
    //       : filteredTransactions
    //           .where((transaction) =>
    //               transaction['time'].contains(DateFormat('dd MMM yyyy')
    //                   .format(selectedDate ?? DateTime.now())
    //                   .toUpperCase()) &&
    //               (transaction['creditor']
    //                       .toString()
    //                       .toLowerCase()
    //                       .contains(searchKey.toLowerCase()) ||
    //                   transaction['reference']
    //                       .toString()
    //                       .toLowerCase()
    //                       .contains(searchKey.toLowerCase())))
    //           .toList();
    //   print(filteredTransactions);
    //   setState(() {
    //     transactions = filteredTransactions;
    //     if (searchKey.isEmpty) {
    //       transactionCount = transactions.length;

    //       totalCredit = transactions.fold(0.0, (sum, item) {
    //         return sum + double.tryParse(item['amount'] ?? '0')!;
    //       });

    //       // Calculate current balance (could be based on your own logic)
    //       currentBalance = totalCredit;
    //     }
    //   });
    //   String last_sync_store = prefs.getString('last_sync') ?? '';
    //   if (last_sync_store.isNotEmpty) {
    //     lastSyncTime = last_sync_store.split(".")[0];
    //   }
    // } else {
    //   if (searchKey.isEmpty) {
    //     setState(() {
    //       transactions = [];
    //       setState(() {
    //         transactions = [];
    //         transactionCount = 0;
    //         totalCredit = 0.0;
    //         currentBalance = 0.0;
    //       });
    //     });
    //   }
    // }
  }

  bool isSyncing = false;

  Future<void> syncData() async {
    setState(() {
      isSyncing = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      // Retrieve existing transactions
      List<String> existingTransactions =
          prefs.getStringList('transactions') ?? [];

      // Decode transactions
      List<Map<String, dynamic>> transactionsInStore = (existingTransactions
          .map(
              (transaction) => json.decode(transaction) as Map<String, dynamic>)
          .toList());
      print(transactionsInStore);
      // Filter out transactions that are not yet synced
      List<Map<String, dynamic>> unsyncedTransactions = transactionsInStore
          .where((transaction) => transaction['status'] != 'SYNCED')
          .toList();
      if (unsyncedTransactions.isEmpty) {
        print("No transactions to sync.");
        setState(() {
          isSyncing = false;
        });
        return;
      }

      final response = await http.post(
        Uri.parse('https://cniff-admin.vercel.app/api/transactions'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'data': unsyncedTransactions}),
      );
      if (response.statusCode == 201) {
        // Save the updated transactions back to shared preferences
        var updatedTransactions = existingTransactions.map((e) {
          var existingTransaction = json.decode(e);
          // Check if the transaction is in the unsyncedTransactions list
          var unsyncedTransaction = unsyncedTransactions.firstWhere(
            (transaction) =>
                transaction['reference'] == existingTransaction['reference'],
            orElse: () => {},
          );

          // If a match is found in unsynced transactions, update it
          if (unsyncedTransaction.isNotEmpty) {
            existingTransaction['status'] = 'SYNCED'; // Update the status field
            return json.encode(existingTransaction);
          } else {
            return e; // Return the original transaction if no match is found
          }
        }).toList();
        print(updatedTransactions);

        await prefs.setStringList('transactions', updatedTransactions);
        await prefs.setString('last_sync', DateTime.now().toString());
        getItems();

        print("Transactions synced successfully!");
      } else {
        throw Exception(
            "Failed to sync transactions. Status: ${response.statusCode}");
      }
    } catch (e) {
      print("Sync failed: $e");
    } finally {
      setState(() {
        isSyncing = false;
      });
    }
  }

  String getTransactionStatus(String transactionTime) {
    var day = transactionTime.split(" ")[0];
    var month = transactionTime.split(" ")[1];
    var year = transactionTime.split(" ")[2];

    DateTime now = DateTime.now();
    String formattedDate = DateFormat('dd MMM yyyy').format(now);
    var nowDay = transactionTime.split(" ")[0];
    var nowMonth = transactionTime.split(" ")[1];
    var nowYear = transactionTime.split(" ")[2];

    if (double.parse(nowYear) > double.parse(year)) {
      return "CLEARED";
    } else {
      if (month != nowMonth) {
        return "CLEARED";
      } else {
        if (double.parse(day) < double.parse(nowDay)) {
          return "CLEARED";
        } else {
          return "PENDING";
        }
      }
    }
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return !_isAuthenticated
        ? Scaffold(
            body: Stack(
              children: [
                Center(
                  child: Image.asset(
                    'assets/images/bg.png',
                    fit: BoxFit.cover,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/images/logo-text-white.png',
                          fit: BoxFit.cover,
                          width: 250,
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'HOME FOR ALL YOUR ACCOUNTS',
                        style: TextStyle(
                          fontSize: 14,
                          // fontWeight: FontWeight.bold,
                          color: Colors.grey[300],
                        ),
                      ),
                      SizedBox(height: 20),
                      FloatingActionButton(
                        onPressed: () async {
                          if (!_isAuthenticated) {
                            final bool canAuthenticateWithBiometrics =
                                await _auth.canCheckBiometrics;
                            if (canAuthenticateWithBiometrics) {
                              try {
                                final bool didAuthenticate =
                                    await _auth.authenticate(
                                        localizedReason:
                                            'Please authenticate to show account details',
                                        options: const AuthenticationOptions(
                                            biometricOnly: false));
                                setState(() {
                                  _isAuthenticated = didAuthenticate;
                                });
                              } catch (e) {
                                print(e);
                              }
                            }
                          } else {
                            _isAuthenticated = false;
                          }
                        },
                        child: Icon(
                            _isAuthenticated ? Icons.lock : Icons.lock_open),
                      )
                    ],
                  ),
                ),
              ],
            ),
            // floatingActionButton: _authButton(),
          )
        : Scaffold(
            backgroundColor: const Color(0xffF1F4FF),
            floatingActionButton: SizedBox(
              width: 65,
              height: 65,
              child: FloatingActionButton(
                onPressed: () {
                  showModalBottomSheet(
                    isScrollControlled: true,
                    context: context,
                    builder: (context) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 20, horizontal: 20),
                          height: MediaQuery.of(context).size.height * 0.83,
                          //child: Text("form"),
                          child: SingleChildScrollView(
                            // Add this widget
                            child: RegisterAccountForm(
                              onSubmit: () {
                                getItems();
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                backgroundColor: Color(0xFF294EC3),
                shape: const CircleBorder(), // Makes it perfectly circular
                child: const Icon(
                  Icons.add, // Changes menu icon to plus icon
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            appBar: AppBar(
                backgroundColor: const Color(0xffF1F4FF),
                toolbarHeight: 60,
                scrolledUnderElevation: 0,
                elevation: 0,
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          // borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            "assets/images/logo-text.png",
                            fit: BoxFit.cover,
                            width: 100,
                          ),
                        ),
                        // Center(
                        //   child: SvgPicture.asset(
                        //     'assets/images/logo.svg',
                        //     semanticsLabel: 'My SVG Image',
                        //     height: 100,
                        //     width: 70,
                        //   ),
                        // ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.calendar_month_outlined,
                              color: Color(0xFF8DA1E1), size: 25),
                          onPressed: () => _selectDate(context),
                        ),
                        IconButton(
                          icon: const Icon(Icons.lock_outline,
                              color: Color(0xFF8DA1E1), size: 25),
                          onPressed: () {
                            setState(() {
                              _isAuthenticated = false;
                            });
                          },
                        ),
                        // IconButton(
                        //   icon: const Icon(Icons.calendar_month_outlined,
                        //       color: Color(0xFF8DA1E1), size: 25),
                        //   onPressed: () => _selectDate(context),
                        // ),
                      ],
                    ),
                  ],
                )),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey, width: 0.5),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                        child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(tabs.length, (index) {
                        return Container(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                    color: activeTab == tabs[index]
                                        ? Color(0xFF294EC3)
                                        : Colors.transparent,
                                    width: activeTab == tabs[index] ? 2 : 0),
                              ),
                            ),
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  activeTab = tabs[index];
                                });
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: activeTab == tabs[index]
                                    ? Color(0xFF294EC3)
                                    : Color(0xFF444750),
                                textStyle: TextStyle(fontSize: 14),
                              ),
                              child: Text(tabs[index] == 0
                                  ? "Summary"
                                  : AppConstants.banks
                                      .firstWhere((element) =>
                                          element.id == tabs[index])
                                      .shortName),
                            ));
                      }),
                    )),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                activeTab == 0
                    ? Expanded(
                        child: Column(
                        children: [
                          Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              color: Colors.blueAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20.0),
                              ),
                              elevation: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF172B6D), // Your first color
                                      Color(0xFF274AB9), // Your second color
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16.0, 28.0, 16.0, 28.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        mainAxisAlignment: MainAxisAlignment
                                            .center, // Centers horizontally
                                        children: [
                                          Text(
                                            'TOTAL BALANCE',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF9FABD2),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(
                                            Icons
                                                .remove_red_eye_outlined, // You can change this icon
                                            size: 20,
                                            color: Color(0xFF9FABD2),
                                          ),
                                          SizedBox(
                                              width:
                                                  8), // Add spacing between icon and text
                                        ],
                                      ),
                                      const SizedBox(
                                        height: 4,
                                      ),
                                      Container(
                                        width: double.infinity,
                                        child: Text(
                                          "${summary?.totalCredit ?? 0 - (summary?.totalDebit ?? 0)} ETB*",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 22,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold
                                              // Subtle text color
                                              ),
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 4,
                                      ),
                                      Container(
                                        width: double.infinity,
                                        child: Text(
                                          "4 Banks | $totalAccounts Accounts",
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFFF7F8FB),
                                            // Subtle text color
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                          const SizedBox(
                            height: 12,
                          ),
                          Expanded(
                            child: BanksSummaryList(banks: bankSummaries),
                          )
                        ],
                      ))
                    : BankDetail(
                        bankId: activeTab,
                        accountSummaries: accountSummaries
                            .where((e) => e.bankId == activeTab)
                            .toList(),
                      ),
              ],
            ),
          );
  }

  Widget _authButton() {
    return FloatingActionButton(
      onPressed: () async {
        if (!_isAuthenticated) {
          final bool canAuthenticateWithBiometrics =
              await _auth.canCheckBiometrics;
          if (canAuthenticateWithBiometrics) {
            try {
              final bool didAuthenticate = await _auth.authenticate(
                  localizedReason:
                      'Please authenticate to show account details',
                  options: const AuthenticationOptions(biometricOnly: false));
              setState(() {
                _isAuthenticated = didAuthenticate;
              });
            } catch (e) {
              print(e);
            }
          }
        } else {
          _isAuthenticated = false;
        }
      },
      child: Icon(_isAuthenticated ? Icons.lock : Icons.lock_open),
    );
  }
}

class LockScreen extends StatelessWidget {
  const LockScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text("App Locked. Please authenticate.")),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text("Welcome to the app!")),
    );
  }
}
