#!/usr/bin/env bash
if [[ -z $BRANCH_NAME ]]; then
  echo "Please set BRANCH_NAME variable"
  exit 1
fi

if [[ -z $ORGANIZATION ]]; then
  echo "Please set ORGANIZATION variable"
  exit 1
fi

set -ex

while true; do
  runs=$(gh run list -b $BRANCH_NAME -L 50 --json status,conclusion,name,url,startedAt -R ${ORGANIZATION}/ockam)
  echo "$runs"
  if [[ $(jq -r '.|type' <<<$runs) != 'array' ]]; then
    echo "Invalid return type... Exiting now."
    exit 1
  fi

  run_length=$(jq '.|length' <<<$runs)

  if [[ $run_length == 0 ]]; then
    echo "No run detected, retrying...."
    sleep 10
    continue
  fi

  jq . <<<$runs >file.json
  new_map="{}"

  # Compare time stamp and get the latest run
  for ((c = 0; c < $run_length; c++)); do
    workflow_name=$(jq -r ".[$c].name" <<<$runs)
    run_timestamp=$(jq -r ".[$c].startedAt" <<<$runs)
    conclusion=$(jq -r ".[$c].conclusion" <<<$runs)
    status=$(jq -r ".[$c].status" <<<$runs)

    # echo "1 $workflow_name"
    if [[ $(jq "has(\"$workflow_name\")" <<<$new_map) == 'false' ]]; then
      new_map=$(jq ".\"${workflow_name}\" += {\"startedAt\":\"$run_timestamp\"}" <<<$new_map)
      new_map=$(jq ".\"${workflow_name}\" += {\"status\":\"$status\"}" <<<$new_map)
      new_map=$(jq ".\"${workflow_name}\" += {\"conclusion\":\"$conclusion\"}" <<<$new_map)

      continue
    fi

    mapped_workflow=$(jq -r ".\"${workflow_name}\"" <<<$new_map)
    mapped_timestamp=$(jq -r ".\"${workflow_name}\".startedAt" <<<$new_map)

    # If workflow name exists, then compare timestamps
    if [[ $run_timestamp > $mapped_timestamp ]]; then
      url=$(jq -r ".[$c].url" <<<$runs)
      echo "Changing data of run to $run_timestamp $url"

      new_map=$(jq ".\"${workflow_name}\" += {\"startedAt\":\"$run_timestamp\"}" <<<$new_map)
      new_map=$(jq ".\"${workflow_name}\" += {\"status\":\"$status\"}" <<<$new_map)
      new_map=$(jq ".\"${workflow_name}\" += {\"conclusion\":\"$conclusion\"}" <<<$new_map)
    fi
  done

  jq '.' <<<$new_map

  # Exit if any of the latest run failed or was cancelled
  if [[ $new_map == *"\"conclusion\": \"failure\""* || $new_map == *"\"conclusion\": \"cancelled\""* ]]; then
    echo "A workflow failed"
    exit 1
  fi

  echo "No workflow failed. Checking if all succeeded"

  # Check individual workflow (Omitting the master workflow) ensuring they all succeeded
  keys=$(jq 'keys' <<<$new_map)

  all_workflow_succeded='true'
  for ((c = 0; c < $(jq '.|length' <<<$keys); c++)); do
    key=$(jq -r ".[$c]" <<<$keys)

    if [[ $key == "PR CI Watcher" ]]; then
      echo "\"PR CI Watcher\" is the parent workflow and the status will always be inconclusive, skipping now"
      continue
    fi

    if [[ $(jq -r ".\"${key}\".conclusion" <<<$new_map) == "" ]]; then
      echo "\"$key\" workflow inconclusive, retrying....."
      all_workflow_succeded='false'
      sleep 10
      break
    fi
  done

  if [[ $all_workflow_succeded == 'true' ]]; then
    echo "All workflows succeeded ✅✅✅"
    break
  fi

  cat file.json
done
