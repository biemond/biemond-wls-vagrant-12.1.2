# test
#
# one machine setup with weblogic 10.3.6 with BSU
# needs jdk7, orawls, orautils, fiddyspence-sysctl, erwbgy-limits puppet modules
#

node 'admin.example.com' {
  
   include os,java, ssh, orautils 
   include wls1212
   include wls1212_domain
   include wls_application_Cluster
   include wls_application_JMS
   include wls_dynamic_cluster
   include wls_coherence_cluster
   include maintenance
   include packdomain
   
   Class['os']  -> 
     Class['ssh']  -> 
       Class['java']  -> 
         Class['wls1212'] -> 
           Class['wls1212_domain'] -> 
             Class['wls_application_Cluster'] -> 
               Class['wls_application_JMS'] ->
                 Class['wls_dynamic_cluster'] ->
                   Class['wls_coherence_cluster'] ->
                     Class['packdomain']
}  

# operating settings for Middleware
class os {

  notice "class os ${operatingsystem}"

  $default_params = {}
  $host_instances = hiera('hosts', [])
  create_resources('host',$host_instances, $default_params)

  exec { "create swap file":
    command => "/bin/dd if=/dev/zero of=/var/swap.1 bs=1M count=8192",
    creates => "/var/swap.1",
  }

  exec { "attach swap file":
    command => "/sbin/mkswap /var/swap.1 && /sbin/swapon /var/swap.1",
    require => Exec["create swap file"],
    unless => "/sbin/swapon -s | grep /var/swap.1",
  }

  #add swap file entry to fstab
  exec {"add swapfile entry to fstab":
    command => "/bin/echo >>/etc/fstab /var/swap.1 swap swap defaults 0 0",
    require => Exec["attach swap file"],
    user => root,
    unless => "/bin/grep '^/var/swap.1' /etc/fstab 2>/dev/null",
  }

  service { iptables:
        enable    => false,
        ensure    => false,
        hasstatus => true,
  }

  group { 'dba' :
    ensure => present,
  }

  # http://raftaman.net/?p=1311 for generating password
  # password = oracle
  user { 'oracle' :
    ensure     => present,
    groups     => 'dba',
    shell      => '/bin/bash',
    password   => '$1$DSJ51vh6$4XzzwyIOk6Bi/54kglGk3.',
    home       => "/home/oracle",
    comment    => 'oracle user created by Puppet',
    managehome => true,
    require    => Group['dba'],
  }

  $install = [ 'binutils.x86_64','unzip.x86_64']


  package { $install:
    ensure  => present,
  }

  class { 'limits':
    config => {
               '*'       => {  'nofile'  => { soft => '2048'   , hard => '8192',   },},
               'oracle'  => {  'nofile'  => { soft => '65536'  , hard => '65536',  },
                               'nproc'   => { soft => '2048'   , hard => '16384',   },
                               'memlock' => { soft => '1048576', hard => '1048576',},
                               'stack'   => { soft => '10240'  ,},},
               },
    use_hiera => false,
  }

  sysctl { 'kernel.msgmnb':                 ensure => 'present', permanent => 'yes', value => '65536',}
  sysctl { 'kernel.msgmax':                 ensure => 'present', permanent => 'yes', value => '65536',}
  sysctl { 'kernel.shmmax':                 ensure => 'present', permanent => 'yes', value => '2588483584',}
  sysctl { 'kernel.shmall':                 ensure => 'present', permanent => 'yes', value => '2097152',}
  sysctl { 'fs.file-max':                   ensure => 'present', permanent => 'yes', value => '6815744',}
  sysctl { 'net.ipv4.tcp_keepalive_time':   ensure => 'present', permanent => 'yes', value => '1800',}
  sysctl { 'net.ipv4.tcp_keepalive_intvl':  ensure => 'present', permanent => 'yes', value => '30',}
  sysctl { 'net.ipv4.tcp_keepalive_probes': ensure => 'present', permanent => 'yes', value => '5',}
  sysctl { 'net.ipv4.tcp_fin_timeout':      ensure => 'present', permanent => 'yes', value => '30',}
  sysctl { 'kernel.shmmni':                 ensure => 'present', permanent => 'yes', value => '4096', }
  sysctl { 'fs.aio-max-nr':                 ensure => 'present', permanent => 'yes', value => '1048576',}
  sysctl { 'kernel.sem':                    ensure => 'present', permanent => 'yes', value => '250 32000 100 128',}
  sysctl { 'net.ipv4.ip_local_port_range':  ensure => 'present', permanent => 'yes', value => '9000 65500',}
  sysctl { 'net.core.rmem_default':         ensure => 'present', permanent => 'yes', value => '262144',}
  sysctl { 'net.core.rmem_max':             ensure => 'present', permanent => 'yes', value => '4194304', }
  sysctl { 'net.core.wmem_default':         ensure => 'present', permanent => 'yes', value => '262144',}
  sysctl { 'net.core.wmem_max':             ensure => 'present', permanent => 'yes', value => '1048576',}

}

