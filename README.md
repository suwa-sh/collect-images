# collect-images

Google画像検索の結果を収集するコマンドラインツールです。



## Getting Started

* ダウンロード

  [GitHubの最新リリース](https://github.com/suwa-sh/collect-images/releases/latest) からダウンロードできます。

* デプロイ

  ``` bash
  # 配置ディレクトリで展開
  DIR_PARENT={配置ディレクトリを指定}
  VERSION={対象のバージョンを指定}
  cd ${DIR_PARENT}
  tar xvfz ./collect-images_*.tar.gz
  rm -f ./collect-images_*.tar.gz

  # 最新版にシンボリックリンクを作成
  ln -s ${DIR_PARENT}/collect-images_${VERSION} ${DIR_PARENT}/collect_images
  ```

* サンプル設定の確認

  ``` bash
  cd ${DIR_PARENT}/collect_images
  # キーワードリスト
  #   検索したいキーワード群を改行区切りで列挙します。
  #   1行に、半角スペース区切りでキーワードを並べると、AND検索されます。
  cat config/keywords

  # 起動設定
  cat config/project.properties
  ```

* サンプル設定で実行

  ``` bash
  # 実行
  cd ${DIR_PARENT}/collect_images/bin
  ./collect_images.sh

  # リターンコード
  #  0: 正常終了
  #  3: ダウンロードエラーが含まれる場合
  #  6: エラー終了
  echo $?

  # 出力
  #   ・収集結果：data/COLLECT_RESULT_${キーワードリスト行番号}
  #       キーワードリスト行番号毎に、ダウンロードしたファイルパスが記載されます。
  #   ・収集履歴：data/COLLECT_RESULT_HISTORY_${キーワードリスト行番号}
  #       キーワードリスト行番号毎に、ダウンロード処理が 成功|スキップ|エラー終了 した結果が記載されます。
  ls -l ../data
  #   ・収集結果ファイル：data/query/${キーワードリスト行番号}/${収集結果ファイル行番号}
  #       キーワードリスト行番号毎に、ダウンロードしたファイルへのエイリアスが作成されます。
  #       複数のキーワードで同じファイルがヒットした場合、ファイルは1つだけダウンロードされ
  #       各キーワードのエイリアスから、ダウンロードしたファイルにアクセスできます。
  ls -l ../data/query
  #   ・ダウンロードファイル：data/images/${URI}
  #       ダウンロードしたファイルは、imagesディレクトリ配下で一意に管理されます。
  ls -l ../data/images
  ```



## Contact

- [要望を伝える](https://github.com/suwa-sh/collect-images/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement)
- [バグを報告する](https://github.com/suwa-sh/collect-images/issues?q=is%3Aopen+is%3Aissue+label%3Abug)
- [質問する](https://github.com/suwa-sh/collect-images/issues?q=is%3Aopen+is%3Aissue+label%3Aquestion)
- [その他](mailto:suwash01@gmail.com)



## ライセンス
[Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0)
