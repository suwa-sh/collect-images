#!/bin/bash
#===================================================================================================
#
# 画像収集ユーティリティ
#
# 前提
#   setenv.sh を事前に読み込んでいること
#
#===================================================================================================
#---------------------------------------------------------------------------------------------------
# 依存ユーティリティの読み込み
#---------------------------------------------------------------------------------------------------
. ${DIR_BIN_LIB}/logging_utils.sh



#---------------------------------------------------------------------------------------------------
# キーワードにマッチする画像を収集します。
#
# 引数
#   1〜: AND条件で繋ぐキーワードリスト
#---------------------------------------------------------------------------------------------------
function collect_images.collect() {
  log.debug_teelog "START: ${FUNCNAME[0]} $@"
  log.save_indent
  log.add_indent

  local keywords="$@"
  local func_return_code=${EXITCODE_SUCCESS}

  # 一時ディレクトリ
  dir_tmp="${DIR_DATA}/tmp_$$"
  if [ -d ${dir_tmp} ]; then
    rm -fr ${dir_tmp}
  fi
  log.debug_teelog "mkdir ${dir_tmp}"
  mkdir ${dir_tmp}

  log.debug_teelog "画像検索"
  log.add_indent

  query=$(collect_images.local.convert2query "${keywords}")
  path_url_list="${dir_tmp}/URL"
  collect_images.local.search_image "${query}" "${MAX_PAGING_COUNT}" "${path_url_list}"
  local _ret_code=$?
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    func_return_code=${EXITCODE_ERROR}
  fi

  log.remove_indent

  log.debug_teelog "ダウンロード"
  log.add_indent

  dir_image_root="${DIR_DATA}/images"
  query_id=$(collect_images.local.get_query_id "${keywords}")
  path_result="${DIR_DATA}/COLLECT_RESULT_${query_id}"
  path_history="${DIR_DATA}/COLLECT_RESULT_HISTORY_${query_id}"
  collect_images.local.download_files "${path_url_list}" "${dir_image_root}" "${path_result}" "${path_history}"
  _ret_code=$?
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    log.warn_teelog "ダウンロードエラーが発生したファイルが存在します。"
    func_return_code=${EXITCODE_WARN}
  fi

  log.remove_indent

  log.debug_teelog "シンボリックリンク作成"
  log.add_indent

  dir_links="${DIR_DATA}/query/${query_id}"
  collect_images.local.create_linenum_link "${path_result}" "${DIR_DATA}" "${dir_links}"
  _ret_code=$?
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    func_return_code=${EXITCODE_ERROR}
  fi

  log.remove_indent

  # 一時ディレクトリ削除
  log.debug_teelog "rm -fr ${dir_tmp}"
  rm -fr ${dir_tmp}

  log.restore_indent
  log.debug_teelog "END  : ${FUNCNAME[0]} $@"
  return ${func_return_code}
}



#---------------------------------------------------------------------------------------------------
# 空白区切りのキーワードリストを、AND条件での検索用クエリに変換します。
#
# 引数
#   1〜: AND条件で繋ぐキーワードリスト
#---------------------------------------------------------------------------------------------------
function collect_images.local.convert2query() {
  log.debug_teelog "${FUNCNAME[0]} $@"
  log.save_indent
  log.add_indent

  local _keywords=($(echo $@))
  local _query=

  for _cur_keyword in "${_keywords[@]}"; do
    # URLエンコード
    _cur_encoded_keyword=$(echo ${_cur_keyword} | nkf -WwMQ | tr = %)
    # +で繋ぐ
    if [ "${_query}" != "" ]; then
      _query="${_query}+"
    fi
    _query="${_query}${_cur_encoded_keyword}"
  done

  log.trace_teelog "query: ${_query}"
  echo ${_query}

  log.restore_indent
  return ${EXITCODE_SUCCESS}
}


