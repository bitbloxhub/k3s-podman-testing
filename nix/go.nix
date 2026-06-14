{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      make-shells.default = {
        packages = [
          pkgs.go
          pkgs.gopls
          pkgs.gotools
          pkgs.golangci-lint
        ];
      };

      treefmt = {
        programs.golangci-lint.enable = true;
      };
    };
}
