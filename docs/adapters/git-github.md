# Git / GitHub 連携

適用先のリポジトリ、作業基準、GitHub 既定ブランチ、PR の base、認証方法と権限を実際に確認する。各設定値は別物であり、`main` を常に既定としない。ユーザーが基準を指定している場合は適用指示に従う。現行例は `examples/movie-create-framework.toml` を参照。

## 着手・作業・提出

`git status --short`、`git worktree list --porcelain`、GitHub の最新の既定と基準 branch の SHA、open Issue/PR と共有 run を調べる。古い `origin/*` だけでリモート最新と判断せず、未統合変更と他担当の所有範囲を保護する。保存済みの GitHub 資格情報を利用する環境では適用先の手順を確認して接続し、失敗だけで保存済み資格情報なしと断定しない。秘密を表示せず、環境変数を一時変更する場合は `try/finally` で元に戻す。既存認証設定は勝手に変更しない。

計画の独立承認後、基準 SHA から Issue ごとの branch と worktree を作り、絶対パス・担当・SHA を記録する。衝突時に既存を流用しない。レビューとテストの対象版が変われば承認を更新し、承認を偽装しない。許可なしに push、PR、マージを行わない。

## 親子 Issue 用 Actions

`docs/ai-workflow-adapters/github/close-integrated-sub-issue.yml` は利用側の `.github/workflows/` に配置されるまでは動作しない。利用前に対象 repo で Actions の権限、親子 Issue 機能と副作用を確認する。現行実装は `integration/issue-<親番号>` へのマージ済み PR、単独行の `Sub-issue: #<番号>` が1つ、同一リポジトリでの親子関係を検証して sub Issue を close する。既に closed なら変更しない。branch 命名や本文形式の動的な設定には対応しない。未マージ・親不一致等は close しない。Action 結果と Issue を読戻し、未確認を成功扱いしない。

自動ドキュメント更新の workflow はこのパッケージの配布対象外であり、上記の Issue close 連携とは別の機能である。

## 整理

[タスク完了チェック](../task-cleanup-check.md) の条件と権限を確認する。ローカル追跡 ref だけでリモートの保護・統合状態を判断せず、未確認は保留する。保護 branch、利用中 worktree、open PR のある branch を削除しない。リモート削除は確認した先端 SHA が変更されていないことを lease で条件付ける。
