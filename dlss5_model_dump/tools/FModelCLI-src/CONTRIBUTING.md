# Contributing to FModelCLI

Thank you for your interest in contributing to FModelCLI! This document provides guidelines for contributing to the project.

## 🚀 Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** with submodules:
   ```bash
   git clone --recursive https://github.com/yourusername/FModelCLI.git
   cd FModelCLI
   ```
3. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## 🛠️ Development Setup

### Prerequisites

- Windows 10/11 (x64)
- .NET 8.0 SDK or later
- Git
- PowerShell 5.1 or later

### Building

```powershell
# Build the project
.\sync_upstream.ps1

# Test the executable
.\dist\FModelCLI.exe "path\to\test\paks" "0xTESTKEY" "output" "ConfigDB"
```

## 📝 Code Guidelines

### Code Style

- Follow standard C# conventions
- Use meaningful variable names
- Add comments for complex logic
- Keep functions focused and concise

### Example:

```csharp
// Good
var gameDirectory = args[0];
if (string.IsNullOrWhiteSpace(gameDirectory))
{
    Console.WriteLine("[Error] Game directory cannot be empty");
    return;
}

// Avoid
var gd = args[0];
if (gd == null || gd == "") return;
```

### Commit Messages

Use clear, descriptive commit messages:

```
✅ Good:
- "Add support for multiple AES keys"
- "Fix null reference in directory creation"
- "Update README with new examples"

❌ Avoid:
- "fix bug"
- "update"
- "changes"
```

## 🧪 Testing

Before submitting a PR, please test your changes:

1. **Build successfully**: Run `.\sync_upstream.ps1` without errors
2. **Test extraction**: Verify the tool extracts files correctly
3. **Check edge cases**: Test with invalid inputs, missing keys, etc.

### Test Checklist

- [ ] Code compiles without warnings (in FModelCLI project)
- [ ] Executable runs without crashes
- [ ] Extraction works with valid inputs
- [ ] Error messages are clear and helpful
- [ ] No regression in existing functionality

## 📋 Pull Request Process

1. **Update documentation** if you've changed functionality
2. **Test thoroughly** on your local machine
3. **Create a PR** with a clear description of changes
4. **Link related issues** if applicable
5. **Respond to feedback** from reviewers

### PR Template

```markdown
## Description
Brief description of what this PR does

## Changes
- List of changes made
- Another change

## Testing
How you tested these changes

## Related Issues
Fixes #123
```

## 🐛 Reporting Bugs

When reporting bugs, please include:

- **OS version** (Windows 10/11)
- **.NET version** (if building from source)
- **Steps to reproduce** the issue
- **Expected behavior** vs **actual behavior**
- **Error messages** or logs
- **Sample command** that triggers the bug

### Bug Report Template

```markdown
**Environment:**
- OS: Windows 11 22H2
- FModelCLI version: v1.0.0

**Steps to Reproduce:**
1. Run command: `FModelCLI.exe ...`
2. See error

**Expected:**
Files should be extracted

**Actual:**
Error: [error message]

**Logs:**
[paste relevant logs]
```

## 💡 Feature Requests

We welcome feature requests! Please:

1. **Check existing issues** to avoid duplicates
2. **Describe the use case** clearly
3. **Explain the benefit** to users
4. **Suggest implementation** if you have ideas

## 🔧 Areas for Contribution

### Easy (Good First Issues)

- Improve error messages
- Add more usage examples to README
- Fix typos in documentation
- Add validation for edge cases

### Medium

- Add support for new game versions
- Improve progress reporting
- Add configuration file support
- Enhance filtering capabilities

### Advanced

- Optimize extraction performance
- Add parallel processing
- Implement custom export formats
- Add GUI wrapper (separate project)

## 📜 Code of Conduct

### Our Standards

- Be respectful and inclusive
- Accept constructive criticism gracefully
- Focus on what's best for the community
- Show empathy towards others

### Unacceptable Behavior

- Harassment or discriminatory language
- Trolling or insulting comments
- Publishing others' private information
- Other unprofessional conduct

## 📞 Questions?

- **General questions**: Use [GitHub Discussions](https://github.com/yourusername/FModelCLI/discussions)
- **Bug reports**: Open an [Issue](https://github.com/yourusername/FModelCLI/issues)
- **Security issues**: Email [security@example.com](mailto:security@example.com)

## 📄 License

By contributing, you agree that your contributions will be licensed under the GNU General Public License v3.0.

All contributions must be compatible with GPL-3.0. You cannot submit code that is licensed under incompatible licenses (e.g., proprietary code).

---

Thank you for contributing to FModelCLI! 🎉
