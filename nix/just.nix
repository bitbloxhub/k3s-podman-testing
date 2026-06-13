{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      make-shells.default = {
        packages = [
          pkgs.just
        ];
      };
    };
}
