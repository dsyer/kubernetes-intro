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
$ mvn package
$ docker build -t dsyer/demo .
$ docker run -p 8080:8080 dsyer/demo
$ curl localhost:8080
Hello World
```

## Deploy to Kubernetes

Create a basic manifest:

```
$ docker push dsyer/demo
$ kubectl create deployment demo --image=dsyer/demo --dry-run -o=yaml > deployment.yaml
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
$ mkdir -p src/main/k8s/demo
$ mv deployment.yaml src/main/k8s/demo
```

Create `src/main/k8s/demo/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
```

Apply the new manifest (which is so far just the same):

```
$ kubectl delete src/main/k8s/demo/deployment.yaml
$ kubectl apply -k src/main/k8s/demo/
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
      - image: dsyer/demo
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
$ kubectl apply -f <(kustomize build src/main/k8s/demo)
```

## Modularize

Delete the current deployment:

```
$ kubectl delete -f src/main/k8s/demo/deployment.yaml
```

and then remove `deployment.yaml` and replace the reference to it in the kustomization with an example from a library, adding also an image replacement:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
commonLabels:
  app: app
images:
  - name: dsyer/template
    newName: dsyer/demo
resources:
- github.com/dsyer/docker-services/layers/base
```

Deploy again:

```
$ kubectl apply -f <(kustomize build src/main/k8s/demo/)
configmap/env-config created
service/app created
deployment.apps/app created
```

You can also add features from the library as patches. E.g. tell Kubernetes that we have Spring Boot actuators in our app:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
commonLabels:
  app: app
images:
  - name: dsyer/template
    newName: dsyer/demo
resources:
- github.com/dsyer/docker-services/layers/base
transformers:
  - github.com/dsyer/docker-services/layers/actuator
```

Deploy it:

```
$ kubectl apply -f <(kustomize build src/main/k8s/demo/)
configmap/env-config unchanged
service/app unchanged
deployment.apps/app configured
```

Something changed in the deployment (liveness and readiness probes):

```yaml
apiVersion: apps/v1
kind: Deployment
...
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

## Spring Boot Features

* + Buildpack support in `pom.xml` or `build.gradle`
* Actuators (separate port or not?)
* + Graceful shutdown
* Loading `application.properties` and `application.yml`
* Autoconfiguration of databases, message brokers, etc.
* ? Support for actuators with Kubernetes API keys

