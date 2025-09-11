# Multi-Solution Dependency Analyzer

Interactive PowerShell tool for analyzing .NET solution dependencies with web-based visualization. This tool scans multiple Visual Studio solutions and projects, then generates an interactive HTML report showing dependency relationships, circular dependencies, and cross-solution references.

## Features

- 🔍 **Multi-Solution Analysis**: Analyzes all `.sln` and `.csproj` files in a directory tree
- 🕸️ **Interactive Visualization**: Web-based dependency graph with zoom, pan, and filter capabilities
- 🔄 **Circular Dependency Detection**: Identifies and highlights circular dependencies
- 🎯 **Advanced Filtering**: Filter by solution or individual projects
- 📊 **Multiple Layout Options**: Physics-based, hierarchical, and circular layouts
- 🎨 **Color-Coded Relationships**: Different colors for project types and dependency types
- 📈 **Dependency Statistics**: Shows total projects, solutions, and dependencies

## Dependency Types

- **Same Solution (ProjectRef)**: Blue - Project references within the same solution
- **Cross Solution (ProjectRef)**: Red - Project references across different solutions  
- **Same Solution (DLL Ref)**: Purple - Assembly references within the same solution
- **Cross Solution (DLL Ref)**: Black - Assembly references across different solutions
- **Circular Dependency**: Orange - Bidirectional dependencies

## Requirements

- Windows PowerShell 5.1 or PowerShell Core 6+
- .NET projects with `.sln` and `.csproj` files
- Modern web browser for viewing the generated report

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

## How to Use the Generated Report

1. **Open the HTML file** in any modern web browser
2. **Filter by Solution**: Use the solution dropdown to focus on specific solutions
3. **Filter by Project**: Select individual projects to see their direct dependencies and dependents
4. **Change Layout**: Switch between Physics, Hierarchical, and Circular layouts
5. **Interactive Controls**:
   - **Show All**: Reset all filters and show complete dependency graph
   - **Show Circular Dependencies**: Display list of circular dependencies
   - **Reset View**: Optimize current view without changing filters
6. **Click on nodes** to see detailed dependency information in the side panel

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

## How It Works

1. **Discovery**: Scans the specified directory for `.sln` and `.csproj` files
2. **Mapping**: Creates relationships between projects and their parent solutions
3. **Analysis**: Extracts dependencies from:
   - ProjectReference elements
   - Reference elements (assembly references)
4. **Circular Detection**: Identifies bidirectional dependencies
5. **Visualization**: Generates interactive HTML with vis.js network visualization

## Supported Dependencies

- **ProjectReference**: Direct project-to-project references
- **Reference**: Assembly/DLL references (excluding system assemblies)
- **Cross-Solution**: Dependencies between projects in different solutions

## Browser Compatibility

- Chrome 60+
- Firefox 55+
- Safari 11+
- Edge 79+

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with your .NET solutions
5. Submit a pull request

## License

This project is open source and available under the [MIT License](LICENSE).

## Screenshots

The generated report includes:
- Interactive dependency graph with multiple layout options
- Solution and project filtering capabilities
- Detailed dependency information panels
- Circular dependency highlighting and reporting

---

**Note**: This tool is designed for .NET projects using traditional `.csproj` and `.sln` files. Modern SDK-style projects are also supported.
