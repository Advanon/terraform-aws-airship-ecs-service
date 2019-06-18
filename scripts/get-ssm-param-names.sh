#!/usr/bin/env bash


function check_deps() {
  test -f $(which aws) || error_exit "aws not found, please install it"
  test -f $(which jq) || error_exit "jq not found, please install it"
}

function parse_input() {
  eval "$(jq -r '@sh "export REGION=\(.region) SSM_PATH=\(.ssm_path)"')"
  if [[ -z "${REGION}" ]]; then export REGION=none; fi
  if [[ -z "${SSM_PATH}" ]]; then export SSM_PATH=none; fi
}

function generate_output(){
  echo $SSM_PATH
  echo $REGION
  aws ssm get-parameters-by-path --path $SSM_PATH --region $REGION | \
  jq '.[][].Name' | \
  awk '{split($0,a,"/"); print a[4]}' | \
  sed -e 's/^/\"/' | \
  jq -s . | \
  jq '{ vars: .}'
}

check_deps
parse_input
generate_output