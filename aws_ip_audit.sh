#!/bin/bash
###############################################################################
#  AWS IP Audit Script — Procafecol INC42131099
#  Objetivo: Listar TODAS las IPs públicas y privadas de una cuenta AWS,
#            identificar a qué servicio pertenecen, y buscar IPs específicas.
#
#  Uso:
#    chmod +x aws_ip_audit.sh
#
#    # Escanear TODAS las regiones:
#    ./aws_ip_audit.sh
#
#    # Escanear solo una región:
#    ./aws_ip_audit.sh us-east-1
#
#    # Buscar IPs específicas (separadas por coma):
#    SEARCH_IPS="34.197.231.195,34.228.175.248" ./aws_ip_audit.sh
#
#    # Combinado:
#    SEARCH_IPS="34.197.231.195,34.228.175.248" ./aws_ip_audit.sh us-east-1
###############################################################################

set -euo pipefail

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Config ---
SEARCH_IPS="${SEARCH_IPS:-34.197.231.195,34.228.175.248}"
SINGLE_REGION="${1:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="aws_ip_audit_${TIMESTAMP}.csv"
SUMMARY_FILE="aws_ip_audit_summary_${TIMESTAMP}.txt"

# --- Cabecera del CSV ---
echo "Region,Service,ResourceId,ResourceName,PublicIP,PrivateIP,Description" > "$REPORT_FILE"

