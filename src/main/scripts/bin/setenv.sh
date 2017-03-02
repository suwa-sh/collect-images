#!/bin/bash
#==================================================================================================
# システム設定
#
# 前提
#   ・${DIR_BASE} が事前に設定されていること
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 定数
#--------------------------------------------------------------------------------------------------
# 終了コード
readonly EXITCODE_SUCCESS=0
readonly EXITCODE_WARN=3
readonly EXITCODE_ERROR=6

# 終了メッセージ
readonly EXITMSG_SUCCESS="NORMAL END."
readonly EXITMSG_WARN="PROCESS END with WARNNING."
readonly EXITMSG_ERROR="ABNORMAL END."

# ログレベル
readonly LOGLEVEL_TRACE="TRACE"
readonly LOGLEVEL_DEBUG="DEBUG"
readonly LOGLEVEL_INFO="INFO "
readonly LOGLEVEL_WARN="WARN "
readonly LOGLEVEL_ERROR="ERROR"

# ステータス文言
readonly STATUS_SUCCESS="SUCCESS"
readonly STATUS_WARN="WARN   "
readonly STATUS_ERROR="ERROR  "
readonly STATUS_SKIP="SKIP   "

# ディレクトリ
readonly DIR_BIN=${DIR_BASE}/bin
readonly DIR_BIN_LIB=${DIR_BIN}/lib
readonly DIR_LOG=${DIR_BASE}/log

readonly DIR_CONFIG=${DIR_BASE}/config
readonly DIR_DATA=${DIR_BASE}/data

# バージョンファイル
readonly PATH_VERSION=${DIR_BASE}/version.txt

# プロセスファイル
readonly PATH_PID=${DIR_DATA}/pid

# プロジェクト毎の上書き設定ファイル
readonly PATH_PROJECT_ENV="${DIR_CONFIG}/project.properties"

readonly OUTPUT_TYPE="ou"
readonly VED="0ahUKEwiulMK6hbTSAhXFyLwKHSe1AtUQ_AUIBygA"


#--------------------------------------------------------------------------------------------------
# 共通関数読込み
#--------------------------------------------------------------------------------------------------
. ${DIR_BIN_LIB}/common_utils.sh


#--------------------------------------------------------------------------------------------------
# 変数
#
# ここでの変数定義はデフォルト値です。
# PATH_PROJECT_ENV、PATH_ACCESS_INFO で自プロジェクト向けの設定に上書きして下さい。
#
#--------------------------------------------------------------------------------------------------
# ログレベル
LOGLEVEL=${LOGLEVEL_TRACE}

# キーワードリスト
PATH_KEYWORDS="${DIR_CONFIG}/keywords"

# プロセス並走数の上限数
MAX_PROCESS_KEYWORD=16
# ページング上限数
MAX_PAGING_COUNT=100
# ダウンロードのタイムアウト秒
TIMEOUT=30
# ダウンロードリクエストのUserAgent
USER_AGENT="XXX"


#--------------------------------------------------------------------------------------------------
# プロジェクト毎の上書き設定読込み
#--------------------------------------------------------------------------------------------------
if [ -f ${PATH_PROJECT_ENV} ]; then
  . ${PATH_PROJECT_ENV}
else
  echo "ERROR ${PATH_PROJECT_ENV} が存在しません。デプロイ結果が正しいか確認して下さい。" >&2
  exit 1
fi
