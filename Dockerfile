FROM openjdk:8-jdk-alpine as build
WORKDIR /workspace/app

COPY target/*.jar app.jar

RUN mkdir target && cd target && jar -xf ../*.jar

FROM openjdk:8-jdk-alpine
VOLUME /tmp
ARG DEPENDENCY=/workspace/app/target
COPY --from=build ${DEPENDENCY}/BOOT-INF/lib /workspace/BOOT-INF/lib
COPY --from=build ${DEPENDENCY}/META-INF /workspace/META-INF
COPY --from=build ${DEPENDENCY}/BOOT-INF/classes /workspace/BOOT-INF/classes
ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -cp /workspace/BOOT-INF/classes:/workspace/BOOT-INF/lib/*:/workspace/BOOT-INF com.example.demo.DemoApplication"]
