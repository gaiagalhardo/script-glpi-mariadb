#!/bin/bash

# Autor: Renan Galhardo
# Script para facilitar a instalação do GLPI e MariaDB fique a vontade para realizar alterações e melhorias.
# Deixei algumas variáveis, mas podem editar para passar como parâmetro no momento de executar o script.
# É um modelo para facilitar a instalação, verifique a segurança de seu servidor e faça as alterações de acordo com seu ambiente.

# Referências:
# https://verdanadesk.com/como-instalar-glpi-10/

# Definir aqui o nome da pasta
# FOLDER_GLPI será o nome usado para a pasta que conterá o GLPI e o nome do arquivo de configuração do apache em /etc/apache2/conf-availables
FOLDER_GLPI=cti
FOLDER_WEB=/var/www/

# Aqui você pode definir o nome do banco, o usuario e senha do MariaDB 
DATABASE=glpi_cti
USER_DATABASE="glpi"
PASS_DATABASE="1234"
IP=$(hostname -I | cut -f1 -d' ')

# Atualiza lista de pacotes
apt update

# Fuso Horario
# Remove pacotes NTP
apt purge ntp
# Instala pacotes openntpd
apt install -y openntpd
# Parando service openntpd
service openntpd stop
# Configurar TimeZone padrao do servidor
dpkg-reconfigure tzdata
# Adicionar servidor NTP.BR
echo "servers pool.ntp.br" > /etc/openntpd/ntpd.conf
# Habilitar e Iniciar services openntpd
systemctl enable openntpd
systemctl start openntpd

# Pacotes de manipulacao de arquivos
apt install -y ca-certificates apt-transport-https lsb-release xz-utils bzip2 unzip curl wget git jq

# Instalando dependencias no sistema
apt install -y apache2 libapache2-mod-php php-soap php-cas php php-{apcu,cli,common,curl,gd,imap,ldap,mysql,xmlrpc,xml,mbstring,bcmath,intl,zip,redis,bz2}

# Habilitando session.cookie_httponly (verificar a versão do php /etc/php/x/apache2/php.ini e onde está o arquivo do php.ini)
sed -i 's,session.cookie_httponly = *\(on\|off\|true\|false\|0\|1\)\?,session.cookie_httponly = on,gi' /etc/php/8.2/apache2/php.ini
sed -i 's,session.cookie_secure = *\(on\|off\|true\|false\|0\|1\)\?,session.cookie_secure = on,gi' /etc/php/8.2/apache2/php.ini

# Reselvendo problemas de acesso web ao diretorio
# Criar arquivo com conteudo
cat > /etc/apache2/conf-available/${FOLDER_GLPI}.conf << EOF
<VirtualHost *:80>
    DocumentRoot ${FOLDER_WEB}${FOLDER_GLPI}/glpi/public/
    <Directory ${FOLDER_WEB}${FOLDER_GLPI}/glpi/public/>
        AllowOverride All
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
        Options -Indexes
        Options -Includes -ExecCGI
        Require all granted
        <IfModule mod_php7.c>
            php_value max_execution_time 600
            php_value always_populate_raw_post_data -1
        </IfModule>
        <IfModule mod_php8.c>
            php_value max_execution_time 600
            php_value always_populate_raw_post_data -1
        </IfModule>
    </Directory>
</VirtualHost>
EOF
# Habilitar o módulo rewrite do apache
a2enmod rewrite
# Habilita a configuração criada
a2enconf ${FOLDER_GLPI}.conf
# Reinicia o servidor web considerando a nova configuração
systemctl restart apache2

# Criando diretorio onde sera instalado o glpi
mkdir ${FOLDER_WEB}${FOLDER_GLPI}
# Baixando o sistema GLPI
# Link para uma versão específica ==> wget -O- https://github.com/glpi-project/glpi/releases/download/10.0.x/glpi-10.0.x.tgz | tar -zxv -C ${FOLDER_WEB}${FOLDER_GLPI}

# Verificar se já existe o GLPI instalado 
# Importante, se o GLPI não está funcionando, mas a pasta está nesse caminho, você precisa remover para realizar o novo download
if [ -e "${FOLDER_WEB}${FOLDER_GLPI}/glpi/" ]; then
	echo "GLPI já existe"
