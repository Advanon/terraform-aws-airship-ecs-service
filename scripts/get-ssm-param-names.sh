#!/usr/bin/env bash


function check_deps() {
  test -f $(which aws) || error_exit "aws not found, please install it"
  test -f $(which jq) || error_exit "jq not found in path, please install it"
}

function parse_input() {
  eval "$(jq -r '@sh "REGION=\(.region) SSM_PATH=\(.ssm_path)"')"
}

check_deps
aws ssm get-parameters-by-path --path $SSM_PATH --region $REGION | jq '.[][].Name' | jq -s .