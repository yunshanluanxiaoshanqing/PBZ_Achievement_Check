param(
    [string]$Txt,
    [string]$Out
)

# 影之刃零 · 成就检测报告 -> 桌面 PNG
# 由 PBZAchDiag 生成的文本报告渲染而来，是只读流程的最后一环。

Add-Type -AssemblyName System.Drawing

if (-not $Txt) {
    $Txt = Join-Path $PSScriptRoot '..\..\..\..\..\PBZ_Achievement_Check.txt'
}
if (-not (Test-Path -LiteralPath $Txt)) {
    Write-Host "找不到检测结果：$Txt" -ForegroundColor Red
    exit 1
}

$lines = Get-Content -LiteralPath $Txt -Encoding UTF8

$time = ''
$recorded = ''
$total = ''
$missingCount = ''
$missing = New-Object System.Collections.ArrayList

$inMissing = $false
foreach ($line in $lines) {
    $t = $line.Trim()
    if ($t -match '^生成时间[:：]\s*(.+)$') { $time = $Matches[1] }
    elseif ($t -match '^存档记录[:：]\s*(\d+)\s*/\s*(\d+)') { $recorded = $Matches[1]; $total = $Matches[2] }
    elseif ($t -match '^缺失数量[:：]\s*(\d+)') { $missingCount = $Matches[1] }
    elseif ($t -match '^【缺失成就】') { $inMissing = $true }
    elseif ($t.StartsWith('【')) { $inMissing = $false }
    elseif ($inMissing -and $t -match '^(ACH_\d{3})\s+(.+)$') {
        [void]$missing.Add(@($Matches[1], $Matches[2]))
    }
}

if (-not $missingCount) { $missingCount = [string]$missing.Count }

if (-not $Out) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $Out = Join-Path $desktop '影之刃零-成就检测.png'
}

# 画布高度随缺失条目数变化，避免大片空白
$rowsShown = [Math]::Min($missing.Count, 8)
if ([int]$missingCount -eq 0 -and $missing.Count -eq 0) { $H = 500 }
else { $H = 392 + $rowsShown * 44 + 120 }
if ($H -lt 520) { $H = 520 }

$W = 1200
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'ClearTypeGridFit'
$g.Clear([System.Drawing.Color]::FromArgb(255, 250, 251, 252))

$navy = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 26, 34, 44))
$ink = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 44, 54, 66))
$soft = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 108, 120, 132))
$red = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 192, 57, 43))
$green = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 39, 150, 96))
$linePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 224, 228, 234), 2)

$fTitle = New-Object System.Drawing.Font 'Microsoft YaHei', 27, ([System.Drawing.FontStyle]::Bold)
$fSub = New-Object System.Drawing.Font 'Microsoft YaHei', 13
$fBig = New-Object System.Drawing.Font 'Microsoft YaHei', 24, ([System.Drawing.FontStyle]::Bold)
$fBody = New-Object System.Drawing.Font 'Microsoft YaHei', 14
$fRow = New-Object System.Drawing.Font 'Microsoft YaHei', 15
$fSmall = New-Object System.Drawing.Font 'Microsoft YaHei', 11
$fMark = New-Object System.Drawing.Font 'Microsoft YaHei', 40, ([System.Drawing.FontStyle]::Bold)

$g.FillRectangle($navy, 0, 0, $W, 120)
$g.DrawString('影之刃零 · 成就检测报告', $fTitle, [System.Drawing.Brushes]::White, 56, 28)
$subBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 186, 194, 204))
$g.DrawString("Phantom Blade Zero    $time", $fSub, $subBrush, 58, 84)

$g.DrawString('存档记录', $fBody, $soft, 56, 156)
$g.DrawString("$recorded / $total", $fBig, $ink, 56, 182)
$g.DrawString('缺失', $fBody, $soft, 420, 156)
$numBrush = if ([int]$missingCount -gt 0) { $red } else { $green }
$g.DrawString($missingCount, $fBig, $numBrush, 420, 182)

$g.DrawLine($linePen, 56, 268, $W - 56, 268)

if ([int]$missingCount -eq 0 -and $missing.Count -eq 0) {
    $g.DrawString('√', $fMark, $green, 54, 300)
    $g.DrawString('全部成就均已记录，存档状态完整。', $fBig, $ink, 116, 312)
    $g.DrawString('如果 Steam 侧仍少一个成就，说明差异不在存档记录，请查看文本报告。', $fSub, $soft, 118, 356)
} else {
    $g.DrawString('缺失成就', $fBig, $red, 56, 300)
    $y = 350
    $n = 0
    foreach ($m in $missing) {
        if ($n -ge 8) { break }
        $g.FillEllipse($red, 58, $y + 10, 10, 10)
        $g.DrawString(("{0}   {1}" -f $m[0], $m[1]), $fRow, $ink, 84, $y)
        $y += 44
        $n++
    }
    if ($missing.Count -gt 8) {
        $g.DrawString(("…… 另有 {0} 项，见文本报告" -f ($missing.Count - 8)), $fSmall, $soft, 84, $y)
    }
}

$g.DrawLine($linePen, 56, $H - 78, $W - 56, $H - 78)
$g.DrawString('PBZAchDiag · 只读检测：不修改存档、不调用解锁接口', $fSmall, $soft, 56, $H - 62)
$g.DrawString('游戏内按 F7 重新检测', $fSmall, $soft, $W - 236, $H - 62)

$dir = Split-Path -Parent $Out
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()

Write-Host "已生成：$Out" -ForegroundColor Green