else
    # Verifica a versão mais atualizada e realiza o download
	VERSION_GLPI=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | grep tag_name | cut -d '"' -f 4)
	SRC_GLPI=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/tags/${VERSION_GLPI} | jq .assets[0].browser_download_url | tr -d \")
	TAR_GLPI=$(basename ${SRC_GLPI})
	
    wget -O- ${SRC_GLPI} | tar -zxv -C ${FOLDER_WEB}${FOLDER_GLPI}

    # Movendo diretórios files e config para fora do GLPi
    mv ${FOLDER_WEB}${FOLDER_GLPI}/glpi/files/ ${FOLDER_WEB}${FOLDER_GLPI}/
    mv ${FOLDER_WEB}${FOLDER_GLPI}/glpi/config/ ${FOLDER_WEB}${FOLDER_GLPI}/

    # Ajustando código do GLPi para o novo local dos diretórios
    sed -i 's/\/config/\/..\/config/g' ${FOLDER_WEB}${FOLDER_GLPI}/glpi/inc/based_config.php
    sed -i 's/\/files/\/..\/files/g' ${FOLDER_WEB}${FOLDER_GLPI}/glpi/inc/based_config.php

    # Ajustar propriedade de arquivos da aplicação GLPi
    chown root:root ${FOLDER_WEB}${FOLDER_GLPI}/glpi/ -Rf
    # Ajustar propriedade de arquivos files, config e marketplace
    chown www-data:www-data ${FOLDER_WEB}${FOLDER_GLPI}/files/ -Rf
    chown www-data:www-data ${FOLDER_WEB}${FOLDER_GLPI}/config/ -Rf
    chown www-data:www-data ${FOLDER_WEB}${FOLDER_GLPI}/glpi/marketplace/ -Rf
    # Ajustar permissões gerais
    find ${FOLDER_WEB}${FOLDER_GLPI}/ -type d -exec chmod 755 {} \;
    find ${FOLDER_WEB}${FOLDER_GLPI}/ -type f -exec chmod 644 {} \;
    find ${FOLDER_WEB}${FOLDER_GLPI}/files -Rf -type f -exec chmod 777 {} \;


    # Criando link simbólico para o sistema GLPi dentro do diretório defalt do apache
    ln -s ${FOLDER_WEB}${FOLDER_GLPI}/glpi /var/www/html/glpi

    echo "Instalação GLPI concluída."

    echo "Instalando MariaDB"

    # Instalando o service MySQL (MariaDB)
    apt install -y mariadb-server

    # criando base de dados
    mysql -e "create database ${DATABASE} character set utf8"
    # criando usuario
    mysql -e "create user '${USER_DATABASE}'@'localhost' identified by '${PASS_DATABASE}'";
    # Definindo privilégios ao usuário
    mysql -e "grant all privileges on ${DATABASE}.* to '${USER_DATABASE}'@'localhost' with grant option";

    # Habilitando suporteao timezone no MariaDB
    mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql mysql
    # Permitindo acesso do usuario ao TimeZone
    mysql -e "GRANT SELECT ON mysql.time_zone_name TO '${USER_DATABASE}'@'localhost';"
    # Forçando aplicação dos privilégios
    mysql -e "FLUSH PRIVILEGES";

    echo "Instalação do MariaDB concluída."

    echo "Criar entrada no agendador de tarefas do Linux - cron"
    echo -e "* *\t* * *\troot\tphp ${FOLDER_WEB}${FOLDER_GLPI}/glpi/front/cron.php" >> /etc/crontab
    # Reiniciando agendador para ler as novas configurações
    systemctl restart cron

    # Instalando REDIS para manter cache dos dados e melhorar o desempenho do sistema.
    apt install -y redis
    # Informando ao glpi para utilizar o redis como armazenador de cache

    php ${FOLDER_WEB}${FOLDER_GLPI}/glpi/bin/console cache:configure --context=core --dsn=redis://127.0.0.1:6379

    echo "Instalação do GLPI e do MariaDB finalizada."

    echo "Acesse o glpi no endereço: http://${IP}/"

fi