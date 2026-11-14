#!/usr/bin/env bash
# Sinh manifest pod Node tạm. Dùng: node-pod.sh <tên> <image> <extra|noextra> <node|-> url...
name=$1 img=$2 extra=$3 node=$4; shift 4
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
    runAsUser: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: node
      image: $img
      command: ["node", "/probe/get.mjs", $urls]
      env:
$( [ "$extra" = extra ] && cat <<E2
        - name: NODE_EXTRA_CA_CERTS
          value: /etc/trust/lab-root-ca.pem
E2
)
        - name: _UNUSED
          value: ""
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: {drop: [ALL]}
      resources:
        requests: {cpu: 50m, memory: 128Mi}
        limits: {memory: 128Mi}
      volumeMounts:
        - {name: probe, mountPath: /probe, readOnly: true}
        - {name: trust, mountPath: /etc/trust, readOnly: true}
  volumes:
    - name: probe
      configMap: {name: probe-node}
    - name: trust
      projected:
        sources:
          - configMap: {name: lab-trust, items: [{key: bundle.p12, path: bundle.p12}]}
          - configMap: {name: lab-root, items: [{key: ca.crt, path: lab-root-ca.pem}]}
YAML