class ssh {
  require os

  notice 'class ssh'

  file { "/home/oracle/.ssh/":
    owner  => "oracle",
    group  => "dba",
    mode   => "700",
    ensure => "directory",
    alias  => "oracle-ssh-dir",
  }
  
  file { "/home/oracle/.ssh/id_rsa.pub":
    ensure  => present,
    owner   => "oracle",
    group   => "dba",
    mode    => "644",
    source  => "/vagrant/ssh/id_rsa.pub",
    require => File["oracle-ssh-dir"],
  }
  
  file { "/home/oracle/.ssh/id_rsa":
    ensure  => present,
    owner   => "oracle",
    group   => "dba",
    mode    => "600",
    source  => "/vagrant/ssh/id_rsa",
    require => File["oracle-ssh-dir"],
  }
  
  file { "/home/oracle/.ssh/authorized_keys":
    ensure  => present,
    owner   => "oracle",
    group   => "dba",
    mode    => "644",
    source  => "/vagrant/ssh/id_rsa.pub",
    require => File["oracle-ssh-dir"],
  }        
}

class java {
  require os

  notice 'class java'

  $remove = [ "java-1.7.0-openjdk.x86_64", "java-1.6.0-openjdk.x86_64" ]

  package { $remove:
    ensure  => absent,
  }

  include jdk7

  jdk7::install7{ 'jdk1.7.0_45':
      version              => "7u45" , 
      fullVersion          => "jdk1.7.0_45",
      alternativesPriority => 18000, 
      x64                  => true,
      downloadDir          => hiera('wls_download_dir'),
      urandomJavaFix       => true,
      sourcePath           => hiera('wls_source'),
  }

}

class wls1212{

   class { 'wls::urandomfix' :}

   $jdkWls12gJDK  = hiera('wls_jdk_version')
   $wls12gVersion = hiera('wls_version')
                       
   $puppetDownloadMntPoint = hiera('wls_source')                       
 
   $osOracleHome = hiera('wls_oracle_base_home_dir')
   $osMdwHome    = hiera('wls_middleware_home_dir')
   $osWlHome     = hiera('wls_weblogic_home_dir')
   $user         = hiera('wls_os_user')
   $group        = hiera('wls_os_group')
   $downloadDir  = hiera('wls_download_dir')
   $logDir       = hiera('wls_log_dir')     

  # set the defaults
  Wls::Installwls {
    version                => $wls12gVersion,
    fullJDKName            => $jdkWls12gJDK,
    oracleHome             => $osOracleHome,
    mdwHome                => $osMdwHome,
    user                   => $user,
    group                  => $group,    
    downloadDir            => $downloadDir,
    remoteFile             => hiera('wls_remote_file'),
    puppetDownloadMntPoint => $puppetDownloadMntPoint,
  }

  # install
  wls::installwls{'wls12.1.2':
     createUser   => false, 
  }

  wls::opatch{'16175470_wls_patch':
    oracleProductHome      => $osMdwHome,
    fullJDKName            => $jdkWls12gJDK,
    patchId                => '16175470',
    patchFile              => 'p16175470_121200_Generic.zip',
    user                   => $user,
    group                  => $group,
    downloadDir            => $downloadDir,
    puppetDownloadMntPoint => $puppetDownloadMntPoint,
    require                => Wls::Installwls['wls12.1.2'],
  }


}

class wls1212_domain{


  $wlsDomainName   = hiera('domain_name')
  $wlsDomainsPath  = hiera('wls_domains_path_dir')
  $osTemplate      = hiera('domain_template')

  $adminListenPort = hiera('domain_adminserver_port')
  $nodemanagerPort = hiera('domain_nodemanager_port')
  $address         = hiera('domain_adminserver_address')

  $userConfigDir   = hiera('wls_user_config_dir')
  $jdkWls12gJDK    = hiera('wls_jdk_version')
  $wls12gVersion   = hiera('wls_version')

                       
  $osOracleHome = hiera('wls_oracle_base_home_dir')
  $osMdwHome    = hiera('wls_middleware_home_dir')
  $osWlHome     = hiera('wls_weblogic_home_dir')
  $user         = hiera('wls_os_user')
  $group        = hiera('wls_os_group')
  $downloadDir  = hiera('wls_download_dir')
  $logDir       = hiera('wls_log_dir')     

