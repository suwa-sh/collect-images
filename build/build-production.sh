#!/bin/bash
# --------------------------------------------------------------------------------
# production build
# --------------------------------------------------------------------------------
cd $(cd $(dirname $0); cd ..; pwd;)

# --------------------------------------------------
# 設定
# --------------------------------------------------
readonly NAME_PROJ="$(basename $(pwd))"
readonly DIR_DEPLOY="./deploy"
readonly DIR_DOCS="./docs"
readonly PROFILE="production"

# package & site
#readonly CMD_BUILD="mvn clean package site:site -P ${PROFILE}"

# package only
#readonly CMD_BUILD="mvn clean package -P ${PROFILE}"

# package only & skip test
readonly CMD_BUILD="mvn clean package -Dmaven.test.skip=true -P ${PROFILE}"

# --------------------------------------------------
# build
# --------------------------------------------------
echo --------------------------------------------------
echo  配布ディレクトリ初期化
echo --------------------------------------------------
if [ -d ${DIR_DEPLOY} ]; then
    rm -fr ${DIR_DEPLOY}
fi
mkdir -p ${DIR_DEPLOY}


echo
echo --------------------------------------------------
echo  build
echo --------------------------------------------------
echo ${CMD_BUILD}
${CMD_BUILD}
ret_code=$?
if [ ${ret_code} -ne 0 ]; then
    echo "maven buildでエラーが発生しました。" >&2
    exit 1
fi

echo
echo --------------------------------------------------
echo 配布用ファイルの収集
echo --------------------------------------------------
mv target/${NAME_PROJ}*.tar.gz ${DIR_DEPLOY}

# 結果表示
echo "${DIR_DEPLOY}"
ls -l "${DIR_DEPLOY}"

exit 0