#---------------------------------------------------------------------------------------------------
# 空白区切りのキーワードリストからクエリIDを返します。
#
# 引数
#   1〜: AND条件で繋ぐキーワードリスト
#
# 標準出力
#   キーワードリストが一覧に記載されている場合、その行番号
#   キーワードリストが一覧に記載されていない場合、追加した行番号
#
#---------------------------------------------------------------------------------------------------
function collect_images.local.get_query_id() {
  log.debug_teelog "${FUNCNAME[0]} $@"
  log.save_indent
  log.add_indent

  local _keywords="$@"

  local _check_keywords=$(echo ${_keywords} | sed -e 's| |__SP__|g')
  local _query_id=$(                                                                               \
    cat ${PATH_KEYWORDS}                                                                           |
    awk -v check_keywords="${_check_keywords}" '
      BEGIN {
        id = 0
      }
      {
        gsub( " ", "__SP__", $0)
        if ( $0 == check_keywords ) {
          id = NR
        }
      }
      END {
        if ( id == 0 ) {
          id = ( NR + 1 )
        }
        print id
      }
    '
  )

  local _keywords_count=$(cat ${PATH_KEYWORDS} | wc -l | sed -e 's|^ *||')
  log.trace_teelog "_query_id      : ${_query_id}"
  log.trace_teelog "_keywords_count: ${_keywords_count}"
  if [ ${_query_id} -gt ${_keywords_count} ]; then
    echo "${_keywords}" >> ${PATH_KEYWORDS}
  fi

  echo ${_query_id}

  log.restore_indent
  return ${EXITCODE_SUCCESS}
}


#---------------------------------------------------------------------------------------------------
# 画像検索結果のURL一覧を出力します
#
# 引数
#   1: クエリ
#   2: ページング上限値
#   3: 出力ファイルパス
#
# 標準出力
#   なし
#
# 出力
#   URL一覧
#
#---------------------------------------------------------------------------------------------------
function collect_images.local.search_image() {
  log.debug_teelog "${FUNCNAME[0]} $@"
  log.save_indent
  log.add_indent

  local _query="$1"
  local _max_paging_count="$2"
  local _path_out="$3"

  local _dir_out="$(dirname ${_path_out})"
  local _tmp_prefix="TMP_URL_"

  local PAGE_SIZE=80

  # 初回リクエスト
  local _page=1
  local _path_tmp="${_dir_out}/${_tmp_prefix}${_page}"
  local _ei=$(collect_images.local.first_request "${_query}" "${_path_tmp}")

  # ページングリクエスト
  for _cur_paging_count in $(seq 1 1 ${_max_paging_count}); do
    _start=$((${_page} * ${PAGE_SIZE} + 1))
    _page=$((${_page} + 1))
    _path_tmp="${_dir_out}/${_tmp_prefix}${_page}"
    collect_images.local.paging_request "${_query}" "${_ei}" "${_start}" "${_page}" "${_path_tmp}"

    # 結果が0バイトの場合、ページングを終了
    if [ ! -s ${_path_tmp} ]; then
      break
    fi
  done

  # URLリストを連結
  cat ${_dir_out}/${_tmp_prefix}*                                                                  | # URLリストを連結
  sort                                                                                             | # 一意に絞り込む
  uniq > ${_path_out}
  rm -f ${_dir_out}/${_tmp_prefix}*

  log.restore_indent
  return ${EXITCODE_SUCCESS}
}