  # install wls 12.1.2 domain
  wls::wlsdomain{'Wls1212Domain':
    version         => $wls12gVersion,
    wlHome          => $osWlHome,
    mdwHome         => $osMdwHome,
    fullJDKName     => $jdkWls12gJDK, 
    wlsTemplate     => $osTemplate,
    domain          => $wlsDomainName,
    developmentMode => false,
    adminServerName => hiera('domain_adminserver'),
    adminListenAdr  => $address,
    adminListenPort => $adminListenPort,
    nodemanagerPort => $nodemanagerPort,
    wlsUser         => hiera('wls_weblogic_user'),
    password        => hiera('domain_wls_password'),
    user            => $user,
    group           => $group,    
    logDir          => $logDir,
    downloadDir     => $downloadDir, 
    reposDbUrl      => $reposUrl,
    reposPrefix     => $reposPrefix,
    reposPassword   => $reposPassword,
  }

  #nodemanager starting 
  # in 12c start it after domain creation
  wls::nodemanager{'nodemanager12c':
    version       => $wls12gVersion,
    wlHome        => $osWlHome,
    fullJDKName   => $jdkWls12gJDK,  
    user          => $user,
    group         => $group,
    serviceName   => $serviceName,  
    listenPort    => $nodemanagerPort,
    listenAddress => $address,
    domain        => $wlsDomainName,     
    require       => Wls::Wlsdomain['Wls1212Domain'],
  }  
 
  orautils::nodemanagerautostart{"autostart ${wlsDomainName}":
    version     => $wls12gVersion,
    wlHome      => $osWlHome, 
    user        => $user,
    domain      => $wlsDomainName,
    logDir      => $logDir,
    require     => Wls::Nodemanager['nodemanager12c'];
  }


  # start AdminServers for configuration of WLS Domain
  wls::wlscontrol{'startAdminServer':
    wlsDomain     => $wlsDomainName,
    wlsDomainPath => "${wlsDomainsPath}/${wlsDomainName}",
    wlsServer     => "AdminServer",
    action        => 'start',
    wlHome        => $osWlHome,
    fullJDKName   => $jdkWls12gJDK,  
    wlsUser       => hiera('wls_weblogic_user'),
    password      => hiera('domain_wls_password'),
    address       => $address,
    port          => $nodemanagerPort,
    user          => $user,
    group         => $group,
    downloadDir   => $downloadDir,
    logOutput     => true, 
    require       => Wls::Nodemanager['nodemanager12c'],
  }

  # create keystores for automatic WLST login
  wls::storeuserconfig{
   'Wls1212Domain_keys':
    wlHome        => $osWlHome,
    fullJDKName   => $jdkWls12gJDK,
    domain        => $wlsDomainName, 
    address       => $address,
    wlsUser       => hiera('wls_weblogic_user'),
    password      => hiera('domain_wls_password'),
    port          => $adminListenPort,
    user          => $user,
    group         => $group,
    userConfigDir => $userConfigDir, 
    downloadDir   => $downloadDir, 
    require       => Wls::Wlscontrol['startAdminServer'],
  }

}

class maintenance {

  $osOracleHome = hiera('wls_oracle_base_home_dir')
  $osMdwHome    = hiera('wls_middleware_home_dir')
  $osWlHome     = hiera('wls_weblogic_home_dir')
  $user         = hiera('wls_os_user')
  $group        = hiera('wls_os_group')
  $downloadDir  = hiera('wls_download_dir')
  $logDir       = hiera('wls_log_dir')     

  $mtimeParam = "1"


  cron { 'cleanwlstmp' :
    command => "find /tmp -name '*.tmp' -mtime ${mtimeParam} -exec rm {} \\; >> /tmp/tmp_purge.log 2>&1",
    user    => $user,
    hour    => 06,
    minute  => 25,
  }

  cron { 'mdwlogs' :
    command => "find ${osMdwHome}/logs -name 'wlst_*.*' -mtime ${mtimeParam} -exec rm {} \\; >> /tmp/wlst_purge.log 2>&1",
    user    => $user,
    hour    => 06,
    minute  => 30,
  }

}

class wls_application_Cluster {

  $wlsDomainName   = hiera('domain_name')
  $wlsDomainsPath  = hiera('wls_domains_path_dir')
  $osTemplate      = hiera('domain_template')

  $adminListenPort = hiera('domain_adminserver_port')
  $nodemanagerPort = hiera('domain_nodemanager_port')
  $address         = hiera('domain_adminserver_address')

  $userConfigDir   = hiera('wls_user_config_dir')
  $jdkWls12gJDK    = hiera('wls_jdk_version')
  $wls12gVersion   = hiera('wls_version')
                       
  $osOracleHome = hiera('wls_oracle_base_home_dir')
  $osMdwHome    = hiera('wls_middleware_home_dir')
  $osWlHome     = hiera('wls_weblogic_home_dir')
  $user         = hiera('wls_os_user')
  $group        = hiera('wls_os_group')
  $downloadDir  = hiera('wls_download_dir')
  $logDir       = hiera('wls_log_dir')     
  
