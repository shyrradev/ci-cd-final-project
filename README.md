# CI/CD Final Project

This project builds a continuous integration and delivery pipeline for IBM's
Python Flask **Hit Counter Service**. GitHub Actions checks every push and pull
request. Tekton and OpenShift Pipelines clean the workspace, clone the source,
lint and test the application, build its container image, and deploy it.

## Project files

| File | Purpose |
| --- | --- |
| `.github/workflows/workflow.yml` | GitHub Actions workflow with flake8 and nose tests |
| `.tekton/tasks.yml` | Tekton cleanup and nose tasks |
| `service/` | Flask counter API |
| `tests/` | Counter service unit tests |
| `Dockerfile` | Application container listening on port 8000 |

## Continuous integration

The workflow checks out the repository, installs the Python dependencies,
runs flake8, and runs nose with coverage. Python 3.9 preserves compatibility
with the course's pinned nose dependencies. The workflow uses read-only
repository permissions.

```bash
python -m pip install -r requirements.txt
flake8 service tests --count --select=E9,F63,F7,F82 --show-source --statistics
flake8 service tests --count --max-complexity=10 --max-line-length=127 --statistics
nosetests -v --with-spec --spec-color --with-coverage --cover-package=service
```

## OpenShift continuous delivery

The pipeline runs these tasks in order:

`cleanup → git-clone → flake8 → nose → buildah → deploy`

The shared PersistentVolumeClaim requests **1Gi** of storage using the lab's
`skills-network-learner` storage class. The final deployment runs the service
on port **8000**. Deployment evidence is collected from an actual pipeline
run and its application logs.

## API

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/health` | Service health |
| GET | `/counters` | List counters |
| POST | `/counters/<name>` | Create a counter starting at zero |
| GET | `/counters/<name>` | Read a counter |
| PUT | `/counters/<name>` | Increment a counter |
| DELETE | `/counters/<name>` | Delete a counter |

## Attribution and license

Based on the [IBM Skills Network CI/CD final project template](https://github.com/ibm-developer-skills-network/vselh-ci-cd-final-project-template).
Licensed under the Apache License 2.0; see [LICENSE](LICENSE).
