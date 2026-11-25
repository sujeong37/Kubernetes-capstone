# step4 공통 (source 해서 쓴다). WSL 에서 실행
#   계정 ID 는 화면 · 문서 · 스크린샷에 남기지 않는다 (평가 기준: 비밀 값 노출 -5) → mask 로 뒤 4자리만
REGION=${REGION:-ap-northeast-2}
PROJECT_TAG="Key=Project,Value=bus-capstone"
REPOS=(bus-app bus-web)

say()  { printf '%s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
mask() { local s=$1; printf '****%s' "${s: -4}"; }

need_aws() {
  command -v aws >/dev/null || die "aws CLI 가 없다 → bash infra/step4/install-aws-cli.sh"
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
    || die "AWS 인증 실패 → aws sts get-caller-identity 로 확인 (Windows ~/.aws 를 쓰는지: echo \$AWS_SHARED_CREDENTIALS_FILE)"
  REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
  REGISTRY_MASKED="$(mask "$ACCOUNT").dkr.ecr.$REGION.amazonaws.com"
  # 이 뒤로 스크립트의 모든 출력(오류 메시지 포함)에서 계정 ID 를 가린다.
  #   AWS 오류는 "... in the registry with id '<계정>'" 처럼 계정 ID 를 그대로 담는다 (4.0.2 에서 겪음)
  [ -n "${STEP4_MASKED:-}" ] || { export STEP4_MASKED=1; exec > >(sed -u "s/$ACCOUNT/$(mask "$ACCOUNT")/g") 2>&1; }
}
