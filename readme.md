### Development from the edge

When you live on and work from the edge, as I do, you must teach yourself some tricks in order to engineer software reliably and reproducibly.

One such trick is [k3s](https://k3s.io/) which allows for rapid prototyping using [helm](https://github.com/helm/helm#helm), [podman](https://podman.io/) and literally any technology you need, such as [flink](https://flink.apache.org/), [mqtt](https://mqtt.io/), [nats](https://nats.io/), etc. What is great about this toolkit is that you can also use any combination of languages, such as [node](https://nodejs.org/), [python](https://www.python.org/), [go](https://go.dev/), and any ui harness, such as (my favorite) [vue](https://vuejs.org), [angular](https://angular.dev) or [react](https://react.dev/).

I tend to use them all.

Sometimes on the same project.

I like variety.

In less inspired days I could never remember what I had for lunch, in spite of the fact that I ate the same thing every day. But these days I cherish the memory of my daily green salad, which is never the same from day to day, but is always memorable.

I live on the edge of a smallish city, in a swamp. When we bought it the real estate agent did not mention the swamp. She talked about small town charm, which this place certainly has. But I know it is now a swamp, because one day my husband said, "look out, that's an alligator," while we were standing in our front yard.

Where we live is otherwise paradise. But given the local wildlife, we have to make some sacrifices. Once such sacrifice is high speed internet. Cable guys understandably don't want to make sales calls, given the treacherous nature of the neighborhood. So we have to use wi-fi, which is less than optimal. Even on the world's largest 5G network we rarely get more that two bars on our home streaming device. Sometimes the iPhone is better, but not by much. And sometimes the wind just blows the towers down, anyway.

So software engineering in this environment requires that we make creative use of what we have. We must be smarter than our machines.

Our challenge was to proxy [OCI](https://opencontainers.org/) images for deployment to our local control plane.

Most of this proxy-business I had already covered with my [creepo](https://dooleydiligent.github.io/creepo/) project. But that creep is insufficient to this task. Instead we need our own [registry](https://hub.docker.com/_/registry) behind our gateway.

This was run on a new install of Ubuntu 22.04, and is mostly explained by the accompanying [Makefile](./Makefile).

When installed you will have a secure docker caching repo on the public IP of your server at port 32000. There is a separate writable docker repository at port 32001, if you should find yourself in need of that. Images pushed to 32001 can be pulled from port 32000.

Also, for extra bonus points, you will have reference material to show you how to do rapid protyping for massively scalable systems.

### Install

```
sudo apt update -y && \
sudo apt install -y build-essential podman apache2-utils curl
```

You must configure podman locally by adding this file to the ~/.config/containers folder.

```
mkdir -p ~/.config/containers
cat <<EOF > ~/.config/containers/registries.conf
unqualified-search-registries = ["docker.io"]

[[registry]]
prefix = "docker.io"
location = "localhost:32000"


[registries.mirror]
docker.io = "localhost:32000"
EOF
```

```
make
k3s DEV is enp1s0, IP is 192.168.122.150
KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade --install --timeout 600s --wait \
        docker-registry \
        charts/docker-registry \
        --namespace tuscawilla-creek \
        --create-namespace \
        --set docker.key="files/docker.tuscawilla-creek.local.key" \
        --set docker.cert="files/docker.tuscawilla-creek.local.crt" \
        --set docker.hostPath=/mnt/tuscawilla-creek/docker \
        --set docker.htpasswd=ZG9ja2VyOiQyeSQwNSR2YUhlUzF1TlZJQi53M3NJZzZLdUVPYUhLTU8ua2hVVXJWUGJ3QXJnQTBxbWw3OTc4TThXSwo= \
        --set docker.hostPort=32000;

Release "docker-registry" does not exist. Installing it now.
NAME: docker-registry
LAST DEPLOYED: Mon Dec 23 14:46:35 2024
NAMESPACE: tuscawilla-creek
STATUS: deployed
REVISION: 1
TEST SUITE: None
wait for docker

Login Succeeded!
Login Succeeded!
secret/regcred created
```

Now test

```
podman pull nginx:latest
podman pull nginx:alpine
Resolving "nginx" using unqualified-search registries (/home/ubuntu2204/.config/containers/registries.conf)
Trying to pull docker.io/library/nginx:alpine...
Getting image source signatures
Copying blob fbbf7d28be71 done
Copying blob b2eb2b8af93a done
Copying blob af9c0e53c5a4 done
Copying blob a2eb5282fbec done
Copying blob da9db072f522 done
Copying blob e10e486de1ab done
Copying blob e351ee5ec3d4 done
Copying blob 471412c08d15 done
Copying config 91ca84b4f5 done
Writing manifest to image destination
Storing signatures
91ca84b4f57794f97f70443afccff26aed771e36bc48bad1e26c2ce66124ea66

```
