# Multi-Solution Dependency Analyzer

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

## Output

The tool generates an interactive HTML report containing:

- Complete dependency graph visualization
- Project and solution statistics
- Interactive filtering and layout options
- Detailed dependency information for each project
- List of circular dependencies (if any)

## Project Structure

```
├── multi-solution-dependency-analyzer.ps1  # Main PowerShell script
├── dependencies.html                       # Generated HTML report (example)
└── README.md                              # This file
```
