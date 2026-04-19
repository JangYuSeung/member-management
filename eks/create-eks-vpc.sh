#!/bin/bash

# =============================================
# STEP 1. VPC 생성
# =============================================

# eks 전용 VPC 생성 (CIDR: 10.1.0.0/16)
EKS_VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.1.0.0/16 \
  --region ap-south-2 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=st8-eks-VPC}]' \
  --query 'Vpc.VpcId' --output text)

# EKS 필수 설정 - DNS 활성화 (비활성화 시 노드가 클러스터에 등록 불가)
aws ec2 modify-vpc-attribute --vpc-id $EKS_VPC_ID --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $EKS_VPC_ID --enable-dns-hostnames

echo "✅ VPC 생성 완료: $EKS_VPC_ID"

# =============================================
# STEP 2. 서브넷 생성 (퍼블릭 3개 + 프라이빗 3개)
# =============================================

# 퍼블릭 서브넷 - ALB가 배치될 영역 (각 AZ마다 1개씩)
SUBNET_PUB_A=$(aws ec2 create-subnet \
  --vpc-id $EKS_VPC_ID --cidr-block 10.1.1.0/24 \
  --availability-zone ap-south-2a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-subnet-2a}]' \
  --query 'Subnet.SubnetId' --output text)

SUBNET_PUB_B=$(aws ec2 create-subnet \
  --vpc-id $EKS_VPC_ID --cidr-block 10.1.2.0/24 \
  --availability-zone ap-south-2b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-subnet-2b}]' \
  --query 'Subnet.SubnetId' --output text)

SUBNET_PUB_C=$(aws ec2 create-subnet \
  --vpc-id $EKS_VPC_ID --cidr-block 10.1.3.0/24 \
  --availability-zone ap-south-2c \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-pub-subnet-2c}]' \
  --query 'Subnet.SubnetId' --output text)

# 퍼블릭 서브넷에 퍼블릭 IP 자동 할당 (인터넷 통신용)
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB_A --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB_B --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB_C --map-public-ip-on-launch

# 프라이빗 서브넷 - 실제 노드(EC2)가 배치될 영역 (외부 직접 접근 차단)
SUBNET_PRI_A=$(aws ec2 create-subnet \
  --vpc-id $EKS_VPC_ID --cidr-block 10.1.11.0/24 \
  --availability-zone ap-south-2a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-pri-subnet-2a}]' \
  --query 'Subnet.SubnetId' --output text)

SUBNET_PRI_B=$(aws ec2 create-subnet \
  --vpc-id $EKS_VPC_ID --cidr-block 10.1.12.0/24 \
  --availability-zone ap-south-2b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-pri-subnet-2b}]' \
  --query 'Subnet.SubnetId' --output text)

SUBNET_PRI_C=$(aws ec2 create-subnet \
  --vpc-id $EKS_VPC_ID --cidr-block 10.1.13.0/24 \
  --availability-zone ap-south-2c \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-pri-subnet-2c}]' \
  --query 'Subnet.SubnetId' --output text)

echo "✅ 서브넷 생성 완료"

# =============================================
# STEP 3. IGW 생성 및 퍼블릭 RT 설정
# =============================================

# IGW - VPC와 인터넷 간의 통신 게이트웨이
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=eks-IGW}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)

# IGW를 VPC에 연결
aws ec2 attach-internet-gateway --vpc-id $EKS_VPC_ID --internet-gateway-id $IGW_ID

# 퍼블릭 RT 생성 - 인터넷(0.0.0.0/0) 트래픽을 IGW로 라우팅
PUB_RT_ID=$(aws ec2 create-route-table \
  --vpc-id $EKS_VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=eks-RT}]' \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route \
  --route-table-id $PUB_RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

# 퍼블릭 서브넷 3개를 퍼블릭 RT에 연결
aws ec2 associate-route-table --route-table-id $PUB_RT_ID --subnet-id $SUBNET_PUB_A
aws ec2 associate-route-table --route-table-id $PUB_RT_ID --subnet-id $SUBNET_PUB_B
aws ec2 associate-route-table --route-table-id $PUB_RT_ID --subnet-id $SUBNET_PUB_C

echo "✅ IGW 및 퍼블릭 RT 설정 완료"

# =============================================
# STEP 4. NAT GW 생성 및 프라이빗 RT 설정
# =============================================

# EIP 할당 - NAT GW에 고정 퍼블릭 IP 부여
EIP_ALLOC=$(aws ec2 allocate-address \
  --domain vpc \
  --query 'AllocationId' --output text)

# NAT GW 생성 - 프라이빗 서브넷의 노드가 인터넷(ECR 등) 접근 시 사용
# 퍼블릭 서브넷 2a에 배치 (AZ당 1개면 충분, 비용 절감)
NAT_GW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id $SUBNET_PUB_A \
  --allocation-id $EIP_ALLOC \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=eks-NAT}]' \
  --query 'NatGateway.NatGatewayId' --output text)

# NAT GW 활성화 대기 (약 1~2분)
echo "NAT GW 활성화 대기 중..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID
echo "✅ NAT GW 활성화 완료: $NAT_GW_ID"

# 프라이빗 RT 각 AZ마다 1개씩 생성
# (AZ별로 분리하는 이유: NAT GW 장애 시 해당 AZ만 영향받도록)
PRI_RT_A=$(aws ec2 create-route-table \
  --vpc-id $EKS_VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=eks-pri-RT-2a}]' \
  --query 'RouteTable.RouteTableId' --output text)

PRI_RT_B=$(aws ec2 create-route-table \
  --vpc-id $EKS_VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=eks-pri-RT-2b}]' \
  --query 'RouteTable.RouteTableId' --output text)

PRI_RT_C=$(aws ec2 create-route-table \
  --vpc-id $EKS_VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=eks-pri-RT-2c}]' \
  --query 'RouteTable.RouteTableId' --output text)

# 프라이빗 RT에 NAT GW 라우트 추가
# 인터넷 트래픽 → NAT GW → IGW → 인터넷 (단방향, 외부에서 직접 접근 불가)
aws ec2 create-route --route-table-id $PRI_RT_A \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID
aws ec2 create-route --route-table-id $PRI_RT_B \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID
aws ec2 create-route --route-table-id $PRI_RT_C \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID

# 각 프라이빗 서브넷을 해당 AZ의 RT에 연결
aws ec2 associate-route-table --route-table-id $PRI_RT_A --subnet-id $SUBNET_PRI_A
aws ec2 associate-route-table --route-table-id $PRI_RT_B --subnet-id $SUBNET_PRI_B
aws ec2 associate-route-table --route-table-id $PRI_RT_C --subnet-id $SUBNET_PRI_C

echo "✅ NAT GW 및 프라이빗 RT 설정 완료"
echo ""
echo "=== 생성된 리소스 ID 정리 ==="
echo "VPC:          $EKS_VPC_ID"
echo "PUB_RT:       $PUB_RT_ID"
echo "SUBNET_PUB_A: $SUBNET_PUB_A"
echo "SUBNET_PUB_B: $SUBNET_PUB_B"
echo "SUBNET_PUB_C: $SUBNET_PUB_C"
echo "SUBNET_PRI_A: $SUBNET_PRI_A"
echo "SUBNET_PRI_B: $SUBNET_PRI_B"
echo "SUBNET_PRI_C: $SUBNET_PRI_C"
echo "IGW:          $IGW_ID"
echo "NAT_GW:       $NAT_GW_ID"