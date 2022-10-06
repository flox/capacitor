{lib}: let
  self = lib.capacitor.capacitate.checks;
  materialize = lib.capacitor.capacitate.capacitate.materialize;
in {
  checksMapper = {
    namespace,
    value,
    system,
    ...
  }: {
    inherit value;
    path = [ system ] ++ namespace;
  };

  plugin = {capacitate, ...}: {
    # TODO: revisit when composition API is clear
    checks = materialize self.checksMapper (capacitate.composeSelf "checks").self;
  };
}
