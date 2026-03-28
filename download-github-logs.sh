#!/usr/bin/env bash
## Download all the GitHub Actions Logs

## Set the GitHub Token: export GITHUB_TOKEN=...
## Any Token with Read-Access to NuttX Repo will do:
## "public_repo" (Access public repositories)
. $HOME/github-token.sh

set -e  #  Exit when any command fails
set -x  #  Echo commands

linux_step=10 ## TODO: Step may change for Linux Builds
msys2_step=9  ## TODO: Step may change for msys2 Builds

## TODO
user=apache
repo=nuttx
run_id=23653869993
nuttx_hash=master
apps_hash=master

## Generate the list of deconfigs
defconfig=/tmp/defconfig-github.txt
find $HOME/riscv/nuttx -name defconfig >$defconfig

function ingest_log {
  ## Fetch the Jobs for the Run ID. Get the Job ID for the Job Name.
  local os=$1 ## "Linux" or "msys2"
  local step=$2 ## "10" or "9"
  local group=$3 ## "arm-01"
  local job_name="$os ($group)"
  local job_id=$(
    curl -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      https://api.github.com/repos/$user/$repo/actions/runs/$run_id/jobs?per_page=100 \
      | jq ".jobs | map(select(.name == \"$job_name\")) | .[].id"
      # | jq ".jobs | map(select(.id == $job_id)) | .[].name"
      # | jq ".jobs[].id,.jobs[].name"
  )
  set +x ; echo job_id=$job_id ; set -x
  if [[ "$job_id" == "" ]]; then
    set +x ; echo "**** Job ID missing for Run ID $run_id, Job Name $job_name" ; set -x
    sleep 10
    return
  fi
  sleep 1

  ## log_file looks like /tmp/ingest-nuttx-builds/33_Linux (arm-01).txt
  ## Or /tmp/ingest-nuttx-builds/6_msys2 (msys2).txt
  ## filename looks like ci-arm-01.log
  ## pathname looks like /tmp/ingest-nuttx-builds/ci-arm-01.log
  ## url looks like https://github.com/NuttX/nuttx/actions/runs/11603561928/job/32310817851#step:7:83
  ## Update: "step:7" has become "step:10"
  local log_file=$(ls $tmp_path/*$os\ \($group\)*.txt)
  local filename="ci-$group.log"
  local pathname="$tmp_path/$filename"

  ## For Testing
  local linenum=83
  local url="https://github.com/$user/$repo/actions/runs/$run_id/job/$job_id#step:$step:$linenum"

  ## Remove the Timestamp Column
  cat "$log_file" \
    | colrm 1 29 \
    > $pathname
  head -n 100 $pathname
  set +x ; echo url=$url ; set -x

  ## Ingest the Log File
  cargo run -- \
    --user $user \
    --repo $repo \
    --defconfig $defconfig \
    --file $pathname \
    --nuttx-hash $nuttx_hash \
    --apps-hash $apps_hash \
    --group $group \
    --run-id $run_id \
    --job-id $job_id \
    --step $step
}

## Download the Run Logs
## https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28#download-workflow-run-logs
curl -L \
  --output /tmp/run-log.zip \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/$user/$repo/actions/runs/$run_id/logs

## Unzip the Log Files
tmp_path=/tmp/download-github-logs
rm -rf $tmp_path
mkdir $tmp_path
pushd $tmp_path
set +e  #  Ignore unzip warnings: "warning:  stripped absolute path spec from /system.txt"
unzip /tmp/run-log.zip
set -e  #  Exit when any command fails
popd

## For All Target Groups
## TODO: Handle macOS when the warnings have been cleaned up
for group in \
  arm-01 arm-02 arm-03 arm-04 \
  arm-05 arm-06 arm-07 arm-08 \
  arm-09 arm-10 arm-11 arm-12 \
  arm-13 arm-14 \
  arm64-01 \
  other \
  risc-v-01 risc-v-02 risc-v-03 risc-v-04 \
  risc-v-05 risc-v-06 \
  sim-01 sim-02 sim-03 \
  x86_64-01 \
  xtensa-01 xtensa-02 \
  msys2
do
  ## Ingest the Log File
  if [[ "$group" == "msys2" ]]; then
    ingest_log "msys2" $msys2_step $group
  else
    ingest_log "Linux" $linux_step $group
  fi
done

exit

## Dump the GitHub PRs into pr/$pr_num.json
function dump_pr_list {
  local repo=$1
  local date=$2
  local pr_list=$(
    gh pr list \
      --repo $repo \
      --limit 1000 \
      --state all \
      --search "created:$date" \
      --json id,url,updatedAt,title,additions,assignees,author,autoMergeRequest,baseRefName,changedFiles,closed,closedAt,createdAt,deletions,files,headRefName,headRefOid,headRepository,headRepositoryOwner,isDraft,labels,mergeCommit,mergeStateStatus,mergeable,mergedAt,mergedBy,milestone,number,state \
      | jq
  )

  local len=$( echo "$pr_list" | jq '. | length' )
  echo "Got $len PRs"
  for (( i=0; i<$len; i++ )) ; do
    local pr=$(echo "$pr_list" | jq ".[$i]")
    local pr_num=$(echo "$pr" | jq .number)
    local file=pr/$pr_num.json
    echo "$pr" | jq >$file
    echo "PR $i: $file"
  done
}

## Result
# [
#   {
#     "additions": 1320,
#     "assignees": [],
#     "author": {
#       "id": "MDQ6VXNlcjY1MzIwMjg=",
#       "is_bot": false,
#       "login": "jasonbu",
#       "name": ""
#     },
#     "autoMergeRequest": null,
#     "baseRefName": "master",
#     "changedFiles": 20,
#     "closed": false,
#     "closedAt": null,
#     "createdAt": "2026-03-06T10:01:56Z",
#     "deletions": 24,
#     "files": [
#       {
#         "path": "arch/arm/include/imx9/imx95_irq.h",
#         "additions": 3,
#         "deletions": 3
#       },
#       {
#         "path": "arch/arm64/include/imx9/imx95_irq.h",
#         "additions": 3,
#         "deletions": 3
#       },
#       {
#         "path": "arch/arm64/src/common/CMakeLists.txt",
#         "additions": 1,
#         "deletions": 0
#       },
#       {
#         "path": "arch/arm64/src/imx9/CMakeLists.txt",
#         "additions": 3,
#         "deletions": 1
#       },
#       {
#         "path": "arch/arm64/src/imx9/Kconfig",
#         "additions": 3,
#         "deletions": 0
#       },
#       {
#         "path": "arch/arm64/src/imx9/hardware/imx95/imx95_ccm.h",
#         "additions": 753,
#         "deletions": 0
#       },
#       {
#         "path": "arch/arm64/src/imx9/hardware/imx95/imx95_gpio.h",
#         "additions": 61,
#         "deletions": 0
#       },
#       {
#         "path": "arch/arm64/src/imx9/hardware/imx95/imx95_pinmux.h",
#         "additions": 50,
#         "deletions": 0
#       },
#       {
#         "path": "arch/arm64/src/imx9/hardware/imx95/imx95_pll.h",
#         "additions": 197,
#         "deletions": 0
#       },
#       {
#         "path": "arch/arm64/src/imx9/hardware/imx9_ccm.h",
#         "additions": 1,
#         "deletions": 0
#       },
#       {
#         "path": "arch/arm64/src/imx9/hardware/imx9_gpio.h",
#         "additions": 1,
#         "deletions": 0
#       },
#       {
#         "path": "arch/arm64/src/imx9/hardware/imx9_pinmux.h",
#         "additions": 1,
#         "deletions": 0
#       },
#       {
#         "path": "arch/arm64/src/imx9/imx9_gpiobase.c",
#         "additions": 1,
#         "deletions": 2
#       },
#       {
#         "path": "arch/arm64/src/imx9/imx9_usdhc.c",
#         "additions": 63,
#         "deletions": 6
#       },
#       {
#         "path": "boards/arm64/imx9/imx95-a55-evk/include/board.h",
#         "additions": 24,
#         "deletions": 3
#       },
#       {
#         "path": "boards/arm64/imx9/imx95-a55-evk/src/CMakeLists.txt",
#         "additions": 4,
#         "deletions": 0
#       },
#       {
#         "path": "boards/arm64/imx9/imx95-a55-evk/src/Makefile",
#         "additions": 4,
#         "deletions": 0
#       },
#       {
#         "path": "boards/arm64/imx9/imx95-a55-evk/src/imx9_bringup.c",
#         "additions": 48,
#         "deletions": 0
#       },
#       {
#         "path": "boards/arm64/imx9/imx95-a55-evk/src/imx9_usdhc.c",
#         "additions": 85,
#         "deletions": 0
#       },
#       {
#         "path": "drivers/mmcsd/mmcsd_sdio.c",
#         "additions": 14,
#         "deletions": 6
#       }
#     ],
#     "headRefName": "imx95_emmc8bit",
#     "headRefOid": "95d44356ea31a03c76208790987d05da674abe1c",
#     "headRepository": {
#       "id": "R_kgDOLHs-vw",
#       "name": "nuttx"
#     },
#     "headRepositoryOwner": {
#       "id": "MDQ6VXNlcjY1MzIwMjg=",
#       "login": "jasonbu"
#     },
#     "id": "PR_kwDODZiUac7IdLQM",
#     "isDraft": false,
#     "labels": [
#       {
#         "id": "LA_kwDODZiUac8AAAABsqOt8A",
#         "name": "Arch: arm",
#         "description": "Issues related to ARM (32-bit) architecture",
#         "color": "DC5544"
#       },
#       {
#         "id": "LA_kwDODZiUac8AAAABsqO1YA",
#         "name": "Arch: arm64",
#         "description": "Issues related to ARM64 (64-bit) architecture",
#         "color": "DC5544"
#       },
#       {
#         "id": "LA_kwDODZiUac8AAAABsqR34A",
#         "name": "Area: Drivers",
#         "description": "Drivers issues",
#         "color": "0075ca"
#       },
#       {
#         "id": "LA_kwDODZiUac8AAAABvj_dNA",
#         "name": "Size: XL",
#         "description": "The size of the change in this PR is very large. Consider breaking down the PR into smaller pieces.",
#         "color": "FEF2C0"
#       },
#       {
#         "id": "LA_kwDODZiUac8AAAABw8LvAA",
#         "name": "Board: arm64",
#         "description": "",
#         "color": "F9D0C4"
#       }
#     ],
#     "mergeCommit": null,
#     "mergeStateStatus": "CLEAN",
#     "mergeable": "MERGEABLE",
#     "mergedAt": null,
#     "mergedBy": null,
#     "milestone": null,
#     "number": 18501,
#     "state": "OPEN",
#     "title": "arch/arm64/imx95-a55: add GPIO and eMMC (USDHC) support with partition table parsing",
#     "updatedAt": "2026-03-09T08:57:41Z",
#     "url": "https://github.com/apache/nuttx/pull/18501"
#   }
# ]

## Dump the GitHub Jobs into job/$run_id.json
function dump_job_list {
  local repo=$1
  local date=$2
  local job_list=$(
    gh run list \
      --repo $repo \
      --limit 1000 \
      --created $date \
      --json conclusion,createdAt,databaseId,displayTitle,event,headBranch,headSha,name,number,startedAt,status,updatedAt,url,workflowDatabaseId,workflowName
  )

  local len=$( echo "$job_list" | jq '. | length' )
  echo "Got $len Jobs"
  for (( i=0; i<$len; i++ )) ; do
    local job=$(echo "$job_list" | jq ".[$i]")
    local run_id=$(echo "$job" | jq .databaseId)
    local file=job/$run_id.json
    echo "$job" | jq >$file
    echo "Job $i: $file"
    dump_duration $repo $run_id
  done
}

## Result:
# "conclusion": "success",
# "createdAt": "2026-03-09T04:01:49Z",
# "databaseId": 22837803838,
# "displayTitle": "arch/arm64/imx95-a55: add GPIO and eMMC (USDHC) support with partition table parsing",
# "event": "pull_request",
# "headBranch": "imx95_emmc8bit",
# "headSha": "95d44356ea31a03c76208790987d05da674abe1c",
# "name": "Build",
# "number": 53875,
# "startedAt": "2026-03-09T04:01:49Z",
# "status": "completed",
# "updatedAt": "2026-03-09T07:34:48Z",
# "url": "https://github.com/apache/nuttx/actions/runs/22837803838",
# "workflowDatabaseId": 908549,
# "workflowName": "Build"

## Dump the GitHub Job Duration into duration/$run_id.txt
function dump_duration {
  local repo=$1
  local run_id=$2
  local duration=$(
    curl -L --silent \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      https://api.github.com/repos/$repo/actions/runs/$run_id/timing \
      | jq '.run_duration_ms'
  )
  local file=duration/$run_id.txt
  echo "$duration" >$file
  echo "Duration for $run_id: $file"
  sleep 1
}

## Result:
# 12779000

## Dump the PRs, Jobs and Durations for the NuttX Repo and NuttX Apps Repo
function dump_repo {
  ## Backtrack for 365 days
  for days in {0..365}; do
    echo "days=$days"
    if [ "`uname`" == "Darwin" ]; then
      date=$(date -v-${days}d +"%Y-%m-%d")
    else
      current_date_seconds=$(date +%s)
      seconds_to_subtract=$((days * 86400)) # 86400 seconds in a day
      past_date_seconds=$((current_date_seconds - seconds_to_subtract))
      date=$(date -d "@$past_date_seconds" +"%Y-%m-%d")
    fi
    echo "date=$date"

    ## Dump the PRs, Jobs and Durations
    dump_pr_list  apache/nuttx $date
    dump_job_list apache/nuttx $date
    dump_pr_list  apache/nuttx-apps $date
    dump_job_list apache/nuttx-apps $date
    sleep 1
  done
}

dump_repo

## For Testing
# date=$(date -u +'%Y-%m-%d')
# run_id=22837803838 ## From databaseId
# repo=apache/nuttx
