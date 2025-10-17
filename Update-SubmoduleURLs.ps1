param(
  [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
  [string[]]$Repos
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Check prerequisites
& git --version | Out-Null
if ($LASTEXITCODE -ne 0) { 
  throw "git not found. Please install git first." 
}

# URL mappings
$oldURLs = @(
  "https://gitee.com/vChewing/libvchewing-data.git",
  "https://gitee.com/vChewing/libvchewing-data",
  "http://gitee.com/vChewing/libvchewing-data.git",
  "http://gitee.com/vChewing/libvchewing-data",
  "git@gitee.com:vChewing/libvchewing-data.git",
  "git://gitee.com/vChewing/libvchewing-data"
)
$newURL = "https://gitlink.org.cn/vChewing/vChewing-VanguardLexicon.git"

foreach ($repoPath in $Repos) {
  Write-Host "`n========================================" -ForegroundColor Cyan
  Write-Host "Processing repository: $repoPath" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  
  # Resolve to absolute path
  $fullPath = Resolve-Path -Path $repoPath -ErrorAction Stop
  
  # Verify it's a git repository
  if (-not (Test-Path (Join-Path $fullPath ".git"))) { 
    throw "Not a git repository: $fullPath" 
  }
  
  Push-Location $fullPath
  try {
    Write-Host "[INFO] Running git filter-branch to rewrite history..." -ForegroundColor Yellow
    
    # Build sed commands for each URL replacement
    $sedCommands = $oldURLs | ForEach-Object { 
      $escaped = $_ -replace '/', '\/'
      $escapedNew = $newURL -replace '/', '\/'
      "s|$escaped|$escapedNew|g"
    }
    $sedScript = $sedCommands -join '; '
    
    # Run filter-branch to rewrite .gitmodules in all commits
    $env:FILTER_BRANCH_SQUELCH_WARNING = "1"
    git filter-branch --force --tree-filter @"
if [ -f .gitmodules ]; then
  sed -i '$sedScript' .gitmodules || sed -i '' '$sedScript' .gitmodules 2>/dev/null
fi
"@ --tag-name-filter cat -- --all 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
      throw "git filter-branch failed for $fullPath"
    }
    
    Write-Host "[INFO] Updating working tree..." -ForegroundColor Yellow
    
    # Update working tree to reflect changes
    git checkout HEAD 2>&1 | Out-Null
    
    # Sync submodule configuration
    Write-Host "[INFO] Syncing submodules..." -ForegroundColor Yellow
    git submodule sync --recursive 2>&1 | Out-Null
    
    # Verify the changes
    Write-Host "[INFO] Verifying changes..." -ForegroundColor Yellow
    $grepResult = git --no-pager grep -n "gitee.com/vChewing/libvchewing-data" -- .gitmodules 2>&1
    
    if ($LASTEXITCODE -eq 0) {
      Write-Host "[WARN] Leftover gitee URL found in $fullPath/.gitmodules:" -ForegroundColor Red
      Write-Host $grepResult -ForegroundColor Red
    } else {
      Write-Host "[OK] Successfully replaced all URLs in $fullPath" -ForegroundColor Green
    }
    
    # Run garbage collection
    Write-Host "[INFO] Running git gc to clean up repository..." -ForegroundColor Yellow
    git reflog expire --expire=now --all 2>&1 | Out-Null
    git gc --prune=now --aggressive 2>&1 | Out-Null
    
    Write-Host "[OK] Repository $fullPath processed successfully!" -ForegroundColor Green
    Write-Host "[INFO] To push the rewritten history, run:" -ForegroundColor Yellow
    Write-Host "       git push --force-with-lease --all" -ForegroundColor Cyan
    Write-Host "       git push --force-with-lease --tags" -ForegroundColor Cyan
    
  } catch {
    Write-Host "[ERROR] Failed to process $fullPath : $_" -ForegroundColor Red
    throw
  } finally {
    Pop-Location
  }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "All repositories processed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
