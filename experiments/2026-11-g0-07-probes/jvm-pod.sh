#!/usr/bin/env bash
# Sinh manifest pod JVM tạm. Dùng: jvm-pod.sh <tên> <mount|nomount> <opts|noopts> <node|-> <p12-configmap> url...
name=$1 mount=$2 opts=$3 node=$4 cm=$5; shift 5
IMG=eclipse-temurin:25-jdk@sha256:b8705e936964c228dfce359e63dbf08f6c69cb380ed1d576b1f6b1064f15567d
urls=$(printf '"%s",' "$@"); urls=${urls%,}
cat <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: sandbox-trust
spec:
  restartPolicy: Never
  $( [ "$node" != - ] && echo "nodeName: $node" )
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: java
      image: $IMG
      command: ["java", "/probe/Get.java", $urls]
      env:
$( [ "$opts" = opts ] && cat <<E2
        - name: JAVA_TOOL_OPTIONS
          value: "-Djavax.net.ssl.trustStore=/etc/trust/bundle.p12 -Djavax.net.ssl.trustStoreType=PKCS12"
E2
)
        - name: _UNUSED
          value: ""
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: {drop: [ALL]}
      resources:
        requests: {cpu: 100m, memory: 256Mi}
        limits: {memory: 256Mi}
      volumeMounts:
        - {name: probe, mountPath: /probe, readOnly: true}
        - {name: tmp, mountPath: /tmp}
$( [ "$mount" = mount ] && echo "        - {name: trust, mountPath: /etc/trust, readOnly: true}" )
  volumes:
    - name: probe
      configMap: {name: probe-java}
    - name: tmp
      emptyDir: {}
$( [ "$mount" = mount ] && cat <<E3
    - name: trust
      projected:
        sources:
          - configMap: {name: $cm, items: [{key: bundle.p12, path: bundle.p12}]}
          - configMap: {name: lab-root, items: [{key: ca.crt, path: lab-root-ca.pem}]}
E3
)
YAML
