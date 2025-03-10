# ----------------------------------------------------------------------------------
#
# Copyright Microsoft Corporation
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------------
[CmdletBinding(DefaultParameterSetName = "AllSet")]
param (
    [string]$RepoRoot,
    [string]$Configuration = 'Debug',
    [Parameter(ParameterSetName = "AllSet")]
    [string]$TestsToRun = 'All',
    [Parameter(ParameterSetName = "CIPlanSet", Mandatory = $true)]
    [switch]$CIPlan,
    [Parameter(ParameterSetName = "ModifiedModuleSet", Mandatory = $true)]
    [switch]$ModifiedModule,
    [Parameter(ParameterSetName = "TargetModuleSet", Mandatory = $true)]
    [string[]]$TargetModule,
    [switch]$ForceRegenerate,
    [switch]$InvokedByPipeline,
    [switch]$GenerateDocumentationFile,
    [switch]$EnableTestCoverage,
    [string]$Scope = 'Netcore',
    [boolean]$CodeSign = $false

)
Write-Host "---- in BuildModules, step 1"
if (($null -eq $RepoRoot) -or (0 -eq $RepoRoot.Length)) {
    $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
}

Write-Host "---- in BuildModules, step 2"
$notModules = @('lib', 'shared', 'helpers')
$coreTestModule = @('Compute', 'Network', 'Resources', 'Sql', 'Websites')
$RepoArtifacts = Join-Path $RepoRoot "artifacts"

Write-Host "---- in BuildModules, step 3"

$csprojFiles = @()
$testModule = @()
$toolDirectory = Join-Path $RepoRoot "tools"
$sourceDirectory = Join-Path $RepoRoot "src"
$generatedDirectory = Join-Path $RepoRoot "generated"

Write-Host "---- in BuildModules, step 4"

$BuildScriptsModulePath = Join-Path $toolDirectory 'BuildScripts' 'BuildScripts.psm1'
Import-Module $BuildScriptsModulePath

Write-Host "---- in BuildModules, step 5"

if (-not (Test-Path $sourceDirectory)) {
    Write-Warning "Cannot find source directory: $sourceDirectory"
}
elseif (-not (Test-Path $generatedDirectory)) {
    Write-Warning "Cannot find generated directory: $generatedDirectory"
}

Write-Host "---- in BuildModules, step 6"

# Add Accounts to target module by default, this is to ensure accounts is always built when target/modified module parameter sets
$TargetModule += 'Accounts'
$testModule += 'Accounts'

switch ($PSCmdlet.ParameterSetName) {
    'AllSet' {
        Write-Host "----------Start building all modules----------" -ForegroundColor DarkYellow
        foreach ($module in (Get-Childitem -Path $sourceDirectory -Directory)) {
            $moduleName = $module.Name
            if ($moduleName -in $notModules) {
                continue
            }
            $TargetModule += $moduleName
            Write-Host "$moduleName" -ForegroundColor DarkYellow
        }
        if ('Core' -eq $TestsToRun) {
            $testModule = $coreTestModule
        }
        elseif ('NonCore' -eq $TestsToRun) {
            $testModule = $TargetModule | Where-Object { $_ -notin $coreTestModule }
        }
        else {
            $testModule = $TargetModule
        }
    }
    'CIPlanSet' {
        $CIPlanPath = Join-Path $RepoArtifacts "PipelineResult" "CIPlan.json"
        If (Test-Path $CIPlanPath) {
            $CIPlanContent = Get-Content $CIPlanPath | ConvertFrom-Json
            foreach ($build in $CIPlanContent.build) {
                $TargetModule += $build
            }
            foreach ($test in $CIPlanContent.test) {
                $testModule += $test
            }
        }
        Write-Host "----------Start building modules from $CIPlanPath----------`r`n$($TargetModule | Join-String -Separator "`r`n")" -ForegroundColor DarkYellow
    }
    'ModifiedModuleSet' {
        $changelogPath = Join-Path $RepoRoot "tools" "Azpreview" "changelog.md"
        if (Test-Path $changelogPath) {
            $content = Get-Content -Path $changelogPath
            $continueReading = $false
            foreach ($line in $content) {
                if ($line -match "^##\s\d+\.\d+\.\d+") {
                    if ($continueReading) {
                        break
                    }
                    else {
                        $continueReading = $true
                    }
                }
                elseif ($continueReading -and $line -match "^####\sAz\.(\w+)") {
                    $TargetModule += $matches[1]
                }
            }
        }
        $testModule = $TargetModule
        Write-Host "----------Start building modified modules----------`r`n$($TargetModule | Join-String -Separator "`r`n")" -ForegroundColor DarkYellow
    }
    'TargetModuleSet' {
        $testModule = $TargetModule
        Write-Host "----------Start building target modules----------`r`n$($TargetModule | Join-String -Separator "`r`n")" -ForegroundColor DarkYellow
    }
}

