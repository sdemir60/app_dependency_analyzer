# Dependency Analyzer

Interactive PowerShell tool for analyzing .NET solution dependencies with web-based visualization. This tool scans multiple Visual Studio solutions and projects, then generates an interactive HTML report showing dependency relationships, circular dependencies, and cross-solution references.

## Usage

### Basic Usage

```powershell
# Analyze dependencies in the current directory
.\multi-solution-dependency-analyzer.ps1

# Analyze specific directory and save to custom output file
.\multi-solution-dependency-analyzer.ps1 -RootPath "D:\YourSourceCode" -OutputPath "dependency-report.html"
```

### Parameters

- **`-RootPath`**: Root directory to scan for solutions and projects (default: `"C:\YourSourceCodeRoot"`)
- **`-OutputPath`**: Output HTML file path (default: `".\dependency-report.html"`)

### Example

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\multi-solution-dependency-analyzer.ps1 -RootPath "D:\OSYSTFS" -OutputPath "dependencies.html"
```

