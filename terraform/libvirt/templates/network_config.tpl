ethernets:
    ${interface}:
        addresses: 
        - ${ip_addr}/24
        dhcp4: false
        gateway4: 192.168.100.1
        match:
	    macaddress:
        nameservers:
            addresses: 
            - 1.1.1.1
            - 8.8.8.8
        set-name: ${interface}
version: 2
