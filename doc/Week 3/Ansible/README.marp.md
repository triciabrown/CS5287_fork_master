# Primer on Ansible

Video: [https://youtu.be/6jz0adB6I0c](https://youtu.be/6jz0adB6I0c)

Ansible is an open-source automation tool for configuration management, application deployment, and orchestration. It uses an agentless, push-based model over SSH (or WinRM) and YAML “playbooks” to define desired state.

---

## 1. Key Concepts

- **Control Node**  
  The machine where you install and run Ansible (often your laptop or CI server).

- **Managed Nodes**  
  Target servers (Linux, Windows, network devices) configured via SSH/WinRM—no agent required.

- **Inventory**  
  A file (INI or YAML) listing managed hosts and groups:
  ```ini
  [web]
  web1.example.com
  web2.example.com

  [db]
  db1.example.com
  ```

---

## 1. Key Concepts (cont.)

- **Modules**  
  Reusable units of work (package installation, file copy, user management). E.g., `yum`, `apt`, `copy`, `template`.

- **Playbooks**  
  YAML files describing orchestration tasks in plays:
  ```yaml
  - hosts: web
    become: yes
    tasks:
      - name: Install NGINX
        apt:
          name: nginx
          state: present
  ```
--- 

## 1. Key Concepts (cont.)

- **Roles**  
  Structured collection of tasks, handlers, files, templates, defaults, and metadata—promote reuse and organization.

- **Variables**  
  Parameterize behavior via inventory vars, playbook vars, group/host var files, or CLI `-e` arguments.

- **Handlers**  
  Tasks triggered by notifications (e.g., restart a service after a config change):
  ```yaml
  handlers:
    - name: restart nginx
      service:
        name: nginx
        state: restarted
  ```

---

## 2. Architecture & Workflow

1. **Write Inventory** listing target hosts/groups.
2. **Write Playbooks** describing desired state.
3. **Optionally Define Roles** for modular structure.
4. **Run**
   ```bash
   ansible-playbook -i inventory.ini site.yml
   ```
   
--- 

## Ansible Engine

- Connects via SSH to each host.
- Transfers a small Python module (the “Ansible module”) and executes.
- Gathers results, reuses connections, reports success/failure.

---

## 3. Inventory Examples

**INI Syntax**:
```
ini
[app_servers]
app1.example.com ansible_user=ubuntu
app2.example.com ansible_user=ubuntu

[db_servers]
db1.example.com ansible_user=ec2-user
```

---

## 3. Inventory Examples (cont.)

**YAML Syntax**:
```
yaml
all:
  children:
    web:
      hosts:
        web1.example.com:
        web2.example.com:
    db:
      hosts:
        db1.example.com:
```

---

## 4. Playbook Structure
```
yaml
- name: Configure web servers
  hosts: web
  become: yes
  vars:
    pkg_nginx: nginx
  tasks:
    - name: Install NGINX
      apt:
        name: "{{ pkg_nginx }}"
        state: latest

    - name: Deploy config template
      template:
        src: templates/nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      notify: restart nginx

  handlers:
    - name: restart nginx
      service:
        name: nginx
        state: restarted
```
---

## 5. Roles Layout
```

roles/
└── webserver/
    ├── defaults/
    │   └── main.yml
    ├── files/
    ├── handlers/
    │   └── main.yml
    ├── meta/
    │   └── main.yml
    ├── tasks/
    │   └── main.yml
    ├── templates/
    └── vars/
        └── main.yml
```
Use in playbook:
```
yaml
- hosts: web
  roles:
    - role: webserver
```
---

## 6. Common Commands

- **Ping all hosts**  
  `ansible all -i inventory.ini -m ping`

- **Run ad-hoc module**  
  `ansible web -m shell -a "uptime" -i inventory.ini`

- **Syntax check**  
  `ansible-playbook site.yml --syntax-check`

- **Dry run**  
  `ansible-playbook site.yml --check`

- **List tasks in playbook**  
  `ansible-playbook site.yml --list-tasks`

- **View gathered facts**  
  `ansible web -m setup -i inventory.ini`

---

## 7. Best Practices

- Use **version control** for playbooks, inventory, and roles.
- Store **secrets** in Ansible Vault (encrypted YAML).
- Keep **idempotency**: tasks should be safe to run multiple times without adverse effects.
- Structure code with **roles** and **include** statements for clarity.
- Use **handlers** for service restarts on configuration changes.
- Leverage **Ansible Galaxy** for community roles.

---

# Summary

Ansible’s simple, agentless, YAML-driven approach makes it ideal for configuration management, application deployment, and orchestration across heterogeneous environments. By mastering inventory, playbooks, modules, and roles, you can automate complex workflows repeatably and at scale.
