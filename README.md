ipset-whitelist
===============

FORKED from https://github.com/trick77/ipset-blacklist and converted to
a whitelisting script.

A Bash shell script which uses ipset and iptables to allow a large number of IP addresses published in IP whitelists. ipset uses a hashtable to store/fetch IP addresses and thus the IP lookup is a lot (!) faster than thousands of sequentially parsed iptables ban rules.


The ipset command doesn't work under OpenVZ. It works fine on dedicated and fully virtualized servers like KVM though.

## What's new

- 05/10/2018: Added regex filter improvements from [@sbujam](https://github.com/sbujam)
- 08/15/2017: Filtering default gateway and multicast ranges
- 11/30/2017: Forked and converted to whitelist
- 08/15/2017: Filtering default gateway and multicast ranges
- 01/20/2017: Ignoring "Service unavailable" HTTP status code, removed IGNORE_CURL_ERRORS 
- 11/04/2016: Documentation added to show how to prevent fail2ban from inserting its rules above the ipset-whitelist when restarting the fail2ban service
- 11/11/2015: Merged all suggestions from https://github.com/drzraf

## Quick start for Debian/Ubuntu based installations
1. wget -O /usr/local/sbin/update-whitelist.sh
   https://raw.githubusercontent.com/sublocale/ipset-whitelist/master/update-whitelist.sh
2. chmod +x /usr/local/sbin/update-whitelist.sh
3. mkdir -p /etc/ipset-whitelist ; wget -O
   /etc/ipset-whitelist/ipset-whitelist.conf
   https://raw.githubusercontent.com/sublocale/ipset-whitelist/master/ipset-whitelist.conf
4. touch /etc/ipset-whitelist/ip-whitelist-custom.list
5. Modify ipset-whitelist.conf according to your needs. Per default, the whitelisted IP addresses will be saved to /etc/ipset-whitelist/ip-whitelist.restore
6. apt-get install ipset
7. Create the ipset whitelist and insert it into your iptables input filter (see below). After proper testing, make sure to persist it in your firewall script or similar or the rules will be lost after the next reboot.
8. Auto-update the whitelist using a cron job

## iptables filter rule
```
# Enable whitelists
ipset restore < /etc/ipset-whitelist/ip-whitelist.restore
iptables -I INPUT 1 -m set --match-set whitelist src -j ACCEPT
```

Make sure to run this snippet in a firewall script or just insert it to /etc/rc.local.

## Cron job
In order to auto-update the whitelist, copy the following code into /etc/cron.d/update-whitelist. Don't update the list too often or some whitelist providers will ban your IP address. Once a day should be OK though.
```
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
33 23 * * *      root /usr/local/sbin/update-whitelist.sh /etc/ipset-whitelist/ipset-whitelist.conf
```

## Check for accepted packets
Using iptables, you can check how many packets got dropped using the whitelist:

```
drfalken@wopr:~# iptables -L INPUT -v --line-numbers
Chain INPUT (policy ACCEPT 60 packets, 17733 bytes)
num   pkts bytes target            prot opt in  out source   destination
1       15  1349 ACCEPT              all  --  any any anywhere anywhere     match-set whitelist src
2        0     0 fail2ban-vsftpd   tcp  --  any any anywhere anywhere     multiport dports ftp,ftp-data,ftps,ftps-data
3      912 69233 fail2ban-ssh-ddos tcp  --  any any anywhere anywhere     multiport dports ssh
4      912 69233 fail2ban-ssh      tcp  --  any any anywhere anywhere     multiport dports ssh
```

Since iptable rules are parsed sequentally, the ipset-blacklist is most effective if it's the **topmost** rule in iptable's INPUT chain. However, restarting fail2ban usually leads to a situation, where fail2ban inserts its rules above our blacklist drop rule. To prevent this from happening we have to tell fail2ban to insert its rules at the 2nd position. Since the iptables-multiport action is the default ban-action we have to add a file to /etc/fail2ban/action.d:

```
tee << EOF /etc/fail2ban/action.d/iptables-multiport.local
[Definition]
actionstart = <iptables> -N f2b-<name>
              <iptables> -A f2b-<name> -j <returntype>
              <iptables> -I <chain> 2 -p <protocol> -m multiport --dports <port> -j f2b-<name>
EOF
```
(Please keep in in mind this is entirely optional, it just makes dropping blacklisted IP addresses most effective)

## Modify the whitelists you want to use
Edit the whitelist array in /etc/ipset-whitelist/ipset-whitelist.conf to add or remove whitelists, or use it to add your own whitelists.
```
whitelistS=(
"http://www.mysite.me/files/mycustomwhitelist.txt" # Your personal whitelist
)
```
If you for some reason want to ban all IP addresses from a certain country, have
a look at [IPverse.net's](http://ipverse.net/ipblocks/data/countries/)
aggregated IP lists which you can simply add to the whitelists variable. For a ton of spam and malware related whitelists, check out this github repo: https://github.com/firehol/blocklist-ipsets

## Troubleshooting

```Set whitelist-tmp is full, maxelem 65536 reached```   
Increase the ipset list capacity. For instance, if you want to store up to 80,000 entries, add these lines to your ipset-whitelist.conf:  
```
MAXELEM=80000
```

```ipset v6.20.1: Error in line 2: Set cannot be created: set with the same name already exists```   
If this happens after changing the MAXELEM parameter: ipset seems to be unable to recreate an exising list with a different size. You will have to solve this manually by deleting and inserting the whitelist in ipset and iptables. A reboot will help as well and may be easier. You may want to remove /etc/ipset-whitelist/ip-whitelist.restore too because it may still contain the old MAXELEM size.

```ipset v6.12: No command specified: unknown argument -file```
You're using an outdated version of ipset which is not supported.
