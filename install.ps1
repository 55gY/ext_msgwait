# tdl-msgwait 快速安装脚本
# Windows PowerShell

Write-Host "🚀 开始安装 tdl-msgwait 扩展..." -ForegroundColor Green

# 1. 创建扩展目录
$extensionsDir = "$env:USERPROFILE\.tdl\extensions"
Write-Host "📁 创建扩展目录: $extensionsDir" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $extensionsDir | Out-Null

# 2. 复制可执行文件
Write-Host "📦 复制扩展文件..." -ForegroundColor Cyan
Copy-Item "tdl-msgwait.exe" "$extensionsDir\" -Force

# 3. 创建数据目录
$dataDir = "$env:USERPROFILE\.tdl\extensions_data\msgwait"
Write-Host "📁 创建数据目录: $dataDir" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

# 4. 复制配置文件
Write-Host "⚙️  复制配置文件..." -ForegroundColor Cyan
Copy-Item "config.yaml" "$dataDir\" -Force

# 5. 创建日志目录
$logDir = "$dataDir\log"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Write-Host ""
Write-Host "✅ 安装完成！" -ForegroundColor Green
Write-Host ""
Write-Host "📋 安装信息:" -ForegroundColor Yellow
Write-Host "   扩展文件: $extensionsDir\tdl-msgwait.exe"
Write-Host "   配置文件: $dataDir\config.yaml"
Write-Host "   日志目录: $logDir"
Write-Host ""
Write-Host "🔧 使用方法:" -ForegroundColor Yellow
Write-Host "   1. 确保已用 tdl 登录: tdl login"
Write-Host "   2. 编辑配置文件（可选）"
Write-Host "   3. 运行扩展: tdl msgwait"
Write-Host ""
Write-Host "💡 提示: 使用 'tdl --debug msgwait' 启用调试模式" -ForegroundColor Cyan