  $userConfigFile = "${userConfigDir}/${user}-${wlsDomainName}-WebLogicConfig.properties"
  $userKeyFile    = "${userConfigDir}/${user}-${wlsDomainName}-WebLogicKey.properties"
  
  # default parameters for the wlst scripts
  Wls::Wlstexec {
    version        => $wls12gVersion,
    wlsDomain      => $wlsDomainName,
    wlHome         => $osWlHome,
    fullJDKName    => $jdkWls12gJDK,  
    user           => $user,
    group          => $group,
    address        => $address,
    userConfigFile => $userConfigFile,
    userKeyFile    => $userKeyFile,
    port           => $adminListenPort,
    downloadDir    => $downloadDir,
    logOutput      => false, 
  }


  # create machine
  wls::wlstexec { 
    'createMachineNode1':
     wlstype       => "machine",
     wlsObjectName => "node1",
     script        => 'createMachine.py',
     params        => ["machineName      = 'node1'",
                       "machineDnsName   = '10.10.10.100'",
                      ],
  }

  # create machine
  wls::wlstexec { 
    'createMachineNode2':
     wlstype       => "machine",
     wlsObjectName => "node2",
     script        => 'createMachine.py',
     params        => ["machineName      = 'node2'",
                       "machineDnsName   = '10.10.10.200'",
                      ],
     require        => Wls::Wlstexec['createMachineNode1'],
  }
  
  
    # create managed server 1
    wls::wlstexec { 
      'createManagerServerWlsServer1':
       wlstype       => "server",
       wlsObjectName => "wlsServer1",
       script        => 'createServer.py',
       params        => ["javaArguments    = '-XX:PermSize=256m -XX:MaxPermSize=512m -Xms1024m -Xmx1024m -Dweblogic.Stdout=/data/logs/wlsServer1.out -Dweblogic.Stderr=/data/logs/wlsServer1_err.out'",
                         "wlsServerName    = 'wlsServer1'",
                         "machineName      = 'node1'",
                         "listenPort       = 9201",
                         "listenAddress    = '10.10.10.100'",
                         "nodeMgrLogDir    = '/data/logs'",
                        ],
      require        => Wls::Wlstexec['createMachineNode2'],
    }
  
    # create managed server 2
    wls::wlstexec { 
      'createManagerServerWlsServer2':
       wlstype       => "server",
       wlsObjectName => "wlsServer2",
       script        => 'createServer.py',
       params        => ["javaArguments    = '-XX:PermSize=256m -XX:MaxPermSize=512m -Xms1024m -Xmx1024m -Dweblogic.Stdout=/data/logs/wlsServer2.out -Dweblogic.Stderr=/data/logs/wlsServer2_err.out'",
                         "wlsServerName    = 'wlsServer2'",
                         "machineName      = 'node2'",
                         "listenPort       = 9201",
                         "listenAddress    = '10.10.10.200'",
                         "nodeMgrLogDir    = '/data/logs'",
                        ],
      require        => Wls::Wlstexec['createManagerServerWlsServer1'],
    }
  
    # create cluster
    wls::wlstexec { 
      'createClusterWeb':
       wlstype       => "cluster",
       wlsObjectName => "WebCluster",
       script        => 'createCluster.py',
       params        => ["clusterName      = 'WebCluster'",
                         "clusterNodes     = 'wlsServer1,wlsServer2'",
                        ],
      require        => Wls::Wlstexec['createManagerServerWlsServer2'],
    }



}

class wls_application_JMS{

  $wlsDomainName   = hiera('domain_name')
  $wlsDomainsPath  = hiera('wls_domains_path_dir')
  $osTemplate      = hiera('domain_template')

  $adminListenPort = hiera('domain_adminserver_port')
  $nodemanagerPort = hiera('domain_nodemanager_port')
  $address         = hiera('domain_adminserver_address')

  $jdkWls12gJDK    = hiera('wls_jdk_version')
  $wls12gVersion   = hiera('wls_version')

  $userConfigDir   = hiera('wls_user_config_dir')
                       
  $osOracleHome = hiera('wls_oracle_base_home_dir')
  $osMdwHome    = hiera('wls_middleware_home_dir')
  $osWlHome     = hiera('wls_weblogic_home_dir')
  $user         = hiera('wls_os_user')
  $group        = hiera('wls_os_group')
  $downloadDir  = hiera('wls_download_dir')
  $logDir       = hiera('wls_log_dir')     
  
  $userConfigFile = "${userConfigDir}/${user}-${wlsDomainName}-WebLogicConfig.properties"
  $userKeyFile    = "${userConfigDir}/${user}-${wlsDomainName}-WebLogicKey.properties"

