# my linux-sysadmin-work
# installing k3s and assigning redhat as leader
## first install and get the token in the redhat node
```sh
sudo cat /var/lib/rancher/k3s/server/node-token
```
## install k3s and configure it to be working node for redhat leader
```yaml
- name: Join Worker Nodes to RedHat Leader
hosts: managed_nodes # This should be your Ubuntu and openSUSE group in 'hosts'
become: true
vars:
leader_ip: "<leader-ip>"
k3s_token: "<k3s-token>"

tasks:
- name: Disable firewalld on openSUSE
ansible.builtin.systemd:
name: firewalld
state: stopped
enabled: no
when: ansible_os_family == "Suse"

- name: Install SELinux dependencies for openSUSE
community.general.zypper:
name:
- container-selinux
- https://rpm.rancher.io/k3s/stable/common/microos/noarch/k3s-selinux-1.6-1.sle.noarch.rpm
state: present
disable_gpg_check: yes
when: ansible_os_family == "Suse"

- name: Check if K3s is already installed
ansible.builtin.command: which k3s
register: k3s_check
failed_when: false
changed_when: false

- name: Run K3s Agent Install Script
ansible.builtin.shell: |
curl -sfL https://get.k3s.io | K3S_URL=https://{{ leader_ip }}:6443 K3S_TOKEN={{ k3s_token }} sh -
when: k3s_check.rc != 0
environment:
# Some systems need the proxy or PATH defined, but usually not needed for K3s
K3S_URL: "https://{{ leader_ip }}:6443"
K3S_TOKEN: "{{ k3s_token }}"

- name: Ensure K3s Agent service is started and enabled
ansible.builtin.systemd:
name: k3s-agent
state: started
enabled: yes
```
# countainarizing and building the images

## flutter build
```sh
flutter build web --release
```
ran on the frontend folder where 'web' live
this will create build/web where the whole frontend is compiled into a highly optimized javascript
## countainarizing
### frontend dockerfile
```
FROM docker.io/library/nginx:alpine
COPY build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```
### backend dockerfile
```
FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000
CMD ["python", "api.py"]
```
### building the images
```sh
podman build -t frontend:v1 .
podman build -t backend:v1 .
```
builds the frontend and backend images with versioning as tags. each run from their perspective folder

