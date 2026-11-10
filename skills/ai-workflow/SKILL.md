---
name: ai-workflow
description: GitHub Issue の調査・詳細化から独立レビュー付きの Git 作業、PR、完了確認までを進める共通ワークフロー。
---

# GitHub Issue と AI 作業の運用

適用先の AGENTS.md と利用者の指示を先に読み、対象・権限・基準ブランチ・認証・検証手順を確定する。設定例は権限を付与しない。必要な設定や操作結果を確認できなければ対象操作を保留し未確認を記録する。

- 計画、Issue、引き継ぎ、GitHub と整理の共通手順は、同梱の [references/workflow.md](references/workflow.md) を読む。親が進行を所有し、作者と別の担当が対象版を確認する。ラベル・コメントは排他ロックではない。応答不明時は照合せず再作成しない。
- 対象リポジトリに配布パッケージの docs/agent-workflow.md、docs/issue-workflow.md、docs/task-cleanup-check.md と docs/adapters/ が導入済みの場合は、対象作業に応じてその詳細手順も読む。単体導入した Skill の相対パスと混同しない。Windows 定期実行には別の連携素材と設定が必要であり、Skill の配置だけでは自動実行は始まらない。

既存の orchestrate-task-workflow は Git の計画・ブランチ・レビューと統合を担う。本 Skill は Issue の状態管理、ファイル引き継ぎ、提案登録と整理を補う。両方を使う場合はユーザーと適用先の指示を優先し、承認や権限を拡張しない。配布フォルダー自体が Git でない場合、そこへ Git 操作を適用しない。
