{lib}: let
  self = lib.capacitor.capacitate.bundlers;
  materialize = lib.capacitor.capacitate.capacitate.materialize;
in {
  bundlersMapper = {
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
    bundlers = materialize self.bundlersMapper (capacitate.composeSelf "bundlers").self;
  };
}
