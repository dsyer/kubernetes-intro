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