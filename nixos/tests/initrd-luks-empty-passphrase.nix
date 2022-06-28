import ./make-test-python.nix ({ lib, pkgs, ... }: let

  keyfile = pkgs.writeText "luks-keyfile" ''
    MIGHAoGBAJ4rGTSo/ldyjQypd0kuS7k2OSsmQYzMH6TNj3nQ/vIUjDn7fqa3slt2
    gV6EK3TmTbGc4tzC1v4SWx2m+2Bjdtn4Fs4wiBwn1lbRdC6i5ZYCqasTWIntWn+6
    FllUkMD5oqjOR/YcboxG8Z3B5sJuvTP9llsF+gnuveWih9dpbBr7AgEC
  '';

in {
  name = "initrd-luks-empty-passphrase";

  nodes.machine = { pkgs, ... }: {
    virtualisation = {
      emptyDiskImages = [ 512 ];
      useBootLoader = true;
    };
    boot.loader.systemd-boot.enable = false;
    boot.loader.grub = {
      enable = true;
      extraConfig = "serial; terminal_output serial";
    };

    environment.systemPackages = with pkgs; [ cryptsetup ];

    specialisation.boot-luks-wrong-keyfile.configuration = {
      boot.initrd.luks.devices = lib.mkVMOverride {
        cryptroot = {
          device = "/dev/vdc";
          keyFile = "/etc/cryptroot.key";
          tryEmptyPassphrase = true;
          fallbackToPassword = true;
        };
      };
      virtualisation.bootDevice = "/dev/mapper/cryptroot";
      boot.initrd.secrets."/etc/cryptroot.key" = keyfile;
    };

    specialisation.boot-luks-missing-keyfile.configuration = {
      boot.initrd.luks.devices = lib.mkVMOverride {
        cryptroot = {
          device = "/dev/vdc";
          keyFile = "/etc/cryptroot.key";
          tryEmptyPassphrase = true;
          fallbackToPassword = true;
        };
      };
      virtualisation.bootDevice = "/dev/mapper/cryptroot";
    };
  };

  testScript = ''
    # Encrypt key with empty key so boot should try keyfile and then fallback to empty passphrase


    def grub_select_boot_luks_wrong_key_file():
        """
        Selects "boot-luks" from the GRUB menu
        to trigger a login request.
        """
        machine.send_monitor_command("sendkey down")
        machine.send_monitor_command("sendkey down")
        machine.send_monitor_command("sendkey ret")

    def grub_select_boot_luks_missing_key_file():
        """
        Selects "boot-luks" from the GRUB menu
        to trigger a login request.
        """
        machine.send_monitor_command("sendkey down")
        machine.send_monitor_command("sendkey ret")

    # Create encrypted volume
    machine.wait_for_unit("multi-user.target")
    machine.succeed("echo "" | cryptsetup luksFormat /dev/vdc --batch-mode")
    machine.crash()

    # Boot and decrypt the disk
    machine.start()

    # Choose boot-luks-wrong-keyfile specialisation
    machine.wait_for_console_text("GNU GRUB")
    grub_select_boot_luks_wrong_key_file()
    machine.send_chars("\n")  # press enter to boot
    machine.wait_for_console_text("Linux version")

    # Check if rootfs is on /dev/mapper/cryptroot
    machine.wait_for_unit("multi-user.target")
    assert "/dev/mapper/cryptroot on / type ext4" in machine.succeed("mount")

    machine.shutdown()

    # Boot and decrypt the disk
    machine.start()

    # Choose boot-luks-missing-keyfile specialisation
    machine.wait_for_console_text("GNU GRUB")
    grub_select_boot_luks_missing_key_file()
    machine.send_chars("\n")  # press enter to boot
    machine.wait_for_console_text("Linux version")

    # Check if rootfs is on /dev/mapper/cryptroot
    machine.wait_for_unit("multi-user.target")
    assert "/dev/mapper/cryptroot on / type ext4" in machine.succeed("mount")
  '';
})
