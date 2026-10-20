[CmdletBinding()]
param(
    [ValidateSet("win-x64")]
    [string]$Runtime = "win-x64",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repoRoot "src\Lynext.App\Lynext.App.csproj"
$publishDir = Join-Path $repoRoot "artifacts\publish"
$artifactDir = Join-Path $repoRoot "artifacts"
$issFile = Join-Path $repoRoot "installer\Lynext.iss"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "O .NET SDK não foi encontrado. Instale o .NET 8 SDK para compilar o Lynext."
}

Write-Host "Publicando Lynext para $Runtime..." -ForegroundColor Cyan
dotnet publish $project -c $Configuration -r $Runtime --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o $publishDir

if ($LASTEXITCODE -ne 0) {
    throw "A publicação do Lynext falhou (código $LASTEXITCODE)."
}

$programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
$programFiles = [Environment]::GetFolderPath('ProgramFiles')
$compilerCandidates = @(
    (Join-Path $programFilesX86 "Inno Setup 6\ISCC.exe"),
    (Join-Path $programFiles "Inno Setup 6\ISCC.exe")
)
$compiler = $compilerCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $compiler) {
    Write-Host "Aplicativo publicado em: $publishDir" -ForegroundColor Green
    Write-Warning "Inno Setup 6 não foi encontrado. O executável está publicado, mas o instalador ainda não foi empacotado."
    Write-Host "Instale Inno Setup 6 e execute novamente este script para gerar o setup."
    exit 0
}

New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
Write-Host "Gerando instalador..." -ForegroundColor Cyan
& $compiler $issFile
if ($LASTEXITCODE -ne 0) {
    throw "A criação do instalador falhou (código $LASTEXITCODE)."
}

Write-Host "Concluído. Verifique a pasta artifacts." -ForegroundColor Green
