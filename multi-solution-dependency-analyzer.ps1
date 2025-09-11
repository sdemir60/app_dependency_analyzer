# multi-solution-dependency-analyzer.ps1 (v2 - Fixed)

param(
    [string]$RootPath = "C:\YourSourceCodeRoot",
    [string]$OutputPath = ".\dependency-report.html"
)

Write-Host "Analyzing dependencies across all solutions..." -ForegroundColor Green

# Tüm solution ve projeleri bul
$solutions = Get-ChildItem -Path $RootPath -Filter "*.sln" -Recurse
$projects  = Get-ChildItem -Path $RootPath -Filter "*.csproj" -Recurse

Write-Host "Found $($solutions.Count) solutions and $($projects.Count) projects" -ForegroundColor Yellow

# Haritalar
$projectMap = @{}                 # projename -> { Path, Solution, FullName, AssemblyName }
$assemblyToProject = @{}          # AssemblyName -> ProjectName
$dependencies = @()               # { From, To, Type, FromSolution }

# Proje -> Solution eşlemesi ve AssemblyName çıkarımı
foreach ($project in $projects) {
    $projName = [IO.Path]::GetFileNameWithoutExtension($project.Name)
    $projPath = $project.FullName

    # Hangi solution'da?
    $parentSolution = ""
    foreach ($sln in $solutions) {
        $slnContent = Get-Content $sln.FullName -Raw
        if ($slnContent -match [regex]::Escape($project.Name)) {
            $parentSolution = [IO.Path]::GetFileNameWithoutExtension($sln.Name)
            break
        }
    }

    # AssemblyName (yoksa proje adı)
    try {
        [xml]$xml = Get-Content $projPath -Raw
        $asmName = ($xml.Project.PropertyGroup | ForEach-Object { $_.AssemblyName } | Where-Object { $_ } | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($asmName)) { $asmName = $projName }
    } catch {
        $asmName = $projName
    }

    $projectMap[$projName] = @{
        Path     = $projPath
        Solution = $parentSolution
        FullName = "$parentSolution.$projName"
        Assembly = $asmName
    }

    # AssemblyName -> Proje adı haritası
    if (-not $assemblyToProject.ContainsKey($asmName)) {
        $assemblyToProject[$asmName] = $projName
    }
}

# Bağımlılıkları topla (ProjectReference + Assembly Reference)
foreach ($project in $projects) {
    $projName = [IO.Path]::GetFileNameWithoutExtension($project.Name)
    $projInfo = $projectMap[$projName]
    $parentSolution = $projInfo.Solution

    $content = Get-Content $projInfo.Path -Raw

    # 1) ProjectReference
    [regex]::Matches($content, '<ProjectReference Include="(.+?)"') | ForEach-Object {
        $refPath = $_.Groups[1].Value
        $refName = [IO.Path]::GetFileNameWithoutExtension($refPath)

        $dependencies += @{
            From         = $projName
            To           = $refName
            Type         = "ProjectReference"
            FromSolution = $parentSolution
        }
    }

    # 2) Assembly Reference (DLL)
    try {
        [xml]$xml = Get-Content $projInfo.Path -Raw
        $refNodes = @()
        if ($xml.Project.ItemGroup) {
            foreach ($ig in $xml.Project.ItemGroup) {
                if ($ig.Reference) { $refNodes += $ig.Reference }
            }
        }

        foreach ($ref in $refNodes) {
            $include = $ref.Include
            if ([string]::IsNullOrWhiteSpace($include)) { continue }

            # "Name, Version=..., Culture=..." -> sadece isim
            $includeName = $include.Split(',')[0].Trim()

            # Sistem / BCL referanslarını ele
            if ($includeName -match '^(System(\.|$)|Microsoft(\.|$)|Windows(\.|$)|netstandard$)') { continue }

            # HintPath varsa muhtemelen local dll referansı
            $hint = $ref.HintPath
            $hasHint = -not [string]::IsNullOrWhiteSpace($hint)

            # Hedef proje var mı? (AssemblyName eşleşmesi)
            if ($assemblyToProject.ContainsKey($includeName)) {
                $targetProj = $assemblyToProject[$includeName]
                if ($targetProj -ne $projName) {
                    $dependencies += @{
                        From         = $projName
                        To           = $targetProj
                        Type         = "AssemblyReference"
                        FromSolution = $parentSolution
                    }
                }
            }
        }
    } catch { }
}

