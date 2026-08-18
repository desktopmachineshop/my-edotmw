param([int]$Seconds = 30, [double]$Interval = 1.0, [string]$Out = "sample.csv", [string]$Tag = "untagged")

$rows = @()
$deadline = (Get-Date).AddSeconds($Seconds)
$totalMB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1MB,0)

while ((Get-Date) -lt $deadline) {
    $os = Get-CimInstance Win32_OperatingSystem
    $availMB = [math]::Round($os.FreePhysicalMemory/1KB,0)
    $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor | Where-Object {$_.Name -eq '_Total'}).PercentProcessorTime

    $procs = Get-Process -ErrorAction SilentlyContinue
    function WS($names) {
        $g = $procs | Where-Object { $names -contains $_.ProcessName }
        if ($g) { [math]::Round((($g | Measure-Object WorkingSet64 -Sum).Sum)/1MB,0) } else { 0 }
    }
    function CNT($names) {
        @($procs | Where-Object { $names -contains $_.ProcessName }).Count
    }

    $rows += [PSCustomObject]@{
        t         = (Get-Date).ToString("HH:mm:ss")
        tag       = $Tag
        cpu_pct   = $cpu
        avail_mb  = $availMB
        godot_mb  = WS @('godot','Godot','godot.windows.editor.x86_64')
        godot_n   = CNT @('godot','Godot','godot.windows.editor.x86_64')
        wsl_mb    = WS @('vmmemWSL','vmmem')
        docker_mb = WS @('com.docker.backend','Docker Desktop','dockerd','docker')
        claude_mb = WS @('claude')
        claude_n  = CNT @('claude')
        node_mb   = WS @('node')
        ao_mb     = WS @('agent-orchestrator','ao')
        chrome_mb = WS @('chrome','msedge','msedgewebview2')
    }
    Start-Sleep -Milliseconds ([int]($Interval*1000))
}
$rows | Export-Csv -Path $Out -NoTypeInformation -Encoding utf8
"samples=$($rows.Count) total_mb=$totalMB"
"cpu_pct  mean={0:N1} max={1}" -f (($rows | Measure-Object cpu_pct -Average).Average), (($rows | Measure-Object cpu_pct -Maximum).Maximum)
"avail_mb mean={0:N0} min={1}" -f (($rows | Measure-Object avail_mb -Average).Average), (($rows | Measure-Object avail_mb -Minimum).Minimum)
"godot_mb max={0} n_max={1}" -f (($rows | Measure-Object godot_mb -Maximum).Maximum), (($rows | Measure-Object godot_n -Maximum).Maximum)
"wsl_mb   max={0}" -f (($rows | Measure-Object wsl_mb -Maximum).Maximum)
"claude_mb max={0} n_max={1}" -f (($rows | Measure-Object claude_mb -Maximum).Maximum), (($rows | Measure-Object claude_n -Maximum).Maximum)
