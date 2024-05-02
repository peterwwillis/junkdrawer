#!/usr/bin/env bash
# aws-ecs-utils.sh - Wrapper for simpler operations on AWS ECS

set -e -o pipefail -u
[ -n "${DEBUG:-}" ] && set -x

logerr () { echo "$0: Error: $@" 1>&2 ; false ; }
_arrayget() { 
    # Usage:
    #    declare "list_$key=$val"
    #    _arrayget list "$key"
    local array=$1 index=$2
    local i="${array}_$index"
    printf '%s' "${!i}"
}
_usage () {
    echo "Usage: $0 COMMAND [ARGS ..]

Valid commands:
  get-log-events
  get-service-task-instances
  describe-log-groups
  describe-service-containers
  describe-service-container-instances
  describe-service-tasks
  describe-task
  describe-task-definition
  describe-task-definitions
  list-log-groups
  list-log-streams
  list-service-tasks
  list-service-task-definitions
  list-services
  list-clusters
" 1>&2
    exit 1
}

get_log_events () {
    if [ $# -lt 2 ] || [ "$1" = "-h" -o "$1" = "--help" ] ; then
        msg="Usage: $0 get-log-events GROUP_NAME STREAM_NAME [START_TIME [END_TIME]]
 Example:
        START=\$(( \$(date --date='TZ=\"America/New_York\" 24 hours ago' +%s%N) / 1000000 ))
        ./ecs-utils.sh list-log-groups | xargs -n1 -I__ /bin/sh -c \"./ecs-utils.sh list-log-streams __ | xargs -n1 -I{} ./ecs-utils.sh get-log-events __ {} \$START\""
        logerr "$msg"
    fi
    declare -a args
    local LOG_GROUP_NAME="$1" LOG_STREAM_NAME="$2"
    shift 2
    [ $# -gt 0 ] && args+=("--start-time" "$1") && shift
    [ $# -gt 0 ] && args+=("--end-time" "$1") && shift
    aws logs get-log-events --log-group-name "$LOG_GROUP_NAME" --log-stream-name "$LOG_STREAM_NAME" "${args[@]}"
}
get_service_task_instances () {
    if [ $# -lt 2 ] ; then logerr "Usage: $0 get-service-task-instances CLUSTER SERVICE" ; fi
    local cluster="$1"; shift
    local service="$1"; shift

    declare -a tasks_containers=( $(describe_service_containers "$cluster" "$service") )
    for i in "${tasks_containers[@]}" ; do
        IFS=, read -a taskarray <<< "$i"
        # containertask array: containerInstanceArn=taskArn
        declare "containertask_${taskarray[1]}=${taskarray[0]}"
    done

    declare -a container_instances=( $(aws ecs describe-container-instances --cluster "$cluster" --container-instances "${containers[@]}" \
        | jq -r '.[][] | (.containerInstanceArn | split("/")[1]) + "," + .ec2InstanceId' ) )
    for i in "${container_instances[@]}" ; do
        IFS=, read -a containerec2id <<< "$i"
        # containerinst array: containerInstanceArn=ec2InstanceId
        #declare "containerinst_${containerec2id[0]}=${containerec2id[1]}"

        task=$(_getarray containertask "${containerec2id[0]}")
        ec2instance=$(_getarray "${containerec2id[1]}")
        echo "task $task ec2InstanceId $ec2instance"
    done
}
describe_task_definition () {
    [ $# -lt 1 ] && logerr "Usage: $0 describe-task-definition TASK [..]"
    for t in "$@" ; do
        aws ecs describe-task-definition --task-definition "$@"
   done
}
describe_task_definitions () {
    [ $# -ne 0 ] && logerr "Usage: $0 describe-task-definitions"
    aws ecs list-task-definitions \
        | jq -r .taskDefinitionArns[] \
        | rev | cut -d : -f 2- | rev \
        | sort -u \
        | xargs -n1 aws ecs describe-task-definition --task-definition
}
describe_task () {
    if [ $# -lt 2 ] ; then logerr "Usage: $0 describe-task CLUSTER TASK [..]" ; fi
    local cluster="$1"; shift
    aws ecs describe-tasks --cluster "$cluster" --tasks "$@"
}
describe_service_tasks () {
    if [ $# -lt 2 ] ; then logerr "Usage: $0 describe-service-tasks CLUSTER SERVICE" ; fi
    local cluster="$1"; shift
    local service="$1"; shift
    aws ecs describe-tasks --cluster "$cluster" --tasks $( list_service_tasks "$cluster" "$service" )
}
describe_service_containers () {
    if [ $# -lt 2 ] ; then logerr "Usage: $0 describe-service-containers CLUSTER SERVICE" ; fi
    local cluster="$1"; shift
    local service="$1"; shift
    describe_service_tasks "$cluster" "$service" \
        | jq -r '.tasks[] | .taskArn + "," + .containerInstanceArn + "," + .containers[].containerArn'
}
describe_service_container_instances () {
    if [ $# -lt 2 ] ; then logerr "Usage: $0 describe-service-container-instances CLUSTER SERVICE" ; fi
    local cluster="$1"; shift
    local service="$1"; shift
    aws ecs describe-container-instances \
        --cluster "$cluster" \
        --container-instances $(describe_service_containers "$cluster" "$service" | cut -d , -f 2)
}
list_log_groups () {
    aws logs describe-log-groups | jq -r .logGroups[].logGroupName
}
list_log_streams () {
    if [ $# -lt 1 ] || [ "$1" = "-h" -o "$1" = "--help" ] ; then logerr "Usage: $0 list-log-streams LOGGROUP_NAME" ; fi
    #aws logs describe-log-streams --log-group-name "$1" --log-stream-name-prefix "$2" | jq -r .logStreams[].logStreamName
    aws logs describe-log-streams --log-group-name "$1" | jq -r .logStreams[].logStreamName
}
list_service_task_definitions () {
    [ $# -lt 2 ] && logerr "Usage: $0 list-service-task-definitions CLUSTER SERVICE"
    aws ecs describe-services --cluster "$1" --services "$2" \
        | jq -r .services[].taskDefinition
}
list_service_tasks () {
    if [ $# -lt 2 ] ; then logerr "Usage: $0 list-service-tasks CLUSTER SERVICE" ; fi
    local cluster="$1"; shift
    local service="$1"; shift
    aws ecs list-tasks --cluster "$cluster" --service-name "$service" | jq -r .[][] | sort
}
list_services () {
    if [ $# -lt 1 ] ; then logerr "Usage: $0 list-services CLUSTER" ; fi
    local cluster="$1"; shift
    aws ecs list-services --cluster "$cluster" | jq -r .[][] | cut -d / -f 2- | sed -e 's/\// /' | sort
}
list_clusters () {
    if [ "${1:-}" = "-h" -o "${1:-}" = "--help" ] ; then logerr "Usage: $0 list-clusters" ; fi
    aws ecs list-clusters | jq -r .[][] | cut -d / -f 2- | sort
}

[ $# -lt 1 ] && _usage

cmd="$1"; shift
case $cmd in
    get-log-events) get_log_events "$@" ;;
    get-service-task-instances) get_service_task_instances "$@" ;;
    describe-service-containers) describe_service_containers "$@" ;;
    describe-service-container-instances) describe_service_container_instances "$@" ;;
    describe-service-tasks) describe_service_tasks "$@" ;;
    describe-task) describe_task "$@" ;;
    describe-task-definition) describe_task_definition "$@" ;;
    describe-task-definitions) describe_task_definitions "$@" ;;
    list-log-groups) list_log_groups "$@" ;;
    list-log-streams) list_log_streams "$@" ;;
    list-service-tasks) list_service_tasks "$@" ;;
    list-service-task-definitions) list_service_task_definitions "$@" ;;
    list-services) list_services "$@" ;;
    list-clusters) list_clusters "$@" ;;
    *)
        logerr "Could not identify command '$cmd'"
        _usage ;;
esac
exit $?
