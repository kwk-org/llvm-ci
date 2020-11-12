RUNNER_IMAGE := quay.io/kkleine/llvm-ci:runner-fedora-33-$(ARCH)-$(CI_GIT_COMMIT_ID)

.PHONY: runner-image
## Generates a container image to be used as a github self-hosted runner.
runner-image: runner/Dockerfile
	@echo Building image ${RUNNER_IMAGE}
	cd runner \
	&& $(CONTAINER_TOOL) build \
		--build-arg ci_git_revision=$(CI_GIT_COMMIT_ID) \
		--build-arg ci_container_image_ref=${RUNNER_IMAGE} \
		--build-arg build_date="$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")" \
		. \
		-f Dockerfile \
		-t ${RUNNER_IMAGE}

.PHONY: push-runner-image
## Pushes the runner container images to a registry.
push-runner-image:
	@echo Pushing image ${RUNNER_IMAGE}
	$(CONTAINER_TOOL) push ${RUNNER_IMAGE}

.PHONY: run-local-runner
## Runs the runner container image locally for quick testing.
## QUICK TIP: To start a bash and not the actual runner run "make run-local-runner bash"
run-local-runner: runner-image
	export SECRET_DIR=$(shell mktemp -d -p $(OUT_DIR)) \
	&& chmod a+rwx $${SECRET_DIR} \
	&& echo '<PUT_URL_TO_GITHUB_REPO_HERE>' > $${SECRET_DIR}/runner-url \
	&& echo '<PUT_GITHUB_RUNNER_TOKEN_HERE>' > $${SECRET_DIR}/runner-token \
	&& $(CONTAINER_TOOL) run -it --rm \
	-v $${SECRET_DIR}:/runner-secret-volume:Z \
	${RUNNER_IMAGE} bash

.PHONY: delete-runner-deployment
## Removes all parts of the buildbot runner deployment from the cluster
delete-runner-deployment:
	-kubectl delete pod,secret --grace-period=0 --force -l app=buildbot -l tier=runner

.PHONY: deploy-runner
## Deletes and recreates the runner container image as a pod on a Kubernetes cluster.
deploy-runner: ready-to-deploy runner-image push-runner-image delete-runner-deployment
	export SECRET_FILE=$(shell test -f ./runner/k8s/secret.yaml && echo ./runner/k8s/secret.yaml || echo ./runner/k8s/secret.yaml.sample)\
	&& kubectl apply -f $${SECRET_FILE}
	export RUNNER_IMAGE=$(RUNNER_IMAGE) \
	&& envsubst '$${RUNNER_IMAGE}' < ./runner/k8s/pod.yaml > ./out/runner-pod.yaml
	kubectl apply -f ./out/runner-pod.yaml