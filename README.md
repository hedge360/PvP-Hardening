# General Documentation for Purple vs Purple

# In the Competition environment, remove this readme to make it harder for adversaries to make changes to your system.nix

---

## Installation:

This guide will be assuming you are already the root user.
1) Install the Nix Package Manager
    - Run `curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --daemon`
    - Edit `/etc/nix/nix.conf` and add the following line: `experimental-features = nix-command flakes`
2) Install system-manager
    - cd to `/root` and run `nix run 'github:numtide/system-manager' -- init`. Note the space between `--` and `init`
    - You will have 2 files in `/root/.config/system-manager`
        1) flake.nix
        2) system.nix
    - cd into `/root/.config/system-manager`
3) Clone this flake
    - rm everything in the directory
    - `git clone https://github.com/hedge360/PvP-Hardening.git`
    - edit `system.nix` as needed
    - `nix flake update`
    - `nix run 'github:numtide/system-manager' -- switch`
        - NOTE: RUN THIS COMMAND EVERY TIME YOU ADD SOMETHING TO `system.nix`

---

## Usage

system-manager has a special property where programs and config files declared in system.nix are symlinked to the read-only Nix Store. As such, the same files found in /etc will be read-only as well unless someone edits system.nix directly and evaluates changes using `nix run 'github:numtide/system-manager' -- switch`.

Packages declared in environment.systemPackages will use their Nix Store counterparts rather than the packages installed by your distro's package manager (e.g. apt). This allows for the installation of newer packages without vulnerabilities.
