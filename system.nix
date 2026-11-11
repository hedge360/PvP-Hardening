{ config, lib, pkgs, ... }:
{
  config = {
    nixpkgs.hostPlatform = "x86_64-linux";

    # Enable and configure services
    services = {
      openssh.enable = true;
      openssh.settings.PermitRootLogin = "no";
    };

    environment = {
      systemPackages = with pkgs; [
        nftables
        fail2ban
	audit
	aide
      ];

      # Add directories and files to `/etc` and set their permissions
      etc = {
        # with_ownership = {
        #   text = ''
        #     This is just a test!
        #   '';
        #   mode = "0755";
        #   uid = 5;
        #   gid = 6;
        # };
        #
        # with_ownership2 = {
        #   text = ''
        #     This is just a test!
        #   '';
        #   mode = "0755";
        #   user = "nobody";
        #   group = "users";
        # };

	"sysctl.d/99-hardening.conf".text = ''
	  dev.tty.legacy_tiocsti = 0
	'';

	"nftables.conf" = {
	  text = ''
	    #!/usr/sbin/nft -f

	    table inet myfilter
	    delete table inet myfilter

	    table inet myfilter {
	      chain prerouting {
	        type nat hook prerouting priority dstnat; policy accept;
	        iifname != "lo" tcp dport 80 redirect to :8080
	      }

	      chain input {
	        type filter hook input priority filter; policy drop;
	        ct state established,related counter accept
	        ct state invalid counter drop

	        iif lo accept
	        iif != lo ip daddr 127.0.0.1/8 counter drop comment "drop connections to lo not coming from lo"
	        iif != lo ip6 daddr ::1/128 counter drop comment "review previous comment"
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

	        tcp dport 22 ct state new limit rate 4/minute burst 5 packets \
		  counter accept comment "normal SSH"
		tcp dport 22 ct state new log prefix "SSH_FLOOD: " level warn \
		  counter drop comment "SSH rate exceeded"

	        tcp dport { 80, 443 } ct state new counter accept
	        tcp dport 8080 ct state new counter accept

	        limit rate 5/minute log prefix "NFT_DROP_IN: " level info
	        counter drop comment "dropped inbound packets"
	      }

	      chain forward {
	        type filter hook forward priority filter; policy drop;

	        ct state { established, related } accept
	        ct state invalid drop

	        iifname "docker0" accept
		iifname "br-*" accept
	        oifname "docker0" accept
		oifname "br-*" accept

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
	after = [ "network-pre.target" "docker.service" ];
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

      sysctl-hardening = {
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
