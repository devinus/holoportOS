{ config, lib, pkgs, ... }:

let
  hydraProject = "holopkgs";
  hydraJobset = "develop";
  hydraChannel = "holopkgs";
in

{
  nix.binaryCaches = [
    "https://cache.holo.host"
    "https://cache.nixos.org"
  ];

  nix.binaryCachePublicKeys = [
    "cache.holo.host-1:lNXIXtJgS9Iuw4Cu6X0HINLu9sTfcjEntnrgwMQIMcE="
  ];

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  nix.extraOptions = ''
    tarball-ttl = 0
  '';

  nix.nixPath = [ ("nixpkgs=" + <nixpkgs>) ];

  nixpkgs.config.allowUnfree = true;

  services.mingetty.autologinUser = "root";

  systemd.services.holoportos-upgrade = {
    serviceConfig.Type = "oneshot";
    unitConfig.X-StopOnRemoval = false;
    restartIfChanged = false;

    environment = config.nix.envVars // {
      inherit (config.environment.sessionVariables) NIX_PATH;
      HOME = "/root";
    } // config.networking.proxy.envVars;

    path = [
      config.system.build.nixos-generate-config
      config.system.build.nixos-rebuild
      config.nix.package.out
      pkgs.coreutils
      pkgs.gitMinimal
      pkgs.gnutar
      pkgs.gzip
      pkgs.utillinux
      pkgs.xz.bin
    ];

    script = ''
      rm -r /etc/nixos
      mkdir /etc/nixos

      cpus=$(lscpu | grep '^CPU(s):' | tr -s ' ' | cut -d ' ' -f2)

      if [ "$cpus" -lt 8 ]; then
        cat ${./config-upgrade/holoport.nix} > /etc/nixos/configuration.nix
      else
        cat ${./config-upgrade/holoport-plus.nix} > /etc/nixos/configuration.nix
      fi

      nixos-generate-config

      nix-channel --remove holoport
      nix-channel --remove nixos
      nix-channel --remove nixpkgs

      nix-channel --add https://hydra.holo.host/channel/custom/${hydraProject}/${hydraJobset}/${hydraChannel}
      nix-channel --update ${hydraChannel}

      nixos-rebuild switch \
        -I holopkgs=/nix/var/nix/profiles/per-user/root/channels/${hydraChannel} \
        -I nixos=/nix/var/nix/profiles/per-user/root/channels/${hydraChannel}/nixpkgs \
        -I nixos-config=/etc/nixos/configuration.nix \
        -I nixpkgs=/nix/var/nix/profiles/per-user/root/channels/${hydraChannel}/nixpkgs \
        -I nixpkgs-overlays=/nix/var/nix/profiles/per-user/root/channels/${hydraChannel}/overlays
  
      # https://github.com/NixOS/nixpkgs/pull/61321#issuecomment-492423742
      rm -rf /var/lib/systemd/timesync
    '';

    startAt = "*:0/1";
  };
}