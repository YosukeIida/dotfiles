---
name: llm-kie-validate-new-model
description: >
  llm-kie に新しいモデル（特に openai_compat プロバイダ経由）を追加した後、
  make matrix-full を実行する前の pre-flight 検証手順を実行するスキル。
  「新しいモデルを追加した」「make matrix の前にテストしたい」「pre-flight チェックしたい」
  「1枚だけテストしたい」などの場合に使用する。
---

# validate-new-model

make matrix-extract を実行する前に、以下の4ステップを順番に実行して経路全体を検証する。

## 前提情報

- プロジェクトルート: `/Users/yosuke/workspace/github.com/TMLlaboratory/llm-kie`
- API サービス: `http://localhost:8000`
- MLX バックエンド: `http://100.64.0.5:8080`（mlx-proxy、Headscale MagicDNS）
- research コンテナ実行: `docker compose --profile research exec research sh -lc "make matrix-extract ..."`
- コンテナ内では entrypoint が `/workspace/research` のため `-C research` 不要

## Step 0: Docker コンテナの起動確認

```bash
docker compose ps
```

api・research コンテナが起動していない場合は起動する:

```bash
# api + research の両方を起動（--profile research が api も含む）
make up-research
```

起動確認:
```bash
curl -s http://localhost:8000/health
# → {"status":"ok",...} が返れば OK
```

## Step 1: モデル設定の確認

```bash
# model YAML の存在確認
ls research/configs/model/<model_name>.yaml

# capabilities への登録確認
grep -A3 '"<model_id>"' api/configs/capabilities/openai_compat.yaml
```

両方が存在しなければ make matrix の前に作成する。

## Step 2: バックエンドのヘルスチェック

```bash
curl -s http://100.64.0.5:8080/health
```

期待する応答:
```json
{"proxy":"ok","backend":"ok","model_id":"...","enable_thinking":false,"mode":"vlm"}
```

- `backend: ok` でなければモデルが未ロード → `/v1/models/load` でロードする
- `mode: vlm` でなければ画像入力不可 → `mode: "vlm"` で再ロード
- ロード方法は `research/docs/notes/20260405_mlx-proxy-integration.md` を参照

## Step 3: API サービス経由テスト

research→API→openai_compat→mlx-proxy の経路を確認する。
**prompt・schema・generation_config を必ず渡すこと**（省略すると構造化 JSON が返らない）。

```bash
# API サービスが起動しているか確認
curl -s http://localhost:8000/health

# 画像1枚で /v1/extract を呼ぶ
PROMPT=$(cat research/configs/prompts/<prompt_name>.md)
SCHEMA=$(cat research/configs/schemas/default_response_schema__v_20250115.json)

curl -s --max-time 60 -X POST http://localhost:8000/v1/extract \
  -F "file=@/path/to/test_image.jpg" \
  -F "category=<category>" \
  -F "output_format=structured" \
  -F "model=<model_id>" \
  -F "provider=openai_compat" \
  -F "openai_compat_base_url=http://100.64.0.5:8080/v1" \
  -F "prompt=${PROMPT}" \
  -F "response_schema_json=${SCHEMA}" \
  -F 'generation_config={"max_tokens":8192,"temperature":0.0,"enable_thinking":false}'
```

`extracted_content.data` に構造化 JSON が返れば正常。エラーの場合は API ログを確認:
```bash
docker compose logs api --tail=50
```

## Step 4: research パイプライン 1枚テスト

`input_file` パラメータで画像を1枚だけ指定して実行する。
- `input_file` はコンテナ内のパスで指定する
- 画像は `data/{dataset}/raw/{category}/images_v{date}/` に格納されている

```bash
docker compose --profile research exec research sh -lc \
  "make matrix-extract \
    dataset=<dataset> \
    model=<model_name> \
    prompt_name=<prompt_name> \
    run_tag=<run_tag>_single \
    category=<category> \
    concurrency=1 \
    'input_file=/workspace/data/<dataset>/raw/<category>/images_v20250408/<filename>.jpg'"
```

成功（per-image JSON・JSONL が生成される）すれば本番実行に進む。

## 判断基準

| ステップ | 問題があった場合 |
|---------|----------------|
| Step 1 | YAML を作成してから再実行 |
| Step 2 | mlx-proxy でモデルを再ロード |
| Step 3 | `docker compose logs api` で原因特定 |
| Step 4 | JSONL/ログでエラー内容を確認 |

全ステップが通ったら本番実行に進む。

## 本番実行: matrix-extract

**foreground で実行し、output エリアにログをストリーミングする。**
長時間になる場合はユーザーが ↓ キーでバックグラウンドに切り替えられる（プロセスは継続し shell details ペインに蓄積される）。
中断・timeout 後は同じコマンドを再実行すれば `retry-missing-only` が完了済みをスキップして続きから再開する。

```bash
docker compose --profile research exec research sh -lc \
  "make matrix-extract \
    dataset=<dataset> \
    model=<model_name> \
    prompt_name=<prompt_name> \
    run_tag=<run_tag> \
    'category=delivery,invoice,quotation,receipt,voucher' \
    concurrency=1" \
  2>&1 | tee /tmp/claude/<model_name>-extract.log
```

Bash ツールのパラメータ:
- `timeout`: 600000（10分・最大値）を指定
- `run_in_background`: 指定しない（foreground 開始）
- リダイレクト（`> file`）は**しない**（output エリアへのストリーミングが消えるため）