  # default parameters for the wlst scripts
  Wls::Wlstexec {
    version        => $wls12gVersion,
    wlsDomain      => $wlsDomainName,
    wlHome         => $osWlHome,
    fullJDKName    => $jdkWls12gJDK,  
    user           => $user,
    group          => $group,
    address        => $address,
    userConfigFile => $userConfigFile,
    userKeyFile    => $userKeyFile,
    port           => $adminListenPort,
    downloadDir    => $downloadDir,
    logOutput      => true, 
  }
  
  # create jms server for wlsServer1 
  wls::wlstexec { 
    'createJmsServerServer1':
     wlstype       => "jmsserver",
     wlsObjectName => "jmsServer1",
     script        => 'createJmsServer.py',
     params        =>  ["serverTarget   = 'wlsServer1'",
                        "jmsServerName  = 'jmsServer1'",
                        ],
  }
  # create jms server for wlsServer2 
  wls::wlstexec { 
    'createJmsServerServer2':
     wlstype       => "jmsserver",
     wlsObjectName => "jmsServer2",
     script        => 'createJmsServer.py',
     params        =>  ["serverTarget   = 'wlsServer2'",
                        "jmsServerName  = 'jmsServer2'",
                       ],
     require       => Wls::Wlstexec['createJmsServerServer1'];
  }

  # create jms module for WebCluster 
  wls::wlstexec { 
    'createJmsModuleServer':
     wlstype       => "jmsmodule",
     wlsObjectName => "jmsModule",
     script        => 'createJmsModule.py',
     params        =>  ["target         = 'WebCluster'",
                        "jmsModuleName  = 'jmsModule'",
                        "targetType     = 'Cluster'",
                       ],
     require       => Wls::Wlstexec['createJmsServerServer2'];
  }

  # create jms subdeployment for jms module 
  wls::wlstexec { 
    'createJmsSubDeploymentWLSforJmsModule':
     wlstype       => "jmssubdeployment",
     wlsObjectName => "jmsModule/JmsServer",
     script        => 'createJmsSubDeployment.py',
     params        => ["target         = 'jmsServer1,jmsServer2'",
                       "jmsModuleName  = 'jmsModule'",
                       "subName        = 'JmsServer'",
                       "targetType     = 'JMSServer'"
                      ],
     require     => Wls::Wlstexec['createJmsModuleServer'];
  }

  # create jms connection factory for jms module 
  wls::wlstexec { 
    'createJmsConnectionFactoryforJmsModule':
     wlstype       => "jmsobject",
     wlsObjectName => "cf",
     script        => 'createJmsConnectionFactory.py',
     params        => ["jmsModuleName     = 'jmsModule'",
                       "cfName            = 'cf'",
                       "cfJNDIName        = 'jms/cf'",
                       "transacted        = 'false'",
                       "timeout           = 'xxxx'"
                      ],
     require     => Wls::Wlstexec['createJmsSubDeploymentWLSforJmsModule'];
  }

  # create jms error Queue for jms module 
  wls::wlstexec { 
    'createJmsErrorQueueforJmsModule':
     wlstype       => "jmsobject",
     wlsObjectName => "ErrorQueue",
     script        => 'createJmsQueueOrTopic.py',
     params        => ["subDeploymentName = 'JmsServer'",
                       "jmsModuleName     = 'jmsModule'",
                       "jmsName           = 'ErrorQueue'",
                       "jmsJNDIName       = 'jms/ErrorQueue'",
                       "jmsType           = 'queue'",
                       "distributed       = 'true'",
                       "balancingPolicy   = 'Round-Robin'",
                       "useRedirect       = 'false'",
                      ],
     require     => Wls::Wlstexec['createJmsConnectionFactoryforJmsModule'];
  }

  # create jms Queue for jms module 
  wls::wlstexec { 
    'createJmsQueueforJmsModule':
     wlstype       => "jmsobject",
     wlsObjectName => "Queue1",
     script        => 'createJmsQueueOrTopic.py',
     params        => ["subDeploymentName   = 'JmsServer'",
                       "jmsModuleName       = 'jmsModule'",
                       "jmsName             = 'Queue1'",
                       "jmsJNDIName         = 'jms/Queue1'",
                       "jmsType             = 'queue'",
                       "distributed         = 'true'",
                       "balancingPolicy   = 'Round-Robin'",
                       "useRedirect         = 'true'",
                       "limit               = 3",
                       "deliveryDelay       = 2000",
                       "timeToLive          = 300000",
                       "policy              = 'Redirect'",
                       "errorObject         = 'ErrorQueue'"
                      ],
     require     => Wls::Wlstexec['createJmsErrorQueueforJmsModule'];
  }

