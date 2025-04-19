#!/bin/bash
# set -ex

tdnf install -y azurelinux-repos-amd
tdnf repolist --refresh

tdnf -y install kernel-drivers-gpu-$(uname -r)
# Install AMD GPU OOT modules and firmware packages from PMC
tdnf -y install amdgpu-firmware \
                amdgpu \
                amdgpu-headers

# Add Azure Linux 3 ROCM repo file
cat <<EOF >> /etc/yum.repos.d/amd_rocm.repo
[amd_rocm]
name="AMD ROCM packages repo for Azure Linux 3.0"
baseurl=https://repo.radeon.com/.hidden/c5c79c1ea1d0aa6008ddbd29c3ea1523/rocm/azurelinux3/6.2.2.1/main/
enabled=1
repo_gpgcheck=0
gpgcheck=0
sslverify=0
EOF

tdnf repolist --refresh
tdnf install -y rocm-dev rocm-validation-suite rocm-bandwidth-test
tdnf install -y rocm-smi-lib rocm-core rocm-device-libs rocm-llvm rocm-validation-suite
 

#Add self to render and video groups so they can access gpus.
usermod -a -G render $(logname)
usermod -a -G video $(logname)

#add future new users to the render and video groups.
# echo 'ADD_EXTRA_GROUPS=1' | tee -a /etc/adduser.conf
# echo 'EXTRA_GROUPS=video' | tee -a /etc/adduser.conf
# echo 'EXTRA_GROUPS=render' | tee -a /etc/adduser.conf

#add nofile limits
string_so="*               soft    nofile          1048576"
line=$(cat /etc/security/limits.conf | grep "soft    nofile")
cat /etc/security/limits.conf | sed -e "s/$line/$string_so/" > temp_file.txt
mv temp_file.txt /etc/security/limits.conf
string_ha="*               hard    nofile          1048576"
line=$(cat /etc/security/limits.conf | grep "hard    nofile")
cat /etc/security/limits.conf | sed -e "s/$line/$string_ha/" > temp_file.txt
mv temp_file.txt /etc/security/limits.conf

cat /etc/security/limits.conf | grep -v "  stack" > tmplimits.conf
mv tmplimits.conf /etc/security/limits.conf

# echo blacklist amdgpu | tee -a /etc/modprobe.d/blacklist.conf
# update-initramfs -c -k $(uname -r)

echo "Writing gpu mode probe in init.d"
cat <<'EOF' > /tmp/tempinit.sh
#!/bin/sh
at_count=0
while [ $at_count -le 90 ]
do
    if [ $(lspci -d 1002:74b5 | wc -l) -eq 8 -o $(lspci -d 1002:740c | wc -l) -eq 16 ]; then
       echo Required number of GPUs found
       at_count=91
       sleep 120s
       echo doing Modprobe for amdgpu
       sudo modprobe -r hyperv_drm
       sudo modprobe amdgpu ip_block_mask=0x7f
    else
       sleep 10
       at_count=$(($at_count + 1))
    fi
done

exit 0
EOF
cp /tmp/tempinit.sh /etc/init.d/initamdgpu.sh
chmod +x /etc/init.d/initamdgpu.sh
rm /tmp/tempinit.sh

echo "Completed gpu mode probe in init.d"

echo -e '[Unit]\n\nDescription=Runs /etc/init.d/initamdgpu.sh\n\n' \
               | tee rocmstartup.service
echo -e '[Service]\n\nExecStart=/etc/init.d/initamdgpu.sh\n\n' \
               | tee -a rocmstartup.service
echo -e '[Install]\n\nWantedBy=multi-user.target' \
               | tee -a rocmstartup.service

mv rocmstartup.service /etc/systemd/system/rocmstartup.service
systemctl start rocmstartup
systemctl enable rocmstartup

tdnf install -y rocm-bandwidth-test
