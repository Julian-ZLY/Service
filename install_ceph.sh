#! /bin/bsah 


# 集群主机名
ceph_cluster='ecs-ceph-0004 ecs-ceph-0005 ecs-ceph-0006' 

# 创建工作目录
mkdir ceph-cluster 
cd ceph-cluster 

# 部署ceph集群；安装ceph-deploy工具
yum -y install ceph-deploy 

# 初始化配置文件
ceph-deploy new ${ceph_cluster} 

# 所有ceph节点安装ceph相关软件包
for i in ${ceph_cluster} 
do 
    ssh $i 'yum -y install ceph-mon eph-osd ceph-mds' 
done 

# 添加网段
echo 'public_netword = 192.168.1.0/24' >> ceph.conf 
# 重新推送配置文件
ceph-deploy --overwrite-conf config push ${ceph_cluster}
ceph-deploy mon create-initial 


# 准备磁盘分区
for i in ${ceph_cluster} 
do 
    ssh $i 'parted /dev/vdb mklabel gpt' 
    ssh $i 'parted /dev/vdb mkpart primary 1 50%' 
    ssh $i 'parted /dev/vdb mkpart primary 50% 100%' 
done 

# 修改磁盘权限
for i in ${ceph_cluster}
do 
    ssh $i 'chown ceph:ceph /dev/vdb1'
    ssh $i 'chown ceph:ceph /dev/vdb2'
    ssh $i echo 'ENV{DEVNAME}=="/dev/vdb1",OWNER="ceph",GROUP="ceph"' >> /etc/udev/rules.d/70-vdb.rules
    ssh $i echo 'ENV{DEVNAME}=="/dev/vdb2",OWNER="ceph",GROUP="ceph"' >> /etc/udev/rules.d/70-vdb.rules
done 

for i in ${ceph_cluster} 
do 
    # 初始化磁盘
    ceph-deploy disk zap $i:vdc $i:vdd 
   
    # 初始化OSD集群
    ceph-deploy osd create $i:vdc:/dev/vdb1 $i:vdd:/dev/vdb2 
done 

# 检测ceph集群
echo -m "\033[32m\t检测ceph集群\033[0m"
ceph -s 



# 部署ceph文件系统
ceph-deploy mds create ecs-ceph-0006 
# 创建储存池
ceph osd pool create cephfs_data 128 
ceph osd pool create cephfs_metadata 128 
# 查看存储池
ceph osd lspools 

# 创建文件系统
ceph fs new myfs2 cephfs_metadata cephfs_data 
# 查看文件系统
ceph fs ls 