#---------------------------------------------------------------------------------------------------
# 初回リクエスト
#
# 引数
#   1: クエリ
#   2: 出力するURLリストファイルパス
#
# 標準出力
#   ei
#
# 出力
#
#---------------------------------------------------------------------------------------------------
function collect_images.local.first_request() {
  log.debug_teelog "${FUNCNAME[0]} $@"
  log.save_indent
  log.add_indent

  local _query="$1"
  local _output_path="$2"
  local _PATH_TMP=/tmp/${FUNCNAME[0]}.html

  # 出力ディレクトリ
  local _output_dir="$(dirname ${_output_path})"
  if [ ! -d "${_output_dir}" ]; then
    mkdir "${_output_dir}"
  fi

  # HTML取得
  espv=2
  tbm="isch"
  biw=1440
  bih=803
  site=webhp
  source=lnms
  sa=X

  url_search="https://www.google.co.jp/search"
  url_search="${url_search}?q=${_query}"
  url_search="${url_search}&espv=${espv}"
  url_search="${url_search}&biw=${biw}"
  url_search="${url_search}&bih=${bih}"
  url_search="${url_search}&site=${site}"
  url_search="${url_search}&source=${source}"
  url_search="${url_search}&tbm=${tbm}"
  url_search="${url_search}&sa=${sa}"
  url_search="${url_search}&ved=${VED}"

  log.trace_teelog "url_search: ${url_search}"

  curl -s -m ${TIMEOUT} "${url_search}"                                                            \
  -H 'Referer: https://www.google.co.jp/'                                                          \
  -H 'Upgrade-Insecure-Requests: 1'                                                                \
  -H "User-Agent: ${USER_AGENT}"                                                                   \
  --compressed                                                                                     |
  tee                                                                                                > ${_PATH_TMP}

  # ei取得
  ei=$(                                                                                            \
    cat ${_PATH_TMP}                                                                               |
    grep "<noscript><meta content=\""                                                              |
    sed -e 's|.*;ei=||'                                                                            |
    sed -e 's|&amp;ved.*||')

  log.trace_teelog "ei        : ${ei}"

  # URLリスト取得
  cat ${_PATH_TMP}                                                                                 |
  tail -n 1                                                                                        |
  sed -e 's|^</script></div>||'                                                                    |
  sed -e 's|</body></html>||'                                                                      |
  sed -e 's|^|<content>|'                                                                          |
  sed -e 's|$|</content>|'                                                                         |
  parsrx.sh                                                                                        |
  grep ",\"${OUTPUT_TYPE}\":"                                                                      |
  cut -d " " -f 2-                                                                                 |
  jq .${OUTPUT_TYPE}                                                                               |
  perl -Xpne 's/\\\\u([0-9a-fA-F]{4})/chr(hex($1))/eg'                                             |
  sed -e 's|^"||'                                                                                  |
  sed -e 's|"$||'                                                                                  |
  tee                                                                                                > ${_output_path}

  log.trace_teelog "_output_path: ${_output_path}"

  echo ${ei}

  log.restore_indent
  return ${EXITCODE_SUCCESS}
}


