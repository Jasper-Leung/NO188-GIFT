# check_all.ps1 — tools/check_all.sh 的 PowerShell 等价物
#
# 为什么要有它：Windows 上 `bash` 有两个完全不同的东西。装了 Git 的机器上
# `bash` 是 Git Bash，看得见 D: 盘，一切正常；**没装 Git 的机器上 `bash` 是
# WSL**（C:\Windows\system32\bash.exe），看不见 Windows 盘，于是
# `bash tools/check_all.sh` 会安静地跑完、什么都不输出。对一台没装 Git 的
# Windows 开发机来说，"给评审的一条命令"不是真的。
#
# 本脚本与 check_all.sh 的**判据完全一致**，照抄的是那套不看退出码的判法：
#   · 输出里有没有 [FAIL]
#   · 有没有打出断言（一条都没有 = 没跑成，不许算 PASS）
# 抛异常时 `--quit-after` 收进程的退出码是 0，所以退出码在这里没有意义。
#
# 用法：
#   pwsh -File tools/check_all.ps1                      # 全部无头回归
#   pwsh -File tools/check_all.ps1 -Window             # 要开窗口的那几条
#   pwsh -File tools/check_all.ps1 -Lookdev            # 出图看观感
#   pwsh -File tools/check_all.ps1 verify_water verify_story   # 只跑指定几条
#   $env:GODOT = 'D:\path\to\godot.exe'; pwsh -File tools/check_all.ps1
param(
	[switch]$Window,
	[switch]$Lookdev,
	[Parameter(ValueFromRemainingArguments = $true)]
	[string[]]$Only
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# ---- 找 Godot：先环境变量，再 PATH，再 CLAUDE.md 里记的那个双层目录名 ----
function Resolve-Godot {
	if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
	$cmd = Get-Command godot -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	# 历史上 Godot 被解压成了一个和 exe 同名的目录，所以要试两层
	$c = Get-Content (Join-Path $root 'CLAUDE.md') -Encoding UTF8 -Raw
	$m = [regex]::Match($c, '([A-Za-z]:\\[^\s`]*Godot[^\s`]*\.exe)')
	if ($m.Success) {
		$p = $m.Groups[1].Value
		if (Test-Path $p) { return $p }
	}
	return $null
}

$godot = Resolve-Godot
if (-not $godot) {
	Write-Host "找不到 Godot。用 `$env:GODOT = '<路径>' 指定，或照 CLAUDE.md 里的路径改这一段。" -ForegroundColor Red
	exit 2
}

$TIMEOUT_S = 240
$NEEDS_WINDOW = @('verify_bamboo_done', 'verify_bamboo_world', 'verify_camera_bike',
	'verify_checkin_all5', 'verify_demo_path', 'verify_mini_game_keys', 'verify_panel_keyboard')

function Get-ExtraArgs([string]$s) {
	if ($s -eq 'verify_layout_editor') { return @('--gift-editor') }
	return @()
}

if ($Lookdev) {
	# 这一族不能加 --headless 也不能加 --quit-after：dummy renderer 不编译着色器、
	# _draw() 一笔都不落盘，而判据全是像素的。
	Write-Host "=== 出图（要开窗口；--headless 渲不出东西）==="
	foreach ($f in Get-ChildItem (Join-Path $root 'tools') -Filter 'lookdev_*.gd' | Sort-Object Name) {
		Write-Host "--- $($f.BaseName) ---"
		& $godot --path . --script "tools/$($f.Name)" 2>&1 |
			Select-String -Pattern '^\[(OK|FAIL)\]|^\[lookdev' | ForEach-Object { $_.Line }
	}
	exit 0
}

$list = if ($Only -and $Only.Count) {
	$Only
} elseif ($Window) {
	$NEEDS_WINDOW
} else {
	$skip = $NEEDS_WINDOW
	@(Get-ChildItem (Join-Path $root 'tools') -Filter 'verify_*.gd' |
		ForEach-Object { $_.BaseName } |
		Where-Object { $skip -notcontains $_ } | Sort-Object)
}

Write-Host "=== $(if($Window){'window'}else{'headless'}) 回归 ==="
Write-Host "Godot: $godot"
$pass = 0; $fail = 0; $empty = 0; $tot_ok = 0; $tot_bad = 0
$t0 = Get-Date

# ---- 护住 res://layout.json（编辑模式 Ctrl+S 的产物，不是测试数据）----
$hadLayout = Test-Path 'layout.json'
$layoutBak = $null
if ($hadLayout) {
	$layoutBak = Join-Path $env:TEMP 'check_all_layout_backup.json'
	Copy-Item 'layout.json' $layoutBak
	Write-Host "（发现已有 layout.json，已护住，跑完原样还回）"
}

foreach ($s in $list) {
	$f = "tools/$s.gd"
	if (-not (Test-Path $f)) { Write-Host "没有这条回归：$s" -ForegroundColor Red; exit 2 }
	$argl = @()
	if (-not $Window) { $argl += '--headless' }
	$argl += @('--path', '.', '--script', $f)
	$argl += (Get-ExtraArgs $s)

	$sw = [Diagnostics.Stopwatch]::StartNew()
	$out = & $godot @argl 2>&1 | Out-String
	$sw.Stop()

	$ok = ([regex]::Matches($out, '(?m)^\[OK\]')).Count
	$bad = ([regex]::Matches($out, '(?m)^\[FAIL\]')).Count
	$tot_ok += $ok; $tot_bad += $bad

	if ($bad -gt 0) { $v = 'FAIL'; $fail++ }
	elseif ($ok -eq 0) { $v = 'NO-ASSERT'; $empty++ }   # 没跑成，不许算通过
	else { $v = 'PASS'; $pass++ }

	Write-Host ("  {0,-28} {1,-11} {2,4}s  {3,4} ok / {4} fail" -f $s, $v, [int]$sw.Elapsed.TotalSeconds, $ok, $bad)
	if ($v -ne 'PASS') {
		($out -split "`n" | Where-Object { $_ -match '^\[FAIL\]' } | Select-Object -First 12) |
			ForEach-Object { Write-Host "      $_" }
	}
}

if ($hadLayout) { Copy-Item $layoutBak 'layout.json' -Force }
elseif (Test-Path 'layout.json') {
	Remove-Item 'layout.json'
	Write-Host "[check_all] 某条回归往 res://layout.json 里留了测试数据，已清掉（它不是产品输入）"
}

$secs = [int]((Get-Date) - $t0).TotalSeconds
Write-Host ""
Write-Host "=== 自检摘要 ==="
Write-Host ("  跑过 {0} 条：PASS {1} / FAIL {2} / 没跑成 {3}" -f ($pass + $fail + $empty), $pass, $fail, $empty)
Write-Host ("  断言 {0} 条，其中 {1} 条红" -f $tot_ok, $tot_bad)
if (-not $Window) {
	Write-Host ("  没跑（要开窗口，--headless 跑出来的 PASS 是假的）：{0} 条" -f $NEEDS_WINDOW.Count)
	Write-Host "    → pwsh -File tools/check_all.ps1 -Window"
}
Write-Host ("  用时 {0}s" -f $secs)
Write-Host ""
Write-Host "  完整陷阱清单与「改什么先跑哪条」：CLAUDE.md"

if ($fail -gt 0 -or $empty -gt 0) { Write-Host "`n[check_all] FAIL" -ForegroundColor Red; exit 1 }
Write-Host "`n[check_all] PASS" -ForegroundColor Green
