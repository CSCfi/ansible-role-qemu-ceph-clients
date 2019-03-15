[![Build Status](https://travis-ci.com/CSCfi/ansible-role-qemu-ceph-clients.svg?branch=master)](https://travis-ci.com/CSCfi/ansible-role-qemu-ceph-clients)

ansible-role-qemu-ceph-clients
=========

Detect qemu process ceph client version staleness

Requirements
------------

None

Role Variables
--------------

See defaults/main.yml

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - { role: ansible-role-qemu-ceph-clients, exclude_qemu_without_rbd: True }

License
-------

MIT

Author Information
------------------

