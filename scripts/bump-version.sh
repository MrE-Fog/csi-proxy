#!/bin/bash

# bump-version.sh
# Bumps an API version from an old version to a new one
# Usage:
#
#   API_GROUP=disk OLD_API_VERSION=v1beta3 NEW_API_VERSION=v1 bump-version.sh
#

set -o nounset
set -ex

: "${API_GROUP?API_GROUP is not set}"
: "${OLD_API_VERSION:?OLD_API_VERSION is not set, it needs the format vX}"
: "${NEW_API_VERSION:?NEW_API_VERSION is not set, it needs the format vX}"

function validate_args {
  if ! [[ $OLD_API_VERSION == v* ]]; then
    echo "OLD_API_VERSION=${OLD_API_VERSION} is invalid, it should have the format v*"
    exit 1
  fi
  if ! [[ -d client/api/$API_GROUP/$OLD_API_VERSION ]]; then
    echo "The directory client/api/$API_GROUP/$OLD_API_VERSION, does not exist"
    exit 1
  fi

  if ! [[ $NEW_API_VERSION == v* ]]; then
    echo "NEW_API_VERSION=${NEW_API_VERSION} is invalid, it should have the format v*"
    exit 1
  fi
}

function generate_client_files {
  # the path to regenerate
  target=$1

  # delete the vendor folder, otherwise generate-protobuf is going to create a wrong path in the api.pb.go file
  rm -rf vendor
  rm client/api/$target/api.pb.go || true
  rm client/groups/$target/client_generated.go || true

  # generate api.pb.go
  # it's going to fail but it's expected :(
  make generate-protobuf || true
  # generate client_generated.go
  make generate-csi-proxy-api-gen

  # restore files from other API groups (side effect of generate-protobuf)
  other_leaf_client_files=$(find client/api/ -links 2 -type d -exec echo {} \; | grep -v "$target\$")
  for leaf in $other_leaf_client_files; do
    git restore $leaf
  done
}

function bump_client {
  cp -R client/api/$API_GROUP/$OLD_API_VERSION/. client/api/$API_GROUP/$NEW_API_VERSION
  cp -R client/groups/$API_GROUP/$OLD_API_VERSION/. client/groups/$API_GROUP/$NEW_API_VERSION

  # fix imports in new file
  sed -i s/$OLD_API_VERSION/$NEW_API_VERSION/g client/api/$API_GROUP/$NEW_API_VERSION/api.proto

  generate_client_files $API_GROUP/$NEW_API_VERSION
}

function bump_server {
  cp -R pkg/server/$API_GROUP/impl/$OLD_API_VERSION/. pkg/server/$API_GROUP/impl/$NEW_API_VERSION

  # delete auto generated files
  find pkg/server/$API_GROUP/impl/$NEW_API_VERSION -name "*_generated.go" | xargs rm

  # fix imports in new file
  sed -i s/$OLD_API_VERSION/$NEW_API_VERSION/g pkg/server/$API_GROUP/impl/$NEW_API_VERSION/conversion.go

  # generate _generated.go files
  make generate-csi-proxy-api-gen

  # it looks like at this point client/groups/<version>/client_generated.go is generated
  # sync it to the vendor folder
  env GO111MODULE=on go mod vendor
}

function bump_integration {
  cp -f integrationtests/${API_GROUP}_${OLD_API_VERSION}_test.go integrationtests/${API_GROUP}_${NEW_API_VERSION}_test.go
  sed -i s/$OLD_API_VERSION/$NEW_API_VERSION/g integrationtests/${API_GROUP}_${NEW_API_VERSION}_test.go
}

function validate_generated_files {
  declare -a expected_files=(
    client/api/$API_GROUP/$NEW_API_VERSION/api.pb.go
    client/api/$API_GROUP/$NEW_API_VERSION/api.proto
    client/groups/$API_GROUP/$NEW_API_VERSION/client_generated.go
    pkg/server/$API_GROUP/impl/$NEW_API_VERSION/conversion.go
    pkg/server/$API_GROUP/impl/$NEW_API_VERSION/conversion_generated.go
    pkg/server/$API_GROUP/impl/$NEW_API_VERSION/server_generated.go
    integrationtests/${API_GROUP}_${NEW_API_VERSION}_test.go
  )
  for file in ${expected_files[@]}; do
    if ! [[ -f $file ]]; then
      echo "expected file $file was not created"
      exit 1
    fi
  done
}

function next_steps {
  cat <<EOF
Success! Next steps:

- verify that the $NEW_API_VERSION files have the right contents
- add the integration test to integrationtests/${API_GROUP}_test.go
- add the vendor/ folder to git with force
- push to the remote

EOF
}

function main {
  printenv | sort | uniq
  protoc --version

  validate_args
  bump_client
  bump_server
  bump_integration
  validate_generated_files
  next_steps
}

main