To get a buildpack image, upgrade to Spring Boot 2.3 and run the plugin (`pom.xml`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
	<modelVersion>4.0.0</modelVersion>
	<parent>
		<groupId>org.springframework.boot</groupId>
		<artifactId>spring-boot-starter-parent</artifactId>
		<version>2.3.0.M3</version>
		<relativePath/> <!-- lookup parent from repository -->
	</parent>
...
	<repositories>
		<repository>
			<id>spring-milestones</id>
			<name>Spring Milestones</name>
			<url>https://repo.spring.io/milestone</url>
		</repository>
		</repositories>
		<pluginRepositories>
		<pluginRepository>
			<id>spring-milestones</id>
			<name>Spring Milestones</name>
			<url>https://repo.spring.io/milestone</url>
		</pluginRepository>
	</pluginRepositories>

</project>
```

```
$ ./mvnw spring-boot:build-image
...
[INFO] Successfully built image 'docker.io/library/demo:0.0.1-SNAPSHOT'
[INFO] 
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
...
$ docker run -p 8080:8080 demo:0.0.1-SNAPSHOT
Container memory limit unset. Configuring JVM for 1G container.
Calculated JVM Memory Configuration: -XX:MaxDirectMemorySize=10M -XX:MaxMetaspaceSize=86381K -XX:ReservedCodeCacheSize=240M -Xss1M -Xmx450194K (Head Room: 0%, Loaded Class Count: 12837, Thread Count: 250, Total Memory: 1073741824)
...
```

> NOTE: The CF memory calculator is used at runtime to size the JVM to fit the container.

You can also change the image label:

```xml
<project>
    ...
	<build>
		<plugins>
			<plugin>
				<groupId>org.springframework.boot</groupId>
				<artifactId>spring-boot-maven-plugin</artifactId>
				<configuration>
					<image>
						<name>dsyer/${project.artifactId}</name>
					</image>
				</configuration>
			</plugin>
		</plugins>
	</build>
</project>
```

## The Bad Bits: Ingress

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
$ kubectl apply -f src/main/k8s/demo/ingress.yaml
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

> NOTE: If your cluster was "brand new" and didn't have an ingress service you can add it like this:
>
>     $ kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/mandatory.yaml
>     $ kubectl apply -f <(curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/provider/baremetal/service-nodeport.yaml | sed -i -e '/  type:.*/d')

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

* The database is tied to the app, all wrapped up in the same manifest. It's great for getting started and getting something running, but it won't be structured like that in production.

* The database probably isn't fit for production use. It has a clear text password for instance.

## A Different Approach to Boilerplate YAML

Kubernetes is flexible and extensible. How about a CRD (Custom Resource Definition)? E.g. what if our demo manifest was just this:

```yaml
apiVersion: spring.io/v1
kind: Microservice
metadata:
  name: demo
spec:
  image: dsyer/demo
```

That's actually all you need to know to create the 30-50 lines of YAML in the original sample. The idea is to expand it in cluster and create the service, deployment (ingress, etc.) automatically. Kubernetes also ties those resources to the "microservice" and does garbage collection - if you delete the parent resource they all get deleted. There are other benefits to having an abstraction that is visible in the Kubernetes API.

This needs to be wired into the Kubernetes cluster. There's a prototype [here](https://github.com/dsyer/spring-boot-operator) and `Microservice` is also pretty similar to the [projectriff](https://github.com/projectriff/riff) resource called `Deployer`. Other implementations have also been seen on the internet.

The prototype has a [PetClinic](https://github.com/dsyer/spring-boot-operator/blob/master/config/samples/petclinic.yaml) that you can deploy to get a feeling for the differences.

The danger with such abstractions is that they potentially close off areas that were formally verbose but flexible. Also, there is a problem with cognitive-saturation - too many CRDs means too many things to learn and too many to keep track of in your cluster.

## Developer Experience with Skaffold

[Skaffold](https://skaffold.dev) is a tool from Google that helps reduce toil for the change-build-test cycle including deploying to Kubernetes.  We can start with a really simple Docker based build (in `skaffold.yaml`):

```yaml
apiVersion: skaffold/v2alpha3
kind: Config
metadata:
  name: demo-app--
build:
  artifacts:
  - image: localhost:5000/apps/demo
    docker: {}
deploy:
  kustomize:
    paths: 
    - "src/main/k8s/demo/"
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

## Using Spring Boot Docker Images with Skaffold

Skaffold has a custom builder option, so we can use that to hook in the buildpack support. First we need to make the image name a parameter of the build (in `pom.xml`):

```xml
<properties>
	<java.version>1.8</java.version>
	<docker.image>localhost:5000/apps/${project.artifactId}</docker.image>
</properties>
<build>
	<plugins>
		<plugin>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-maven-plugin</artifactId>
			<configuration>
				<image>
					<name>${docker.image}</name>
				</image>
			</configuration>
		</plugin>
	</plugins>
</build>
```

and then we can set up Skaffold like this:

```yaml
apiVersion: skaffold/v2alpha4
kind: Config
metadata:
  name: demo-app--
build:
  artifacts:
  - image: localhost:5000/apps/demo
    custom:
      buildCommand: ./mvnw spring-boot:build-image -D docker.image=$IMAGE && docker push $IMAGE
      dependencies:
        paths:
        - src
        - pom.xml
deploy:
  kustomize:
    paths: 
    - "src/main/k8s/demo/"
```