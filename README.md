* [Pre-requisites](#pre-requisites)
* [Getting Started](#getting-started)
* [Deploy to Kubernetes](#deploy-to-kubernetes)
* [Organize with Kustomize](#organize-with-kustomize)
* [Modularize](#modularize)
* [Developer Experience with Skaffold](#developer-experience-with-skaffold)
* [Spring Boot Features](#spring-boot-features)
* [Buildpack Images](#buildpack-images)
* [Using Spring Boot Docker Images with Skaffold](#using-spring-boot-docker-images-with-skaffold)
* [Hot Reload in Skaffold with Spring Boot Devtools](#hot-reload-in-skaffold-with-spring-boot-devtools)
* [Layered JARs](#layered-jars)
* [Probes](#probes)
* [Graceful Shutdown](#graceful-shutdown)
* [The Bad Bits: Ingress](#the-bad-bits-ingress)
* [The Bad Bits: Persistent Volumes](#the-bad-bits-persistent-volumes)
* [The Bad Bits: Secrets](#the-bad-bits-secrets)
* [A Different Approach to Boilerplate YAML](#a-different-approach-to-boilerplate-yaml)
* [Another Idea](#another-idea)
* [Metrics Server](#metrics-server)
* [Autoscaler](#autoscaler)

## Pre-requisites

You need Docker. If you can install [Nix](https://nixos.org/nix/) then do that and then just `nix-shell` on your command line to install all dependencies except Docker. If you can't do that, you will need to install them manually. Here's what it installs:

- `jdk11`
- `kind` (you might not need that if you can get hold of a Kubernetes cluster some other way)
- `kubectl`
- `kustomize`
- `skaffold`
- `apacheHttpd` just to get the `ab` utility for load generation

There is also `kind-setup.sh` script that you might feel like using to set up a Kubernetes cluster and a Docker registry (`nix-shell` will run it automatically). Maybe an IDE would come in handy, but not mandatory.

## Getting Started

Create a basic Spring Boot application:

```
$ curl https://start.spring.io/starter.tgz -d dependencies=webflux -d dependencies=actuator | tar -xzvf -
```

Add an endpoint (`src/main/java/com/example/demo/Home.java`):

```java
package com.example.demo;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class Home {
    @GetMapping("/")
    public String home() {
        return "Hello World";
    }
}
```

Containerize (`Dockerfile`):

```
FROM openjdk:8-jdk-alpine as build
WORKDIR /workspace/app

COPY target/*.jar app.jar

RUN mkdir target && cd target && jar -xf ../*.jar

FROM openjdk:8-jdk-alpine
VOLUME /tmp
ARG DEPENDENCY=/workspace/app/target
COPY --from=build ${DEPENDENCY}/BOOT-INF/lib /app/lib
COPY --from=build ${DEPENDENCY}/META-INF /app/META-INF
COPY --from=build ${DEPENDENCY}/BOOT-INF/classes /app
ENTRYPOINT ["java","-cp","app:app/lib/*","com.example.demo.DemoApplication"]
```

Run and test...

```
$ ./mvnw package
$ docker build -t localhost:5000/apps/demo .
$ docker run -p 8080:8080 localhost:5000/apps/demo
$ curl localhost:8080
Hello World
```

Stash the image for later in our local repository (which was started with `kind-setup` if you used that):

```
$ docker push localhost:5000/apps/demo
```

## Deploy to Kubernetes

Create a basic manifest:

```
$ kubectl create deployment demo --image=localhost:5000/apps/demo --dry-run -o=yaml > deployment.yaml
$ echo --- >> deployment.yaml
$ kubectl create service clusterip demo --tcp=80:8080 --dry-run -o=yaml >> deployment.yaml
```

Apply it:

```
$ kubectl apply -f deployment.yaml
$ kubectl port-forward svc/demo 8080:80
$ curl localhost:8080
Hello World
```

## Organize with Kustomize

```
$ mkdir -p k8s
$ mv deployment.yaml k8s
```

Create `k8s/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
```

Apply the new manifest (which is so far just the same):

```
$ kubectl delete -f k8s/deployment.yaml
$ kubectl apply -k k8s/
service/demo created
deployment.apps/demo created
```

Now we can strip away some of the manifest and let Kustomize fill in the gaps (`deployment.yaml`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
spec:
  template:
    spec:
      containers:
        - image: localhost:5000/apps/demo
          name: demo
---
apiVersion: v1
kind: Service
metadata:
  name: demo
spec:
  ports:
    - name: 80-8080
      port: 80
      protocol: TCP
      targetPort: 8080
```

Add labels to the kustomization:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
commonLabels:
  app: app
resources:
  - deployment.yaml
```

Maybe switch to `kustomize` on the command line (to pick up latest version, although at this stage it doesn't matter):

```
$ kubectl apply -f <(kustomize build k8s)
```

## Modularize

Delete the current deployment:

```
$ kubectl delete -f k8s/deployment.yaml
```

and then remove `deployment.yaml` and replace the reference to it in the kustomization with an example from a library, adding also an image replacement:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
commonLabels:
  app: app
images:
  - name: dsyer/template
    newName: localhost:5000/apps/demo
resources:
  - github.com/dsyer/docker-services/layers/base
```

Deploy again:

```
$ kubectl apply -f <(kustomize build k8s/)
configmap/env-config created
service/app created
deployment.apps/app created
```

You can also add features from the library as patches. E.g. tell Kubernetes that we have Spring Boot actuators in our app:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
...
transformers:
  - github.com/dsyer/docker-services/layers/actuator
```

Deploy it:

```
$ kubectl apply -f <(kustomize build k8s/)
configmap/env-config unchanged
service/app unchanged
deployment.apps/app configured
```

Something changed in the deployment (liveness and readiness probes):

```yaml
apiVersion: apps/v1
kind: Deployment
---
livenessProbe:
  httpGet:
    path: /actuator/info
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 3
name: app
readinessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 20
  periodSeconds: 10
```

## Developer Experience with Skaffold

[Skaffold](https://skaffold.dev) is a tool from Google that helps reduce toil for the change-build-test cycle including deploying to Kubernetes. We can start with a really simple Docker based build (in `skaffold.yaml`):

```yaml
apiVersion: skaffold/v2beta3
kind: Config
build:
  artifacts:
    - image: localhost:5000/apps/demo
      docker: {}
deploy:
  kustomize:
    paths:
      - k8s
```

Start the app:

```
$ skaffold dev --port-forward
...
Watching for changes...
Port forwarding service/app in namespace default, remote port 80 -> address 127.0.0.1 port 4503
...
```

You can test that the app is running on port 4503. Because of the way we defined our `Dockerfile`, it is watching for changes in the jar file. So we can make as many changes as we want to the source code and they only get deployed if we rebuild the jar.

## Spring Boot Features

- Loading `application.properties` and `application.yml`
- Autoconfiguration of databases, message brokers, etc.
- Decryption of encrypted secrets in process (e.g. Spring Cloud Commons and Spring Cloud Vault)
- Spring Cloud Kubernetes (direct access to Kubernetes API required for some features)
- \+ Buildpack support in `pom.xml` or `build.gradle`
- Actuators (separate port or not?)
- \+ Liveness and Readiness as first class features
- \+ Graceful shutdown
- ? Support for actuators with Kubernetes API keys

## Buildpack Images

To get a buildpack image, ensure you are using Spring Boot 2.3 (`pom.xml`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
	<modelVersion>4.0.0</modelVersion>
	<parent>
		<groupId>org.springframework.boot</groupId>
		<artifactId>spring-boot-starter-parent</artifactId>
		<version>2.3.0.RELEASE</version>
		<relativePath/> <!-- lookup parent from repository -->
	</parent>
</project>
```

and run the plugin on the command line:

```
$ rm Dockerfile
$ ./mvnw spring-boot:build-image -Dspring-boot.build-image.imageName=localhost:5000/apps/demo
...
[INFO] Successfully built image 'docker.io/library/demo:0.0.1-SNAPSHOT'
[INFO]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
...
$ docker run -p 8080:8080 demo:0.0.1-SNAPSHOT localhost:5000/apps/demo
Container memory limit unset. Configuring JVM for 1G container.
Calculated JVM Memory Configuration: -XX:MaxDirectMemorySize=10M -XX:MaxMetaspaceSize=86381K -XX:ReservedCodeCacheSize=240M -Xss1M -Xmx450194K (Head Room: 0%, Loaded Class Count: 12837, Thread Count: 250, Total Memory: 1073741824)
...
```

> NOTE: The CF memory calculator is used at runtime to size the JVM to fit the container.

You can also change the image tag (in `pom.xml` or on the command line with `-D`):

```xml
<project>
    ...
	<properties>
		<java.version>1.8</java.version>
		<spring-boot.build-image.imageName>localhost:5000/apps/${project.artifactId}</spring-boot.build-image.imageName>
	</properties>
</project>
```

## Using Spring Boot Docker Images with Skaffold

If you use SKaffold 1.11.0 or better you can use the `buildpacks` builder:

```yaml
apiVersion: skaffold/v2beta5
kind: Config
build:
  artifacts:
    - image: localhost:5000/apps/demo
      buildpacks:
        builder: gcr.io/paketo-buildpacks/builder:base-platform-api-0.3
        dependencies:
          paths:
            - pom.xml
            - src/main/resources
            - target/classes
      sync:
        manual:
          - src: "src/main/resources/**/*"
            dest: /workspace/BOOT-INF/classes
            strip: src/main/resources/
          - src: "target/classes/**/*"
            dest: /workspace/BOOT-INF/classes
            strip: target/classes/
deploy:
  kustomize:
    paths:
      - "src/k8s/demo/"
```

Skaffold also has a custom builder option, so we can use that to do the same thing effectively:

```yaml
apiVersion: skaffold/v2beta3
kind: Config
build:
  artifacts:
    - image: localhost:5000/apps/demo
      custom:
        buildCommand: ./mvnw spring-boot:build-image -D spring-boot.build-image.imageName=$IMAGE && docker push $IMAGE
        ...
```

## Hot Reload in Skaffold with Spring Boot Devtools

Add `spring-boot-devtools` to your project `pom.xml`:

```xml
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-devtools</artifactId>
      <scope>runtime</scope>
    </dependency>
```

and make sure it gets added to the runtime image in (see `excludeDevtools`):

```xml
	<properties>
		<spring-boot.repackage.excludeDevtools>false</spring-boot.repackage.excludeDevtools>
	</properties>
```

Then in `skaffold.yaml` we can use changes in source files to sync to the running container instead of doing a full rebuild:

```yaml
apiVersion: skaffold/v2beta3
kind: Config
build:
  artifacts:
    - image: localhost:5000/apps/demo
      custom:
        buildCommand: docker build -t $IMAGE . && docker push $IMAGE
        dependencies:
          paths:
            - pom.xml
            - src/main/resources
            - target/classes
            - Dockerfile
      sync:
        manual:
          - src: "src/main/resources/**/*"
            dest: /workspace/app
            strip: src/main/resources/
          - src: "target/classes/**/*"
            dest: /workspace/app
            strip: target/classes/
deploy:
  kustomize:
    paths:
      - k8s
```

The key parts of this are the `custom.dependencies` and `sync.manual` fields. They have to match - i.e. no files are copied into the running container from `sync` if they don't appear also in `dependencies`.

You need a `Dockerfile` that builds the app in `/workspace/app`, so here's one that works and has a cache for Maven artifacts:

```
# syntax=docker/dockerfile:experimental
FROM openjdk:8-jdk-alpine as build
WORKDIR /workspace/app

COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .
COPY src src

RUN --mount=type=cache,target=/root/.m2 ./mvnw install -DskipTests
RUN mkdir -p target/dependency && (cd target/dependency; jar -xf ../*.jar)

FROM openjdk:8-jdk-alpine
VOLUME /tmp
ARG DEPENDENCY=/workspace/app/target/dependency
WORKDIR /workspace
COPY --from=build ${DEPENDENCY}/BOOT-INF/lib app/lib
COPY --from=build ${DEPENDENCY}/META-INF app/META-INF
COPY --from=build ${DEPENDENCY}/BOOT-INF/classes app
ENTRYPOINT ["java","-cp","app:app/lib/*","com.example.demo.DemoApplication"]
```

The effect is that if any `.java` or `.properties` files are changed, they are copied into the running container, and this causes Spring Boot to restart the app, usually quite quickly.

> NOTE: You can use Skaffold and Maven "profiles" to keep the devtools stuff only at dev time. The production image can be built without the devtools dependency if the flag is inverted or the dependency is removed.

> NOTE: You can't currently use Skaffold to trigger a restart in Dev Tools when you build the image using Spring Boot tools because the buildpack runs the app using a `JarLauncher` (from an exploded archive), and Spring Boot thinks that means you don't want to restart when files change.

## Layered JARs

Spring Boot 2.3 also has some [capabilities](https://docs.spring.io/spring-boot/docs/current-SNAPSHOT/maven-plugin/reference/html/#repackage) to unpack its executable jars in a way that can easily be mapped to more finely grained filesystem layers in a container. You have to switch on the layering feature in the build (in `pom.xml`):

```
			<plugin>
				<groupId>org.springframework.boot</groupId>
				<artifactId>spring-boot-maven-plugin</artifactId>
				<configuration>
					<layers>
						<enabled>true</enabled>
					</layers>
          ...
          </configuration>
			</plugin>
```

By default it splits a JAR into 4 layers and you can list and extract them by using the JAR file itself and a system property:

```
$ java -jar -Djarmode=layertools target/docker-demo-0.0.1-SNAPSHOT.jar list
dependencies
spring-boot-loader
snapshot-dependencies
application
```

> NOTE: It actually doesn't add much value over the standard JAR layout unless you have snapshot dependencies.

Then if you ask it to `extract` (instead of `list`) it will dump the contents of those layers in the current directory. Here's a `Dockerfile` that works with that:

```
# syntax=docker/dockerfile:experimental
FROM openjdk:8-jdk-alpine as build
WORKDIR /workspace/app

COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .
COPY src src

RUN --mount=type=cache,target=/root/.m2 ./mvnw install -DskipTests
RUN mkdir -p target/dependency && (cd target/dependency; java -Djarmode=layertools -jar ../*.jar extract)

FROM openjdk:8-jre-alpine
RUN addgroup -S demo && adduser -S demo -G demo
VOLUME /tmp
ARG DEPENDENCY=/workspace/app/target/dependency
COPY --from=build ${DEPENDENCY}/dependencies/BOOT-INF/lib /app/lib
COPY --from=build ${DEPENDENCY}/application/META-INF /app/META-INF
COPY --from=build ${DEPENDENCY}/application/BOOT-INF/classes /app
RUN chown -R demo:demo /app
USER demo
ENTRYPOINT ["sh", "-c", "java -cp /app:/app/lib/* com.example.demo.DemoApplication ${0} ${@}"]
```

If you want to get fancy you can tweak the layer definitions to make new layers and put whatever files you like in each layer.

## Probes

Kubernetes uses two probes to determine if the app is ready to accept traffic and whether the app is alive:

* If the readiness probe does not return a `200` no trafic will be routed to it
* If the liveness probe does not return a `200` kubernetes will restart the Pod

Spring Boot has a build in set of endpoints from the [Actuator](https://spring.io/blog/2020/03/25/liveness-and-readiness-probes-with-spring-boot) module that fit nicely into these use cases

* The `/health/readiness` endpoint indicates if the application is healthy, this fits with the readiness proble
* The `/health/liveness` endpoint serves application info, we can use this to make sure the application is "alive"

> NOTE: before Spring Boot 2.3, `/health` and `/info` worked just as well for most apps. The new endpoints are more flexible and configurable for specific use cases.

Here's a basic patch that works (`k8s/probes.yaml`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
        - name: app
          readinessProbe:
            httpGet:
              port: 8080
              path: /actuator/health/readiness
          livenessProbe:
            httpGet:
              port: 8080
              path: /actuator/health/liveness
```

You can install it in the `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
commonLabels:
  app: demo
images:
  - name: dsyer/template
    newName: localhost:5000/apps/demo
resources:
  - github.com/dsyer/docker-services/layers/base
patchesStrategicMerge:
  - probes.yaml
```

## Graceful Shutdown

Kubernetes sends `SIGTERM` to containers it wants to shutdown. It tries to shield them from further traffic, but there are no guarantees in a distributed system. It then waits for a grace period (by default 30s) before shooting the container in the head.

If your app has a lot of traffic, or takes a long time to process requests, you may have to take steps to avoid lost connections. One thing you can always do is add a sleep to the Kubernetes `preStop` hook:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
        - name: app
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 10"]
```

Also, it is possible that the `ApplicationContext` could close before the HTTP server shuts down, so in-flight requests can fail because they no longer have access to database connections etc. Spring Boot 2.3 has some new configuration properties

```
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=20s
```

to delay the hard stop of the HTTP server while the `ApplicationContext` is still running.

## The Bad Bits: Ingress

> NOTE: If your cluster is "brand new" and doesn't have an ingress service you can add one like this:
>
>     $ kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/mandatory.yaml
>     $ kubectl apply -f <(curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/provider/baremetal/service-nodeport.yaml | sed -e '/  type:.*/d')

[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) in Kubernetes refers to an API resource that defines how HTTP requests get routed to applications (or rather services). You can create rules based on hostname or URL paths. Example:

```yaml
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - host: demo
      http:
        paths:
          - path: /
            backend:
              serviceName: app
              servicePort: 80
```

Apply this YAML and check the status:

```
$ kubectl apply -f k8s/ingress.yaml
$ kubectl get ingress
NAME      HOSTS   ADDRESS       PORTS   AGE
ingress   demo    10.103.4.16   80      2m15s
```

So it's working (because we had nginx ingress already installed in the cluster) and we can connect to the service through the ingress:

```
$ kubectl port-forward --namespace=ingress-nginx service/ingress-nginx 8080:80
$ curl localhost:8080 -H "Host: demo"
Hello World!!
```

Having to add `Host:demo` to HTTP requests manually is kind of a pain. Normally you want to rely on default behaviour of HTTP clients (like browsers) and just `curl demo`. But that means you need DNS or `/etc/hosts` configuration and that's where it gets to be even more painful. DNS changes can take minutes or even hours to propagate, and `/etc/hosts` only works on your machine.

## The Bad Bits: Persistent Volumes

How about an app with a database? Let's look at a PetClinic:

```
$ kubectl apply -f <(kustomize build github.com/dsyer/docker-services/layers/samples/petclinic)
configmap/petclinic-env-config created
configmap/petclinic-mysql-config created
configmap/petclinic-mysql-env created
service/petclinic-app created
service/petclinic-mysql created
deployment.apps/petclinic-app created
deployment.apps/petclinic-mysql created
persistentvolumeclaim/petclinic-mysql created
$ kubectl port-forward service/petclinic-app 8080:80
```

Visit `http://localhost:8080` in your browser:

![PetClinic](https://i.imgur.com/MCgAL4n.png)

So that works. What's the problem?

```
$ kubectl get persistentvolumeclaim
NAME              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
petclinic-mysql   Bound    pvc-68d43a16-1953-4754-893c-5f383556b912   8Gi        RWO            standard       5m25s
```

All perfectly fine, so what is the problem? The PVC is "Bound", which means there was a PV that satisfied its resource constraints. That won't always be the case, and you might need an admin operator to fix it. It worked here because there is a default PV. Some platforms have that, and some don't.

More issues with this PetClinic:

- The database is tied to the app, all wrapped up in the same manifest. It's great for getting started and getting something running, but it won't be structured like that in production.

- The database probably isn't fit for production use. It has a clear text password for instance.

## The Bad Bits: Secrets

Kubernetes has a [Secret](https://kubernetes.io/docs/concepts/configuration/secret/) feature built in, but everyone knows they are not encrypted, so not really secret. There are several approaches that work to encrypt secrets, but it's not standardized and it's hard to operationalize. We've been here before, so Vault and/or Credhub will probably end up being a solution.

For high-end, super security-concious sites, you have to ensure that unencrypted data is never at rest, anywhere (including in an ephemeral file system in a container volume). Applications have to be able to decrypt secrets in-process, so Spring can help with that, but in practice only if users explicitly ask for it.

## A Different Approach to Boilerplate YAML

Kubernetes is flexible and extensible. How about a CRD (Custom Resource Definition)? E.g. what if our demo manifest was just this:

```yaml
apiVersion: spring.io/v1
kind: Microservice
metadata:
  name: demo
spec:
  image: localhost:5000/apps/demo
```

That's actually all you need to know to create the 30-50 lines of YAML in the original sample. The idea is to expand it in cluster and create the service, deployment (ingress, etc.) automatically. Kubernetes also ties those resources to the "microservice" and does garbage collection - if you delete the parent resource they all get deleted. There are other benefits to having an abstraction that is visible in the Kubernetes API.

This needs to be wired into the Kubernetes cluster. There's a prototype [here](https://github.com/dsyer/spring-boot-operator) and `Microservice` is also pretty similar to the [projectriff](https://github.com/projectriff/riff) resource called `Deployer`. Other implementations have also been seen on the internet.

The prototype has a [PetClinic](https://github.com/dsyer/spring-boot-operator/blob/master/config/samples/petclinic.yaml) that you can deploy to get a feeling for the differences. Here's the manifest:

```yaml
apiVersion: spring.io/v1
kind: Microservice
metadata:
  name: petclinic
spec:
  image: dsyer/petclinic
  bindings:
    - services/mysql
  template:
    spec:
      containers:
        - name: app
          env:
            - name: MANAGEMENT_ENDPOINTS_WEB_BASEPATH
              value: /actuator
            - name: DATABASE
              value: mysql
```

The danger with such abstractions is that they potentially close off areas that were formally verbose but flexible. Also, there is a problem with cognitive-saturation - too many CRDs means too many things to learn and too many to keep track of in your cluster.

## Another Idea

Instead of a CRD that creates deployments, you could have a CRD that injects stuff into existing deployments. Kubernetes has a `PodPreset` feature that is a similar idea, and the implementation would be similar (a mutating webhook). E.g.

```yaml
apiVersion: spring.io/v1
kind: Microservice
metadata:
  name: demo
spec:
  target:
    apiVersion: apps/v1
    kind: Deployment
    name: demo
```

The "opinions" about what to inject into the "demo" deployment could be located in the Microservice controller. It can look at the metadata in the container image and add probes that match the dependencies - if actuator is present use `/actuator/info`. If there is no metadata in the container the manifest can list opinions explicitly.

The "target" for the Microservice could also be a Kubernetes selector (e.g. all deployments with a specific label).

## Metrics Server

You need a [Metrics Server](https://github.com/kubernetes-sigs/metrics-server) to benefit from `kubectl top` and the [Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/). Kind doesn't support the metrics server [out of the box](https://github.com/kubernetes-sigs/kind/issues/398):

```
$ kubectl top pod
W0323 08:01:25.173488   18448 top_pod.go:266] Metrics not available for pod default/app-5f969c594d-79s79, age: 65h4m54.173475197s
error: Metrics not available for pod default/app-5f969c594d-79s79, age: 65h4m54.173475197s
```

But you _can_ install it using the manifests in the [source code](https://github.com/kubernetes-sigs/metrics-server/blob/master/deploy/kubernetes/) (or this [gist](https://gist.github.com/hjacobs/69b6844ba8442fcbc2007da316499eb4)). It is available here as well:

```
$ kubectl apply -f src/k8s/metrics
$ kubectl top pod
NAME                   CPU(cores)   MEMORY(bytes)
app-79fdc46f88-mjm5c   217m         143Mi
```

> NOTE: You might need to recycle the application Pods to make them wake up to the metrics server.

## Autoscaler

First make sure you have a CPU request in your app container:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
---
resources:
  requests:
    cpu: 200m
  limits:
    cpu: 500m
```

And recycle the deployment (Skaffold will do it for you). Then add an autoscaler:

```
$ kubectl autoscale deployment app --min=1 --max=3
$ kubectl get hpa
NAME   REFERENCE        TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
app    Deployment/app   5%/80%          1         3         1          9s
```

Hit the endpoints hard with (e.g.) Apache Bench:

```
$ ab -c 100 -n 10000 http://localhost:4503/actuator/
```

and you should see it scale up:

```
$ kubectl get hpa
NAME   REFERENCE        TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
app    Deployment/app   112%/80%        1         3         2          7m25s
```

and then back down:

```
$ kubectl get hpa
NAME   REFERENCE        TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
app    Deployment/app   5%/80%          1         3         1          20m
```

> NOTE: If you update the app and it restarts or redeploys, the CPU activity on startup can trigger an autoscale up. Kind of nuts. It's potentially a thundering herd.

The `kubectl autoscale` command generates a manifest for the "hpa" something like this:

```yaml
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
metadata:
  name: app
spec:
  maxReplicas: 3
  metrics:
    - resource:
        name: cpu
        target:
          averageUtilization: 80
          type: Utilization
      type: Resource
  minReplicas: 1
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app
```