  # create jms Topic for jms module 
  wls::wlstexec { 
    'createJmsTopicforJmsModule':
     wlstype       => "jmsobject",
     wlsObjectName => "Topic1",
     script        => 'createJmsQueueOrTopic.py',
     params        => ["subDeploymentName   = 'JmsServer'",
                       "jmsModuleName       = 'jmsModule'",
                       "jmsName             = 'Topic1'",
                       "jmsJNDIName         = 'jms/Topic1'",
                       "jmsType             = 'topic'",
                       "distributed         = 'true'",
                       "balancingPolicy     = 'Round-Robin'",
                      ],
     require     => Wls::Wlstexec['createJmsQueueforJmsModule'];
  }

  # create jms Queue for jms module 
  wls::wlstexec { 
    'createJmsQueue2forJmsModule':
     wlstype       => "jmsobject",
     wlsObjectName => "Queue2",
     script        => 'createJmsQueueOrTopic.py',
     params        => ["subDeploymentName   = 'JmsServer'",
                       "jmsModuleName       = 'jmsModule'",
                       "jmsName             = 'Queue2'",
                       "jmsJNDIName         = 'jms/Queue2'",
                       "jmsType             = 'queue'",
                       "distributed         = 'true'",
                       "balancingPolicy     = 'Round-Robin'",
                       "useLogRedirect      = 'true'",
                       "loggingPolicy       = '%header%,%properties%'",
                       "limit               = 3",
                       "deliveryDelay       = 2000",
                       "timeToLive          = 300000",
                      ],
     require     => Wls::Wlstexec['createJmsTopicforJmsModule'];
  }

  # create jms Queue for jms module 
  wls::wlstexec { 
    'createJmsQueue3forJmsModule':
     wlstype       => "jmsobject",
     wlsObjectName => "Queue3",
     script        => 'createJmsQueueOrTopic.py',
     params        => ["subDeploymentName   = 'JmsServer'",
                       "jmsModuleName       = 'jmsModule'",
                       "jmsName             = 'Queue3'",
                       "jmsJNDIName         = 'jms/Queue3'",
                       "jmsType             = 'queue'",
                       "distributed         = 'true'",
                       "balancingPolicy     = 'Round-Robin'",
                       "timeToLive          = 300000",
                      ],
     require     => Wls::Wlstexec['createJmsQueue2forJmsModule'];
  }

}

class wls_dynamic_cluster {

  $wlsDomainName   = hiera('domain_name')
  $wlsDomainsPath  = hiera('wls_domains_path_dir')
  $osTemplate      = hiera('domain_template')

  $adminListenPort = hiera('domain_adminserver_port')
  $nodemanagerPort = hiera('domain_nodemanager_port')
  $address         = hiera('domain_adminserver_address')

  $jdkWls12gJDK    = hiera('wls_jdk_version')
  $wls12gVersion   = hiera('wls_version')

  $userConfigDir   = hiera('wls_user_config_dir')
                       
  $osOracleHome = hiera('wls_oracle_base_home_dir')
  $osMdwHome    = hiera('wls_middleware_home_dir')
  $osWlHome     = hiera('wls_weblogic_home_dir')
  $user         = hiera('wls_os_user')
  $group        = hiera('wls_os_group')
  $downloadDir  = hiera('wls_download_dir')
  $logDir       = hiera('wls_log_dir')     
  
  $userConfigFile = "${userConfigDir}/${user}-${wlsDomainName}-WebLogicConfig.properties"
  $userKeyFile    = "${userConfigDir}/${user}-${wlsDomainName}-WebLogicKey.properties"

  # default parameters for the wlst scripts
  Wls::Wlstexec {
    version        => $wls12gVersion,
    wlsDomain      => $wlsDomainName,
    wlHome         => $osWlHome,
    fullJDKName    => $jdkWls12gJDK,  
    user           => $user,
    group          => $group,
    address        => $address,
    userConfigFile => $userConfigFile,
    userKeyFile    => $userKeyFile,
    port           => $adminListenPort,
    downloadDir    => $downloadDir,
    logOutput      => true, 
  }

  # create Server template for Dynamic Clusters 
  wls::wlstexec { 
    'createServerTemplateCluster':
     wlstype       => "server_templates",
     wlsObjectName => "serverTemplateCluster",
     script        => 'createServerTemplateCluster.py',
     params        =>  ["server_template_name          = 'serverTemplateCluster'",
                        "server_template_listen_port   = 7100",
                        "dynamic_server_name_arguments ='-XX:PermSize=128m -XX:MaxPermSize=256m -Xms512m -Xmx1024m'"],
  }

