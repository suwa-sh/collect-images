#!/bin/bash
#set -eux
#==================================================================================================
# unit test
#
# 引数
#   1: テストスクリプトのフルパス
#
# 前提
#   ・テストスクリプトで、before_script, before, after, after_script 関数が定義されていること
#   ・テストスクリプトで、環境変数：LIST_TEST_FUNC に実行するテストケース関数名が配列として定義されていること
#
# コマンドサンプル
#   cd /path/to/bin
#   ./unit_test.sh ./lib/xxx_utils.sh
#
# テストスクリプトでできること
#   ・PATH_TEST_SCRIPT で、自ファイルパスを取得できます。
#   ・setenv_ut.sh の定義内容を参照できます。
#   ・logging_utils.sh の関数を利用できます。
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 環境設定
#--------------------------------------------------------------------------------------------------
# カレントディレクトリの移動
cd $(cd $(dirname $0); pwd)

# テストモード：UT
export readonly TEST_MODE="UT"

# 共通設定
export readonly DIR_BASE=$(cd ../../../main/scripts; pwd)
. ./setenv_ut.sh

# ログファイルパス
readonly PATH_LOG=${DIR_LOG}/`basename $1 .sh`.log
# ログ出力ユーティリティ
. ${DIR_BIN_LIB}/logging_utils.sh

# テストスクリプト
readonly PATH_TEST_SCRIPT=$1
if [ ! -f ${PATH_TEST_SCRIPT} ]; then
    echo "テストスクリプト：${PATH_TEST_SCRIPT} は存在しません。" >&2
    exit ${EXITCODE_ERROR}
fi
. $1


#--------------------------------------------------------------------------------------------------
# 主処理
#--------------------------------------------------------------------------------------------------
log.info_teelog "`basename ${PATH_TEST_SCRIPT} .sh` - START"

# スクリプト単位の前処理
log.info_teelog "-- before_script - START"
before_script
return_code=$?
if [ ${return_code} -eq ${EXITCODE_SUCCESS} ]; then
  log.info_teelog "-- before_script - END"
else
  log.error_teelog "-- before_script - ${EXITMSG_ERROR}"
  log.error_teelog "`basename ${PATH_TEST_SCRIPT} .sh` - ${EXITMSG_ERROR}"
fi

# テスト実行
return_code=${EXITCODE_SUCCESS}
for cur_func in ${LIST_TEST_FUNC[@]}; do
  log.info_teelog "-- `basename ${PATH_TEST_SCRIPT} .sh`.${cur_func} - START"

  # テストケース単位の前処理
  log.info_teelog "---- before - START"
  before
  log.info_teelog "---- before - END"

  # 実行
  ${cur_func}
  cur_return_code=$?

  # テストケース単位の後処理
  log.info_teelog "---- after - START"
  after
  log.info_teelog "---- after - END"

  # 実行結果を判断
  if [ ${cur_return_code} -eq ${EXITCODE_SUCCESS} ]; then
    log.info_teelog "-- `basename ${PATH_TEST_SCRIPT} .sh`.${cur_func} - ${EXITMSG_SUCCESS}"
  else
    return_code=${cur_return_code}
    log.error_teelog "-- `basename ${PATH_TEST_SCRIPT} .sh`.${cur_func} - ${EXITMSG_ERROR}"
  fi
done

# スクリプト単位の後処理
log.info_teelog "-- after_script - START"
after_script
log.info_teelog "-- after_script - END"

# 事後処理
if [ ${return_code} -eq ${EXITCODE_SUCCESS} ]; then
  log.info_teelog "`basename ${PATH_TEST_SCRIPT} .sh` - ${EXITMSG_SUCCESS}"
else
  log.error_teelog "`basename ${PATH_TEST_SCRIPT} .sh` - ${EXITMSG_ERROR}"
fi

exit ${return_code}
