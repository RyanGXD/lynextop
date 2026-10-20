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

# Generate a simple native Windows icon until the final artwork is supplied.
$brandingDir = Join-Path $repoRoot "src\Lynext.App\Branding"
$iconPath = Join-Path $brandingDir "Lynext.ico"
New-Item -ItemType Directory -Path $brandingDir -Force | Out-Null
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object System.Drawing.Bitmap 256, 256
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::FromArgb(16, 19, 35))
$rect = New-Object System.Drawing.Rectangle 8, 8, 240, 240
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc(8, 8, 48, 48, 180, 90)
$path.AddArc(200, 8, 48, 48, 270, 90)
$path.AddArc(200, 200, 48, 48, 0, 90)
$path.AddArc(8, 200, 48, 48, 90, 90)
$path.CloseFigure()
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(20, 130, 255), [System.Drawing.Color]::FromArgb(168, 45, 255), 45)
$graphics.FillPath($brush, $path)
$font = New-Object System.Drawing.Font("Segoe UI", 132, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$format = New-Object System.Drawing.StringFormat
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center
$graphics.DrawString("L", $font, [System.Drawing.Brushes]::White, $rect, $format)
$bitmap.Save($iconPath, [System.Drawing.Imaging.ImageFormat]::Icon)
$graphics.Dispose()
$bitmap.Dispose()
$brush.Dispose()
$path.Dispose()
$font.Dispose()
$format.Dispose()

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
