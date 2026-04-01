#!/usr/bin/env bash
## Download and Parse all the GitHub Actions Logs

## For Testing: NuttX
## user=apache
## repo=nuttx
## run_id=23653869993  ## sim-02:sim:login: >>>> WARNING: YOU ARE USING DEFAULT PASSWORD KEYS (CONFIG_FSUTILS_PASSWD_KEY1-4)!!! PLEASE CHANGE IT!!! <<<< \n 17d16 \n < CONFIG_BOARD_ETC_ROMFS_PASSWD_PASSWORD=\"Administrator\" \n Saving the new configuration file
## run_id=23669957941  ## Successful
## run_id=23679432579  ## Test Retry
## ./download-github-logs.sh apache nuttx 23679432579

## For Testing: NuttX Apps
## user=apache
## repo=nuttx-apps
## run_id=23636620855

## Set the GitHub Token: export GITHUB_TOKEN=...
## Any Token with Read-Access to NuttX Repo will do:
## "public_repo" (Access public repositories)
. $HOME/github-token.sh

set -e  #  Exit when any command fails
set -x  #  Echo commands

linux_step=10 ## TODO: Step may change for Linux Builds
msys2_step=9  ## TODO: Step may change for msys2 Builds
nuttx_hash=master
apps_hash=master

## First Parameter is Repo Owner
user=$1
if [[ "$user" == "" ]]; then
  echo "ERROR: Repo Owner Parameter is missing (e.g. apache)"
  exit 1
fi

## Second Parameter is Repo Name
repo=$2
if [[ "$repo" == "" ]]; then
  echo "ERROR: Repo Name Parameter is missing (e.g. nuttx or nuttx-apps)"
  exit 1
fi

## Third Parameter is Run ID
run_id=$3
if [[ "$run_id" == "" ]]; then
  echo "ERROR: Run ID Parameter is missing (e.g. 23669957941)"
  exit 1
fi

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
    cat $jobs_path \
    | jq ".jobs | map(select(.name == \"$job_name\")) | .[].id"
  )
  set +x ; echo job_id=$job_id ; set -x
  if [[ "$job_id" == "" ]]; then
    set +x ; echo "**** Job ID missing for Run ID $run_id, Job Name $job_name" ; set -x
    return
  fi

  ## log_file looks like /tmp/ingest-nuttx-builds/33_Linux (arm-01).txt
  ## Or /tmp/ingest-nuttx-builds/6_msys2 (msys2).txt
  ## filename looks like ci-arm-01.log
  ## pathname looks like /tmp/ingest-nuttx-builds/ci-arm-01.log
  ## url looks like https://github.com/NuttX/nuttx/actions/runs/11603561928/job/32310817851#step:7:83
  ## Update: "step:7" has become "step:10"
  local log_file=$(ls $tmp_path/*$os\ \($group\)*.txt)
  local filename="ci-$group.log"
  local pathname="$tmp_path/$filename"

  ## If pathname doesn't exist, quit
  if [[ ! -f "$log_file" ]]; then
    set +x ; echo "**** Log File missing for Run ID $run_id, Job Name $job_name, Expected Path $log_file" ; set -x
    return
  fi

  ## Remove the Timestamp Column
  cat "$log_file" \
    | colrm 1 29 \
    > $pathname
  head -n 100 $pathname

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

## Fetch the Jobs for the Run ID
tmp_path=/tmp/download-github-logs
rm -rf $tmp_path
mkdir $tmp_path
jobs_path=$tmp_path/jobs.json
set +x  ## Don't Echo commands
curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/$user/$repo/actions/runs/$run_id/jobs?per_page=100 \
  > $jobs_path
set -x  ## Echo commands

## Download the Run Logs
## https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28#download-workflow-run-logs
set +x  ## Don't Echo commands
curl -L \
  --output /tmp/run-log.zip \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/$user/$repo/actions/runs/$run_id/logs
set -x  ## Echo commands

## Unzip the Log Files
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
  xtensa-01 xtensa-02 xtensa-03 \
  msys2
do
  ## Ingest the Log File
  if [[ "$group" == "msys2" ]]; then
    ingest_log "msys2" $msys2_step $group
  else
    ingest_log "Linux" $linux_step $group
  fi
done
