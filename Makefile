NAMESPACE	 			:= tuscawilla-creek
DOMAIN						:= $(NAMESPACE).local
FQDN							:= home.$(DOMAIN)
DEV				 			:= $(word 2,$(shell ip addr | grep '2:' | head -n 1 | sed 's/:/ /g'))
PODMAN						:= $(word 1,$(shell which podman))
HELM							:= KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm

ifndef PODMAN
$(error You must install podman: 'sudo apt install -y podman')
endif

DOCKER_PATH 			:= charts/docker-registry/files/
DOCKER_PORT 			:= 32000
DOCKER_PORTP			:= $(shell echo $$(($(DOCKER_PORT)+1)))
DOCKER_USER 			:= docker
DOCKER_PASS 			:= password

HAS_HTPASSWD			:= $(shell which htpasswd)
ifndef HAS_HTPASSWD
$(error Cannot find htpasswd.	Maybe 'sudo apt install -y apache2-utils')
endif

DOCKER_CRED 			:= $(shell htpasswd -nBb $(DOCKER_USER) $(DOCKER_PASS) | head -n 1 | base64 -w 0)

ifndef DOCKER_CRED
$(error Cannot get output from htpasswd.	Please install apache2-utils and retry)
endif

IP								:= $(word 2,$(shell ip addr show dev $(DEV) | grep 'inet ' | sed 's,/, ,g'))

ifndef IP
$(error You must define IP.	The script cannot)
endif

RESOLVE						:= $(word 2,$(shell nslookup docker.$(NAMESPACE).local| tail -2 | head -n 1))
ifndef RESOLVE
$(error Cannot resolve docker.$(NAMESPACE).local.	This should be an entry in /etc/hosts: e.g. $(IP) docker.$(NAMESPACE).local)
endif

DOCKER_HOST_CACHE := $(word 1, $(shell echo $(DOCKER_HOST_CACHE) /mnt/$(NAMESPACE)/docker))

ifndef DOCKER_HOST_CACHE
$(error You must set DOCKER_HOST_CACHE to some folder on your host)
endif

RSA_KEY_SIZE		 	:= 4096

docker: $(DOCKER_HOST_CACHE) cert
	@if [ ! -d $(DOCKER_HOST_CACHE) ]; then \
		echo Attempting to make folder $(DOCKER_HOST_CACHE); \
		mkdir -p $(DOCKER_HOST_CACHE); \
	fi
	@if [ $$? -ne 0 ]; then \
		echo "Could not create $(DOCKER_HOST_CACHE)" && exit 1; \
	fi

	$(HELM) upgrade --install --timeout 600s --wait \
		docker-registry \
		charts/docker-registry \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--set docker.key="files/docker.$(DOMAIN).key" \
		--set docker.cert="files/docker.$(DOMAIN).crt" \
		--set docker.hostPath=$(DOCKER_HOST_CACHE) \
		--set docker.htpasswd=$(DOCKER_CRED) \
		--set docker.hostPort=$(DOCKER_PORT);
	@sudo chmod -R go+rw /run/containerd/
	@echo wait for docker
	@sleep 10
	@$(PODMAN) login -u $(DOCKER_USER) -p $(DOCKER_PASS) docker.$(DOMAIN):$(DOCKER_PORT)
	@$(PODMAN) login -u $(DOCKER_USER) -p $(DOCKER_PASS) docker.$(DOMAIN):$(DOCKER_PORTP)

	@if [ ! -z "$(shell kubectl get secret -A | grep regcred | grep $(NAMESPACE))" ]; then \
		kubectl delete secret regcred -n $(NAMESPACE); \
	fi;
	@kubectl create secret generic regcred \
		--namespace $(NAMESPACE) \
		--from-file=.dockerconfigjson=$$XDG_RUNTIME_DIR/containers/auth.json	\
		--type=kubernetes.io/dockerconfigjson

cert: k3s
	@if [ ! -f "$(DOCKER_PATH)docker.$(DOMAIN).crt" ]; then \
		echo "Creating ssl configuration"; \
		cat $(DOCKER_PATH)ssl.cnf | \
		sed "s/##DOMAIN##/$(DOMAIN)/g" | \
		sed "s/##PORT##/$(DOCKER_PORT)/g" | \
		sed "s/##NAMESPACE##/$(NAMESPACE)/g" | \
		sed "s/##IP##/$(IP)/g" > /tmp/ssl.cnf; \
		openssl req -new -nodes -newkey \
		rsa:$(RSA_KEY_SIZE) \
		-config /tmp/ssl.cnf \
		-reqexts req_ext \
		-outform pem \
		-keyout $(DOCKER_PATH)docker.$(DOMAIN).key \
		-out /tmp/docker.$(DOMAIN).csr; \
		sudo openssl x509 \
		-req -in /tmp/docker.$(DOMAIN).csr \
		-CA /var/lib/rancher/k3s/server/tls/server-ca.crt \
		-CAkey /var/lib/rancher/k3s/server/tls/server-ca.key \
		-extfile /tmp/ssl.cnf \
		-extensions req_ext \
		-days 365 \
		-outform pem \
		-out $(DOCKER_PATH)docker.$(DOMAIN).crt \
		-set_serial 01 -sha256; \
		sudo cp $(DOCKER_PATH)docker.$(DOMAIN).crt /usr/local/share/ca-certificates; \
		sudo update-ca-certificates; \
		sudo mkdir -p /etc/docker/certs.d/docker.$(DOMAIN):$(DOCKER_PORT); \
	fi;

k3s: helm
	@echo "k3s DEV is $(DEV), IP is $(IP)"
	@if [ ! -f "/etc/rancher/k3s/k3s.yaml" ]; then \
		curl -sfL https://get.k3s.io | K3S_KUBECONFIG_GROUP=k3s K3S_KUBECONFIG_MODE=644 INSTALL_K3S_CHANNEL=stable	sh -s - --write-kubeconfig-mode 644; \
	fi;

helm:
	@if [ -z "$(shell which helm)" ]; then \
		curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -; \
	fi

clean: uninstall
	@rm -rf charts/docker-registry/files/docker.$(DOMAIN).*
	@if [ ! -z "$(shell kubectl get secret -A | grep $(NAMESPACE) | grep regcred)" ]; then \
		kubectl delete secret regcred -n $(NAMESPACE); \
	fi;

uninstall:
	@if [ ! -z "$(shell $(HELM) ls -n $(NAMESPACE) | grep docker-registry)" ]; then \
		$(HELM) uninstall -n $(NAMESPACE) docker-registry; \
	fi