  # create Dynamic Cluster 
  wls::wlstexec { 
    'createDynamicCluster':
     wlstype       => "cluster",
     wlsObjectName => "dynamicCluster",
     script        => 'createDynamicCluster.py',
     params        =>  ["server_template_name       = 'serverTemplateCluster'",
                        "dynamic_cluster_name       = 'dynamicCluster'",
                        "dynamic_nodemanager_match  = 'node1,node2'",
                        "dynamic_server_name_prefix = 'dynamic_server_'"],
     require       => Wls::Wlstexec['createServerTemplateCluster'];
  }

  # create file persistence store 1 for dynamic cluster 
  wls::wlstexec { 
    'createFilePersistenceStoreDynamicCluster':
     wlstype       => "filestore",
     wlsObjectName => "jmsModuleFilePersistence1",
     script        => 'createFilePersistenceStore2.py',
     params        =>  ["fileStoreName = 'jmsModuleFilePersistence1'",
                        "target          = 'dynamicCluster'",
                        "targetType      = 'Cluster'"],
     require       => Wls::Wlstexec['createDynamicCluster'];
  }

  # create jms server 1 for dynamic cluster 
  wls::wlstexec { 
    'createJmsServerDynamicCluster':
     wlstype       => "jmsserver",
     wlsObjectName => "jmsServer21",
     script      => 'createJmsServer2.py',
     params      =>  ["storeName      = 'jmsModuleFilePersistence1'",
                      "target         = 'dynamicCluster'",
                      "targetType     = 'Cluster'",
                      "jmsServerName  = 'jmsServer21'",
                      "storeType      = 'file'",
                      ],
     require     => Wls::Wlstexec['createFilePersistenceStoreDynamicCluster'];
  }

  # create jms module for dynamic cluster 
  wls::wlstexec { 
    'createJmsModuleCluster':
     wlstype       => "jmsmodule",
     wlsObjectName => "jmsClusterModule",
     script        => 'createJmsModule.py',
     params        =>  ["target         = 'dynamicCluster'",
                        "jmsModuleName  = 'jmsClusterModule'",
                        "targetType     = 'Cluster'",
                       ],
     require       => Wls::Wlstexec['createJmsServerDynamicCluster'];
  }

  # create jms subdeployment for dynamic cluster 
  wls::wlstexec { 
    'createJmsSubDeploymentForCluster':
     wlstype       => "jmssubdeployment",
     wlsObjectName => "jmsClusterModule/dynamicCluster",
     script        => 'createJmsSubDeployment.py',
     params        => ["target         = 'dynamicCluster'",
                       "jmsModuleName  = 'jmsClusterModule'",
                       "subName        = 'dynamicCluster'",
                       "targetType     = 'Cluster'"
                      ],
     require       => Wls::Wlstexec['createJmsModuleCluster'];
  }

  # create jms connection factory for jms module 
  wls::wlstexec { 
  
    'createJmsConnectionFactoryforCluster':
     wlstype       => "jmsobject",
     wlsObjectName => "cf",
     script        => 'createJmsConnectionFactory.py',
     params        =>["subDeploymentName = 'dynamicCluster'",
                      "jmsModuleName     = 'jmsClusterModule'",
                      "cfName            = 'cf'",
                      "cfJNDIName        = 'jms/cf'",
                      "transacted        = 'false'",
                      "timeout           = 'xxxx'"
                      ],
     require       => Wls::Wlstexec['createJmsSubDeploymentForCluster'];
  }

  # create jms error Queue for jms module 
  wls::wlstexec { 
  
    'createJmsErrorQueue2forJmsModule':
     wlstype       => "jmsobject",
     wlsObjectName => "ErrorQueue2",
     script        => 'createJmsQueueOrTopic.py',
     params        =>["subDeploymentName = 'dynamicCluster'",
                      "jmsModuleName     = 'jmsClusterModule'",
                      "jmsName           = 'ErrorQueue2'",
                      "jmsJNDIName       = 'jms/ErrorQueue2'",
                      "jmsType           = 'queue'",
                      "distributed       = 'true'",
                      "balancingPolicy   = 'Round-Robin'",
                      "useRedirect       = 'false'",
                      ],
     require       => Wls::Wlstexec['createJmsConnectionFactoryforCluster'];
  }

  # create jms Queue for jms module 
  wls::wlstexec { 
    'createJmsQueueforDynJmsModule':
     wlstype       => "jmsobject",
     wlsObjectName => "Queue4",
     script        => 'createJmsQueueOrTopic.py',
     params        => ["subDeploymentName  = 'dynamicCluster'",
                      "jmsModuleName       = 'jmsClusterModule'",
                      "jmsName             = 'Queue4'",
                      "jmsJNDIName         = 'jms/Queue4'",
                      "jmsType             = 'queue'",
                      "distributed         = 'true'",
                      "balancingPolicy     = 'Round-Robin'",
                      "useRedirect         = 'true'",
                      "limit               = '3'",
                      "policy              = 'Redirect'",
                      "errorObject         = 'ErrorQueue2'"
                      ],
     require     => Wls::Wlstexec['createJmsErrorQueue2forJmsModule'];
  }


}