# --- Funciones auxiliares ---
log_section() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_info() {
    echo -e "  ${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

log_match() {
    echo -e "  ${RED}🔴 MATCH ENCONTRADO: $1${NC}"
}

add_to_report() {
    # $1=region $2=service $3=resourceId $4=name $5=publicIp $6=privateIp $7=description
    echo "\"$1\",\"$2\",\"$3\",\"$4\",\"$5\",\"$6\",\"$7\"" >> "$REPORT_FILE"
}

check_ip_match() {
    local ip="$1"
    local context="$2"
    if [ -z "$ip" ] || [ "$ip" = "null" ] || [ "$ip" = "None" ]; then
        return
    fi
    IFS=',' read -ra TARGETS <<< "$SEARCH_IPS"
    for target in "${TARGETS[@]}"; do
        if [ "$ip" = "$target" ]; then
            log_match "$ip encontrada en: $context"
            echo "*** MATCH: $ip -> $context" >> "$SUMMARY_FILE"
        fi
    done
}

# --- Obtener identidad de la cuenta ---
log_section "INFORMACIÓN DE LA CUENTA"
ACCOUNT_INFO=$(aws sts get-caller-identity 2>/dev/null || echo "{}")
ACCOUNT_ID=$(echo "$ACCOUNT_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Account','N/A'))" 2>/dev/null || echo "N/A")
ACCOUNT_ARN=$(echo "$ACCOUNT_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Arn','N/A'))" 2>/dev/null || echo "N/A")
echo -e "  Account ID : ${BOLD}${ACCOUNT_ID}${NC}"
echo -e "  ARN        : ${ACCOUNT_ARN}"
echo -e "  IPs a buscar: ${RED}${SEARCH_IPS}${NC}"
echo -e "  Reporte    : ${REPORT_FILE}"

echo "=== AWS IP Audit Report ===" > "$SUMMARY_FILE"
echo "Account: $ACCOUNT_ID" >> "$SUMMARY_FILE"
echo "Fecha: $(date)" >> "$SUMMARY_FILE"
echo "IPs buscadas: $SEARCH_IPS" >> "$SUMMARY_FILE"
echo "========================================" >> "$SUMMARY_FILE"

# --- Determinar regiones ---
if [ -n "$SINGLE_REGION" ]; then
    REGIONS=("$SINGLE_REGION")
    echo -e "  Región     : ${BOLD}${SINGLE_REGION}${NC} (especificada manualmente)"
else
    echo -e "  Modo       : ${BOLD}TODAS LAS REGIONES${NC}"
    mapfile -t REGIONS < <(aws ec2 describe-regions --query 'Regions[].RegionName' --output text | tr '\t' '\n' | sort)
    echo -e "  Regiones   : ${#REGIONS[@]} encontradas"
fi

# --- Contador global ---
TOTAL_IPS=0
TOTAL_MATCHES=0

###############################################################################
#  LOOP POR REGIÓN
###############################################################################
for REGION in "${REGIONS[@]}"; do

    log_section "REGIÓN: $REGION"
    REGION_COUNT=0

    #--------------------------------------------------------------------------
    # 1. EC2 INSTANCES
    #--------------------------------------------------------------------------
    echo -e "\n  ${BOLD}[1/10] EC2 Instances${NC}"
    EC2_DATA=$(aws ec2 describe-instances \
        --region "$REGION" \
        --query 'Reservations[].Instances[].{
            Id:InstanceId,
            Name:Tags[?Key==`Name`]|[0].Value,
            PublicIp:PublicIpAddress,
            PrivateIp:PrivateIpAddress,
            State:State.Name,
            Type:InstanceType
        }' \
        --output json 2>/dev/null || echo "[]")

    EC2_COUNT=$(echo "$EC2_DATA" | python3 -c "
import sys,json
instances = json.load(sys.stdin)
for i in instances:
    pub = i.get('PublicIp') or ''
    priv = i.get('PrivateIp') or ''
    name = i.get('Name') or 'sin-nombre'
    iid = i.get('Id') or ''
    state = i.get('State') or ''
    itype = i.get('Type') or ''
    desc = f'State={state}, Type={itype}'
    print(f'{pub}|{priv}|{iid}|{name}|{desc}')
count = len(instances)
import os
" 2>/dev/null || echo "")

    ec2_n=0
    while IFS='|' read -r pub priv iid name desc; do
        [ -z "$iid" ] && continue
        ec2_n=$((ec2_n + 1))
        add_to_report "$REGION" "EC2" "$iid" "$name" "$pub" "$priv" "$desc"
        check_ip_match "$pub" "EC2 $iid ($name) en $REGION"
        check_ip_match "$priv" "EC2 $iid ($name) en $REGION [privada]"
    done <<< "$EC2_COUNT"
    log_info "Instancias encontradas: $ec2_n"
    REGION_COUNT=$((REGION_COUNT + ec2_n))

    #--------------------------------------------------------------------------
    # 2. ELASTIC IPs
    #--------------------------------------------------------------------------
    echo -e "\n  ${BOLD}[2/10] Elastic IPs${NC}"
    EIP_DATA=$(aws ec2 describe-addresses \
        --region "$REGION" \
        --query 'Addresses[].{
            PublicIp:PublicIp,
            PrivateIp:PrivateIpAddress,
            AllocId:AllocationId,
            AssocId:AssociationId,
            InstanceId:InstanceId,
            NetIfId:NetworkInterfaceId
        }' \
        --output json 2>/dev/null || echo "[]")

    eip_n=0
    while IFS='|' read -r pub priv allocid instid netid; do
        [ -z "$allocid" ] && continue
        eip_n=$((eip_n + 1))
        assoc="Instance=$instid, ENI=$netid"
        add_to_report "$REGION" "ElasticIP" "$allocid" "" "$pub" "$priv" "$assoc"
        check_ip_match "$pub" "Elastic IP $allocid (asociada a $instid) en $REGION"
    done < <(echo "$EIP_DATA" | python3 -c "
import sys,json
for a in json.load(sys.stdin):
    pub=a.get('PublicIp') or ''
    priv=a.get('PrivateIp') or ''
    alloc=a.get('AllocId') or ''
    inst=a.get('InstanceId') or 'ninguna'
    net=a.get('NetIfId') or ''
    print(f'{pub}|{priv}|{alloc}|{inst}|{net}')
" 2>/dev/null)
    log_info "Elastic IPs encontradas: $eip_n"
    REGION_COUNT=$((REGION_COUNT + eip_n))

    #--------------------------------------------------------------------------
    # 3. NAT GATEWAYS
    #--------------------------------------------------------------------------
    echo -e "\n  ${BOLD}[3/10] NAT Gateways${NC}"
    NAT_DATA=$(aws ec2 describe-nat-gateways \
        --region "$REGION" \
        --filter "Name=state,Values=available,pending" \
        --query 'NatGateways[].{
            Id:NatGatewayId,
            Addresses:NatGatewayAddresses,
            VpcId:VpcId,
            SubnetId:SubnetId,
            Tags:Tags
        }' \
        --output json 2>/dev/null || echo "[]")

    nat_n=0
    while IFS='|' read -r natid pub priv vpcid; do
        [ -z "$natid" ] && continue
        nat_n=$((nat_n + 1))
        add_to_report "$REGION" "NATGateway" "$natid" "" "$pub" "$priv" "VPC=$vpcid"
        check_ip_match "$pub" "NAT Gateway $natid (VPC=$vpcid) en $REGION"
    done < <(echo "$NAT_DATA" | python3 -c "
import sys,json
for n in json.load(sys.stdin):
    nid=n.get('Id','')
    vpc=n.get('VpcId','')
    for addr in n.get('Addresses',[]):
        pub=addr.get('PublicIp','')
        priv=addr.get('PrivateIpAddress','')
        print(f'{nid}|{pub}|{priv}|{vpc}')
" 2>/dev/null)
    log_info "NAT Gateways encontrados: $nat_n"
    REGION_COUNT=$((REGION_COUNT + nat_n))

    #--------------------------------------------------------------------------
    # 4. NETWORK INTERFACES (ENIs) — captura todo lo que tenga IP pública
    #--------------------------------------------------------------------------
    echo -e "\n  ${BOLD}[4/10] Network Interfaces (ENIs con IP pública)${NC}"
    ENI_DATA=$(aws ec2 describe-network-interfaces \
        --region "$REGION" \
        --query 'NetworkInterfaces[?Association.PublicIp!=`null`].{
            Id:NetworkInterfaceId,
            PublicIp:Association.PublicIp,
            PrivateIp:PrivateIpAddress,
            Desc:Description,
            AttachInstance:Attachment.InstanceId,
            InterfaceType:InterfaceType
        }' \
        --output json 2>/dev/null || echo "[]")

    eni_n=0
    while IFS='|' read -r eniid pub priv desc attinst iftype; do
        [ -z "$eniid" ] && continue
        eni_n=$((eni_n + 1))
        add_to_report "$REGION" "ENI" "$eniid" "" "$pub" "$priv" "Type=$iftype, Attached=$attinst, $desc"
        check_ip_match "$pub" "ENI $eniid ($desc) en $REGION"
    done < <(echo "$ENI_DATA" | python3 -c "
import sys,json
for e in json.load(sys.stdin):
    eid=e.get('Id','')
    pub=e.get('PublicIp','')
    priv=e.get('PrivateIp','')
    desc=e.get('Desc','')
    att=e.get('AttachInstance') or 'ninguna'
    ift=e.get('InterfaceType','')
    print(f'{eid}|{pub}|{priv}|{desc}|{att}|{ift}')
" 2>/dev/null)
    log_info "ENIs con IP pública: $eni_n"
    REGION_COUNT=$((REGION_COUNT + eni_n))

    #--------------------------------------------------------------------------
    # 5. EKS CLUSTERS
    #--------------------------------------------------------------------------
    echo -e "\n  ${BOLD}[5/10] EKS Clusters${NC}"
    EKS_CLUSTERS=$(aws eks list-clusters \
        --region "$REGION" \
        --query 'clusters[]' \
        --output text 2>/dev/null || echo "")

    if [ -z "$EKS_CLUSTERS" ]; then
        log_info "No hay clústeres EKS en esta región"
    else
        for CLUSTER in $EKS_CLUSTERS; do
            echo -e "    ${YELLOW}→ Clúster: ${BOLD}$CLUSTER${NC}"

            # Info del clúster
            CLUSTER_INFO=$(aws eks describe-cluster \
                --region "$REGION" \
                --name "$CLUSTER" \
                --query 'cluster.{
                    Endpoint:endpoint,
                    VpcId:resourcesVpcConfig.vpcId,
                    SubnetIds:resourcesVpcConfig.subnetIds,
                    SecurityGroups:resourcesVpcConfig.securityGroupIds,
                    PublicAccess:resourcesVpcConfig.endpointPublicAccess
                }' \
                --output json 2>/dev/null || echo "{}")

            CLUSTER_VPC=$(echo "$CLUSTER_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('VpcId',''))" 2>/dev/null || echo "")
            CLUSTER_ENDPOINT=$(echo "$CLUSTER_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Endpoint',''))" 2>/dev/null || echo "")
            echo -e "      VPC: $CLUSTER_VPC"
            echo -e "      Endpoint: $CLUSTER_ENDPOINT"
            add_to_report "$REGION" "EKS-Cluster" "$CLUSTER" "" "" "" "VPC=$CLUSTER_VPC, Endpoint=$CLUSTER_ENDPOINT"

            # Nodos del clúster (EC2 con tag del clúster)
            CLUSTER_NODES=$(aws ec2 describe-instances \
                --region "$REGION" \
                --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned,shared" \
                --query 'Reservations[].Instances[].{
                    Id:InstanceId,
                    Name:Tags[?Key==`Name`]|[0].Value,
                    PublicIp:PublicIpAddress,
                    PrivateIp:PrivateIpAddress
                }' \
                --output json 2>/dev/null || echo "[]")

            node_n=0
            while IFS='|' read -r nid nname npub npriv; do
                [ -z "$nid" ] && continue
                node_n=$((node_n + 1))
                add_to_report "$REGION" "EKS-Node($CLUSTER)" "$nid" "$nname" "$npub" "$npriv" "Nodo del clúster $CLUSTER"
                check_ip_match "$npub" "EKS Node $nid ($nname) del clúster $CLUSTER en $REGION"
            done < <(echo "$CLUSTER_NODES" | python3 -c "
import sys,json
for n in json.load(sys.stdin):
    print(f'{n.get(\"Id\",\"\")}'
          f'|{n.get(\"Name\",\"sin-nombre\")}'
          f'|{n.get(\"PublicIp\",\"\")}'
          f'|{n.get(\"PrivateIp\",\"\")}')
" 2>/dev/null)
            echo -e "      Nodos encontrados: $node_n"

            # Fargate profiles
            FARGATE_PROFILES=$(aws eks list-fargate-profiles \
                --region "$REGION" \
                --cluster-name "$CLUSTER" \
                --query 'fargateProfileNames[]' \
                --output text 2>/dev/null || echo "")

            if [ -n "$FARGATE_PROFILES" ]; then
                echo -e "      ${YELLOW}Fargate Profiles: $FARGATE_PROFILES${NC}"
                echo -e "      ${YELLOW}(Fargate usa IPs efímeras del pool de AWS — no rastreables)${NC}"
                add_to_report "$REGION" "EKS-Fargate($CLUSTER)" "$FARGATE_PROFILES" "" "EFÍMERAS" "" "Las IPs de Fargate son del pool de AWS"
            fi

            # Nodegroups
            NODEGROUPS=$(aws eks list-nodegroups \
                --region "$REGION" \
                --cluster-name "$CLUSTER" \
                --query 'nodegroups[]' \
                --output text 2>/dev/null || echo "")

            if [ -n "$NODEGROUPS" ]; then
                for NG in $NODEGROUPS; do
                    NG_INFO=$(aws eks describe-nodegroup \
                        --region "$REGION" \
                        --cluster-name "$CLUSTER" \
                        --nodegroup-name "$NG" \
                        --query 'nodegroup.{
                            Status:status,
                            CapType:capacityType,
                            AmiType:amiType,
                            DesiredSize:scalingConfig.desiredSize
                        }' \
                        --output json 2>/dev/null || echo "{}")
                    echo -e "      Nodegroup: $NG -> $(echo $NG_INFO | python3 -c "import sys,json;d=json.load(sys.stdin);print(f'Status={d.get(\"Status\",\"?\")}, Capacity={d.get(\"CapType\",\"?\")}, Desired={d.get(\"DesiredSize\",\"?\")}')" 2>/dev/null)"
                    add_to_report "$REGION" "EKS-Nodegroup($CLUSTER)" "$NG" "" "" "" "$(echo $NG_INFO)"
                done
            fi
        done
    fi

    #--------------------------------------------------------------------------
    # 6. LOAD BALANCERS (ALB/NLB + Classic)
    #--------------------------------------------------------------------------
    echo -e "\n  ${BOLD}[6/10] Load Balancers (ALB/NLB)${NC}"
    ELBV2_DATA=$(aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --query 'LoadBalancers[].{
            Arn:LoadBalancerArn,
            Name:LoadBalancerName,
            DNSName:DNSName,
            Type:Type,
            Scheme:Scheme,
            VpcId:VpcId
        }' \
        --output json 2>/dev/null || echo "[]")

    elbv2_n=0
    while IFS='|' read -r lbname lbdns lbtype lbscheme lbvpc; do
        [ -z "$lbname" ] && continue
        elbv2_n=$((elbv2_n + 1))
        add_to_report "$REGION" "ELBv2-$lbtype" "$lbname" "$lbname" "DNS:$lbdns" "" "Scheme=$lbscheme, VPC=$lbvpc"
        # Resolver DNS para ver IPs
        if command -v dig &>/dev/null && [ -n "$lbdns" ]; then
            LB_IPS=$(dig +short "$lbdns" 2>/dev/null | head -5 || echo "")
            if [ -n "$LB_IPS" ]; then
                for lbip in $LB_IPS; do
                    check_ip_match "$lbip" "Load Balancer $lbname ($lbdns) en $REGION"
                done
            fi
        fi
    done < <(echo "$ELBV2_DATA" | python3 -c "
import sys,json
for lb in json.load(sys.stdin):
    print(f'{lb.get(\"Name\",\"\")}'
          f'|{lb.get(\"DNSName\",\"\")}'
          f'|{lb.get(\"Type\",\"\")}'
          f'|{lb.get(\"Scheme\",\"\")}'
          f'|{lb.get(\"VpcId\",\"\")}')
" 2>/dev/null)
    log_info "ALB/NLB encontrados: $elbv2_n"

    echo -e "\n  ${BOLD}[6b/10] Load Balancers (Classic)${NC}"
    CLB_DATA=$(aws elb describe-load-balancers \
        --region "$REGION" \
        --query 'LoadBalancerDescriptions[].{
            Name:LoadBalancerName,
            DNSName:DNSName,
            VpcId:VPCId
        }' \
        --output json 2>/dev/null || echo "[]")

    clb_n=0
    while IFS='|' read -r clbname clbdns clbvpc; do
        [ -z "$clbname" ] && continue
        clb_n=$((clb_n + 1))
        add_to_report "$REGION" "CLB" "$clbname" "$clbname" "DNS:$clbdns" "" "VPC=$clbvpc"
    done < <(echo "$CLB_DATA" | python3 -c "
import sys,json
for lb in json.load(sys.stdin):
    print(f'{lb.get(\"Name\",\"\")}'
          f'|{lb.get(\"DNSName\",\"\")}'
          f'|{lb.get(\"VpcId\",\"\")}')
" 2>/dev/null)
    log_info "Classic LB encontrados: $clb_n"

    #--------------------------------------------------------------------------
    # 7. LAMBDA FUNCTIONS (con VPC config)
    #--------------------------------------------------------------------------
    echo -e "\n  ${BOLD}[7/10] Lambda Functions${NC}"
    LAMBDA_DATA=$(aws lambda list-functions \
        --region "$REGION" \
        --query 'Functions[].{
            Name:FunctionName,
            Arn:FunctionArn,
            VpcId:VpcConfig.VpcId,
            SubnetIds:VpcConfig.SubnetIds
        }' \
        --output json 2>/dev/null || echo "[]")

    lambda_n=0
    lambda_vpc_n=0
    while IFS='|' read -r fname fvpc fsubnets; do
        [ -z "$fname" ] && continue
        lambda_n=$((lambda_n + 1))
        if [ -n "$fvpc" ] && [ "$fvpc" != "None" ] && [ "$fvpc" != "" ]; then
            lambda_vpc_n=$((lambda_vpc_n + 1))
            add_to_report "$REGION" "Lambda(VPC)" "$fname" "$fname" "VíaNATGW" "" "VPC=$fvpc, Subnets=$fsubnets"
        else
            add_to_report "$REGION" "Lambda(NoVPC)" "$fname" "$fname" "EFÍMERAS" "" "Sin VPC — IPs del pool AWS"
        fi
    done < <(echo "$LAMBDA_DATA" | python3 -c "
import sys,json
for f in json.load(sys.stdin):
    vpc = f.get('VpcId') or ''
    subs = ','.join(f.get('SubnetIds') or [])
    print(f'{f.get(\"Name\",\"\")}'
          f'|{vpc}'
          f'|{subs}')
" 2>/dev/null)
    log_info "Lambdas totales: $lambda_n (en VPC: $lambda_vpc_n, sin VPC: $((lambda_n - lambda_vpc_n)))"
    if [ $((lambda_n - lambda_vpc_n)) -gt 0 ]; then
        log_warn "Lambdas sin VPC usan IPs efímeras del pool de AWS — podrían ser origen del tráfico"
    fi

    #--------------------------------------------------------------------------
    # 8. RDS INSTANCES
    #--------------------------------------------------------------------------
    echo -e "\n  ${BOLD}[8/10] RDS Instances${NC}"
    RDS_DATA=$(aws rds describe-db-instances \
        --region "$REGION" \
        --query 'DBInstances[].{
            Id:DBInstanceIdentifier,
            Endpoint:Endpoint.Address,
            Port:Endpoint.Port,
            Engine:Engine,
            Public:PubliclyAccessible,
            VpcId:DBSubnetGroup.VpcId
        }' \
        --output json 2>/dev/null || echo "[]")

    rds_n=0
    while IFS='|' read -r rdsid rdsep rdspub rdsvpc rdsengine; do
        [ -z "$rdsid" ] && continue
        rds_n=$((rds_n + 1))
        pubflag=""
        [ "$rdspub" = "True" ] && pubflag="PÚBLICO"
        add_to_report "$REGION" "RDS" "$rdsid" "$rdsid" "DNS:$rdsep" "" "Engine=$rdsengine, Public=$rdspub, VPC=$rdsvpc"
    done < <(echo "$RDS_DATA" | python3 -c "
import sys,json
for r in json.load(sys.stdin):
    print(f'{r.get(\"Id\",\"\")}'
          f'|{r.get(\"Endpoint\",\"\")}'
          f'|{r.get(\"Public\",\"\")}'
          f'|{r.get(\"VpcId\",\"\")}'
          f'|{r.get(\"Engine\",\"\")}')
" 2>/dev/null)
    log_info "RDS Instances: $rds_n"

    #--------------------------------------------------------------------------
    # 9. CLOUDFRONT DISTRIBUTIONS
    #--------------------------------------------------------------------------
    # CloudFront es global, solo correr en us-east-1 o primera región
    if [ "$REGION" = "us-east-1" ] || [ "$REGION" = "${REGIONS[0]}" ]; then
        echo -e "\n  ${BOLD}[9/10] CloudFront Distributions (global)${NC}"
        CF_DATA=$(aws cloudfront list-distributions \
            --query 'DistributionList.Items[].{
                Id:Id,
                Domain:DomainName,
                Origins:Origins.Items[].DomainName,
                Status:Status
            }' \
            --output json 2>/dev/null || echo "[]")

        cf_n=0
        if [ "$CF_DATA" != "[]" ] && [ "$CF_DATA" != "null" ] && [ -n "$CF_DATA" ]; then
            while IFS='|' read -r cfid cfdomain cforigins; do
                [ -z "$cfid" ] && continue
                cf_n=$((cf_n + 1))
                add_to_report "global" "CloudFront" "$cfid" "$cfdomain" "CDN" "" "Origins=$cforigins"
            done < <(echo "$CF_DATA" | python3 -c "
import sys,json
data = json.load(sys.stdin)
if data:
    for d in data:
        origins = ','.join(d.get('Origins',[]) or [])
        print(f'{d.get(\"Id\",\"\")}'
              f'|{d.get(\"Domain\",\"\")}'
              f'|{origins}')
" 2>/dev/null)
        fi
        log_info "CloudFront Distributions: $cf_n"
    fi

    #--------------------------------------------------------------------------
    # 10. VPC ENDPOINTS / GLOBAL ACCELERATOR
    #--------------------------------------------------------------------------
    echo -e "\n  ${BOLD}[10/10] Otros servicios con IPs${NC}"

    # Global Accelerator (solo en us-west-2)
    if [ "$REGION" = "us-west-2" ] || [ "$REGION" = "${REGIONS[0]}" ]; then
        GA_DATA=$(aws globalaccelerator list-accelerators \
            --region us-west-2 \
            --query 'Accelerators[].{
                Name:Name,
                IPs:IpSets[].IpAddresses[]
            }' \
            --output json 2>/dev/null || echo "[]")

        ga_n=0
        if [ "$GA_DATA" != "[]" ] && [ -n "$GA_DATA" ]; then
            while IFS='|' read -r ganame gaips; do
                [ -z "$ganame" ] && continue
                ga_n=$((ga_n + 1))
                add_to_report "global" "GlobalAccelerator" "$ganame" "$ganame" "$gaips" "" ""
                for gaip in $(echo "$gaips" | tr ',' ' '); do
                    check_ip_match "$gaip" "Global Accelerator $ganame"
                done
            done < <(echo "$GA_DATA" | python3 -c "
import sys,json
for g in json.load(sys.stdin):
    ips=[]
    for ipset in (g.get('IPs') or []):
        if isinstance(ipset, list):
            ips.extend(ipset)
        else:
            ips.append(str(ipset))
    print(f'{g.get(\"Name\",\"\")}|{\",\".join(ips)}')
" 2>/dev/null)
        fi
        log_info "Global Accelerators: $ga_n"
    fi

    # API Gateways
    APIGW_DATA=$(aws apigateway get-rest-apis \
        --region "$REGION" \
        --query 'items[].{Name:name,Id:id}' \
        --output json 2>/dev/null || echo "[]")

    apigw_n=$(echo "$APIGW_DATA" | python3 -c "import sys,json;print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
    if [ "$apigw_n" -gt 0 ]; then
        log_info "API Gateways: $apigw_n (usan IPs del pool de AWS)"
        while IFS='|' read -r agname agid; do
            [ -z "$agid" ] && continue
            add_to_report "$REGION" "APIGateway" "$agid" "$agname" "EFÍMERAS" "" "IPs del pool AWS"
        done < <(echo "$APIGW_DATA" | python3 -c "
import sys,json
for a in json.load(sys.stdin):
    print(f'{a.get(\"Name\",\"\")}'
          f'|{a.get(\"Id\",\"\")}')
" 2>/dev/null)
    else
        log_info "API Gateways: 0"
    fi

    TOTAL_IPS=$((TOTAL_IPS + REGION_COUNT))
    echo -e "\n  ${BOLD}Recursos con IP en $REGION: $REGION_COUNT${NC}"

done  # fin del loop de regiones

###############################################################################
#  RESUMEN FINAL
###############################################################################
log_section "RESUMEN FINAL"
echo -e "  Cuenta AWS     : ${BOLD}${ACCOUNT_ID}${NC}"
echo -e "  Regiones        : ${#REGIONS[@]}"
echo -e "  Total recursos  : ${BOLD}${TOTAL_IPS}${NC}"
echo -e "  Reporte CSV     : ${GREEN}${REPORT_FILE}${NC}"
echo -e "  Resumen         : ${GREEN}${SUMMARY_FILE}${NC}"

# Verificar matches
echo "" >> "$SUMMARY_FILE"
MATCH_COUNT=$(grep -c "MATCH" "$SUMMARY_FILE" 2>/dev/null || echo 0)
if [ "$MATCH_COUNT" -gt 0 ]; then
    echo -e "\n  ${RED}${BOLD}🔴 SE ENCONTRARON $MATCH_COUNT COINCIDENCIAS:${NC}"
    grep "MATCH" "$SUMMARY_FILE" | while read -r line; do
        echo -e "     ${RED}$line${NC}"
    done
else
    echo -e "\n  ${YELLOW}${BOLD}⚠ NO se encontraron las IPs buscadas en esta cuenta.${NC}"
    echo -e "  ${YELLOW}Esto confirma que el tráfico NO se origina desde los recursos de esta cuenta.${NC}"
    echo -e "  ${YELLOW}Posibles causas:${NC}"
    echo -e "    1. Las IPs pertenecen a otra cuenta AWS no mapeada"
    echo -e "    2. Son IPs efímeras de servicios como Fargate, Lambda sin VPC, o CodeBuild"
    echo -e "    3. El tráfico proviene de fuera de la infraestructura DXC/Procafecol"
fi

echo "" >> "$SUMMARY_FILE"
echo "Total recursos escaneados: $TOTAL_IPS" >> "$SUMMARY_FILE"
echo "Matches encontrados: $MATCH_COUNT" >> "$SUMMARY_FILE"

echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Audit completado. Revisa $REPORT_FILE para el detalle completo.${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
