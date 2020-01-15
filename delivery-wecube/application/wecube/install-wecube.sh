install_target_host=$1
docker_registry_password=$2
wecube_version=$3
mysql_password=$4

yum install git -y
yum install docker -y
yum install docker-compose -y

systemctl start docker.service
systemctl enable docker.service

#Download packages
docker login -u 100011085647 ccr.ccs.tencentyun.com -p ${docker_registry_password}

#Install Dependencies
docker run -d -p 3307:3306 --name mysql_wecube -e MYSQL_ROOT_PASSWORD=${mysql_password}  docker.io/mysql:latest
docker run -d -p 3308:3306 --name mysql_auth_server -e MYSQL_ROOT_PASSWORD=${mysql_password}  docker.io/mysql:latest
docker run -d -p 9000:9000 --name minio_wecube -e MINIO_ACCESS_KEY=access_key -e MINIO_SECRET_KEY=secret_key -v /data:/data minio/minio server /data

#Config Mysql
sleep 20
docker exec mysql_wecube mysql -u root -h localhost -p${mysql_password} -P 3306 -e 'create database IF NOT EXISTS wecube'
docker exec mysql_wecube mysql -u root -h localhost -p${mysql_password} -P 3306 -e "alter user 'root'@'%' identified with mysql_native_password by '${mysql_password}'"
docker exec mysql_auth_server mysql -u root -h localhost -p${mysql_password} -P 3306 -e 'create database IF NOT EXISTS auth_server'
docker exec mysql_auth_server mysql -u root -h localhost -p${mysql_password} -P 3306 -e "alter user 'root'@'%' identified with mysql_native_password by '${mysql_password}'"

#Load init data
docker exec mysql_wecube mkdir -p /home/wecube
docker cp database mysql_wecube:/home/wecube/database
docker exec mysql_wecube mysql -u root -h localhost -p${mysql_password} -P 3306 -Dwecube -e 'source /home/wecube/database/core_flow_engine_init.sql'
docker exec mysql_wecube mysql -u root -h localhost -p${mysql_password} -P 3306 -Dwecube -e 'source /home/wecube/database/01.wecube.schema.sql'
docker exec mysql_wecube mysql -u root -h localhost -p${mysql_password} -P 3306 -Dwecube -e 'source /home/wecube/database/02.wecube.system.data.sql'

docker exec mysql_auth_server mkdir -p /home/wecube
docker cp database mysql_auth_server:/home/wecube/database
docker exec mysql_auth_server mysql -u root -h localhost -p${mysql_password} -P 3306 -Dauth_server -e 'source /home/wecube/database/auth_init.sql'

#Install Wecube
sed -i "s~{{SINGLE_HOST}}~$install_target_host~g" wecube.cfg
sed -i "s~{{SINGLE_PASSWORD}}~$mysql_password~g" wecube.cfg
./deploy_generate_compose.sh wecube.cfg ${wecube_version}
docker-compose -f docker-compose.yml up -d