#---------------------------------------------------------------------------------------------------
# ページングリクエスト
#
# 引数
#   1: クエリ
#   2: 初回リクエストei
#   3: オフセット
#   4: ページ番号
#   5: 出力するURLリストファイルパス
#
# 標準出力
#   ei
#
# 出力
#
#---------------------------------------------------------------------------------------------------
function collect_images.local.paging_request() {
  log.debug_teelog "${FUNCNAME[0]} $@"
  log.save_indent
  log.add_indent

  local _query="$1"
  local _ei="$2"
  local _start="$3"
  local _page="$4"
  local _output_path="$5"

  # スクロールイベント発行
  iact=ms
  forward=1
  scroll=100
  ndsp=12

  url_search="https://www.google.co.jp/imgevent"
  url_search="${url_search}?ei=${_ei}"
  url_search="${url_search}&iact=${iact}"
  url_search="${url_search}&forward=${forward}"
  url_search="${url_search}&scroll=${scroll}"
  url_search="${url_search}&page=${_page}"
  url_search="${url_search}&start=${_start}"
  url_search="${url_search}&ndsp=${ndsp}"
  url_search="${url_search}&bih=${bih}"
  url_search="${url_search}&biw=${biw}"

  log.trace_teelog "url_search: ${url_search}"

  cur_ei=$(                                                                                        \
    curl -s -m ${TIMEOUT} "${url_search}"                                                          \
      -H 'Referer: https://www.google.co.jp/'                                                      \
      -H 'Upgrade-Insecure-Requests: 1'                                                            \
      -H "User-Agent: ${USER_AGENT}"                                                               \
      --compressed                                                                                 |
    sed -e 's|.*"ei":"||' |
    sed -e 's|".*$||')

  log.trace_teelog "cur_ei    : ${cur_ei}"

  # 発行したイベントIDでHTML取得
  async="_id:rg_s,_pms:s"
  yv=2
  asearch="ichunk"
  ijn=3
  vet="1${VED}.${cur_ei}.i"

  url_search="https://www.google.co.jp/search"
  url_search="${url_search}?async=${async}"
  url_search="${url_search}&ei=${cur_ei}"
  url_search="${url_search}&espv=${espv}"
  url_search="${url_search}&yv=${yv}"
  url_search="${url_search}&q=${_query}"
  url_search="${url_search}&start=${_start}"
  url_search="${url_search}&asearch=${asearch}"
  url_search="${url_search}&tbm=${tbm}"
  url_search="${url_search}&vet=${vet}"
  url_search="${url_search}&ved=${VED}"
  url_search="${url_search}&ijn=${ijn}"

  log.trace_teelog "url_search: ${url_search}"

  curl -s -m ${TIMEOUT} "${url_search}"                                                            \
    -H 'Referer: https://www.google.co.jp/'                                                        \
    -H 'Upgrade-Insecure-Requests: 1'                                                              \
    -H "User-Agent: ${USER_AGENT}"                                                                 \
    --compressed                                                                                   |
#---------------------------------------------------------------------------------------------------
# デバッグ用
#  tee > ${_output_path}.json
#  cat ${_output_path}.json                                                                         |
#---------------------------------------------------------------------------------------------------
  jq .                                                                                             | # jsonが返される
  tail -n 3                                                                                        | # 後ろから3行目 が htmlソース
  head -n 1                                                                                        |
  parsrx.sh                                                                                        | # 「xpath 要素or属性値」にパース
  grep "/imgres"                                                                                   | # googleの/imgresエンドポイント要素から
  cut -d " " -f 2-                                                                                 | # 値に絞る
  sed -e 's|^.*imgurl=||'                                                                          | # クエリストリングの参照先URLに絞り込む
  sed -e 's|&amp;.*$||'                                                                            |
  perl -Xpne 's/\\\\u([0-9a-fA-F]{4})/chr(hex($1))/eg'                                             | # Unicodeエスケープをデコード
  nkf --url-input                                                                                  | # URLデコード
  sed -e 's|^"||'                                                                                  | # ダブルクォートを除去
  sed -e 's|"$||'                                                                                  |
  tee > ${_output_path}

  log.debug_teelog "_output_path: ${_output_path}"

  log.restore_indent
  return ${EXITCODE_SUCCESS}
}


