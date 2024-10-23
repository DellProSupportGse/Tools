	#!/bin/bash
	version="1.0.1_for_ACP01"
	tajmstemp="UTC_"`date -u +"%Y_%m_%d_T_%H_%M"`
	file="manual_log_D_"$tajmstemp"_for_vrm_on_ACP".zip
	folder="manual_log_"$tajmstemp
	 
	if [[ $EUID -ne 0 ]]; then
	  echo "This script must be run as root"
	  exit 1
	fi
	 
	echo #
	echo "Script to perform manual log collection on ACP - Version: "$version
	echo #
	echo "For new versions of this script, check attachments under KB XXXXXXX"
	echo #
	echo "Current disk space"
	echo #
	df -h -t ext4
	echo #

	  echo -e ""
	  mkdir -p /$PWD/$folder/dump
	  echo $version > /$PWD/$folder/script_version.txt
	  pg_dump -U postgres apexcpdb > /$PWD/$folder/dump/db_apexcpdb
	  for sf in rabbitmq microservice_log dblog vami apache-tomcat opt opt/vami ; do mkdir -p /$PWD/$folder/logs/$sf ; done
	  for sf in var_lib_rabbitmq cmd conf/etc/sysconfig/network ; do mkdir -p /$PWD/$folder/$sf ; done
	 
	  mkdir -p /$PWD/$folder/data
	  mkdir -p /$PWD/$folder/cert
	  cp /etc/krb5.conf.d/init1.conf /$PWD/$folder/init1
	  cp /var/lib/apexcp/trust /$PWD/$folder/cert/ -R
	  cp /var/lib/service_data/* /$PWD/$folder/data/ -R
	  cp /var/lib/rancher/rke2/agent/containerd/containerd.log /$PWD/$folder/logs
	  cp /var/lib/rancher/rke2/agent/logs/kubelet.log /$PWD/$folder/logs
	  cp /var/log/* /$PWD/$folder/logs -R
	  cp /var/log/rabbitmq/* /$PWD/$folder/logs/rabbitmq/ -R
	  cp /var/log/microservice_log/* /$PWD/$folder/logs/microservice_log/ -R
	  cp /var/lib/rabbitmq/* /$PWD/$folder/var_lib_rabbitmq/ -R
	  cp /etc/resolv.conf /$PWD/$folder/conf/etc/ -R
	  cp /etc/dnsmasq.conf /$PWD/$folder/conf/etc/ -R
	  cp /etc/ntp.conf /$PWD/$folder/conf/etc/ -R
	  cp /etc/hosts /$PWD/$folder/conf/etc/ -R
	  cp /etc/vmware-marvin /$PWD/$folder/conf/etc/ -R
	  cp /etc/ssh /$PWD/$folder/conf/etc/ -R
	  cp /etc/sysconfig/network/ifcfg-eth* /$PWD/$folder/conf/etc/sysconfig/network/ -R
	  cp /etc/sysconfig/network/routes /$PWD/$folder/conf/etc/sysconfig/network/ -R
	  mkdir /$PWD/$folder/logs/ese
	  cp /home/mystic/ese/rsc/rsc_login.log /$PWD/$folder/logs/ese -R
	  cp /home/mystic/ese/var/config/ESEProperties.json /$PWD/$folder/logs/ese -R
	  cp /home/mystic/ese/var/log/ESE.log /$PWD/$folder/logs/ese -R
	  cp /home/mystic/ese/var/log/ESE_Audit.log /$PWD/$folder/logs/ese -R
	  uname -a > /$PWD/$folder/cmd/uname_-a.txt
	  df -h > /$PWD/$folder/cmd/df_-h.txt
	  ip addr > /$PWD/$folder/cmd/ip_addr.txt
	  ip route > /$PWD/$folder/cmd/ip_route.txt
	  ps aux > /$PWD/$folder/cmd/ps.txt
	  netstat -i > /$PWD/$folder/cmd/netstat_-i.txt
	  netstat -anp > /$PWD/$folder/cmd/netstat.txt
	  free -m > /$PWD/$folder/cmd/free_-m.txt
	  hostname -s > /$PWD/$folder/cmd/hostname_-s.txt
	  hostname -f > /$PWD/$folder/cmd/hostname_-f.txt
	  ifstatus debug all > /$PWD/$folder/cmd/ifstatus_debug_all.txt
	  pam_tally2 --user=root > /$PWD/$folder/cmd/pam_tally2_--user=root.txt
	  pam_tally2 --user=mystic > /$PWD/$folder/cmd/pam_tally2_--user=mystic.txt
	  rpm -qa > /$PWD/$folder/cmd/rpm_-qa.txt
	  top -b -n 1 > /$PWD/$folder/cmd/top_-b_-n_1.txt
	  uptime > /$PWD/$folder/cmd/uptime.txt
	  journalctl -b > /$PWD/$folder/cmd/journalctl_-b.txt
	  iptables -L -n > /$PWD/$folder/cmd/iptables_-L_-n.txt
	  fdisk -lu > /$PWD/$folder/cmd/fdisk_-lu.txt
	  dmesg -H > /$PWD/$folder/cmd/dmesg_-H.txt
	  arp -nv > /$PWD/$folder/cmd/arp_-nv.txt
	  mkdir /$PWD/$folder/var_lib_pgsql_data
	  cp /var/lib/pgsql/data/log/* /$PWD/$folder/logs/dblog
	  gzip /$PWD/$folder/logs/dblog/postgresql.log /$PWD/$folder/logs/dblog/postgresql.log.gz
	  cp /var/lib/pgsql/data/postgresql.conf /$PWD/$folder/var_lib_pgsql_data
	  mkdir -p /$PWD/$folder/home/root
	  cp /home/mystic/.bash_history /$PWD/$folder/home/mystic
	  export HISTTIMEFORMAT='%F %T %Z '
	  HISTFILE=~/.bash_history
	  set -o history
	  history > /$PWD/$folder/home/root/.bash_history
	  mkdir -p /$PWD/$folder/service_status/pods_describe /$PWD/$folder/service_status/pods_logs
	  mkdir /data/store2/container_logs_script
	  # systemctl status vami-sfcb > /$PWD/$folder/service_status/vami-sfcb.txt
	  systemctl status postgresql > /$PWD/$folder/service_status/postgresql.txt
	  systemctl status rabbitmq-server > /$PWD/$folder/service_status/rabbitmq-server.txt
	  systemctl status rke2-server.service > /$PWD/$folder/service_status/rk2-server.service.txt
	  systemctl status docker > /$PWD/$folder/service_status/docker.txt
	  systemctl status sshd > /$PWD/$folder/service_status/sshd.txt
	  systemctl status dnsmasq > /$PWD/$folder/service_status/dnsmasq.txt
	  systemctl status apexcp-ipv6-proxy > /$PWD/$folder/service_status/apexcp-ipv6-proxy.txt
	 
	  kubectl cluster-info dump --output-directory /$PWD/$folder/service_status/kubectl_cluster_info
	  /var/lib/rancher/rke2/bin/crictl --config /var/lib/rancher/rke2/agent/etc/crictl.yaml images > /$PWD/$folder/service_status/k8s_crictl_images.txt
	  /var/lib/rancher/rke2/bin/crictl --config /var/lib/rancher/rke2/agent/etc/crictl.yaml info > /$PWD/$folder/service_status/k8s_crictl_info.txt
	  /var/lib/rancher/rke2/bin/ctr -v > /$PWD/$folder/service_status/k8s_ctr-v.txt
	  /var/lib/rancher/rke2/bin/ctr -v > /$PWD/$folder/service_status/k8s_ctr-v.txt
	  /var/lib/rancher/rke2/bin/crictl --config /var/lib/rancher/rke2/agent/etc/crictl.yaml info > /$PWD/$folder/service_status/k8s_crictl_info.txt
	  /var/lib/rancher/rke2/bin/crictl --config /var/lib/rancher/rke2/agent/etc/crictl.yaml images > /$PWD/$folder/service_status/k8s_crictl_images.txt
	  /var/lib/rancher/rke2/bin/crictl --config /var/lib/rancher/rke2/agent/etc/crictl.yaml ps -a > /$PWD/$folder/service_status/k8s_crictl_ps-a.txt
	  kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n helium get pods > /$PWD/$folder/service_status/kubectl_get_pods.txt
	  kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n helium get deployments > /$PWD/$folder/service_status/kubectl_get_deployments.txt
	  kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n helium get services > /$PWD/$folder/service_status/kubectl_get_services.txt
	 
	  for i in $(kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n helium get pod --no-headers |awk '{print $1}'); do kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n helium describe pod $i > /$PWD/$folder/service_status/pods_describe/$i-describe.txt ; done
	  for i in $(kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n helium get pod --no-headers |awk '{print $1}'); do kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml -n helium logs $i > /$PWD/$folder/service_status/pods_logs/$i-log.txt; done
	 
	  mv /data/store2/container_logs_script/* /$PWD/$folder/service_status/container_logs
	  rm /data/store2/container_logs_script -r
	  zip -r /$PWD/$file /$PWD/$folder/*
	  rm -R /$PWD/$folder/
	fi
