#/bin/bash
#set -eux
#===================================================================================================
#
# Google画像検索結果収集
#
#===================================================================================================
#--------------------------------------------------------------------------------------------------
# 環境設定
#--------------------------------------------------------------------------------------------------
# カレントディレクトリの移動
cd $(cd $(dirname $0); pwd)

# 共通設定
if [ "${DIR_BASE}" = "" ]; then
  readonly DIR_BASE=$(cd ..; pwd)
  . ./setenv.sh

  # ログ出力ユーティリティ
  . ${DIR_BIN_LIB}/logging_utils.sh
fi

# スクリプト名
readonly SCRIPTNAME=`basename $0 .sh`
# ログファイルパス
PATH_LOG=${DIR_LOG}/${SCRIPTNAME}.log


# セマフォユーティリティ
. ${DIR_BIN_LIB}/semaphore_utils.sh
# バックグラウンドプロセス管理
. ${DIR_BIN_LIB}/bg_proc_control.sh



#--------------------------------------------------------------------------------------------------
# 関数定義
#--------------------------------------------------------------------------------------------------
#--------------------------------------------------------------------------------
# usage
#--------------------------------------------------------------------------------
function usage() {
  cat <<_EOT_
    Usage:
      `basename $0`

    Description:
      ${PATH_KEYWORDS}に記載されたキーワードリスト群で
      画像検索にヒットしたファイルをダウンロードします。

      キーワードリスト毎に、検索・ダウンロードを並走します。
      並走数は、${DIR_CONFIG}/project.properties の MAX_PROCESS_KEYWORD で指定できます。

      ダウンロードしたファイルは、${DIR_DATA}/images/${URI}で、一元管理します。
      ※一度ダウンロードしたファイルは、別のキーワードでヒットしたとしてもダウンロードされません。


      キーワードリストとダウンロードしたファイルの紐付けは
      ${DIR_DATA}/COLLECT_RESULT と ${DIR_DATA}/queries で確認できます。

        ${DIR_DATA}/COLLECT_RESULT_${KEYWORDSの行番号}
          ダウンロードしたファイルパスのリスト
        ${DIR_DATA}/queries/${KEYWORDSの行番号}/${COLLECT_RESULTの行番号}
          ${DIR_DATA}/images/${URI} へのシンボリックリンク


      ダウンロード実行の履歴は ${DIR_DATA}/COLLECT_RESULT_HISTORY で確認できます。

        ${DIR_DATA}/COLLECT_RESULT_HISTORY_${KEYWORDSの行番号}
          実行時刻 ステータス ダウンロードファイルパス
            ステータス
              SUCCESS: ダウンロード成功
              ERROR  : ダウンロード失敗
              SKIP   : スキップ ※すでにダウンロードされているため


    OPTIONS:
      なし

    Args:
      なし

    Sample:
      `basename $0`

    Output:
      ${DIR_DATA}/
        KEYWORDS
        COLLECT_RESULT_${KEYWORDSの行番号}
        COLLECT_RESULT_HISTORY_${KEYWORDSの行番号}
        images/${URI}
        queries/${KEYWORDSの行番号}/${COLLECT_RESULTの行番号}

    ReturnCode:
      ${EXITCODE_SUCCESS}: 正常終了
      ${EXITCODE_ERROR}: エラー発生時

_EOT_
  exit ${EXITCODE_ERROR}
}

#---------------------------------------------------------------------------------------------------
# exit
#---------------------------------------------------------------------------------------------------
function exit_script() {
  log.restore_indent
  log.add_indent

  #------------------------------------------------------------------------------
  # スクリプト個別処理
  #------------------------------------------------------------------------------
  # なし

  #------------------------------------------------------------------------------
  # 共通処理
  #------------------------------------------------------------------------------
  # エラーの場合、子プロセス群をkill
  if [ ${proc_exit_code} -eq ${EXITCODE_ERROR} ]; then
    . ${DIR_BIN_LIB}/bg_proc_control.sh
    bg_proc_control.kill_children
  fi

  # セマフォ解放
  semaphore.release
  log.remove_indent

  # 終了ログ
  if [ ${proc_exit_code} -eq ${EXITCODE_SUCCESS} ]; then
    log.info_teelog "${proc_exit_msg}"
    log.info_teelog "ExitCode:${proc_exit_code}"
    log.info_teelog "END   `basename $0` $*"
  elif [ ${proc_exit_code} -eq ${EXITCODE_WARN} ]; then
    log.warn_teelog "${proc_exit_msg}"
    log.warn_teelog "ExitCode:${proc_exit_code}"
    log.warn_teelog "END   `basename $0` $*"
  else
    log.error_teelog "${proc_exit_msg}"
    log.error_teelog "ExitCode:${proc_exit_code}"
    log.error_teelog "END   `basename $0` $*"
  fi

  # ログローテーション（日次） ※先頭行判断
  log.rotatelog_by_day_first

  # 終了
  exit ${proc_exit_code}
}



