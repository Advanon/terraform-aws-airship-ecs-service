#!/usr/bin/env bash
set -v


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
  aws ssm get-parameters-by-path --path $SSM_PATH --region $REGION | jq '.[][].Name' | rev | cut -d '/' -f1 | rev | sed -e 's/\"/,/' | tr -d '\n' | sed -e 's/^/\"/' | sed -e 's/.$/\"/' | jq '{ vars: . }'

}

check_deps
parse_input
generate_output
