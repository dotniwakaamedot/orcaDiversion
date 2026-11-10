# AI ワークフロー共通パッケージ

Git/GitHub を使った Issue の調査、ファイルによるエージェント間の引き継ぎ、独立レビュー、PR と完了後整理のための配布物です。配置しただけでは Skill の登録、GitHub Actions の有効化、定期実行や外部操作は行われません。配布先自体は Diversion で管理される場合があり、その場合は対象先の Git リポジトリだと仮定しません。

## 含まれるもの

- [Agent ワークフロー](docs/agent-workflow.md)：所有権、版・SHA256、質問・レビュー・進行管理とテンプレート。
- [Issue 運用](docs/issue-workflow.md)：詳細化、状態、二重着手、再開、PR、提案登録と失敗時の処理。
- [タスク完了チェック](docs/task-cleanup-check.md)：読み取りの候補調査、削除前の再確認、未確認の保留と記録。
- [Git/GitHub 連携](docs/adapters/git-github.md) と [Windows 連携](docs/adapters/windows.md)：各環境に依存する前提と注意事項。
- `skills/ai-workflow/SKILL.md`、`.codex/agents/`：配布用 Skill と Codex Agent 定義。これらは手順の入口で、利用環境による発見・起動は未確認。
- `adapters/github/`、`adapters/windows/`：明示的に導入する連携素材。GitHub の Action はこの位置では起動しない。
- 自動ドキュメント更新ワークフローは、このパッケージの配布対象外です。

## 利用開始

1. 対象の Git/GitHub リポジトリで既存の指示、対象ブランチ、共有 run、テスト手段、認証・操作権限を確認し、競合するファイルを上書きしない。
2. 必要な文書と Agent 定義を導入先の規約に沿って配置し、既存 `AGENTS.md` と整合させる。Skill の導入方法は下記を参照する。Skill の同梱だけでインストール済みと判断しない。
3. `examples/generic.toml` または `examples/movie-create-framework.toml` は人・Agent が読む記入例。リポジトリ、ブランチ、保存先、認証方式、テストと権限を利用先で確認する。例は runner の機械設定ではなく、許可を付与しない。
4. Windows runner を使う場合だけ `examples/windows-issue-review.json` を別名で複製し、その環境の絶対パスと Git branch に置き換える。JSON と TOML は同期されないため利用者が整合を確認する。秘密は設定に書かない。詳しくは [Windows 連携](docs/adapters/windows.md) を参照。
5. [Issue 運用](docs/issue-workflow.md) の全手順と外部操作の権限を確認してから実行する。実環境の権限、Actions、スケジューラー、非表示動作は対象環境で個別に検証する。

### Skill の配置と確認

`skills/ai-workflow/` フォルダーを丸ごと利用環境が認識する Skill 配置先にコピーする。コピー先に同名の Skill がある場合は内容・所有者を確認し、無断で上書きしない。Windows PowerShell で、配布物のルートをカレントディレクトリとし、利用環境の配置先がユーザーの `.codex/skills` である場合の例:

```powershell
$skillDestination = Join-Path $env:USERPROFILE '.codex\skills\ai-workflow'
if (Test-Path -LiteralPath $skillDestination) { throw '同名 Skill が存在します。内容と所有者を確認してください。' }
Copy-Item -LiteralPath '.\skills\ai-workflow' -Destination $skillDestination -Recurse
Test-Path -LiteralPath (Join-Path $skillDestination 'SKILL.md')
Test-Path -LiteralPath (Join-Path $skillDestination 'references\workflow.md')
```

コピー先の親ディレクトリが存在することと書き込み権限を事前に確認する。両方の `Test-Path` が `True` であることを確認し、環境によっては新しいセッションで Skill が認識されることを確認する。Skill は単体で `references/workflow.md` を参照できるが、Agent 定義・Windows runner は含まない。必要ならパッケージの `docs/` と `.codex/agents/`、`adapters/` を別途導入し、既存指示との整合性を確認する。

## 更新・戻し方

導入前の対象ファイル・有無と SHA256、導入後の SHA256、変更者と設定を記録する。更新・復旧前に現在のファイルが導入後の版と一致するか再確認し、他者の変更、同期・未保存物、所有権が不明なら上書きせず保留する。復旧が他のシステムの状態を戻すことを意味しない。登録済みタスクや GitHub の変更がある場合は別途内容と権限を確認する。

## 制約

状態ラベルとコメントは排他ロックではありません。個別環境の認証・PR マージ・Issue 更新・削除の許可はユーザー指示と適用される上位指示から判断します。モックや文書確認の結果から、実 GitHub、Windows の表示、スケジューラー、同期の動作を保証しません。