Write-Host "---- in BuildModules, step 7"

$TargetModule = $TargetModule | Select-Object -Unique
$testModule = $testModule | Select-Object -Unique

Write-Host "---- in BuildModules, step 8"

# Prepare autorest based modules
$prepareScriptPath = Join-Path $toolDirectory 'BuildScripts' 'PrepareAutorestModule.ps1'

Write-Host "---- in BuildModules, step 9"

$isInvokedByPipeline = $false
if ($InvokedByPipeline) {
    Write-Host "---- in BuildModules, step 10"
    $isInvokedByPipeline = $true
    $outputTargetPath = Join-Path $RepoArtifacts "TargetModule.txt"
    New-Item -Path $outputTargetPath -Force
    $TargetModule | Out-File -Path $outputTargetPath -Force
    Write-Host "---- in BuildModules, step 11"
}
Write-Host "---- in BuildModules, step 12"
foreach ($moduleRootName in $TargetModule) {
    Write-Host "---- in BuildModules, step 13"
    Write-Host "Preparing $moduleRootName ..." -ForegroundColor DarkGreen
    & $prepareScriptPath -ModuleRootName $moduleRootName -RepoRoot $RepoRoot -ForceRegenerate:$ForceRegenerate -InvokedByPipeline:$isInvokedByPipeline
    Write-Host "---- in BuildModules, step 14"
}
Write-Host "---- in BuildModules, step 15"

$buildCsprojFiles = Get-CsprojFromModule -BuildModuleList $TargetModule -RepoRoot $RepoRoot -Configuration $Configuration
Write-Host "---- in BuildModules, step 16"

Set-Location $RepoRoot
Write-Host "---- in BuildModules, step 17"
$buildSln = Join-Path $RepoArtifacts "Azure.PowerShell.sln"
Write-Host "---- in BuildModules, step 18"

& dotnet --version
Write-Host "---- in BuildModules, step 19"
if (Test-Path $buildSln) {
    Remove-Item $buildSln -Force
}
Write-Host "---- in BuildModules, step 20"
& dotnet new sln -n Azure.PowerShell -o $RepoArtifacts --force
Write-Host "---- in BuildModules, step 21"
foreach ($file in $buildCsprojFiles) {
    Write-Host "---- in BuildModules, step 22 ---- $file"
    & dotnet sln $buildSln add "$file"
}
Write-Host "---- in BuildModules, step 23"
Write-Output "Modules are added to build sln file"

$LogFile = Join-Path $RepoArtifacts 'Build.log'
if ('Release' -eq $Configuration) {
    $BuildAction = 'publish'
}
else {
    $BuildAction = 'build'

    $testCsprojFiles = Get-CsprojFromModule -TestModuleList $testModule -RepoRoot $RepoRoot -Configuration $Configuration
    $testSln = Join-Path $RepoArtifacts "Azure.PowerShell.Test.sln"
    if (Test-Path $testSln) {
        Remove-Item $testSln -Force
    }
    & dotnet new sln -n Azure.PowerShell.Test -o $RepoArtifacts --force
    foreach ($file in $testCsprojFiles) {
        & dotnet sln $testSln add "$file"
    }
    Write-Output "Modules are added to test sln file"
}

$buildCmdResult = "dotnet $BuildAction $Buildsln -c $Configuration -fl '/flp1:logFile=$LogFile;verbosity=quiet'"
If ($GenerateDocumentationFile -eq "false") {
    $buildCmdResult += " -p:GenerateDocumentationFile=false"
}
if ($EnableTestCoverage -eq "true") {
    $buildCmdResult += " -p:TestCoverage=TESTCOVERAGE"
}
Invoke-Expression -Command $buildCmdResult

$versionControllerCsprojPath = Join-Path $toolDirectory 'VersionController' 'VersionController.Netcore.csproj'
dotnet build $versionControllerCsprojPath -c $Configuration

$removeScriptPath = Join-Path $toolDirectory 'BuildScripts' 'RemoveUnwantedFiles.ps1'
& $removeScriptPath -RootPath (Join-Path $RepoArtifacts $Configuration) -CodeSign $CodeSign

$updateModuleScriptPath = Join-Path $toolDirectory 'UpdateModules.ps1'
pwsh $updateModuleScriptPath -BuildConfig $Configuration -Scope $Scope
