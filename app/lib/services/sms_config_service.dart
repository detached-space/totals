import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/sms_pattern.dart';

class SmsConfigService {
  static final List<SmsPattern> _defaultPatterns = [
    SmsPattern(
      bankId: 1,
      senderId: "CBE",
      regex:
          r"Account\s+(?<account>\d\*+\d+)\s+has been credited.*?ETB\s+(?<amount>[\d,.]+).*?Balance is ETB\s+(?<balance>[\d,.]+).*?/(?:BranchReceipt|Receipt)/(?<reference>[A-Z0-9]+)",
      type: "CREDIT",
      description: "CBE Payroll Credit",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 1,
      senderId: "CBE",
      regex:
          r"(?:Account|Acct)\s+(?<account>[\d\*]+).*?credited\s+with\s+ETB\s?(?<amount>[\d,.]+).*?Balance\s+is\s+ETB\s?(?<balance>[\d,.]+).*?((id=|BranchReceipt/)(?<reference>FT\w+))",
      type: "CREDIT",
      description: "CBE Credit with Account",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 1,
      senderId: "CBE",
      regex:
          r"(?:Account|Acct)\s+(?<account>[\d\*]+).*?debited\s+with\s+ETB\s?(?<amount>[\d,.]+).*?Balance\s+is\s+ETB\s?(?<balance>[\d,.]+).*?((id=|BranchReceipt/)(?<reference>FT\w+))",
      type: "DEBIT",
      description: "CBE Debit with Account",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 1,
      senderId: "CBE",
      regex:
          r"credited\s+with\s+ETB\s?(?<amount>[\d,.]+).*?Balance\s+is\s+ETB\s?(?<balance>[\d,.]+).*?((id=|BranchReceipt/)(?<reference>FT\w+))",
      type: "CREDIT",
      description: "CBE Credit Basic",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 1,
      senderId: "CBE",
      regex:
          r"debited\s+with\s+ETB\s?(?<amount>[\d,.]+).*?Balance\s+is\s+ETB\s?(?<balance>[\d,.]+).*?((id=|BranchReceipt/)(?<reference>FT\w+))",
      type: "DEBIT",
      description: "CBE Debit Basic",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 1,
      senderId: "CBE",
      regex:
          r"transfered\s+ETB\s?(?<amount>[\d,.]+)\s+to.*?from\s+your\s+account\s+(?<account>[\d\*]+).*?Balance\s+is\s+ETB\s?(?<balance>[\d,.]+).*?((id=|BranchReceipt/)(?<reference>FT\w+))",
      type: "DEBIT",
      description: "CBE Transfer Debit",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 1,
      senderId: "CBE",
      regex:
          r"Account\s+(?<account>\d\*+\d+).*?debited\s+with\s+ETB\s+(?<amount>[\d,.]+).*?Balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "CBE ATM withdrawal",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 1,
      senderId: "CBE",
      regex:
          r"(?:Account|Acct)\s+(?<account>[\d\*]+).*?has\s+been\s+debited\s+with\s+ETB\s?(?<amount>[\d,.]+).*?Current\s+Balance\s+is\s+ETB\s?(?<balance>[\d,.]+).*?(id=|BranchReceipt/)(?<reference>FT\w+)",
      type: "DEBIT",
      description: "CBE to own telebirr",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 1,
      senderId: "CBE",
      regex:
          r"Account\s+(?<account>\d\*+\d+).*?(?<type>credited|debited)\s+with\s+ETB\s+(?<amount>[\d,.]+).*?Balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "CREDIT",
      description: "CBE credit, no ref",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 2,
      senderId: "Awash",
      regex:
          r"account\s+(?<account>[\d\*x]+)\s+has\s+been\s+debited\s+with\s+ETB\s+(?<amount>[\d,.]+).*?Your\s+current\s+balance\s+is\s+ETB\s+(?<balance>[\d,.]+).*?https?:\/\/[^\s]+\/(?<reference>[A-Z0-9-]+)",
      type: "DEBIT",
      description: "Awash Account Debit",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 2,
      senderId: "Awash",
      regex:
          r"Account\s+(?<account>[\d\*x]+)\s+has\s+been\s+Credited\s+with\s+ETB\s+(?<amount>[\d,.]+).*?to\s+Awash\s+with\s+reference\s+(?<reference>[A-Z0-9]+).*?balance\s+now\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "CREDIT",
      description: "Awash Account Credit (TeleBirr C2B)",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 2,
      senderId: "Awash",
      regex:
          r"You\s+have\s+transferred\s+to\s+other\s+bank\s+ETB\s+(?<amount>[\d,.]+)\s+To\s+(?<receiver>[^\(]+).*?Your\s+available\s+Balance\s+is\s+ETB\s+(?<balance>[\d,.]+).*?Receipt\s+Link:\s*https?:\/\/[^\s]+\/(?<reference>[A-Z0-9-]+)",
      type: "DEBIT",
      description: "Awash Other Bank Transfer",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 2,
      senderId: "Awash",
      regex:
          r"Telebirr\s+Transfer\s+of\s+(?<amount>[\d,.]+)\s+ETB\s+to\s+(?<receiver>[^-]+)\s+-\s+(?<receiverAccount>[\d]+).*?Your\s+Balance\s+is\s+ETB\s+(?<balance>[\d,.]+).*?Receipt\s+Link:\s*https?:\/\/[^\s]+\/(?<reference>[A-Z0-9-]+)",
      type: "DEBIT",
      description: "Awash Telebirr Transfer",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 2,
      senderId: "Awash",
      regex:
          r"Account\s+(?<account>[\d\*x]+)\s+has\s+been\s+Credited\s+with\s+ETB\s+(?<amount>[\d,.]+).*?Your\s+balance\s+now\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "CREDIT",
      description: "Awash Account Credit",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 2,
      senderId: "Awash",
      regex:
          r"Merchant\s+payment\s+of\s+(?<amount>[\d,.]+)\s+ETB\s+to\s+(?<receiver>[^.]+)\.\s+Ref\s+(?<reference>[\dA-Z]+).*?Receipt\s+Link:\s*https?:\/\/[^\s]+",
      type: "DEBIT",
      description: "Awash Merchant Payment",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 2,
      senderId: "Awash",
      regex:
          r"Account\s+(?<account>[0-9xX*]+).*?(?:Debited|Credited)\s+with\s+ETB\s+-?(?<amount>[\d,.]+).*?balance\s+now\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Awash debit with no ref",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 2,
      senderId: "Awash",
      regex:
          r"You\s+have\s+transferred\s+to\s+.*?\s+Amount\s+(?<amount>[\d,.]+)\s*ETB\s+To\s+(?<receiverAccount>\d+)\s+\((?<receiver>[^)]+)\).*?Balance\s+is\s+ETB\s+(?<balance>[\d,.]+).*?Receipt\s+Link:\s*https?:\/\/[^\s]+\/(?<reference>[A-Z0-9-]+)",
      type: "DEBIT",
      description: "Awash Other Bank Transfer (Flexible)",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 3,
      senderId: "BOA",
      regex:
          r"account\s+(?<account>[\d\*]+)\s+was\s+debited\s+with\s+ETB\s+(?<amount>[\d,.]+)\s*\.\s*Available\s+Balance:\s*ETB\s+(?<balance>[\d,.]+)\s*\.\s*Receipt:\s*https?:\/\/[^\s]+\?trx=(?<reference>FT[A-Z0-9]+)",
      type: "DEBIT",
      description: "BOA Debit",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 3,
      senderId: "BOA",
      regex:
          r"account\s+(?<account>[\d\*]+).*?credited\s+with\s+ETB\s+(?<amount>[\d,.]+)\s+by\s+(?<source>[^.]+)\.\s+Available\s+Balance:\s+ETB\s+(?<balance>[\d,.]+).*?Receipt:\s*https?:\/\/[^\s]+\?trx=(?<reference>FT[A-Z0-9]+)",
      type: "CREDIT",
      description: "BOA Credit",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 3,
      senderId: "BOA",
      regex:
          r"account\s+(?<account>[\d\*]+).*?credited\s+with\s+ETB\s+(?<amount>[\d,\.]+).*?transfer\s+made\s+by\s+(?<source>.+?)\s+through.*?available\s+balance.*?ETB\s+(?<balance>[\d,\.]+)",
      type: "CREDIT",
      description: "BOA Transfer Credit (old)",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 3,
      senderId: "BOA",
      regex:
          r"account\s+(?<account>[\d\*]+).*?debited\s+with\s+ETB\s+(?<amount>[\d,\.]+).*?account transfer you made\s+through\s+(?<source>.+?)\..*?available\s+balance.*?ETB\s+(?<balance>[\d,\.]+)",
      type: "DEBIT",
      description: "BOA Transfer Debit (old)",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 3,
      senderId: "BOA",
      regex:
          r"account\s+(?<account>[\d\*]+).*?credited\s+with\s+ETB\s+(?<amount>[\d,\.]+).*?transfer\s+made\s+by\s*(?<source>.*?)\s+through.*?available\s+balance.*?ETB\s+(?<balance>[\d,\.]+)",
      type: "CREDIT",
      description: "BOA Transfer Credit (no ref)",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 4,
      senderId: "Dashen",
      regex:
          r"received\s+ETB\s+(?<amount>[\d,.]+).*?Ref\s+No:?\s*(?<reference>\d+).*?on\s+(?<date>\d{2}\/\d{2}\/\d{4})\s+\d{2}:\d{2}:\d{2}.*?account\s+'(?<account>[\d\*]+)'.*?balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "CREDIT",
      description: "Dashen Telebirr Credit",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 4,
      senderId: "Dashen",
      regex:
          r"ETB\s+(?<amount>[\d,.]+)\s+has\s+been\s+debited\s+from\s+your\s+account\s+(?<account>[\d\*]+).*?on\s+(?<date>\d{4}-\d{2}-\d{2})\s+at\s+\d{2}:\d{2}:\d{2}.*?current\s+balance\s+is\s+ETB\s+(?<balance>[\d,.]+).*?receipt\/+(?<reference>[A-Z0-9]+)",
      type: "DEBIT",
      description: "Dashen Telebirr Transfer Debit (with Receipt Ref)",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 4,
      senderId: "Dashen",
      regex:
          r"account\s+'(?<account>[\d\*]+)'.*?credited\s+with\s+ETB\s+(?<amount>[\d,.]+).*?on\s+(?<date>\d{2}\/\d{2}\/\d{4}).*?current\s+balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "CREDIT",
      description: "Dashen Account Credit",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 4,
      senderId: "Dashen",
      regex:
          r"transferred\s+ETB\s+(?<amount>[\d,.]+)\s+to\s+your\s+account\s+'(?<account>[\d\*]+)'.*?on\s+(?<date>\d{2}\/\d{2}\/\d{4}).*?current\s+balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "CREDIT",
      description: "Dashen Account Transfer Credit",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 4,
      senderId: "Dashen",
      regex:
          r"account\s+'(?<account>[\d\*]+)'\s+is\s+debited\s+with\s+ETB\s+(?<amount>[\d,.]+)\s+on\s+(?<date>\d{2}\/\d{2}\/\d{4}).*?current\s+balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Dashen Account Debit",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 4,
      senderId: "Dashen",
      regex:
          r"account\s+(?<account>[\d\*]+)\s+has\s+been\s+debited\s+with\s+ETB\s+(?<amount>[\d,.]+).*?on\s+(?<date>\d{4}-\d{2}-\d{2}).*?current\s+balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Dashen Account Debit 2",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 5,
      senderId: "Zemen",
      regex:
          r"account\s+(?<account>[\dx]+)\s+has\s+been\s+credited\s+with\s+ETB\s+(?<amount>[\d,.]+).*?with\s+reference\s+(?<reference>[A-Z0-9]+)\s+on\s+(?<date>\d{1,2}-[A-Za-z]{3}-\d{4}).*?Current\s+Balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "CREDIT",
      description: "Zemen Account Credit",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 5,
      senderId: "Zemen",
      regex:
          r"Birr\s+(?<amount>[\d,.]+)\s+ATM\s+cash\s+withdrawal.*?from\s+A\/c\s+No\.\s+(?<account>[\dx]+)\s+on\s+(?<date>\d{1,2}-[A-Za-z]{3}-\d{4}).*?Available\s+Bal\.\s+is\s+Birr\s+(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Zemen ATM Withdrawal",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 5,
      senderId: "Zemen",
      regex:
          r"Birr\s+(?<amount>[\d,]+(?:\.\d+)?)\s+Cash\s+deposit.*?to\s+A\/c\s+No\.\s+(?<account>[\dx]+)\s+on\s+(?<date>\d{1,2}-[A-Za-z]{3}-\d{4}).*?Available\s+Bal\.\s+is\s+Birr\s+(?<balance>[\d,]+(?:\.\d+)?)",
      type: "CREDIT",
      description: "Zemen Cash Deposit",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 6,
      senderId: "telebirr",
      regex:
          r"transferred\s+ETB\s?(?<amount>[\d,.]+)\s+to\s+(?<receiver>[^(]+?)\s*\(.*?transaction\s+number\s+is\s+(?<reference>[A-Z0-9]+).*?balance\s+is\s+ETB\s?(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Telebirr P2P Transfer",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 5,
      senderId: "Zemen",
      regex:
          r"Birr\s+(?<amount>[\d,]+(?:\.\d+)?)\s+Inward\s+RTGS\s+transfer.*?to\s+A\/c\s+No\.\s+(?<account>[\dx]+)\s+on\s+(?<date>\d{1,2}-[A-Za-z]{3}-\d{4}).*?Available\s+Bal\.\s+is\s+Birr\s+(?<balance>[\d,]+\.\d{2})",
      type: "CREDIT",
      description: "Zemen Inward RTGS Transfer",
      refRequired: false,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 6,
      senderId: "telebirr",
      regex:
          r"transferred\s+ETB\s+(?<amount>[\d,]+(?:\.\d+)?)\s+successfully\s+from\s+yourtelebirr\s+account\s+(?<account>\d+).*?on\s+(?<date>\d{1,2}/\d{1,2}/\d{4}).*?telebirr\s+transaction\s+number\s+is\s+(?<reference>[A-Z0-9]+).*?current\s+balance\s+is\s+ETB\s+(?<balance>[\d,]+\.\d{2})",
      type: "DEBIT",
      description: "Telebirr Transfer to banks",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 6,
      senderId: "telebirr",
      regex:
          r"transferred\s+ETB\s?(?<amount>[\d,.]+).*?from\s+your\s+telebirr\s+account\s+(?<account>\d+)\s+to\s+(?<receiver>.+?)\s+account\s+number\s+(?<bankAccount>\d+).*?telebirr\s+transaction\s+number\s*is\s*(?<reference>[A-Z0-9]+).*?balance\s+is\s+ETB\s?(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Telebirr to Bank Transfer",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 6,
      senderId: "telebirr",
      regex:
          r"paid\s+ETB\s?(?<amount>[\d,.]+)\s+for\s+goods\s+purchased\s+from\s+(?<receiver>.+?)\s+on.*?transaction\s+number\s+is\s+(?<reference>[A-Z0-9]+).*?balance\s+is\s+ETB\s?(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Telebirr Merchant Purchase",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 6,
      senderId: "telebirr",
      regex:
          r"paid\s+ETB\s?(?<amount>[\d,.]+)\s+to\s+(?<receiver>.+?)\s*(?:;|,\s*Bill).*?transaction\s+number\s+is\s+(?<reference>[A-Z0-9]+).*?balance\s+is\s+ETB\s?(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Telebirr Bill Payment",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 6,
      senderId: "telebirr",
      regex:
          r"received\s+ETB\s?(?<amount>[\d,.]+).*?\s+from\s+(?<sender>.+?)\s+on\s+(?<date>\d{1,2}[\/]\d{1,2}[\/]\d{4}\s+\d{1,2}:\d{2}:\d{2}).*?transaction\s+number\s+is\s*(?<reference>[A-Z0-9]+).*?balance\s+is\s+ETB\s?(?<balance>[\d,.]+)",
      type: "CREDIT",
      description: "Telebirr Money Received (P2P)",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 6,
      senderId: "telebirr",
      regex:
          r"received\s+ETB\s?(?<amount>[\d,.]+)\s+by\s+transaction\s+number\s*(?<reference>[A-Z0-9]+).*?from\s+.*?\s+to\s+your\s+telebirr\s+account.*?balance\s+is\s+ETB\s?(?<balance>[\d,.]+)",
      type: "CREDIT",
      description: "Telebirr Received from Bank",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 6,
      senderId: "telebirr",
      regex:
          r"paid\s+ETB\s+(?<amount>[\d,]+(?:\.\d{2})?)\s+for\s+(?<receiver>.+?)\s+purchase\s+made.*?transaction\s+number\s+is\s+(?<reference>[A-Z0-9]+).*?current\s+balance\s+is\s+ETB\s+(?<balance>[\d,]+(?:\.\d{2})?)",
      type: "DEBIT",
      description: "Telebirr debit for package",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 7,
      senderId: "NIB",
      regex:
          r"Account\s+(?<account>[\d\*]+)\s+has\s+been\s+Debited\s+with\s+ETB\s+-?(?<amount>[\d,.]+)\s+On\s+(?<date>\d{1,2}\s+[A-Z]{3}\s+\d{4})\s+Ref:\s+(?<reference>[A-Z0-9]+).*?Current\s+Balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Nib Account Debit",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 7,
      senderId: "NIB",
      regex:
          r"Account\s+(?<account>[\d\*]+)\s+has\s+been\s+Debited\s+with\s+ETB\s+-?(?<amount>[\d,.]+).*?On\s+(?<date>\d{1,2}\s+[A-Z]{3}\s+\d{4})\s+Ref:\s+(?<reference>[A-Z0-9]+).*?Current\s+Balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Nib Account Debit with Charges",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 7,
      senderId: "NIB",
      regex:
          r"Account\s+(?<account>[\d\*]+)\s+has\s+been\s+Debited\s+with\s+ETB\s+-?(?<amount>[\d,.]+)\s+On\s+(?<date>\d{1,2}\s+[A-Z]{3}\s+\d{4}).*?Ref:\s+(?<reference>[A-Z0-9]+).*?Current\s+Balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "DEBIT",
      description: "Nib Account Debit (Telebirr/Service Charge)",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 7,
      senderId: "NIB",
      regex:
          r"Account\s+(?<account>[\d\*]+)\s+has\s+been\s+Credited\s+with\s+ETB\s+(?<amount>[\d,.]+)\s+On\s+(?<date>\d{1,2}\s+[A-Z]{3}\s+\d{4}).*?Ref:\s+(?<reference>[A-Z0-9]+).*?Current\s+Balance\s+is\s+ETB\s+(?<balance>[\d,.]+)",
      type: "CREDIT",
      description: "Nib Account Credit",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 8,
      senderId: "MPESA",
      regex:
          r"you\s+have\s+deposited\s+(?<amount>[\d,.]+)\s+Birr\s+with\s+agent\s+(?<agent>.*?)\s+on\s+(?<date>\d{1,2}/\d{1,2}/\d{2})\s+at\s+(?<time>\d{1,2}:\d{2}\s+[AP]M)\.\s+Transaction\s+number\s+(?<reference>[A-Z0-9]+)\.\s+Your\s+current\s+M-PESA\s+balance\s+is\s+(?<balance>[\d,.]+)\s+Birr",
      type: "CREDIT",
      description: "M-PESA Deposit from Agent",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 8,
      senderId: "MPESA",
      regex:
          r"የ(?<amount>[\d,.]+)\s+ብር\s+የሳፋሪኮም\s+ጥቅል\s+ለ(?<account>\d+)\s+በ(?<date>\d{1,2}/\d{1,2}/\d{2})\s+በ(?<time>\d{1,2}:\d{2}\s+[AP]M)\s+ላይ\s+ገዝተዋል።\s+የገንዘብ\s+ዝውውር\s+መለያ\s+ቁጥር\s+(?<reference>[A-Z0-9]+)\s+ነው።.*?አሁን\s+ያለዎት\s+የM-PESA\s+ቀሪ\s+ሒሳብ\s+(?<balance>[\d,.]+)\s+ብር",
      type: "DEBIT",
      description: "M-PESA Bundle Purchase (Amharic)",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 8,
      senderId: "MPESA",
      regex:
          r"you\s+have\s+paid\s+(?<amount>[\d,.]+)\s+Birr\s+to\s+(?<receiver>\d+\s+-\s+.*?)\s+on\s+(?<date>\d{1,2}/\d{1,2}/\d{2}).*?at\s+(?<time>\d{1,2}:\d{2}\s+[AP]M)\.\s+Transaction\s+number\s+(?<reference>[A-Z0-9]+).*?Your\s+M-PESA\s+balance\s+is\s+(?<balance>[\d,.]+)\s+Birr",
      type: "DEBIT",
      description: "M-PESA Payment to Merchant",
      refRequired: true,
      hasAccount: true,
    ),
    SmsPattern(
      bankId: 8,
      senderId: "MPESA",
      regex:
          r"(?<amount>[\d,.]+)\s+ብር\s+ከ\s+(?<sender>.*?)\s+በ\s+(?<date>\d{1,2}/\d{1,2}/\d{2})\s+በ\s+(?<time>\d{1,2}:\d{2}\s+[AP]M)\s+ላይ\s+ተቀብለዋል።\s+የገንዘብ\s+ዝውውር\s+መለያ\s+ቁጥር\s+(?<reference>[A-Z0-9]+)\s+ነው።.*?የM-PESA\s+ቀሪ\s+ሒሳብ\s+(?<balance>[\d,.]+)\s+ብር",
      type: "CREDIT",
      description: "M-PESA Received from Bank (Amharic)",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 8,
      senderId: "MPESA",
      regex:
          r"የ(?<amount>[\d,.]+)\s+ብር\s+የአየር\s+ሰዓት\s+ለራስዎ\s+ስልክ\s+በ(?<date>\d{1,2}/\d{1,2}/\d{2})\s+(?<time>\d{1,2}:\d{2}\s+[AP]M)\s+ላይ\s+ገዝተዋል።\s+የገንዘብ\s+ዝውውር\s+መለያ\s+ቁጥር\s+(?<reference>[A-Z0-9]+)\s+ነው።.*?አሁን\s+ያልዎት\s+የM-PESA\s+ቀሪ\s+ሒሳብ\s+(?<balance>[\d,.]+)\s+ብር",
      type: "DEBIT",
      description: "M-PESA Airtime for Self (Amharic)",
      refRequired: true,
      hasAccount: false,
    ),
    SmsPattern(
      bankId: 8,
      senderId: "MPESA",
      regex:
          r"ተመላሽ\s+ስለሆነ\s+(?<amount>[\d,.]+)\s+ብር\s+ወደ\s+M-PESA\s+ሒሳብዎ\s+ገቢ\s+ተደርጓል።\s+የገንዘብ\s+ዝውውር\s+መለያ\s+ቁጥር\s+(?<reference>[A-Z0-9]+)\s+ነው።.*?የM-PESA\s+ቀሪ\s+ሂሳብ\s+(?<balance>[\d,.]+)\s+ብር",
      type: "CREDIT",
      description: "M-PESA Reversal (Amharic)",
      refRequired: true,
      hasAccount: false,
    ),
  ];
  void debugSms(String smsText) {
    // Show invisible characters
    // print("Raw SMS (escaped): ${jsonEncode(smsText)}");

    // // Optionally show code units for each character
    // print("Code units: ${smsText.codeUnits}");
  }

