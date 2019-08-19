#! /bin/bash 


#########################################################
# 运行环境: 	CentOS Linux 7.x 			#
# 作	者: 	小伙计					# 
# 邮	箱: 	Julian_cn@126.com  			# 
# Github  : 	https://www.github.com/Julian-ZLY	#
#########################################################



NGINX_PATH='/usr/local/nginx'
ZABBIX_CONF_PATH='/usr/local/etc/zabbix_server.conf'


# 操作MySQL数据库函数   
function sql() { 
    mysql -uroot -p123456 -e "$1"
} 

function zabbix_sql() { 
    mysql -uzabbix -p123456 zabbix < "$1"  
} 


# 检测运行环境      
function get_tar_file() {
    
    rpm -q wget || yum -y install wget  

    # 查找本机nginx源码包 
    nginx_tar=`find / -name nginx*.tar.* | awk 'END{print $NF}'`
    if [ -z "${nginx_tar}" ]; then 
        wget https://github.com/Julian-ZLY/Yum_repo/raw/master/nginx-1.12.2.tar.gz -P /opt 
        [  $? -ne 0 ] && echo -e "\033[31m\t下载失败;请检查网络是否通畅...\033[0m`exit 1`"
    fi 
    
    zabbix_tar=`find / -name zabbix*.tar.* | awk 'END{print $NF}'`
    if [ -z "${zabbix_tar}" ]; then
        wget https://github.com/Julian-ZLY/Yum_repo/raw/master/zabbix-3.4.4.tar.gz -P /opt 
        [  $? -ne 0 ] && echo -e "\033[31m\t下载失败;请检查网络是否通畅...\033[0m`exit 1`"
    fi 

}

get_tar_file 



# 部署LNMP环境     
function install_lnmp() {
    
    # LNMP所需要软件包
    packages='gcc pcre-devel openssl-devel mariadb mariadb-server mariadb-devel php php-fpm php-mysql'
    for i in ${packages} 
    do 
        rpm -q $i || yum -y install $i 
    done 
    
    # 安装nginx  
    tar -xvf ${nginx_tar} -C /opt 
    nginx_path=${nginx_tar##*/}
    nginx_path=${nginx_path%.tar*}
    cd /opt/${nginx_path}
    
    ./configure --with-http_ssl_module 
    make && make install 
    
    # 创建快捷方式
    ln -s /usr/local/nginx/sbin/nginx /usr/local/bin/nginx
    

    # 修改配置文件  
    echo '
    
        fastcgi_buffers    8    16k;
        fastcgi_buffer_size     32k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout    300;
        fastcgi_read_timeout    300; 
	' > php.conf 
    # row=$(grep -En 'http {' ${NGINX_PATH}/conf/nginx.conf | awk -F [\:] 'END{print $1}')
    sed -i '/http {/r php.conf' ${NGINX_PATH}/conf/nginx.conf 
    
    # 开启PHP功能
    echo ' 
        location ~ \.php$ {
            root           html;
            fastcgi_pass   127.0.0.1:9000;
            fastcgi_index  index.php;
            include        fastcgi.conf; 
        }' > php.conf  

    row=$(grep -En '*location\ \~\ \\.php\$\ \{' ${NGINX_PATH}/conf/nginx.conf | awk -F [\:] 'END{print $1}') 
    sed -i ''${row}',+7d' ${NGINX_PATH}/conf/nginx.conf 
    sed -i ''${row}'r php.conf' ${NGINX_PATH}/conf/nginx.conf 

    rm -rf php.conf 
} 

install_lnmp 



# 源码安装zabbix     
function install_zabbix() { 

    # zabbix依赖包
    packages='net-snmp-devel curl-devel libevent-devel'
    for i in ${packages}
    do 
        rpm -q $i || yum -y install $i 
    done 

    # 安装zabbix
    tar -xvf ${zabbix_tar} -C /opt 
    zabbix_path=${zabbix_tar##*/}
    zabbix_path=${zabbix_path%.tar*} 
    cd /opt/${zabbix_path}
    
    # 源码编译安装
    ./configure --enable-server --enable-proxy --enable-agent --with-mysql=/usr/bin/mysql_config --with-net-snmp --with-libcurl
    make install 

    # 配置文件;参数列表 
    # LogFile=/tmp/zabbix_server.log
    # DBHost=localhost
    # DBName=zabbix
    # DBUser=zabbix
    # DBPassword='pass'
    sed -i 's/.*DBPassword=.*/DBPassword=123456/' ${ZABBIX_CONF_PATH}
} 

install_zabbix 



# 准备存储数据库使用的库,表,及授权用户 
function prepare_database() { 

    systemctl restart mariadb 
    systemctl enable  mariadb 
    
    # 修改数据库密码
    mysql -e 'set password=password("123456");'
    # 创建数据库,支持中文字符集. 
    sql 'create database zabbix character set utf8;'
    # 授权可以访问数据库的用户 
    sql 'grant all on zabbix.* to zabbix@"localhost" identified by "123456";' 
    # 进入zabbix数据库目录;导入数据
    cd /opt/${zabbix_path}/database/mysql 
    clear 
    echo -e "\033[32m\t数据库导入数据中...\033[0m"
    zabbix_sql  schema.sql 
    zabbix_sql  images.sql 
    zabbix_sql  data.sql 
}

prepare_database 



# 上线zabbix页面    
function on_line_web() { 

    # 进入zabbix PHP动态网页路径拷贝数据
    cd /opt/${zabbix_path}/frontends/php/
    # 拷贝数据 -a 选项;复制属性
    \cp -a * $NGINX_PATH/html/ 
    # 添加最高权限
    chmod -R 777 $NGINX_PATH/html/* 

    # 默认会提示PHP的配置不满足环境要求，需要修改PHP配置文件 
    PHP_CONF='/etc/php.ini'
    # date.timezone = Asia/Shanghai         # 设置时区
    # post_max_size = 16M                   # POST数据最大容量
    # max_execution_time = 300              # 最大执行时间，秒
    # max_input_time = 300                  # 服务器接收数据的时间限制
    # memory_limit = 128M                   # 内存容量限制
    sed -i 's/.*date.timezone =.*/date.timezone = Asia\/Shanghai/' 	${PHP_CONF}
    sed -i 's/.*post_max_size =.*/post_max_size = 16M/'			${PHP_CONF}
    sed -i 's/.*max_execution_time =.*/max_execution_time = 300/' 	${PHP_CONF}
    sed -i 's/.*max_input_time =.*/max_input_time = 300M/'		${PHP_CONF}
    sed -i 's/.*memory_limit =.*/memory_limit = 128M/'			${PHP_CONF}

} 

on_line_web



# 启动服务      
function start_service() {

    yum -y install php-gd php-xml php-ldap php-bcmath php-mbstring 
    
    # 启动zabbix服务 
    useradd zabbix
    zabbix_server

    # 启动nginx服务 
    nginx 

    # 启动php服务
    systemctl restart php-fpm 
    systemctl enable php-fpm 

    # 检测服务
    sleep 1; clear 
    netstat -ntupl 
}

start_service 

