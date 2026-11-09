# カン、カン

2ちゃんねるの怪談「カン、カン」（後日談の手前まで）を、縦の画面で読むホラーノベルにした物。flix_game_engine の sound-novel-starter から作った。

タップかクリックで読み進める。音を出して、暗い部屋で。

右上の … から設定・タイトルへ・隠す。右端の列はしおり（セーブ・ロード）・ログ・オート（長押しでスキップ）で、長押しで名前が出る。上下に払うと 1 行送り、左へ払うと 1 行戻る。

## 直す所

| 直したい物 | 書く所 |
|---|---|
| 文章・演出の順番 | `assets/talk/kankan.yarn`（頭のコメントにコマンドの一覧。直したら `bin/fge yarn build assets/talk`） |
| 画像と明暗 | `assets/bg/`・`assets/novel.backdrops.json` |
| 字の大きさ・置き場 | `<<text 位置 大きさ 揃え>>`・`src/Stage.flix`・`src/Layout.flix` の `pageAt` |
| 音 | `assets/sfx/`・`project.json` の `sounds` |
| 字の速さ・揺れ | `assets/novel.kind.json` |

## 動かす

| コマンド | 何をするか |
|---|---|
| `make run` | ウィンドウで遊ぶ |
| `make check` | 型検査 |
| `make test` | Doc の検査 |
| `make render SHOT=portrait-woman` | 場面を `debug/` へ描き出す |

ブラウザ版は engine 側で `make sync-engine-full-web` を流してから、`bin/fge export-web . --id kankan` の後に `python3 web/fit-page.py`（スマホの見えている範囲に収める）。出力の `build/web` を `gh-pages` ブランチへ置く。

素材の出典は [CREDITS.md](CREDITS.md)。
