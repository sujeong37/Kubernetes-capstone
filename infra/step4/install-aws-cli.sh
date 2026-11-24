#!/usr/bin/env bash
# step4.0.1 — WSL 에 AWS CLI v2 설치 + Windows 의 자격 증명(~/.aws)을 그대로 쓰게 한다
#   3단계까지 AWS 는 PowerShell 에서만 썼다. 4단계는 WSL 에서 docker push(ECR 로그인) · kubectl(EKS) 을 하므로
#   WSL 에도 aws 가 필요하다. 키를 복사하지 않고 Windows 파일을 가리키게 한다 (키는 한 곳에만)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if ! command -v aws >/dev/null; then
  say "== AWS CLI v2 설치"
  tmp=$(mktemp -d)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmp/awscliv2.zip"
  command -v unzip >/dev/null || sudo apt-get install -y unzip >/dev/null
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  sudo "$tmp/aws/install" >/dev/null
  rm -rf "$tmp"
fi
say "== $(aws --version)"

WINHOME=$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")
[ -f "$WINHOME/.aws/credentials" ] || die "$WINHOME/.aws/credentials 없음 (Windows 에서 aws configure 했는지)"
if ! grep -q AWS_SHARED_CREDENTIALS_FILE ~/.bashrc; then
  cat >> ~/.bashrc <<RC
# step4 — Windows 의 AWS 설정 · 자격 증명을 그대로 사용 (키 복사 없음)
export AWS_CONFIG_FILE="$WINHOME/.aws/config"
export AWS_SHARED_CREDENTIALS_FILE="$WINHOME/.aws/credentials"
export AWS_DEFAULT_REGION=$REGION
RC
  say "== ~/.bashrc 에 AWS_CONFIG_FILE · AWS_SHARED_CREDENTIALS_FILE 추가 (새 터미널 또는 source ~/.bashrc)"
fi
export AWS_CONFIG_FILE="$WINHOME/.aws/config" AWS_SHARED_CREDENTIALS_FILE="$WINHOME/.aws/credentials" AWS_DEFAULT_REGION=$REGION

need_aws
ARN=$(aws sts get-caller-identity --query Arn --output text)
say "== 인증 OK: 계정 $(mask "$ACCOUNT") · 사용자 ${ARN##*/} · 리전 $REGION"