# Circular dependency tespiti
$edgeSet = @{}
$circularDeps = @()

foreach ($dep in $dependencies) {
    if ($projectMap.ContainsKey($dep.From) -and $projectMap.ContainsKey($dep.To)) {
        $edgeKey = "$($dep.From)-$($dep.To)"
        $reverseKey = "$($dep.To)-$($dep.From)"
        
        if ($edgeSet.ContainsKey($reverseKey)) {
            $circularDeps += "$($dep.From) `<-`> $($dep.To)"
        }
        $edgeSet[$edgeKey] = $true
    }
}

Write-Host "Creating interactive HTML report..." -ForegroundColor Green

# HTML/JS hazırlığı
$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>Multi-Solution Dependency Analyzer</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/vis-network/9.1.2/dist/vis-network.min.js"></script>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/vis-network/9.1.2/dist/vis-network.min.css" rel="stylesheet" />
    <style>
        body { font-family: Arial, sans-serif; margin:0; padding:20px; background:#f5f5f5; }
        #controls { background:#fff; padding:15px; margin-bottom:20px; border-radius:5px; box-shadow:0 2px 4px rgba(0,0,0,0.1); }
        #controls button, #controls select { margin:5px; padding:8px 15px; border:1px solid #ddd; border-radius:3px; background:#fff; cursor:pointer; }
        #controls button:hover { background:#f0f0f0; }
        #mynetwork { width:100%; height:700px; border:1px solid #ddd; background:#fff; border-radius:5px; }
        #info { position:absolute; top:100px; right:20px; width:320px; background:#fff; padding:15px; border-radius:5px; box-shadow:0 2px 4px rgba(0,0,0,0.1); max-height:500px; overflow-y:auto; display:none; }
        .legend { display:inline-block; margin:10px; }
        .legend-item { display:inline-block; margin-right:20px; }
        .legend-color { display:inline-block; width:20px; height:20px; margin-right:5px; vertical-align:middle; border:1px solid #999; }
        #stats { margin-top:10px; padding:10px; background:#f9f9f9; border-radius:3px; }
    </style>
</head>
<body>
    <h1>Multi-Solution Dependency Analyzer</h1>

    <div id="controls">
        <button onclick="showAll()">Show All</button>
        <button onclick="showCircularDeps()">Show Circular Dependencies</button>
        <button onclick="resetGraph()">Reset View</button>

        <select id="solutionFilter" onchange="filterBySolution()">
            <option value="">All Solutions</option>
"@

# Solution seçenekleri
$solutions | ForEach-Object {
    $slnName = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    $optionHtml = "<option value='" + $slnName + "'>" + $slnName + "</option>"
    $html += "            $optionHtml`n"
}

$html += @"
        </select>

        <select id="projectFilter" onchange="filterByProject()" style="display:none;">
            <option value="">All Projects in Solution</option>
        </select>

        <select id="layoutSelect" onchange="changeLayout()">
            <option value="physics">Physics Layout</option>
            <option value="hierarchical">Hierarchical Layout</option>
            <option value="circular">Circular Layout</option>
        </select>

        <div class="legend">
            <span class="legend-item"><span class="legend-color" style="background:#97C2FC;"></span>Same Solution (ProjectRef)</span>
            <span class="legend-item"><span class="legend-color" style="background:#FB7E81;"></span>Cross Solution (ProjectRef)</span>
            <span class="legend-item"><span class="legend-color" style="background:#9370DB;"></span>Same Solution (DLL Ref)</span>
            <span class="legend-item"><span class="legend-color" style="background:#111111;"></span>Cross Solution (DLL Ref)</span>
            <span class="legend-item"><span class="legend-color" style="background:#FFA500;"></span>Circular Dependency</span>
        </div>
    </div>

    <div id="stats">
        <strong>Statistics:</strong>
        Total Projects: $($projects.Count) |
        Total Solutions: $($solutions.Count) |
        Total Dependencies: $($dependencies.Count)
    </div>

    <div id="mynetwork"></div>
    <div id="info">
        <h3>Selected Node Info</h3>
        <div id="nodeInfo"></div>
    </div>

    <script>
        // Node'ları oluştur
        var nodes = new vis.DataSet([
"@

# Node'lar
$nodeId = 1
$nodeMap = @{}
$solutionIndex = 0
$solutionColorMap = @{}
$colors = @('#FF6B6B','#4ECDC4','#45B7D1','#96CEB4','#FFEAA7','#DDA0DD','#98D8C8','#F7DC6F','#85C1E2','#F8B739')

foreach ($projName in $projectMap.Keys) {
    $proj = $projectMap[$projName]
    $solution = $proj.Solution
    if (-not $solutionColorMap.ContainsKey($solution)) { 
        $solutionColorMap[$solution] = $solutionIndex % 10
        $solutionIndex++ 
    }
    $nodeMap[$projName] = $nodeId
    $nodeHtml = "{id:$nodeId,label:'$projName',title:'Solution: $solution',group:'$solution',solution:'$solution'},"
    $html += "            $nodeHtml`n"
    $nodeId++
}

# Nodes kapanışı
$html += @"
        ]);

        // Circular dependencies listesi
"@

# Circular dependencies JSON (tek sefer)
$circles = @($circularDeps | Select-Object -Unique)
if ($circles.Count -eq 0) {
    $html += "        var circularList = [];`n"
} else {
    $circlesJson = ($circles | ConvertTo-Json -Compress)
    $html += "        var circularList = $circlesJson;`n"
}

# Edges
$html += @"

        // Edge'leri oluştur
        var edges = new vis.DataSet([
"@

# Kenarları tekrar işle (circular detection zaten yapıldı)
foreach ($dep in $dependencies) {
    if ($nodeMap.ContainsKey($dep.From) -and $nodeMap.ContainsKey($dep.To)) {
        $fromId = $nodeMap[$dep.From]
        $toId   = $nodeMap[$dep.To]
        $edgeKey = "$($dep.From)-$($dep.To)"
        $reverseKey = "$($dep.To)-$($dep.From)"

        $fromSolution = $projectMap[$dep.From].Solution
        $toSolution   = $projectMap[$dep.To].Solution
        $isCrossSolution = $fromSolution -ne $toSolution
        $isCircular = $edgeSet.ContainsKey($reverseKey)

        # Renk seçimi
        if ($isCircular) {
            $color = "#FFA500"
            $width = 3
        }
        else {
            switch ($dep.Type) {
                "ProjectReference" {
                    if ($isCrossSolution) {
                        $color = "#FB7E81"; $width = 2
                    } else {
                        $color = "#97C2FC"; $width = 1
                    }
                }
                "AssemblyReference" {
                    if ($isCrossSolution) {
                        $color = "#111111"; $width = 2
                    } else {
                        $color = "#9370DB"; $width = 1
                    }
                }
                default {
                    $color = "#97C2FC"; $width = 1
                }
            }
        }

        $edgeHtml = "{from:$fromId,to:$toId,color:'$color',width:$width,arrows:'to',title:'$($dep.Type)'},"
        $html += "            $edgeHtml`n"
    }
}

$html += @"
        ]);

        // Network oluştur
        var container = document.getElementById('mynetwork');
        var data = { nodes: nodes, edges: edges };
        var options = {
            physics:{ enabled:true, solver:'forceAtlas2Based', stabilization:{ iterations:100 } },
            edges:{ smooth:{ type:'curvedCW', roundness:0.2 } },
            groups:{
"@

foreach ($sln in $solutionColorMap.Keys) {
    $colorIndex = $solutionColorMap[$sln]
    $groupHtml = "'$sln': { color: { background: '$($colors[$colorIndex])' } },"
    $html += "                $groupHtml`n"
}

$html += @"
            },
            interaction:{ hover:true, tooltipDelay:200 }
        };

        var network = new vis.Network(container, data, options);

        // Event handlers
        network.on('click', function(params){
            if(params.nodes.length>0){
                var nodeId = params.nodes[0];
                var node = nodes.get(nodeId);
                showNodeInfo(node);
            }
        });

        function showNodeInfo(node){
            var info = document.getElementById('info');
            var nodeInfo = document.getElementById('nodeInfo');

            var connectedEdges = edges.get({ filter: function(e){ return e.from===node.id || e.to===node.id; }});
            var dependencies = connectedEdges.filter(e => e.from===node.id);
            var dependents   = connectedEdges.filter(e => e.to===node.id);

            var html = '<strong>Project:</strong> '+node.label+'<br>';
            html += '<strong>Solution:</strong> '+node.solution+'<br><br>';

            html += '<strong>Dependencies ('+dependencies.length+'):</strong><br>';
            dependencies.forEach(function(e){
                var target = nodes.get(e.to);
                html += '→ '+target.label+' ('+target.solution+') ['+(e.title||'')+']<br>';
            });

            html += '<br><strong>Used By ('+dependents.length+'):</strong><br>';
            dependents.forEach(function(e){
                var source = nodes.get(e.from);
                html += '← '+source.label+' ('+source.solution+') ['+(e.title||'')+']<br>';
            });

            nodeInfo.innerHTML = html;
            info.style.display = 'block';
        }

        // Get all dependencies recursively
        function getAllDependencies(nodeIds) {
            var allIds = new Set(nodeIds);
            var toCheck = [...nodeIds];
            
            while(toCheck.length > 0) {
                var currentId = toCheck.pop();
                var deps = edges.get({ filter: function(e){ return e.from === currentId; }});
                deps.forEach(function(e) {
                    if(!allIds.has(e.to)) {
                        allIds.add(e.to);
                        toCheck.push(e.to);
                    }
                });
            }
            
            return Array.from(allIds);
        }

        // Get all dependents recursively
        function getAllDependents(nodeIds) {
            var allIds = new Set(nodeIds);
            var toCheck = [...nodeIds];
            
            while(toCheck.length > 0) {
                var currentId = toCheck.pop();
                var deps = edges.get({ filter: function(e){ return e.to === currentId; }});
                deps.forEach(function(e) {
                    if(!allIds.has(e.from)) {
                        allIds.add(e.from);
                        toCheck.push(e.from);
                    }
                });
            }
            
            return Array.from(allIds);
        }

        // Get direct dependencies only (not recursive)
        function getDirectDependencies(nodeId) {
            var deps = edges.get({ filter: function(e){ return e.from === nodeId; }});
            return deps.map(e => e.to);
        }

        // Get direct dependents only (not recursive)
        function getDirectDependents(nodeId) {
            var deps = edges.get({ filter: function(e){ return e.to === nodeId; }});
            return deps.map(e => e.from);
        }

        function filterBySolution(){
            var selected = document.getElementById('solutionFilter').value;
            var projectFilter = document.getElementById('projectFilter');
            
            if(selected===''){
                // Show all
                nodes.update(nodes.get().map(n=>({id:n.id,hidden:false})));
                edges.update(edges.get().map(e=>({id:e.id,hidden:false})));
                if(projectFilter) {
                    projectFilter.style.display = 'none';
                    projectFilter.innerHTML = '<option value="">All Projects in Solution</option>';
                }
                
                // Fit to all nodes
                setTimeout(function() {
                    network.fit({ animation: { duration: 800, easingFunction: 'easeInOutQuad' } });
                }, 100);
                
            }else{
                // Get nodes in selected solution
                var solutionNodes = nodes.get({ filter:n=>n.solution===selected });
                var solutionNodeIds = solutionNodes.map(n=>n.id);
                
                // Get only direct dependencies of solution projects (not recursive)
                var allRelatedIds = new Set(solutionNodeIds);
                solutionNodeIds.forEach(nodeId => {
                    var directDeps = getDirectDependencies(nodeId);
                    directDeps.forEach(depId => allRelatedIds.add(depId));
                });
                
                var finalIds = Array.from(allRelatedIds);
                
                // Update visibility
                nodes.update(nodes.get().map(n=>({id:n.id,hidden:!finalIds.includes(n.id)})));
                edges.update(edges.get().map(e=>({
                    id:e.id,
                    hidden:!(finalIds.includes(e.from) && finalIds.includes(e.to))
                })));
                
                // Populate project filter
                if(projectFilter) {
                    projectFilter.style.display = 'inline-block';
                    projectFilter.innerHTML = '<option value="">All Projects in Solution</option>';
                    solutionNodes.forEach(function(node) {
                        projectFilter.innerHTML += '<option value="'+node.id+'">'+node.label+'</option>';
                    });
                }
                
                // Fit to visible nodes
                setTimeout(function() {
                    network.fit({ 
                        nodes: finalIds, 
                        animation: { duration: 800, easingFunction: 'easeInOutQuad' }
                    });
                }, 100);
            }
        }
        
        // Get direct dependencies only (not recursive)
        function getDirectDependencies(nodeId) {
            var deps = edges.get({ filter: function(e){ return e.from === nodeId; }});
            return deps.map(e => e.to);
        }

        // Get direct dependents only (not recursive)
        function getDirectDependents(nodeId) {
            var deps = edges.get({ filter: function(e){ return e.to === nodeId; }});
            return deps.map(e => e.from);
        }

        function filterByProject(){
            var projectFilterElement = document.getElementById('projectFilter');
            if(!projectFilterElement) return;
            
            var projectId = projectFilterElement.value;
            
            if(projectId === ''){
                // Re-apply solution filter
                filterBySolution();
            } else {
                var nodeId = parseInt(projectId);
                
                // Get direct dependencies and dependents (1 level only)
                var directDeps = getDirectDependencies(nodeId);
                var directDependents = getDirectDependents(nodeId);
                var finalIds = [nodeId, ...directDeps, ...directDependents]; // Selected project + 1 level deps + 1 level dependents
                
                // Update visibility - show selected project with 1 level dependencies and dependents
                nodes.update(nodes.get().map(n=>({id:n.id,hidden:!finalIds.includes(n.id)})));
                edges.update(edges.get().map(e=>({
                    id:e.id,
                    hidden:!(finalIds.includes(e.from) && finalIds.includes(e.to))
                })));
                
                // Focus on the selected project
                setTimeout(function() {
                    // First fit to all visible nodes
                    network.fit({ 
                        nodes: finalIds, 
                        animation: { duration: 800, easingFunction: 'easeInOutQuad' }
                    });
                    
                    // Then focus on the selected node
                    setTimeout(function() {
                        network.focus(nodeId, { 
                            scale: 1.2,
                            animation: { duration: 500, easingFunction: 'easeInOutQuad' }
                        });
                    }, 900);
                }, 100);
            }
        }

        function showCircularDeps(){
            if(circularList && circularList.length > 0){
                var txt = 'Circular Dependencies Found:\n' + circularList.join('\n');
                alert(txt);
            } else {
                alert('No circular dependencies found!');
            }
        }

        function changeLayout(){
            var layout = document.getElementById('layoutSelect').value;
            
            // Store current visible nodes for proper fitting
            var visibleNodes = nodes.get({ filter: function(n) { return !n.hidden; }});
            var visibleNodeIds = visibleNodes.map(n => n.id);
            
            if(layout==='hierarchical'){
                options.layout = { 
                    hierarchical: { 
                        direction: 'UD', 
                        sortMethod: 'directed',
                        levelSeparation: 100,
                        nodeSpacing: 100,
                        treeSpacing: 100,
                        blockShifting: true,
                        edgeMinimization: true,
                        parentCentralization: true
                    } 
                };
                options.physics = { enabled: false };
                options.edges = { 
                    smooth: { 
                        type: 'cubicBezier', 
                        forceDirection: 'vertical', 
                        roundness: 0.2 
                    } 
                };
            }else if(layout==='circular'){
                options.layout = { randomSeed: 1 };
                options.physics = { 
                    enabled: true,
                    solver: 'repulsion',
                    repulsion: {
                        centralGravity: 0.3,
                        springLength: 150,
                        springConstant: 0.1,
                        damping: 0.4,
                        nodeDistance: 150
                    },
                    stabilization: { iterations: 100 }
                };
                options.edges = { smooth: { type: 'continuous', roundness: 0.5 } };
            }else{
                // Physics layout - default and most stable
                delete options.layout;
                options.physics = { 
                    enabled: true, 
                    solver: 'forceAtlas2Based',
                    forceAtlas2Based: {
                        gravitationalConstant: -26,
                        centralGravity: 0.005,
                        springLength: 230,
                        springConstant: 0.18,
                        damping: 0.4,
                        avoidOverlap: 0.5
                    },
                    stabilization: { 
                        enabled: true,
                        iterations: 100,
                        updateInterval: 25
                    }
                };
                options.edges = { smooth: { type: 'continuous', roundness: 0.5 } };
            }
            
            network.setOptions(options);
            
            // Wait a bit for layout to settle, then fit to visible nodes
            setTimeout(function() {
                if(visibleNodeIds.length > 0) {
                    network.fit({ nodes: visibleNodeIds, animation: true });
                } else {
                    network.fit({ animation: true });
                }
            }, 500);
        }

        function showAll(){
            // Reset all filters to initial state
            document.getElementById('solutionFilter').value = '';
            var projectFilter = document.getElementById('projectFilter');
            if(projectFilter) {
                projectFilter.value = '';
                projectFilter.style.display = 'none';
            }
            
            // Show all nodes and edges
            nodes.update(nodes.get().map(n=>({id:n.id,hidden:false})));
            edges.update(edges.get().map(e=>({id:e.id,hidden:false})));
            
            // Reset to default physics layout for best initial view
            document.getElementById('layoutSelect').value = 'physics';
            delete options.layout;
            options.physics = { 
                enabled: true, 
                solver: 'forceAtlas2Based',
                forceAtlas2Based: {
                    gravitationalConstant: -26,
                    centralGravity: 0.005,
                    springLength: 230,
                    springConstant: 0.18,
                    damping: 0.4,
                    avoidOverlap: 0.5
                },
                stabilization: { 
                    enabled: true,
                    iterations: 100,
                    updateInterval: 25
                }
            };
            options.edges = { smooth: { type: 'continuous', roundness: 0.5 } };
            network.setOptions(options);
            
            // Fit to all nodes with animation
            setTimeout(function() {
                network.fit({ animation: { duration: 1000, easingFunction: 'easeInOutQuad' } });
            }, 100);
        }

        function resetGraph(){ 
            // Don't change filters - just optimize current view
            var visibleNodes = nodes.get({ filter: function(n) { return !n.hidden; }});
            var visibleNodeIds = visibleNodes.map(n => n.id);
            
            if(visibleNodeIds.length > 0) {
                // Fit to visible nodes with animation
                network.fit({ 
                    nodes: visibleNodeIds, 
                    animation: { duration: 1000, easingFunction: 'easeInOutQuad' } 
                });
            } else {
                // If no visible nodes, fit to all
                network.fit({ animation: { duration: 1000, easingFunction: 'easeInOutQuad' } });
            }
        }
    </script>
</body>
</html>
"@

# HTML kaydet
$html | Out-File -FilePath $OutputPath -Encoding UTF8

Write-Host "`nAnalysis complete!" -ForegroundColor Green
Write-Host "Report saved to: $OutputPath" -ForegroundColor Yellow

# Özet
$circularDepsCount = ($circularDeps | Select-Object -Unique).Count
Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "- Total Solutions: $($solutions.Count)"
Write-Host "- Total Projects:  $($projects.Count)"
Write-Host "- Total Dependencies: $($dependencies.Count)"
Write-Host "- Circular Dependencies: $circularDepsCount"

if ($circularDepsCount -gt 0) {
    Write-Host "`nCircular Dependencies Found:" -ForegroundColor Red
    $circularDeps | Select-Object -Unique | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Yellow
    }
}

# Tarayıcıda aç
Start-Process $OutputPath