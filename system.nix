{ config, lib, pkgs, ... }:
{
  config = {
    nixpkgs.hostPlatform = "x86_64-linux"; #CPU Architecture

    system-manager.allowAnyDistro = true; #Allow more distro support. Need to test with CentOS

    # Enable and configure services
    services = {
      openssh.enable = true; #Replace distro ssh server with our ssh server
      openssh.settings.PermitRootLogin = "no"; 
    };

    environment = {
      systemPackages = with pkgs; [ #declare our own packages here rather than using official distro package manager
        nftables
        fail2ban
	audit
	aide
      ];

      # Add directories and files to `/etc` and set their permissions
      etc = {
	#Counter doas priv esc CVE
	"sysctl.d/99-hardening.conf".text = ''
	  dev.tty.legacy_tiocsti = 0
	'';

	"nftables.conf" = { #Firewall rules. Edit as needed
	  #NOTE: The following wrapped in double single quotes use the same syntax as you would see for /etc/nftables.conf. No need to convert syntax here
	  #NOTE: THIS CONFIG ONLY ALLOWS SSH BY DEFAULT
	  text = ''
	    #!/usr/sbin/nft -f

	    table inet myfilter
	    delete table inet myfilter
	    comment "reset tables"

	    table inet myfilter {
	      set input_tcp_22 {
		type ipv4_addr
		comment "SSH sources allowed to bypass rate limit"
	      }

	      set input_tcp_8080 {
		type ipv4_addr
		comment "Direct HTTP backend sources"
	      }

	      chain prerouting {
	        type nat hook prerouting priority dstnat; policy accept;
	        iifname != "lo" tcp dport 80 redirect to :8080
		comment "Port forwarding 80 to 8080"
	      }

	      chain input {
	        type filter hook input priority filter; policy drop;

	        ct state established,related counter accept
	        ct state invalid counter drop

		ct status dnat ct original proto-dst 80 counter accept \
		  comment "accept redirected HTTP"

	        iif lo accept
	        iif != lo ip daddr 127.0.0.1/8 counter drop comment "drop connections to lo not coming from lo"
	        iif != lo ip6 daddr ::1/128 counter drop comment "review previous comment"

		#restrict ipv6
	        icmpv6 type {
		  nd-neighbor-solicit,
		  nd-router-advert,
		  destination-unreachable,
		  packet-too-big,
		  time-exceeded,
		  parameter-problem
	        } accept

	        ip protocol icmp icmp type {
		  echo-request,
		  destination-unreachable,
		  time-exceeded,
		  parameter-problem
	        } limit rate 10/second counter accept

		#Whitelisted ssh ips that bypass rate limit
		ip saddr @input_tcp_22 tcp dport 22 ct state new counter accept

		#rate limit for all other connections
	        tcp dport 22 ct state new meter ssh_ratelimit { ip saddr limit rate 4/minute burst 5 packets } \
		  counter accept comment "normal SSH per source"
		tcp dport 22 ct state new log prefix "SSH_FLOOD: " level warn \
		  counter drop comment "SSH rate exceeded per-source"

		#Direct 8080 access from whitelisted IPs
		ip saddr @input_tcp_8080 tcp dport 8080 ct state new counter accept

	        limit rate 5/minute log prefix "NFT_DROP_IN: " level info
	        counter drop comment "dropped inbound packets"
	      }

	      chain forward {
	        type filter hook forward priority filter; policy drop;

	        ct state { established, related } accept
	        ct state invalid drop

	        counter drop
	      }

	      chain output {
	        type filter hook output priority filter; policy accept;

	        tcp dport { 25, 445, 3389, 4444, 5555, 6667 } \
	      	  log prefix "NFT_EGRESS_SUSPECT: " level warn

	        counter accept
	      }
	    }
	  '';

	  replaceExisting = true;
	};
      };
    };

    # Enable and configure systemd services
    systemd.services = { 
      nftables = {
	description = "nftables firewall";
	wantedBy = [ "system-manager.target" ];
	after = [ "network-pre.target" "docker.service" ]; #remove docker.service as needed
	before = [ "network.target" ];
	serviceConfig = {
	  Type = "oneshot";
	  ExecStart = "${pkgs.nftables}/bin/nft -f /etc/nftables.conf";
	  RemainAfterExit = true;
	  NoNewPrivileges = true;
	  PrivateTmp = true;
	  ProtectSystem = "full";
	  ProtectHome = true;
	  CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
	};
	restartTriggers = [ config.environment.etc."nftables.conf".text ];
      };

      sysctl-hardening = { #NOTE: Counters Critical CVE in doas
	description = "Apply sysctl hardening";
	wantedBy = [ "system-manager.target" ];
	after = [ "systemd-sysctl.service" ];
	serviceConfig = {
	  Type = "oneshot";
	  ExecStart = "${pkgs.procps}/bin/sysctl -p /etc/sysctl.d/99-hardening.conf";
	  RemainAfterExit = true;
	};
      };
    };

    # Configure systemd tmpfile settings
    systemd.tmpfiles = {
      # rules = [
      #   "D /var/tmp/system-manager 0755 root root -"
      # ];
      #
      # settings.sample = {
      #   "/var/tmp/sample".d = {
      #     mode = "0755";
      #   };
      # };
    };
  };
}
