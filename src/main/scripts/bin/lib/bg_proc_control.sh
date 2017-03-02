#!/bin/bash
#set -eux
#==================================================================================================
# バックグラウンドプロセス管理ユーティリティ
#
#   並走数上限を設定して、バックグラウンドプロセスをパラレル実行します。
#   並走数上限に達すると、自動でwaitして、同期後に後続プロセスを実行します。
#   各バックグラウンドプロセスの標準出力/エラーは
#   start_process と destroy で catされるので、必要に応じてログなどにteeして下さい。
#   実行が終了すると、バックグラウンドプロセスの実行結果を一覧で表示します。
#
#   詳しい利用方法は「bg_proc_control.SAMPLE」を参考にして下さい。
#
# 前提
#   ・setenv.sh を事前に読み込んでいること
#
# 定義リスト
#   ・bg_proc_control.init
#   ・bg_proc_control.start_process
#   ・bg_proc_control.destroy
#   ・bg_proc_control.kill
#   ・bg_proc_control.kill_children
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 依存スクリプト読込み
#--------------------------------------------------------------------------------------------------
# ログ出力ユーティリティ
. ${DIR_BIN_LIB}/logging_utils.sh



#--------------------------------------------------------------------------------------------------
# 定数
#--------------------------------------------------------------------------------------------------
BG_PROC_CONTROL__DIR_WK_PREFIX="/tmp/bg_procs"
BG_PROC_CONTROL__HANDLEMODE_IGNORE_STATUS="ignore_status"
BG_PROC_CONTROL__HANDLEMODE_EXIT_ON_WARN="exit_on_warn"
BG_PROC_CONTROL__HANDLEMODE_EXIT_ON_ERROR="exit_on_error"



