FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
COPY --chmod=644 runtime/brouter.jar /app/brouter.jar
COPY --chmod=755 runtime/profiles2 /profiles2
COPY --chmod=644 LICENSE /app/LICENSE
USER 1000:1000
EXPOSE 17777
ENTRYPOINT ["java", "-Xmx1024m", "-Xms64m", "-XX:MaxDirectMemorySize=32m", "-DmaxRunningTime=60", "-DuseRFCMimeType=true", "-cp", "/app/brouter.jar", "btools.server.RouteServer", "/segments4", "/profiles2", "/tmp/customprofiles", "17777", "8", "0.0.0.0"]
