install_target_host=$1
docker_registry_password=$2
mysql_password=$3
wecube_version=$4

yum install git -y
yum install docker -y
yum install docker-compose -y

systemctl start docker.service
systemctl enable docker.service

docker login -u 100011085647 ccr.ccs.tencentyun.com -p ${docker_registry_password}
sed -i "s~{{SINGLE_HOST}}~$install_target_host~g" wecube.cfg
sed -i "s~{{SINGLE_PASSWORD}}~$mysql_password~g" wecube.cfg
./deploy_generate_compose.sh wecube.cfg ${wecube_version}
docker-compose -f docker-compose.yml up -d