class wls_coherence_cluster {

  $wlsDomainName   = hiera('domain_name')
  $wlsDomainsPath  = hiera('wls_domains_path_dir')
  $osTemplate      = hiera('domain_template')

  $adminListenPort = hiera('domain_adminserver_port')
  $nodemanagerPort = hiera('domain_nodemanager_port')
  $address         = hiera('domain_adminserver_address')

  $jdkWls12gJDK    = hiera('wls_jdk_version')
  $wls12gVersion   = hiera('wls_version')

  $userConfigDir   = hiera('wls_user_config_dir')
                       
  $osOracleHome = hiera('wls_oracle_base_home_dir')
  $osMdwHome    = hiera('wls_middleware_home_dir')
  $osWlHome     = hiera('wls_weblogic_home_dir')
  $user         = hiera('wls_os_user')
  $group        = hiera('wls_os_group')
  $downloadDir  = hiera('wls_download_dir')
  $logDir       = hiera('wls_log_dir')     
  
  $userConfigFile = "${userConfigDir}/${user}-${wlsDomainName}-WebLogicConfig.properties"
  $userKeyFile    = "${userConfigDir}/${user}-${wlsDomainName}-WebLogicKey.properties"

  # default parameters for the wlst scripts
  Wls::Wlstexec {
    version        => $wls12gVersion,
    wlsDomain      => $wlsDomainName,
    wlHome         => $osWlHome,
    fullJDKName    => $jdkWls12gJDK,  
    user           => $user,
    group          => $group,
    address        => $address,
    userConfigFile => $userConfigFile,
    userKeyFile    => $userKeyFile,
    port           => $adminListenPort,
    downloadDir    => $downloadDir,
    logOutput      => true, 
  }


  # create Server template for Dynamic Coherence Clusters 
  wls::wlstexec { 
    'createServerTemplateCoherence':
     wlstype       => "server_templates",
     wlsObjectName => "serverTemplateCoherence",
     script        => 'createServerTemplateCluster.py',
     params        =>  ["server_template_name          = 'serverTemplateCoherence'",
                        "server_template_listen_port   = 7200",
                        "dynamic_server_name_arguments ='-XX:PermSize=128m -XX:MaxPermSize=256m -Xms512m -Xmx1024m'"],
  }

  # create Dynamic Coherence Cluster 
  wls::wlstexec { 
    'createDynamicClusterCoherence':
     wlstype       => "cluster",
     wlsObjectName => "dynamicClusterCoherence",
     script        => 'createDynamicCluster.py',
     params        =>  ["server_template_name       = 'serverTemplateCoherence'",
                        "dynamic_cluster_name       = 'dynamicClusterCoherence'",
                        "dynamic_nodemanager_match  = 'node1,node2'",
                        "dynamic_server_name_prefix = 'dynamic_coherence_server_'"],
     require       => Wls::Wlstexec['createServerTemplateCoherence'];
  }

  # create Coherence Cluster 
  wls::wlstexec { 
    'createClusterCoherence':
     wlstype       => "coherence",
     wlsObjectName => "clusterCoherence",
     script        => 'createCoherenceCluster.py',
     params        =>  ["coherence_cluster_name = 'clusterCoherence'",
                        "target                 = 'dynamicClusterCoherence'",
                        "targetType             = 'Cluster'",
                        "storage_enabled        = true",
                        "unicast_address        = '10.10.10.100,10.10.10.200'",
                        "unicast_port           = 8088",
                        "multicast_address      = '231.1.1.1'",
                        "multicast_port         = 33387",
                        "machines               = ['node1','node2']"],
     require       => Wls::Wlstexec['createDynamicClusterCoherence'];
  }


}

class packdomain {

  $wlsDomainName   = hiera('domain_name')
  $jdkWls12gJDK    = hiera('wls_jdk_version')
                       
  $osMdwHome       = hiera('wls_middleware_home_dir')
  $osWlHome        = hiera('wls_weblogic_home_dir')
  $user            = hiera('wls_os_user')
  $group           = hiera('wls_os_group')
  $downloadDir     = hiera('wls_download_dir')

  wls::packdomain{'packWlsDomain':
      wlHome          => $osWlHome,
      mdwHome         => $osMdwHome,
      fullJDKName     => $jdkWls12gJDK,  
      user            => $user,
      group           => $group,    
      downloadDir     => $downloadDir, 
      domain          => $wlsDomainName,
  }
}

