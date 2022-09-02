#!/bin/sh
#TODO.md

if [ "$1" = "-v" ]; then
  ANSIBLE_VERSION="${2}"
fi

yum_makecache_retry() {
  tries=0
  until [ $tries -ge 5 ]
  do
    yum makecache && break
    let tries++
    sleep 1
  done
}

wait_for_cloud_init() {
  while pgrep -f "/usr/bin/python /usr/bin/cloud-init" >/dev/null 2>&1; do
    echo "Waiting for cloud-init to complete"
    sleep 1
  done
}

dpkg_check_lock() {
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    echo "Waiting for dpkg lock release"
    sleep 1
  done
}

apt_install() {
  dpkg_check_lock && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o DPkg::Options::=--force-confold -o DPkg::Options::=--force-confdef "$@"
}

if [ "x$KITCHEN_LOG" = "xDEBUG" ] || [ "x$OMNIBUS_ANSIBLE_LOG" = "xDEBUG" ]; then
  export PS4='(${BASH_SOURCE}:${LINENO}): - [${SHLVL},${BASH_SUBSHELL},$?] $ '
  set -x
fi

if [ ! "$(which ansible-playbook)" ]; then
  if [ -f /etc/centos-release ] || [ -f /etc/redhat-release ] || [ -f /etc/oracle-release ] || [ -f /etc/system-release ]; then

    # Install required Python libs and pip
    # Fix EPEL Metalink SSL error
    # - workaround: https://community.hpcloud.com/article/centos-63-instance-giving-cannot-retrieve-metalink-repository-epel-error
    # - SSL secure solution: Update ca-certs!!
    #   - http://stackoverflow.com/q/26734777/645491#27667111
    #   - http://serverfault.com/q/637549/77156
    #   - http://unix.stackexchange.com/a/163368/7688
    yum -y install ca-certificates nss
    yum clean all
    rm -rf /var/cache/yum
    yum_makecache_retry
    yum -y install epel-release
    # One more time with EPEL to avoid failures
    yum_makecache_retry

    yum -y install python3 python3-devel python3-pip git curl which
    [ "X$?" != X0 ] && yum -y install python-pip PyYAML python-jinja2 python-httplib2 python-keyczar python-paramiko git
    set -x
    cat /etc/system-release-cpe
    set +x
    [ -n "$(grep ':8' /etc/system-release-cpe)" ] && yum -y install python3-pyyaml python3-paramiko python3-PyMySQL python3-cryptography python3-jinja2 rust-toolset
    [ -n "$(grep ':7' /etc/system-release-cpe)" ] && yum -y install python36-PyYAML libselinux-python3
    # Only for testing
    [ -n "$(grep ':7' /etc/system-release-cpe)" ] && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && export PATH=$PATH:$HOME/.cargo/bin
    which rustc
    rustc --version
    export CRYPTOGRAPHY_DONT_BUILD_RUST=1
    # If python-pip install failed and setuptools exists, try that
    if [ -z "$(which pip3)" ] && [ -z "$(which easy_install)" ]; then
      yum -y install python3-setuptools
      easy_install pip
    elif [ -z "$(which pip3)" ] && [ -n "$(which easy_install)" ]; then
      easy_install pip
    fi

    # Install passlib for encrypt
    yum -y groupinstall "Development tools"
    yum -y install sshpass libffi-devel openssl-devel && pip3 install setuptools-rust && pip3 install cryptography==3.3.2 && pip3 install pyrax pysphere boto passlib dnspython

    # Install Ansible module dependencies
    yum -y install bzip2 file findutils git gzip hg svn sudo tar unzip xz zip
    [ -n "$(yum search procps-ng)" ] && yum -y install procps-ng || yum -y install procps

  elif [ -f /etc/debian_version ] || grep -qi ubuntu /etc/lsb-release || grep -qi ubuntu /etc/os-release; then
    wait_for_cloud_init
    dpkg_check_lock && apt-get update -q

    # Install required Python libs and pip
    apt_install python3-pip python3-yaml python3-jinja2 python3-httplib2 python3-netaddr python3-paramiko python3-pkg-resources libffi-dev python3-all-dev python3-mysqldb python3-selinux python3-boto rustc
    [ "X$?" != X0 ] && apt_install python-pip python-yaml python-jinja2 python-httplib2 python-netaddr python-paramiko python-pkg-resources libffi-dev python-all-dev python-mysqldb python-selinux python-boto
    [ -n "$( dpkg_check_lock && apt-cache search python-keyczar )" ] && apt_install python-keyczar
    dpkg_check_lock && apt-cache search ^git$ | grep -q "^git\s" && apt_install git || apt_install git-core

    # If python-pip install failed and setuptools exists, try that
    if [ -z "$(which pip3)" ] && [ -z "$(which pip)" ] && [ -z "$(which easy_install)" ]; then
      apt_install python-setuptools
      easy_install pip
    elif [ -z "$(which pip3)" ] && [ -z "$(which pip)" ] && [ -n "$(which easy_install)" ]; then
      easy_install pip
    fi
    # If python-keyczar apt package does not exist, use pip
    [ -z "$( apt-cache search python-keyczar )" ] && sudo pip3 install python-keyczar || sudo pip install python-keyczar

    # Install passlib for encrypt
    apt_install build-essential
    if [ ! -z "$(which pip3)" ]; then
      apt_install sshpass
      pip3 install cryptography || pip3 install cryptography==3.2.1
      pip3 install pyrax pysphere boto passlib dnspython pyopenssl
    elif [ ! -z "$(which pip)" ]; then
      apt_install sshpass && pip install pyrax pysphere boto passlib dnspython pyopenssl
    fi

    # Install Ansible module dependencies
    apt_install bzip2 file findutils git gzip mercurial procps subversion sudo tar debianutils unzip xz-utils zip

  elif [ -f /etc/SuSE-release ] || grep -i opensuse /etc/os-release; then
    zypper --quiet --non-interactive refresh

    # Install required Python libs and pip
    zypper --quiet --non-interactive install libffi-devel openssl-devel python-devel perl-Error python-xml rpm-python
    zypper --quiet --non-interactive install git || zypper --quiet --non-interactive install git-core

    # If python-pip install failed and setuptools exists, try that
    if [ -z "$(which pip)" ] && [ -z "$(which easy_install)" ]; then
      zypper --quiet --non-interactive install python-setuptools
      easy_install pip
    elif [ -z "$(which pip)" ] && [ -n "$(which easy_install)" ]; then
      easy_install pip
    fi

  elif [ -f /etc/fedora-release ]; then
    # Install required Python libs and pip
    dnf -y install gcc libffi-devel openssl-devel python-devel

    # If python-pip install failed and setuptools exists, try that
    if [ -z "$(which pip)" ] && [ -z "$(which easy_install)" ]; then
      dng -y install python-setuptools
      easy_install pip
    elif [ -z "$(which pip)" ] && [ -n "$(which easy_install)" ]; then
      easy_install pip
    fi

  else
    echo 'WARN: Could not detect distro or distro unsupported'
    echo 'WARN: Trying to install ansible via pip without some dependencies'
    echo 'WARN: Not all functionality of ansible may be available'
  fi

  mkdir -p /etc/ansible/
  printf "%s\n" "[local]" "localhost" > /etc/ansible/hosts
  set -x
  if [ -z "$ANSIBLE_VERSION" -a -n "$(which pip3)" ]; then
    pip3 install -q ansible || pip3 install -q ansible==4.9.0
  elif [ -n "$(which pip3)" ]; then
    pip3 install -q ansible=="$ANSIBLE_VERSION"
  elif [ -z "$ANSIBLE_VERSION" ]; then
    pip install -q six --upgrade
    pip install -q ansible
  else
    pip install -q six --upgrade
    pip install -q ansible=="$ANSIBLE_VERSION"
  fi
  [ -n "$(egrep ':[78]' /etc/system-release-cpe 2>/dev/null)" ] && ln -s /usr/local/bin/ansible /usr/bin/
  [ -n "$(egrep ':[78]' /etc/system-release-cpe 2>/dev/null)" ] && ln -s /usr/local/bin/ansible-playbook /usr/bin/
  which ansible
  ansible --version
  set +x
  if [ -f /etc/centos-release ] || [ -f /etc/redhat-release ] || [ -f /etc/oracle-release ] || [ -f /etc/system-release ]; then
    # Fix for pycrypto pip / yum issue
    # https://github.com/ansible/ansible/issues/276
    if  ansible --version 2>&1  | grep -q "AttributeError: 'module' object has no attribute 'HAVE_DECL_MPZ_POWM_SEC'" ; then
      echo 'WARN: Re-installing python-crypto package to workaround ansible/ansible#276'
      echo 'WARN: https://github.com/ansible/ansible/issues/276'
      pip uninstall -y pycrypto
      yum erase -y python-crypto
      yum install -y python-crypto python-paramiko
    fi
  fi

fi
