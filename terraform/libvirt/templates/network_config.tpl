ethernets:
    ${interface}:
        addresses: 
        - ${ip_addr}/24
        dhcp4: false
        routes:
          - to: default
            via: 192.168.100.1
        nameservers:
            addresses: 
            - 1.1.1.1
            - 8.8.8.8
version: 2
