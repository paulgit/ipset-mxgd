ipset-mxgd
==========

A Bash shell script which uses ipset and iptables to allow connections from MXGuardDog IP addresses published in a DNS TXT record.

The ipset command doesn't work under OpenVZ. It works fine on dedicated and fully virtualized servers like KVM though.

## What's new
- 2019-03-31: Initial public release

## Quick start for Debian/Ubuntu based installations
1. ```wget -O /usr/local/sbin/update-mxgd.sh https://code.paulg.it/paulgit/ipset-mxgd/raw/branch/master/update-mxgd.sh```
2. ```chmod +x /usr/local/sbin/update-mxgd.sh```
3. ```mkdir -p /etc/ipset-mxgd; wget -O /etc/ipset-mxgd/ipset-mxgd.conf https://code.paulg.it/paulgit/ipset-blacklist/raw/branch/master/ipset-mxgd.conf```
4. Modify ```ipset-mxgd.conf`` according to your needs. The default should suffice.
5. ```apt-get install ipset```
6. Create the ipset mxgd and insert it into your iptables input filter (see below). After proper testing, make sure to persist it in your firewall script or similar or the rules will be lost after the next reboot.
7. Auto-update the mxgd ip list using a cron job

## First run, create the list
to generate the ```/etc/ipset-mxgd/ip-mxgd.restore```
```
/usr/local/sbin/update-mxgd.sh /etc/ipset-mxgd/ipset-mxgd.conf
```

## iptables filter rule
```
# Enable mxgd ip list
ipset restore < /etc/ipset-mxgd/ip-mxgd.restore
iptables -I INPUT 1 -m set --match-set mxgd src -j DROP
```
Make sure to run this snippet in a firewall script or just insert it to /etc/rc.local.

## Cron job
In order to auto-update the MXGuardDog IP list, copy the following code into /etc/cron.d/update-mxgd. Don't update the list too often or some blacklist providers will ban your IP address. Once a day should be OK though.
```
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
33 23 * * *      /usr/local/sbin/update-mxgd.sh /etc/ipset-mxgd/ipset-mxgd.conf
```

## Check for dropped packets
Using iptables, you can check how many packets got dropped using the ip list:

```
user@server:~# iptables -L INPUT -v --line-numbers
Chain INPUT (policy DROP 60 packets, 17733 bytes)
num   pkts bytes target            prot opt in  out source   destination
1       15  1349 DROP              all  --  any any anywhere anywhere     match-set mxgd src
```
