param(
    $SCRIPT_DIR = $PSScriptRoot,
    $ARTIFACTS = "$SCRIPT_DIR\..\artifacts",

    $DEPLOYMENT_SOURCE = $env:DEPLOYMENT_SOURCE,
    $DEPLOYMENT_TARGET = 'd:\home\data\SitePackages',

    $NEXT_MANIFEST_PATH = "$($DEPLOYMENT_TARGET)_manifest.txt",
    $PREVIOUS_MANIFEST_PATH = $NEXT_MANIFEST_PATH
)
$ErrorActionPreference = 'stop'
$global:ProgressPreference = 'silentlycontinue'
# ----------------------
# KUDU Deployment Script
# Version: 1.0.17
# ----------------------

# Helpers
# -------

function exitWithMessageOnError($1) {
  if ($? -eq $false) {
    echo "An error has occurred during web site deployment."
    echo $1
    exit 1
  }
}

# Prerequisites
# -------------

# Verify node.js installed
where.exe node 2> $null > $null
exitWithMessageOnError "Missing node.js executable, please install node.js, if already installed make sure it can be reached from current environment."

# Setup
# -----
if ($DEPLOYMENT_SOURCE -eq $null) {
  $DEPLOYMENT_SOURCE = $SCRIPT_DIR
}

if ($DEPLOYMENT_TARGET -eq $null) {
  $DEPLOYMENT_TARGET = "$ARTIFACTS\wwwroot"
}

if ($NEXT_MANIFEST_PATH -eq $null) {
  $NEXT_MANIFEST_PATH = "$ARTIFACTS\manifest"

  if ($PREVIOUS_MANIFEST_PATH -eq $null) {
    $PREVIOUS_MANIFEST_PATH = $NEXT_MANIFEST_PATH
  }
}

$DEPLOYMENT_TEMP = $env:DEPLOYMENT_TEMP
$MSBUILD_PATH = $env:MSBUILD_PATH

if ($DEPLOYMENT_TEMP -eq $null) {
  $DEPLOYMENT_TEMP = "$env:temp\___deployTemp$env:random"
  $CLEAN_LOCAL_DEPLOYMENT_TEMP = $true
}

if ($CLEAN_LOCAL_DEPLOYMENT_TEMP -eq $true) {
  if (Test-Path $DEPLOYMENT_TEMP) {
    rd -Path $DEPLOYMENT_TEMP -Recurse -Force
  }
  mkdir "$DEPLOYMENT_TEMP"
}

if ($MSBUILD_PATH -eq $null) {
  $MSBUILD_PATH = "${env:ProgramFiles(x86)}\MSBuild\14.0\Bin\MSBuild.exe"
}
##################################################################################################################################
# Deployment
# ----------

echo "Handling ASP.NET Core Web Application deployment."

# 1. Restore nuget packages
dotnet restore "$DEPLOYMENT_SOURCE\vandelay.sln"
exitWithMessageOnError "Restore failed"

# 2. Run unit tests
dotnet test './vandelay.xunittests/vandelay.xunittests.csproj'
exitWithMessageOnError "Test(s) failed"

# 3. Build and publish
dotnet publish "$DEPLOYMENT_SOURCE\vandelay.web/vandelay.web.csproj" --output "$DEPLOYMENT_TEMP" --configuration Release
exitWithMessageOnError "dotnet publish failed"

function isCurrentScriptDirectoryGitRepository {
  $here = $PSScriptRoot
  if ((Test-Path "$here\.git") -eq $TRUE) {
      return $TRUE
  }
  
  # Test within parent dirs
  $checkIn = (Get-Item $here).parent
  while ($NULL -ne $checkIn) {
      $pathToTest = $checkIn.fullname + '/.git'
      if ((Test-Path $pathToTest) -eq $TRUE) {
          return $TRUE
      } else {
          $checkIn = $checkIn.parent
      }
  }
  $FALSE
}

function find-githash {
  $isInGit = isCurrentScriptDirectoryGitRepository
  if (-not($isInGit)) {
    get-date -Format 'yyyy-MM-dd_hh-mm-ss'
  } else {
    git rev-parse HEAD  
  }
}
function New-ZipDirIfNotExists($zipdir) {
  if (-not(test-path $zipdir -PathType Container)) {
    mkdir $zipdir | out-null  
  }
}
# 3. Zip
New-ZipDirIfNotExists $DEPLOYMENT_TARGET
$zipArchive = "$(find-githash).zip"
Write-Output "Compressing content from $DEPLOYMENT_TEMP\* to $DEPLOYMENT_TARGET\$zipArchive"
Compress-Archive -Path "$DEPLOYMENT_TEMP\*" -DestinationPath $DEPLOYMENT_TARGET\$zipArchive -force
$zipArchive | Out-File "$DEPLOYMENT_TARGET\packagename.txt" -Encoding ASCII -NoNewline
exitWithMessageOnError "Application publish failed"

##################################################################################################################################
echo "Finished successfully."