#--------------------------------------------------------------------------------------------------
# 指定プロセスグループの作業ディレクトリを返します。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.get_group_dir() {
  echo "${BG_PROC_CONTROL__DIR_WK_PREFIX}__$1"
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループの並走リミットファイルパスを返します。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.get_limit_path() {
  echo "$(bg_proc_control.local.get_group_dir $1)/limit"
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループのサマリファイルパスを返します。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.get_summary_path() {
  echo "$(bg_proc_control.local.get_group_dir $1)/summary"
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループのエラーハンドリングモードファイルパスを返します。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.get_handle_mode_path() {
  echo "$(bg_proc_control.local.get_group_dir $1)/handle_mode"
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループのPIDディレクトリを返します。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.get_pid_dir() {
  echo "$(bg_proc_control.local.get_group_dir $1)/pid"
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループのログディレクトリを返します。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.get_log_dir() {
  echo "$(bg_proc_control.local.get_group_dir $1)/log"
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループ、プロセス名のログファイルパスを返します。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.get_log_path() {
  echo "$(bg_proc_control.local.get_log_dir $1)/$2"
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループのステータス文言ファイルパスを返します。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.get_status_msg_path() {
  echo "$(bg_proc_control.local.get_group_dir $1)/status_msg"
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループ、リターンコードでのステータス文言を設定します
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.set_status_msg() {
  local _group="$1"
  local _ret_code="$2"
  local _msg="$3"

  echo "${_ret_code},${_msg}" >> $(bg_proc_control.local.get_status_msg_path ${_group})
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループ、リターンコードでのステータス文言を返します
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.get_status_msg() {
  local _group="$1"
  local _ret_code="$2"

  local _status_msg=$(
    cat $(bg_proc_control.local.get_status_msg_path ${_group})                                     |
    grep -e "${_ret_code}"                                                                         |
    cut -d "," -f 2
  )

  # メッセージが取得できない場合、STATUS_ERRORを返却
  if [ "${_status_msg}" = "" ]; then
    _status_msg=${STATUS_ERROR}
  fi

  echo ${_status_msg}
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグのサマリファイルに、指定のリターンコードが含まれているか、確認します
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.has_status_in_summary() {
  local _group="$1"
  local _target_ret_code="$2"

  # リターンコードから、ステータス文言に変換
  local _target_status_msg=$(bg_proc_control.local.get_status_msg ${_group} ${_target_ret_code})

  cat $(bg_proc_control.local.get_summary_path ${_group})                                          |
  cut -d "," -f 1                                                                                  |
  grep -e "${_target_status_msg}"                                                                    > /dev/null
  local _ret_code=$?

  if [ ${_ret_code} -eq ${EXITCODE_SUCCESS} ]; then
    echo "true"
  else
    echo "false"
  fi

  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループに、バックグラウンドプロセスを追加できるか判断します。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.can_start_process() {
  local _group="$1"

  # 初期化済チェック
  if [ ! -d "$(bg_proc_control.local.get_group_dir ${_group})" ]; then
    log.error_console "初期化されていません。処理順を見なおして下さい。"
    return ${EXITCODE_ERROR}
  fi

#  log.trace_console "${FUNCNAME[0]} $@"
#  log.add_indent

  # log_dir の logファイル数 をカウント
  local _cur_proc_count=$(ls $(bg_proc_control.local.get_log_dir ${_group}) | wc -l)
#  log.trace_console "_cur_proc_count: ${_cur_proc_count}"

  # limit と比較
  local _limit=$(cat $(bg_proc_control.local.get_limit_path ${_group}))
#  log.trace_console "_limit: ${_limit}"

  if [ ${_limit} -le 0 -o ${_cur_proc_count} -lt ${_limit} ]; then
    # limitが0以下の場合、無条件でtrue
    # limit未満の場合、true
    echo "true"
#    log.trace_console "result: true"
  else
    # その他の場合、false
    echo "false"
#    log.trace_console "result: false"
  fi

#  log.remove_indent
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループ、プロセス名の実行結果を反映します。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.finish_process() {
  local _group="$1"
  local _proc_name="$2"
  local _proc_ret_code="$3"

  # ret_codeから終了ステータスを判定
  local _proc_status="$(bg_proc_control.local.get_status_msg ${_group} ${_proc_ret_code})"

  # summaryファイル に 判定した終了ステータスを追記
  echo "${_proc_status},${_proc_name}" >> $(bg_proc_control.local.get_summary_path ${_group})
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 指定プロセスグループの実行結果をフラッシュします。
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.flush() {
  local _group="$1"

  # log_dir の logファイル を全件ループ
  for _cur_file_path in `find $(bg_proc_control.local.get_log_dir ${_group}) -maxdepth 1 -follow -type f | sort`; do
    local _cur_file_name=`basename ${_cur_file_path}`

    # logファイルをcat
    echo "============================== ${_group}.${_cur_file_name} 標準出力/標準エラー START =============================="
    cat ${_cur_file_path}
    echo "============================== ${_group}.${_cur_file_name} 標準出力/標準エラー END   =============================="

    # logファイルをremove
    rm -f ${_cur_file_path}
    # pidファイルをremove
    rm -f $(bg_proc_control.local.get_pid_dir ${_group})/${_cur_file_name}
  done

  # エラーハンドリング
  local _handle_mode=$(cat $(bg_proc_control.local.get_handle_mode_path ${_group}))
  local _has_error_in_summary=$(bg_proc_control.local.has_status_in_summary ${_group} ${EXITCODE_ERROR})
  local _has_warn_in_summary=$(bg_proc_control.local.has_status_in_summary ${_group} ${EXITCODE_WARN})

  if [ "${_handle_mode}" = "${BG_PROC_CONTROL__HANDLEMODE_EXIT_ON_ERROR}" ]; then
    # exit_on_err の場合
    if [ "${_has_error_in_summary}" = "true" ]; then
      # 共通終了処理
      bg_proc_control.local.end_script ${_group}
      log.error_console "バックグラウンドプロセスが、エラー終了しました。"
      return ${EXITCODE_ERROR}
    fi

  elif [ "${_handle_mode}" = "${BG_PROC_CONTROL__HANDLEMODE_EXIT_ON_WARN}" ]; then
    # exit_on_warn の場合
    if [ "${_has_error_in_summary}" = "true" ]; then
      # 共通終了処理
      bg_proc_control.local.end_script ${_group}
      log.error_console "バックグラウンドプロセスが、エラー終了しました。"
      return ${EXITCODE_ERROR}

    elif [ "${_has_warn_in_summary}" = "true" ]; then
      # 共通終了処理
      bg_proc_control.local.end_script ${_group}
      log.warn_console "バックグラウンドプロセスが、警告終了しました。"
      return ${EXITCODE_WARN}

    fi
  fi

  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 共通終了処理
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.end_script() {
  local _group="$1"

  # summaryファイルをcat
  log.info_console "バックグラウンドプロセス 実行結果サマリ"
  cat $(bg_proc_control.local.get_summary_path ${_group})

  # workディレクトリ削除
  rm -fr $(bg_proc_control.local.get_group_dir ${_group})

  log.remove_indent
}

#--------------------------------------------------------------------------------------------------
# 概要
#   自プロセスの子プロセス群をkillします。
#
# 引数
#   なし
#
# 出力
#   なし
#
#--------------------------------------------------------------------------------------------------
function bg_proc_control.kill_children() {
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  bg_proc_control.local.kill_tree_by_pid `bg_proc_control.local.get_children_pid $$`

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 概要
#   指定PIDを、子プロセスから順にkillします。
#
# 引数
#   ・1〜: kill対象プロセスIDリスト
#
# 出力
#   なし
#
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.kill_tree_by_pid() {
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  while [ $# -gt 0 ]; do
    log.debug_console "bg_proc_control.local.get_children_pid $1"
    sub_procs=`bg_proc_control.local.get_children_pid $1`

    log.add_indent
    while [ "${sub_procs}" != "" ]; do
      log.debug_console "kill ${sub_procs}"
      kill ${sub_procs}

      log.debug_console "bg_proc_control.local.get_children_pid $1"
      sub_procs=`bg_proc_control.local.get_children_pid $1`
    done
    log.remove_indent

    shift
  done

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}
function bg_proc_control.local.get_children_pid() {
  log.trace_console "${FUNCNAME[0]} $@"
  log.add_indent

  if [ "$1" = "" ]; then
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  if [ $(is_mac) = "true" ]; then
    log.trace_console "ps -eo ppid,pid | grep \" $1 \" | sed -E \"s| +| |g\" | sed -E \"s|^ ||\" | cut -d \" \" -f 2"
    ps -eo ppid,pid | grep " $1 " | sed -E "s| +| |g" | sed -E "s|^ ||" | cut -d " " -f 2
  else
    log.trace_console "ps ho pid --ppid=$1"
    ps ho pid --ppid=$1
  fi

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}

#--------------------------------------------------------------------------------------------------
# 概要
#   初期化
#
# 引数
#   ・1: グループ名
#   ・2: 並走リミット数
#   ・3: 正常終了時ステータス文言
#   ・4: 警告終了時ステータス文言
#   ・5: エラー終了時ステータス文言
#
# オプション
#   ・-e|--exit_on_error
#     バックグラウンドプロセスでエラーが発生した場合、後続は起動せずにエラー終了します。
#
#   ・-w|--exit_on_warn
#     バックグラウンドプロセスで警告終了が発生した場合、後続は起動せずに警告終了
#     エラーが発生した場合、後続は起動せずにエラー終了します。
#
# リターンコード
#    0: 成功時
#    3: 警告発生時
#    6: エラー発生時
#
# 出力
#   プロセスグループ作業ディレクトリ
#
#--------------------------------------------------------------------------------------------------
function bg_proc_control.init() {
  log.debug_console "${FUNCNAME[0]} $1 $2"
  log.add_indent

  _is_exit_on_error=false
  _is_exit_on_warn=false

  # オプション解析
  while :; do
    case $1 in
      -e|--exit_on_error)
        _is_exit_on_error=true
        shift
        ;;
      -w|--exit_on_warn)
        _is_exit_on_warn=true
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  # オプションチェック
  if [ "${_is_exit_on_error}" = "true" -a "${_is_exit_on_warn}" = "true" ]; then
    log.error_console "exit_on_error と exit_on_warn は同時に指定できません。呼出しを見なおして下さい。"
    return ${EXITCODE_ERROR}
  fi

  # 引数取得
  local _group="$1"
  local _limit="$2"
  local _msg_success="$3"
  local _msg_warn="$4"
  local _msg_error="$5"

  # 引数チェック
  if [ "${_group}" = "" ]; then
    log.error_console "グループ名が指定されていません。呼出しを見なおして下さい。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  if [ "${_limit}" = "" ]; then
    log.error_console "並走リミット数が指定されていません。呼出しを見なおして下さい。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # logディレクトリ作成
  log.trace_console "mkdir -p $(bg_proc_control.local.get_log_dir ${_group})"
  mkdir -p $(bg_proc_control.local.get_log_dir ${_group})

  # pidディレクトリ作成
  log.trace_console "mkdir -p $(bg_proc_control.local.get_pid_dir ${_group})"
  mkdir -p $(bg_proc_control.local.get_pid_dir ${_group})

  # summaryファイル ヘッダー出力
  log.trace_console "echo \"STATUS ,PROCESS_NAME\" > $(bg_proc_control.local.get_summary_path ${_group})"
  echo "STATUS ,PROCESS_NAME" > $(bg_proc_control.local.get_summary_path ${_group})

  # limitファイル出力
  log.trace_console "echo \"${_limit}\" > $(bg_proc_control.local.get_limit_path ${_group})"
  echo "${_limit}" > $(bg_proc_control.local.get_limit_path ${_group})

  # エラーハンドリングモードファイル出力
  if [ "${_is_exit_on_error}" = "true" ]; then
    log.trace_console "echo \"${BG_PROC_CONTROL__HANDLEMODE_EXIT_ON_ERROR}\" > $(bg_proc_control.local.get_handle_mode_path ${_group})"
    echo "${BG_PROC_CONTROL__HANDLEMODE_EXIT_ON_ERROR}" > $(bg_proc_control.local.get_handle_mode_path ${_group})

  elif [ "${_is_exit_on_warn}" = "true" ]; then
    log.trace_console "echo \"${BG_PROC_CONTROL__HANDLEMODE_EXIT_ON_WARN}\" > $(bg_proc_control.local.get_handle_mode_path ${_group})"
    echo "${BG_PROC_CONTROL__HANDLEMODE_EXIT_ON_WARN}" > $(bg_proc_control.local.get_handle_mode_path ${_group})

  else
    log.trace_console "echo \"${BG_PROC_CONTROL__HANDLEMODE_IGNORE_STATUS}\" > $(bg_proc_control.local.get_handle_mode_path ${_group})"
    echo "${BG_PROC_CONTROL__HANDLEMODE_IGNORE_STATUS}" > $(bg_proc_control.local.get_handle_mode_path ${_group})
  fi

  # ステータス文言ファイル出力
  log.trace_console "bg_proc_control.local.set_status_msg ${_group} ${EXITCODE_SUCCESS} \"${_msg_success}\""
  log.trace_console "bg_proc_control.local.set_status_msg ${_group} ${EXITCODE_WARN}    \"${_msg_warn}\""
  log.trace_console "bg_proc_control.local.set_status_msg ${_group} ${EXITCODE_ERROR}   \"${_msg_error}\""
  bg_proc_control.local.set_status_msg ${_group} ${EXITCODE_SUCCESS} "${_msg_success}"
  bg_proc_control.local.set_status_msg ${_group} ${EXITCODE_WARN}    "${_msg_warn}"
  bg_proc_control.local.set_status_msg ${_group} ${EXITCODE_ERROR}   "${_msg_error}"

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}


#--------------------------------------------------------------------------------------------------
# 概要
#   バックグラウンドプロセス開始
#
# 引数
#   ・1: グループ名
#   ・2: プロセス名
#   ・3〜: 実行コマンド
#
# オプション
#    なし
#
# リターンコード
#    0: 成功時
#    3: 警告発生時
#    6: エラー発生時
#
# 出力
#   プロセスグループ作業ディレクトリ
#
#--------------------------------------------------------------------------------------------------
function bg_proc_control.start_process() {
  log.debug_console "${FUNCNAME[0]} $1 $2"
  log.trace_console "command: \"${@:3:$#-2}\""
  log.add_indent

  local _group="$1"
  local _proc_name="$2"

  # 引数チェック
  if [ "${_group}" = "" ]; then
    log.error_console "グループ名が指定されていません。呼出しを見なおして下さい。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  if [ "${_proc_name}" = "" ]; then
    log.error_console "プロセス名が指定されていません。呼出しを見なおして下さい。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 実行可否チェック
  local _can_start=$(bg_proc_control.local.can_start_process ${_group})
  local _ret_code=$?
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
      # 正常終了以外は、ここで終了
      return ${_ret_code}
  fi
  if [ "${_can_start}" != "true" ]; then
    # limitに達している場合、wait
    log.debug_console "wait"
    wait

    log.debug_console "bg_proc_control.local.flush ${_group}"
    bg_proc_control.local.flush ${_group}
    _ret_code=$?
    if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
      # 正常終了以外は、ここで終了
      return ${_ret_code}
    fi

  fi

  # 開始ログ
  log.info_console "START ${_group} ${_proc_name}"

  # logファイルをtouch
  local _proc_log_path="$(bg_proc_control.local.get_log_path ${_group} ${_proc_name})"
  touch ${_proc_log_path}
  log.debug_console "tail -f \"${_proc_log_path}\""

  # コマンドをバックグラウンド実行
  shift 2
  {
    bash -c "$@" >>${_proc_log_path} 2>&1;
    local _cur_ret_code=$?;
    # バックグラウンド実行 後処理
    bg_proc_control.local.finish_process ${_group} ${_proc_name} ${_cur_ret_code}
    # 終了ログ
    log.info_console "END   ${_group} ${_proc_name}"
  } &
  # PIDを保存
  log.trace_console "echo $! > $(bg_proc_control.local.get_pid_dir ${_group})/${_proc_name}"
  echo $! > $(bg_proc_control.local.get_pid_dir ${_group})/${_proc_name}

  log.remove_indent
  return ${EXITCODE_SUCCESS}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   終了処理
#
# 引数
#   ・1: グループ名
#
# オプション
#    なし
#
# リターンコード
#    0: 成功時
#    3: 警告発生時
#    6: エラー発生時
#
# 出力
#   なし
#
#--------------------------------------------------------------------------------------------------
function bg_proc_control.destroy() {
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  local _group="$1"

  # 引数チェック
  if [ "${_group}" = "" ]; then
    log.error_console "グループ名が指定されていません。呼出しを見なおして下さい。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # 実行可否チェック
  local _can_start=$(bg_proc_control.local.can_start_process ${_group})
  local _ret_code=$?
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    # エラー時はここで終了
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi
  # 最後のBGプロセスをwait
  log.debug_console "wait"
  wait

  # flush
  log.debug_console "bg_proc_control.local.flush ${_group}"
  bg_proc_control.local.flush ${_group}
  _ret_code=$?
  if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
    # 正常終了以外は、ここで終了
    log.remove_indent
    return ${_ret_code}
  fi

  # リターンコード判定
  local _has_error_in_summary=$(bg_proc_control.local.has_status_in_summary ${_group} ${EXITCODE_ERROR})
  local _has_warn_in_summary=$(bg_proc_control.local.has_status_in_summary ${_group} ${EXITCODE_WARN})
  if [ "${_has_error_in_summary}" = "true" ]; then
    _ret_code=${EXITCODE_ERROR}
  elif [ "${_has_warn_in_summary}" = "true" ]; then
    _ret_code=${EXITCODE_WARN}
  else
    _ret_code=${EXITCODE_SUCCESS}
  fi

  # 共通終了処理
  bg_proc_control.local.end_script ${_group}
  return ${_ret_code}
}



#--------------------------------------------------------------------------------------------------
# 概要
#   強制終了処理
#
# 引数
#   ・1: グループ名
#
# オプション
#    なし
#
# リターンコード
#    0: 成功時
#    3: 警告発生時
#    6: エラー発生時
#
# 出力
#   なし
#
#--------------------------------------------------------------------------------------------------
function bg_proc_control.kill() {
  log.debug_console "${FUNCNAME[0]} $@"
  log.add_indent

  local _group="$1"

  # 引数チェック
  if [ "${_group}" = "" ]; then
    log.error_console "グループ名が指定されていません。呼出しを見なおして下さい。"
    log.remove_indent
    return ${EXITCODE_ERROR}
  fi

  # pidファイルを全件ループ
  for _cur_file_path in `find $(bg_proc_control.local.get_pid_dir ${_group}) -maxdepth 1 -follow -type f | sort`; do
    local _cur_file_name=`basename ${_cur_file_path}`

    # pid
    local _cur_pid=$(cat ${_cur_file_path})

    # kill_tree
    log.debug_console "bg_proc_control.local.kill_tree_by_pid ${_cur_pid}"
    bg_proc_control.local.kill_tree_by_pid ${_cur_pid}

    # pidファイルをremove
    log.debug_console "rm -f $(bg_proc_control.local.get_pid_dir ${_group})/${_cur_file_name}"
    rm -f $(bg_proc_control.local.get_pid_dir ${_group})/${_cur_file_name}
  done

  # 共通終了処理
  bg_proc_control.local.end_script ${_group}

  return ${EXITCODE_ERROR}
}




#--------------------------------------------------------------------------------------------------
# サンプル実装
#--------------------------------------------------------------------------------------------------
function bg_proc_control.SAMPLE() {
  log.info_console "${FUNCNAME[0]}"
  local _process_option=""
#  local _process_option="-w"
#  local _process_option="-e"
  local _process_group="${FUNCNAME[0]}_$$"
  local _max_process=4

  local SUB_PROCESS_LIST=( "sub1" "sub2" "sub3" "sub4" "sub5" )

  # バックグラウンド実行 初期化処理
  bg_proc_control.init ${_process_option} ${_process_group} ${_max_process} "${STATUS_SUCCESS}" "${STATUS_WARN}" "${STATUS_ERROR}"

  # バックグラウンド実行 trap設定
  trap "                                                                                           \
  echo 'bg_proc_control:強制終了を検知したため処理を終了します。';                                 \
  bg_proc_control.kill ${_process_group};                                                          \
  exit ${EXITCODE_ERROR}" SIGHUP SIGINT SIGQUIT SIGTERM

  for _cur_proc_name in ${SUB_PROCESS_LIST[@]}; do
    # バックグラウンド実行 ※別プロセスとして実行されるので、依存スクリプトがある場合は、sourceして下さい。
    local _cur_command="                                                                          \
      DIR_BASE=${DIR_BASE};                                                                       \
      PATH_LOG=${PATH_LOG};                                                                       \
      . ${DIR_BIN}/setenv.sh;                                                                     \
      . ${DIR_BIN_LIB}/logging_utils.sh;                                                          \
      bg_proc_control.local.SAMPLE_SUB \"${_cur_proc_name}\"                                      \
    "
    bg_proc_control.start_process ${_process_group} ${_cur_proc_name} "${_cur_command}"
    local _ret_code=$?
    if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
      return ${_ret_code}
    fi

    # util外のコマンドを実行する場合など、各バックグラウンドプロセスの標準出力/エラーをPATH_LOGに追記するときは
    # start_process、destroy の標準出力を「tee -a ${PATH_LOG}」して下さい。
# サンプル
#    bg_proc_control.start_process ${_process_group} ${_cur_proc_name} ${_cur_command}             |
#    tee -a ${PATH_LOG}
#    local _ret_code=${PIPESTATUS[0]}
#    if [ ${_ret_code} -ne ${EXITCODE_SUCCESS} ]; then
#      return ${_ret_code}
#    fi

  done

  # バックグラウンド実行 終了処理
  bg_proc_control.destroy ${_process_group}
  _ret_code=$?
  return ${_ret_code}

# サンプル
#  bg_proc_control.destroy ${_process_group}                                                       |
#  tee -a ${PATH_LOG}
#  _ret_code=${PIPESTATUS[0]}
#  return ${_ret_code}
}

#--------------------------------------------------------------------------------------------------
# バックグランドで実行するfunction相当
#--------------------------------------------------------------------------------------------------
function bg_proc_control.local.SAMPLE_SUB() {
  echo "$1 is invoked!"
  sleep 3
  if [ "$1" = "\"sub3\"" ]; then
    echo "warn"
    return ${EXITCODE_WARN}
  elif [ "$1" = "\"sub4\"" ]; then
    echo "error"
    return ${EXITCODE_ERROR}
  else
    echo "success"
    return ${EXITCODE_SUCCESS}
  fi
}
