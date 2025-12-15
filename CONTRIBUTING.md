# Contributing to Totals

Thank you for your interest in contributing to Totals! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Code Style Guidelines](#code-style-guidelines)
- [Testing](#testing)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Areas for Contribution](#areas-for-contribution)
- [Project Structure](#project-structure)

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on constructive feedback
- Respect different viewpoints and experiences

## Getting Started

### Prerequisites

- Flutter SDK (>=3.2.6)
- Dart SDK
- Git
- Android Studio / Xcode (for mobile development)
- A code editor (VS Code, Android Studio, etc.)

### Setting Up Your Development Environment

1. **Fork and Clone the Repository**
   ```bash
   git clone https://github.com/your-username/totals.git
   cd totals/app
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Verify Setup**
   ```bash
   flutter doctor
   flutter analyze
   ```

4. **Run the App**
   ```bash
   flutter run
   ```

## Development Workflow

### Branch Naming Convention

Use descriptive branch names that indicate the type of change:

- `feature/description` - New features
- `fix/description` - Bug fixes
- `refactor/description` - Code refactoring
- `docs/description` - Documentation updates
- `test/description` - Test additions or updates

Examples:
- `feature/add-dashen-bank-support`
- `fix/sms-parsing-error`
- `refactor/transaction-service`

### Creating a Branch

```bash
# Update your main branch
git checkout main
git pull origin main

# Create a new branch
git checkout -b feature/your-feature-name
```

## Code Style Guidelines

### Dart/Flutter Style

- Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart) style guide
- Use `flutter analyze` to check for style issues
- The project uses `flutter_lints` package - ensure your code passes linting

### Key Style Points

1. **Naming Conventions**
   - Use `lowerCamelCase` for variables, functions, and parameters
   - Use `UpperCamelCase` for classes and types
   - Use `lowercase_with_underscores` for file names
   - Use `SCREAMING_CAPS` for constants

2. **File Organization**
   ```dart
   // 1. Imports (dart: imports first, then package:, then relative)
   import 'dart:async';
   import 'package:flutter/material.dart';
   import 'package:totals/models/account.dart';
   
   // 2. Exports (if any)
   
   // 3. Main code
   ```

3. **Widget Structure**
   - Keep widgets small and focused
   - Extract reusable components to `lib/widgets/`
   - Use `const` constructors where possible
   - Prefer composition over inheritance

4. **Error Handling**
   - Use try-catch blocks for async operations
   - Provide meaningful error messages
   - Log errors appropriately (use `print` for debug, consider logging service for production)

5. **Comments**
   - Write self-documenting code
   - Add comments for complex logic
   - Use DartDoc comments for public APIs

### Example Code Style

```dart
// Good
class AccountCard extends StatelessWidget {
  final Account account;
  
  const AccountCard({
    required this.account,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(account.accountHolderName),
        subtitle: Text(account.accountNumber),
      ),
    );
  }
}

// Avoid
class AccountCard extends StatelessWidget {
  Account account;
  AccountCard(this.account);
  // ... rest of code
}
```

## Testing

### Running Tests

```bash
# Run all tests
flutter test

# Run tests with coverage
flutter test --coverage
```

### Writing Tests

- Write tests for business logic, services, and repositories
- Test edge cases and error scenarios
- Keep tests isolated and independent
- Use descriptive test names

### Test Structure

```dart
void main() {
  group('AccountRepository', () {
    test('should create account successfully', () async {
      // Arrange
      final repository = AccountRepository();
      
      // Act
      final account = await repository.createAccount(
        accountNumber: '123456',
        bankId: 1,
      );
      
      // Assert
      expect(account, isNotNull);
      expect(account.accountNumber, equals('123456'));
    });
  });
}
```

## Commit Guidelines

### Commit Message Format

Use clear, descriptive commit messages:

```
<type>: <subject>

<body (optional)>

<footer (optional)>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Examples

```
feat: add Dashen Bank SMS parsing support

Add regex patterns and parsing logic for Dashen Bank transaction SMS messages.
Includes support for debit, credit, and balance update messages.

Closes #123
```

```
fix: handle null account balance in transaction list

Prevent crash when account balance is null by providing default value.
```

## Pull Request Process

### Before Submitting

1. **Update Your Branch**
   ```bash
   git checkout main
   git pull origin main
   git checkout your-branch
   git rebase main
   ```

2. **Run Checks**
   ```bash
   flutter analyze
   flutter test
   flutter format .
   ```

3. **Test Your Changes**
   - Test on Android device/emulator
   - Test on iOS device/simulator (if applicable)
   - Verify the feature works as expected
   - Check for any regressions

### Submitting a Pull Request

1. **Create the PR**
   - Use a clear, descriptive title
   - Fill out the PR template (if available)
   - Reference related issues

2. **PR Description Should Include**
   - What changes were made
   - Why the changes were made
   - How to test the changes
   - Screenshots (for UI changes)
   - Any breaking changes

3. **Respond to Feedback**
   - Address review comments promptly
   - Make requested changes
   - Ask questions if something is unclear

### PR Checklist

- [ ] Code follows the project's style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] Documentation updated (if needed)
- [ ] Tests added/updated (if applicable)
- [ ] All tests pass
- [ ] No new warnings introduced
- [ ] Changes tested on Android (and iOS if applicable)

## Areas for Contribution

### High Priority

1. **SMS Parsing Patterns**
   - Add support for new banks
   - Improve existing regex patterns
   - Handle edge cases in SMS formats
   - Location: `lib/sms_handler/`, `lib/data/consts.dart`

2. **Bug Fixes**
   - Check open issues for bugs to fix
   - Improve error handling
   - Fix UI/UX issues

3. **Testing**
   - Add unit tests for services and repositories
   - Add widget tests for UI components
   - Improve test coverage

### Medium Priority

1. **UI/UX Improvements**
   - Improve accessibility
   - Enhance animations and transitions
   - Better error messages and user feedback
   - Dark mode improvements

2. **Performance**
   - Optimize database queries
   - Improve app startup time
   - Reduce memory usage

3. **Documentation**
   - Improve code comments
   - Add API documentation
   - Update README with new features
   - Create tutorials or guides

### Nice to Have

1. **New Features**
   - Export functionality (CSV, PDF)
   - Budget tracking
   - Recurring transaction detection
   - Category management

2. **Local Server**
   - Add new API endpoints
   - Improve web UI
   - Add authentication for web access

## Project Structure

### Key Directories

```
lib/
├── components/          # Reusable UI components
├── data/                # Constants and configuration
├── database/            # Database setup and migrations
├── local_server/        # HTTP server for web access
├── models/              # Data models
├── providers/           # State management (Provider)
├── repositories/        # Data access layer
├── screens/             # Main app screens
├── services/            # Business logic services
├── sms_handler/         # SMS processing logic
├── utils/               # Utility functions
└── widgets/             # UI widgets
```

### Architecture Patterns

- **State Management**: Provider pattern
- **Data Layer**: Repository pattern
- **UI Layer**: Widget composition
- **Services**: Singleton pattern for services

### Adding a New Bank

1. Add bank definition to `lib/data/consts.dart`
2. Create SMS parsing patterns in `lib/sms_handler/`
3. Add bank logo to `assets/images/`
4. Test with real SMS messages
5. Update documentation

### Adding a New Feature

1. Create feature branch
2. Implement changes following project structure
3. Add tests
4. Update documentation
5. Submit PR

## Questions?

- Open an issue for bug reports or feature requests
- Check existing issues and discussions
- Review the codebase and documentation

## Thank You!

Your contributions make Totals better for everyone. We appreciate your time and effort!

