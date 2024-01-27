FROM ubuntu:latest AS builder
ADD . /app
ADD https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb /
RUN apt update && \
    apt install -y /jdk-21_linux-x64_bin.deb && \
    rm -f /jdk-21_linux-x64_bin.deb && \
    rm -Rf /var/lib/apt/lists/* && \
    bash /app/gradlew build -S -p /app/

FROM cgr.dev/chainguard/jre:latest
WORKDIR /app
COPY --from=builder /app/build/libs/desafio*SNAPSHOT.jar /app/desafio-devops.jar
EXPOSE 8080
ENTRYPOINT ["/usr/bin/java","-jar","desafio-devops.jar"]
