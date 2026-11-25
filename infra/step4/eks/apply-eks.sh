#!/usr/bin/env bash
# step4.3 — (WSL) 3단계와 같은 web · app · db 를 EKS 에 배포하고 ALB 주소로 연다
#   bash apply-eks.sh --compare : 3단계(k8s/step3)와 EKS overlay 의 차이 = 「③에서 바꾼 값」 (클러스터에 안 닿음)
#   bash apply-eks.sh --diff    : 지금 클러스터와 바뀔 것
#   bash apply-eks.sh           : 적용 → rollout → ALB 준비 → /api/healthz 200 까지 → 배치 · EBS · ALB 요약
#   Git 의 overlay 에는 ACCOUNT_ID · MY_IP 자리 표시만 있다. 실행 때 채우고 화면에서는 둘 다 가린다.
#   발표 장소에서 인터넷(공인 IP)이 바뀌면 다시 실행 → ALB 허용 IP 만 바뀐다
set -euo pipefail
cd "$(dirname "$0")"; source ../lib.sh; need_aws
ROOT=$(cd ../../.. && pwd); CLUSTER=bus-eks; NS=bus
MYIP=$(curl -s -m 5 https://checkip.amazonaws.com | tr -d '[:space:]')
[[ "$MYIP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "내 공인 IP 를 못 얻음 (checkip.amazonaws.com)"
IPRE=${MYIP//./\\.}
exec > >(sed -u "s/$IPRE/<내 IP>/g") 2>&1     # 공인 IP 도 화면 · 스크린샷에 남기지 않는다
render_eks() { kubectl kustomize "$ROOT/k8s/overlays/eks" | sed -e "s/ACCOUNT_ID/$ACCOUNT/g" -e "s#MY_IP/32#$MYIP/32#" -e "s#gateway.k8s.aws/v1beta1#$GWV#"; }

if [ "${1:-}" = --compare ]; then
  say "== ③(k8s/step3) → ④(k8s/overlays/eks) 에서 바뀐 줄 (- 3단계, + EKS)"
  GWV=gateway.k8s.aws/v1beta1
  diff -u <(kubectl kustomize "$ROOT/k8s/step3") <(kubectl kustomize "$ROOT/k8s/overlays/eks") \
   | grep -E '^[-+]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[-+]\s*$' || true
  exit 0
fi

[ "$(kubectl config current-context)" = $CLUSTER ] || die "context 가 $CLUSTER 가 아니다"
GWV=$(kubectl api-versions | grep -xE 'gateway.k8s.aws/v1' || kubectl api-versions | grep -xE 'gateway.k8s.aws/v1beta1' || true)
[ -n "$GWV" ] || die "gateway.k8s.aws API 가 없다 → 4.2 setup-cluster.sh 먼저 (Gateway API 켜기)"
kubectl get storageclass ebs >/dev/null 2>&1 && kubectl get gatewayclass eks-alb >/dev/null 2>&1 && kubectl get secret bus-db -n $NS >/dev/null 2>&1 \
  || die "4.2 가 덜 됨 (StorageClass ebs · GatewayClass eks-alb · Secret bus-db 중 없음)"

if [ "${1:-}" = --diff ]; then render_eks | kubectl diff -f - | grep -E '^[-+] ' || true; exit 0; fi

say "== 적용 ($(date +%T)) · ALB 확장 API $GWV · 이미지 $(mask "$ACCOUNT").dkr.ecr…:$(awk '/newTag:/{print $2; exit}' "$ROOT/k8s/overlays/eks/kustomization.yaml")"
t0=$SECONDS
render_eks | kubectl apply -f - | sed 's/^/  /'
say "== rollout (노드가 없으면 Auto Mode 가 만든다 · db 는 EBS 를 만들어 붙인다)"
for d in db app web; do kubectl rollout status deploy/$d -n $NS --timeout=10m | tail -1 | sed "s/^/  /"; done
say "  Pod 준비 $((SECONDS-t0))초"
say "== ALB (Gateway → Programmed)"
kubectl wait --for=condition=Programmed gateway/bus -n $NS --timeout=10m >/dev/null
ADDR=$(kubectl get gateway bus -n $NS -o jsonpath='{.status.addresses[0].value}')
mkdir -p ~/.bus-step4 && echo "$ADDR" > ~/.bus-step4/alb
say "  주소 http://$ADDR  (~/.bus-step4/alb 에 저장) · Programmed $((SECONDS-t0))초"
for i in $(seq 1 72); do curl -s -m 3 "http://$ADDR/api/healthz" | grep -q '"ok"' && break; sleep 5; done
curl -s -m 3 "http://$ADDR/api/healthz" | grep -q '"ok"' || die "6분 안에 ALB 로 /api/healthz 가 안 됨 → Runbook 문제 해결"
say "  /api/healthz 200 · 적용부터 $((SECONDS-t0))초 (DNS 전파 · 대상 등록 포함)"

say "== 배치"
kubectl get pods -n $NS -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[0].ready,NODE:.spec.nodeName,IP:.status.podIP' | sed 's/^/  /'
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/nodepool --no-headers \
 | awk '{printf "  %-22s %-16s %-11s %-6s %s\n",$1,$6,$7,$8,$9}'
say "== DB 디스크"
pv=$(kubectl get pvc db-data -n $NS -o jsonpath='{.spec.volumeName}')
vol=$(kubectl get pv "$pv" -o jsonpath='{.spec.csi.volumeHandle}')
say "  PVC db-data $(kubectl get pvc db-data -n $NS -o jsonpath='{.status.phase} {.spec.storageClassName}') → $vol"
aws ec2 describe-volumes --volume-ids "$vol" --query 'Volumes[0].[VolumeType,Size,Encrypted,AvailabilityZone,State]' --output text | awk '{printf "  EBS %s %sGiB · 암호화 %s · %s · %s\n",$1,$2,$3,$4,$5}'
say "== ALB"
lb=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='$ADDR'].[LoadBalancerArn,Scheme,State.Code,join(',',AvailabilityZones[].ZoneName)]" --output text)
read -r LBARN scheme state zones <<<"$lb"
say "  $scheme · $state · $zones"
for sg in $(aws elbv2 describe-load-balancers --load-balancer-arns "$LBARN" --query 'LoadBalancers[0].SecurityGroups[]' --output text); do
  say "  보안 그룹 들어오는 규칙: $(aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions[].[FromPort,IpRanges[].CidrIp]' --output text | tr '\n\t' '  ')"
done
for tg in $(aws elbv2 describe-target-groups --load-balancer-arn "$LBARN" --query 'TargetGroups[].TargetGroupArn' --output text); do
  aws elbv2 describe-target-groups --target-group-arns "$tg" --query 'TargetGroups[0].[Port,TargetType,HealthCheckPath]' --output text \
   | awk -v h="$(aws elbv2 describe-target-health --target-group-arn "$tg" --query 'TargetHealthDescriptions[].TargetHealth.State' --output text)" \
     '{printf "  대상 그룹 포트 %s · %s · 상태 확인 %s · 대상 %s\n",$1,$2,$3,h}'
done
say "== 다음: SEARCH=북대전 STOP_ID=DJB8001795 STOP_NAME=KT북대전지사 WAIT=0 bash tests/scenario.sh http://\$(cat ~/.bus-step4/alb)"
