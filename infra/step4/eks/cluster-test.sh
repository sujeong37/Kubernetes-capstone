#!/usr/bin/env bash
# step4.2 — (WSL) 4.2 에서 켠 것이 정말 동작하는지 시험 namespace 에서 확인하고 지운다 (앱 namespace bus 는 건드리지 않는다)
#   A. EBS  : PVC 만 만들면 Pending(WaitForFirstConsumer) → Pod 를 붙이면 Auto Mode 가 노드를 만들고 그 영역에 gp3 · 암호화 EBS
#   B. NetworkPolicy : 막기 전 통과 → 기본 거부 후 시간 초과 → 필요한 길만 열면 다시 통과 (3.11 과 같은 모양, 이번엔 VPC CNI 가 지킨다)
#   ONLY=ebs 또는 ONLY=np 로 하나만
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
[ "$(kubectl config current-context)" = bus-eks ] || die "context 가 bus-eks 가 아니다 → kubectl config use-context bus-eks"
NS=step42-test
BB=public.ecr.aws/docker/library/busybox:1.37     # Docker Hub 요청 한도를 피해 ECR Public 의 공식 이미지
NG=public.ecr.aws/docker/library/nginx:1.27-alpine
kubectl create ns $NS --dry-run=client -o yaml | kubectl apply -f - >/dev/null
trap 'kubectl delete ns $NS --wait=false >/dev/null 2>&1 || true' EXIT
say "== 시험 namespace $NS ($(date +%T)) · 노드 $(kubectl get nodes --no-headers 2>/dev/null | wc -l)대"

if [ "${ONLY:-ebs}" != np ]; then
say "== A. EBS StorageClass ebs"
kubectl apply -n $NS -f - >/dev/null <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data}
spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 1Gi}}}
YAML
sleep 5
say "  PVC 만 만든 뒤: $(kubectl get pvc data -n $NS -o jsonpath='{.status.phase}') · storageClass $(kubectl get pvc data -n $NS -o jsonpath='{.spec.storageClassName}')  ← 생략했는데 기본 ebs"
say "    이유: $(kubectl get events -n $NS --field-selector involvedObject.name=data -o jsonpath='{.items[-1:].message}' | cut -c1-90)"
t0=$SECONDS
kubectl apply -n $NS -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: writer}
spec:
  containers:
  - name: c
    image: $BB
    command: [sh, -c, 'date > /data/hello && sleep 600']
    volumeMounts: [{name: d, mountPath: /data}]
    resources: {requests: {cpu: 10m, memory: 16Mi}}
  volumes: [{name: d, persistentVolumeClaim: {claimName: data}}]
YAML
kubectl wait -n $NS --for=condition=Ready pod/writer --timeout=6m >/dev/null
node=$(kubectl get pod writer -n $NS -o jsonpath='{.spec.nodeName}')
say "  Pod 를 붙이자: PVC $(kubectl get pvc data -n $NS -o jsonpath='{.status.phase}') · Pod Running $((SECONDS-t0))초 (노드가 없었으면 Auto Mode 가 만드는 시간 포함)"
say "    노드 $node · $(kubectl get node $node -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone} {.metadata.labels.node\.kubernetes\.io/instance-type}')"
vol=$(kubectl get pv "$(kubectl get pvc data -n $NS -o jsonpath='{.spec.volumeName}')" -o jsonpath='{.spec.csi.volumeHandle}')
aws ec2 describe-volumes --volume-ids "$vol" --query 'Volumes[0].[VolumeType,Size,Iops,Throughput,Encrypted,AvailabilityZone,State]' --output text \
 | awk -v v="${vol:0:8}" '{printf "    EBS %s… · %s %sGiB · IOPS %s · %sMiB/s · 암호화 %s · %s · %s\n", v,$1,$2,$3,$4,$5,$6,$7}'
say "    파일: $(kubectl exec -n $NS writer -- cat /data/hello)"
kubectl delete pod writer -n $NS --grace-period=1 --wait >/dev/null; kubectl delete pvc data -n $NS --wait >/dev/null
for i in $(seq 1 18); do s=$(aws ec2 describe-volumes --volume-ids "$vol" --query 'Volumes[0].State' --output text 2>/dev/null || echo 없음); [ "$s" = 없음 ] && break; sleep 5; done
say "  PVC 지운 뒤 EBS: $s  ← reclaimPolicy Delete (남는 디스크 없음)"
fi

if [ "${ONLY:-np}" != ebs ]; then
say "== B. NetworkPolicy (VPC CNI)"
kubectl run web -n $NS --image=$NG --labels=app=web --port=80 >/dev/null
kubectl expose pod web -n $NS --port=80 >/dev/null
kubectl run client -n $NS --image=$BB --labels=app=client --command -- sleep 600 >/dev/null
kubectl run stranger -n $NS --image=$BB --labels=app=stranger --command -- sleep 600 >/dev/null
kubectl wait -n $NS --for=condition=Ready pod/web pod/client pod/stranger --timeout=6m >/dev/null
try() { kubectl exec -n $NS "$1" -- wget -q -T 3 -O /dev/null http://web 2>/dev/null && echo 통과 || echo "막힘(시간 초과)"; }   # wget 오류 줄은 숨긴다 (4.2 첫 실행)
say "  ① 정책 없음      client → web: $(try client) · stranger → web: $(try stranger)"
kubectl apply -n $NS -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-ingress}
spec: {podSelector: {}, policyTypes: [Ingress]}
YAML
r=; for i in $(seq 1 10); do r=$(try client); [ "$r" != 통과 ] && break; sleep 3; done
say "  ② 기본 거부      client → web: $r · stranger → web: $(try stranger)"
kubectl apply -n $NS -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: web-from-client}
spec:
  podSelector: {matchLabels: {app: web}}
  policyTypes: [Ingress]
  ingress: [{from: [{podSelector: {matchLabels: {app: client}}}], ports: [{port: 80}]}]
YAML
r=; for i in $(seq 1 10); do r=$(try client); [ "$r" = 통과 ] && break; sleep 3; done
say "  ③ client 만 허용  client → web: $r · stranger → web: $(try stranger)"
fi
say "== 시험 namespace 지움 (노드는 Pod 가 없어지면 Auto Mode 가 몇 분 뒤 정리)"
