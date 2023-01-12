# capacitor API
{lib, ...}:
# user API
{dir ? "plugins"}:
# Plugin API
{context, ...}: {
  plugins =
    builtins.mapAttrs
    (k: v: import v.path context)
    (lib.capacitor.dirToAttrs (
      if builtins.isPath dir
      then dir
      else context.self + "/${dir}"
    ) {});
}