# running backend on servers
## load the images from my PC to my servers
save them in tarballs like this:
```sh
podman save localhost/chatbot-backend:v2 -o chatbot-backend-v2.tar
podman save localhost/chatbot-frontend:v2 -o chatbot-frontend-v2.tar
```
## import them in servers
```yaml
- name: Distribute Images to K3s Cluster
  hosts: servers  # This targets RedHat, Ubuntu, and openSUSE
  become: true
  tasks:
    - name: Copy images to nodes
      ansible.builtin.copy:
        src: "{{ item }}"
        dest: "/tmp/{{ item }}"
      loop:
        - chatbot-backend-v2.tar
        - chatbot-frontend-v2.tar

    - name: Import images into K3s containerd
      ansible.builtin.shell: |
        /usr/local/bin/k3s ctr images import /tmp/{{ item }}
      loop:
        - chatbot-backend-v2.tar
        - chatbot-frontend-v2.tar

    - name: Cleanup tar files from /tmp
      ansible.builtin.file:
        path: "/tmp/{{ item }}"
        state: absent
      loop:
        - chatbot-backend-v2.tar
        - chatbot-frontend-v2.tar
```
check if it worked properl:
```sh
sudo k3s ctr images list | grep chatbot
```
## create the deployment
```sh
sudo kubectl create deployment chatbot-backend --image=localhost/chatbot-backend:v3 --port=8000 --replicas=3
```
## change scale 
```sh
sudo kubectl scale deployment chatbot-backend --replicas=3
```
## to check errors during deployments
```sh
sudo kubectl get pods -o wide # show status
sudo kubectl logs chatbot-backend-7d448b68b-xljj7
```
## deploy the front end
```sh
# 1. Create the Frontend Deployment (defaults to 1 replica)



# 2. Scale the Frontend to 3 replicas
sudo kubectl scale deployment chatbot-frontend --replicas=3

# 3. Create the Frontend Service (NodePort) to expose it to your browser
sudo kubectl expose deployment chatbot-frontend --type=NodePort --port=80 --target-port=80 --name=chatbot-frontend-service

# 4. Set the specific NodePort to 30080 (optional, but keeps it consistent with your plan)
sudo kubectl patch svc chatbot-frontend-service -p '{"spec":{"ports":[{"port":80,"nodePort":30080}]}}'
```
### yml version for LoadBalancer
```yaml
# chatbot-frontend-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: chatbot-frontend-service
  namespace: default
spec:
  type: LoadBalancer
  selector:
    app: chatbot-frontend # Ensure this matches your Deployment's labels
  ports:
    - protocol: TCP
      port: 8081          # External Port (Ugly but avoids conflict)
      targetPort: 80      # Container Port
      nodePort: 30080     # Fixed NodePort for consistency
```
```sh
kubectl apply -f service.yaml
```
### yml version for NodePort
```yml
# chatbot-backend-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: chatbot-backend-external
  namespace: default
spec:
  type: NodePort
  selector:
    app: chatbot-backend  # Ensure this matches your Deployment's labels
  ports:
    - protocol: TCP
      port: 5000          # Internal Cluster Port
      targetPort: 5000    # Container Port
      nodePort: 30008     # Port used to access from outside
```
## changing deployment image and
```sh
sudo kubectl set image deployment/chatbot-frontend frontend=localhost/chatbot-frontend:v3
sudo kubectl rollout status deployment/chatbot-frontend #checking rollout status
```
# Monitoring
## Node_Exporter
download:
```sh
wget https://github.com/prometheus/node_exporter/releases/download/v1.11.1/node_exporter-1.11.1.linux-amd64.tar.gz

tar xvfz node_exporter-1.11.1.linux-amd64.tar.gz

./node_exporter 
```
creating a systemd service to start it on boot on /etc/systemd/system/node_exporter.service
```ini
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=<user>
Group=<group>
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target # provides the instruction that tells systemctl enable what to do.
```
starting the new service:
```sh
sudo systemctl daemon-reload #sync with current config on disk
sudo systemctl enable --now node_exporter
sudo systemctl status node_exporter
```
## Prometheus
```sh
wget https://github.com/prometheus/prometheus/releases/download/v3.11.2/prometheus-3.11.2.linux-amd64.tar.gz

tar xvf prometheus-3.11.2.linux-amd64.tar.gz

cd prometheus-3.11.2.linux-amd64
```
writing prometheus.yml config for node_exporter
```yml
global:
  scrape_interval: 15s

scrape_configs:
- job_name: node
  static_configs:
  - targets: ['localhost:9100']
```
run it:
```sh
./prometheus --config.file=./prometheus.yml
```
## Grafana
[install page](https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/#install-from-apt-repository)
start the grafana server with systemd
```sh
sudo systemctl daemon-reload
sudo systemctl start grafana-server
sudo systemctl enable grafana-server.service
```
access at http://localhost:3000/

# found it unnecessary step but might be useful reference

## installing podman for linux and windows servers
```yml
- name: install or check podman installation on Linux servers
hosts: servers
gather_facts: true
become: true

roles:
- { role: podman_install_ubuntu, when: "ansible_facts['distribution'] == 'Ubuntu'" }
- { role: podman_install_suse, when: "ansible_facts['os_family'] == 'Suse'" }
- { role: podman_install_redhat, when: "ansible_facts['os_family'] == 'RedHat'" }

- name: installing podman for windows servers
hosts: windows
gather_facts: true
roles:
- { role: podman_install_windows, when: "ansible_facts['os_family'] == 'Windows'" }
```
### linux
#### ubuntu
```yml
- name: check podman isntallation on Ubuntu
ansible.builtin.command: podman --version
register: podman_check_ubuntu
failed_when: false # prevent marking as failed when command is not found
changed_when: false # prevent reporting change since we are just checking

- name: Report podman status on Ubuntu
ansible.builtin.debug:
msg: "Podman is installed {{podman_check_ubuntu.stdout}}"
when:
- podman_check_ubuntu.rc is defined and podman_check_ubuntu.rc == 0

- name: Installing podman for Ubuntu
ansible.builtin.apt: # handels -y for modules install
name: podman
state: present
update_cache: yes
when:
- ansible_facts['distribution'] == "Ubuntu"
- podman_check_ubuntu.rc is defined and podman_check_ubuntu.rc != 0
```
#### redhat
```yml
- name: check podman isntallation on RedHat
ansible.builtin.command: podman --version
register: podman_check_redhat
failed_when: false # prevent marking as failed when command is not found
changed_when: false # prevent reporting change since we are just checkin

- name: Report podman status on RedHat
ansible.builtin.debug:
msg: "Podman is installed {{podman_check_redhat.stdout}}"
when:
- podman_check_redhat.rc is defined and podman_check_redhat.rc == 0

- name: Installing podman for RedHat
ansible.builtin.dnf: # handels -y for modules install
name: podman
state: present
update_cache: yes
when:
- podman_check_redhat.rc is defined and podman_check_redhat.rc != 0
```
#### opensuse
```yml
- name: check podman isntallation on OpenSUSE
ansible.builtin.command: podman --version
register: podman_check_OpenSUSE
failed_when: false # prevent marking as failed when command is not found
changed_when: false # prevent reporting change since we are just checking

- name: Report podman status on OpenSUSE
ansible.builtin.debug:
msg: "Podman is installed {{podman_check_OpenSUSE.stdout}}"
when:
- podman_check_OpenSUSE.rc is defined and podman_check_OpenSUSE.rc == 0

- name: Installing podman for OpenSUSE
ansible.builtin.zypper: # handels -y for modules install
name: podman
state: present
refresh: yes # refresh is opensuse equivilant for update_cache
when:
- podman_check_OpenSUSE.rc is defined and podman_check_OpenSUSE.rc != 0
```
### windows
```yml
- name: check if podman is installed on Windows
ansible.windows.win_shell: podman --version
register: podman_check_windows
failed_when: false
changed_when: false

- name: Report podman status on Windows
ansible.builtin.debug:
msg: "Podman is installed: {{ podman_check_windows.stdout }}"
when:
- podman_check_windows.rc is defined and podman_check_windows.rc == 0

- name: Install Podman via Chocolatey # This is the standard Windows module for package management
chocolatey.chocolatey.win_chocolatey:
name: podman-cli
state: present
when:
- podman_check_windows.rc is defined and podman_check_windows.rc != 0
```