  String cleanSmsText(String text) {
    try {
      // String jsonString = jsonEncode(text);
      // String cleaned = jsonDecode(jsonString);
      // cleaned = cleaned.replaceAll('\r', ' ');
      // cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
      // cleaned = cleaned.replaceAll(RegExp(r'\.\s*([A-Z])'), ' \$1');
      return text.trim();
    } catch (e) {
      print("debug: JSON sanitization failed: $e");
      return text;
    }
  }

  Future<List<SmsPattern>> getPatterns() async {
    final db = await DatabaseHelper.instance.database;

    // First, try to load from database
    final List<Map<String, dynamic>> maps = await db.query('sms_patterns');
    if (maps.isNotEmpty) {
      try {
        final patterns = maps.map((map) {
          return SmsPattern.fromJson({
            'bankId': map['bankId'],
            'senderId': map['senderId'],
            'regex': map['regex'],
            'type': map['type'],
            'description': map['description'],
            'refRequired':
                map['refRequired'] == null ? null : (map['refRequired'] == 1),
            'hasAccount':
                map['hasAccount'] == null ? null : (map['hasAccount'] == 1),
          });
        }).toList();
        print("debug: Loaded ${patterns.length} patterns from database");
        return patterns;
      } catch (e) {
        print("debug: Error parsing stored patterns: $e");
        // Fall through to fetch from remote
      }
    }

    // If not in database, try to fetch from remote (only if internet available)
    final hasInternet = await _hasInternetConnection();
    if (hasInternet) {
      try {
        final patterns = await _fetchRemotePatterns();
        if (patterns.isNotEmpty) {
          await savePatterns(patterns);
          return patterns;
        }
      } catch (e) {
        print("debug: Error fetching remote patterns: $e");
      }
    } else {
      print("debug: No internet connection, cannot fetch remote patterns");
    }

    // Fallback to default patterns
    print("debug: Using default patterns as fallback");
    // Save defaults to database for next time
    await savePatterns(_defaultPatterns);
    return _defaultPatterns;
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      // Check if we have any connection (mobile, wifi, ethernet, etc.)
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }
      // Additional check: try to reach a known server
      try {
        final response = await http
            .get(Uri.parse('https://www.google.com'))
            .timeout(const Duration(seconds: 3));
        return response.statusCode == 200;
      } catch (e) {
        return false;
      }
    } catch (e) {
      print("debug: Error checking connectivity: $e");
      return false;
    }
  }

  Future<List<SmsPattern>> _fetchRemotePatterns() async {
    const String url =
        "https://sms-parsing-visualizer.vercel.app/sms_patterns.json";

    try {
      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        String body = response.body;

        // Handle JavaScript file that might export JSON
        // Remove any JavaScript wrapper if present
        body = body.trim();
        if (body.startsWith('export') ||
            body.startsWith('const') ||
            body.startsWith('var') ||
            body.startsWith('let')) {
          // Extract JSON from JS file
          final jsonMatch =
              RegExp(r'(\[[\s\S]*\])|(\{[\s\S]*\})').firstMatch(body);
          if (jsonMatch != null) {
            body = jsonMatch.group(0)!;
          }
        }

        // Parse JSON
        final dynamic jsonData = jsonDecode(body);
        List<SmsPattern> patterns = [];

        if (jsonData is List) {
          patterns = jsonData
              .map((item) => SmsPattern.fromJson(item as Map<String, dynamic>))
              .toList();
        } else if (jsonData is Map && jsonData.containsKey('patterns')) {
          // Handle case where JSON has a 'patterns' key
          final patternsList = jsonData['patterns'] as List;
          patterns = patternsList
              .map((item) => SmsPattern.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        print("debug: Fetched ${patterns.length} patterns from remote");
        return patterns;
      } else {
        print("debug: Remote fetch failed with status ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("debug: Exception fetching remote patterns: $e");
      return [];
    }
  }

  Future<void> savePatterns(List<SmsPattern> patterns) async {
    final db = await DatabaseHelper.instance.database;

    // Clear existing patterns and insert new ones
    await db.delete('sms_patterns');

    final batch = db.batch();
    for (var pattern in patterns) {
      batch.insert('sms_patterns', {
        'bankId': pattern.bankId,
        'senderId': pattern.senderId,
        'regex': pattern.regex,
        'type': pattern.type,
        'description': pattern.description,
        'refRequired':
            pattern.refRequired == null ? null : (pattern.refRequired! ? 1 : 0),
        'hasAccount':
            pattern.hasAccount == null ? null : (pattern.hasAccount! ? 1 : 0),
      });
    }
    await batch.commit(noResult: true);
    print("debug: Saved ${patterns.length} patterns to database");
  }

  // Method to force fetch remote config (background sync)
  Future<void> syncRemoteConfig({bool showError = false}) async {
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      print("debug: No internet connection, skipping remote sync");
      return;
    }

    try {
      final patterns = await _fetchRemotePatterns();
      if (patterns.isNotEmpty) {
        await savePatterns(patterns);
        print("debug: Successfully synced remote config");
      } else {
        print("debug: Remote sync returned empty patterns");
      }
    } catch (e) {
      print("debug: Error syncing remote config: $e");
      if (showError) {
        rethrow;
      }
    }
  }

  // Initialize patterns on app launch
  // Returns true if internet is needed but not available
  // Only fetches if patterns don't exist (no background sync)
  Future<bool> initializePatterns() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('sms_patterns');

    // If patterns exist, return (no sync - sync only happens on explicit refresh)
    if (maps.isNotEmpty) {
      return false; // No internet needed, we have cached patterns
    }

    // No patterns stored, need to fetch
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      return true; // Internet needed but not available
    }

    // Fetch and save patterns
    try {
      final patterns = await _fetchRemotePatterns();
      if (patterns.isNotEmpty) {
        await savePatterns(patterns);
        return false; // Success
      } else {
        // Fallback to defaults
        await savePatterns(_defaultPatterns);
        return false;
      }
    } catch (e) {
      print("debug: Error initializing patterns: $e");
      // Fallback to defaults
      await savePatterns(_defaultPatterns);
      return false;
    }
  }
}
