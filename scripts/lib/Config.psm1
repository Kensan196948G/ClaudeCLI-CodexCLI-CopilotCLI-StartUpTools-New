# ============================================================
# Config.psm1 - 設定管理モジュール（オーケストレーター）
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.0.0
#
# 実装は以下の .ps1 ファイルに分割されています:
#   ConfigSchema.ps1  — スキーマ定義・検証
#   ConfigLoader.ps1  — 設定読み込み・バックアップ
#   RecentProjects.ps1 — 最近使用プロジェクト履歴
# ============================================================
Set-StrictMode -Version Latest

# Dot-source submodules — functions land in this module's scope
. (Join-Path $PSScriptRoot 'ConfigSchema.ps1')
. (Join-Path $PSScriptRoot 'ConfigLoader.ps1')
. (Join-Path $PSScriptRoot 'RecentProjects.ps1')

# Export all public functions (schema + loader + recent-projects)
Export-ModuleMember -Function '*'