#---------------------------------------------------------------------------------------------------
# ファイルダウンロード
#
# 引数
#   1: ダウンロード対象URLリスト
#   2: ダウンロードディレクトリ
#   3: ダウンロード結果ファイルパス
#   4: ダウンロード履歴ファイルパス
#
#---------------------------------------------------------------------------------------------------
function collect_images.local.download_files() {
  log.debug_teelog "${FUNCNAME[0]} $@"
  log.save_indent
  log.add_indent

  local _path_url_list="$1"
  local _dir_image_root="$2"
  local _path_result="$3"
  local _path_history="$4"

  # ヘッダー出力
  if [ ! -f ${path_history} ]; then
    echo "TIMESTAMP STATUS URL PATH" > ${path_history}
  fi

  local _func_ret_code=${EXITCODE_SUCCESS}
  local _total_dl_count=$(cat ${_path_url_list} | wc -l | sed -e 's|^ *||')
  local _cur_dl_count=0
  for _cur_url in $(cat ${_path_url_list}); do
    _cur_dl_count=$((${_cur_dl_count} + 1))

    local _downloaded_path=$(collect_images.local.cut_filepath ${_dir_image_root}/$(echo ${_cur_url} | sed -e 's|.*//||'))
    local _rel_path=$(echo ${_downloaded_path} | sed -e "s|${DIR_DATA}/||")

    local _status=""
    if [ -f ${_downloaded_path} ]; then
      # すでに存在する場合、スキップ
      _status="SKIP"
      echo "${_rel_path}" >> ${_path_result}

    else
      # 存在しない場合、ダウンロード
      local _downloaded_dir=$(dirname ${_downloaded_path})
      if [ ! -d ${_downloaded_dir} ]; then
        mkdir -p ${_downloaded_dir}
      fi

      curl -s -m ${TIMEOUT} -o "${_downloaded_path}" "${_cur_url}"
      local _ret_code=$?
      if [ ${_ret_code} -eq 0 ]; then
        _status="SUCCESS"
        echo "${_rel_path}" >> ${_path_result}
      else
        log.error_teelog "curl -s -m ${TIMEOUT} -o \"${_downloaded_path}\" \"${_cur_url}\""
        log.error_teelog "ret_code: ${_ret_code}"
        _func_ret_code=${EXITCODE_ERROR}
        _status="ERROR"
      fi
    fi

    echo "$(date '+%Y-%m-%dT%H:%M:%S+0900') ${_status} ${_cur_url} ${_rel_path}" >> ${_path_history}
    log.debug_teelog "${_cur_dl_count} / ${_total_dl_count} files downloaded."
  done

  log.restore_indent
  return ${_func_ret_code}
}



#---------------------------------------------------------------------------------------------------
# ファイル名の文字数制限考慮
#   256バイトを超える場合、240バイトにカットしたファイル名を返します。
#
# 引数
#   1: 確認対象ファイルパス
#
#---------------------------------------------------------------------------------------------------
function collect_images.local.cut_filepath() {
  local _path="$1"
  local _dir=$(dirname ${_path})
  local _src_name=$(basename ${_path})
  local _dst_name=""

  local _byte_length=$(echo -n ${_src_name} | wc -c)
  if [ ${_byte_length} -ge 256 ]; then
    # バイト長が256を超えている場合、カット
    local _char_length=${#_src_name}
    if [ ${_char_length} -eq ${_byte_length} ]; then
      # 文字数がバイト長と一致する場合、240文字（バイト）でカット
      _dst_name="${_src_name:0:240}"
    else
      # 文字数がバイト長と一致しない場合、UTF8扱いで1/3の80文字でカット
      _dst_name="${_src_name:0:80}"
    fi

  else
    # バイト長が256を超えていない場合、カットなし
    _dst_name="${_src_name}"
  fi

  echo "${_dir}/${_dst_name}"
}



#---------------------------------------------------------------------------------------------------
# 行番号シンボリックリンク作成
#
# 引数
#   1: 相対パスが列挙されたリスト
#   2: 相対パスの起点ディレクトリ
#   3: シンボリックリンク作成ディレクトリ
#
#---------------------------------------------------------------------------------------------------
function collect_images.local.create_linenum_link() {
  log.debug_teelog "${FUNCNAME[0]} $@"
  log.save_indent
  log.add_indent

  local _path_target_list="$1"
  local _dir_relate="$2"
  local _dir_links="$3"

  if [ -d ${_dir_links} ]; then
    rm -fr ${_dir_links}
  fi
  mkdir -p ${_dir_links}

  cur_line_num=0
  for cur_line in $(cat ${_path_target_list}); do
    cur_line_num=$((${cur_line_num} + 1))
    ln -s ${_dir_relate}/${cur_line} ${_dir_links}/${cur_line_num}
  done

  log.restore_indent
  return ${EXITCODE_SUCCESS}
}