#--------------------------------------------------------------------------------------------------
# 事前処理
#--------------------------------------------------------------------------------------------------
log.info_teelog "START `basename $0` $*"

proc_exit_msg=${EXITMSG_SUCCESS}
proc_exit_code=${EXITCODE_SUCCESS}

#--------------------------------------------------------------------------------
# オプション解析
#--------------------------------------------------------------------------------
while :; do
  case $1 in
    --)
      shift
      break
      ;;
    -*)
      usage
      ;;
    *)
      break
      ;;
  esac
done

#--------------------------------------------------------------------------------
# 引数取得
#--------------------------------------------------------------------------------
# 引数チェック
if [ $# -ne 0 ]; then
  usage
fi

#--------------------------------------------------------------------------------
# ロック開始
#--------------------------------------------------------------------------------
log.save_indent
log.add_indent

# セマフォ取得
semaphore.acquire `basename $0`

# 強制終了トラップ
trap "                                                                                             \
proc_exit_msg='強制終了を検知したため処理を終了します。';                                          \
proc_exit_code=${EXITCODE_ERROR};                                                                  \
exit_script" SIGHUP SIGINT SIGQUIT SIGTERM


#---------------------------------------------------------------------------------------------------
# 本処理
#---------------------------------------------------------------------------------------------------
# 検索条件ファイル
if [ ! -f ${PATH_KEYWORDS} ]; then
  log.error_teelog "${PATH_KEYWORDS} が存在しません。"
  proc_exit_msg=${EXITMSG_ERROR}
  proc_exit_code=${EXITCODE_ERROR}
  exit_script
fi

# vedがなくても大丈夫な様子
## VED設定チェック
#if [ "${VED}" = "" ]; then
#  log.error_teelog "環境変数 VED が設定されていません。Google検索結果のアドレスバーからvedの値を config/project.properties に設定してください。"
#  proc_exit_msg=${EXITMSG_ERROR}
#  proc_exit_code=${EXITCODE_ERROR}
#  exit_script
#fi

process_option=""
#  local _process_option="-w"
#  local _process_option="-e"
process_group="${SCRIPTNAME}_$$"
max_process_keyword=${MAX_PROCESS_KEYWORD}

# バックグラウンド実行 初期化処理
bg_proc_control.init ${process_option} ${process_group} ${max_process_keyword} "${STATUS_SUCCESS}" "${STATUS_WARN}" "${STATUS_ERROR}"

# キーワード一覧の全行をダウンロード
before_IFS="$IFS"
IFS=$'\n'
for cur_keywords in $(cat ${PATH_KEYWORDS} | _except_comment_row | _except_empty_row); do

  cur_command="                                                                                    \
    DIR_BASE=${DIR_BASE};                                                                          \
    PATH_LOG=${PATH_LOG};                                                                          \
    . ${DIR_BIN}/setenv.sh;                                                                        \
    . ${DIR_BIN_LIB}/collect_images_utils.sh;                                                      \
    collect_images.collect \"${cur_keywords}\"                                                     \
  "
  cur_proc_name=$(echo ${cur_keywords} | sed -e 's| |-|g')
  bg_proc_control.start_process ${process_group} ${cur_proc_name} "${cur_command}"
  ret_code=$?
  if [ ${ret_code} -eq ${EXITCODE_WARN} ]; then
    proc_exit_msg=${EXITMSG_WARN}
    proc_exit_code=${EXITCODE_WARN}

  elif [ ${ret_code} -eq ${EXITCODE_ERROR} ]; then
    proc_exit_msg=${EXITMSG_ERROR}
    proc_exit_code=${EXITCODE_ERROR}
    exit_script
  fi

done
IFS="${before_IFS}"

# バックグラウンド実行 終了処理
bg_proc_control.destroy ${process_group}
ret_code=$?
if [ ${ret_code} -eq ${EXITCODE_WARN} ]; then
  proc_exit_msg=${EXITMSG_WARN}
  proc_exit_code=${EXITCODE_WARN}

elif [ ${ret_code} -eq ${EXITCODE_ERROR} ]; then
  proc_exit_msg=${EXITMSG_ERROR}
  proc_exit_code=${EXITCODE_ERROR}
fi


#---------------------------------------------------------------------------------------------------
# 事後処理
#---------------------------------------------------------------------------------------------------
exit_script
