import ./make-test-python.nix ({ lib, pkgs, ... }: let

  keyfile = pkgs.writeText "luks-keyfile" ''
    MIGHAoGBAJ4rGTSo/ldyjQypd0kuS7k2OSsmQYzMH6TNj3nQ/vIUjDn7fqa3slt2
    gV6EK3TmTbGc4tzC1v4SWx2m+2Bjdtn4Fs4wiBwn1lbRdC6i5ZYCqasTWIntWn+6
    FllUkMD5oqjOR/YcboxG8Z3B5sJuvTP9llsF+gnuveWih9dpbBr7AgEC
  '';

in {
  name = "systemd-initrd-luks-empty-passphrase";

  nodes.machine = { pkgs, ... }: {
    # Use systemd-boot
    virtualisation = {
      emptyDiskImages = [ 512 ];
      useBootLoader = true;
      useEFIBoot = true;
    };
    boot.loader.systemd-boot.enable = true;

    environment.systemPackages = with pkgs; [ cryptsetup ];
    boot.initrd.systemd = {
      enable = true;
      emergencyAccess = true;
    };

    specialisation.boot-luks.configuration = {
      boot.initrd.luks.devices = lib.mkVMOverride {
        cryptroot = {
          device = "/dev/vdc";
          keyFile = "/etc/cryptroot.key";
          tryEmptyPassphrase = true;
          keyFileTimeout = 5;
        };
      };
      virtualisation.bootDevice = "/dev/mapper/cryptroot";
      boot.initrd.secrets."/etc/cryptroot.key" = keyfile;
    };
  };

  testScript = ''
    # Encrypt key with empty key so boot should try keyfile and then fallback to empty passphrase

    # Create encrypted volume
    machine.wait_for_unit("multi-user.target")
    machine.succeed("echo "" | cryptsetup luksFormat /dev/vdc --batch-mode")

    # Boot from the encrypted disk
    machine.succeed("bootctl set-default nixos-generation-1-specialisation-boot-luks.conf")
    machine.succeed("sync")
    machine.crash()

    # Boot and decrypt the disk
    machine.wait_for_unit("multi-user.target")
    assert "/dev/mapper/cryptroot on / type ext4" in machine.succeed("mount")
  '';
})
