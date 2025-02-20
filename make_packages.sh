#     Copyright 2025. ThingsBoard
#
#     Licensed under the Apache License, Version 2.0 (the "License");
#     you may not use this file except in compliance with the License.
#     You may obtain a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS,
#     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#     See the License for the specific language governing permissions and
#     limitations under the License.

#!/bin/sh
CURRENT_VERSION=$( grep -Po 'VERSION[ ,]=[ ,]\"\K(([0-9])+(\.){0,1})+' thingsboard_gateway/version.py )
if [ "$1" = "clean" ] || [ "$1" = "only_clean" ] ; then
  sudo rm -rf /var/log/thingsboard-gateway/
  sudo rm -rf /var/lib/thingsboard_gateway/
  sudo rm -rf deb_dist/
  sudo rm -rf dist/
  sudo rm -rf thingsboard-gateway.egg-info/
  sudo rm -rf /etc/thingsboard-gateway/
  sudo rm -rf thingsboard-gateway-*.tar.gz
  sudo rm -rf configs.tar.gz
  sudo rm -rf thingsboard-gateway-*.deb
  sudo rm -rf python3-thingsboard-gateway.deb
  sudo rm -rf python3-thingsboard-gateway.rpm
  sudo rm -rf thingsboard-gateway-*.noarch.rpm
  sudo rm -rf thingsboard_gateway.egg-info
  sudo rm -rf thingsboard_gateway/config/backup
  sudo rm -rf build/
  sudo rm -rf docker/config || echo ''
  sudo rm -rf docker/extensions || echo ''
  sudo find thingsboard_gateway/ -name "*.pyc" -exec rm -f {} \;
  sudo apt remove python3-thingsboard-gateway -y
fi

CURRENT_USER=$USER
export PYTHONDONTWRITEBYTECODE=1

if [ "$1" != "only_clean" ] ; then
  echo "Building DEB package"

  # Ensure the 'build' module is installed
  pip install build

  # Create sources for DEB package
  python3 -m build --no-isolation --wheel --outdir .

  WHEEL_FILE=$(ls | grep thingsboard_gateway-*.whl)
  echo $WHEEL_FILE
  # Ensure the thingsboard-gateway.whl exists
  if [ ! -f $WHEEL_FILE ]; then
    echo "Error: $WHEEL_FILE not found."
    exit 1
  fi

  # Create required directories
  mkdir -p deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway
  mkdir -p for_build/var/lib

  mkdir -p deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway/DEBIAN

cat <<EOT > deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway/DEBIAN/control
Package: python3-thingsboard-gateway
Version: $CURRENT_VERSION
Section: python
Priority: optional
Architecture: all
Essential: no
Installed-Size: $(du -ks for_build/var/lib | cut -f1)
Maintainer: ThingsBoard <info@thingsboard.io>
Description: ThingsBoard IoT Gateway
 The ThingsBoard Gateway service for handling MQTT, Modbus, OPC-UA, and other connectors.
Depends: python3, python3-venv
EOT

  # Adding the files, scripts, and permissions
  mkdir -p for_build/var/lib/thingsboard_gateway
  cp -r $WHEEL_FILE for_build/var/lib/thingsboard_gateway/$WHEEL_FILE
  cp -r for_build/etc deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway
  cp -r for_build/var deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway
  cp -r -a for_build/DEBIAN deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway

  # Set correct ownership and permissions
  sudo chown root:root deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway/ -R
  sudo chown root:root deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway/var/ -R
  sudo chmod 775 deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway/DEBIAN/preinst
  sudo chmod +x deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway/DEBIAN/postinst
  sudo chown root:root deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway/DEBIAN/preinst

  # Building Deb package
  dpkg-deb -b deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway/

  mkdir deb-temp
  cd deb-temp
  ar x ../deb_dist/thingsboard-gateway-$CURRENT_VERSION/debian/python3-thingsboard-gateway.deb
  zstd -d *.zst
  rm *.zst
  xz *.tar
  ar r ../python3-thingsboard-gateway.deb debian-binary control.tar.xz data.tar.xz
  cd ..
  rm -r deb-temp
  # Create sources for RPM Package
  echo 'Building RPM package'
  #find thingsboard_gateway/ -name "*.pyc" -exec rm -f {} \;
  python3 setup.py bdist_rpm
  #find thingsboard_gateway/ -name "*.pyc" -exec rm -f {} \;
  cp build/bdist.linux-x86_64/rpm/* /home/$CURRENT_USER/rpmbuild/ -r
  # Adding the file, scripts and permissions
  cp for_build/etc/systemd/system/thingsboard-gateway.service /home/$CURRENT_USER/rpmbuild/SOURCES/
  cp -r thingsboard_gateway/extensions for_build/etc/thingsboard-gateway/
  cd for_build/etc/thingsboard-gateway || echo 0 > /dev/null
  tar -zcvf configs.tar.gz config/*
  tar -zcvf extensions.tar.gz extensions/*
  mv configs.tar.gz ../../../ -f
  cd ../../../
  rm /home/$CURRENT_USER/rpmbuild/SOURCES/configs.tar.gz
  cp configs.tar.gz /home/$CURRENT_USER/rpmbuild/SOURCES/
  # Bulding RPM Package
  cp thingsboard-gateway.spec /home/$CURRENT_USER/rpmbuild/SPECS/
  rpmbuild -ba thingsboard-gateway.spec
  cp /home/$CURRENT_USER/rpmbuild/RPMS/noarch/*.rpm .
  mv thingsboard-gateway-$CURRENT_VERSION-1.noarch.rpm python3-thingsboard-gateway.rpm
  chown $CURRENT_USER. *.rpm
fi
