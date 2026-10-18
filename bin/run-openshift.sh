#!/usr/bin/env bash
set -Eeuo pipefail

project_dir=$(mktemp -d /home/project/cicd-final.XXXXXX)
evidence_dir="$project_dir/evidence"
mkdir -p "$evidence_dir"
trap 'echo "Stopped at line $LINENO. Working directory: $project_dir" >&2' ERR

oc whoami
namespace=$(oc project -q)
if [ "$namespace" != "sn-labs-shayanobrohi" ]; then
  echo "Expected the Skills Network project sn-labs-shayanobrohi; current project is $namespace." >&2
  exit 1
fi
oc get storageclass skills-network-learner
oc get serviceaccount pipeline
for task in git-clone buildah openshift-client; do
  oc get clustertask "$task" >/dev/null
done

git clone https://github.com/shyrradev/ci-cd-final-project.git "$project_dir/repo"
cd "$project_dir/repo"
oc apply -f .tekton/tasks.yml
oc apply -f .tekton/pvc.yml
oc apply -f .tekton/pipeline.yml

# The claim uses WaitForFirstConsumer: start the run before waiting for binding.
image_url="image-registry.openshift-image-registry.svc:5000/$namespace/ci-cd-final-project:latest"
cat > "$project_dir/run.yml" <<RUN
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: oc-final-run-
  labels:
    project: ci-cd-final-project
spec:
  serviceAccountName: pipeline
  pipelineRef:
    name: oc-final
  timeout: 30m
  params:
    - name: image-url
      value: $image_url
  workspaces:
    - name: shared-workspace
      persistentVolumeClaim:
        claimName: cicd-source-pvc
RUN
run_name=$(oc create -f "$project_dir/run.yml" -o jsonpath='{.metadata.name}')
printf '%s\n' "$run_name" | tee "$evidence_dir/pipeline-run-name"
printf '\nPipelineRun started: %s\n' "$run_name"

tkn pipelinerun logs "$run_name" -f 2>&1 | tee "$evidence_dir/oc-pipeline-run-logs"
oc get pipelinerun "$run_name" -o json > "$evidence_dir/pipeline-run.json"
python3 - "$evidence_dir/pipeline-run.json" <<'PY'
import json, sys
run = json.load(open(sys.argv[1]))
condition = next((c for c in run.get('status', {}).get('conditions', []) if c['type'] == 'Succeeded'), {})
print(json.dumps(condition, indent=2))
if condition.get('status') != 'True':
    raise SystemExit('Pipeline has not succeeded. Send this output and the failed task logs back to chat.')
PY
oc get pvc cicd-source-pvc -o yaml | tee "$evidence_dir/oc-pipelines-console-pvc-details.yml"
oc describe pipeline oc-final > "$evidence_dir/oc-pipelines-oc-final"
oc describe pipelinerun "$run_name" > "$evidence_dir/oc-pipelines-oc-green"
oc rollout status deployment/ci-cd-final-project --timeout=120s
oc logs deployment/ci-cd-final-project --all-containers=true --tail=150 2>&1 | tee "$evidence_dir/oc-pipeline-application-logs"
route_host=$(oc get route ci-cd-final-project -o jsonpath='{.spec.host}')
printf '\nApplication URL: https://%s\n' "$route_host"
printf '\nEvidence saved in %s\n' "$evidence_dir"
console_url=$(oc whoami --show-console 2>/dev/null || true)
if [ -n "$console_url" ]; then
  printf '\nPVC screenshot page: %s/k8s/ns/%s/persistentvolumeclaims/cicd-source-pvc\n' "${console_url%/}" "$namespace"
  printf 'Pipeline screenshot page: %s/k8s/ns/%s/tekton.dev~v1beta1~Pipeline/oc-final\n' "${console_url%/}" "$namespace"
  printf 'Successful run screenshot page: %s/k8s/ns/%s/tekton.dev~v1beta1~PipelineRun/%s\n' "${console_url%/}" "$namespace" "$run_name"
fi
